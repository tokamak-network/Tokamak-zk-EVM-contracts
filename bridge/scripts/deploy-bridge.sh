#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENV_FILE="${BRIDGE_ENV_FILE:-$PROJECT_ROOT/.env}"
DEPLOY_MODE="${BRIDGE_DEPLOY_MODE:-upgrade}"
FORWARD_ARGS=()

resolve_bridge_path() {
    local input_path="$1"
    if [[ "$input_path" = /* ]]; then
        printf '%s\n' "$input_path"
    else
        (
            cd "$PROJECT_ROOT/bridge"
            python3 - <<'PY' "$input_path"
import os
import sys
print(os.path.abspath(sys.argv[1]))
PY
        )
    fi
}

cleanup_broadcast_traces() {
    local script_name="$1"
    local chain_id="$2"
    local trace_dir="$PROJECT_ROOT/bridge/broadcast/${script_name}/${chain_id}"
    if [[ -d "$trace_dir" ]]; then
        rm -rf "$trace_dir"
    fi
}

latest_complete_bridge_dir() {
    local root_dir="$1"
    local chain_id="$2"
    if [[ ! -d "$root_dir" ]]; then
        return 0
    fi

    find "$root_dir" -mindepth 1 -maxdepth 1 -type d -name '20??????T??????Z' -print \
        | while read -r candidate_dir; do
            if [[ -f "$candidate_dir/bridge.${chain_id}.json" ]]; then
                printf '%s\n' "$candidate_dir"
            fi
        done \
        | LC_ALL=C sort \
        | tail -n 1
}

load_tokamak_cli_entry_context() {
    eval "$(
        node --input-type=module <<'NODE'
import path from "node:path";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const packageRoot = path.dirname(require.resolve("@tokamak-zk-evm/cli/package.json"));
const entryPath = path.join(packageRoot, "dist", "cli.js");

function shellQuote(value) {
  return `'${String(value).replace(/'/g, "'\\''")}'`;
}

console.log(`export TOKAMAK_CLI_PACKAGE_ROOT=${shellQuote(packageRoot)}`);
console.log(`export TOKAMAK_CLI_ENTRY_PATH=${shellQuote(entryPath)}`);
NODE
    )"
}

load_tokamak_runtime_context() {
    eval "$(
        node --input-type=module <<'NODE'
const runtimePaths = await import("@tokamak-private-dapps/common-library/tokamak-runtime-paths");

function shellQuote(value) {
  return `'${String(value).replace(/'/g, "'\\''")}'`;
}

const setupOutputDir = runtimePaths.resolveTokamakCliSetupOutputDir();
console.log(`export TOKAMAK_CLI_PACKAGE_ROOT=${shellQuote(runtimePaths.resolveTokamakCliPackageRoot())}`);
console.log(`export TOKAMAK_CLI_ENTRY_PATH=${shellQuote(runtimePaths.resolveTokamakCliEntryPath())}`);
console.log(`export TOKAMAK_CLI_RUNTIME_ROOT=${shellQuote(runtimePaths.resolveTokamakCliRuntimeRoot())}`);
console.log(`export TOKAMAK_CLI_SETUP_OUTPUT_DIR=${shellQuote(setupOutputDir)}`);
console.log(`export TOKAMAK_SIGMA_VERIFY_PATH=${shellQuote(runtimePaths.resolveTokamakCliSetupArtifactPath("sigma_verify.json"))}`);
console.log(`export SUBCIRCUIT_SETUP_PARAMS_PATH=${shellQuote(runtimePaths.resolveSubcircuitSetupParamsPath())}`);
console.log(`export SUBCIRCUIT_FRONTEND_CFG_PATH=${shellQuote(runtimePaths.resolveSubcircuitFrontendCfgPath())}`);
NODE
    )"
}

run_tokamak_cli_install() {
    node "$TOKAMAK_CLI_ENTRY_PATH" --install
}

refresh_tokamak_verifier_solidity() {
    node --input-type=module - "$PROJECT_ROOT" <<'NODE'
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";

const repoRoot = process.argv[2];
const installedSigmaVerifyJsonPath = process.env.TOKAMAK_SIGMA_VERIFY_PATH;
const setupParamsPath = process.env.SUBCIRCUIT_SETUP_PARAMS_PATH;
const sigmaVerifyJsonPath = path.join(repoRoot, "bridge", "src", "generated", "sigma_verify.json");
const tokamakVerifierGeneratedPath = path.join(repoRoot, "bridge", "src", "generated", "TokamakVerifierKey.generated.sol");
const tokamakVerifierSourcePath = path.join(repoRoot, "bridge", "src", "verifiers", "TokamakVerifier.sol");
const BLS12_381_FQ_MODULUS = BigInt(
  "0x1a0111ea397fe69a4b1ba7b6434bacd7"
  + "64774b84f38512bf6730d2a0f6b0f624"
  + "1eabfffeb153ffffb9feffffffffaaab",
);
const OMEGA_SMAX_INVERSES = new Map([
  [64, "0x199cdaee7b3c79d6566009b5882952d6a41e85011d426b52b891fa3f982b68c5"],
  [128, "0x1996fa8d52f970ba51420be43501370b166fb582ac74db12571ba2fccf28601b"],
  [256, "0x6d64ed25272e58ee91b000235a5bfd4fc03cae032393991be9561c176a2f777a"],
  [512, "0x1907a56e80f82b2df675522e37ad4eca1c510ebfb4543a3efb350dbef02a116e"],
  [1024, "0x2bcd9508a3dad316105f067219141f4450a32c41aa67e0beb0ad80034eb71aa6"],
  [2048, "0x394fda0d65ba213edeae67bc36f376e13cc5bb329aa58ff53dc9e5600f6fb2ac"],
]);
const OMEGA_LFREE_VALUES = new Map([
  [64, "0x0e4840ac57f86f5e293b1d67bc8de5d9a12a70a615d0b8e4d2fc5e69ac5db47f"],
  [128, "0x07d0c802a94a946e8cbe2437f0b4b276501dff643be95635b750da4cab28e208"],
  [512, "0x1bb466679a5d88b1ecfbede342dee7f415c1ad4c687f28a233811ea1fe0c65f4"],
]);
const OMEGA_MI_INVERSES = new Map([
  [2048, "0x394fda0d65ba213edeae67bc36f376e13cc5bb329aa58ff53dc9e5600f6fb2ac"],
  [4096, "0x58c3ba636d174692ad5a534045625d9514180e0e8b24f12309f239f760b82267"],
]);

function assertFile(filePath, label) {
  if (!fs.existsSync(filePath)) {
    throw new Error(`Missing ${label}: ${filePath}`);
  }
}

function normalizeHex(value, label, expectedHexLen) {
  if (typeof value !== "string") {
    throw new Error(`${label} must be a hex string`);
  }
  let hex = value.startsWith("0x") ? value.slice(2) : value;
  hex = hex.toLowerCase();
  if (hex.length > expectedHexLen) {
    throw new Error(`${label} exceeds expected length (${hex.length} > ${expectedHexLen})`);
  }
  return hex.padStart(expectedHexLen, "0");
}

function splitG1(value, label) {
  const hex = normalizeHex(value, label, 96);
  const part1 = hex.slice(0, 32);
  const part2 = hex.slice(32);
  return {
    part1: `0x${part1.padStart(64, "0")}`,
    part2: `0x${part2.padStart(64, "0")}`,
  };
}

function splitG2Coordinate(value, label) {
  const hex = normalizeHex(value, label, 192);
  return {
    c0: splitG1(`0x${hex.slice(0, 96)}`, `${label}.c0`),
    c1: splitG1(`0x${hex.slice(96)}`, `${label}.c1`),
  };
}

function negateFq(value, label) {
  const hex = normalizeHex(value, label, 96);
  const bigint = BigInt(`0x${hex}`);
  if (bigint === 0n) {
    return `0x${hex}`;
  }
  return `0x${(BLS12_381_FQ_MODULUS - bigint).toString(16).padStart(96, "0")}`;
}

function negateG2YCoordinate(value, label) {
  const hex = normalizeHex(value, label, 192);
  const c0 = negateFq(`0x${hex.slice(0, 96)}`, `${label}.c0`);
  const c1 = negateFq(`0x${hex.slice(96)}`, `${label}.c1`);
  return `0x${c0.slice(2)}${c1.slice(2)}`;
}

function readPoint(json, pathLabel, point) {
  if (!point || typeof point !== "object") {
    throw new Error(`${pathLabel} is missing`);
  }
  return {
    x: splitG1(point.x, `${pathLabel}.x`),
    y: splitG1(point.y, `${pathLabel}.y`),
  };
}

function readG2Point(pathLabel, point, { negateY = false } = {}) {
  if (!point || typeof point !== "object") {
    throw new Error(`${pathLabel} is missing`);
  }
  const y = negateY ? negateG2YCoordinate(point.y, `${pathLabel}.y`) : point.y;
  return {
    x: splitG2Coordinate(point.x, `${pathLabel}.x`),
    y: splitG2Coordinate(y, `${pathLabel}.y`),
  };
}

function g2ConstantLines(prefix, point) {
  return [
    `    uint256 internal constant ${prefix}_X0_PART1 = ${point.x.c0.part1};`,
    `    uint256 internal constant ${prefix}_X0_PART2 = ${point.x.c0.part2};`,
    `    uint256 internal constant ${prefix}_X1_PART1 = ${point.x.c1.part1};`,
    `    uint256 internal constant ${prefix}_X1_PART2 = ${point.x.c1.part2};`,
    `    uint256 internal constant ${prefix}_Y0_PART1 = ${point.y.c0.part1};`,
    `    uint256 internal constant ${prefix}_Y0_PART2 = ${point.y.c0.part2};`,
    `    uint256 internal constant ${prefix}_Y1_PART1 = ${point.y.c1.part1};`,
    `    uint256 internal constant ${prefix}_Y1_PART2 = ${point.y.c1.part2};`,
  ];
}

function buildGeneratedSolidity(points) {
  return `// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

/// @dev AUTO-GENERATED FILE. DO NOT EDIT MANUALLY.
/// Source: bridge/src/generated/sigma_verify.json
library TokamakVerifierKeyGenerated {
    uint256 internal constant LAGRANGE_KL_X_PART1 = ${points.lagrange.x.part1};
    uint256 internal constant LAGRANGE_KL_X_PART2 = ${points.lagrange.x.part2};
    uint256 internal constant LAGRANGE_KL_Y_PART1 = ${points.lagrange.y.part1};
    uint256 internal constant LAGRANGE_KL_Y_PART2 = ${points.lagrange.y.part2};

    uint256 internal constant IDENTITY_X_PART1 = ${points.identity.x.part1};
    uint256 internal constant IDENTITY_X_PART2 = ${points.identity.x.part2};
    uint256 internal constant IDENTITY_Y_PART1 = ${points.identity.y.part1};
    uint256 internal constant IDENTITY_Y_PART2 = ${points.identity.y.part2};

    uint256 internal constant SIGMA_X_X_PART1 = ${points.sigmaX.x.part1};
    uint256 internal constant SIGMA_X_X_PART2 = ${points.sigmaX.x.part2};
    uint256 internal constant SIGMA_X_Y_PART1 = ${points.sigmaX.y.part1};
    uint256 internal constant SIGMA_X_Y_PART2 = ${points.sigmaX.y.part2};

    uint256 internal constant SIGMA_Y_X_PART1 = ${points.sigmaY.x.part1};
    uint256 internal constant SIGMA_Y_X_PART2 = ${points.sigmaY.x.part2};
    uint256 internal constant SIGMA_Y_Y_PART1 = ${points.sigmaY.y.part1};
    uint256 internal constant SIGMA_Y_Y_PART2 = ${points.sigmaY.y.part2};

${g2ConstantLines("IDENTITY2", points.identity2).join("\n")}

${g2ConstantLines("ALPHA", points.alpha).join("\n")}

${g2ConstantLines("ALPHA_POWER2", points.alpha2).join("\n")}

${g2ConstantLines("ALPHA_POWER3", points.alpha3).join("\n")}

${g2ConstantLines("ALPHA_POWER4", points.alpha4).join("\n")}

${g2ConstantLines("GAMMA", points.gamma).join("\n")}

${g2ConstantLines("DELTA", points.delta).join("\n")}

${g2ConstantLines("ETA", points.eta).join("\n")}

${g2ConstantLines("X", points.x).join("\n")}

${g2ConstantLines("Y", points.y).join("\n")}
}
`;
}

function rewriteVerifierG2Constants(source, points) {
  let output = source;
  for (const [prefix, point] of Object.entries({
    IDENTITY2: points.identity2,
    ALPHA: points.alpha,
    ALPHA_POWER2: points.alpha2,
    ALPHA_POWER3: points.alpha3,
    ALPHA_POWER4: points.alpha4,
    GAMMA: points.gamma,
    DELTA: points.delta,
    ETA: points.eta,
    X: points.x,
    Y: points.y,
  })) {
    for (const line of g2ConstantLines(prefix, point)) {
      const [, name, value] = line.match(/constant ([A-Z0-9_]+) = (0x[0-9a-f]+);/) ?? [];
      if (!name || !value) {
        throw new Error(`Failed to parse generated constant line: ${line}`);
      }
      const pattern = new RegExp(`uint256 internal constant ${name} = 0x[0-9a-f]+;`);
      if (!pattern.test(output)) {
        throw new Error(`TokamakVerifier.sol is missing expected G2 constant ${name}`);
      }
      output = output.replace(pattern, `uint256 internal constant ${name} = ${value};`);
    }
  }
  return output;
}

function refreshTokamakVerifierKey() {
  const json = JSON.parse(fs.readFileSync(sigmaVerifyJsonPath, "utf8"));
  const points = {
    lagrange: readPoint(json, "lagrange_KL", json.lagrange_KL),
    identity: readPoint(json, "G", json.G),
    sigmaX: readPoint(json, "sigma_1.x", json.sigma_1?.x),
    sigmaY: readPoint(json, "sigma_1.y", json.sigma_1?.y),
    identity2: readG2Point("H", json.H),
    alpha: readG2Point("sigma_2.alpha", json.sigma_2?.alpha),
    alpha2: readG2Point("sigma_2.alpha2", json.sigma_2?.alpha2),
    alpha3: readG2Point("sigma_2.alpha3", json.sigma_2?.alpha3),
    alpha4: readG2Point("sigma_2.alpha4", json.sigma_2?.alpha4),
    gamma: readG2Point("sigma_2.gamma", json.sigma_2?.gamma, { negateY: true }),
    delta: readG2Point("sigma_2.delta", json.sigma_2?.delta, { negateY: true }),
    eta: readG2Point("sigma_2.eta", json.sigma_2?.eta, { negateY: true }),
    x: readG2Point("sigma_2.x", json.sigma_2?.x, { negateY: true }),
    y: readG2Point("sigma_2.y", json.sigma_2?.y, { negateY: true }),
  };
  fs.writeFileSync(tokamakVerifierGeneratedPath, buildGeneratedSolidity(points));
  const verifierSource = fs.readFileSync(tokamakVerifierSourcePath, "utf8");
  fs.writeFileSync(tokamakVerifierSourcePath, rewriteVerifierG2Constants(verifierSource, points));
  console.log(`Generated ${path.relative(process.cwd(), tokamakVerifierGeneratedPath)} from ${path.relative(process.cwd(), sigmaVerifyJsonPath)}`);
  console.log(`Updated ${path.relative(process.cwd(), tokamakVerifierSourcePath)} G2 constants from ${path.relative(process.cwd(), sigmaVerifyJsonPath)}`);
}

function rewriteVerifierSetupParams(source, setupParams) {
  const lUserPattern = /uint256 internal constant EXPECTED_L_USER = \d+;/;
  const lFreePattern = /uint256 internal constant EXPECTED_L_FREE = \d+;/;
  const omegaLFreePattern = /uint256 internal constant OMEGA_L_FREE = 0x[0-9a-f]+;/;
  const nPattern = /uint256 internal constant CONSTANT_N = \d+;/;
  const miPattern = /uint256 internal constant CONSTANT_MI = \d+;/;
  const omegaMiPattern = /uint256 internal constant OMEGA_MI_1 = 0x[0-9a-f]+;/;
  const smaxPattern = /uint256 internal constant EXPECTED_SMAX = \d+;/;
  const omegaPattern = /uint256 internal constant OMEGA_SMAX_MINUS_1 =\s*\n\s*0x[0-9a-f]+;/;
  const denominatorSlotPattern = /uint256 internal constant COMPUTE_APUB_DENOMINATOR_BUFFER_SLOT = 0x[0-9a-f]+;/;
  const prefixSlotPattern = /uint256 internal constant COMPUTE_APUB_PREFIX_BUFFER_SLOT = 0x[0-9a-f]+;/;
  const step4CgSlotPattern = /uint256 internal constant STEP4_COEFF_C_G_SLOT = 0x[0-9a-f]+;/;
  const step4CfSlotPattern = /uint256 internal constant STEP4_COEFF_C_F_SLOT = 0x[0-9a-f]+;/;
  const step4CbSlotPattern = /uint256 internal constant STEP4_COEFF_C_B_SLOT = 0x[0-9a-f]+;/;
  const patterns = [
    lUserPattern, lFreePattern, omegaLFreePattern, nPattern, miPattern, omegaMiPattern,
    smaxPattern, omegaPattern, denominatorSlotPattern, prefixSlotPattern, step4CgSlotPattern,
    step4CfSlotPattern, step4CbSlotPattern,
  ];
  if (!patterns.every((pattern) => pattern.test(source))) {
    throw new Error("Failed to update TokamakVerifier.sol setup constants. Expected replacement markers were not found.");
  }

  const expectedLUser = Number(setupParams.l_user);
  const expectedLFree = Number(setupParams.l_free);
  const expectedN = Number(setupParams.n);
  const expectedMi = Number(setupParams.l_D) - Number(setupParams.l);
  const expectedSmax = Number(setupParams.s_max);
  for (const [label, value] of Object.entries({
    l_user: expectedLUser,
    l_free: expectedLFree,
    n: expectedN,
    "l_D - l": expectedMi,
    s_max: expectedSmax,
  })) {
    if (!Number.isInteger(value) || value <= 0) {
      throw new Error(`setupParams.json ${label} must be a positive integer. Received: ${value}`);
    }
  }
  const omegaLFree = OMEGA_LFREE_VALUES.get(expectedLFree);
  const omegaMiInverse = OMEGA_MI_INVERSES.get(expectedMi);
  const omegaInverse = OMEGA_SMAX_INVERSES.get(expectedSmax);
  if (!omegaLFree || !omegaMiInverse || !omegaInverse) {
    throw new Error(`Unsupported setup params: l_free=${expectedLFree}, m_i=${expectedMi}, s_max=${expectedSmax}.`);
  }

  const bufferBytes = expectedLFree * 0x20;
  const denominatorSlot = 0x10000 + bufferBytes;
  const prefixSlot = denominatorSlot + bufferBytes;
  const step4CgSlot = prefixSlot + bufferBytes;
  const step4CfSlot = step4CgSlot + 0x20;
  const step4CbSlot = step4CgSlot + 0x40;
  return source
    .replace(lUserPattern, `uint256 internal constant EXPECTED_L_USER = ${expectedLUser};`)
    .replace(lFreePattern, `uint256 internal constant EXPECTED_L_FREE = ${expectedLFree};`)
    .replace(omegaLFreePattern, `uint256 internal constant OMEGA_L_FREE = ${omegaLFree};`)
    .replace(nPattern, `uint256 internal constant CONSTANT_N = ${expectedN};`)
    .replace(miPattern, `uint256 internal constant CONSTANT_MI = ${expectedMi};`)
    .replace(omegaMiPattern, `uint256 internal constant OMEGA_MI_1 = ${omegaMiInverse};`)
    .replace(denominatorSlotPattern, `uint256 internal constant COMPUTE_APUB_DENOMINATOR_BUFFER_SLOT = 0x${denominatorSlot.toString(16)};`)
    .replace(prefixSlotPattern, `uint256 internal constant COMPUTE_APUB_PREFIX_BUFFER_SLOT = 0x${prefixSlot.toString(16)};`)
    .replace(step4CgSlotPattern, `uint256 internal constant STEP4_COEFF_C_G_SLOT = 0x${step4CgSlot.toString(16)};`)
    .replace(step4CfSlotPattern, `uint256 internal constant STEP4_COEFF_C_F_SLOT = 0x${step4CfSlot.toString(16)};`)
    .replace(step4CbSlotPattern, `uint256 internal constant STEP4_COEFF_C_B_SLOT = 0x${step4CbSlot.toString(16)};`)
    .replace(smaxPattern, `uint256 internal constant EXPECTED_SMAX = ${expectedSmax};`)
    .replace(omegaPattern, `uint256 internal constant OMEGA_SMAX_MINUS_1 =\n        ${omegaInverse};`);
}

assertFile(installedSigmaVerifyJsonPath, "Tokamak sigma_verify.json");
assertFile(setupParamsPath, "Tokamak setupParams.json");
fs.mkdirSync(path.dirname(sigmaVerifyJsonPath), { recursive: true });
fs.copyFileSync(installedSigmaVerifyJsonPath, sigmaVerifyJsonPath);

refreshTokamakVerifierKey();
const setupParams = JSON.parse(fs.readFileSync(setupParamsPath, "utf8"));
const verifierSource = fs.readFileSync(tokamakVerifierSourcePath, "utf8");
fs.writeFileSync(tokamakVerifierSourcePath, rewriteVerifierSetupParams(verifierSource, setupParams));
console.log(`Updated ${path.relative(process.cwd(), tokamakVerifierSourcePath)} setup constants from ${path.relative(process.cwd(), setupParamsPath)}`);
NODE
}

refresh_bridge_zk_constants() {
    node --input-type=module - "$PROJECT_ROOT" <<'NODE'
import fs from "node:fs";
import { createRequire } from "node:module";
import path from "node:path";
import { createAddressFromString } from "@ethereumjs/util";
import { ethers } from "ethers";

const repoRoot = process.argv[2];
const setupParamsPath = process.env.SUBCIRCUIT_SETUP_PARAMS_PATH;
const frontendCfgPath = process.env.SUBCIRCUIT_FRONTEND_CFG_PATH;
const require = createRequire(import.meta.url);
const targetFiles = [
  {
    path: "bridge/src/ChannelManager.sol",
    replacements: [
      {
        pattern: /uint256 internal constant TOKAMAK_APUB_BLOCK_LENGTH = \d+;/,
        render: ({ aPubBlockLength }) => `uint256 internal constant TOKAMAK_APUB_BLOCK_LENGTH = ${aPubBlockLength};`,
      },
      {
        pattern: /uint256 internal constant TOKAMAK_PREVIOUS_BLOCK_HASHES = \d+;/,
        render: ({ previousBlockHashCount }) => `uint256 internal constant TOKAMAK_PREVIOUS_BLOCK_HASHES = ${previousBlockHashCount};`,
      },
    ],
  },
];

function renderTokamakEnvironmentSource({ mtDepth, zeroFilledTreeRoot }) {
  return `// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Generated by bridge/scripts/deploy-bridge.sh.
library TokamakEnvironment {
    uint8 internal constant MT_DEPTH = ${mtDepth};
    uint256 internal constant MAX_MT_LEAVES = uint256(1) << uint256(MT_DEPTH);
    bytes32 internal constant ZERO_FILLED_TREE_ROOT = ${zeroFilledTreeRoot};
}
`;
}

async function computeZeroFilledTreeRoot(tokamak) {
  const stateManager = new tokamak.TokamakL2StateManager({ common: tokamak.createTokamakL2Common() });
  const dummyAddress = createAddressFromString("0x0000000000000000000000000000000000000001");
  await stateManager._initializeForAddresses([dummyAddress]);
  stateManager._channelId = "1";
  stateManager._commitResolvedStorageEntries(dummyAddress, []);
  const snapshot = await stateManager.captureStateSnapshot();
  const [root] = snapshot.stateRoots;
  if (typeof root !== "string" || !root.startsWith("0x")) {
    throw new Error(`Failed to compute ZERO_FILLED_TREE_ROOT from tokamak-l2js. Received: ${String(root)}`);
  }
  return root.toLowerCase();
}

function resolveTokamakPackageJsonPath() {
  const entryPath = require.resolve("tokamak-l2js");
  const packageRoot = entryPath.includes(`${path.sep}dist${path.sep}`)
    ? entryPath.slice(0, entryPath.lastIndexOf(`${path.sep}dist${path.sep}`))
    : path.dirname(entryPath);
  return path.join(packageRoot, "package.json");
}

const setupParams = JSON.parse(fs.readFileSync(setupParamsPath, "utf8"));
const frontendCfg = JSON.parse(fs.readFileSync(frontendCfgPath, "utf8"));
const tokamakPackageJsonPath = resolveTokamakPackageJsonPath();
const tokamakPackageJson = JSON.parse(fs.readFileSync(tokamakPackageJsonPath, "utf8"));
const tokamak = await import("tokamak-l2js");
const lUser = Number(setupParams.l_user);
const lFree = Number(setupParams.l_free);
if (!Number.isInteger(lUser) || lUser < 0) {
  throw new Error(`setupParams.json l_user must be a non-negative integer. Received: ${setupParams.l_user}`);
}
if (!Number.isInteger(lFree) || lFree <= 0) {
  throw new Error(`setupParams.json l_free must be a positive integer. Received: ${setupParams.l_free}`);
}
const aPubBlockLength = lFree - lUser;
if (!Number.isInteger(aPubBlockLength) || aPubBlockLength <= 0) {
  throw new Error(`setupParams.json must satisfy l_free - l_user > 0. Received: ${lFree} - ${lUser} = ${aPubBlockLength}`);
}
const previousBlockHashCount = Number(frontendCfg.nPrevBlockHashes);
if (!Number.isInteger(previousBlockHashCount) || previousBlockHashCount < 0) {
  throw new Error(`frontendCfg.json nPrevBlockHashes must be a non-negative integer. Received: ${frontendCfg.nPrevBlockHashes}`);
}
const mtDepth = Number(tokamak.MT_DEPTH);
if (!Number.isInteger(mtDepth) || mtDepth <= 0) {
  throw new Error(`tokamak-l2js MT_DEPTH must be a positive integer. Received: ${String(tokamak.MT_DEPTH)}`);
}
const maxMtLeaves = ethers.toBigInt(tokamak.MAX_MT_LEAVES);
const expectedMaxMtLeaves = 1n << ethers.toBigInt(mtDepth);
if (maxMtLeaves !== expectedMaxMtLeaves) {
  throw new Error(`tokamak-l2js MAX_MT_LEAVES mismatch. Expected 2^${mtDepth}=${expectedMaxMtLeaves}, received ${maxMtLeaves}.`);
}
const zeroFilledTreeRoot = await computeZeroFilledTreeRoot(tokamak);

for (const target of targetFiles) {
  const targetPath = path.join(repoRoot, target.path);
  let next = fs.readFileSync(targetPath, "utf8");
  for (const replacement of target.replacements) {
    if (!replacement.pattern.test(next)) {
      throw new Error(`Failed to update ${target.path}: replacement marker not found.`);
    }
    next = next.replace(replacement.pattern, replacement.render({ aPubBlockLength, previousBlockHashCount }));
  }
  fs.writeFileSync(targetPath, next);
}

const generatedEnvironmentPath = path.join(repoRoot, "bridge/src/generated/TokamakEnvironment.sol");
fs.mkdirSync(path.dirname(generatedEnvironmentPath), { recursive: true });
fs.writeFileSync(generatedEnvironmentPath, renderTokamakEnvironmentSource({ mtDepth, zeroFilledTreeRoot }));
console.log([
  `Updated shared Tokamak constants from ${path.relative(process.cwd(), setupParamsPath)}`,
  `and ${path.relative(process.cwd(), frontendCfgPath)}.`,
  `Using tokamak-l2js@${tokamakPackageJson.version} MT_DEPTH=${mtDepth},`,
  `ZERO_FILLED_TREE_ROOT=${zeroFilledTreeRoot},`,
  `a_pub_block length=${aPubBlockLength} (l_free=${lFree}, l_user=${lUser}),`,
  `nPrevBlockHashes=${previousBlockHashCount}.`,
].join(" "));
NODE
}

refresh_groth16_verifier_solidity() {
    local groth_source="$1"
    local groth_crs_dir="$PROJECT_ROOT/packages/groth16/crs"
    local groth_verification_key_path="$groth_crs_dir/verification_key.json"
    local groth_verifier_output_path="$PROJECT_ROOT/bridge/src/generated/Groth16Verifier.sol"

    case "$groth_source" in
        trusted|mpc)
            ;;
        *)
            echo "Unsupported BRIDGE_GROTH_SOURCE=$groth_source" >&2
            echo "Supported values: trusted, mpc" >&2
            exit 1
            ;;
    esac

    node --input-type=module - "$PROJECT_ROOT" "$groth_source" <<'NODE'
import path from "node:path";
import { pathToFileURL } from "node:url";

const repoRoot = process.argv[2];
const grothSource = process.argv[3];
const runtime = await import(pathToFileURL(path.join(repoRoot, "packages", "groth16", "lib", "proof-runtime.mjs")).href);
await runtime.installGroth16Runtime({
  workspaceRoot: path.join(repoRoot, "packages", "groth16"),
  trustedSetup: grothSource === "trusted",
});
NODE

    node --input-type=module - "$groth_verification_key_path" "$groth_verifier_output_path" <<'NODE'
import fs from "node:fs";
import path from "node:path";

const verificationKeyPath = process.argv[2];
const outputPath = process.argv[3];

function splitFieldElement(value) {
  const hexValue = BigInt(value).toString(16).padStart(96, "0");
  const highPart = hexValue.slice(0, 32);
  const lowPart = hexValue.slice(32);
  return [`0x${"0".repeat(32)}${highPart}`, `0x${lowPart}`];
}

function generateIcConstants(icArray) {
  return icArray.map((point, index) => {
    const [xPart1, xPart2] = splitFieldElement(point[0]);
    const [yPart1, yPart2] = splitFieldElement(point[1]);
    return [
      `    uint256 constant IC${index}x_PART1 = ${xPart1};`,
      `    uint256 constant IC${index}x_PART2 = ${xPart2};`,
      `    uint256 constant IC${index}y_PART1 = ${yPart1};`,
      `    uint256 constant IC${index}y_PART2 = ${yPart2};`,
      "",
    ].join("\n");
  }).join("\n").trimEnd();
}

function generateIcCalls(icCount) {
  const lines = [];
  for (let index = 1; index < icCount; index += 1) {
    const offset = (index - 1) * 32;
    lines.push(`                g1_mulAccC(_pVk, IC${index}x_PART1, IC${index}x_PART2, IC${index}y_PART1, IC${index}y_PART2, calldataload(add(pubSignals, ${offset})))`, "");
  }
  return lines.join("\n").trimEnd();
}

function generateCheckFieldCalls(pubSignalCount) {
  const lines = [];
  for (let index = 0; index < pubSignalCount; index += 1) {
    const offset = index * 32;
    lines.push(`            checkField(calldataload(add(_pubSignals, ${offset})))`, "");
  }
  return lines.join("\n").trimEnd();
}

function generateContract(vkData) {
  if (vkData.curve !== "bls12381") {
    throw new Error("Only bls12381 verification keys are supported.");
  }
  const alpha = vkData.vk_alpha_1;
  const beta = vkData.vk_beta_2;
  const gamma = vkData.vk_gamma_2;
  const delta = vkData.vk_delta_2;
  const icArray = vkData.IC;
  const icCount = icArray.length;
  const pubSignalCount = icCount - 1;
  if (pubSignalCount !== Number(vkData.nPublic ?? pubSignalCount)) {
    throw new Error("Verification key public-input count does not match the IC array.");
  }
  const [alphaxPart1, alphaxPart2] = splitFieldElement(alpha[0]);
  const [alphayPart1, alphayPart2] = splitFieldElement(alpha[1]);
  const [betax1Part1, betax1Part2] = splitFieldElement(beta[0][1]);
  const [betax2Part1, betax2Part2] = splitFieldElement(beta[0][0]);
  const [betay1Part1, betay1Part2] = splitFieldElement(beta[1][1]);
  const [betay2Part1, betay2Part2] = splitFieldElement(beta[1][0]);
  const [gammax1Part1, gammax1Part2] = splitFieldElement(gamma[0][1]);
  const [gammax2Part1, gammax2Part2] = splitFieldElement(gamma[0][0]);
  const [gammay1Part1, gammay1Part2] = splitFieldElement(gamma[1][1]);
  const [gammay2Part1, gammay2Part2] = splitFieldElement(gamma[1][0]);
  const [deltax1Part1, deltax1Part2] = splitFieldElement(delta[0][1]);
  const [deltax2Part1, deltax2Part2] = splitFieldElement(delta[0][0]);
  const [deltay1Part1, deltay1Part2] = splitFieldElement(delta[1][1]);
  const [deltay2Part1, deltay2Part2] = splitFieldElement(delta[1][0]);
  const icConstants = generateIcConstants(icArray);
  const icCalls = generateIcCalls(icCount);
  const checkFieldCalls = generateCheckFieldCalls(pubSignalCount);
  return `// SPDX-License-Identifier: GPL-3.0
/*
    This file is generated from the updateTree Groth16 verification key.
*/

pragma solidity >=0.7.0 <0.9.0;

contract Groth16Verifier {
    uint256 constant R_MOD = 0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001;
    uint256 constant Q_MOD_PART1 = 0x000000000000000000000000000000001a0111ea397fe69a4b1ba7b6434bacd7;
    uint256 constant Q_MOD_PART2 = 0x64774b84f38512bf6730d2a0f6b0f6241eabfffeb153ffffb9feffffffffaaab;

    uint256 constant alphax_PART1 = ${alphaxPart1};
    uint256 constant alphax_PART2 = ${alphaxPart2};
    uint256 constant alphay_PART1 = ${alphayPart1};
    uint256 constant alphay_PART2 = ${alphayPart2};
    uint256 constant betax1_PART1 = ${betax1Part1};
    uint256 constant betax1_PART2 = ${betax1Part2};
    uint256 constant betax2_PART1 = ${betax2Part1};
    uint256 constant betax2_PART2 = ${betax2Part2};
    uint256 constant betay1_PART1 = ${betay1Part1};
    uint256 constant betay1_PART2 = ${betay1Part2};
    uint256 constant betay2_PART1 = ${betay2Part1};
    uint256 constant betay2_PART2 = ${betay2Part2};
    uint256 constant gammax1_PART1 = ${gammax1Part1};
    uint256 constant gammax1_PART2 = ${gammax1Part2};
    uint256 constant gammax2_PART1 = ${gammax2Part1};
    uint256 constant gammax2_PART2 = ${gammax2Part2};
    uint256 constant gammay1_PART1 = ${gammay1Part1};
    uint256 constant gammay1_PART2 = ${gammay1Part2};
    uint256 constant gammay2_PART1 = ${gammay2Part1};
    uint256 constant gammay2_PART2 = ${gammay2Part2};

    uint256 constant deltax2_PART1 = ${deltax2Part1};
    uint256 constant deltax2_PART2 = ${deltax2Part2};
    uint256 constant deltax1_PART1 = ${deltax1Part1};
    uint256 constant deltax1_PART2 = ${deltax1Part2};
    uint256 constant deltay2_PART1 = ${deltay2Part1};
    uint256 constant deltay2_PART2 = ${deltay2Part2};
    uint256 constant deltay1_PART1 = ${deltay1Part1};
    uint256 constant deltay1_PART2 = ${deltay1Part2};

${icConstants}

    uint16 constant pVk = 0;
    uint16 constant pPairing = 128;
    uint16 constant pLastMem = 1664;

    function verifyProof(
        uint256[4] calldata _pA,
        uint256[8] calldata _pB,
        uint256[4] calldata _pC,
        uint256[${pubSignalCount}] calldata _pubSignals
    ) external view returns (bool) {
        assembly {
            function checkField(v) {
                if iszero(lt(v, R_MOD)) {
                    mstore(0, 0)
                    return(0, 0x20)
                }
            }

            function g1_mulAccC(pR, x0, x1, y0, y1, s) {
                let success
                let mIn := mload(0x40)
                mstore(mIn, x0)
                mstore(add(mIn, 32), x1)
                mstore(add(mIn, 64), y0)
                mstore(add(mIn, 96), y1)
                mstore(add(mIn, 128), s)
                success := staticcall(sub(gas(), 2000), 0x0c, mIn, 160, mIn, 128)
                if iszero(success) { mstore(0, 0) return(0, 0x20) }
                mstore(add(mIn, 128), mload(pR))
                mstore(add(mIn, 160), mload(add(pR, 32)))
                mstore(add(mIn, 192), mload(add(pR, 64)))
                mstore(add(mIn, 224), mload(add(pR, 96)))
                success := staticcall(sub(gas(), 2000), 0x0b, mIn, 256, pR, 128)
                if iszero(success) { mstore(0, 0) return(0, 0x20) }
            }

            function checkPairing(pA, pB, pC, pubSignals, pMem) -> isOk {
                let _pPairing := add(pMem, pPairing)
                let _pVk := add(pMem, pVk)
                mstore(_pVk, IC0x_PART1)
                mstore(add(_pVk, 32), IC0x_PART2)
                mstore(add(_pVk, 64), IC0y_PART1)
                mstore(add(_pVk, 96), IC0y_PART2)

${icCalls}

                mstore(_pPairing, calldataload(pA))
                mstore(add(_pPairing, 32), calldataload(add(pA, 32)))
                let y_high := calldataload(add(pA, 64))
                let y_low := calldataload(add(pA, 96))
                let neg_y_high
                let neg_y_low
                let borrow := 0
                switch lt(Q_MOD_PART2, y_low)
                case 1 {
                    neg_y_low := sub(Q_MOD_PART2, y_low)
                    neg_y_low := add(neg_y_low, not(0))
                    neg_y_low := add(neg_y_low, 1)
                    borrow := 1
                }
                default { neg_y_low := sub(Q_MOD_PART2, y_low) }
                neg_y_high := sub(sub(Q_MOD_PART1, y_high), borrow)
                mstore(add(_pPairing, 64), neg_y_high)
                mstore(add(_pPairing, 96), neg_y_low)
                mstore(add(_pPairing, 128), calldataload(add(pB, 64)))
                mstore(add(_pPairing, 160), calldataload(add(pB, 96)))
                mstore(add(_pPairing, 192), calldataload(pB))
                mstore(add(_pPairing, 224), calldataload(add(pB, 32)))
                mstore(add(_pPairing, 256), calldataload(add(pB, 192)))
                mstore(add(_pPairing, 288), calldataload(add(pB, 224)))
                mstore(add(_pPairing, 320), calldataload(add(pB, 128)))
                mstore(add(_pPairing, 352), calldataload(add(pB, 160)))
                mstore(add(_pPairing, 384), alphax_PART1)
                mstore(add(_pPairing, 416), alphax_PART2)
                mstore(add(_pPairing, 448), alphay_PART1)
                mstore(add(_pPairing, 480), alphay_PART2)
                mstore(add(_pPairing, 512), betax2_PART1)
                mstore(add(_pPairing, 544), betax2_PART2)
                mstore(add(_pPairing, 576), betax1_PART1)
                mstore(add(_pPairing, 608), betax1_PART2)
                mstore(add(_pPairing, 640), betay2_PART1)
                mstore(add(_pPairing, 672), betay2_PART2)
                mstore(add(_pPairing, 704), betay1_PART1)
                mstore(add(_pPairing, 736), betay1_PART2)
                mstore(add(_pPairing, 768), mload(add(pMem, pVk)))
                mstore(add(_pPairing, 800), mload(add(pMem, add(pVk, 32))))
                mstore(add(_pPairing, 832), mload(add(pMem, add(pVk, 64))))
                mstore(add(_pPairing, 864), mload(add(pMem, add(pVk, 96))))
                mstore(add(_pPairing, 896), gammax2_PART1)
                mstore(add(_pPairing, 928), gammax2_PART2)
                mstore(add(_pPairing, 960), gammax1_PART1)
                mstore(add(_pPairing, 992), gammax1_PART2)
                mstore(add(_pPairing, 1024), gammay2_PART1)
                mstore(add(_pPairing, 1056), gammay2_PART2)
                mstore(add(_pPairing, 1088), gammay1_PART1)
                mstore(add(_pPairing, 1120), gammay1_PART2)
                mstore(add(_pPairing, 1152), calldataload(pC))
                mstore(add(_pPairing, 1184), calldataload(add(pC, 32)))
                mstore(add(_pPairing, 1216), calldataload(add(pC, 64)))
                mstore(add(_pPairing, 1248), calldataload(add(pC, 96)))
                mstore(add(_pPairing, 1280), deltax2_PART1)
                mstore(add(_pPairing, 1312), deltax2_PART2)
                mstore(add(_pPairing, 1344), deltax1_PART1)
                mstore(add(_pPairing, 1376), deltax1_PART2)
                mstore(add(_pPairing, 1408), deltay2_PART1)
                mstore(add(_pPairing, 1440), deltay2_PART2)
                mstore(add(_pPairing, 1472), deltay1_PART1)
                mstore(add(_pPairing, 1504), deltay1_PART2)
                let success := staticcall(sub(gas(), 2000), 0x0f, _pPairing, 1536, _pPairing, 0x20)
                isOk := and(success, mload(_pPairing))
            }

            let pMem := mload(0x40)
            mstore(0x40, add(pMem, pLastMem))

${checkFieldCalls}

            let isValid := checkPairing(_pA, _pB, _pC, _pubSignals, pMem)
            mstore(0, isValid)
            return(0, 0x20)
        }
    }
}
`;
}

const vkData = JSON.parse(fs.readFileSync(verificationKeyPath, "utf8"));
fs.mkdirSync(path.dirname(outputPath), { recursive: true });
fs.writeFileSync(outputPath, generateContract(vkData));
console.log(`Generated ${path.relative(process.cwd(), outputPath)} from ${path.relative(process.cwd(), verificationKeyPath)}`);
NODE
}

write_bridge_zk_manifest() {
    local manifest_path="$1"
    local groth_source="$2"

    node --input-type=module - "$PROJECT_ROOT" "$manifest_path" "$groth_source" <<'NODE'
import fs from "node:fs";
import { createRequire } from "node:module";
import path from "node:path";

const repoRoot = process.argv[2];
const manifestPath = process.argv[3];
const grothSource = process.argv[4];
const require = createRequire(import.meta.url);

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function grothCrsDirFor(source) {
  if (source !== "trusted" && source !== "mpc") {
    throw new Error(`Unsupported Groth16 source: ${source}`);
  }
  return path.join(repoRoot, "packages", "groth16", "crs");
}

function resolveTokamakPackageJsonPath() {
  const entryPath = require.resolve("tokamak-l2js");
  const packageRoot = entryPath.includes(`${path.sep}dist${path.sep}`)
    ? entryPath.slice(0, entryPath.lastIndexOf(`${path.sep}dist${path.sep}`))
    : path.dirname(entryPath);
  return path.join(packageRoot, "package.json");
}

const tokamakCliPackageRoot = process.env.TOKAMAK_CLI_PACKAGE_ROOT;
const tokamak = await import("tokamak-l2js");
const tokamakPackageJson = readJson(resolveTokamakPackageJsonPath());
const mtDepth = Number(tokamak.MT_DEPTH);
if (!Number.isInteger(mtDepth) || mtDepth <= 0) {
  throw new Error(`tokamak-l2js MT_DEPTH must be a positive integer. Received: ${String(tokamak.MT_DEPTH)}`);
}
const tokamakL2js = {
  version: tokamakPackageJson.version,
  mtDepth,
};
const setupParamsPath = process.env.SUBCIRCUIT_SETUP_PARAMS_PATH;
const grothCrsDir = grothCrsDirFor(grothSource);
const manifest = {
  generatedAt: new Date().toISOString(),
  tokamakRuntime: {
    cliPackageRoot: tokamakCliPackageRoot,
    cliVersion: readJson(path.join(tokamakCliPackageRoot, "package.json")).version,
    runtimeRoot: process.env.TOKAMAK_CLI_RUNTIME_ROOT,
    setupParamsPath,
    installedSigmaVerifyJsonPath: process.env.TOKAMAK_SIGMA_VERIFY_PATH,
  },
  tokamakL2js,
  tokamakVerifier: {
    sigmaVerifyJsonPath: path.join(repoRoot, "bridge", "src", "generated", "sigma_verify.json"),
    generatedVerifierKeyPath: path.join(repoRoot, "bridge", "src", "generated", "TokamakVerifierKey.generated.sol"),
    verifierSourcePath: path.join(repoRoot, "bridge", "src", "verifiers", "TokamakVerifier.sol"),
    setupParams: readJson(setupParamsPath),
  },
  groth16: {
    source: grothSource,
    verificationKeyPath: path.join(grothCrsDir, "verification_key.json"),
    verifierPath: path.join(repoRoot, "bridge", "src", "generated", "Groth16Verifier.sol"),
    metadata: readJson(path.join(grothCrsDir, "metadata.json")),
  },
  bridge: {
    recommendedMerkleTreeLevels: tokamakL2js.mtDepth,
  },
};

fs.mkdirSync(path.dirname(manifestPath), { recursive: true });
fs.writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);
console.log(`Wrote bridge ZK manifest: ${manifestPath}`);
NODE
}

sync_groth16_artifacts_for_bridge() {
    local chain_id="$1"
    local source_groth_dir="$PROJECT_ROOT/packages/groth16/crs"
    local timestamp_label="${BRIDGE_ARTIFACT_TIMESTAMP:-$(date -u +"%Y%m%dT%H%M%SZ")}"
    local snapshot_dir="$PROJECT_ROOT/deployment/chain-id-${chain_id}/bridge/${timestamp_label}"
    local artifact_dir="$snapshot_dir/groth16"
    local manifest_path="$snapshot_dir/groth16.${chain_id}.latest.json"
    local timestamp_utc
    timestamp_utc="$(date -u +"%Y%m%dT%H%M%SZ")"

    for required_path in \
        "$source_groth_dir/circuit_final.zkey" \
        "$source_groth_dir/metadata.json" \
        "$source_groth_dir/verification_key.json"
    do
        if [[ ! -f "$required_path" ]]; then
            echo "Missing required Groth16 artifact: $required_path" >&2
            exit 1
        fi
    done

    rm -rf "$artifact_dir"
    mkdir -p "$artifact_dir"
    cp "$source_groth_dir/circuit_final.zkey" "$artifact_dir/circuit_final.zkey"
    cp "$source_groth_dir/metadata.json" "$artifact_dir/metadata.json"
    cp "$source_groth_dir/verification_key.json" "$artifact_dir/verification_key.json"

    local zkey_provenance_path="null"
    if [[ -f "$source_groth_dir/zkey_provenance.json" ]]; then
        cp "$source_groth_dir/zkey_provenance.json" "$artifact_dir/zkey_provenance.json"
        zkey_provenance_path="\"groth16/zkey_provenance.json\""
    fi

    jq -n \
        --arg generatedAtUtc "$timestamp_utc" \
        --arg chainId "$chain_id" \
        --arg grothArtifactSource "$BRIDGE_GROTH_SOURCE" \
        --arg artifactDir "groth16" \
        --arg zkeyPath "groth16/circuit_final.zkey" \
        --arg metadataPath "groth16/metadata.json" \
        --arg verificationKeyPath "groth16/verification_key.json" \
        --argjson zkeyProvenancePath "$zkey_provenance_path" \
        '{
            generatedAtUtc: $generatedAtUtc,
            chainId: ($chainId | tonumber),
            grothArtifactSource: $grothArtifactSource,
            artifactDir: $artifactDir,
            artifacts: {
                zkeyPath: $zkeyPath,
                metadataPath: $metadataPath,
                verificationKeyPath: $verificationKeyPath,
                zkeyProvenancePath: $zkeyProvenancePath
            }
        }' > "$manifest_path"

    echo "Updated bridge Groth16 manifest: $manifest_path"
    echo "Groth16 artifact source: $BRIDGE_GROTH_SOURCE"
}

sync_tokamak_zkp_artifacts_for_bridge() {
    local chain_id="$1"

    node --input-type=module - "$PROJECT_ROOT" "$chain_id" "$BRIDGE_ARTIFACT_TIMESTAMP" <<'NODE'
import fs from "node:fs";
import path from "node:path";

const repoRoot = process.argv[2];
const chainId = process.argv[3];
const timestampLabel = process.argv[4];
const tokamakCliPackageRoot = process.env.TOKAMAK_CLI_PACKAGE_ROOT;
const tokamakSetupOutputDir = process.env.TOKAMAK_CLI_SETUP_OUTPUT_DIR;
const snapshotDir = path.join(repoRoot, "deployment", `chain-id-${chainId}`, "bridge", timestampLabel);
const artifactDir = path.join(snapshotDir, "tokamak-zkp");
const manifestPath = path.join(snapshotDir, `tokamak-zkp.${chainId}.latest.json`);
const combinedSigmaPath = path.join(tokamakSetupOutputDir, "combined_sigma.rkyv");
const sigmaPreprocessPath = path.join(tokamakSetupOutputDir, "sigma_preprocess.rkyv");
const sigmaVerifyPath = path.join(tokamakSetupOutputDir, "sigma_verify.json");
const buildMetadataPath = path.join(tokamakSetupOutputDir, "build-metadata-mpc-setup.json");
const crsProvenancePath = path.join(tokamakSetupOutputDir, "crs_provenance.json");

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function writeJson(filePath, value) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`);
}

function assertFileExists(filePath, label) {
  if (!fs.existsSync(filePath)) {
    throw new Error(`Missing required Tokamak zk proof artifact: ${label}: ${filePath}`);
  }
}

function copyFile(sourcePath, targetPath) {
  fs.mkdirSync(path.dirname(targetPath), { recursive: true });
  fs.copyFileSync(sourcePath, targetPath);
}

function readCliVersion() {
  const packageJsonPath = path.join(tokamakCliPackageRoot, "package.json");
  const packageJson = readJson(packageJsonPath);
  if (typeof packageJson.version !== "string" || packageJson.version.length === 0) {
    throw new Error(`Tokamak CLI package has no version: ${packageJsonPath}`);
  }
  return packageJson.version;
}

function readSetupVersion(buildMetadataPathValue, fallbackVersion) {
  if (!fs.existsSync(buildMetadataPathValue)) {
    return fallbackVersion;
  }
  const metadata = readJson(buildMetadataPathValue);
  return typeof metadata.packageVersion === "string" && metadata.packageVersion.length > 0
    ? metadata.packageVersion
    : fallbackVersion;
}

assertFileExists(combinedSigmaPath, "combined_sigma.rkyv");
assertFileExists(sigmaPreprocessPath, "sigma_preprocess.rkyv");
assertFileExists(sigmaVerifyPath, "sigma_verify.json");
fs.rmSync(artifactDir, { recursive: true, force: true });

let relativeBuildMetadataPath = null;
if (fs.existsSync(buildMetadataPath)) {
  fs.mkdirSync(artifactDir, { recursive: true });
  copyFile(buildMetadataPath, path.join(artifactDir, "build-metadata-mpc-setup.json"));
  relativeBuildMetadataPath = "tokamak-zkp/build-metadata-mpc-setup.json";
}

let relativeCrsProvenancePath = null;
if (fs.existsSync(crsProvenancePath)) {
  fs.mkdirSync(artifactDir, { recursive: true });
  copyFile(crsProvenancePath, path.join(artifactDir, "crs_provenance.json"));
  relativeCrsProvenancePath = "tokamak-zkp/crs_provenance.json";
}

const cliVersion = readCliVersion();
const artifactVersion = readSetupVersion(buildMetadataPath, cliVersion);
writeJson(manifestPath, {
  generatedAtUtc: new Date().toISOString().replace(/[-:]/g, "").replace(/\.\d{3}Z$/, "Z"),
  chainId: Number(chainId),
  tokamakZkpArtifactSource: "cli-runtime-cache",
  artifactDir: "tokamak-zkp",
  artifacts: {
    version: artifactVersion,
    buildMetadataPath: relativeBuildMetadataPath,
    crsProvenancePath: relativeCrsProvenancePath,
  },
});

console.log(`Updated bridge Tokamak zk proof manifest: ${manifestPath}`);
console.log(`Tokamak setup output directory: ${tokamakSetupOutputDir}`);
NODE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --mode)
            if [[ $# -lt 2 ]]; then
                echo "Missing value for --mode" >&2
                exit 1
            fi
            DEPLOY_MODE="$2"
            shift 2
            ;;
        *)
            FORWARD_ARGS+=("$1")
            shift
            ;;
    esac
done

if [[ ! -f "$ENV_FILE" ]]; then
    echo "Missing $ENV_FILE"
    echo "Create it from $PROJECT_ROOT/.env.example"
    exit 1
fi

set -a
source "$ENV_FILE"
set +a

if [[ -n "${BRIDGE_DEPLOYER_PRIVATE_KEY:-}" && "${BRIDGE_DEPLOYER_PRIVATE_KEY}" != 0x* ]]; then
    BRIDGE_DEPLOYER_PRIVATE_KEY="0x${BRIDGE_DEPLOYER_PRIVATE_KEY}"
    export BRIDGE_DEPLOYER_PRIVATE_KEY
fi

required_vars=(
    "BRIDGE_DEPLOYER_PRIVATE_KEY"
    "BRIDGE_NETWORK"
)

if [[ -z "${BRIDGE_RPC_URL_OVERRIDE:-}" && "${BRIDGE_NETWORK:-}" != "anvil" ]]; then
    required_vars+=("BRIDGE_ALCHEMY_API_KEY")
fi

for var_name in "${required_vars[@]}"; do
    if [[ -z "${!var_name:-}" ]]; then
        echo "Missing required environment variable: $var_name"
        exit 1
    fi
done

case "${BRIDGE_NETWORK}" in
    sepolia)
        BRIDGE_CHAIN_ID=11155111
        BRIDGE_ALCHEMY_NETWORK="eth-sepolia"
        ;;
    mainnet)
        BRIDGE_CHAIN_ID=1
        BRIDGE_ALCHEMY_NETWORK="eth-mainnet"
        ;;
    anvil)
        BRIDGE_CHAIN_ID=31337
        BRIDGE_ALCHEMY_NETWORK=""
        ;;
    *)
        echo "Unsupported BRIDGE_NETWORK=${BRIDGE_NETWORK}" >&2
        echo "Supported values: sepolia, mainnet, anvil" >&2
        exit 1
        ;;
esac

if [[ -n "${BRIDGE_GROTH_SOURCE:-}" ]]; then
    EFFECTIVE_BRIDGE_GROTH_SOURCE="${BRIDGE_GROTH_SOURCE}"
else
    EFFECTIVE_BRIDGE_GROTH_SOURCE="mpc"
fi

case "${EFFECTIVE_BRIDGE_GROTH_SOURCE}" in
    trusted|mpc)
        ;;
    *)
        echo "Unsupported BRIDGE_GROTH_SOURCE=${EFFECTIVE_BRIDGE_GROTH_SOURCE}" >&2
        echo "Supported values: trusted, mpc" >&2
        exit 1
        ;;
esac

export BRIDGE_GROTH_SOURCE="${EFFECTIVE_BRIDGE_GROTH_SOURCE}"

case "${DEPLOY_MODE}" in
    upgrade|redeploy-proxy)
        ;;
    *)
        echo "Unsupported deploy mode: ${DEPLOY_MODE}" >&2
        echo "Supported modes: upgrade, redeploy-proxy" >&2
        exit 1
        ;;
esac

if [[ -n "${BRIDGE_RPC_URL_OVERRIDE:-}" ]]; then
    BRIDGE_RPC_URL="$BRIDGE_RPC_URL_OVERRIDE"
    NETWORK_LABEL="<override>"
elif [[ "$BRIDGE_NETWORK" == "anvil" ]]; then
    BRIDGE_RPC_URL="http://127.0.0.1:8545"
    NETWORK_LABEL="anvil-localhost"
else
    BRIDGE_RPC_URL="https://${BRIDGE_ALCHEMY_NETWORK}.g.alchemy.com/v2/${BRIDGE_ALCHEMY_API_KEY}"
    NETWORK_LABEL="$BRIDGE_ALCHEMY_NETWORK"
fi

UPLOAD_TIMESTAMP="$(date -u +"%Y%m%dT%H%M%SZ")"
BRIDGE_CANONICAL_DIR="$PROJECT_ROOT/deployment/chain-id-${BRIDGE_CHAIN_ID}/bridge/${UPLOAD_TIMESTAMP}"
LATEST_BRIDGE_DIR="$(latest_complete_bridge_dir "$PROJECT_ROOT/deployment/chain-id-${BRIDGE_CHAIN_ID}/bridge" "$BRIDGE_CHAIN_ID")"
DEFAULT_BRIDGE_INPUT_PATH="./deployments/bridge.${BRIDGE_CHAIN_ID}.json"
if [[ -n "$LATEST_BRIDGE_DIR" ]]; then
    DEFAULT_BRIDGE_INPUT_PATH="$LATEST_BRIDGE_DIR/bridge.${BRIDGE_CHAIN_ID}.json"
fi

ZK_MANIFEST_PATH="${BRIDGE_REFLECTION_MANIFEST_PATH:-$BRIDGE_CANONICAL_DIR/zk-reflection.latest.json}"

load_tokamak_cli_entry_context

if [[ "${BRIDGE_SKIP_TOKAMAK_INSTALL:-0}" == "1" ]]; then
    echo "Skipping tokamak-cli runtime install because BRIDGE_SKIP_TOKAMAK_INSTALL=1"
else
    run_tokamak_cli_install
fi

load_tokamak_runtime_context

if [[ "${BRIDGE_SKIP_TOKAMAK_VERIFIER_REFRESH:-0}" == "1" ]]; then
    echo "Skipping Tokamak verifier Solidity refresh because BRIDGE_SKIP_TOKAMAK_VERIFIER_REFRESH=1"
else
    refresh_tokamak_verifier_solidity
fi

refresh_bridge_zk_constants

if [[ "${BRIDGE_SKIP_GROTH_REFRESH:-0}" == "1" ]]; then
    echo "Skipping Groth16 verifier Solidity refresh because BRIDGE_SKIP_GROTH_REFRESH=1"
else
    refresh_groth16_verifier_solidity "$BRIDGE_GROTH_SOURCE"
fi

write_bridge_zk_manifest "$ZK_MANIFEST_PATH" "$BRIDGE_GROTH_SOURCE"

MT_DEPTH_METADATA="$(cat "$ZK_MANIFEST_PATH")"
BRIDGE_MERKLE_TREE_LEVELS="$(printf '%s' "$MT_DEPTH_METADATA" | node -e 'process.stdin.on("data",(buf)=>{const parsed=JSON.parse(String(buf)); process.stdout.write(String(parsed.tokamakL2js.mtDepth));});')"
BRIDGE_MERKLE_TREE_SOURCE_VERSION="$(printf '%s' "$MT_DEPTH_METADATA" | node -e 'process.stdin.on("data",(buf)=>{const parsed=JSON.parse(String(buf)); process.stdout.write(String(parsed.tokamakL2js.version));});')"
export BRIDGE_MERKLE_TREE_LEVELS
CANONICAL_BRIDGE_OUTPUT_PATH="${BRIDGE_OUTPUT_PATH:-$BRIDGE_CANONICAL_DIR/bridge.${BRIDGE_CHAIN_ID}.json}"
CANONICAL_BRIDGE_INPUT_PATH="${BRIDGE_INPUT_PATH:-$DEFAULT_BRIDGE_INPUT_PATH}"
CANONICAL_BRIDGE_OUTPUT_PATH="$(resolve_bridge_path "$CANONICAL_BRIDGE_OUTPUT_PATH")"
CANONICAL_BRIDGE_INPUT_PATH="$(resolve_bridge_path "$CANONICAL_BRIDGE_INPUT_PATH")"
BRIDGE_PENDING_DIR="$PROJECT_ROOT/deployment/.pending/chain-id-${BRIDGE_CHAIN_ID}/bridge/${UPLOAD_TIMESTAMP}"
BRIDGE_PENDING_OUTPUT_PATH="$BRIDGE_PENDING_DIR/$(basename "$CANONICAL_BRIDGE_OUTPUT_PATH")"
export BRIDGE_OUTPUT_PATH="$BRIDGE_PENDING_OUTPUT_PATH"
export BRIDGE_INPUT_PATH="$CANONICAL_BRIDGE_INPUT_PATH"
export BRIDGE_ARTIFACT_TIMESTAMP="$UPLOAD_TIMESTAMP"

BRIDGE_OUTPUT_PATH_ABS_FOR_MODE="$CANONICAL_BRIDGE_INPUT_PATH"
FORGE_SCRIPT="scripts/UpgradeBridgeStack.s.sol:UpgradeBridgeStackScript"

if [[ "${DEPLOY_MODE}" == "redeploy-proxy" ]]; then
    FORGE_SCRIPT="scripts/DeployBridgeStack.s.sol:DeployBridgeStackScript"
else
    if [[ ! -f "$BRIDGE_OUTPUT_PATH_ABS_FOR_MODE" ]]; then
        echo "Missing proxy deployment artifact for upgrade mode: $BRIDGE_OUTPUT_PATH_ABS_FOR_MODE" >&2
        echo "Run with --mode redeploy-proxy once to bootstrap proxy addresses on this network." >&2
        exit 1
    fi
    EXISTING_PROXY_KIND="$(node -e 'const fs=require("fs"); const p=process.argv[1]; const j=JSON.parse(fs.readFileSync(p,"utf8")); process.stdout.write(String(j.proxyKind || ""));' "$BRIDGE_OUTPUT_PATH_ABS_FOR_MODE")"
    if [[ "$EXISTING_PROXY_KIND" != "uups" ]]; then
        echo "Deployment artifact is not proxy-based: $BRIDGE_OUTPUT_PATH_ABS_FOR_MODE" >&2
        echo "Run with --mode redeploy-proxy to replace it with a proxy deployment." >&2
        exit 1
    fi
fi

FORGE_CMD=(
    forge script "$FORGE_SCRIPT"
    --sig "run()"
    --broadcast
    --rpc-url "$BRIDGE_RPC_URL"
)

if [[ ${#FORWARD_ARGS[@]} -gt 0 ]]; then
    FORGE_CMD+=("${FORWARD_ARGS[@]}")
fi

echo "Deploying bridge to network ${BRIDGE_NETWORK} (chain ID ${BRIDGE_CHAIN_ID})"
echo "Deployment mode: ${DEPLOY_MODE}"
echo "RPC network label: ${NETWORK_LABEL}"
echo "Environment file: ${ENV_FILE}"
echo "Resolved tokamak-l2js version: ${BRIDGE_MERKLE_TREE_SOURCE_VERSION}"
echo "Resolved tokamak-l2js MT_DEPTH: ${BRIDGE_MERKLE_TREE_LEVELS}"
echo "Groth16 artifact source: ${BRIDGE_GROTH_SOURCE}"
echo "ZK manifest: ${ZK_MANIFEST_PATH}"

if [[ "${BRIDGE_NETWORK}" != "anvil" ]]; then
    node "$PROJECT_ROOT/bridge/scripts/upload-bridge-artifacts.mjs" \
        "$BRIDGE_CHAIN_ID" \
        --timestamp "$UPLOAD_TIMESTAMP" \
        --preflight
fi

mkdir -p "$BRIDGE_PENDING_DIR"

(
    cd "$PROJECT_ROOT/bridge"
    "${FORGE_CMD[@]}"
)

if [[ "${DEPLOY_MODE}" == "redeploy-proxy" ]]; then
    cleanup_broadcast_traces "DeployBridgeStack.s.sol" "$BRIDGE_CHAIN_ID"
else
    cleanup_broadcast_traces "UpgradeBridgeStack.s.sol" "$BRIDGE_CHAIN_ID"
fi

BRIDGE_PENDING_OUTPUT_PATH_ABS="$(resolve_bridge_path "$BRIDGE_OUTPUT_PATH")"
BRIDGE_ABI_MANIFEST_PATH="$BRIDGE_CANONICAL_DIR/bridge-abi-manifest.${BRIDGE_CHAIN_ID}.json"
BRIDGE_ABI_MANIFEST_PATH_ABS="$(resolve_bridge_path "$BRIDGE_ABI_MANIFEST_PATH")"
BRIDGE_PENDING_ABI_MANIFEST_PATH="$BRIDGE_PENDING_DIR/$(basename "$BRIDGE_ABI_MANIFEST_PATH_ABS")"

node "$PROJECT_ROOT/bridge/scripts/generate-bridge-abi-manifest.mjs" \
    --output "$BRIDGE_PENDING_ABI_MANIFEST_PATH" \
    --chain-id "$BRIDGE_CHAIN_ID" \
    --deployment-path "$BRIDGE_PENDING_OUTPUT_PATH_ABS" >/dev/null

node - <<'NODE' "$BRIDGE_PENDING_OUTPUT_PATH_ABS" "$BRIDGE_ABI_MANIFEST_PATH_ABS"
const fs = require("fs");
const path = require("path");

const deploymentPath = process.argv[2];
const canonicalAbiManifestPath = process.argv[3];

const deployment = JSON.parse(fs.readFileSync(deploymentPath, "utf8"));
deployment.abiManifestPath = path.basename(canonicalAbiManifestPath);
fs.writeFileSync(deploymentPath, `${JSON.stringify(deployment, null, 2)}\n`);
NODE

sync_groth16_artifacts_for_bridge "$BRIDGE_CHAIN_ID"
sync_tokamak_zkp_artifacts_for_bridge "$BRIDGE_CHAIN_ID"

if [[ "${BRIDGE_NETWORK}" != "anvil" ]]; then
    node "$PROJECT_ROOT/bridge/scripts/upload-bridge-artifacts.mjs" \
        "$BRIDGE_CHAIN_ID" \
        --timestamp "$UPLOAD_TIMESTAMP" \
        --deployment-path "$BRIDGE_PENDING_OUTPUT_PATH_ABS" \
        --abi-manifest-path "$BRIDGE_PENDING_ABI_MANIFEST_PATH"
fi

mkdir -p "$(dirname "$CANONICAL_BRIDGE_OUTPUT_PATH")"
mv "$BRIDGE_PENDING_OUTPUT_PATH_ABS" "$CANONICAL_BRIDGE_OUTPUT_PATH"
mkdir -p "$(dirname "$BRIDGE_ABI_MANIFEST_PATH_ABS")"
mv "$BRIDGE_PENDING_ABI_MANIFEST_PATH" "$BRIDGE_ABI_MANIFEST_PATH_ABS"
rm -rf "$BRIDGE_PENDING_DIR"

echo "Deployment artifact: $CANONICAL_BRIDGE_OUTPUT_PATH"
echo "ABI manifest: $BRIDGE_ABI_MANIFEST_PATH_ABS"

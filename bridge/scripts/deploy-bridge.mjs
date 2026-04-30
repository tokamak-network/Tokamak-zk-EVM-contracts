#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import fs from "node:fs";
import { createRequire } from "node:module";
import path from "node:path";
import process from "node:process";
import { fileURLToPath, pathToFileURL } from "node:url";
import { createAddressFromString } from "@ethereumjs/util";
import { parse as parseDotenv } from "dotenv";
import { ethers } from "ethers";
import { resolveAppNetwork } from "@tokamak-private-dapps/common-library/network-config";
import {
  groth16WorkspacePaths,
  resolveGroth16WorkspaceRoot,
} from "../../packages/groth16/lib/paths.mjs";
import {
  assertLatestPublicGroth16MpcArchiveVersion,
  normalizeGroth16CompatibleBackendVersion,
} from "../../packages/groth16/lib/public-drive-crs.mjs";
import {
  fetchLatestNpmPackageVersion,
  GROTH16_NPM_PACKAGE_NAME,
} from "../../packages/groth16/lib/npm-registry.mjs";
import { createTimestampLabel } from "../../scripts/deployment/lib/deployment-layout.mjs";

const require = createRequire(import.meta.url);
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const projectRoot = path.resolve(__dirname, "..", "..");
const bridgeRoot = path.join(projectRoot, "bridge");
const invocationCwd = process.cwd();
const envFile = process.env.BRIDGE_ENV_FILE || path.join(projectRoot, ".env");
const initialDeployMode = process.env.BRIDGE_DEPLOY_MODE || "upgrade";
const TOKAMAK_CLI_PACKAGE_NAME = "@tokamak-zk-evm/cli";

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

function fail(message) {
  throw new Error(message);
}

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function writeJson(filePath, value) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`);
}

function assertFileExists(filePath, label) {
  if (!fs.existsSync(filePath)) {
    fail(`Missing ${label}: ${filePath}`);
  }
}

function copyFile(sourcePath, targetPath) {
  fs.mkdirSync(path.dirname(targetPath), { recursive: true });
  fs.copyFileSync(sourcePath, targetPath);
}

function run(command, args, { cwd = invocationCwd, env = process.env, stdio = "inherit" } = {}) {
  const result = spawnSync(command, args, {
    cwd,
    env,
    encoding: "utf8",
    stdio,
  });
  if (result.error) {
    throw result.error;
  }
  if (result.status !== 0) {
    fail(`${command} ${args.join(" ")} exited with status ${result.status ?? "unknown"}`);
  }
  return result;
}

function resolveRuntimeBinaryPath(runtimeRoot, binaryName) {
  const executableName = process.platform === "win32" ? `${binaryName}.exe` : binaryName;
  return path.join(runtimeRoot, "bin", executableName);
}

function prependEnvPath(existing, nextValue) {
  return existing && existing.length > 0 ? `${nextValue}${path.delimiter}${existing}` : nextValue;
}

function runtimeBackendEnvironment(runtimeRoot) {
  const icicleLibDir = path.join(runtimeRoot, "backend-lib", "icicle", "lib");
  const env = { ...process.env };
  env.LD_LIBRARY_PATH = prependEnvPath(env.LD_LIBRARY_PATH, icicleLibDir);
  if (process.platform === "darwin") {
    env.DYLD_LIBRARY_PATH = prependEnvPath(env.DYLD_LIBRARY_PATH, icicleLibDir);
    env.ICICLE_BACKEND_INSTALL_DIR = path.join(icicleLibDir, "backend");
    return env;
  }
  env.ICICLE_BACKEND_INSTALL_DIR = process.platform === "linux"
    ? path.join(icicleLibDir, "backend")
    : "";
  return env;
}

function formatCommandOutput(label, value) {
  const output = String(value ?? "").trim();
  return `${label}:\n${output.length > 0 ? output : "(empty)"}`;
}

function readRuntimeBinaryVersion(runtimeRoot, binaryName) {
  const binaryPath = resolveRuntimeBinaryPath(runtimeRoot, binaryName);
  assertFileExists(binaryPath, `Tokamak zk proof backend binary: ${binaryName}`);
  const result = spawnSync(binaryPath, ["--version"], {
    encoding: "utf8",
    env: runtimeBackendEnvironment(runtimeRoot),
    stdio: ["ignore", "pipe", "pipe"],
  });
  if (result.error) {
    throw result.error;
  }
  if (result.status !== 0) {
    fail([
      `${binaryPath} --version exited with status ${result.status ?? "unknown"}`,
      formatCommandOutput("stdout", result.stdout),
      formatCommandOutput("stderr", result.stderr),
    ].join("\n"));
  }
  const output = `${result.stdout ?? ""}\n${result.stderr ?? ""}`.trim();
  const match = output.match(/(?:v)?(\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?)/i);
  if (!match) {
    fail(`Could not parse ${binaryName} version from --version output: ${output}`);
  }
  return match[1];
}

function npmPackageSource({ name, version }) {
  if (typeof name !== "string" || name.length === 0 || typeof version !== "string" || version.length === 0) {
    return null;
  }
  return {
    packageName: name,
    version,
    npmPackage: `${name}@${version}`,
  };
}

function optionalReadJson(filePath) {
  return fs.existsSync(filePath) ? readJson(filePath) : null;
}

function resolveBridgePath(inputPath) {
  return path.isAbsolute(inputPath) ? inputPath : path.resolve(bridgeRoot, inputPath);
}

function cleanupBroadcastTraces(scriptName, chainId) {
  fs.rmSync(path.join(bridgeRoot, "broadcast", scriptName, String(chainId)), { recursive: true, force: true });
}

function resolveBridgeNetwork(networkName) {
  if (!["sepolia", "mainnet", "anvil"].includes(networkName)) {
    fail(`Unsupported BRIDGE_NETWORK=${networkName}\nSupported values: sepolia, mainnet, anvil`);
  }
  return resolveAppNetwork(networkName);
}

function latestCompleteBridgeDir(rootDir, chainId) {
  if (!fs.existsSync(rootDir)) {
    return "";
  }
  const timestampPattern = /^20\d{6}T\d{6}Z$/;
  return fs.readdirSync(rootDir, { withFileTypes: true })
    .filter((entry) => entry.isDirectory() && timestampPattern.test(entry.name))
    .map((entry) => path.join(rootDir, entry.name))
    .filter((candidateDir) => fs.existsSync(path.join(candidateDir, `bridge.${chainId}.json`)))
    .sort()
    .at(-1) ?? "";
}

function parseArgs(argv) {
  let deployMode = initialDeployMode;
  const forwardArgs = [];
  for (let index = 0; index < argv.length; index += 1) {
    const current = argv[index];
    if (current === "--mode") {
      const value = argv[index + 1];
      if (!value) {
        fail("Missing value for --mode");
      }
      deployMode = value;
      index += 1;
      continue;
    }
    forwardArgs.push(current);
  }
  return { deployMode, forwardArgs };
}

function loadEnvFile() {
  if (!fs.existsSync(envFile)) {
    fail(`Missing ${envFile}\nCreate it from ${path.join(projectRoot, ".env.example")}`);
  }
  const parsed = parseDotenv(fs.readFileSync(envFile));
  for (const [key, value] of Object.entries(parsed)) {
    process.env[key] = value;
  }
}

function requireEnv(names) {
  for (const name of names) {
    if (!process.env[name]) {
      fail(`Missing required environment variable: ${name}`);
    }
  }
}

function loadTokamakCliEntryContext() {
  const packageRoot = path.dirname(require.resolve("@tokamak-zk-evm/cli/package.json"));
  process.env.TOKAMAK_CLI_PACKAGE_ROOT = packageRoot;
  process.env.TOKAMAK_CLI_ENTRY_PATH = path.join(packageRoot, "dist", "cli.js");
}

async function loadTokamakRuntimeContext() {
  const runtimePaths = await import("@tokamak-private-dapps/common-library/tokamak-runtime-paths");
  const setupOutputDir = runtimePaths.resolveTokamakCliSetupOutputDir();
  process.env.TOKAMAK_CLI_PACKAGE_ROOT = runtimePaths.resolveTokamakCliPackageRoot();
  process.env.TOKAMAK_CLI_ENTRY_PATH = runtimePaths.resolveTokamakCliEntryPath();
  process.env.TOKAMAK_CLI_RUNTIME_ROOT = runtimePaths.resolveTokamakCliRuntimeRoot();
  process.env.TOKAMAK_CLI_SETUP_OUTPUT_DIR = setupOutputDir;
  process.env.TOKAMAK_SIGMA_VERIFY_PATH = runtimePaths.resolveTokamakCliSetupArtifactPath("sigma_verify.json");
  process.env.SUBCIRCUIT_SETUP_PARAMS_PATH = runtimePaths.resolveSubcircuitSetupParamsPath();
  process.env.SUBCIRCUIT_FRONTEND_CFG_PATH = runtimePaths.resolveSubcircuitFrontendCfgPath();
}

function runTokamakCliInstall() {
  run("node", [process.env.TOKAMAK_CLI_ENTRY_PATH, "--install"]);
}

function normalizeHex(value, label, expectedHexLen) {
  if (typeof value !== "string") {
    fail(`${label} must be a hex string`);
  }
  let hex = value.startsWith("0x") ? value.slice(2) : value;
  hex = hex.toLowerCase();
  if (hex.length > expectedHexLen) {
    fail(`${label} exceeds expected length (${hex.length} > ${expectedHexLen})`);
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

function readPoint(_json, pathLabel, point) {
  if (!point || typeof point !== "object") {
    fail(`${pathLabel} is missing`);
  }
  return {
    x: splitG1(point.x, `${pathLabel}.x`),
    y: splitG1(point.y, `${pathLabel}.y`),
  };
}

function readG2Point(pathLabel, point, { negateY = false } = {}) {
  if (!point || typeof point !== "object") {
    fail(`${pathLabel} is missing`);
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

function buildGeneratedTokamakVerifierKeySolidity(points) {
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
        fail(`Failed to parse generated constant line: ${line}`);
      }
      const pattern = new RegExp(`uint256 internal constant ${name} = 0x[0-9a-f]+;`);
      if (!pattern.test(output)) {
        fail(`TokamakVerifier.sol is missing expected G2 constant ${name}`);
      }
      output = output.replace(pattern, `uint256 internal constant ${name} = ${value};`);
    }
  }
  return output;
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
    lUserPattern,
    lFreePattern,
    omegaLFreePattern,
    nPattern,
    miPattern,
    omegaMiPattern,
    smaxPattern,
    omegaPattern,
    denominatorSlotPattern,
    prefixSlotPattern,
    step4CgSlotPattern,
    step4CfSlotPattern,
    step4CbSlotPattern,
  ];
  if (!patterns.every((pattern) => pattern.test(source))) {
    fail("Failed to update TokamakVerifier.sol setup constants. Expected replacement markers were not found.");
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
      fail(`setupParams.json ${label} must be a positive integer. Received: ${value}`);
    }
  }
  const omegaLFree = OMEGA_LFREE_VALUES.get(expectedLFree);
  const omegaMiInverse = OMEGA_MI_INVERSES.get(expectedMi);
  const omegaInverse = OMEGA_SMAX_INVERSES.get(expectedSmax);
  if (!omegaLFree || !omegaMiInverse || !omegaInverse) {
    fail(`Unsupported setup params: l_free=${expectedLFree}, m_i=${expectedMi}, s_max=${expectedSmax}.`);
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

function refreshTokamakVerifierKey(sigmaVerifyJsonPath, tokamakVerifierGeneratedPath, tokamakVerifierSourcePath) {
  const json = readJson(sigmaVerifyJsonPath);
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
  fs.mkdirSync(path.dirname(tokamakVerifierGeneratedPath), { recursive: true });
  fs.writeFileSync(tokamakVerifierGeneratedPath, buildGeneratedTokamakVerifierKeySolidity(points));
  const verifierSource = fs.readFileSync(tokamakVerifierSourcePath, "utf8");
  fs.writeFileSync(tokamakVerifierSourcePath, rewriteVerifierG2Constants(verifierSource, points));
  console.log(`Generated ${path.relative(process.cwd(), tokamakVerifierGeneratedPath)} from ${path.relative(process.cwd(), sigmaVerifyJsonPath)}`);
  console.log(`Updated ${path.relative(process.cwd(), tokamakVerifierSourcePath)} G2 constants from ${path.relative(process.cwd(), sigmaVerifyJsonPath)}`);
}

function refreshTokamakVerifierSolidity() {
  const installedSigmaVerifyJsonPath = process.env.TOKAMAK_SIGMA_VERIFY_PATH;
  const setupParamsPath = process.env.SUBCIRCUIT_SETUP_PARAMS_PATH;
  const sigmaVerifyJsonPath = path.join(projectRoot, "bridge", "src", "generated", "sigma_verify.json");
  const tokamakVerifierGeneratedPath = path.join(projectRoot, "bridge", "src", "generated", "TokamakVerifierKey.generated.sol");
  const tokamakVerifierSourcePath = path.join(projectRoot, "bridge", "src", "verifiers", "TokamakVerifier.sol");

  assertFileExists(installedSigmaVerifyJsonPath, "Tokamak sigma_verify.json");
  assertFileExists(setupParamsPath, "Tokamak setupParams.json");
  fs.mkdirSync(path.dirname(sigmaVerifyJsonPath), { recursive: true });
  fs.copyFileSync(installedSigmaVerifyJsonPath, sigmaVerifyJsonPath);

  refreshTokamakVerifierKey(sigmaVerifyJsonPath, tokamakVerifierGeneratedPath, tokamakVerifierSourcePath);
  const setupParams = readJson(setupParamsPath);
  const verifierSource = fs.readFileSync(tokamakVerifierSourcePath, "utf8");
  fs.writeFileSync(tokamakVerifierSourcePath, rewriteVerifierSetupParams(verifierSource, setupParams));
  console.log(`Updated ${path.relative(process.cwd(), tokamakVerifierSourcePath)} setup constants from ${path.relative(process.cwd(), setupParamsPath)}`);
}

function renderTokamakEnvironmentSource({
  mtDepth,
  zeroFilledTreeRoot,
  aPubBlockLength,
  previousBlockHashCount,
}) {
  return `// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Generated by bridge/scripts/deploy-bridge.mjs.
library TokamakEnvironment {
    uint8 internal constant MT_DEPTH = ${mtDepth};
    uint256 internal constant MAX_MT_LEAVES = uint256(1) << uint256(MT_DEPTH);
    bytes32 internal constant ZERO_FILLED_TREE_ROOT =
        ${zeroFilledTreeRoot};
    uint256 internal constant TOKAMAK_APUB_BLOCK_LENGTH = ${aPubBlockLength};
    uint256 internal constant TOKAMAK_PREVIOUS_BLOCK_HASHES = ${previousBlockHashCount};
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
    fail(`Failed to compute ZERO_FILLED_TREE_ROOT from tokamak-l2js. Received: ${String(root)}`);
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

async function refreshBridgeZkConstants() {
  const setupParamsPath = process.env.SUBCIRCUIT_SETUP_PARAMS_PATH;
  const frontendCfgPath = process.env.SUBCIRCUIT_FRONTEND_CFG_PATH;
  const setupParams = readJson(setupParamsPath);
  const frontendCfg = readJson(frontendCfgPath);
  const tokamakPackageJsonPath = resolveTokamakPackageJsonPath();
  const tokamakPackageJson = readJson(tokamakPackageJsonPath);
  const tokamak = await import("tokamak-l2js");
  const lUser = Number(setupParams.l_user);
  const lFree = Number(setupParams.l_free);
  if (!Number.isInteger(lUser) || lUser < 0) {
    fail(`setupParams.json l_user must be a non-negative integer. Received: ${setupParams.l_user}`);
  }
  if (!Number.isInteger(lFree) || lFree <= 0) {
    fail(`setupParams.json l_free must be a positive integer. Received: ${setupParams.l_free}`);
  }
  const aPubBlockLength = lFree - lUser;
  if (!Number.isInteger(aPubBlockLength) || aPubBlockLength <= 0) {
    fail(`setupParams.json must satisfy l_free - l_user > 0. Received: ${lFree} - ${lUser} = ${aPubBlockLength}`);
  }
  const previousBlockHashCount = Number(frontendCfg.nPrevBlockHashes);
  if (!Number.isInteger(previousBlockHashCount) || previousBlockHashCount < 0) {
    fail(`frontendCfg.json nPrevBlockHashes must be a non-negative integer. Received: ${frontendCfg.nPrevBlockHashes}`);
  }
  const mtDepth = Number(tokamak.MT_DEPTH);
  if (!Number.isInteger(mtDepth) || mtDepth <= 0) {
    fail(`tokamak-l2js MT_DEPTH must be a positive integer. Received: ${String(tokamak.MT_DEPTH)}`);
  }
  const maxMtLeaves = ethers.toBigInt(tokamak.MAX_MT_LEAVES);
  const expectedMaxMtLeaves = 1n << ethers.toBigInt(mtDepth);
  if (maxMtLeaves !== expectedMaxMtLeaves) {
    fail(`tokamak-l2js MAX_MT_LEAVES mismatch. Expected 2^${mtDepth}=${expectedMaxMtLeaves}, received ${maxMtLeaves}.`);
  }
  const zeroFilledTreeRoot = await computeZeroFilledTreeRoot(tokamak);

  const generatedEnvironmentPath = path.join(projectRoot, "bridge", "src", "generated", "TokamakEnvironment.sol");
  fs.mkdirSync(path.dirname(generatedEnvironmentPath), { recursive: true });
  fs.writeFileSync(generatedEnvironmentPath, renderTokamakEnvironmentSource({
    mtDepth,
    zeroFilledTreeRoot,
    aPubBlockLength,
    previousBlockHashCount,
  }));
  console.log([
    `Updated shared Tokamak constants from ${path.relative(process.cwd(), setupParamsPath)}`,
    `and ${path.relative(process.cwd(), frontendCfgPath)}.`,
    `Using tokamak-l2js@${tokamakPackageJson.version} MT_DEPTH=${mtDepth},`,
    `ZERO_FILLED_TREE_ROOT=${zeroFilledTreeRoot},`,
    `a_pub_block length=${aPubBlockLength} (l_free=${lFree}, l_user=${lUser}),`,
    `nPrevBlockHashes=${previousBlockHashCount}.`,
  ].join(" "));
}

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

function generateGroth16VerifierContract(vkData) {
  if (vkData.curve !== "bls12381") {
    fail("Only bls12381 verification keys are supported.");
  }
  const alpha = vkData.vk_alpha_1;
  const beta = vkData.vk_beta_2;
  const gamma = vkData.vk_gamma_2;
  const delta = vkData.vk_delta_2;
  const icArray = vkData.IC;
  const icCount = icArray.length;
  const pubSignalCount = icCount - 1;
  if (pubSignalCount !== Number(vkData.nPublic ?? pubSignalCount)) {
    fail("Verification key public-input count does not match the IC array.");
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
    string public compatibleBackendVersion;

    constructor(string memory compatibleBackendVersion_) {
        compatibleBackendVersion = compatibleBackendVersion_;
    }

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

async function refreshGroth16VerifierSolidity(grothSource) {
  if (grothSource !== "trusted" && grothSource !== "mpc") {
    fail(`Unsupported BRIDGE_GROTH_SOURCE=${grothSource}\nSupported values: trusted, mpc`);
  }

  const grothPaths = bridgeGroth16WorkspacePaths();
  const verificationKeyPath = grothPaths.verificationKeyPath;
  const outputPath = path.join(projectRoot, "bridge", "src", "generated", "Groth16Verifier.sol");
  const runtime = await import(pathToFileURL(path.join(projectRoot, "packages", "groth16", "lib", "proof-runtime.mjs")).href);
  await runtime.installGroth16Runtime({
    workspaceRoot: grothPaths.rootDir,
    trustedSetup: grothSource === "trusted",
    publicMpcExpectedVersion: process.env.BRIDGE_GROTH_COMPATIBLE_BACKEND_VERSION,
  });

  const vkData = readJson(verificationKeyPath);
  fs.mkdirSync(path.dirname(outputPath), { recursive: true });
  fs.writeFileSync(outputPath, generateGroth16VerifierContract(vkData));
  console.log(`Generated ${path.relative(process.cwd(), outputPath)} from ${path.relative(process.cwd(), verificationKeyPath)}`);
}

function bridgeGroth16WorkspacePaths() {
  return groth16WorkspacePaths(resolveGroth16WorkspaceRoot());
}

function grothCrsPathsFor(source) {
  if (source !== "trusted" && source !== "mpc") {
    fail(`Unsupported Groth16 source: ${source}`);
  }
  return bridgeGroth16WorkspacePaths();
}

async function writeBridgeZkManifest(manifestPath, grothSource) {
  const tokamakCliPackageRoot = process.env.TOKAMAK_CLI_PACKAGE_ROOT;
  const tokamakCliPackageJson = readJson(path.join(tokamakCliPackageRoot, "package.json"));
  const tokamakCliRuntimeRoot = process.env.TOKAMAK_CLI_RUNTIME_ROOT;
  const tokamakSetupOutputDir = process.env.TOKAMAK_CLI_SETUP_OUTPUT_DIR;
  const tokamak = await import("tokamak-l2js");
  const tokamakPackageJson = readJson(resolveTokamakPackageJsonPath());
  const mtDepth = Number(tokamak.MT_DEPTH);
  if (!Number.isInteger(mtDepth) || mtDepth <= 0) {
    fail(`tokamak-l2js MT_DEPTH must be a positive integer. Received: ${String(tokamak.MT_DEPTH)}`);
  }
  const tokamakBuildMetadataPath = path.join(tokamakSetupOutputDir, "build-metadata-mpc-setup.json");
  const tokamakBuildMetadata = readJson(tokamakBuildMetadataPath);
  const tokamakSetupPackage = npmPackageSource({
    name: tokamakBuildMetadata.packageName,
    version: tokamakBuildMetadata.packageVersion,
  });
  const subcircuitLibrary = tokamakBuildMetadata.dependencies?.subcircuitLibrary;
  const subcircuitLibraryPackage = npmPackageSource({
    name: subcircuitLibrary?.packageName,
    version: subcircuitLibrary?.buildVersion,
  });
  const tokamakBackendBinaries = Object.fromEntries(
    ["preprocess", "prove", "verify"].map((binaryName) => [
      binaryName,
      readRuntimeBinaryVersion(tokamakCliRuntimeRoot, binaryName),
    ]),
  );
  const tokamakL2js = {
    package: npmPackageSource(tokamakPackageJson),
    mtDepth,
  };
  const setupParamsPath = process.env.SUBCIRCUIT_SETUP_PARAMS_PATH;
  const grothPaths = grothCrsPathsFor(grothSource);
  const grothPackageJson = readJson(path.join(projectRoot, "packages", "groth16", "package.json"));
  const grothProvenance = optionalReadJson(grothPaths.provenancePath);
  const grothArchiveSource = grothSource === "mpc" && grothProvenance?.zkey_download_url
    ? {
        type: "google-drive-archive",
        folderUrl: grothProvenance.published_folder_url ?? null,
        archiveName: grothProvenance.published_archive_name ?? null,
        downloadUrl: grothProvenance.zkey_download_url,
      }
    : {
        type: "npm-generated-trusted-setup",
        package: npmPackageSource(grothPackageJson),
      };
  const manifest = {
    generatedAt: new Date().toISOString(),
    tokamakRuntime: {
      cliPackage: npmPackageSource(tokamakCliPackageJson),
      setupPackage: tokamakSetupPackage,
      backendBinaries: tokamakBackendBinaries,
    },
    tokamakL2js,
    tokamakVerifier: {
      compatibleBackendVersion: process.env.BRIDGE_TOKAMAK_COMPATIBLE_BACKEND_VERSION,
      artifacts: {
        sigmaVerifyJson: {
          sourcePackage: tokamakSetupPackage?.npmPackage ?? null,
        },
        buildMetadata: {
          sourcePackage: tokamakSetupPackage?.npmPackage ?? null,
        },
        setupParams: {
          sourcePackage: subcircuitLibraryPackage?.npmPackage ?? null,
          declaredRange: subcircuitLibrary?.declaredRange ?? null,
          runtimeMode: subcircuitLibrary?.runtimeMode ?? null,
        },
      },
      setupParams: readJson(setupParamsPath),
    },
    groth16: {
      source: grothSource,
      package: npmPackageSource(grothPackageJson),
      compatibleBackendVersion: process.env.BRIDGE_GROTH_COMPATIBLE_BACKEND_VERSION,
      artifactSource: grothArchiveSource,
      artifacts: {
        circuitFinalZkey: {
          sourceUrl: grothProvenance?.zkey_download_url ?? null,
          sourcePackage: grothSource === "trusted" ? npmPackageSource(grothPackageJson)?.npmPackage : null,
          sha256: grothProvenance?.zkey_sha256 ?? null,
        },
        verificationKey: {
          sourceUrl: grothProvenance?.zkey_download_url ?? null,
          sourcePackage: grothSource === "trusted" ? npmPackageSource(grothPackageJson)?.npmPackage : null,
          sha256: grothProvenance?.verification_key_sha256 ?? null,
        },
        metadata: {
          sourceUrl: grothProvenance?.zkey_download_url ?? null,
          sourcePackage: grothSource === "trusted" ? npmPackageSource(grothPackageJson)?.npmPackage : null,
          sha256: grothProvenance?.metadata_sha256 ?? null,
        },
        zkeyProvenance: {
          sourceUrl: grothProvenance?.zkey_download_url ?? null,
          sourcePackage: grothSource === "trusted" ? npmPackageSource(grothPackageJson)?.npmPackage : null,
        },
      },
      metadata: readJson(grothPaths.metadataPath),
    },
    bridge: {
      recommendedMerkleTreeLevels: tokamakL2js.mtDepth,
    },
  };

  writeJson(manifestPath, manifest);
  console.log(`Wrote bridge ZK manifest: ${manifestPath}`);
}

function syncGroth16ArtifactsForBridge(chainId, snapshotDir) {
  const sourceGrothDir = bridgeGroth16WorkspacePaths().crsDir;
  const artifactDir = path.join(snapshotDir, "groth16");
  const manifestPath = path.join(snapshotDir, `groth16.${chainId}.latest.json`);
  const requiredPaths = [
    path.join(sourceGrothDir, "circuit_final.zkey"),
    path.join(sourceGrothDir, "metadata.json"),
    path.join(sourceGrothDir, "verification_key.json"),
  ];
  for (const requiredPath of requiredPaths) {
    if (!fs.existsSync(requiredPath)) {
      fail(`Missing required Groth16 artifact: ${requiredPath}`);
    }
  }

  fs.rmSync(artifactDir, { recursive: true, force: true });
  copyFile(path.join(sourceGrothDir, "circuit_final.zkey"), path.join(artifactDir, "circuit_final.zkey"));
  copyFile(path.join(sourceGrothDir, "metadata.json"), path.join(artifactDir, "metadata.json"));
  copyFile(path.join(sourceGrothDir, "verification_key.json"), path.join(artifactDir, "verification_key.json"));

  let zkeyProvenancePath = null;
  const sourceZkeyProvenancePath = path.join(sourceGrothDir, "zkey_provenance.json");
  if (fs.existsSync(sourceZkeyProvenancePath)) {
    copyFile(sourceZkeyProvenancePath, path.join(artifactDir, "zkey_provenance.json"));
    zkeyProvenancePath = "groth16/zkey_provenance.json";
  }

  writeJson(manifestPath, {
    generatedAtUtc: createTimestampLabel(),
    chainId: Number(chainId),
    grothArtifactSource: process.env.BRIDGE_GROTH_SOURCE,
    artifactDir: "groth16",
    artifacts: {
      zkeyPath: "groth16/circuit_final.zkey",
      metadataPath: "groth16/metadata.json",
      verificationKeyPath: "groth16/verification_key.json",
      zkeyProvenancePath,
    },
  });

  console.log(`Updated bridge Groth16 manifest: ${manifestPath}`);
  console.log(`Groth16 artifact source: ${process.env.BRIDGE_GROTH_SOURCE}`);
}

function syncTokamakZkpArtifactsForBridge(chainId, snapshotDir) {
  const tokamakCliRuntimeRoot = process.env.TOKAMAK_CLI_RUNTIME_ROOT;
  const tokamakSetupOutputDir = process.env.TOKAMAK_CLI_SETUP_OUTPUT_DIR;
  const artifactDir = path.join(snapshotDir, "tokamak-zkp");
  const manifestPath = path.join(snapshotDir, `tokamak-zkp.${chainId}.latest.json`);
  const combinedSigmaPath = path.join(tokamakSetupOutputDir, "combined_sigma.rkyv");
  const sigmaPreprocessPath = path.join(tokamakSetupOutputDir, "sigma_preprocess.rkyv");
  const sigmaVerifyPath = path.join(tokamakSetupOutputDir, "sigma_verify.json");
  const buildMetadataPath = path.join(tokamakSetupOutputDir, "build-metadata-mpc-setup.json");
  const crsProvenancePath = path.join(tokamakSetupOutputDir, "crs_provenance.json");

  assertFileExists(combinedSigmaPath, "required Tokamak zk proof artifact: combined_sigma.rkyv");
  assertFileExists(sigmaPreprocessPath, "required Tokamak zk proof artifact: sigma_preprocess.rkyv");
  assertFileExists(sigmaVerifyPath, "required Tokamak zk proof artifact: sigma_verify.json");
  assertFileExists(buildMetadataPath, "required Tokamak zk proof artifact: build-metadata-mpc-setup.json");

  if (typeof tokamakCliRuntimeRoot !== "string" || tokamakCliRuntimeRoot.length === 0) {
    fail("Missing TOKAMAK_CLI_RUNTIME_ROOT for Tokamak zk proof backend version checks");
  }
  const buildMetadata = readJson(buildMetadataPath);
  const artifactVersion = buildMetadata.packageVersion;
  if (typeof artifactVersion !== "string" || artifactVersion.length === 0) {
    fail(`Tokamak setup metadata has no packageVersion: ${buildMetadataPath}`);
  }
  const backendVersions = Object.fromEntries(
    ["preprocess", "prove", "verify"].map((binaryName) => [
      binaryName,
      readRuntimeBinaryVersion(tokamakCliRuntimeRoot, binaryName),
    ]),
  );
  const mismatchedBackendVersions = Object.entries(backendVersions)
    .filter(([, version]) => version !== artifactVersion);
  if (mismatchedBackendVersions.length > 0) {
    fail([
      "Tokamak setup metadata version does not match the installed backend binary versions.",
      `build-metadata-mpc-setup.json packageVersion: ${artifactVersion}`,
      `preprocess binary version: ${backendVersions.preprocess}`,
      `prove binary version: ${backendVersions.prove}`,
      `verify binary version: ${backendVersions.verify}`,
    ].join("\n"));
  }

  fs.rmSync(artifactDir, { recursive: true, force: true });
  copyFile(buildMetadataPath, path.join(artifactDir, "build-metadata-mpc-setup.json"));
  let relativeCrsProvenancePath = null;
  if (fs.existsSync(crsProvenancePath)) {
    copyFile(crsProvenancePath, path.join(artifactDir, "crs_provenance.json"));
    relativeCrsProvenancePath = "tokamak-zkp/crs_provenance.json";
  }

  writeJson(manifestPath, {
    generatedAtUtc: createTimestampLabel(),
    chainId: Number(chainId),
    tokamakZkpArtifactSource: "cli-runtime-cache",
    artifactDir: "tokamak-zkp",
    artifacts: {
      version: artifactVersion,
      buildMetadataPath: "tokamak-zkp/build-metadata-mpc-setup.json",
      crsProvenancePath: relativeCrsProvenancePath,
    },
  });

  console.log(`Updated bridge Tokamak zk proof manifest: ${manifestPath}`);
  console.log(`Tokamak setup output directory: ${tokamakSetupOutputDir}`);
}

function updateDeploymentAbiManifestPath(deploymentPath, canonicalAbiManifestPath) {
  const deployment = readJson(deploymentPath);
  deployment.abiManifestPath = path.basename(canonicalAbiManifestPath);
  writeJson(deploymentPath, deployment);
}

async function main() {
  const { deployMode, forwardArgs } = parseArgs(process.argv.slice(2));
  loadEnvFile();

  if (process.env.BRIDGE_DEPLOYER_PRIVATE_KEY && !process.env.BRIDGE_DEPLOYER_PRIVATE_KEY.startsWith("0x")) {
    process.env.BRIDGE_DEPLOYER_PRIVATE_KEY = `0x${process.env.BRIDGE_DEPLOYER_PRIVATE_KEY}`;
  }

  const requiredVars = ["BRIDGE_DEPLOYER_PRIVATE_KEY", "BRIDGE_NETWORK"];
  if (!process.env.BRIDGE_RPC_URL_OVERRIDE && process.env.BRIDGE_NETWORK !== "anvil") {
    requiredVars.push("BRIDGE_ALCHEMY_API_KEY");
  }
  requireEnv(requiredVars);

  const bridgeNetwork = resolveBridgeNetwork(process.env.BRIDGE_NETWORK);
  const bridgeChainId = bridgeNetwork.chainId;

  const effectiveGrothSource = process.env.BRIDGE_GROTH_SOURCE || "mpc";
  if (effectiveGrothSource !== "trusted" && effectiveGrothSource !== "mpc") {
    fail(`Unsupported BRIDGE_GROTH_SOURCE=${effectiveGrothSource}\nSupported values: trusted, mpc`);
  }
  process.env.BRIDGE_GROTH_SOURCE = effectiveGrothSource;

  if (deployMode !== "upgrade" && deployMode !== "redeploy-proxy") {
    fail(`Unsupported deploy mode: ${deployMode}\nSupported modes: upgrade, redeploy-proxy`);
  }

  let bridgeRpcUrl;
  let networkLabel;
  if (process.env.BRIDGE_RPC_URL_OVERRIDE) {
    bridgeRpcUrl = process.env.BRIDGE_RPC_URL_OVERRIDE;
    networkLabel = "<override>";
  } else if (bridgeNetwork.defaultRpcUrl) {
    bridgeRpcUrl = bridgeNetwork.defaultRpcUrl;
    networkLabel = "anvil-localhost";
  } else {
    bridgeRpcUrl = `https://${bridgeNetwork.alchemyNetwork}.g.alchemy.com/v2/${process.env.BRIDGE_ALCHEMY_API_KEY}`;
    networkLabel = bridgeNetwork.alchemyNetwork;
  }

  const uploadTimestamp = createTimestampLabel();
  const bridgeCanonicalDir = path.join(projectRoot, "deployment", `chain-id-${bridgeChainId}`, "bridge", uploadTimestamp);
  const bridgePendingDir = path.join(projectRoot, "deployment", ".pending", `chain-id-${bridgeChainId}`, "bridge", uploadTimestamp);
  const latestBridgeDir = latestCompleteBridgeDir(path.join(projectRoot, "deployment", `chain-id-${bridgeChainId}`, "bridge"), bridgeChainId);
  const defaultBridgeInputPath = latestBridgeDir
    ? path.join(latestBridgeDir, `bridge.${bridgeChainId}.json`)
    : `./deployments/bridge.${bridgeChainId}.json`;
  const externalZkManifestPath = process.env.BRIDGE_REFLECTION_MANIFEST_PATH
    ? resolveBridgePath(process.env.BRIDGE_REFLECTION_MANIFEST_PATH)
    : "";
  const bridgePendingZkManifestPath = path.join(bridgePendingDir, "zk-reflection.latest.json");
  const canonicalZkManifestPath = path.join(bridgeCanonicalDir, "zk-reflection.latest.json");

  loadTokamakCliEntryContext();

  if (process.env.BRIDGE_SKIP_TOKAMAK_INSTALL === "1") {
    console.log("Skipping tokamak-cli runtime install because BRIDGE_SKIP_TOKAMAK_INSTALL=1");
  } else {
    runTokamakCliInstall();
  }

  await loadTokamakRuntimeContext();

  if (process.env.BRIDGE_SKIP_TOKAMAK_VERIFIER_REFRESH === "1") {
    console.log("Skipping Tokamak verifier Solidity refresh because BRIDGE_SKIP_TOKAMAK_VERIFIER_REFRESH=1");
  } else {
    refreshTokamakVerifierSolidity();
  }

  await refreshBridgeZkConstants();

  process.env.BRIDGE_TOKAMAK_COMPATIBLE_BACKEND_VERSION =
    await fetchLatestNpmPackageVersion(TOKAMAK_CLI_PACKAGE_NAME);
  const groth16LatestPackageVersion = await fetchLatestNpmPackageVersion(GROTH16_NPM_PACKAGE_NAME);
  process.env.BRIDGE_GROTH_COMPATIBLE_BACKEND_VERSION =
    normalizeGroth16CompatibleBackendVersion(
      groth16LatestPackageVersion,
      `${GROTH16_NPM_PACKAGE_NAME} npm latest version`,
    );
  if (process.env.BRIDGE_GROTH_SOURCE === "mpc") {
    await assertLatestPublicGroth16MpcArchiveVersion(process.env.BRIDGE_GROTH_COMPATIBLE_BACKEND_VERSION, {
      expectedVersionLabel: `${GROTH16_NPM_PACKAGE_NAME} npm latest compatible backend version`,
    });
  }

  if (process.env.BRIDGE_SKIP_GROTH_REFRESH === "1") {
    console.log("Skipping Groth16 verifier Solidity refresh because BRIDGE_SKIP_GROTH_REFRESH=1");
  } else {
    await refreshGroth16VerifierSolidity(process.env.BRIDGE_GROTH_SOURCE);
  }

  await writeBridgeZkManifest(bridgePendingZkManifestPath, process.env.BRIDGE_GROTH_SOURCE);

  const mtDepthMetadata = readJson(bridgePendingZkManifestPath);
  const bridgeMerkleTreeLevels = String(mtDepthMetadata.tokamakL2js.mtDepth);
  const bridgeMerkleTreeSourceVersion = String(mtDepthMetadata.tokamakL2js.package.version);
  process.env.BRIDGE_MERKLE_TREE_LEVELS = bridgeMerkleTreeLevels;

  const canonicalBridgeOutputPath = resolveBridgePath(
    process.env.BRIDGE_OUTPUT_PATH || path.join(bridgeCanonicalDir, `bridge.${bridgeChainId}.json`),
  );
  const canonicalBridgeInputPath = resolveBridgePath(process.env.BRIDGE_INPUT_PATH || defaultBridgeInputPath);
  const bridgePendingOutputPath = path.join(bridgePendingDir, path.basename(canonicalBridgeOutputPath));
  process.env.BRIDGE_OUTPUT_PATH = bridgePendingOutputPath;
  process.env.BRIDGE_INPUT_PATH = canonicalBridgeInputPath;
  process.env.BRIDGE_ARTIFACT_TIMESTAMP = uploadTimestamp;

  let forgeScript = "scripts/UpgradeBridgeStack.s.sol:UpgradeBridgeStackScript";
  if (deployMode === "redeploy-proxy") {
    forgeScript = "scripts/DeployBridgeStack.s.sol:DeployBridgeStackScript";
  } else {
    if (!fs.existsSync(canonicalBridgeInputPath)) {
      fail([
        `Missing proxy deployment artifact for upgrade mode: ${canonicalBridgeInputPath}`,
        "Run with --mode redeploy-proxy once to bootstrap proxy addresses on this network.",
      ].join("\n"));
    }
    const existingProxyKind = String(readJson(canonicalBridgeInputPath).proxyKind || "");
    if (existingProxyKind !== "uups") {
      fail([
        `Deployment artifact is not proxy-based: ${canonicalBridgeInputPath}`,
        "Run with --mode redeploy-proxy to replace it with a proxy deployment.",
      ].join("\n"));
    }
  }

  const forgeCmdArgs = [
    "script",
    forgeScript,
    "--sig",
    "run()",
    "--broadcast",
    "--rpc-url",
    bridgeRpcUrl,
    ...forwardArgs,
  ];

  console.log(`Deploying bridge to network ${process.env.BRIDGE_NETWORK} (chain ID ${bridgeChainId})`);
  console.log(`Deployment mode: ${deployMode}`);
  console.log(`RPC network label: ${networkLabel}`);
  console.log(`Environment file: ${envFile}`);
  console.log(`Resolved tokamak-l2js version: ${bridgeMerkleTreeSourceVersion}`);
  console.log(`Resolved tokamak-l2js MT_DEPTH: ${bridgeMerkleTreeLevels}`);
  console.log(
    `Resolved ${TOKAMAK_CLI_PACKAGE_NAME} latest version: ${process.env.BRIDGE_TOKAMAK_COMPATIBLE_BACKEND_VERSION}`,
  );
  console.log(
    `Resolved ${GROTH16_NPM_PACKAGE_NAME} compatible backend version: ${process.env.BRIDGE_GROTH_COMPATIBLE_BACKEND_VERSION}`,
  );
  console.log(
    `Resolved ${GROTH16_NPM_PACKAGE_NAME} latest package version: ${groth16LatestPackageVersion}`,
  );
  console.log(`Groth16 artifact source: ${process.env.BRIDGE_GROTH_SOURCE}`);
  console.log(`ZK manifest: ${bridgePendingZkManifestPath}`);

  if (process.env.BRIDGE_NETWORK !== "anvil" && process.env.BRIDGE_SKIP_ARTIFACT_UPLOAD !== "1") {
    run("node", [
      path.join(projectRoot, "bridge", "scripts", "upload-bridge-artifacts.mjs"),
      String(bridgeChainId),
      "--timestamp",
      uploadTimestamp,
      "--preflight",
    ]);
  } else if (process.env.BRIDGE_SKIP_ARTIFACT_UPLOAD === "1") {
    console.log("Skipping bridge artifact upload preflight because BRIDGE_SKIP_ARTIFACT_UPLOAD=1");
  }

  fs.mkdirSync(bridgePendingDir, { recursive: true });
  run("forge", forgeCmdArgs, { cwd: bridgeRoot });

  cleanupBroadcastTraces(
    deployMode === "redeploy-proxy" ? "DeployBridgeStack.s.sol" : "UpgradeBridgeStack.s.sol",
    bridgeChainId,
  );

  const bridgePendingOutputPathAbs = resolveBridgePath(process.env.BRIDGE_OUTPUT_PATH);
  const bridgeAbiManifestPath = path.join(bridgeCanonicalDir, `bridge-abi-manifest.${bridgeChainId}.json`);
  const bridgeAbiManifestPathAbs = resolveBridgePath(bridgeAbiManifestPath);
  const bridgePendingAbiManifestPath = path.join(bridgePendingDir, path.basename(bridgeAbiManifestPathAbs));

  run("node", [
    path.join(projectRoot, "bridge", "scripts", "generate-bridge-abi-manifest.mjs"),
    "--output",
    bridgePendingAbiManifestPath,
    "--chain-id",
    String(bridgeChainId),
    "--deployment-path",
    bridgePendingOutputPathAbs,
  ], { stdio: ["ignore", "ignore", "inherit"] });

  updateDeploymentAbiManifestPath(bridgePendingOutputPathAbs, bridgeAbiManifestPathAbs);
  syncGroth16ArtifactsForBridge(bridgeChainId, bridgePendingDir);
  syncTokamakZkpArtifactsForBridge(bridgeChainId, bridgePendingDir);

  if (process.env.BRIDGE_NETWORK !== "anvil" && process.env.BRIDGE_SKIP_ARTIFACT_UPLOAD !== "1") {
    run("node", [
      path.join(projectRoot, "bridge", "scripts", "upload-bridge-artifacts.mjs"),
      String(bridgeChainId),
      "--timestamp",
      uploadTimestamp,
      "--deployment-path",
      bridgePendingOutputPathAbs,
      "--abi-manifest-path",
      bridgePendingAbiManifestPath,
    ]);
  } else if (process.env.BRIDGE_SKIP_ARTIFACT_UPLOAD === "1") {
    console.log("Skipping bridge artifact upload because BRIDGE_SKIP_ARTIFACT_UPLOAD=1");
  }

  fs.mkdirSync(path.dirname(bridgeCanonicalDir), { recursive: true });
  if (fs.existsSync(bridgeCanonicalDir)) {
    fail(`Refusing to overwrite existing bridge deployment snapshot: ${bridgeCanonicalDir}`);
  }
  fs.renameSync(bridgePendingDir, bridgeCanonicalDir);

  const publishedBridgeOutputPath = path.join(bridgeCanonicalDir, path.basename(canonicalBridgeOutputPath));
  if (publishedBridgeOutputPath !== canonicalBridgeOutputPath) {
    copyFile(publishedBridgeOutputPath, canonicalBridgeOutputPath);
  }
  if (externalZkManifestPath) {
    copyFile(canonicalZkManifestPath, externalZkManifestPath);
  }

  console.log(`Deployment artifact: ${publishedBridgeOutputPath}`);
  console.log(`ABI manifest: ${bridgeAbiManifestPathAbs}`);
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : String(error));
  process.exit(1);
});

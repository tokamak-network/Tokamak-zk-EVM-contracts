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

run_tokamak_cli_install() {
    node --input-type=module - "$PROJECT_ROOT" <<'NODE'
import { spawnSync } from "node:child_process";
import path from "node:path";
import { pathToFileURL } from "node:url";

const repoRoot = process.argv[2];
const runtimePaths = await import(pathToFileURL(path.join(repoRoot, "scripts/zk/lib/tokamak-runtime-paths.mjs")).href);
const invocation = runtimePaths.buildTokamakCliInvocation(["--install"]);
const result = spawnSync(invocation.command, invocation.args, {
  cwd: repoRoot,
  stdio: "inherit",
  env: process.env,
});

if (result.error) {
  throw result.error;
}
if (result.status !== 0) {
  process.exit(result.status ?? 1);
}
NODE
}

refresh_tokamak_verifier_solidity() {
    node --input-type=module - "$PROJECT_ROOT" <<'NODE'
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";

const repoRoot = process.argv[2];
const runtimePaths = await import(pathToFileURL(path.join(repoRoot, "scripts/zk/lib/tokamak-runtime-paths.mjs")).href);
const installedSigmaVerifyJsonPath = runtimePaths.resolveTokamakCliSetupArtifactPath("sigma_verify.json");
const setupParamsPath = runtimePaths.resolveSubcircuitSetupParamsPath();
const sigmaVerifyJsonPath = path.join(repoRoot, "tokamak-zkp", "TokamakVerifierKey", "sigma_verify.json");

function assertFile(filePath, label) {
  if (!fs.existsSync(filePath)) {
    throw new Error(`Missing ${label}: ${filePath}`);
  }
}

function run(args) {
  const result = spawnSync(process.execPath, args, {
    cwd: repoRoot,
    stdio: "inherit",
    env: process.env,
  });
  if (result.error) {
    throw result.error;
  }
  if (result.status !== 0) {
    process.exit(result.status ?? 1);
  }
}

assertFile(installedSigmaVerifyJsonPath, "Tokamak sigma_verify.json");
assertFile(setupParamsPath, "Tokamak setupParams.json");
fs.mkdirSync(path.dirname(sigmaVerifyJsonPath), { recursive: true });
fs.copyFileSync(installedSigmaVerifyJsonPath, sigmaVerifyJsonPath);

run([path.join(repoRoot, "scripts/generate-tokamak-verifier-key.js")]);
run([path.join(repoRoot, "scripts/generate-tokamak-verifier-params.js")]);
NODE
}

refresh_bridge_zk_constants() {
    node --input-type=module - "$PROJECT_ROOT" <<'NODE'
import { spawnSync } from "node:child_process";
import path from "node:path";
import { pathToFileURL } from "node:url";

const repoRoot = process.argv[2];
const runtimePaths = await import(pathToFileURL(path.join(repoRoot, "scripts/zk/lib/tokamak-runtime-paths.mjs")).href);
const setupParamsPath = runtimePaths.resolveSubcircuitSetupParamsPath();

function run(args) {
  const result = spawnSync(process.execPath, args, {
    cwd: repoRoot,
    stdio: "inherit",
    env: process.env,
  });
  if (result.error) {
    throw result.error;
  }
  if (result.status !== 0) {
    process.exit(result.status ?? 1);
  }
}

run([path.join(repoRoot, "scripts/generate-tokamak-shared-constants.js"), setupParamsPath]);
run([path.join(repoRoot, "scripts/groth16/render-update-tree-circuit.mjs")]);
NODE
}

refresh_groth16_verifier_solidity() {
    local groth_source="$1"
    local groth_crs_dir
    local groth_verification_key_path
    local groth_verifier_output_path="$PROJECT_ROOT/groth16/verifier/src/Groth16Verifier.sol"

    case "$groth_source" in
        trusted)
            node "$PROJECT_ROOT/scripts/groth16/trusted-setup/generate_update_tree_setup.mjs"
            groth_crs_dir="$PROJECT_ROOT/groth16/trusted-setup/crs"
            ;;
        mpc)
            groth_crs_dir="$PROJECT_ROOT/groth16/mpc-setup/crs"
            node --input-type=module - "$PROJECT_ROOT" "$groth_crs_dir" <<'NODE'
import path from "node:path";
import { pathToFileURL } from "node:url";

const repoRoot = process.argv[2];
const outputDir = process.argv[3];
const publicDriveCrs = await import(pathToFileURL(path.join(repoRoot, "groth16/lib/public-drive-crs.mjs")).href);
const result = await publicDriveCrs.downloadLatestPublicGroth16MpcArtifacts({
  outputDir,
  selectedFiles: [
    "circuit_final.zkey",
    "verification_key.json",
    "metadata.json",
    "zkey_provenance.json",
  ],
});
console.log(`Downloaded Groth16 MPC archive: ${result.archiveName}`);
NODE
            ;;
        *)
            echo "Unsupported BRIDGE_GROTH_SOURCE=$groth_source" >&2
            echo "Supported values: trusted, mpc" >&2
            exit 1
            ;;
    esac

    groth_verification_key_path="$groth_crs_dir/verification_key.json"
    python3 "$PROJECT_ROOT/scripts/groth16/verifier/generate_update_tree_verifier.py" \
        "$groth_verification_key_path" \
        "$groth_verifier_output_path"
}

write_bridge_zk_manifest() {
    local manifest_path="$1"
    local groth_source="$2"

    node --input-type=module - "$PROJECT_ROOT" "$manifest_path" "$groth_source" <<'NODE'
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";

const repoRoot = process.argv[2];
const manifestPath = process.argv[3];
const grothSource = process.argv[4];
const runtimePaths = await import(pathToFileURL(path.join(repoRoot, "scripts/zk/lib/tokamak-runtime-paths.mjs")).href);

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function runCapture(args) {
  const result = spawnSync(process.execPath, args, {
    cwd: repoRoot,
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
    env: process.env,
  });
  if (result.error) {
    throw result.error;
  }
  if (result.status !== 0) {
    throw new Error([
      `Command failed: node ${args.join(" ")}`,
      result.stdout?.trim(),
      result.stderr?.trim(),
    ].filter(Boolean).join("\n"));
  }
  return result.stdout;
}

function grothCrsDirFor(source) {
  if (source === "trusted") {
    return path.join(repoRoot, "groth16", "trusted-setup", "crs");
  }
  if (source === "mpc") {
    return path.join(repoRoot, "groth16", "mpc-setup", "crs");
  }
  throw new Error(`Unsupported Groth16 source: ${source}`);
}

const tokamakCliPackageRoot = runtimePaths.resolveTokamakCliPackageRoot();
const tokamakL2js = JSON.parse(runCapture([path.join(repoRoot, "bridge/scripts/resolve-latest-mt-depth.mjs")]));
const setupParamsPath = runtimePaths.resolveSubcircuitSetupParamsPath();
const grothCrsDir = grothCrsDirFor(grothSource);
const manifest = {
  generatedAt: new Date().toISOString(),
  tokamakRuntime: {
    cliPackageRoot: tokamakCliPackageRoot,
    cliVersion: readJson(path.join(tokamakCliPackageRoot, "package.json")).version,
    cacheRoot: runtimePaths.resolveTokamakCliCacheRoot(),
    runtimeRoot: runtimePaths.resolveTokamakCliRuntimeRoot(),
    setupParamsPath,
    installedSigmaVerifyJsonPath: runtimePaths.resolveTokamakCliSetupArtifactPath("sigma_verify.json"),
  },
  tokamakL2js,
  tokamakVerifier: {
    sigmaVerifyJsonPath: path.join(repoRoot, "tokamak-zkp", "TokamakVerifierKey", "sigma_verify.json"),
    generatedVerifierKeyPath: path.join(repoRoot, "tokamak-zkp", "TokamakVerifierKey", "TokamakVerifierKey.generated.sol"),
    verifierSourcePath: path.join(repoRoot, "tokamak-zkp", "TokamakVerifier.sol"),
    setupParams: readJson(setupParamsPath),
  },
  groth16: {
    source: grothSource,
    verificationKeyPath: path.join(grothCrsDir, "verification_key.json"),
    verifierPath: path.join(repoRoot, "groth16", "verifier", "src", "Groth16Verifier.sol"),
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

if [[ "${BRIDGE_SKIP_TOKAMAK_INSTALL:-0}" == "1" ]]; then
    echo "Skipping tokamak-cli runtime install because BRIDGE_SKIP_TOKAMAK_INSTALL=1"
else
    run_tokamak_cli_install
fi

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

GROTH_ARTIFACT_SOURCE="$BRIDGE_GROTH_SOURCE" \
    bash "$PROJECT_ROOT/bridge/scripts/sync-groth16-artifacts.sh" "$BRIDGE_CHAIN_ID"

node "$PROJECT_ROOT/bridge/scripts/sync-tokamak-zkp-artifacts.mjs" "$BRIDGE_CHAIN_ID"

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

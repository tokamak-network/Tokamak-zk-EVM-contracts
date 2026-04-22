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
elif [[ "${BRIDGE_NETWORK}" == "mainnet" ]]; then
    EFFECTIVE_BRIDGE_GROTH_SOURCE="mpc"
else
    EFFECTIVE_BRIDGE_GROTH_SOURCE="trusted"
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

REFLECTION_MANIFEST_PATH="${BRIDGE_REFLECTION_MANIFEST_PATH:-$PROJECT_ROOT/scripts/zk/artifacts/reflection.latest.json}"

REFLECTION_CMD=(
    node "$PROJECT_ROOT/scripts/zk/reflect-submodule-updates.mjs"
    --manifest-out "$REFLECTION_MANIFEST_PATH"
    --groth-source "$BRIDGE_GROTH_SOURCE"
)

if [[ "${BRIDGE_SKIP_TOKAMAK_INSTALL:-0}" == "1" ]]; then
    REFLECTION_CMD+=("--skip-install")
fi

if [[ "${BRIDGE_SKIP_TOKAMAK_VERIFIER_REFRESH:-0}" == "1" ]]; then
    REFLECTION_CMD+=("--skip-tokamak-verifier")
fi

if [[ "${BRIDGE_SKIP_GROTH_REFRESH:-0}" == "1" ]]; then
    REFLECTION_CMD+=("--skip-groth")
fi

"${REFLECTION_CMD[@]}"

MT_DEPTH_METADATA="$(cat "$REFLECTION_MANIFEST_PATH")"
BRIDGE_MERKLE_TREE_LEVELS="$(printf '%s' "$MT_DEPTH_METADATA" | node -e 'process.stdin.on("data",(buf)=>{const parsed=JSON.parse(String(buf)); process.stdout.write(String(parsed.tokamakL2js.mtDepth));});')"
BRIDGE_MERKLE_TREE_SOURCE_VERSION="$(printf '%s' "$MT_DEPTH_METADATA" | node -e 'process.stdin.on("data",(buf)=>{const parsed=JSON.parse(String(buf)); process.stdout.write(String(parsed.tokamakL2js.version));});')"
export BRIDGE_MERKLE_TREE_LEVELS
BRIDGE_OUTPUT_PATH="${BRIDGE_OUTPUT_PATH:-./deployments/bridge.${BRIDGE_CHAIN_ID}.json}"
BRIDGE_INPUT_PATH="${BRIDGE_INPUT_PATH:-$BRIDGE_OUTPUT_PATH}"
BRIDGE_OUTPUT_PATH="$(resolve_bridge_path "$BRIDGE_OUTPUT_PATH")"
BRIDGE_INPUT_PATH="$(resolve_bridge_path "$BRIDGE_INPUT_PATH")"
export BRIDGE_OUTPUT_PATH
export BRIDGE_INPUT_PATH

BRIDGE_OUTPUT_PATH_ABS_FOR_MODE="$BRIDGE_OUTPUT_PATH"
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
echo "Reflection manifest: ${REFLECTION_MANIFEST_PATH}"

(
    cd "$PROJECT_ROOT/bridge"
    "${FORGE_CMD[@]}"
)

if [[ "${DEPLOY_MODE}" == "redeploy-proxy" ]]; then
    cleanup_broadcast_traces "DeployBridgeStack.s.sol" "$BRIDGE_CHAIN_ID"
else
    cleanup_broadcast_traces "UpgradeBridgeStack.s.sol" "$BRIDGE_CHAIN_ID"
fi

BRIDGE_OUTPUT_PATH_ABS="$(resolve_bridge_path "$BRIDGE_OUTPUT_PATH")"
BRIDGE_ABI_MANIFEST_PATH="./deployments/bridge-abi-manifest.${BRIDGE_CHAIN_ID}.json"
BRIDGE_ABI_MANIFEST_PATH_ABS="$(resolve_bridge_path "$BRIDGE_ABI_MANIFEST_PATH")"

node "$PROJECT_ROOT/bridge/scripts/generate-bridge-abi-manifest.mjs" \
    --output "$BRIDGE_ABI_MANIFEST_PATH_ABS" \
    --chain-id "$BRIDGE_CHAIN_ID" \
    --deployment-path "$BRIDGE_OUTPUT_PATH_ABS" >/dev/null

GROTH_ARTIFACT_SOURCE="$BRIDGE_GROTH_SOURCE" \
    bash "$PROJECT_ROOT/bridge/scripts/sync-groth16-artifacts.sh" "$BRIDGE_CHAIN_ID"

node "$PROJECT_ROOT/bridge/scripts/sync-tokamak-zkp-artifacts.mjs" "$BRIDGE_CHAIN_ID"

echo "Deployment artifact: $BRIDGE_OUTPUT_PATH_ABS"
echo "ABI manifest: $BRIDGE_ABI_MANIFEST_PATH_ABS"

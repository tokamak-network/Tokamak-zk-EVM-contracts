#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
ENV_FILE="${APPS_ENV_FILE:-$PROJECT_ROOT/apps/.env}"
source "$PROJECT_ROOT/apps/script/network-config.sh"

if [[ ! -f "$ENV_FILE" ]]; then
    echo "Missing $ENV_FILE"
    exit 1
fi

set -a
source "$ENV_FILE"
set +a

if [[ -n "${APPS_DEPLOYER_PRIVATE_KEY:-}" && "${APPS_DEPLOYER_PRIVATE_KEY}" != 0x* ]]; then
    APPS_DEPLOYER_PRIVATE_KEY="0x${APPS_DEPLOYER_PRIVATE_KEY}"
    export APPS_DEPLOYER_PRIVATE_KEY
fi

VERIFY_FLAG=""
if [[ "${1:-}" == "--verify" ]]; then
    VERIFY_FLAG="--verify"
fi

required_vars=(
    "APPS_DEPLOYER_PRIVATE_KEY"
    "APPS_NETWORK"
)

if [[ -z "${APPS_RPC_URL_OVERRIDE:-}" && "${APPS_NETWORK:-}" != "anvil" ]]; then
    required_vars+=("APPS_ALCHEMY_API_KEY")
fi

for var_name in "${required_vars[@]}"; do
    if [[ -z "${!var_name:-}" ]]; then
        echo "Missing required environment variable: $var_name"
        exit 1
    fi
done

resolve_app_network "$APPS_NETWORK"

if [[ -n "$VERIFY_FLAG" && -z "${APPS_ETHERSCAN_API_KEY:-}" ]]; then
    echo "APPS_ETHERSCAN_API_KEY is required when --verify is used"
    exit 1
fi

if [[ -n "${APPS_RPC_URL_OVERRIDE:-}" ]]; then
    APPS_RPC_URL="$APPS_RPC_URL_OVERRIDE"
    NETWORK_LABEL="<override>"
elif [[ "$APPS_NETWORK" == "anvil" ]]; then
    APPS_RPC_URL="http://127.0.0.1:8545"
    NETWORK_LABEL="anvil-localhost"
else
    if [[ -z "$APPS_ALCHEMY_NETWORK" ]]; then
        echo "Unsupported APPS_NETWORK=$APPS_NETWORK without an explicit APPS_RPC_URL_OVERRIDE" >&2
        exit 1
    fi

    NETWORK_LABEL="$APPS_ALCHEMY_NETWORK"
    APPS_RPC_URL="https://${APPS_ALCHEMY_NETWORK}.g.alchemy.com/v2/${APPS_ALCHEMY_API_KEY}"
fi

FORGE_CMD=(
    forge script apps/private-state/script/deploy/DeployPrivateState.s.sol:DeployPrivateStateScript
    --rpc-url "$APPS_RPC_URL"
    --broadcast
)

if [[ -n "$VERIFY_FLAG" ]]; then
    FORGE_CMD+=(--verify --etherscan-api-key "$APPS_ETHERSCAN_API_KEY")
fi

echo "Deploying private-state to network $APPS_NETWORK (chain ID $APPS_CHAIN_ID)"
echo "RPC network label: $NETWORK_LABEL"
echo "Owner: <deployer>"
echo "Environment file: $ENV_FILE"

(
    cd "$PROJECT_ROOT"
    "${FORGE_CMD[@]}"
)

bash "$PROJECT_ROOT/apps/private-state/script/deploy/write-deploy-artifacts.sh" "$APPS_CHAIN_ID"

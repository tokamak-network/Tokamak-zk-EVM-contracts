#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENV_FILE="${BRIDGE_ENV_FILE:-$PROJECT_ROOT/.env}"

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

FORGE_CMD=(
    forge script script/DeployBridgeStack.s.sol:DeployBridgeStackScript
    --sig "run()"
    --broadcast
    --rpc-url "$BRIDGE_RPC_URL"
)

if [[ $# -gt 0 ]]; then
    FORGE_CMD+=("$@")
fi

echo "Deploying bridge to network ${BRIDGE_NETWORK} (chain ID ${BRIDGE_CHAIN_ID})"
echo "RPC network label: ${NETWORK_LABEL}"
echo "Environment file: ${ENV_FILE}"

(
    cd "$PROJECT_ROOT/bridge"
    "${FORGE_CMD[@]}"
)

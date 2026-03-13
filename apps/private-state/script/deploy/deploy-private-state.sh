#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
ENV_FILE="${APPS_ENV_FILE:-$PROJECT_ROOT/apps/.env}"

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
    "APPS_CHAIN_ID"
    "PRIVATE_STATE_CANONICAL_ASSET"
)

if [[ -z "${APPS_RPC_URL_OVERRIDE:-}" ]]; then
    required_vars+=("APPS_ALCHEMY_API_KEY")
fi

for var_name in "${required_vars[@]}"; do
    if [[ -z "${!var_name:-}" ]]; then
        echo "Missing required environment variable: $var_name"
        exit 1
    fi
done

alchemy_network() {
    case "$1" in
        11155111) echo "eth-sepolia" ;;
        1) echo "eth-mainnet" ;;
        84532) echo "base-sepolia" ;;
        8453) echo "base-mainnet" ;;
        421614) echo "arb-sepolia" ;;
        42161) echo "arb-mainnet" ;;
        10) echo "opt-mainnet" ;;
        11155420) echo "opt-sepolia" ;;
        *)
            echo "Unsupported APPS_CHAIN_ID for Alchemy RPC derivation: $1" >&2
            exit 1
            ;;
    esac
}

if [[ -n "$VERIFY_FLAG" && -z "${APPS_ETHERSCAN_API_KEY:-}" ]]; then
    echo "APPS_ETHERSCAN_API_KEY is required when --verify is used"
    exit 1
fi

if [[ -n "${APPS_RPC_URL_OVERRIDE:-}" ]]; then
    APPS_RPC_URL="$APPS_RPC_URL_OVERRIDE"
    ALCHEMY_NETWORK="<override>"
else
    ALCHEMY_NETWORK="$(alchemy_network "$APPS_CHAIN_ID")"
    APPS_RPC_URL="https://${ALCHEMY_NETWORK}.g.alchemy.com/v2/${APPS_ALCHEMY_API_KEY}"
fi

FORGE_CMD=(
    forge script apps/private-state/script/deploy/DeployPrivateState.s.sol:DeployPrivateStateScript
    --rpc-url "$APPS_RPC_URL"
    --broadcast
)

if [[ -n "$VERIFY_FLAG" ]]; then
    FORGE_CMD+=(--verify --etherscan-api-key "$APPS_ETHERSCAN_API_KEY")
fi

echo "Deploying private-state to chain ID $APPS_CHAIN_ID"
echo "Alchemy network: $ALCHEMY_NETWORK"
echo "Canonical asset: $PRIVATE_STATE_CANONICAL_ASSET"
echo "Owner: <deployer>"
echo "Environment file: $ENV_FILE"

(
    cd "$PROJECT_ROOT"
    "${FORGE_CMD[@]}"
)

bash "$PROJECT_ROOT/apps/private-state/script/deploy/write-deploy-artifacts.sh" "$APPS_CHAIN_ID"

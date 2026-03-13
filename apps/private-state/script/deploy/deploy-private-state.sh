#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
ENV_FILE="$PROJECT_ROOT/apps/.env"

if [[ ! -f "$ENV_FILE" ]]; then
    echo "Missing $ENV_FILE"
    exit 1
fi

set -a
source "$ENV_FILE"
set +a

VERIFY_FLAG=""
if [[ "${1:-}" == "--verify" ]]; then
    VERIFY_FLAG="--verify"
fi

required_vars=(
    "PRIVATE_STATE_PRIVATE_KEY"
    "PRIVATE_STATE_RPC_URL"
    "PRIVATE_STATE_CHAIN_ID"
    "PRIVATE_STATE_CANONICAL_ASSET"
)

for var_name in "${required_vars[@]}"; do
    if [[ -z "${!var_name:-}" ]]; then
        echo "Missing required environment variable: $var_name"
        exit 1
    fi
done

if [[ -n "$VERIFY_FLAG" && -z "${PRIVATE_STATE_ETHERSCAN_API_KEY:-}" ]]; then
    echo "PRIVATE_STATE_ETHERSCAN_API_KEY is required when --verify is used"
    exit 1
fi

FORGE_CMD=(
    forge script apps/private-state/script/deploy/DeployPrivateState.s.sol:DeployPrivateStateScript
    --rpc-url "$PRIVATE_STATE_RPC_URL"
    --broadcast
)

if [[ -n "$VERIFY_FLAG" ]]; then
    FORGE_CMD+=(--verify --etherscan-api-key "$PRIVATE_STATE_ETHERSCAN_API_KEY")
fi

echo "Deploying private-state to chain ID $PRIVATE_STATE_CHAIN_ID"
echo "Canonical asset: $PRIVATE_STATE_CANONICAL_ASSET"
echo "Final owner: ${PRIVATE_STATE_OWNER:-<deployer>}"
echo "Environment file: $ENV_FILE"

(
    cd "$PROJECT_ROOT"
    "${FORGE_CMD[@]}"
)

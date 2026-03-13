#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENV_FILE="$PROJECT_ROOT/.env"

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

required_vars=("PRIVATE_KEY" "RPC_URL" "CHAIN_ID" "PRIVATE_STATE_CANONICAL_ASSET")
for var_name in "${required_vars[@]}"; do
    if [[ -z "${!var_name:-}" ]]; then
        echo "Missing required environment variable: $var_name"
        exit 1
    fi
done

if [[ -n "$VERIFY_FLAG" && -z "${ETHERSCAN_API_KEY:-}" ]]; then
    echo "ETHERSCAN_API_KEY is required when --verify is used"
    exit 1
fi

FORGE_CMD=(
    forge script script/deploy/DeployPrivateState.s.sol:DeployPrivateStateScript
    --rpc-url "$RPC_URL"
    --broadcast
)

if [[ -n "$VERIFY_FLAG" ]]; then
    FORGE_CMD+=(--verify --etherscan-api-key "$ETHERSCAN_API_KEY")
fi

echo "Deploying private-state to chain ID $CHAIN_ID"
echo "Canonical asset: $PRIVATE_STATE_CANONICAL_ASSET"
echo "Final owner: ${PRIVATE_STATE_OWNER:-<deployer>}"

(
    cd "$PROJECT_ROOT"
    "${FORGE_CMD[@]}"
)

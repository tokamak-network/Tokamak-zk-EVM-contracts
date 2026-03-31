#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
ENV_FILE="${APPS_ENV_FILE:-$PROJECT_ROOT/apps/.env}"
TEMP_ENV_FILE="$(mktemp /tmp/private-state-anvil.env.XXXXXX)"
source "$PROJECT_ROOT/apps/scripts/network-config.sh"

ANVIL_DEFAULT_DEPLOYER_PRIVATE_KEY="0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"

cleanup() {
    rm -f "$TEMP_ENV_FILE"
}
trap cleanup EXIT

if [[ -f "$ENV_FILE" ]]; then
    set -a
    source "$ENV_FILE"
    set +a
fi

if [[ -n "${APPS_DEPLOYER_PRIVATE_KEY:-}" && "${APPS_DEPLOYER_PRIVATE_KEY}" != 0x* ]]; then
    APPS_DEPLOYER_PRIVATE_KEY="0x${APPS_DEPLOYER_PRIVATE_KEY}"
    export APPS_DEPLOYER_PRIVATE_KEY
fi

# The anvil bootstrap flow must not depend on apps/.env being present or set to an anvil network.
APPS_RPC_URL="${APPS_RPC_URL_OVERRIDE:-http://127.0.0.1:8545}"
APPS_NETWORK="anvil"
resolve_app_network "$APPS_NETWORK"

APPS_DEPLOYER_PRIVATE_KEY="${APPS_ANVIL_DEPLOYER_PRIVATE_KEY:-$ANVIL_DEFAULT_DEPLOYER_PRIVATE_KEY}"
export APPS_DEPLOYER_PRIVATE_KEY

if ! curl -sS \
    -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' \
    "$APPS_RPC_URL" >/dev/null 2>&1; then
    echo "anvil is not reachable at $APPS_RPC_URL" >&2
    exit 1
fi

export APPS_RPC_URL_OVERRIDE="$APPS_RPC_URL"
cat > "$TEMP_ENV_FILE" <<EOF
APPS_NETWORK=anvil
APPS_DEPLOYER_PRIVATE_KEY=$APPS_DEPLOYER_PRIVATE_KEY
EOF

APPS_ENV_FILE="$TEMP_ENV_FILE" bash "$PROJECT_ROOT/apps/private-state/scripts/deploy/deploy-private-state.sh"

echo "Bootstrapped private-state on anvil"
echo "RPC URL: $APPS_RPC_URL"
echo "Anvil deployer: $(cast wallet address --private-key "$APPS_DEPLOYER_PRIVATE_KEY")"
echo "Deployment manifest: $PROJECT_ROOT/apps/private-state/deploy/deployment.${APPS_CHAIN_ID}.latest.json"

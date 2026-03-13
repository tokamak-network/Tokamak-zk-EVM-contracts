#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
ENV_FILE="$PROJECT_ROOT/apps/.env"
TEMP_ENV_FILE="$(mktemp /tmp/private-state-anvil.env.XXXXXX)"

if [[ ! -f "$ENV_FILE" ]]; then
    echo "Missing $ENV_FILE" >&2
    exit 1
fi

cleanup() {
    rm -f "$TEMP_ENV_FILE"
}
trap cleanup EXIT

set -a
source "$ENV_FILE"
set +a

if [[ -n "${APPS_DEPLOYER_PRIVATE_KEY:-}" && "${APPS_DEPLOYER_PRIVATE_KEY}" != 0x* ]]; then
    APPS_DEPLOYER_PRIVATE_KEY="0x${APPS_DEPLOYER_PRIVATE_KEY}"
    export APPS_DEPLOYER_PRIVATE_KEY
fi

APPS_RPC_URL="${APPS_RPC_URL_OVERRIDE:-http://127.0.0.1:8545}"
APPS_CHAIN_ID="${APPS_CHAIN_ID:-31337}"

if ! curl -sS \
    -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' \
    "$APPS_RPC_URL" >/dev/null 2>&1; then
    echo "anvil is not reachable at $APPS_RPC_URL" >&2
    exit 1
fi

(
    cd "$PROJECT_ROOT"
    forge script apps/private-state/script/anvil/DeployMockTokamakNetworkToken.s.sol:DeployMockTokamakNetworkTokenScript \
        --rpc-url "$APPS_RPC_URL" \
        --broadcast
)

PRIVATE_STATE_CANONICAL_ASSET="$(
    jq -r 'first(.transactions[] | select(.transactionType == "CREATE" and .contractName == "MockTokamakNetworkToken") | .contractAddress) // empty' \
        "$PROJECT_ROOT/broadcast/DeployMockTokamakNetworkToken.s.sol/${APPS_CHAIN_ID}/run-latest.json"
)"

if [[ -z "$PRIVATE_STATE_CANONICAL_ASSET" ]]; then
    echo "Failed to determine mock canonical asset address" >&2
    exit 1
fi

export APPS_RPC_URL_OVERRIDE="$APPS_RPC_URL"
cp "$ENV_FILE" "$TEMP_ENV_FILE"
awk -v canonical_asset="$PRIVATE_STATE_CANONICAL_ASSET" '
BEGIN { replaced = 0 }
/^PRIVATE_STATE_CANONICAL_ASSET=/ {
    print "PRIVATE_STATE_CANONICAL_ASSET=" canonical_asset
    replaced = 1
    next
}
{ print }
END {
    if (replaced == 0) {
        print "PRIVATE_STATE_CANONICAL_ASSET=" canonical_asset
    }
}
' "$TEMP_ENV_FILE" > "${TEMP_ENV_FILE}.next"
mv "${TEMP_ENV_FILE}.next" "$TEMP_ENV_FILE"

APPS_ENV_FILE="$TEMP_ENV_FILE" bash "$PROJECT_ROOT/apps/private-state/script/deploy/deploy-private-state.sh"
bash "$PROJECT_ROOT/apps/private-state/script/anvil/write-anvil-artifacts.sh" "$APPS_CHAIN_ID"

echo "Bootstrapped private-state on anvil"
echo "RPC URL: $APPS_RPC_URL"
echo "Mock canonical asset: $PRIVATE_STATE_CANONICAL_ASSET"
echo "Deployment manifest: $PROJECT_ROOT/apps/private-state/deploy/deployment.${APPS_CHAIN_ID}.latest.json"
echo "Anvil bootstrap manifest: $PROJECT_ROOT/apps/private-state/deploy/anvil-bootstrap.latest.json"

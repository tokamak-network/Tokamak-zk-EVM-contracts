#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
DEPLOY_DIR="$PROJECT_ROOT/apps/private-state/deploy"
CHAIN_ID="${1:-31337}"
TOKEN_BROADCAST="$PROJECT_ROOT/broadcast/DeployMockTokamakNetworkToken.s.sol/${CHAIN_ID}/run-latest.json"

if [[ ! -f "$TOKEN_BROADCAST" ]]; then
    echo "Missing token deployment broadcast file: $TOKEN_BROADCAST" >&2
    exit 1
fi

mkdir -p "$DEPLOY_DIR"

TIMESTAMP_UTC="$(date -u +"%Y%m%dT%H%M%SZ")"
ANVIL_MANIFEST="$DEPLOY_DIR/anvil-bootstrap.${CHAIN_ID}.${TIMESTAMP_UTC}.json"
ANVIL_LATEST="$DEPLOY_DIR/anvil-bootstrap.latest.json"

TOKEN_ADDRESS="$(
    jq -r 'first(.transactions[] | select(.transactionType == "CREATE" and .contractName == "MockTokamakNetworkToken") | .contractAddress) // empty' "$TOKEN_BROADCAST"
)"
DEPLOYER="$(
    jq -r 'first(.transactions[]?.transaction.from) // empty' "$TOKEN_BROADCAST"
)"
INITIAL_HOLDER="$(
    jq -r 'first(.transactions[] | select(.transactionType == "CREATE" and .contractName == "MockTokamakNetworkToken") | .transaction.from) // empty' "$TOKEN_BROADCAST"
)"

jq -n \
    --arg generatedAtUtc "$TIMESTAMP_UTC" \
    --arg chainId "$CHAIN_ID" \
    --arg tokenBroadcastFile "$TOKEN_BROADCAST" \
    --arg deployer "$DEPLOYER" \
    --arg tokenAddress "$TOKEN_ADDRESS" \
    --arg initialHolder "$INITIAL_HOLDER" \
    --arg privateStateManifest "$DEPLOY_DIR/deployment.${CHAIN_ID}.latest.json" \
    '{
        generatedAtUtc: $generatedAtUtc,
        chainId: ($chainId | tonumber),
        tokenBroadcastFile: $tokenBroadcastFile,
        deployer: $deployer,
        initialHolder: $initialHolder,
        mockCanonicalAsset: $tokenAddress,
        privateStateDeploymentManifest: $privateStateManifest
    }' > "$ANVIL_MANIFEST"

cp "$ANVIL_MANIFEST" "$ANVIL_LATEST"

jq \
    '[.abi[] | . as $entry | select($entry.type == "function" and (["allowance","approve","balanceOf","decimals","mint","name","symbol","totalSupply","transfer","transferFrom"] | index($entry.name)))]' \
    "$PROJECT_ROOT/out/MockTokamakNetworkToken.sol/MockTokamakNetworkToken.json" \
    > "$DEPLOY_DIR/MockTokamakNetworkToken.callable-abi.json"

echo "Wrote anvil bootstrap manifest: $ANVIL_MANIFEST"
echo "Updated anvil bootstrap manifest: $ANVIL_LATEST"
echo "Wrote mock token callable ABI: $DEPLOY_DIR/MockTokamakNetworkToken.callable-abi.json"

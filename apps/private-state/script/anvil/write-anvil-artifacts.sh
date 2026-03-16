#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
DEPLOY_DIR="$PROJECT_ROOT/apps/private-state/deploy"
CHAIN_ID="${1:-31337}"
PRIVATE_STATE_MANIFEST="$DEPLOY_DIR/deployment.${CHAIN_ID}.latest.json"

if [[ ! -f "$PRIVATE_STATE_MANIFEST" ]]; then
    echo "Missing private-state deployment manifest: $PRIVATE_STATE_MANIFEST" >&2
    exit 1
fi

mkdir -p "$DEPLOY_DIR"

TIMESTAMP_UTC="$(date -u +"%Y%m%dT%H%M%SZ")"
ANVIL_MANIFEST="$DEPLOY_DIR/anvil-bootstrap.${CHAIN_ID}.${TIMESTAMP_UTC}.json"
ANVIL_LATEST="$DEPLOY_DIR/anvil-bootstrap.latest.json"

DEPLOYER="$(
    jq -r '.deployer // empty' "$PRIVATE_STATE_MANIFEST"
)"

jq -n \
    --arg generatedAtUtc "$TIMESTAMP_UTC" \
    --arg chainId "$CHAIN_ID" \
    --arg deployer "$DEPLOYER" \
    --arg privateStateManifest "$PRIVATE_STATE_MANIFEST" \
    '{
        generatedAtUtc: $generatedAtUtc,
        chainId: ($chainId | tonumber),
        deployer: $deployer,
        privateStateDeploymentManifest: $privateStateManifest
    }' > "$ANVIL_MANIFEST"

cp "$ANVIL_MANIFEST" "$ANVIL_LATEST"

echo "Wrote anvil bootstrap manifest: $ANVIL_MANIFEST"
echo "Updated anvil bootstrap manifest: $ANVIL_LATEST"

#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
DEPLOY_DIR="$PROJECT_ROOT/apps/private-state/deploy"
BRIDGE_DEPLOY_DIR="$PROJECT_ROOT/bridge/deployments"

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <chain-id>" >&2
    exit 1
fi

CHAIN_ID="$1"
BRIDGE_MANIFEST_PATH="$BRIDGE_DEPLOY_DIR/groth16.${CHAIN_ID}.latest.json"
ARTIFACT_DIR="$DEPLOY_DIR/groth16/$CHAIN_ID"
MANIFEST_PATH="$DEPLOY_DIR/groth16-updateTree.${CHAIN_ID}.latest.json"
TIMESTAMP_UTC="$(date -u +"%Y%m%dT%H%M%SZ")"

if [[ ! -f "$BRIDGE_MANIFEST_PATH" ]]; then
    echo "Missing bridge Groth16 manifest: $BRIDGE_MANIFEST_PATH" >&2
    exit 1
fi

resolve_manifest_artifact_path() {
    local manifest_path="$1"
    local artifact_path="$2"

    if [[ "$artifact_path" = /* ]]; then
        printf '%s\n' "$artifact_path"
    else
        local manifest_dir
        manifest_dir="$(cd "$(dirname "$manifest_path")" && pwd)"
        printf '%s\n' "$manifest_dir/$artifact_path"
    fi
}

BRIDGE_GROTH_SOURCE="$(jq -r '.grothArtifactSource // empty' "$BRIDGE_MANIFEST_PATH")"
SOURCE_ZKEY_PATH="$(resolve_manifest_artifact_path "$BRIDGE_MANIFEST_PATH" "$(jq -r '.artifacts.zkeyPath // empty' "$BRIDGE_MANIFEST_PATH")")"
SOURCE_METADATA_PATH="$(resolve_manifest_artifact_path "$BRIDGE_MANIFEST_PATH" "$(jq -r '.artifacts.metadataPath // empty' "$BRIDGE_MANIFEST_PATH")")"

for required_path in \
    "$SOURCE_ZKEY_PATH" \
    "$SOURCE_METADATA_PATH"
do
    if [[ ! -f "$required_path" ]]; then
        echo "Missing required Groth16 artifact: $required_path" >&2
        exit 1
    fi
done

rm -rf "$ARTIFACT_DIR"
mkdir -p "$ARTIFACT_DIR"

cp "$SOURCE_ZKEY_PATH" "$ARTIFACT_DIR/circuit_final.zkey"
cp "$SOURCE_METADATA_PATH" "$ARTIFACT_DIR/metadata.json"

jq -n \
    --arg generatedAtUtc "$TIMESTAMP_UTC" \
    --arg chainId "$CHAIN_ID" \
    --arg grothArtifactSource "$BRIDGE_GROTH_SOURCE" \
    --arg bridgeManifestPath "$(basename "$BRIDGE_MANIFEST_PATH")" \
    --arg zkeyPath "groth16/$CHAIN_ID/circuit_final.zkey" \
    --arg metadataPath "groth16/$CHAIN_ID/metadata.json" \
    '{
        generatedAtUtc: $generatedAtUtc,
        chainId: ($chainId | tonumber),
        grothArtifactSource: $grothArtifactSource,
        bridgeManifestPath: $bridgeManifestPath,
        artifacts: {
            zkeyPath: $zkeyPath,
            metadataPath: $metadataPath
        }
    }' > "$MANIFEST_PATH"

echo "Updated Groth16 updateTree manifest: $MANIFEST_PATH"
echo "Groth16 artifact source: $BRIDGE_GROTH_SOURCE"

#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
DEPLOY_DIR="$PROJECT_ROOT/apps/private-state/deploy"
GROTH_ARTIFACT_SOURCE="${GROTH_ARTIFACT_SOURCE:-trusted}"

case "$GROTH_ARTIFACT_SOURCE" in
    trusted)
        SOURCE_GROTH_DIR="$PROJECT_ROOT/groth16/trusted-setup/crs"
        ;;
    mpc)
        SOURCE_GROTH_DIR="$PROJECT_ROOT/groth16/mpc-setup/crs"
        ;;
    *)
        echo "Unsupported GROTH_ARTIFACT_SOURCE=$GROTH_ARTIFACT_SOURCE" >&2
        echo "Supported values: trusted, mpc" >&2
        exit 1
        ;;
esac

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <chain-id>" >&2
    exit 1
fi

CHAIN_ID="$1"
ARTIFACT_DIR="$DEPLOY_DIR/groth16/updateTree/$CHAIN_ID"
MANIFEST_PATH="$DEPLOY_DIR/groth16-updateTree.${CHAIN_ID}.latest.json"
TIMESTAMP_UTC="$(date -u +"%Y%m%dT%H%M%SZ")"

SOURCE_ZKEY_PATH="$SOURCE_GROTH_DIR/circuit_final.zkey"
SOURCE_METADATA_PATH="$SOURCE_GROTH_DIR/metadata.json"

for required_path in \
    "$SOURCE_ZKEY_PATH" \
    "$SOURCE_METADATA_PATH"
do
    if [[ ! -f "$required_path" ]]; then
        echo "Missing required Groth16 artifact: $required_path" >&2
        exit 1
    fi
done

mkdir -p "$ARTIFACT_DIR"

cp "$SOURCE_ZKEY_PATH" "$ARTIFACT_DIR/circuit_final.zkey"
cp "$SOURCE_METADATA_PATH" "$ARTIFACT_DIR/metadata.json"

jq -n \
    --arg generatedAtUtc "$TIMESTAMP_UTC" \
    --arg chainId "$CHAIN_ID" \
    --arg grothArtifactSource "$GROTH_ARTIFACT_SOURCE" \
    --arg zkeyPath "groth16/updateTree/$CHAIN_ID/circuit_final.zkey" \
    --arg metadataPath "groth16/updateTree/$CHAIN_ID/metadata.json" \
    '{
        generatedAtUtc: $generatedAtUtc,
        chainId: ($chainId | tonumber),
        grothArtifactSource: $grothArtifactSource,
        artifacts: {
            zkeyPath: $zkeyPath,
            metadataPath: $metadataPath
        }
    }' > "$MANIFEST_PATH"

echo "Updated Groth16 updateTree manifest: $MANIFEST_PATH"
echo "Groth16 artifact source: $GROTH_ARTIFACT_SOURCE"

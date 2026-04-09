#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DEPLOY_DIR="$PROJECT_ROOT/bridge/deployments"
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
ARTIFACT_DIR="$DEPLOY_DIR/groth16/$CHAIN_ID"
MANIFEST_PATH="$DEPLOY_DIR/groth16.${CHAIN_ID}.latest.json"
TIMESTAMP_UTC="$(date -u +"%Y%m%dT%H%M%SZ")"

for required_path in \
    "$SOURCE_GROTH_DIR/circuit_final.zkey" \
    "$SOURCE_GROTH_DIR/metadata.json" \
    "$SOURCE_GROTH_DIR/verification_key.json"
do
    if [[ ! -f "$required_path" ]]; then
        echo "Missing required Groth16 artifact: $required_path" >&2
        exit 1
    fi
done

rm -rf "$ARTIFACT_DIR"
mkdir -p "$ARTIFACT_DIR"
cp "$SOURCE_GROTH_DIR"/* "$ARTIFACT_DIR/"

PHASE1_PATH="null"
if [[ -f "$ARTIFACT_DIR/phase1_final_14.ptau" ]]; then
    PHASE1_PATH="\"groth16/$CHAIN_ID/phase1_final_14.ptau\""
fi

jq -n \
    --arg generatedAtUtc "$TIMESTAMP_UTC" \
    --arg chainId "$CHAIN_ID" \
    --arg grothArtifactSource "$GROTH_ARTIFACT_SOURCE" \
    --arg artifactDir "groth16/$CHAIN_ID" \
    --arg zkeyPath "groth16/$CHAIN_ID/circuit_final.zkey" \
    --arg metadataPath "groth16/$CHAIN_ID/metadata.json" \
    --arg verificationKeyPath "groth16/$CHAIN_ID/verification_key.json" \
    --argjson phase1Path "$PHASE1_PATH" \
    '{
        generatedAtUtc: $generatedAtUtc,
        chainId: ($chainId | tonumber),
        grothArtifactSource: $grothArtifactSource,
        artifactDir: $artifactDir,
        artifacts: {
            zkeyPath: $zkeyPath,
            metadataPath: $metadataPath,
            verificationKeyPath: $verificationKeyPath,
            phase1PtauPath: $phase1Path
        }
    }' > "$MANIFEST_PATH"

echo "Updated bridge Groth16 manifest: $MANIFEST_PATH"
echo "Groth16 artifact source: $GROTH_ARTIFACT_SOURCE"

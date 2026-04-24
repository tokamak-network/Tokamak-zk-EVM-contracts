#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
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
TIMESTAMP_LABEL="${BRIDGE_ARTIFACT_TIMESTAMP:-$(date -u +"%Y%m%dT%H%M%SZ")}"
CHAIN_DIR="$PROJECT_ROOT/deployment/chain-id-${CHAIN_ID}"
SNAPSHOT_DIR="$CHAIN_DIR/bridge/$TIMESTAMP_LABEL"
ARTIFACT_DIR="$SNAPSHOT_DIR/groth16"
MANIFEST_PATH="$SNAPSHOT_DIR/groth16.${CHAIN_ID}.latest.json"
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

SOURCE_ZKEY_PROVENANCE_PATH="$SOURCE_GROTH_DIR/zkey_provenance.json"
if [[ "$GROTH_ARTIFACT_SOURCE" == "mpc" && ! -f "$SOURCE_ZKEY_PROVENANCE_PATH" ]]; then
    echo "Missing required Groth16 provenance artifact: $SOURCE_ZKEY_PROVENANCE_PATH" >&2
    exit 1
fi

rm -rf "$ARTIFACT_DIR"
mkdir -p "$ARTIFACT_DIR"
cp "$SOURCE_GROTH_DIR/circuit_final.zkey" "$ARTIFACT_DIR/circuit_final.zkey"
cp "$SOURCE_GROTH_DIR/metadata.json" "$ARTIFACT_DIR/metadata.json"
cp "$SOURCE_GROTH_DIR/verification_key.json" "$ARTIFACT_DIR/verification_key.json"

ZKEY_PROVENANCE_PATH="null"
if [[ -f "$SOURCE_ZKEY_PROVENANCE_PATH" ]]; then
    cp "$SOURCE_ZKEY_PROVENANCE_PATH" "$ARTIFACT_DIR/zkey_provenance.json"
    ZKEY_PROVENANCE_PATH="\"groth16/zkey_provenance.json\""
fi

jq -n \
    --arg generatedAtUtc "$TIMESTAMP_UTC" \
    --arg chainId "$CHAIN_ID" \
    --arg grothArtifactSource "$GROTH_ARTIFACT_SOURCE" \
    --arg artifactDir "groth16" \
    --arg zkeyPath "groth16/circuit_final.zkey" \
    --arg metadataPath "groth16/metadata.json" \
    --arg verificationKeyPath "groth16/verification_key.json" \
    --argjson zkeyProvenancePath "$ZKEY_PROVENANCE_PATH" \
    '{
        generatedAtUtc: $generatedAtUtc,
        chainId: ($chainId | tonumber),
        grothArtifactSource: $grothArtifactSource,
        artifactDir: $artifactDir,
        artifacts: {
            zkeyPath: $zkeyPath,
            metadataPath: $metadataPath,
            verificationKeyPath: $verificationKeyPath,
            zkeyProvenancePath: $zkeyProvenancePath
        }
    }' > "$MANIFEST_PATH"

echo "Updated bridge Groth16 manifest: $MANIFEST_PATH"
echo "Groth16 artifact source: $GROTH_ARTIFACT_SOURCE"

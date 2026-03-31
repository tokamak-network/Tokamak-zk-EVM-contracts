#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
DEPLOY_DIR="$PROJECT_ROOT/apps/private-state/deploy"
SOURCE_TRUSTED_SETUP_DIR="$PROJECT_ROOT/groth16/trusted-setup/updateTree"
SOURCE_WASM_PATH="$PROJECT_ROOT/groth16/circuits/build/circuit_updateTree_js/circuit_updateTree.wasm"

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <chain-id>" >&2
    exit 1
fi

CHAIN_ID="$1"
ARTIFACT_DIR="$DEPLOY_DIR/groth16/updateTree/$CHAIN_ID"
MANIFEST_PATH="$DEPLOY_DIR/groth16-updateTree.${CHAIN_ID}.latest.json"
TIMESTAMP_UTC="$(date -u +"%Y%m%dT%H%M%SZ")"

SOURCE_ZKEY_PATH="$SOURCE_TRUSTED_SETUP_DIR/circuit_final.zkey"
SOURCE_VERIFICATION_KEY_PATH="$SOURCE_TRUSTED_SETUP_DIR/verification_key.json"
SOURCE_METADATA_PATH="$SOURCE_TRUSTED_SETUP_DIR/metadata.json"

for required_path in \
    "$SOURCE_ZKEY_PATH" \
    "$SOURCE_VERIFICATION_KEY_PATH" \
    "$SOURCE_METADATA_PATH" \
    "$SOURCE_WASM_PATH"
do
    if [[ ! -f "$required_path" ]]; then
        echo "Missing required Groth16 artifact: $required_path" >&2
        exit 1
    fi
done

mkdir -p "$ARTIFACT_DIR"

cp "$SOURCE_ZKEY_PATH" "$ARTIFACT_DIR/circuit_final.zkey"
cp "$SOURCE_VERIFICATION_KEY_PATH" "$ARTIFACT_DIR/verification_key.json"
cp "$SOURCE_METADATA_PATH" "$ARTIFACT_DIR/metadata.json"
cp "$SOURCE_WASM_PATH" "$ARTIFACT_DIR/circuit_updateTree.wasm"

jq -n \
    --arg generatedAtUtc "$TIMESTAMP_UTC" \
    --arg chainId "$CHAIN_ID" \
    --arg zkeyPath "groth16/updateTree/$CHAIN_ID/circuit_final.zkey" \
    --arg verificationKeyPath "groth16/updateTree/$CHAIN_ID/verification_key.json" \
    --arg metadataPath "groth16/updateTree/$CHAIN_ID/metadata.json" \
    --arg wasmPath "groth16/updateTree/$CHAIN_ID/circuit_updateTree.wasm" \
    '{
        generatedAtUtc: $generatedAtUtc,
        chainId: ($chainId | tonumber),
        artifacts: {
            zkeyPath: $zkeyPath,
            verificationKeyPath: $verificationKeyPath,
            metadataPath: $metadataPath,
            wasmPath: $wasmPath
        }
    }' > "$MANIFEST_PATH"

echo "Updated Groth16 updateTree manifest: $MANIFEST_PATH"

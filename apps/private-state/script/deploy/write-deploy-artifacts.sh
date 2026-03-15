#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
DEPLOY_DIR="$PROJECT_ROOT/apps/private-state/deploy"

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <chain-id>" >&2
    exit 1
fi

CHAIN_ID="$1"
RUN_FILE="$PROJECT_ROOT/broadcast/DeployPrivateState.s.sol/${CHAIN_ID}/run-latest.json"

if [[ ! -f "$RUN_FILE" ]]; then
    echo "Missing deployment broadcast file: $RUN_FILE" >&2
    exit 1
fi

mkdir -p "$DEPLOY_DIR"

TIMESTAMP_UTC="$(date -u +"%Y%m%dT%H%M%SZ")"
DEPLOYMENT_FILE="$DEPLOY_DIR/deployment.${CHAIN_ID}.${TIMESTAMP_UTC}.json"
CHAIN_LATEST_FILE="$DEPLOY_DIR/deployment.${CHAIN_ID}.latest.json"

ZERO_ADDRESS="0x0000000000000000000000000000000000000000"

DEPLOYER="$(
    jq -r 'first(.transactions[]?.transaction.from) // empty' "$RUN_FILE"
)"
DEPLOYMENT_FACTORY="$(
    jq -r 'first(.transactions[] | select(.transactionType == "CREATE" and .contractName == "PrivateStateDeploymentFactory") | .contractAddress) // empty' "$RUN_FILE"
)"
CONTROLLER="$(
    jq -r 'first(.transactions[] | (.additionalContracts // [])[]? | select(.contractName == "PrivateStateController") | .address) // empty' "$RUN_FILE"
)"
L2_ACCOUNTING_VAULT="$(
    jq -r 'first(.transactions[] | (.additionalContracts // [])[]? | select(.contractName == "L2AccountingVault") | .address) // empty' "$RUN_FILE"
)"
NOTE_REGISTRY="$(
    jq -r 'first(.transactions[] | (.additionalContracts // [])[]? | select(.contractName == "PrivateNoteRegistry") | .address) // empty' "$RUN_FILE"
)"
NULLIFIER_REGISTRY="$(
    jq -r 'first(.transactions[] | (.additionalContracts // [])[]? | select(.contractName == "PrivateNullifierRegistry") | .address) // empty' "$RUN_FILE"
)"
CANONICAL_ASSET="$(
    jq -r 'first(.transactions[] | select(.function == "deployController(address,address,address,address)") | .arguments[3]) // empty' "$RUN_FILE"
)"

jq -n \
    --arg generatedAtUtc "$TIMESTAMP_UTC" \
    --arg chainId "$CHAIN_ID" \
    --arg runFile "$RUN_FILE" \
    --arg deployer "$DEPLOYER" \
    --arg canonicalAsset "$CANONICAL_ASSET" \
    --arg deploymentFactory "$DEPLOYMENT_FACTORY" \
    --arg controller "$CONTROLLER" \
    --arg l2AccountingVault "$L2_ACCOUNTING_VAULT" \
    --arg noteRegistry "$NOTE_REGISTRY" \
    --arg nullifierRegistry "$NULLIFIER_REGISTRY" \
    '{
        generatedAtUtc: $generatedAtUtc,
        chainId: ($chainId | tonumber),
        broadcastRunFile: $runFile,
        deployer: $deployer,
        canonicalAsset: $canonicalAsset,
        contracts: {
            deploymentFactory: $deploymentFactory,
            controller: $controller,
            l2AccountingVault: $l2AccountingVault,
            noteRegistry: $noteRegistry,
            nullifierRegistry: $nullifierRegistry
        }
    }' > "$DEPLOYMENT_FILE"

cp "$DEPLOYMENT_FILE" "$CHAIN_LATEST_FILE"

write_callable_abi() {
    local artifact_path="$1"
    local output_path="$2"
    local names_json="$3"

    jq --argjson names "$names_json" \
        '[.abi[] | . as $entry | select($entry.type == "function" and ($names | index($entry.name)))]' \
        "$artifact_path" > "$output_path"
}

write_callable_abi \
    "$PROJECT_ROOT/out/PrivateStateController.sol/PrivateStateController.json" \
    "$DEPLOY_DIR/PrivateStateController.callable-abi.json" \
    '[
        "mockBridgeDeposit",
        "mockBridgeWithdraw",
        "canonicalAsset",
        "computeNoteCommitment",
        "computeNullifier",
        "l2AccountingVault",
        "mintNotes1",
        "mintNotes2",
        "mintNotes3",
        "noteRegistry",
        "nullifierStore",
        "redeemNotes4",
        "redeemNotes6",
        "redeemNotes8",
        "transferNotes1",
        "transferNotes4",
        "transferNotes6",
        "transferNotes8"
    ]'

write_callable_abi \
    "$PROJECT_ROOT/out/L2AccountingVault.sol/L2AccountingVault.json" \
    "$DEPLOY_DIR/L2AccountingVault.callable-abi.json" \
    '[
        "controller",
        "liquidBalances"
    ]'

write_callable_abi \
    "$PROJECT_ROOT/out/PrivateNoteRegistry.sol/PrivateNoteRegistry.json" \
    "$DEPLOY_DIR/PrivateNoteRegistry.callable-abi.json" \
    '[
        "commitmentExists",
        "controller"
    ]'

write_callable_abi \
    "$PROJECT_ROOT/out/PrivateNullifierRegistry.sol/PrivateNullifierRegistry.json" \
    "$DEPLOY_DIR/PrivateNullifierRegistry.callable-abi.json" \
    '[
        "controller",
        "nullifierUsed"
    ]'

echo "Wrote deployment manifest: $DEPLOYMENT_FILE"
echo "Updated chain deployment manifest: $CHAIN_LATEST_FILE"
echo "Wrote callable ABI files under: $DEPLOY_DIR"

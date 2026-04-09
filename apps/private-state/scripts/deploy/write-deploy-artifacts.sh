#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
DEPLOY_DIR="$PROJECT_ROOT/apps/private-state/deploy"
SUBMODULE_PRIVATE_STATE_DEPLOY_DIR="$PROJECT_ROOT/submodules/Tokamak-zk-EVM/packages/frontend/synthesizer/scripts/deployment/private-state"

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
mkdir -p "$SUBMODULE_PRIVATE_STATE_DEPLOY_DIR"

TIMESTAMP_UTC="$(date -u +"%Y%m%dT%H%M%SZ")"
CHAIN_LATEST_FILE="$DEPLOY_DIR/deployment.${CHAIN_ID}.latest.json"
STORAGE_LAYOUT_LATEST_FILE="$DEPLOY_DIR/storage-layout.${CHAIN_ID}.latest.json"
SUBMODULE_CHAIN_LATEST_FILE="$SUBMODULE_PRIVATE_STATE_DEPLOY_DIR/deployment.${CHAIN_ID}.latest.json"
SUBMODULE_STORAGE_LAYOUT_LATEST_FILE="$SUBMODULE_PRIVATE_STATE_DEPLOY_DIR/storage-layout.${CHAIN_ID}.latest.json"

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
jq -n \
    --arg generatedAtUtc "$TIMESTAMP_UTC" \
    --arg chainId "$CHAIN_ID" \
    --arg runFile "$RUN_FILE" \
    --arg deployer "$DEPLOYER" \
    --arg deploymentFactory "$DEPLOYMENT_FACTORY" \
    --arg controller "$CONTROLLER" \
    --arg l2AccountingVault "$L2_ACCOUNTING_VAULT" \
    '{
        generatedAtUtc: $generatedAtUtc,
        chainId: ($chainId | tonumber),
        broadcastRunFile: $runFile,
        deployer: $deployer,
        contracts: {
            deploymentFactory: $deploymentFactory,
            controller: $controller,
            l2AccountingVault: $l2AccountingVault
        }
    }' > "$CHAIN_LATEST_FILE"

cp "$CHAIN_LATEST_FILE" "$SUBMODULE_CHAIN_LATEST_FILE"

CONTROLLER_STORAGE_LAYOUT="$(
    forge inspect --json PrivateStateController storage-layout
)"
L2_ACCOUNTING_VAULT_STORAGE_LAYOUT="$(
    forge inspect --json L2AccountingVault storage-layout
)"

jq -n \
    --arg generatedAtUtc "$TIMESTAMP_UTC" \
    --arg chainId "$CHAIN_ID" \
    --arg controllerAddress "$CONTROLLER" \
    --arg l2AccountingVaultAddress "$L2_ACCOUNTING_VAULT" \
    --argjson controllerLayout "$CONTROLLER_STORAGE_LAYOUT" \
    --argjson l2AccountingVaultLayout "$L2_ACCOUNTING_VAULT_STORAGE_LAYOUT" \
    '{
        generatedAtUtc: $generatedAtUtc,
        chainId: ($chainId | tonumber),
        contracts: {
            PrivateStateController: {
                address: $controllerAddress,
                sourceName: "apps/private-state/src/PrivateStateController.sol",
                contractName: "PrivateStateController",
                storageLayout: $controllerLayout
            },
            L2AccountingVault: {
                address: $l2AccountingVaultAddress,
                sourceName: "apps/private-state/src/L2AccountingVault.sol",
                contractName: "L2AccountingVault",
                storageLayout: $l2AccountingVaultLayout
            }
        }
    }' > "$STORAGE_LAYOUT_LATEST_FILE"

cp "$STORAGE_LAYOUT_LATEST_FILE" "$SUBMODULE_STORAGE_LAYOUT_LATEST_FILE"

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
        "computeNoteCommitment",
        "computeNullifier",
        "commitmentExists",
        "l2AccountingVault",
        "mintNotes1",
        "mintNotes2",
        "mintNotes3",
        "mintNotes4",
        "mintNotes5",
        "mintNotes6",
        "redeemNotes1",
        "redeemNotes2",
        "redeemNotes3",
        "redeemNotes4",
        "nullifierUsed",
        "transferNotes1To1",
        "transferNotes1To2",
        "transferNotes1To3",
        "transferNotes2To1",
        "transferNotes2To2",
        "transferNotes3To1",
        "transferNotes3To2",
        "transferNotes4To1"
    ]'

write_callable_abi \
    "$PROJECT_ROOT/out/L2AccountingVault.sol/L2AccountingVault.json" \
    "$DEPLOY_DIR/L2AccountingVault.callable-abi.json" \
    '[
        "controller",
        "liquidBalances"
    ]'

echo "Updated chain deployment manifest: $CHAIN_LATEST_FILE"
echo "Mirrored chain deployment manifest: $SUBMODULE_CHAIN_LATEST_FILE"
echo "Updated storage layout manifest: $STORAGE_LAYOUT_LATEST_FILE"
echo "Mirrored storage layout manifest: $SUBMODULE_STORAGE_LAYOUT_LATEST_FILE"
echo "Wrote callable ABI files under: $DEPLOY_DIR"

if [[ "${PRIVATE_STATE_SKIP_GROTH_SYNC:-0}" == "1" ]]; then
    echo "Skipping Groth16 artifact sync because PRIVATE_STATE_SKIP_GROTH_SYNC=1"
else
    bash "$PROJECT_ROOT/apps/private-state/scripts/deploy/sync-groth16-update-tree-artifacts.sh" "$CHAIN_ID"
fi

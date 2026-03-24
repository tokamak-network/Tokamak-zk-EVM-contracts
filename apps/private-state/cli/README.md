# private-state CLI

This folder contains the terminal CLI for the private-state DApp.

## Structure

- `private-state-bridge-cli.mjs`: the bridge-coupled L2 user workflow CLI
- `functions/index.json`: selectable function list
- `functions/<function-name>/calldata.json`: default calldata template for that function
- `workspaces/`: local channel workspaces, snapshots, proofs, and receipts created by the bridge-coupled CLI

Each `calldata.json` file follows this shape:

```json
{
  "description": "Human-readable note for the operator",
  "contractKey": "controller",
  "abiFile": "../deploy/PrivateStateController.callable-abi.json",
  "method": "mintNotes1",
  "mode": "send",
  "value": "0x0",
  "args": [[{"owner":"0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266","value":"1000000000000000000","salt":"0x1000000000000000000000000000000000000000000000000000000000000001"}]]
}
```

The bridge-coupled CLI reads a function's `calldata.json`, optionally replaces `args` through `--args-file` or
replaces the full template through `--template-file`, resolves the bridge deployment and ABI manifest, maintains a
channel workspace, generates proofs, and submits the resulting bridge transactions.

## Usage

```bash
node apps/private-state/cli/private-state-bridge-cli.mjs list-functions
node apps/private-state/cli/private-state-bridge-cli.mjs show-template mintNotes1
```

The bridge-coupled CLI manages a channel workspace, generates Groth or Tokamak proofs, calls the deployed bridge, and
stores every resulting `state_snapshot.json`.

For bridge contract ABIs, the bridge-coupled CLI does not use hardcoded function signatures anymore. It reads the
bridge deployment JSON plus the bridge ABI manifest generated at deployment time under `bridge/deployments/`.

Example:

```bash
node apps/private-state/cli/private-state-bridge-cli.mjs workspace-init \
  --workspace demo \
  --network anvil \
  --channel-name demo-channel \
  --bridge-deployment bridge/deployments/private-state-bridge-e2e-latest.json

node apps/private-state/cli/private-state-bridge-cli.mjs register-and-fund \
  --workspace demo \
  --network anvil \
  --private-key <hex> \
  --l2-key-signature "participant-a" \
  --amount 3000000000000000000

node apps/private-state/cli/private-state-bridge-cli.mjs deposit \
  --workspace demo \
  --network anvil \
  --private-key <hex> \
  --l2-key-signature "participant-a" \
  --amount 3000000000000000000

node apps/private-state/cli/private-state-bridge-cli.mjs bridge-send mintNotes1 \
  --workspace demo \
  --network anvil \
  --private-key <hex> \
  --l2-key-signature "participant-a" \
  --template-file apps/private-state/cli/functions/mintNotes1/calldata.json
```

Every bridge-coupled operation writes its inputs, proofs, receipts, and resulting state snapshot under:

```text
apps/private-state/cli/workspaces/<workspace>/operations/
```

The latest channel snapshot is mirrored under:

```text
apps/private-state/cli/workspaces/<workspace>/current/state_snapshot.json
```

## Function-folder naming

The requirement is to keep one folder per function name. That creates a collision risk when several contracts expose a
function with the same name. private-state already has repeated low-signal getters such as `controller()`. Those
duplicates are intentionally omitted from the function-folder set so the folder naming rule remains usable.

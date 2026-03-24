# private-state CLI

This folder contains the terminal CLI for the private-state DApp.

## Structure

- `private-state-bridge-cli.mjs`: the bridge-coupled L2 user workflow CLI
- `functions/index.json`: selectable function list
- `functions/<function-name>/calldata.json`: default calldata template for that function
- `workspaces/`: optional channel workspaces that cache reconstructed channel snapshots
- `user-workspaces/`: mandatory per-user workspaces that track L2 identity, nonce, and note ledgers

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
replaces the full template through `--template-file`, resolves the bridge deployment and ABI manifest, reconstructs or
loads the channel state snapshot, maintains per-user note workspaces, generates proofs, and submits the resulting
bridge transactions.

## Usage

```bash
node apps/private-state/cli/private-state-bridge-cli.mjs list-functions
node apps/private-state/cli/private-state-bridge-cli.mjs show-template mintNotes1
```

The bridge-coupled CLI separates channel creation from channel-workspace initialization:

- `channel-create` creates the bridge channel on-chain.
- `channel-workspace-init` reconstructs the latest channel `state_snapshot.json` from bridge events starting at the
  stored `genesisBlockNumber`.
- `user-workspaces` store per-user note plaintexts, classify notes into used vs unused sets, maintain aggregated
  unused-note balance, and keep a value-sorted unused-note order for efficient spend selection.
- Channel workspaces are optional caches. User actions can reconstruct channel state directly from chain events when no
  channel workspace is present.
- User workspaces are mandatory for note-carrying users. They are the authoritative local record for note plaintexts,
  note usage, and per-user L2 nonce.

For bridge contract ABIs, the bridge-coupled CLI does not use hardcoded function signatures anymore. It reads the
bridge deployment JSON plus the bridge ABI manifest generated at deployment time under `bridge/deployments/`.

Example:

```bash
node apps/private-state/cli/private-state-bridge-cli.mjs channel-create \
  --channel-name demo-channel \
  --dapp-id 1 \
  --asset <erc20-address> \
  --private-key <hex> \
  --create-workspace \
  --workspace demo \
  --network anvil \
  --bridge-deployment bridge/deployments/private-state-bridge-e2e-latest.json

node apps/private-state/cli/private-state-bridge-cli.mjs channel-workspace-init \
  --network anvil \
  --channel-name demo-channel \
  --workspace demo \
  --bridge-deployment bridge/deployments/private-state-bridge-e2e-latest.json

node apps/private-state/cli/private-state-bridge-cli.mjs register-and-fund \
  --channel-name demo-channel \
  --user-workspace participant-a \
  --network anvil \
  --private-key <hex> \
  --l2-key-signature "participant-a" \
  --amount 3000000000000000000

node apps/private-state/cli/private-state-bridge-cli.mjs deposit \
  --channel-name demo-channel \
  --user-workspace participant-a \
  --network anvil \
  --private-key <hex> \
  --l2-key-signature "participant-a" \
  --amount 3000000000000000000

node apps/private-state/cli/private-state-bridge-cli.mjs bridge-send mintNotes1 \
  --user-workspace participant-a \
  --network anvil \
  --private-key <hex> \
  --l2-key-signature "participant-a" \
  --template-file apps/private-state/cli/functions/mintNotes1/calldata.json
```

Channel-workspace caches live under:

```text
apps/private-state/cli/workspaces/<workspace>/
```

Per-user operations and note ledgers live under:

```text
apps/private-state/cli/user-workspaces/<workspace>/
```

User-action commands accept channel selection in this order:

1. `--workspace` when a channel workspace cache exists
2. `--channel-name` for direct on-chain reconstruction
3. `--user-workspace` when the user workspace already records the channel binding

## Function-folder naming

The requirement is to keep one folder per function name. That creates a collision risk when several contracts expose a
function with the same name. private-state already has repeated low-signal getters such as `controller()`. Those
duplicates are intentionally omitted from the function-folder set so the folder naming rule remains usable.

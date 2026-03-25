# private-state CLI

This folder contains the terminal CLI for the private-state DApp.

## Structure

- `private-state-bridge-cli.mjs`: the bridge-coupled L2 user workflow CLI
- `functions/index.json`: selectable function list
- `functions/<function-name>/calldata.json`: default calldata template for that function
- `workspaces/`: optional channel workspaces that cache reconstructed channel snapshots
- `wallets/`: mandatory per-user wallets that track L2 identity, nonce, and note ledgers

The CLI now assumes a clean-slate wallet model. Legacy CLI data is not reused.

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
replaces the full template through `--template-file`, auto-selects the bridge deployment and ABI manifest from the
chosen network, reconstructs or loads the channel state snapshot, maintains per-user note wallets, generates
proofs, and submits the resulting bridge transactions.

Every CLI `--amount` input is interpreted as a human Tokamak Network Token amount. The CLI converts it into base units
with the canonical token `decimals()` for the selected channel.
Every CLI `--password` input accepts any string. During `register-channel` and other wallet-aware
flows, the CLI signs a domain-separated password message with the user's L1 `--private-key`, uses the resulting
signature as the seed for `deriveL2KeysFromSignature`, and derives the L2 identity that is stored in the channel wallet.

## Usage

```bash
node apps/private-state/cli/private-state-bridge-cli.mjs list-functions
node apps/private-state/cli/private-state-bridge-cli.mjs show-template mintNotes1
```

The bridge-coupled CLI separates channel creation from channel-workspace initialization:

- `create-channel` creates the bridge channel on-chain.
- `create-channel` does not accept an asset address. The bridge binds the channel to the canonical Tokamak Network
  Token for the selected network.
- `create-channel --create-workspace` uses the channel name itself as the channel-workspace name.
- `deposit-bridge` funds the shared bridge-level L1 token vault.
- `get-bridge-deposit` reads the caller's shared bridge-level L1 token-vault balance.
- `is-channel-registered` checks whether the local wallet's L2 identity matches the selected channel's registered
  on-chain participant record. It accepts only `--wallet` and `--password`.
- `register-channel` registers the caller's L2 address, L2 token-vault key, and token-vault leaf index in the selected channel.
- `deposit-channel` moves value from the shared bridge-level L1 token vault into the selected channel's L2 token vault.
  It accepts only `--wallet`, `--password`, and `--amount`, and it fails unless the local wallet already contains
  plaintext network/channel metadata plus encrypted L1/L2 key material.
- `recover-workspace` reconstructs the latest channel `state_snapshot.json` from bridge events starting at the stored
  `genesisBlockNumber` and writes it into `workspaces/<channel-name>/`.
- `wallets` store per-user note plaintexts, classify notes into used vs unused sets, maintain aggregated
  unused-note balance, and keep a value-sorted unused-note order for efficient spend selection.
- Channel workspaces are optional caches. User actions can reconstruct channel state directly from chain events when no
  channel workspace is present.
- Wallets are mandatory for note-carrying users. They are the authoritative local record for note plaintexts,
  note usage, and per-user L2 nonce.
- Wallet folders are encrypted at rest. Only `register-channel` sets up L1/L2 keys in the active wallet.
- `bridge-send` updates nonce and note state in an existing wallet, and the CLI then needs only the matching
  `--password` to open or update that wallet.
- `get-bridge-deposit`, `fund-l1`, and `claim` can also recover the L1 signer from an existing encrypted wallet when
  `--wallet` and `--password` are provided.
- `is-channel-registered` also requires an existing wallet and derives its network and channel from that wallet.
- `deposit-channel` requires an existing wallet and derives its network, channel, and signer keys from that wallet.
- `withdraw` can still reuse an existing wallet when one is provided, but it does not set up wallet keys.
- The CLI only updates the active wallet. It does not auto-refresh other wallets, because their encrypted folders
  cannot be opened without their own `--password`.

For bridge contract ABIs, the bridge-coupled CLI does not use hardcoded function signatures anymore. It reads the
network-scoped bridge deployment JSON plus the network-scoped bridge ABI manifest generated at deployment time under
`bridge/deployments/`, selected solely from `--network`.

Example:

```bash
node apps/private-state/cli/private-state-bridge-cli.mjs create-channel \
  --channel-name demo-channel \
  --dapp-label private-state \
  --private-key <hex> \
  --create-workspace \
  --network sepolia

node apps/private-state/cli/private-state-bridge-cli.mjs recover-workspace \
  --network sepolia \
  --channel-name demo-channel \

node apps/private-state/cli/private-state-bridge-cli.mjs deposit-bridge \
  --network sepolia \
  --private-key <hex> \
  --amount 3

node apps/private-state/cli/private-state-bridge-cli.mjs get-bridge-deposit \
  --network sepolia \
  --private-key <hex>

node apps/private-state/cli/private-state-bridge-cli.mjs is-channel-registered \
  --wallet participant-a \
  --password "participant-a"

node apps/private-state/cli/private-state-bridge-cli.mjs register-channel \
  --channel-name demo-channel \
  --wallet participant-a \
  --network sepolia \
  --private-key <hex> \
  --password "participant-a"

node apps/private-state/cli/private-state-bridge-cli.mjs deposit-channel \
  --wallet participant-a \
  --password "participant-a" \
  --amount 1.5

node apps/private-state/cli/private-state-bridge-cli.mjs bridge-send mintNotes1 \
  --wallet participant-a \
  --network sepolia \
  --password "participant-a" \
  --template-file apps/private-state/cli/functions/mintNotes1/calldata.json
```

Channel-workspace caches live under:

```text
apps/private-state/cli/workspaces/<workspace>/
```

Per-wallet operations and note ledgers live under:

```text
apps/private-state/cli/wallets/<wallet>/
```

Each wallet is persisted as:

```text
apps/private-state/cli/wallets/<wallet>/wallet.json
```

Each wallet also stores unencrypted metadata as:

```text
apps/private-state/cli/wallets/<wallet>/wallet.metadata.json
```

That plaintext metadata includes only:

- `network`
- `channelName`

User-action commands accept channel selection in this order:

1. `--workspace` when a channel workspace cache exists
2. `--channel-name` for direct on-chain reconstruction
3. `--wallet` when the wallet already records the channel binding

## Function-folder naming

The requirement is to keep one folder per function name. That creates a collision risk when several contracts expose a
function with the same name. private-state already has repeated low-signal getters such as `controller()`. Those
duplicates are intentionally omitted from the function-folder set so the folder naming rule remains usable.

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
  "method": "transferNotes1To1",
  "mode": "send",
  "value": "0x0",
  "args": [
    [
      {
        "owner": "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266",
        "value": "1000000000000000000",
        "salt": "0xa100000000000000000000000000000000000000000000000000000000000001"
      }
    ],
    [
      {
        "owner": "0x70997970C51812dc3A010C7d01b50e0d17dc79C8",
        "value": "1000000000000000000",
        "salt": "0xa110000000000000000000000000000000000000000000000000000000000001"
      }
    ]
  ]
}
```

The bridge-coupled CLI uses the function templates as operator-facing references through `list-functions` and
`show-template`, auto-selects the bridge deployment and ABI manifest from the chosen network, reconstructs or loads the
channel state snapshot, maintains per-user note wallets, generates proofs, and submits the resulting bridge
transactions for the supported direct commands.

Every CLI `--amount` input is interpreted as a human Tokamak Network Token amount. The CLI converts it into base units
with the canonical token `decimals()` for the selected channel.
Every CLI `--password` input accepts any string. During `register-channel` and other wallet-aware
flows, the CLI signs a domain-separated password message with the user's L1 `--private-key`, uses the resulting
signature as the seed for `deriveL2KeysFromSignature`, and derives the L2 identity that is stored in the channel wallet.

## Usage

```bash
node apps/private-state/cli/private-state-bridge-cli.mjs list-functions
node apps/private-state/cli/private-state-bridge-cli.mjs show-template transferNotes1To1
node apps/private-state/cli/private-state-bridge-cli.mjs install-zk-evm --rpc-url https://eth-sepolia.g.alchemy.com/v2/<key>
node apps/private-state/cli/private-state-bridge-cli.mjs uninstall-zk-evm
```

The bridge-coupled CLI separates channel creation from channel-workspace initialization:

- `create-channel` creates the bridge channel on-chain.
- `install-zk-evm` runs `submodules/Tokamak-zk-EVM/tokamak-cli --install <rpc-url>` for the local zk-EVM toolchain.
  It accepts only `--rpc-url`.
- `uninstall-zk-evm` removes every file and directory inside `submodules/Tokamak-zk-EVM/` except the submodule's
  root `.git` pointer file. It accepts no options.
- `create-channel` does not accept an asset address. The bridge binds the channel to the canonical Tokamak Network
  Token for the selected network.
- `create-channel --create-workspace` uses the channel name itself as the channel-workspace name.
- The CLI now accepts `anvil` as a target network, but only for command-driven end-to-end tests. It is not meant as a
  user-facing real-world network mode.
- `deposit-bridge` funds the shared bridge-level `bridgeTokenVault`.
- `withdraw-bridge` is the wallet-only inverse of `deposit-bridge`. It accepts only `--wallet`, `--password`, and
  `--amount`, and it calls the bridge `claimToWallet` path to move value from the shared bridge-level `bridgeTokenVault`
  back into Tokamak Network Token in the caller's L1 wallet.
- `get-bridge-deposit` reads the caller's shared bridge-level `bridgeTokenVault` balance.
- `is-channel-registered` checks whether the local wallet's L2 identity matches the selected channel's registered
  on-chain participant record. It accepts only `--wallet` and `--password`.
- `get-wallet-address` reads the caller's registered L2 address from the selected channel's bridge registration.
  It accepts only `--wallet` and `--password`.
- `get-channel-deposit` reads the current channel-level L2 accounting balance bound to the local wallet's registered
  `channelTokenVault` key. It accepts only `--wallet` and `--password`.
- `mint-notes` directly mints one to six notes. It accepts only `--wallet`,
  `--password`, and `--amounts`, where `--amounts` is a JSON vector such as `'[1,2,3]'`.
- `redeem-notes` directly executes `redeemNotes1`. It accepts only `--wallet`,
  `--password`, and `--note-id`, where `--note-id` is a note commitment string from `get-my-notes`.
- `transfer-notes` directly executes one of `transferNotes1To1`, `transferNotes1To2`, or `transferNotes2To1`
  with only `--wallet`, `--password`, `--note-ids`, `--recipients`,
  and `--amounts`, where all three vector inputs are JSON arrays and `--amounts.length` must equal
  `--recipients.length`.
- `import-notes` imports off-chain note plaintexts into the selected wallet. It accepts only `--wallet`,
  `--password`, and `--notes`, where `--notes` is a JSON array of note objects emitted by `transfer-notes`.
- `get-my-notes` reads the local wallet's tracked note sets and checks each note's commitment/nullifier status against
  the current controller state accepted by the bridge. It accepts only `--wallet` and `--password`.
- `register-channel` registers the caller's L2 address, L2 `channelTokenVault` key, and `channelTokenVault` leaf index in the selected channel.
- `deposit-channel` moves value from the shared bridge-level `bridgeTokenVault` into the selected channel's `channelTokenVault`.
  It accepts only `--wallet`, `--password`, and `--amount`, and it fails unless the local wallet already contains
  plaintext network/channel metadata plus encrypted L1/L2 key material.
- `withdraw-channel` is the wallet-only inverse of `deposit-channel`. It accepts only `--wallet`, `--password`,
  and `--amount`, and it calls the bridge `withdraw` path to move value from the channel L2 accounting vault back into
  the shared bridge-level `bridgeTokenVault`.
- `recover-workspace` reconstructs the latest channel `state_snapshot.json` from bridge events starting at the stored
  `genesisBlockNumber` and writes it into `workspaces/<channel-name>/`.
- `wallets` store per-user note plaintexts, classify notes into used vs unused sets, maintain aggregated
  unused-note balance, and keep a value-sorted unused-note order for efficient spend selection.
- Channel workspaces are optional caches. User actions can reconstruct channel state directly from chain events when no
  channel workspace is present.
- Wallets are mandatory for note-carrying users. They are the authoritative local record for note plaintexts,
  note usage, and per-user L2 nonce.
- Wallet folders are encrypted at rest. Only `register-channel` sets up L1/L2 keys in the active wallet.
- `install-zk-evm` currently requires an Alchemy Ethereum RPC URL, because the underlying `tokamak-cli --install`
  implementation only accepts Alchemy mainnet or sepolia URLs and extracts the API key from that URL.
- Before `install-zk-evm` runs `tokamak-cli --install`, it fetches `origin/dev` in the Tokamak zk-EVM submodule,
  switches to the local `dev` branch, and fast-forwards that branch to the latest remote commit. If the submodule has
  local changes other than the cleared-worktree state produced by `uninstall-zk-evm`, the command fails instead of
  overwriting them.
- `uninstall-zk-evm` preserves the submodule pointer itself but removes the checked-out working tree contents that
  `install-zk-evm` relies on.
- `mint-notes` maps the `--amounts` vector length to the underlying fixed-arity `mintNotes<N>` controller method.
- `redeem-notes` always maps to `redeemNotes1` and credits the wallet owner's own L2 liquid balance.
- `transfer-notes` maps the `--note-ids.length` and `--recipients.length` pair to `transferNotes1To1`,
  `transferNotes1To2`, or `transferNotes2To1`.
- If a ready channel workspace exists for the wallet channel, `mint-notes` uses that cached `state_snapshot.json`
  first. If `tokamak-cli --verify` fails, the CLI refreshes the workspace through `recover-workspace` semantics and retries once.
- `redeem-notes` uses the same cached-workspace / recover-and-retry flow as `mint-notes`.
- `transfer-notes` uses the same cached-workspace / recover-and-retry flow as `mint-notes`.
- After a successful `mint-notes`, the CLI stores the resulting note plaintexts in the encrypted wallet and updates the
  channel workspace snapshot when that workspace exists.
- After a successful `redeem-notes`, the CLI marks the redeemed input note as spent in the encrypted wallet and updates
  the channel workspace snapshot when that workspace exists.
- After a successful `transfer-notes`, the CLI updates both spent input notes and newly received output notes inside
  the encrypted wallet and updates the channel workspace snapshot when that workspace exists.
- `transfer-notes` also prints the output note plaintext plus bridge commitment keys so the recipient can import that
  note through `import-notes`.
- `import-notes` is the explicit recipient-side handoff step. The CLI cannot auto-refresh another wallet because that
  wallet is encrypted under a different password.
- `get-my-notes` reports both the wallet's local note classification and whether each note still matches the
  bridge-accepted controller state.
- The `noteId` values consumed by `transfer-notes` are note commitments from `get-my-notes`.
- `get-bridge-deposit` and `withdraw-bridge` can also recover the L1 signer from an existing
  encrypted wallet when `--wallet` and `--password` are provided.
- `is-channel-registered` also requires an existing wallet and derives its network and channel from that wallet.
- `get-wallet-address` also requires an existing wallet and derives its network and channel from that wallet.
- `get-channel-deposit` also requires an existing wallet and fails unless the wallet's L2 identity matches the
  on-chain channel registration for the stored channel.
- `deposit-channel` requires an existing wallet and derives its network, channel, and signer keys from that wallet.
- `withdraw-channel` requires an existing wallet and derives its network, channel, and signer keys from that wallet.
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

node apps/private-state/cli/private-state-bridge-cli.mjs install-zk-evm \
  --rpc-url https://eth-sepolia.g.alchemy.com/v2/<key>

node apps/private-state/cli/private-state-bridge-cli.mjs uninstall-zk-evm

node apps/private-state/cli/private-state-bridge-cli.mjs recover-workspace \
  --network sepolia \
  --channel-name demo-channel \

node apps/private-state/cli/private-state-bridge-cli.mjs deposit-bridge \
  --network sepolia \
  --private-key <hex> \
  --amount 3

node apps/private-state/cli/private-state-bridge-cli.mjs withdraw-bridge \
  --wallet participant-a \
  --password "participant-a" \
  --amount 1

node apps/private-state/cli/private-state-bridge-cli.mjs get-bridge-deposit \
  --network sepolia \
  --private-key <hex>

node apps/private-state/cli/private-state-bridge-cli.mjs is-channel-registered \
  --wallet participant-a \
  --password "participant-a"

node apps/private-state/cli/private-state-bridge-cli.mjs get-wallet-address \
  --wallet participant-a \
  --password "participant-a"

node apps/private-state/cli/private-state-bridge-cli.mjs get-channel-deposit \
  --wallet participant-a \
  --password "participant-a"

node apps/private-state/cli/private-state-bridge-cli.mjs mint-notes \
  --wallet participant-a \
  --password "participant-a" \
  --amounts '[1,2,3]'

node apps/private-state/cli/private-state-bridge-cli.mjs redeem-notes \
  --wallet participant-a \
  --password "participant-a" \
  --note-id 0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa

node apps/private-state/cli/private-state-bridge-cli.mjs transfer-notes \
  --wallet participant-a \
  --password "participant-a" \
  --note-ids '["0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"]' \
  --recipients '["0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"]' \
  --amounts '[3]'

node apps/private-state/cli/private-state-bridge-cli.mjs get-my-notes \
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

node apps/private-state/cli/private-state-bridge-cli.mjs withdraw-channel \
  --wallet participant-a \
  --password "participant-a" \
  --amount 0.5
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

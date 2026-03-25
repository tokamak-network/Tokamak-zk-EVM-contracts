# private-state CLI

This folder contains the terminal CLI for the private-state DApp.

## Structure

- `private-state-bridge-cli.mjs`: the bridge-coupled L2 user workflow CLI
- `workspace/`: per-channel workspace roots
- `workspace/<channel>/channel/`: channel state, snapshots, and channel-level operations
- `workspace/<channel>/wallets/`: per-user wallets for that channel

Legacy CLI data under the old `workspaces/` and `wallets/` roots is migrated into the new `workspace/` layout on access.

The bridge-coupled CLI auto-selects the bridge deployment and ABI manifest from the chosen network, reconstructs or
loads the channel state snapshot, maintains per-user note wallets, generates proofs, and submits the resulting bridge
transactions for the supported direct commands.

Every CLI `--amount` input is interpreted as a human Tokamak Network Token amount. The CLI converts it into base units
with the canonical token `decimals()` for the selected channel.
Every CLI `--password` input accepts any string. During `register-channel` and other wallet-aware
flows, the CLI signs a domain-separated message that binds both the selected channel name and the user's password to
the user's L1 `--private-key`, uses the resulting signature as the seed for `deriveL2KeysFromSignature`, and derives
the channel-specific L2 identity that is stored in the channel wallet.
Existing wallets created before this channel-bound derivation rule are not supported and must be recreated with
`register-channel`.

## Usage

```bash
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
  `--recipients.length`. It also writes each output note into the deterministic recipient wallet folder inbox.
- `get-my-notes` reads the local wallet's tracked note sets and checks each note's commitment/nullifier status against
  the current controller state accepted by the bridge. It accepts only `--wallet` and `--password`.
- `register-channel` registers the caller's L2 address, L2 `channelTokenVault` key, and `channelTokenVault` leaf index in the selected channel.
  It does not accept `--wallet`. The wallet folder name is fixed to `<channelName>-<l2Address>`, and the command
  returns that generated wallet name in its JSON output. Channel selection still uses `--channel-name` or `--workspace`.
- `deposit-channel` moves value from the shared bridge-level `bridgeTokenVault` into the selected channel's `channelTokenVault`.
  It accepts only `--wallet`, `--password`, and `--amount`, and it fails unless the local wallet already contains
  plaintext network/channel metadata plus encrypted L1/L2 key material.
- `withdraw-channel` is the wallet-only inverse of `deposit-channel`. It accepts only `--wallet`, `--password`,
  and `--amount`, and it calls the bridge `withdraw` path to move value from the channel L2 accounting vault back into
  the shared bridge-level `bridgeTokenVault`.
- `recover-workspace` reconstructs the latest channel `state_snapshot.json` from bridge events starting at the stored
  `genesisBlockNumber` and writes it into `workspace/<channel-name>/channel/`.
- `wallets` store per-user note plaintexts, classify notes into used vs unused sets, maintain aggregated
  unused-note balance, and keep a value-sorted unused-note order for efficient spend selection.
- Channel workspaces remain optional as user-managed files, but every wallet-backed command that depends on a
  `StateSnapshot` now materializes `workspace/<channel-name>/channel/` automatically when it is missing and then reruns
  from that saved workspace.
- Wallets are mandatory for note-carrying users. They are the authoritative local record for note plaintexts,
  note usage, and per-user L2 nonce.
- Wallet folders are encrypted at rest. Only `register-channel` sets up L1/L2 keys in the active wallet.
  Recipient inbox sidecars are the exception: `transfer-notes` writes pending note plaintext into
  `incoming-notes.json` under the recipient wallet folder because the sender does not know the recipient password.
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
- `mint-notes`, `redeem-notes`, `transfer-notes`, `deposit-channel`, `withdraw-channel`, `get-channel-deposit`, and
  `get-my-notes` all follow the same workspace rule: if `workspace/<channel-name>/channel/` is missing, the CLI
  rebuilds it through `recover-workspace` semantics, saves it, reloads it from disk, and only then runs the command.
  If the saved workspace snapshot is stale, the CLI refreshes that workspace on disk and reruns from the refreshed
  saved workspace.
- For `mint-notes`, `redeem-notes`, and `transfer-notes`, a `tokamak-cli --verify` failure is also treated as a
  recoverable workspace issue. The CLI refreshes the saved workspace and retries once from that refreshed workspace.
- After a successful `mint-notes`, the CLI stores the resulting note plaintexts in the encrypted wallet and updates the
  saved channel workspace snapshot.
- After a successful `redeem-notes`, the CLI marks the redeemed input note as spent in the encrypted wallet and updates
  the saved channel workspace snapshot.
- After a successful `transfer-notes`, the CLI updates both spent input notes and newly received output notes inside
  the sender's encrypted wallet and updates the saved channel workspace snapshot.
- `transfer-notes` also prints the output note plaintext plus bridge commitment keys and writes those notes into
  `apps/private-state/cli/workspace/<channel-name>/wallets/<channelName>-<recipientL2Address>/incoming-notes.json`.
- The recipient's next wallet-backed command absorbs that inbox into the encrypted wallet and clears the inbox file.
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
- Because recipient passwords are not available to the sender, `transfer-notes` cannot rewrite another user's
  encrypted `wallet.json` directly. It stages recipient notes in inbox sidecars, and the recipient's next wallet-backed
  command absorbs that inbox into the encrypted wallet.

## Getter Output Formats

Each getter prints a single JSON object to stdout.

### `get-bridge-deposit`

```json
{
  "action": "get-bridge-deposit",
  "wallet": "<wallet-name-or-null>",
  "l1Address": "<address>",
  "bridgeTokenVault": "<address>",
  "canonicalAsset": "<address>",
  "canonicalAssetDecimals": 18,
  "availableBalanceBaseUnits": "<uint256-string>",
  "availableBalanceTokens": "<decimal-string>"
}
```

### `is-channel-registered`

```json
{
  "action": "is-channel-registered",
  "wallet": "<wallet-name>",
  "network": "anvil|sepolia|mainnet",
  "channelName": "<channel-name>",
  "l1Address": "<address>",
  "walletL2Address": "<address>",
  "walletL2StorageKey": "<bytes32>",
  "registrationExists": true,
  "matchesWallet": true,
  "registeredL2Address": "<address-or-null>",
  "registeredL2StorageKey": "<bytes32-or-null>",
  "registeredLeafIndex": "<string-or-null>"
}
```

### `get-wallet-address`

```json
{
  "action": "get-wallet-address",
  "wallet": "<wallet-name>",
  "network": "anvil|sepolia|mainnet",
  "channelName": "<channel-name>",
  "l1Address": "<address>",
  "l2Address": "<address>",
  "registeredLeafIndex": "<string>"
}
```

### `get-channel-deposit`

```json
{
  "action": "get-channel-deposit",
  "wallet": "<wallet-name>",
  "network": "anvil|sepolia|mainnet",
  "channelName": "<channel-name>",
  "l1Address": "<address>",
  "walletL2Address": "<address>",
  "walletL2StorageKey": "<bytes32>",
  "registeredLeafIndex": "<string>",
  "channelDepositBaseUnits": "<uint256-string>",
  "channelDepositTokens": "<decimal-string>",
  "canonicalAsset": "<address>",
  "canonicalAssetDecimals": 18,
  "l2AccountingVault": "<address>"
}
```

### `get-my-notes`

```json
{
  "action": "get-my-notes",
  "wallet": "<wallet-name>",
  "network": "anvil|sepolia|mainnet",
  "channelName": "<channel-name>",
  "controller": "<address>",
  "unusedNotes": [
    {
      "owner": "<l2-address>",
      "valueBaseUnits": "<uint256-string>",
      "valueTokens": "<decimal-string>",
      "commitment": "<bytes32>",
      "nullifier": "<bytes32>",
      "walletStatus": "unused|spent",
      "bridgeCommitmentExists": true,
      "bridgeNullifierUsed": false,
      "walletStatusMatchesBridge": true,
      "sourceFunction": "<string-or-null>",
      "sourceTxHash": "<tx-hash-or-null>"
    }
  ],
  "spentNotes": [],
  "unusedTotalBaseUnits": "<uint256-string>",
  "unusedTotalTokens": "<decimal-string>",
  "spentTotalBaseUnits": "<uint256-string>",
  "spentTotalTokens": "<decimal-string>",
  "bridgeStatusMismatches": 0
}
```

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
  --wallet demo-channel-<l2Address> \
  --password "participant-a" \
  --amount 1

node apps/private-state/cli/private-state-bridge-cli.mjs get-bridge-deposit \
  --network sepolia \
  --private-key <hex>

node apps/private-state/cli/private-state-bridge-cli.mjs is-channel-registered \
  --wallet demo-channel-<l2Address> \
  --password "participant-a"

node apps/private-state/cli/private-state-bridge-cli.mjs get-wallet-address \
  --wallet demo-channel-<l2Address> \
  --password "participant-a"

node apps/private-state/cli/private-state-bridge-cli.mjs get-channel-deposit \
  --wallet demo-channel-<l2Address> \
  --password "participant-a"

node apps/private-state/cli/private-state-bridge-cli.mjs mint-notes \
  --wallet demo-channel-<l2Address> \
  --password "participant-a" \
  --amounts '[1,2,3]'

node apps/private-state/cli/private-state-bridge-cli.mjs redeem-notes \
  --wallet demo-channel-<l2Address> \
  --password "participant-a" \
  --note-id 0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa

node apps/private-state/cli/private-state-bridge-cli.mjs transfer-notes \
  --wallet demo-channel-<l2Address> \
  --password "participant-a" \
  --note-ids '["0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"]' \
  --recipients '["0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"]' \
  --amounts '[3]'

node apps/private-state/cli/private-state-bridge-cli.mjs get-my-notes \
  --wallet demo-channel-<l2Address> \
  --password "participant-a"

node apps/private-state/cli/private-state-bridge-cli.mjs register-channel \
  --channel-name demo-channel \
  --network sepolia \
  --private-key <hex> \
  --password "participant-a"

# Then use the returned wallet name: demo-channel-<l2Address>

node apps/private-state/cli/private-state-bridge-cli.mjs deposit-channel \
  --wallet demo-channel-<l2Address> \
  --password "participant-a" \
  --amount 1.5

node apps/private-state/cli/private-state-bridge-cli.mjs withdraw-channel \
  --wallet demo-channel-<l2Address> \
  --password "participant-a" \
  --amount 0.5
```

Channel-workspace caches live under:

```text
apps/private-state/cli/workspace/<workspace>/channel/
```

Per-wallet operations and note ledgers live under:

```text
apps/private-state/cli/workspace/<channel-name>/wallets/<wallet>/
```

Each wallet is persisted as:

```text
apps/private-state/cli/workspace/<channel-name>/wallets/<wallet>/wallet.json
```

`register-channel` fixes `<wallet>` to:

```text
<channelName>-<l2Address>
```

Each wallet also stores unencrypted metadata as:

```text
apps/private-state/cli/workspace/<channel-name>/wallets/<wallet>/wallet.metadata.json
```

Pending recipient transfers are staged as:

```text
apps/private-state/cli/workspace/<channel-name>/wallets/<wallet>/incoming-notes.json
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

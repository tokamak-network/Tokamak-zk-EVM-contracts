# Private State zk-note DApp

private-state is a bridge-coupled zk-note style payment DApp for the Tokamak Network Token.
Canonical asset custody remains on L1. The DApp keeps accounting balances and note state on the proving-based L2 side,
while the bridge accepts proof-backed state transitions.

## Scope

The user-facing state machine is:

1. fund the shared L1 bridge vault
2. register a channel-specific L2 identity
3. move value into the channel L2 accounting vault
4. mint notes from liquid accounting balance
5. transfer notes by consuming input notes and creating output notes
6. redeem notes back into liquid accounting balance
7. move value back from the channel L2 accounting vault into the shared L1 bridge vault
8. claim the shared L1 bridge deposit back into the user's L1 wallet

This repository does not implement note-ownership privacy inside the DApp contracts themselves. Privacy depends on the
surrounding proving-based L2 execution model.

## Contract Layout

- `src/L2AccountingVault.sol`: stores per-account L2 accounting balances only
- `src/PrivateStateController.sol`: reconstructs commitments and nullifiers from calldata and applies note/accounting transitions

## Deployment Inputs

private-state app deployment uses `apps/.env`.

Required variables:

- `APPS_DEPLOYER_PRIVATE_KEY`
- `APPS_NETWORK`
- `APPS_ALCHEMY_API_KEY`
- `APPS_ETHERSCAN_API_KEY` when block explorer verification is needed

For `APPS_NETWORK=anvil`, scripts default to `http://127.0.0.1:8545`.

Successful deployments write app-local artifacts into `apps/private-state/deploy`:

- `deployment.<chain-id>.<timestamp>.json`
- `deployment.<chain-id>.latest.json`
- `storage-layout.<chain-id>.<timestamp>.json`
- `storage-layout.<chain-id>.latest.json`
- `PrivateStateController.callable-abi.json`
- `L2AccountingVault.callable-abi.json`

## Local Commands

The DApp Makefile exposes the shortest local workflows:

```bash
cd apps/private-state
make help
make anvil-start
make anvil-bootstrap
make test
make deploy-sepolia
make deploy-mainnet
make cli-bridge-help
make e2e-bridge-cli
```

## CLI Overview

The bridge-coupled CLI entrypoint is:

```bash
node apps/private-state/cli/private-state-bridge-cli.mjs <command> ...
```

The CLI:

- selects the network from `--network` or wallet metadata
- reads the bridge deployment manifest and ABI manifest from `bridge/deployments/`
- binds every channel to the canonical Tokamak Network Token for the selected network
- stores channel state under `apps/private-state/cli/workspace/<channel>/channel/`
- stores per-user wallets under `apps/private-state/cli/workspace/<channel>/wallets/<wallet>/`
- materializes or refreshes saved channel workspaces automatically for wallet-backed snapshot commands

Important rules:

- `--amount` is always a human token amount and is converted with the canonical token decimals
- `--password` accepts any string
- `register-channel` binds `channelName + password` to the user's L1 private key and derives the channel-specific L2 identity
- `register-channel` is the only command that sets up encrypted L1/L2 wallet keys
- wallet folder names are fixed to `<channelName>-<l2Address>`
- recipient note delivery is staged through `incoming-notes.json` because the sender does not know the recipient password
- `anvil` support exists only for command-driven local end-to-end testing

## CLI Command Flow

The commands below are ordered by the normal execution flow.

### 1. Install or remove the local zk-EVM toolchain

`install-zk-evm`

- installs the local Tokamak zk-EVM toolchain through `submodules/Tokamak-zk-EVM/tokamak-cli --install`
- accepts only `--rpc-url`
- requires an Alchemy Ethereum mainnet or sepolia RPC URL because the upstream installer extracts the API key from that URL
- fetches `origin/dev` inside the submodule, switches to `dev`, and fast-forwards before running the installer

Example:

```bash
node apps/private-state/cli/private-state-bridge-cli.mjs install-zk-evm \
  --rpc-url https://eth-sepolia.g.alchemy.com/v2/<key>
```

`uninstall-zk-evm`

- removes the checked-out contents of `submodules/Tokamak-zk-EVM/`
- preserves the submodule pointer itself
- accepts no options

Example:

```bash
node apps/private-state/cli/private-state-bridge-cli.mjs uninstall-zk-evm
```

### 2. Create the channel

`create-channel`

- creates the bridge channel on-chain
- binds the channel to the canonical Tokamak Network Token for the selected network
- optionally creates the saved channel workspace with `--create-workspace`

Example:

```bash
node apps/private-state/cli/private-state-bridge-cli.mjs create-channel \
  --channel-name demo-channel \
  --dapp-label private-state \
  --private-key <hex> \
  --create-workspace \
  --network sepolia
```

### 3. Rebuild or refresh the saved channel workspace

`recover-workspace`

- reconstructs the latest channel snapshot from bridge events
- writes the saved workspace into `apps/private-state/cli/workspace/<channel-name>/channel/`
- is optional in the happy path because wallet-backed snapshot commands now materialize and refresh the saved workspace automatically

Example:

```bash
node apps/private-state/cli/private-state-bridge-cli.mjs recover-workspace \
  --network sepolia \
  --channel-name demo-channel
```

### 4. Fund the shared L1 bridge vault

`deposit-bridge`

- deposits Tokamak Network Token into the shared bridge-level `bridgeTokenVault`
- does not register the user in the channel

Example:

```bash
node apps/private-state/cli/private-state-bridge-cli.mjs deposit-bridge \
  --network sepolia \
  --private-key <hex> \
  --amount 3
```

`get-bridge-deposit`

- reads the caller's balance in the shared bridge-level `bridgeTokenVault`

Example:

```bash
node apps/private-state/cli/private-state-bridge-cli.mjs get-bridge-deposit \
  --network sepolia \
  --private-key <hex>
```

### 5. Register the channel-specific wallet and L2 identity

`register-channel`

- derives the channel-specific L2 identity
- registers the caller's L2 address, channel token-vault storage key, and leaf index on-chain
- creates the encrypted wallet
- returns the deterministic wallet name `<channelName>-<l2Address>`
- accepts `--channel-name`, `--network`, `--private-key`, and `--password`

Example:

```bash
node apps/private-state/cli/private-state-bridge-cli.mjs register-channel \
  --channel-name demo-channel \
  --network sepolia \
  --private-key <hex> \
  --password "participant-a"
```

### 6. Inspect bridge-side registration derived from the wallet

`is-channel-registered`

- checks whether the wallet's stored L2 identity matches the on-chain registration
- accepts only `--wallet` and `--password`

Example:

```bash
node apps/private-state/cli/private-state-bridge-cli.mjs is-channel-registered \
  --wallet demo-channel-<l2Address> \
  --password "participant-a"
```

`get-wallet-address`

- reads the registered L2 address for the wallet's channel registration
- accepts only `--wallet` and `--password`

Example:

```bash
node apps/private-state/cli/private-state-bridge-cli.mjs get-wallet-address \
  --wallet demo-channel-<l2Address> \
  --password "participant-a"
```

### 7. Move value into the channel L2 accounting vault

`deposit-channel`

- moves value from the shared bridge-level `bridgeTokenVault` into the channel-level L2 accounting vault
- accepts only `--wallet`, `--password`, and `--amount`
- requires an existing wallet with plaintext network/channel metadata and encrypted L1/L2 keys

Example:

```bash
node apps/private-state/cli/private-state-bridge-cli.mjs deposit-channel \
  --wallet demo-channel-<l2Address> \
  --password "participant-a" \
  --amount 1.5
```

`get-channel-deposit`

- reads the wallet's current channel-level L2 accounting deposit
- accepts only `--wallet` and `--password`

Example:

```bash
node apps/private-state/cli/private-state-bridge-cli.mjs get-channel-deposit \
  --wallet demo-channel-<l2Address> \
  --password "participant-a"
```

### 8. Mint notes from liquid accounting balance

`mint-notes`

- mints one to six notes
- accepts only `--wallet`, `--password`, and `--amounts`
- maps the `--amounts` vector length to the underlying `mintNotes<N>` controller entrypoint
- stores the resulting note plaintexts in the encrypted wallet

Example:

```bash
node apps/private-state/cli/private-state-bridge-cli.mjs mint-notes \
  --wallet demo-channel-<l2Address> \
  --password "participant-a" \
  --amounts '[1,2,3]'
```

### 9. Inspect tracked notes

`get-my-notes`

- reads the wallet's tracked note sets
- checks each note's commitment and nullifier status against the current controller state accepted by the bridge
- accepts only `--wallet` and `--password`

Example:

```bash
node apps/private-state/cli/private-state-bridge-cli.mjs get-my-notes \
  --wallet demo-channel-<l2Address> \
  --password "participant-a"
```

### 10. Transfer notes

`transfer-notes`

- executes one of `transferNotes1To1`, `transferNotes1To2`, or `transferNotes2To1`
- accepts only `--wallet`, `--password`, `--note-ids`, `--recipients`, and `--amounts`
- requires JSON arrays for all vector inputs
- requires `--amounts.length == --recipients.length`
- consumes note commitments returned by `get-my-notes`
- updates the sender wallet and stages recipient notes in deterministic recipient inbox files

Example:

```bash
node apps/private-state/cli/private-state-bridge-cli.mjs transfer-notes \
  --wallet demo-channel-<l2Address> \
  --password "participant-a" \
  --note-ids '["0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"]' \
  --recipients '["0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"]' \
  --amounts '[3]'
```

### 11. Redeem notes back into liquid accounting balance

`redeem-notes`

- executes `redeemNotes1`
- accepts only `--wallet`, `--password`, and `--note-id`
- marks the redeemed note as spent in the encrypted wallet

Example:

```bash
node apps/private-state/cli/private-state-bridge-cli.mjs redeem-notes \
  --wallet demo-channel-<l2Address> \
  --password "participant-a" \
  --note-id 0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
```

### 12. Move value back out of the channel and then out of the bridge

`withdraw-channel`

- moves value from the channel L2 accounting vault back into the shared bridge-level `bridgeTokenVault`
- accepts only `--wallet`, `--password`, and `--amount`

Example:

```bash
node apps/private-state/cli/private-state-bridge-cli.mjs withdraw-channel \
  --wallet demo-channel-<l2Address> \
  --password "participant-a" \
  --amount 0.5
```

`withdraw-bridge`

- claims Tokamak Network Token from the shared bridge-level `bridgeTokenVault` back into the caller's L1 wallet
- accepts only `--wallet`, `--password`, and `--amount`

Example:

```bash
node apps/private-state/cli/private-state-bridge-cli.mjs withdraw-bridge \
  --wallet demo-channel-<l2Address> \
  --password "participant-a" \
  --amount 1
```

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

## CLI Storage Layout

Saved channel data lives under:

```text
apps/private-state/cli/workspace/<channel-name>/channel/
```

Wallet data lives under:

```text
apps/private-state/cli/workspace/<channel-name>/wallets/<wallet>/
```

Important files:

- `wallet.json`: encrypted wallet state
- `wallet.metadata.json`: plaintext `network` and `channelName`
- `incoming-notes.json`: staged recipient note delivery

## Local anvil Workflow

The shortest local workflow is:

```bash
cd apps/private-state
make anvil-start
make anvil-bootstrap
make test
make anvil-stop
```

The CLI also supports a command-driven local end-to-end flow:

```bash
cd apps/private-state
make e2e-bridge-cli
```

## Security Tradeoffs

- note validity and spend authorization are still checked directly in contract code
- the system still relies on invariants between the controller and the accounting vault
- privacy depends on the surrounding L2 execution model, not only on the contracts
- note plaintexts and note-spend history remain local wallet state and cannot be reconstructed from bridge events alone

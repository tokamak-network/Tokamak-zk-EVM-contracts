# Private State zk-note DApp

private-state is a bridge-coupled zk-note payment DApp for the Tokamak Network Token.
Canonical asset custody remains on L1. The DApp keeps accounting balances and note state on the proving-based L2 side,
while the bridge accepts proof-backed state transitions.

## Scope

The user-facing state machine is:

1. fund the shared L1 bridge vault
2. join a channel-specific L2 identity
3. move value into the channel L2 accounting vault
4. mint notes from liquid accounting balance
5. transfer notes by consuming input notes and creating encrypted output payloads
6. recover received notes from bridge-propagated event logs
7. redeem notes back into liquid accounting balance
8. move value back from the channel L2 accounting vault into the shared L1 bridge vault
9. claim the shared L1 bridge deposit back into the user's L1 wallet

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

Successful deployments also refresh the checked-in Synthesizer private-state launch inputs under:

- `submodules/Tokamak-zk-EVM/packages/frontend/synthesizer/examples/privateState/`
- `submodules/Tokamak-zk-EVM/packages/frontend/synthesizer/.vscode/launch.json`

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

- requires `--network` on bridge-facing commands that do not already have a local wallet
- does not read `apps/.env`
- rebuilds wallet-backed providers from the wallet metadata `rpcUrl`
- reads the bridge deployment manifest and ABI manifest from `bridge/deployments/`
- binds every channel to the canonical Tokamak Network Token for the selected network
- stores channel state under `apps/private-state/cli/workspace/<channel>/channel/`
- stores per-user wallets under `apps/private-state/cli/workspace/<channel>/wallets/<wallet>/`
- materializes or refreshes saved channel workspaces automatically for wallet-backed snapshot commands

Important rules:

- `--amount` is always a human token amount and is converted with the canonical token decimals
- `--password` accepts any string
- `join-channel` binds `channelName + password` to the user's L1 private key and derives the channel-specific L2 identity
- `join-channel` is the only command that sets up encrypted L1/L2 wallet keys
- wallet folder names are fixed to `<channelName>-<l2Address>`
- recipient note delivery is recovered from bridge-propagated Ethereum event logs through `get-my-notes`
- `anvil` support exists only for command-driven local end-to-end testing

## Recipient Note Delivery

The protocol-level recipient note delivery design is documented in
[NOTE_RECEIVE_KEY_PLAN.md](NOTE_RECEIVE_KEY_PLAN.md).

The current implementation includes:

- a channel-scoped note-receive auxiliary public key registered on-chain
- deterministic recovery of the corresponding auxiliary private key from a fixed MetaMask-compatible typed-data signature
- recipient note ciphertext publication on Ethereum
- recipient note salt derived from the encrypted payload
- bridge propagation of DApp event logs emitted from channel execution
- wallet-side event-log scanning and decryption in `get-my-notes`

## CLI Command Flow

The commands below are ordered by the normal execution flow.

### 1. Install or remove the local zk-EVM toolchain

`install-zk-evm`

- installs the local Tokamak zk-EVM toolchain through `submodules/Tokamak-zk-EVM/tokamak-cli --install`
- accepts no options
- bootstraps `submodules/Tokamak-zk-EVM` from the repository `.gitmodules` definition if the submodule worktree is missing
- then fetches `origin/dev` inside the submodule, switches to `dev`, and fast-forwards before running the installer

`uninstall-zk-evm`

- removes the checked-out contents of `submodules/Tokamak-zk-EVM/`
- preserves the submodule pointer itself
- accepts no options

### 2. Create the channel

`create-channel`

- creates the bridge channel on-chain
- always binds the channel to the `private-state` DApp
- always creates the saved channel workspace for the channel
- requires `--alchemy-api-key` on public networks

Example:

```bash
node apps/private-state/cli/private-state-bridge-cli.mjs create-channel \
  --channel-name demo-channel \
  --private-key <hex> \
  --alchemy-api-key <key> \
  --network sepolia
```

### 3. Rebuild or refresh the saved channel workspace

`recover-workspace`

- reconstructs the latest channel snapshot from bridge events
- writes the saved workspace into `apps/private-state/cli/workspace/<channel-name>/channel/`
- reuses existing local artifacts when their hashes still match the current on-chain channel state
- is optional in the happy path because wallet-backed snapshot commands now materialize and refresh the saved workspace automatically
- requires `--alchemy-api-key` on public networks

### 4. Fund the shared L1 bridge vault

`deposit-bridge`

- deposits Tokamak Network Token into the shared bridge-level `bridgeTokenVault`
- does not register the user in the channel
- requires `--alchemy-api-key` on public networks

`get-my-bridge-fund`

- reads the caller's balance in the shared bridge-level `bridgeTokenVault`
- requires `--network`, `--private-key`, and `--alchemy-api-key` on public networks

### 5. Join the channel-specific wallet and L2 identity

`join-channel`

- derives the channel-specific L2 identity
- registers the caller's L2 address, channel token-vault storage key, leaf index, and note-receive public key on-chain
- creates the encrypted wallet
- stores the resolved `rpcUrl` in the wallet metadata so later wallet-backed commands do not need CLI RPC inputs
- returns the deterministic wallet name `<channelName>-<l2Address>`
- requires `--alchemy-api-key` on public networks

`recover-wallet`

- rebuilds the encrypted wallet only up to the subset that can be recovered from the current channel workspace, channel registration, and bridge-propagated encrypted note logs
- recreates the channel-bound wallet keys from `--channel-name`, `--password`, and `--private-key`
- resets `l2Nonce` to `0`
- stops early if the target wallet folder already exists and decrypts to valid metadata and registration state for the requested channel
- requires `--alchemy-api-key` on public networks

### 6. Inspect wallet-to-channel registration

`get-my-address`

- checks whether the wallet's stored L2 identity matches the on-chain registration
- returns the wallet L2 address, registered L2 address, storage key, leaf index, and match status
- accepts only `--wallet` and `--password`

### 7. Move value into the channel L2 accounting vault

`deposit-channel`

- moves value from the shared bridge-level `bridgeTokenVault` into the channel-level L2 accounting vault
- accepts only `--wallet`, `--password`, and `--amount`
- requires an existing wallet with plaintext network/channel metadata and encrypted L1/L2 keys

`get-my-channel-fund`

- reads the current channel L2 accounting balance bound to the wallet registration
- accepts only `--wallet` and `--password`

### 8. Mint private notes from the wallet balance

`mint-notes`

- mints one to six notes owned by the wallet's L2 address
- accepts `--wallet`, `--password`, and `--amounts`
- maps the amount-vector length to the fixed-arity `mintNotes<N>` contract entrypoint

### 9. Transfer notes

`transfer-notes`

- consumes tracked input notes and creates encrypted recipient note payloads
- accepts `--wallet`, `--password`, `--note-ids`, `--recipients`, and `--amounts`
- supports only `1->1`, `1->2`, and `2->1` note transfer shapes
- updates the sender wallet immediately and relies on recipient-side event-log recovery rather than local recipient inbox files

### 10. Recover and inspect received notes

`get-my-notes`

- scans bridge-propagated private-state transfer events from Ethereum
- decrypts note payloads addressed to the caller
- merges newly discovered notes into the encrypted wallet
- reports both unused and spent note sets plus bridge-consistency status
- accepts only `--wallet` and `--password`

### 11. Redeem notes

`redeem-notes`

- redeems one tracked note back into liquid accounting balance
- accepts `--wallet`, `--password`, and `--note-id`

### 12. Move value back to the shared L1 bridge vault

`withdraw-channel`

- moves value from the channel L2 accounting vault back into the shared bridge-level `bridgeTokenVault`
- accepts only `--wallet`, `--password`, and `--amount`

### 13. Claim the shared L1 bridge deposit

`withdraw-bridge`

- claims value from the shared bridge-level `bridgeTokenVault` back into the caller wallet
- uses explicit signer input instead of local wallet state
- requires `--amount`, `--network`, `--private-key`, and `--alchemy-api-key` on public networks

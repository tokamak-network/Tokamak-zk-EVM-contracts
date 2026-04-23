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

## Documentation

For the current protocol, contract, security, and bridge-coupling design, start from:

- [docs/index.md](docs/index.md)

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

Deployment artifacts can be materialized into `apps/private-state/deploy` by running
`apps/private-state/scripts/deploy/write-deploy-artifacts.sh`:

- `deployment.<chain-id>.<timestamp>.json`
- `deployment.<chain-id>.latest.json`
- `storage-layout.<chain-id>.<timestamp>.json`
- `storage-layout.<chain-id>.latest.json`
- `PrivateStateController.callable-abi.json`
- `L2AccountingVault.callable-abi.json`

Bridge-side DApp registration then refreshes the app-local Groth16 consumption mirror under:

- `groth16-updateTree.<chain-id>.latest.json`
- `groth16/<chain-id>/circuit_final.zkey`
- `groth16/<chain-id>/metadata.json`

Bridge-side DApp registration consumes repo-owned Synthesizer example inputs under:

- `apps/private-state/examples/synthesizer/privateState/`

## Local Commands

The DApp Makefile exposes the shortest local workflows:

```bash
cd apps/private-state
make help
make anvil-start
make anvil-bootstrap
make test
make e2e-bridge
make e2e-bridge-cli
make deploy-sepolia
make deploy-sepolia-verify
make deploy-mainnet
make deploy-mainnet-verify
make cli-bridge-help
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
- stores channel state under `~/tokamak-private-channels/workspace/<network>/<channel>/channel/`
- stores per-user wallets under `~/tokamak-private-channels/workspace/<network>/<channel>/wallets/<wallet>/`
- loads deployed proving artifacts from `apps/private-state/deploy/` for proof-backed channel and wallet commands
- may rebuild the local `updateTree` circuit before proof generation, but never reruns trusted setup
- materializes or refreshes saved channel workspaces automatically for wallet-backed snapshot commands

Important rules:

- `--amount` is always a human token amount and is converted with the canonical token decimals
- `--password` accepts any string
- `join-channel` binds `channelName + password` to the user's L1 private key and derives the channel-specific L2 identity
- `join-channel` is the only command that sets up encrypted L1/L2 wallet keys
- wallet folder names are fixed to `<channelName>-<l1Address>`
- recipient note delivery is recovered from bridge-propagated Ethereum event logs through `get-my-notes`
- `anvil` support exists only for command-driven local end-to-end testing

## Recipient Note Delivery

The protocol-level recipient note delivery design is documented in
[docs/cli-security.md](docs/cli-security.md),
[docs/cli-dapp-protocol.md](docs/cli-dapp-protocol.md), and
[docs/bridge-dapp-protocol.md](docs/bridge-dapp-protocol.md).

The current implementation includes:

- a channel-scoped note-receive auxiliary public key registered on-chain
- deterministic recovery of the corresponding auxiliary private key from a fixed MetaMask-compatible typed-data signature
- ciphertext publication on Ethereum for both transferred notes and self-minted notes
- recipient note salt derived from the encrypted payload
- bridge propagation of DApp event logs emitted from channel execution
- wallet-side event-log scanning and decryption in `get-my-notes`
- uniform event decryption for both transfer and self-mint delivery through the note-receive key path

## CLI Command Flow

The commands below are ordered by the normal execution flow.

### 1. Install or remove the local zk-EVM toolchain

`install-zk-evm`

- installs the local Tokamak zk-EVM toolchain through the published `@tokamak-zk-evm/cli` package
- accepts no options
- refreshes the local `~/.tokamak-zk-evm` runtime cache
- refreshes shared bridge constants derived from `tokamak-l2js`

`uninstall-zk-evm`

- removes the local `~/.tokamak-zk-evm` runtime cache
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
- writes the saved workspace into `~/tokamak-private-channels/workspace/<network>/<channel-name>/channel/`
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
- returns the deterministic wallet name `<channelName>-<l1Address>`
- requires `--alchemy-api-key` on public networks

`recover-wallet`

- rebuilds the encrypted wallet only up to the subset that can be recovered from the current channel workspace, channel registration, and bridge-propagated encrypted note logs
- recreates the channel-bound wallet keys from `--channel-name`, `--password`, and `--private-key`
- reclassifies every recovered current-version note into `unused` or `spent` by checking the on-chain commitment and nullifier state
- resets `l2Nonce` to `0`
- stops early if the target wallet folder already exists and decrypts to valid metadata and registration state for the requested channel
- requires `--alchemy-api-key` on public networks

### 6. Inspect wallet-to-channel registration

`get-my-address`

- checks whether the wallet's stored L2 identity matches the on-chain registration
- returns the wallet L2 address, registered L2 address, storage key, leaf index, and match status
- accepts `--wallet`, `--password`, and `--network`

### 7. Move value into the channel L2 accounting vault

`deposit-channel`

- moves value from the shared bridge-level `bridgeTokenVault` into the channel-level L2 accounting vault
- accepts `--wallet`, `--password`, `--network`, and `--amount`
- requires an existing wallet with plaintext network/channel metadata and encrypted L1/L2 keys

`get-my-channel-fund`

- reads the current channel L2 accounting balance bound to the wallet registration
- accepts `--wallet`, `--password`, and `--network`

### 8. Mint private notes from the wallet balance

`mint-notes`

- mints one to six notes owned by the wallet's L2 address
- builds self-mint ciphertext outputs and lets the controller derive note salts from the ciphertext hash
- accepts `--wallet`, `--password`, `--network`, and `--amounts`
- maps the amount-vector length to the fixed-arity `mintNotes<N>` contract entrypoint

### 9. Transfer notes

`transfer-notes`

- consumes tracked input notes and creates encrypted recipient note payloads
- accepts `--wallet`, `--password`, `--network`, `--note-ids`, `--recipients`, and `--amounts`
- supports only `1->1`, `1->2`, and `2->1` note transfer shapes
- updates the sender wallet immediately and relies on recipient-side event-log recovery rather than local recipient inbox files

### 10. Recover and inspect received notes

`get-my-notes`

- scans bridge-propagated private-state encrypted-note events from Ethereum
- decrypts both transferred note payloads and self-minted note payloads with the note-receive private key
- merges newly discovered notes into the encrypted wallet
- reconciles the wallet's current-version notes against on-chain commitment/nullifier state to classify them into `unused` and `spent`
- reports both unused and spent note sets plus bridge-consistency status
- accepts `--wallet`, `--password`, and `--network`

### 11. Redeem notes

`redeem-notes`

- redeems one or two tracked notes back into liquid accounting balance
- accepts `--wallet`, `--password`, `--network`, and `--note-ids`

### 12. Move value back to the shared L1 bridge vault

`withdraw-channel`

- moves value from the channel L2 accounting vault back into the shared bridge-level `bridgeTokenVault`
- accepts `--wallet`, `--password`, `--network`, and `--amount`

### 13. Claim the shared L1 bridge deposit

`withdraw-bridge`

- claims value from the shared bridge-level `bridgeTokenVault` back into the caller wallet
- uses explicit signer input instead of local wallet state
- requires `--amount`, `--network`, `--private-key`, and `--alchemy-api-key` on public networks

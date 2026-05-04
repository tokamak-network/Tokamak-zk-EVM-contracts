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

private-state app deployment uses `packages/apps/.env`.

Required variables:

- `APPS_DEPLOYER_PRIVATE_KEY`
- `APPS_ALCHEMY_API_KEY`
- `APPS_ETHERSCAN_API_KEY` when block explorer verification is needed

Pass the deployment network as `--network <anvil|sepolia|mainnet>` when running
`scripts/deploy/deploy-private-state.mjs`. For `--network anvil`, scripts
default to `http://127.0.0.1:8545`.

After a successful broadcast, `deploy-private-state.mjs` automatically
materializes deployment artifacts into
`deployment/chain-id-<chain-id>/dapps/private-state/<timestamp>/`.
The standalone `packages/apps/private-state/scripts/deploy/write-deploy-artifacts.mjs`
helper remains available for recovery or rematerialization from an existing
Foundry broadcast:

- `deployment.<chain-id>.latest.json`
- `storage-layout.<chain-id>.latest.json`
- `PrivateStateController.callable-abi.json`
- `L2AccountingVault.callable-abi.json`

Bridge-side DApp registration then writes the registered DApp snapshot in the same chain-scoped deployment layout:

- `dapp-registration.<chain-id>.json`
- `source/`

Bridge-side DApp registration consumes repo-owned Synthesizer example inputs under:

- `packages/apps/private-state/examples/synthesizer/privateState/`

## Local Commands

The DApp Makefile exposes the shortest local workflows:

```bash
cd packages/apps/private-state
make help
make anvil-start
make anvil-bootstrap
make test
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
node packages/apps/private-state/cli/private-state-bridge-cli.mjs <command> ...
```

The CLI:

- requires `--network` on bridge-facing commands that do not already have a local wallet
- does not read `packages/apps/.env`
- accepts optional `--rpc-url <URL>` on bridge-facing commands and stores it as `RPC_URL` in
  `~/tokamak-private-channels/secrets/<network>/.env`; when omitted, reads the saved network RPC URL
- rebuilds wallet-backed providers from the wallet metadata `rpcUrl`
- reads installed bridge, DApp, registration, and Groth16 artifacts from
  `~/tokamak-private-channels/dapps/private-state/chain-id-<chainId>/`
- binds every channel to the canonical Tokamak Network Token for the selected network
- stores channel state under `~/tokamak-private-channels/workspace/<network>/<channel>/channel/`
- stores per-user wallets under `~/tokamak-private-channels/workspace/<network>/<channel>/wallets/<wallet>/`
- uses the fixed Groth16 runtime workspace under `~/tokamak-private-channels/groth16/` for channel balance proofs
- may rebuild the local `updateTree` circuit before proof generation, but never reruns trusted setup during normal proof-backed commands
- materializes or refreshes saved channel workspaces automatically for wallet-backed snapshot commands

Important rules:

- `--amount` is always a human token amount and is converted with the canonical token decimals
- L1 signing commands use `--account`; create the local account secret once with `account import --private-key-file`
- wallet commands use the wallet-local default password file and do not accept explicit password arguments
- `join-channel` must create or import the wallet-local secret with either `--random-wallet-secret` or `--wallet-secret-path <PATH>`
- channel creation commits to an immutable channel policy: verifier bindings, DApp execution metadata, function layout, managed storage vector, and refund policy are fixed for that channel
- joining a channel means accepting that channel's current policy; later fixes to policy-level bugs require a new channel or migration rather than in-place mutation of the joined channel
- `join-channel` binds the channel name, wallet-local password, and local account signer to derive the channel-specific L2 identity
- `join-channel` is the only command that sets up encrypted L1/L2 wallet keys
- wallet folder names are fixed to `<channelName>-<l1Address>`
- recipient note delivery is recovered from bridge-propagated Ethereum event logs through `get-my-notes`
- `anvil` support exists only for command-driven local end-to-end testing

## Recipient Note Delivery

The protocol-level recipient note delivery design is documented in
[docs/security-model.md](docs/security-model.md) and
[docs/workflow.md](docs/workflow.md).

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

`install`

- installs the local Tokamak zk-EVM toolchain through the published `@tokamak-zk-evm/cli` package
- accepts optional `--docker` to forward `tokamak-cli --install --docker`
- supports `--docker` only on Linux hosts because that mode is implemented by the upstream Tokamak CLI
- refreshes the local Tokamak zk-EVM runtime workspace reported by `tokamak-cli --doctor`
- installs the minimal private-state deployment artifacts into
  `~/tokamak-private-channels/dapps/private-state/chain-id-<chainId>/`
- installs the latest public Groth16 MPC `circuit_final.zkey` from the Groth16 CRS Drive folder
- writes Groth16 proof outputs only under the fixed runtime workspace proof directory
- refreshes shared bridge constants derived from `tokamak-l2js`

`uninstall`

- is the CLI's only interactive command
- requires typing `I understand that the wallet secrets deleted due to this decision cannot be recovered`
- removes `~/tokamak-private-channels/`, including local wallet secrets, channel workspaces, installed private-state artifacts, and Groth16 proof artifacts
- removes the Tokamak zk-EVM runtime cache
- attempts to remove the global `@tokamak-private-dapps/private-state-cli` npm package when npm reports that it is globally installed
- accepts no options

### 2. Create the channel

`account import`

- imports `--private-key-file` into a protected local L1 account secret for later `--account` use
- does not require the source private-key file to use `0600` permissions
- keeps the canonical account secret protected; macOS/Linux uses `0600`, and Windows uses ACL repair and inspection when possible
- should be run before bridge-facing user commands that need L1 signing

`create-channel`

- creates the bridge channel on-chain
- always binds the channel to the `private-state` DApp
- always creates the saved channel workspace for the channel
- accepts optional `--rpc-url`; when omitted, reads `RPC_URL` from `~/tokamak-private-channels/secrets/<network>/.env`
- prints an immutable-channel-policy warning before sending the transaction
- should be run only after the verifier versions, DApp registration metadata, function layout, managed storage vector, and refund policy have been reviewed for the intended channel

Example:

```bash
node packages/apps/private-state/cli/private-state-bridge-cli.mjs create-channel \
  --channel-name demo-channel \
  --join-toll 0 \
  --account <account-name> \
  --rpc-url <url> \
  --network sepolia
```

### 3. Rebuild or refresh the saved channel workspace

`recover-workspace`

- reconstructs the latest channel snapshot from bridge events
- writes the saved workspace into `~/tokamak-private-channels/workspace/<network>/<channel-name>/channel/`
- reuses existing local artifacts when their hashes still match the current on-chain channel state
- is optional in the happy path because wallet-backed snapshot commands now materialize and refresh the saved workspace automatically
- accepts optional `--rpc-url`; when omitted, reads `RPC_URL` from `~/tokamak-private-channels/secrets/<network>/.env`

### 4. Fund the shared L1 bridge vault

`deposit-bridge`

- deposits Tokamak Network Token into the shared bridge-level `bridgeTokenVault`
- does not register the user in the channel
- accepts optional `--rpc-url`; when omitted, reads `RPC_URL` from `~/tokamak-private-channels/secrets/<network>/.env`

`get-my-bridge-fund`

- reads the caller's balance in the shared bridge-level `bridgeTokenVault`
- requires `--network` and `--account`; accepts optional `--rpc-url`, otherwise reads the saved network `RPC_URL`

### 5. Join the channel-specific wallet and L2 identity

`join-channel`

- derives the channel-specific L2 identity
- registers the caller's L2 address, channel token-vault storage key, leaf index, and note-receive public key on-chain
- creates the encrypted wallet
- requires exactly one wallet secret source:
  - `--random-wallet-secret` to generate a new protected wallet-local secret
  - `--wallet-secret-path <PATH>` to import an existing source secret file into the protected wallet-local secret path
- does not require the source wallet-secret file to use `0600` permissions
- stores the resolved `rpcUrl` in the wallet metadata so later wallet-backed commands do not need CLI RPC inputs
- returns the deterministic wallet name `<channelName>-<l1Address>`
- accepts optional `--rpc-url`; when omitted, reads `RPC_URL` from `~/tokamak-private-channels/secrets/<network>/.env`
- prints an immutable-channel-policy warning before first registration
- should be treated as user acceptance of the channel's fixed verifier bindings, DApp execution metadata, function layout, managed storage vector, and refund policy

`recover-wallet`

- rebuilds the encrypted wallet only up to the subset that can be recovered from the current channel workspace, channel registration, and bridge-propagated encrypted note logs
- recreates the channel-bound wallet keys from `--channel-name`, the wallet-local default password file, and `--account`
- reclassifies every recovered current-version note into `unused` or `spent` by checking the on-chain commitment and nullifier state
- resets `l2Nonce` to `0`
- stops early if the target wallet folder already exists and decrypts to valid metadata and registration state for the requested channel
- accepts optional `--rpc-url`; when omitted, reads `RPC_URL` from `~/tokamak-private-channels/secrets/<network>/.env`

### 6. Inspect wallet-to-channel registration

`get-my-wallet-meta`

- checks whether the wallet's stored L2 identity matches the on-chain registration
- returns the wallet L2 address, registered L2 address, storage key, leaf index, and match status
- accepts `--wallet` and `--network`

### 7. Move value into the channel L2 accounting vault

`deposit-channel`

- moves value from the shared bridge-level `bridgeTokenVault` into the channel-level L2 accounting vault
- accepts `--wallet`, `--network`, and `--amount`
- requires an existing wallet with plaintext network/channel metadata and encrypted L1/L2 keys

`get-my-channel-fund`

- reads the current channel L2 accounting balance bound to the wallet registration
- accepts `--wallet` and `--network`

### 8. Mint private notes from the wallet balance

`mint-notes`

- mints one to six notes owned by the wallet's L2 address
- builds self-mint ciphertext outputs and lets the controller derive note salts from the ciphertext hash
- accepts `--wallet`, `--network`, and `--amounts`
- maps the amount-vector length to the fixed-arity `mintNotes<N>` contract entrypoint

### 9. Transfer notes

`transfer-notes`

- consumes tracked input notes and creates encrypted recipient note payloads
- accepts `--wallet`, `--network`, `--note-ids`, `--recipients`, and `--amounts`
- supports only `1->1`, `1->2`, and `2->1` note transfer shapes
- updates the sender wallet immediately and relies on recipient-side event-log recovery rather than local recipient inbox files

### 10. Recover and inspect received notes

`get-my-notes`

- scans bridge-propagated private-state encrypted-note events from Ethereum
- decrypts both transferred note payloads and self-minted note payloads with the note-receive private key
- merges newly discovered notes into the encrypted wallet
- reconciles the wallet's current-version notes against on-chain commitment/nullifier state to classify them into `unused` and `spent`
- reports both unused and spent note sets plus bridge-consistency status
- accepts `--wallet` and `--network`

### 11. Redeem notes

`redeem-notes`

- redeems one or two tracked notes back into liquid accounting balance
- accepts `--wallet`, `--network`, and `--note-ids`

### 12. Move value back to the shared L1 bridge vault

`withdraw-channel`

- moves value from the channel L2 accounting vault back into the shared bridge-level `bridgeTokenVault`
- accepts `--wallet`, `--network`, and `--amount`

### 13. Claim the shared L1 bridge deposit

`withdraw-bridge`

- claims value from the shared bridge-level `bridgeTokenVault` back into the caller wallet
- uses the local `--account` signer instead of channel wallet state
- requires `--amount`, `--network`, and `--account`; accepts optional `--rpc-url`, otherwise reads the saved network `RPC_URL`

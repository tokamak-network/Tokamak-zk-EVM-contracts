# Private State zk-note DApp

private-state is a bridge-coupled zk-note payment DApp for the Tokamak Network Token.
Canonical asset custody remains on L1. The DApp keeps accounting balances and note state as
proof-backed confidential application state on the proving-based L2 side, while the bridge accepts
proof-backed state transitions.

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

This repository does not implement note-ownership privacy inside the DApp contracts themselves.
Privacy-preserving note semantics depend on the surrounding proving-based L2 execution model and
the DApp-programmed public disclosure surface.

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
- `APPS_ETHERSCAN_API_KEY` when block explorer verification is needed

Pass the deployment network as `--network <anvil|sepolia|mainnet>` when running
`scripts/deploy/deploy-private-state.mjs`. Sepolia and mainnet deployments also
require an explicit `--rpc-url <URL>` so the deployment endpoint is visible at
the command boundary. For `--network anvil`, scripts default to
`http://127.0.0.1:8545`.

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
- refreshes small stale channel and wallet workspaces from saved recovery indexes before commands that require current local state

Important rules:

- `--amount` is always a human token amount and is converted with the canonical token decimals
- commands print human-readable output by default; pass `--json` when automation needs a machine-readable result
- L1 signing commands use `--account`; create the local account secret once with `account import --private-key-file`
- wallet commands load viewing and spending authority from separate protected key files when those capabilities are needed
- `channel join` requires `--wallet-secret-path <PATH>` and reads that source file once for spending-key derivation
- `wallet export backup` backs up metadata and encrypted note payloads without exporting viewing or spending authority
- `wallet export viewing-key` and `wallet export spending-key` are the authority-bearing wallet exports; keep them separate from backups unless a full operational restore is intended
- channel creation commits to an immutable channel policy: verifier bindings, DApp execution metadata, function layout, managed storage vector, and refund policy are fixed for that channel
- joining a channel means accepting that channel's current policy; later fixes to policy-level bugs require a new channel or migration rather than in-place mutation of the joined channel
- `channel join` binds the channel name, one-time wallet secret source, and local account signer to derive the channel-specific L2 identity
- `channel join` is the first-time wallet setup command for a channel; `wallet recover-workspace`
  can later rebuild backup metadata from on-chain channel data
- canonical wallet folder names are fixed to `<channelName>-<l1Address>`, with per-registration
  wallet epochs stored below that canonical folder
- recipient note delivery is recovered from bridge-propagated Ethereum event logs through `wallet recover-workspace`
- `anvil` support exists only for command-driven local end-to-end testing
- proof-backed commands print four progress phases, `loading`, `proving`, `submitting`, and `persisting`, followed by `done`
- common failures print `Try:` recovery actions after the root error message
- LLM agents that guide human users should read the CLI package's
  [LLM Agent Guidance](cli/README.md#llm-agent-guidance). That section explains how to introduce
  private key files, local account aliases, wallet secret source files, network RPC URLs, and
  channel policy review before walking a new user through `channel join`.

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
- wallet-side event-log scanning and decryption in `wallet recover-workspace`
- uniform event decryption for both transfer and self-mint delivery through the note-receive key path

## CLI Command Flow

The commands below are ordered by the normal execution flow.

### 1. Install or remove the local zk-EVM toolchain

`help guide`

- inspects local private-state workspace state, saved network RPC configuration, deployment artifacts, channel workspace state, account secrets, wallet metadata, bridge balance, channel balance, and local note inventory when enough selectors are provided
- prints the next safe command and the reason for that recommendation
- accepts optional `--network`, `--channel-name`, `--account`, and `--wallet`
- does not accept `--rpc-url`; configure network RPC through a bridge-facing command once with `--rpc-url`, or by writing `RPC_URL=<URL>` to `~/tokamak-private-channels/secrets/<network>/.env`
- is read-only and never creates wallets, sends transactions, or changes channel state

`help doctor`

- checks private-state CLI package versions, runtime install state, Docker mode, CUDA mode, and deployment artifacts
- prints a concise human-readable table by default
- accepts `--json` to print the full machine-readable report

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
- removes `~/tokamak-private-channels/`, including local account secrets, wallet key files, channel workspaces, installed private-state artifacts, and Groth16 proof artifacts
- removes the Tokamak zk-EVM runtime cache
- attempts to remove the global `@tokamak-private-dapps/private-state-cli` npm package when npm reports that it is globally installed
- accepts no options

### 2. Create the channel

`account import`

- imports `--private-key-file` into a protected local L1 account secret for later `--account` use
- does not require the source private-key file to use `0600` permissions
- keeps the canonical account secret protected; macOS/Linux uses `0600`, and Windows uses ACL repair and inspection when possible
- should be run before bridge-facing user commands that need L1 signing

`channel create`

- creates the bridge channel on-chain
- always binds the channel to the `private-state` DApp
- always creates the saved channel workspace for the channel
- accepts optional `--rpc-url`; when omitted, reads `RPC_URL` from `~/tokamak-private-channels/secrets/<network>/.env`
- prints an immutable-channel-policy warning before sending the transaction
- should be run only after the verifier versions, DApp registration metadata, function layout, managed storage vector, and refund policy have been reviewed for the intended channel

Example:

```bash
node packages/apps/private-state/cli/private-state-bridge-cli.mjs channel create \
  --channel-name demo-channel \
  --join-toll 0 \
  --account <account-name> \
  --rpc-url <url> \
  --network sepolia
```

### 3. Rebuild or refresh the saved channel workspace

`channel recover-workspace`

- reconstructs the latest channel snapshot from bridge events
- writes the saved workspace into `~/tokamak-private-channels/workspace/<network>/<channel-name>/channel/`
- reuses existing local artifacts when their hashes still match the current on-chain channel state
- is optional in the happy path because wallet-backed snapshot commands now materialize and refresh the saved workspace automatically
- accepts optional `--rpc-url`; when omitted, reads `RPC_URL` from `~/tokamak-private-channels/secrets/<network>/.env`
- resumes RPC log scanning from the saved recovery index by default
- fails instead of silently replaying from channel genesis when no usable recovery index exists
- accepts `--source rpc --from-genesis` when the user intentionally wants to ignore the local index and replay the channel from its creation block

`channel get-meta`

- reads whether a channel exists and reports its manager, vault, join toll, refund schedule, and immutable policy snapshot
- accepts optional `--rpc-url`; when omitted, reads `RPC_URL` from `~/tokamak-private-channels/secrets/<network>/.env`
- is the lightest inspection command when a user or channel creator wants to review policy before joining or creating local wallet state

### 4. Fund the shared L1 bridge vault

`account deposit-bridge`

- deposits Tokamak Network Token into the shared bridge-level `bridgeTokenVault`
- does not register the user in the channel
- accepts optional `--rpc-url`; when omitted, reads `RPC_URL` from `~/tokamak-private-channels/secrets/<network>/.env`

`account get-bridge-fund`

- reads the caller's balance in the shared bridge-level `bridgeTokenVault`
- requires `--network` and `--account`; accepts optional `--rpc-url`, otherwise reads the saved network `RPC_URL`

### 5. Join the channel-specific wallet and L2 identity

`channel join`

- derives the channel-specific L2 identity
- registers the caller's L2 address, channel token-vault storage key, leaf index, and note-receive public key on-chain
- creates wallet note metadata, viewing-key metadata, and spending-key metadata
- requires `--wallet-secret-path <PATH>` to read an existing source secret file once for spending-key derivation
- does not require the source wallet-secret file to use `0600` permissions
- stores the resolved `rpcUrl` in the wallet metadata so later wallet-backed commands do not need CLI RPC inputs
- returns the deterministic wallet name `<channelName>-<l1Address>`
- accepts optional `--rpc-url`; when omitted, reads `RPC_URL` from `~/tokamak-private-channels/secrets/<network>/.env`
- prints an immutable-channel-policy warning before first registration
- should be treated as user acceptance of the channel's fixed verifier bindings, DApp execution metadata, function layout, managed storage vector, and refund policy

`wallet recover-workspace`

- rebuilds wallet backup metadata from the current channel workspace, channel registration, and bridge-propagated encrypted note logs
- can recreate the viewing key when the local account signer reproduces the registered viewing public key
- can recover an exited registration epoch from historical channel registration and exit events for read-only note inspection and disclosure
- reclassifies every recovered current-version note into `unused` or `spent` by checking the on-chain commitment and nullifier state
- resets `l2Nonce` to `0`
- stops early if the target wallet epoch already exists with current-version metadata for the requested channel
- accepts optional `--rpc-url`; when omitted, reads `RPC_URL` from `~/tokamak-private-channels/secrets/<network>/.env`
- resumes channel workspace scanning from the saved recovery index by default
- fails instead of silently replaying from channel genesis when no usable recovery index exists
- accepts `--from-genesis` when the user intentionally wants to rebuild channel state from the channel creation block before recovering the wallet

Wallet getter commands that need channel state, including `wallet get-meta`, `wallet get-channel-fund`, and
`wallet get-notes`, refresh stale local workspaces through saved recovery indexes before reading state when the
estimated RPC log scan fits within the 10 second pre-command budget. Automatic refresh never replays from channel
genesis; if the saved index is missing, unusable, or too far behind, the command stops and asks the user to run
`channel recover-workspace --source rpc --from-genesis` or `wallet recover-workspace --from-genesis` explicitly.

`wallet export backup`

- writes a ZIP backup for one selected wallet with `--network`, `--wallet`, and `--output`
- includes wallet note-tracking metadata and the channel workspace cache
- excludes spending keys, viewing keys, key derivation material, and plaintext note `owner`, `value`, and `salt`
- preserves commitments, nullifiers, and encrypted note payloads
- is safe to treat as a non-authorizing recovery artifact, not as a full wallet authority transfer

`wallet export viewing-key` and `wallet export spending-key`

- write secret `.key` files for viewing and spending authority respectively
- include public metadata derived from the secret, but do not include additional derivation material
- should be exported only when the target machine or custodian should receive that specific authority

`wallet import backup`, `wallet import viewing-key`, and `wallet import spending-key`

- restore backup metadata, viewing authority, and spending authority independently
- refuse to overwrite existing protected key files or backup metadata files
- validate manifests or key payloads before writing files
- together form a full operational restore only when all three artifacts are imported

### 6. Inspect wallet-to-channel registration

`wallet get-meta`

- checks whether the wallet's stored L2 identity matches the on-chain registration
- returns the wallet L2 address, registered L2 address, storage key, leaf index, and match status
- reports the on-chain registered note-receive public key when present
- accepts `--wallet` and `--network`

### 7. Move value into the channel L2 accounting vault

`wallet deposit-channel`

- moves value from the shared bridge-level `bridgeTokenVault` into the channel-level L2 accounting vault
- accepts `--wallet`, `--network`, and `--amount`
- requires an existing wallet and the matching local account secret for the wallet owner

`wallet get-channel-fund`

- reads the current channel L2 accounting balance bound to the wallet registration
- accepts `--wallet` and `--network`

### 8. Mint private notes from the wallet balance

`wallet mint-notes`

- mints one or two notes owned by the wallet's L2 address with the currently registered private-state DApp metadata
- builds self-mint ciphertext outputs and lets the controller derive note salts from the ciphertext hash
- accepts `--wallet`, `--network`, and `--amounts`
- maps the amount-vector length to the fixed-arity `mintNotes<N>` contract entrypoint
- requires the wallet spending key because minting changes the wallet's channel-local L2 state
- uses the registered note-receive public key to create self-mint ciphertext outputs for later recovery

### 9. Transfer notes

`wallet transfer-notes`

- consumes tracked input notes and creates encrypted recipient note payloads
- accepts `--wallet`, `--network`, `--note-ids`, `--recipients`, and `--amounts`
- supports only `1->1`, `1->2`, and `2->1` note transfer shapes
- updates the sender wallet immediately and relies on recipient-side event-log recovery rather than local recipient inbox files
- requires both the viewing key and the spending key: the viewing key reconstructs the plaintext input notes, and the spending key authorizes the proof-backed spend

### 10. Recover and inspect received notes

`wallet get-notes`

- scans bridge-propagated private-state encrypted-note events from Ethereum
- decrypts both transferred note payloads and self-minted note payloads with the note-receive private key
- merges newly discovered notes into wallet note metadata without persisting plaintext note secrets
- reconciles the wallet's current-version notes against on-chain commitment/nullifier state to classify them into `unused` and `spent`
- reports both unused and spent note sets plus bridge-consistency status
- reports whether a viewing key is available; without it, the command can show encrypted-only tracked note state but cannot refresh or decrypt received-note events
- accepts `--wallet` and `--network`

### 11. Redeem notes

`wallet redeem-notes`

- redeems one or two tracked notes back into liquid accounting balance
- accepts `--wallet`, `--network`, and `--note-ids`
- requires both the viewing key and the spending key for the same reason as `wallet transfer-notes`

### 12. Move value back to the shared L1 bridge vault

`wallet withdraw-channel`

- moves value from the channel L2 accounting vault back into the shared bridge-level `bridgeTokenVault`
- accepts `--wallet`, `--network`, and `--amount`

### 13. Exit the channel registration

`channel exit`

- deletes the wallet's channel registration after the channel L2 accounting balance is zero
- marks the local wallet epoch as exited and keeps it read-only for historical note inspection and evidence export
- frees the reserved token-vault leaf binding, L2 address binding, storage-key binding, and note-receive key binding
- applies the channel's time-decayed join-toll refund schedule
- accepts `--wallet` and `--network`
- does not accept `--force`; both the CLI and the bridge contract require a zero channel balance

### 14. Claim the shared L1 bridge deposit

`account withdraw-bridge`

- claims value from the shared bridge-level `bridgeTokenVault` back into the caller wallet
- uses the local `--account` signer instead of channel wallet state
- requires `--amount`, `--network`, and `--account`; accepts optional `--rpc-url`, otherwise reads the saved network `RPC_URL`

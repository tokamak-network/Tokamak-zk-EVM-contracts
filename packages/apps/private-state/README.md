# Private State zk-note DApp

private-state is a bridge-coupled zk-note payment DApp for the Tokamak Network Token.
Canonical asset custody remains on Ethereum mainnet. The DApp keeps accounting balances and note state as
proof-backed confidential application state inside Tonnel private application state, while the bridge accepts
proof-backed state transitions.

## Scope

The user-facing state machine is:

1. fund the shared Ethereum mainnet bridge vault
2. join a channel-specific private application identity
3. move value into the channel accounting vault
4. mint notes from liquid accounting balance
5. transfer notes by consuming input notes and creating encrypted output payloads
6. recover received notes from bridge-propagated event logs
7. redeem notes back into liquid accounting balance
8. move value back from the channel accounting vault into the shared Ethereum mainnet bridge vault
9. claim the shared Ethereum mainnet bridge deposit back into the user's Ethereum wallet

This repository does not implement note-ownership privacy inside the DApp contracts themselves.
Private note semantics depend on the surrounding proving-based execution model and
the DApp-programmed public disclosure surface.

## Documentation

For the current protocol, contract, security, and bridge-coupling design, start from:

- [docs/dapps/private-state/index.md](../../../docs/dapps/private-state/index.md)

## Contract Layout

- `src/L2AccountingVault.sol`: stores per-account channel accounting balances only
- `src/PrivateStateController.sol`: reconstructs commitments and nullifiers from calldata and applies note/accounting transitions

## Deployment Inputs

private-state app deployment uses `packages/apps/.env`.

Required variables:

- `APPS_DEPLOYER_PRIVATE_KEY`
- `APPS_ETHERSCAN_API_KEY` when block explorer verification is needed

Pass the deployment network as `--network <name>` when running
`scripts/deploy/deploy-private-state.mjs`. The deploy script accepts the shared app network names
from `APP_NETWORKS`: `anvil`, `sepolia`, `mainnet`, `base-sepolia`, `base-mainnet`,
`arb-sepolia`, `arb-mainnet`, `op-sepolia`, and `op-mainnet`. Every non-`anvil` deployment
requires an explicit `--rpc-url <URL>` so the deployment endpoint is visible at the command
boundary. For `--network anvil`, scripts default to `http://127.0.0.1:8545`.

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
- configures the network RPC endpoint once through `set rpc`; ordinary bridge-facing and wallet
  commands read `~/tokamak-private-channels/workspace/<network>/rpc-config.env` and do not accept
  `--rpc-url`
- records the resolved RPC URL in wallet metadata for auditability, but live providers are rebuilt
  from the current per-network RPC configuration
- reads installed bridge, DApp, registration, and Groth16 artifacts from full installs under
  `~/tokamak-private-channels/dapps/private-state/chain-id-<chainId>/`
- read-only installs include only the bridge deployment, bridge ABI manifest, DApp deployment, and storage layout
  artifacts needed by channel-state read commands
- binds every channel to the canonical Tokamak Network Token for the selected network
- stores channel state under `~/tokamak-private-channels/workspace/<network>/<channel>/channel/`
- stores per-user wallets under `~/tokamak-private-channels/workspace/<network>/<channel>/wallets/<wallet>/`
  with a wallet index and per-registration epochs under `epochs/<epoch-id>/`
- uses the fixed Groth16 runtime workspace under `~/tokamak-private-channels/groth16/` for channel balance proofs
- may rebuild the local `updateTree` circuit before proof generation, but never reruns trusted setup during normal proof-backed commands
- refreshes small stale channel and wallet workspaces from saved recovery indexes before commands that require current local state

Important rules:

- `--amount` is always a human token amount and is converted with the canonical token decimals
- commands print human-readable output by default; pass `--json` when automation needs a machine-readable final
  success or failure result on stdout
- Ethereum signing commands use `--account`; create the local account secret once with `account import --private-key-file`
- wallet commands load viewing and spending authority from separate protected key files when those capabilities are needed
- `channel join` requires `--wallet-secret-path <PATH>` and reads that source file once for spending-key derivation
- `wallet export backup` backs up metadata and encrypted note payloads without exporting viewing or spending authority
- `wallet export viewing-key` and `wallet export spending-key` are the authority-bearing wallet exports; keep them separate from backups unless a full operational restore is intended
- channel creation commits to an immutable channel policy: verifier bindings, DApp execution metadata, function layout, managed storage vector, and refund policy are fixed for that channel
- joining a channel means accepting that channel's current policy; later fixes to policy-level bugs require a new channel or migration rather than in-place mutation of the joined channel
- `channel join` binds the channel name, one-time wallet secret source, and local account signer to derive the channel-specific private application identity
- `channel join` is the first-time wallet setup command for a channel; `wallet recover-workspace`
  can later rebuild backup metadata from on-chain channel data
- canonical wallet folder names are fixed to `<channelName>-<l1Address>`, with per-registration
  wallet epochs stored below that canonical folder
- current wallet commands require this epoch-aware workspace layout; rebuild older local wallet directories with
  `wallet recover-workspace`
- recipient note delivery is recovered from bridge-propagated Ethereum event logs through `wallet recover-workspace`
- `anvil` support exists only for command-driven local end-to-end testing
- proof-backed commands print four progress phases, `loading`, `proving`, `submitting`, and `persisting`, followed by `done`;
  in `--json` mode, progress, warning, and informational events are emitted as JSON Lines on stderr
- common failures print `Try:` recovery actions after the root error message
- User-Controlled AI Agents that guide human users should read the CLI package's
  [User-Controlled AI Agent Guidance](cli/README.md#user-controlled-ai-agent-guidance). That section explains how to introduce
  private key files, local account aliases, wallet secret source files, network RPC URLs, and
  channel policy review before walking a new user through `channel join`.

## Recipient Note Delivery

The protocol-level recipient note delivery design is documented in
[docs/dapps/private-state/security-model.md](../../../docs/dapps/private-state/security-model.md) and
[docs/dapps/private-state/workflow.md](../../../docs/dapps/private-state/workflow.md).

The current implementation includes:

- a channel-scoped note-receive auxiliary public key registered on-chain
- deterministic recovery of the corresponding auxiliary private key from a fixed MetaMask-compatible typed-data signature
- ciphertext publication on Ethereum for both transferred notes and self-minted notes
- recipient note salt derived from the encrypted payload
- bridge propagation of DApp event logs emitted from channel execution
- wallet-side event-log scanning and decryption in `wallet recover-workspace`
- uniform event decryption for both transfer and self-mint delivery through the note-receive key path

## CLI Command Flow

The commands below follow the normal note-use flow; bridge funding is for channel liquidity, not Join Toll payment.
Join Toll means the one-time Channel entry fee paid when a user joins a Channel.

### 1. Install, remove, or configure the local CLI runtime

`help guide`

- inspects local private-state workspace state, saved network RPC configuration, deployment artifacts, channel workspace state, account secrets, wallet metadata, bridge balance, channel balance, and local note inventory when enough selectors are provided
- prints the next safe command and the reason for that recommendation
- accepts optional `--network`, `--channel-name`, `--account`, and `--wallet`
- does not accept `--rpc-url`; configure network RPC with `set rpc`
- is read-only and never creates wallets, sends transactions, or changes channel state

`help doctor`

- checks private-state CLI package versions, runtime install state, Docker mode, CUDA mode, and deployment artifacts
- prints a concise human-readable table by default
- accepts `--json` to print the full machine-readable report
- reports command-by-command availability for the current read-only or full install state

`install`

- defaults to full mode, which installs the local Tokamak zk-EVM toolchain through the published
  `@tokamak-zk-evm/cli` package
- accepts optional `--read-only` to install only artifacts needed by channel-state read commands and commands that do
  not depend on channel state
- accepts optional `--docker` in full mode to forward `tokamak-cli --install --docker`
- supports `--docker` only on Linux hosts because that mode is implemented by the upstream Tokamak CLI
- refreshes the local Tokamak zk-EVM runtime workspace reported by `tokamak-cli --doctor` in full mode
- installs private-state deployment artifacts into
  `~/tokamak-private-channels/dapps/private-state/chain-id-<chainId>/`
- installs the latest public Groth16 MPC `circuit_final.zkey` from the Groth16 CRS Drive folder in full mode
- writes Groth16 proof outputs only under the fixed runtime workspace proof directory in full mode
- refreshes shared bridge constants derived from `tokamak-l2js`
- displays the current Service Terms and requires explicit human acceptance before installation proceeds
- reports that interactive Terms acceptance is required without installing artifacts when run with `--json`

`uninstall`

- is intentionally interactive and requires typing the exact confirmation phrase printed by the command
- by default, removes local workspaces, account secrets, wallet secret source files stored under the CLI root, installed private-state artifacts, Groth16 workspace files, and the Tokamak zk-EVM runtime workspace
- by default, preserves wallet spending-key and viewing-key files under the CLI secret root
- accepts `--include-wallet-keys` to delete every local private-state CLI file, including wallet spending-key and viewing-key files
- removes the Tokamak zk-EVM runtime cache
- attempts to remove the global `@tokamak-private-dapps/private-state-cli` npm package when npm reports that it is globally installed

`set rpc`

- configures the network RPC URL and fixed `eth_getLogs` scan limits before bridge-facing or wallet recovery commands
- writes `~/tokamak-private-channels/workspace/<network>/rpc-config.env`
- accepts `--network`, `--rpc-url`, and either `--provider` or both `--log-requests-per-second` and `--block-range-cap`
- supports built-in provider presets for Alchemy, Ankr, Chainstack, Chainnodes, and QuickNode
- should be rerun with a provider or limits that better match the endpoint when workspace recovery is unexpectedly slow or the provider rejects the configured log range

### 2. Create the channel

`account import`

- imports `--private-key-file` into a protected local Ethereum account secret for later `--account` use
- does not require the source private-key file to use `0600` permissions
- keeps the canonical account secret protected; macOS/Linux uses `0600`, and Windows uses ACL repair and inspection when possible
- should be run before bridge-facing user commands that need Ethereum signing

`channel create`

- creates the bridge channel on-chain
- always binds the channel to the `private-state` DApp
- always creates the saved channel workspace for the channel
- reads the RPC endpoint and fixed log-scan limits from the per-network `set rpc` configuration
- prints an immutable-channel-policy warning before sending the transaction
- should be run only after the verifier versions, DApp registration metadata, function layout, managed storage vector, and refund policy have been reviewed for the intended channel

Example:

```bash
node packages/apps/private-state/cli/private-state-bridge-cli.mjs set rpc \
  --network sepolia \
  --rpc-url <url> \
  --provider <provider>

node packages/apps/private-state/cli/private-state-bridge-cli.mjs channel create \
  --channel-name demo-channel \
  --join-toll 0 \
  --account <account-name> \
  --network sepolia
```

### 3. Rebuild or refresh the saved channel workspace

`channel recover-workspace`

- reconstructs the latest channel snapshot from bridge events
- writes the saved workspace into `~/tokamak-private-channels/workspace/<network>/<channel-name>/channel/`
- reuses existing local artifacts when their hashes still match the current on-chain channel state
- is optional in the happy path because wallet-backed snapshot commands now materialize and refresh the saved workspace automatically
- reads RPC settings from `~/tokamak-private-channels/workspace/<network>/rpc-config.env`
- resumes RPC log scanning from the saved recovery index by default
- fails instead of silently replaying from channel genesis when no usable recovery index exists
- accepts `--source mirror` to recover from a registered workspace mirror without falling back to a full RPC genesis rebuild
- accepts `--source rpc --from-genesis` only when no compatible mirror is available and the user intentionally wants to ignore the local index and replay the channel from its creation block

`channel get-meta`

- reads whether a channel exists and reports its manager, vault, Join Toll, refund schedule, Channel Operation status, and immutable policy snapshot
- reads RPC settings from the per-network `set rpc` configuration
- is the lightest inspection command when a user or channel creator wants to review policy before joining or creating local wallet state

`channel abandon-operation`

- is a channel leader command that immediately records Channel Operation Abandonment on Ethereum mainnet
- disables new `channel join` and `wallet deposit-channel` actions for the selected channel
- does not block existing note activity, `wallet redeem-notes`, `wallet withdraw-channel`, or `channel exit`
- should be used only when the channel leader intends to stop onboarding and new channel deposits for that channel
- reads RPC settings from the per-network `set rpc` configuration

### 4. Join the channel-specific wallet and private application identity

`channel join`

- derives the channel-specific private application identity
- pays any Join Toll directly from the Ethereum wallet, not from bridge-deposited balance
- fails if the selected channel has been abandoned
- registers the caller's channel-local address, channel token-vault storage key, leaf index, and note-receive public key on-chain
- creates wallet note metadata, viewing-key metadata, and spending-key metadata
- requires `--wallet-secret-path <PATH>` to read an existing source secret file once for spending-key derivation
- does not require the source wallet-secret file to use `0600` permissions
- stores the resolved `rpcUrl` in the wallet metadata so later wallet-backed commands do not need CLI RPC inputs
- returns the deterministic wallet name `<channelName>-<l1Address>`
- reads RPC settings from the per-network `set rpc` configuration
- prints an immutable-channel-policy warning before first registration
- should be treated as user acceptance of the channel's fixed verifier bindings, DApp execution metadata, function layout, managed storage vector, and refund policy
- prints a command-specific warning summary before transaction submission

`wallet recover-workspace`

- rebuilds wallet backup metadata from the current channel workspace, channel registration, and bridge-propagated encrypted note logs
- can recreate the viewing key when the local account signer reproduces the registered viewing public key
- can rederive and store the spending key only when `--wallet-secret-path <PATH>` is supplied and the account has a current active channel registration
- rejects `--wallet-secret-path` for exited or non-active accounts; run without that option to recover read-only viewing/evidence history
- verifies the rederived spending key against the current on-chain channel-local address and channel token-vault storage key before received-note recovery starts
- never stores the wallet secret source file or its plaintext contents
- can recover an exited registration epoch from historical channel registration and exit events for read-only note inspection and disclosure
- reclassifies every recovered current-version note into `unused` or `spent` by checking the on-chain commitment and nullifier state
- resets `l2Nonce` to `0`
- stops early if the target wallet epoch already exists with current-version metadata for the requested channel
- reads RPC settings from the per-network `set rpc` configuration
- refreshes the channel workspace only when the saved channel recovery index delta fits the pre-command budget
- fails and asks for `channel recover-workspace` first when the channel workspace is missing, unusable, or too stale for automatic recovery
- accepts `--from-genesis` to restart received-note scanning from channel genesis; it does not rebuild the channel workspace from genesis

### 5. Fund the shared Ethereum mainnet bridge vault

`account deposit-bridge`

- deposits Tokamak Network Token into the shared bridge-level `bridgeTokenVault`
- does not register the user in the channel
- does not pay the channel Join Toll
- reads RPC settings from the per-network `set rpc` configuration
- prints a command-specific warning summary before transaction submission

`account get-bridge-fund`

- reads the caller's balance in the shared bridge-level `bridgeTokenVault`
- requires `--network` and `--account`

Wallet getter commands that need channel state, including `wallet get-meta`, `wallet get-channel-fund`, and
`wallet get-notes`, refresh stale local workspaces through saved recovery indexes before reading state when the
estimated RPC log scan fits within the 7,200-block pre-command budget. Automatic refresh never replays from channel
genesis; if the saved index is missing, unusable, or too far behind, the command stops and asks the user to run
`channel recover-workspace --source mirror` when a registered mirror is available, or
`channel recover-workspace --source rpc --from-genesis` only when no compatible mirror exists. Wallet note scanning
can still be restarted explicitly with `wallet recover-workspace --from-genesis`.

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

- checks whether the wallet's stored private application identity matches the on-chain registration
- returns the wallet channel-local address, registered channel-local address, storage key, leaf index, and match status
- reports the on-chain registered note-receive public key when present
- accepts `--wallet` and `--network`

### 7. Move value into the channel accounting vault

`wallet deposit-channel`

- moves value from the shared bridge-level `bridgeTokenVault` into the channel-level accounting vault
- accepts `--wallet`, `--network`, and `--amount`
- requires an existing wallet and the matching local account secret for the wallet owner
- fails if the selected channel has been abandoned
- prints a command-specific warning summary before transaction submission

`wallet get-channel-fund`

- reads the current channel accounting balance bound to the wallet registration
- accepts `--wallet` and `--network`

### 8. Mint private notes from the wallet balance

`wallet mint-notes`

- mints one or two notes owned by the wallet's channel-local address with the currently registered private-state DApp metadata
- builds self-mint ciphertext outputs and lets the controller derive note salts from the ciphertext hash
- accepts `--wallet`, `--network`, and `--amounts`
- accepts optional `--tx-submitter <ACCOUNT>` so a separate local Ethereum account can submit the Ethereum mainnet transaction and pay gas
- maps the amount-vector length to the fixed-arity `mintNotes<N>` contract entrypoint
- requires both viewing and spending key capability so the accepted mint can be recovered through the normal note event path
- uses the registered note-receive public key to create self-mint ciphertext outputs for later recovery
- prints an additional warning when the selected channel has been abandoned, but abandonment does not block this command
- prints a command-specific warning summary before transaction submission

### 9. Transfer notes

`wallet transfer-notes`

- consumes tracked input notes and creates encrypted recipient note payloads
- accepts `--wallet`, `--network`, `--note-ids`, `--recipients`, and `--amounts`
- requires `--note-ids` as a JSON array of note commitment IDs from `wallet get-notes`, for example `--note-ids '["0xNOTE1","0xNOTE2"]'`
- requires `--recipients` as a JSON array of recipient channel-local addresses, for example `--recipients '["0xRECIPIENT1","0xRECIPIENT2"]'`
- requires `--amounts` as a JSON array of token amounts, preferably quoted for decimals, for example `--amounts '["1.5","2"]'`
- requires `--recipients` length to equal `--amounts` length, and requires the output amount sum to equal the selected input note value sum
- accepts optional `--tx-submitter <ACCOUNT>` so a separate local Ethereum account can submit the Ethereum mainnet transaction and pay gas
- supports only `1->1`, `1->2`, and `2->1` note transfer shapes
- refreshes local workspace state after the accepted transaction and relies on recipient-side event-log recovery rather than local recipient inbox files
- requires both the viewing key and the spending key: the viewing key reconstructs the plaintext input notes, and the spending key authorizes the proof-backed spend
- prints an additional warning when the selected channel has been abandoned, but abandonment does not block this command
- prints a command-specific warning summary before transaction submission

### 10. Recover and inspect received notes

`wallet get-notes`

- refreshes received-note logs from the saved wallet recovery index when the delta fits the pre-command budget
- decrypts transferred note payloads and self-minted note payloads with the note-receive private key when viewing authority is available
- merges newly discovered notes into wallet note metadata without persisting plaintext note secrets
- reconciles the wallet's current-version notes against on-chain commitment/nullifier state to classify them into `unused` and `spent`
- reports both unused and spent note sets plus bridge-consistency status
- reports whether a viewing key is available; without it, the command can show encrypted-only tracked note state but cannot refresh or decrypt received-note events
- accepts `--wallet` and `--network`
- accepts `--export-evidence <PATH>` to write a raw evidence ZIP for `private-state-cli investigator` after interactive confirmation

### 11. Redeem notes

`wallet redeem-notes`

- redeems one tracked note back into liquid accounting balance
- accepts `--wallet`, `--network`, and `--note-ids`
- accepts optional `--tx-submitter <ACCOUNT>` so a separate local Ethereum account can submit the Ethereum mainnet transaction and pay gas
- requires both the viewing key and the spending key for the same reason as `wallet transfer-notes`
- prints an additional warning when the selected channel has been abandoned, but abandonment does not block this command
- prints a command-specific warning summary before transaction submission

### 12. Move value back to the shared Ethereum mainnet bridge vault

`wallet withdraw-channel`

- moves value from the channel accounting vault back into the shared bridge-level `bridgeTokenVault`
- accepts `--wallet`, `--network`, and `--amount`
- prints an additional warning when the selected channel has been abandoned, but abandonment does not block this command
- prints a command-specific warning summary before transaction submission

### 13. Exit the channel registration

`channel exit`

- deletes the wallet's channel registration after the channel accounting balance is zero
- marks the local wallet epoch as exited and keeps it read-only for historical note inspection and evidence export
- frees the reserved token-vault leaf binding, channel-local address binding, storage-key binding, and note-receive key binding
- applies the selected channel's fixed Join Toll refund schedule and transfers the non-refundable portion to the burn
  address
- accepts `--wallet` and `--network`
- does not accept `--force`; both the CLI and the bridge contract require a zero channel balance
- prints an additional warning when the selected channel has been abandoned, but abandonment does not block this command

### 14. Claim the shared Ethereum mainnet bridge deposit

`account withdraw-bridge`

- claims value from the shared bridge-level `bridgeTokenVault` back into the caller wallet
- uses the local `--account` signer instead of channel wallet state
- requires `--amount`, `--network`, and `--account`
- prints a command-specific warning summary before transaction submission

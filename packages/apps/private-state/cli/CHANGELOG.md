# Changelog

## Unreleased

- Removed `--source auto` from `channel recover-workspace`; recovery source is now either
  `rpc` or `mirror`.
- Required `channel recover-workspace --from-genesis` to be paired with explicit `--source rpc`
  so genesis replay cannot be requested accidentally through an omitted source.
- Restored pre-command workspace refresh for commands that require current local state, but limited
  automatic refresh to saved recovery indexes. Automatic command preflight never replays from
  genesis and points users to explicit `channel recover-workspace` or `wallet recover-workspace`
  when a genesis rebuild is required.
- Restored received-note event-log refresh for `wallet get-notes`, `wallet transfer-notes`, and
  `wallet redeem-notes`, limited to the saved wallet note recovery index.
- Limited pre-command automatic recovery to a 10 second RPC log scan budget based on the CLI's
  paced log query rate.
- Reworked workspace mirror recovery around leader-signed checkpoint manifests and
  delta bundles. When a local recovery index exists, the CLI prechecks the mirror checkpoint and
  downloads only the matching delta bundle instead of a full workspace bundle.
- Removed the version segment from workspace mirror URLs and kept the protocol version only in
  manifest and bundle metadata.
- Added `channel publish-workspace-mirror` to build static mirror files when the local workspace is
  current and ahead of the registered mirror checkpoint.
- Kept streaming checkpoint or delta bundle download progress with an estimated remaining time.

## 1.2.0 - 2026-05-08

- Added optional channel workspace mirror recovery. `channel recover-workspace` now accepts
  `--source rpc|mirror`, with `rpc` remaining the default when `--source` is omitted.
- Added `channel set-workspace-mirror` so a channel leader can register the official workspace
  mirror base URL stored in `BridgeCore`.
- Added mirror checkpoint validation that checks signed checkpoint metadata before downloading
  bundles, then validates downloaded checkpoint or delta bundle contents against on-chain channel
  metadata before replaying the remaining RPC log delta to the latest block.
- Documented the static server protocol for channel workspace mirrors.

## 1.1.1 - 2026-05-08

- Added bridge deployment verification support for Etherscan-compatible explorers, including
  proxy and implementation verification for the main bridge contracts after deploy or upgrade
  flows.
- Added an incremental ChannelManager verification script that scans channel creation events from
  the last indexed block, skips already verified channel contracts, and persists scan progress for
  later runs.
- Required `channel join` to refresh through the recovery index before joining an existing channel,
  while preserving the explicit `--from-genesis` path for recovery commands that intentionally
  rebuild workspace state from channel genesis.
- Verified the private-state CLI end-to-end flow with isolated local workspace state after the
  indexed join recovery change.

## 1.1.0 - 2026-05-06

- Required `channel join` to use an existing recovered channel workspace and refresh through the
  recovery index before submitting the join transaction, so old channels are not silently replayed
  from genesis during join. `wallet recover-workspace --from-genesis` now also replays encrypted
  note delivery logs from channel genesis for existing wallets.
- Refreshed channel workspaces through the existing recovery-indexed replay path after successful
  wallet transactions instead of manually patching local snapshots, and bounded post-transaction
  replay by the transaction receipt block so provider latest-block lag cannot skip the confirmed
  transaction logs. This prevents stale `recoveryRootVectorHash` / `recoveryLastScannedBlock`
  metadata after local state changes.
- Reported `usedWorkspaceCache` and `recoveredWorkspace` from channel vault move commands so
  automated tests can verify that follow-up wallet transactions do not replay workspace recovery
  when the local workspace is already current.
- Removed the local wallet folder and canonical wallet secret after successful `channel exit`, and
  made `wallet recover-workspace` delete stale local wallet folders and canonical wallet secrets
  when the corresponding L1 account is no longer registered on-chain.
- Improved `channel join` stale-wallet guidance. The command still does not delete stale wallets
  itself; it tells users to run `wallet recover-workspace` first, and it overwrites the canonical
  wallet secret from the provided `--wallet-secret-path` whenever a new local wallet is allowed.
- Normalized account command JSON `action` labels and CLI e2e helper names to the current
  `account`, `channel`, and `wallet` command taxonomy.
- Added `wallet export` and `wallet import` for ZIP-based local wallet backup and restore.
  The default export includes the encrypted wallet, wallet metadata, and wallet-local secret so
  an imported wallet can be used after `channel recover-workspace`. Tracked notes remain preserved
  because they live inside encrypted `wallet.json`; `--include-notes` also includes the channel
  workspace cache needed to use wallet commands immediately when that cache is still chain-aligned.
- Hardened `wallet import` error handling for invalid ZIP or manifest data and staged imported
  files in a temporary directory before committing them into the CLI data root.
- Kept account secrets out of wallet exports. Wallet commands restore their signer from the
  encrypted `wallet.json`, while account secrets remain scoped to account-level bridge-vault
  commands and optional `--tx-submitter` use.
- Reclassified user-facing commands into `account`, `channel`, `wallet`, and `help` namespaces.
  `install`, `uninstall`, and `--version` remain top-level commands.
- Renamed `get-my-l1-address` to `account get-l1-address` so account helpers live under the
  same `account` command namespace as `account import`.
- Renamed `get-my-bridge-fund` to `account get-bridge-fund` so bridge-vault balance lookup is
  grouped with account-level helpers.
- Moved bridge-vault movement commands to `account deposit-bridge` and `account withdraw-bridge`.
- Moved channel lifecycle commands to `channel create`, `channel recover-workspace`,
  `channel get-meta`, `channel join`, and `channel exit`.
- Moved wallet-local state, channel balance, and note commands to `wallet recover-workspace`,
  `wallet get-meta`, `wallet list`, `wallet deposit-channel`, `wallet withdraw-channel`,
  `wallet get-channel-fund`, `wallet mint-notes`, `wallet transfer-notes`,
  `wallet redeem-notes`, and `wallet get-notes`.
- Moved helper commands to `help commands`, `help update`, `help doctor`, `help guide`, and
  `help transaction-fees`; `--help` still prints the same command reference for shell
  compatibility.
- Updated README files, private-state workflow docs, the browser CLI assistant, transaction-fee
  command labels, and the CLI e2e harness to use the new command taxonomy.

## 1.0.2 - 2026-05-06

- Added `update`, which checks npm registry for the latest private-state CLI package and updates
  global npm installs when a newer version exists.
- Kept repository checkouts and non-global installs read-only during `update`; those modes print
  the exact `npm install -g @tokamak-private-dapps/private-state-cli@latest` command instead.
- Reused runtime-management output parsing helpers for `update` and `uninstall` instead of
  duplicating npm JSON and ANSI-output handling in the CLI entrypoint.
- Added `transaction-fees`, which reads packaged measured gas data from `assets/tx-fees.json`,
  combines it with live RPC fee data and live ETH/USD pricing, and prints a per-command ETH/USD
  fee table.
- Split `transaction-fees` estimates into typical cost from RPC `gasPrice` and worst-case cost
  from EIP-1559 `maxFeePerGas`.
- Added optional `--tx-submitter <ACCOUNT>` support to `mint-notes`, `transfer-notes`, and
  `redeem-notes` so proof-backed note owners can separate note ownership from the L1 account
  that submits `executeChannelTransaction` and pays gas.
- Expanded LLM-agent README guidance so agents explain private key files, local account aliases,
  wallet secret source files, network RPC URLs, and immutable channel policy step by step before
  guiding new users through `join-channel`.
- Added RPC log scan progress output to `recover-workspace` and `recover-wallet`, with progress
  routed to stderr in `--json` mode so machine-readable command results stay valid.
- Added `recover-wallet --from-genesis` and removed implicit genesis replay fallback from
  `recover-workspace` and `recover-wallet`; both commands now require a usable recovery index
  unless the user explicitly requests `--from-genesis`.
- Changed `get-my-wallet-meta`, `get-my-channel-fund`, and `get-my-notes` to use indexed
  recovery only before reading channel state, with `get-my-notes` also validating the wallet
  note-receive recovery index before scanning delivery logs.
- Unified wallet command workspace refresh through the same recovery-indexed path used by
  `recover-workspace`, and shared received-note recovery through the wallet's
  `noteReceiveLastScannedBlock` index.

## 1.0.1 - 2026-05-05

- Added global `--version` output for scripts that need the installed private-state CLI package
  version without running `doctor`.
- Changed the channel-bound L2 identity derivation signing domain and mode from password wording
  to wallet-secret wording. Existing local wallets from the pre-1.0.0 cleanup path are not
  compatibility targets.
- Centralized CLI command option schemas used by validation, while keeping the existing command
  implementations in the single CLI entrypoint.
- Moved private-state Tokamak L2 snapshot, storage, and leaf-index helpers into a shared CLI library
  reused by the CLI and registration materialization scripts.
- Moved runtime install, artifact install, and doctor report helpers out of the CLI entrypoint.
- Reused the same command registry for CLI help text and the browser command assistant so command
  additions no longer require three separate hardcoded updates.
- Made live Docker/NVIDIA GPU probing in `doctor` opt-in through `doctor --gpu`; the default doctor
  run now reports runtime metadata without launching GPU containers.
- Shared private-state registration fixture builders between DApp registration materialization and
  the CLI end-to-end scenario.
- Moved note receive key derivation and note value encryption/decryption into a CLI library helper
  reused by the CLI, DApp registration materializer, and CLI end-to-end scenario.
- Removed the CLI end-to-end runner's trailing-JSON fallback now that CLI progress logs are kept off
  stdout in `--json` mode.
- Required public-network private-state DApp deployment scripts to receive an explicit `--rpc-url`
  instead of deriving deployment RPC endpoints from environment-only Alchemy settings.
- Replaced local wallet recovery hint string matching with typed CLI error codes for local RPC,
  wallet, artifact, registration, and stale-workspace failures.
- Removed unused replay/synthetic snapshot helpers from the CLI end-to-end script.
- Added deterministic anvil account and wallet secret cleanup to the CLI end-to-end runner so
  repeated local runs do not fail on stale canonical secret files.
- Stopped parsing the `install --include-local-artifacts` end-to-end step as JSON because runtime
  package installation legitimately writes installer logs to stdout.
- Reused a shared artifact selection helper for Drive and local private-state artifact installs.
- Removed stale `--install` and `--doctor` compatibility aliases after the command syntax was
  standardized around positional command names.
- Tightened local wallet loading to require the current wallet format instead of silently filling
  legacy defaults.
- Renamed stale internal wallet-secret terminology consistently around wallet secrets and moved the
  canonical wallet secret path from `password` to `secret`.
- Reused private-state CLI shared helpers in the CLI end-to-end test instead of duplicating channel
  ID, wallet path, and L2 identity derivation logic.
- Fixed the browser CLI assistant's `create-channel` builder to include required `--join-toll`.
- Preserved the resolved network name in CLI runtime contexts so account-backed commands and
  wallet-backed commands can pass the correct network selector into downstream recovery helpers.
- Routed Groth16 prover package root, entrypoint, and proof-manifest path resolution through
  runtime management instead of leaving the CLI entrypoint to call internal runtime helper names.
- Routed Tokamak CLI invocation resolution through runtime management instead of calling internal
  runtime helper names from the CLI entrypoint.
- Kept Groth16 prover stdout quiet during `--json` proof-backed commands so machine-readable output
  remains valid JSON.
- Verified the full private-state CLI end-to-end flow through channel exit and bridge withdrawal
  after the runtime-management refactor.

## 1.0.0 - 2026-05-04

- Stabilized the private-state CLI command contract for the first mainnet-ready release.
- Removed routine raw `--private-key` and `--password` command arguments.
- Added named local L1 account management through `account import --private-key-file`, with later
  signing commands using `--account`.
- Moved wallet commands to wallet-local canonical secret files instead of explicit password input.
- Added the wallet secret source-file flow for `join-channel --wallet-secret-path <PATH>`.
- Removed `join-channel --random-wallet-secret`; channel joins now always require
  `--wallet-secret-path <PATH>`.
- Relaxed imported source secret file permission checks while keeping canonical CLI secrets
  protected with POSIX `0600` or Windows ACL repair and inspection.
- Added per-network RPC URL persistence under the private-state workspace, with `--rpc-url` as
  the optional bridge-facing override.
- Renamed private-state CLI commands `--install` and `--doctor` to `install` and `doctor` so
  commands consistently omit a leading `--`.
- Replaced the old zk-EVM-only uninstall command with interactive `uninstall`, which removes local
  private-state data, Tokamak zk-EVM runtime data, and the global CLI package when installed.
- Added `guide` as the state-aware workflow assistant command.
- Added `get-channel` for channel policy, toll, refund schedule, and immutable policy snapshot
  inspection.
- Added CLI-wide `--json`; commands print human-readable output by default and structured output
  when requested.
- Made `doctor` human-readable by default while preserving full machine-readable diagnostics through
  `doctor --json`.
- Added durable progress phases for proof-backed commands: `loading`, `proving`, `submitting`,
  `persisting`, and `done`.
- Added centralized recovery hints for common RPC, artifact, account, wallet, channel selector,
  registration, and local-state errors.

## 0.1.9 - 2026-05-03

- Used the bundled Groth16 package version as the default `private-state-cli --install` Groth16 runtime version.
- Treated stale local Groth16 CRS metadata without `compatibleBackendVersion` as a cache miss so the matching public CRS can be reinstalled.

## 0.1.8 - 2026-04-30

- Reused common proof backend version helpers for Tokamak and Groth16 compatibility checks.
- Reused common npm registry metadata lookup during proof backend runtime installation.

## 0.1.7 - 2026-04-29

- Required Groth16 channel verifier and installed CRS compatibility versions to use canonical major.minor form.
- Matched Groth16 channel verifier compatibility against the installed CRS major.minor compatibility version.
- Required the Groth16 package version with verified public CRS archive selection.
- Required Tokamak zk-EVM channel verifier and CLI package compatibility versions to use canonical major.minor form.

## 0.1.6 - 2026-04-29

- Added `--groth16-cli-version` and `--tokamak-zk-evm-cli-version` install options with npm latest defaults.
- Installed selected proof backend package versions into managed runtime directories.
- Downloaded Groth16 CRS artifacts matching the selected Groth16 CLI version.
- Checked channel verifier compatible backend versions before local proof generation.
- Reported selected proof backend runtime versions from `--doctor`.

## 0.1.5 - 2026-04-28

- Switched channel balance proof generation to invoke `tokamak-groth16 --prove` instead of importing Groth16 proof internals directly.
- Read proof artifacts from the fixed Groth16 runtime workspace manifest.

## 0.1.4 - 2026-04-28

- Paced chunked log recovery queries at five requests per second to avoid RPC throughput bursts.
- Combined channel manager recovery log scans and filtered wallet note recovery scans to reduce RPC usage.

## 0.1.3 - 2026-04-28

- Installed the Groth16 runtime during `private-state-cli --install` and reported Groth16 readiness from `--doctor`.
- Added live NVIDIA and Docker GPU probes to `--doctor`, with a hard failure when live Docker GPU readiness does not match the recorded Tokamak CLI metadata.
- Renamed `get-my-address` to `get-my-wallet-meta`, added `get-my-l1-address`, and added `list-local-wallets`.
- Documented the private-state CLI helper commands, common flow examples, and LLM agent guidance.

## 0.1.2 - 2026-04-28

- Added `private-state-cli --doctor` to report CLI and install-time dependency versions through `tokamak-l2js`.
- Reported Tokamak zk-EVM runtime install mode, Docker mode, and CUDA runtime metadata.

## 0.1.1 - 2026-04-28

- Updated channel balance proof generation to use the fixed Groth16 runtime workspace proof paths.

## 0.1.0 - 2026-04-27

- Added the initial independently publishable private-state CLI package.

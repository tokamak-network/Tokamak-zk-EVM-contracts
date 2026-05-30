# Changelog

## Unreleased

## 2.4.2 - 2026-05-30

- Changed channel workspace recovery guidance so CLI help, guide output, agent instructions, and documentation direct
  users to registered workspace mirrors before explicit RPC genesis rebuilds.

## 2.4.1 - 2026-05-30

- Classified `UnexpectedCurrentRootVector()` submit reverts as stale channel-root failures with recovery hints that
  tell agents to refresh workspace state, re-check affected wallet state, and regenerate the original intended proof
  without changing command semantics.
- Moved LLM-agent operating guidance from the CLI README into package-shipped `agents.md`.
- Generalized the CLI README's LLM-agent summary to refer to error-response policy instead of naming one revert.
- Added private-state CLI install prerequisites to the README while delegating Tokamak zk-EVM CLI prerequisites to that
  package's README.

## 2.4.0 - 2026-05-29

- Removed the standalone `channel publish-workspace-mirror` command. Channel leaders now publish
  mirror files through `channel recover-workspace --publish-workspace-mirror --leader-account <ACCOUNT> --output <PATH>`.

## 2.3.4 - 2026-05-29

- Removed the implicit wallet proof context recovery path so proof-backed wallet commands require
  their channel context to be prepared before proof generation.
- Added a post-proof, pre-submit channel root check for proof-backed channel state updates so stale
  proofs are rejected before submitting transactions whenever the root changed during proof generation.

## 2.3.3 - 2026-05-27

- Changed `help observer` and monitoring references to use the public observer URL
  `https://observer.tonnel.io`.
- Clarified CLI help, guide output, and README guidance so channel join tolls are paid directly
  from the L1 wallet, while `account deposit-bridge` is only for channel liquidity.
- Clarified README and `help commands` guidance so AI agents answer user gas, fee, and USD cost
  questions by running `help transaction-fees --json` instead of escalating to developers.

## 2.3.2 - 2026-05-21

- Clarified `wallet transfer-notes` JSON-array argument formats in CLI help and README guidance.
- Changed wallet note freshness to use the fresh channel workspace recovery frontier instead of the
  provider's latest L1 block, so unrelated L1 blocks do not make wallet workspaces stale.
- Simplified wallet recovery and command-argument validation logic while preserving the channel-frontier
  recovery model.

## 2.3.1 - 2026-05-20

- Added `wallet recover-workspace --wallet-secret-path` support for rederiving and storing an active
  wallet spending key from the original L1 account and wallet secret source.
- Validated recovered spending keys against the current on-chain L2 address and channel token-vault
  storage key before received-note recovery starts.
- Documented the active-wallet-only spending-key recovery policy in the CLI README and private-state
  DApp README.

## 2.3.0 - 2026-05-20

- Added `help observer` to print the deployed public observer URL for the private-state monitoring
  surface.
- Documented the deployed public observer in the monitoring audit packet and observability matrix.

## 2.2.1 - 2026-05-18

- Added `channel recover-workspace --source rpc --output-raw` to append raw JSON-RPC request and response history
  to method-specific JSON files under the channel workspace `rpcCallHistory/` directory, with `eth_getLogs` split by event.
  Indexed recovery appends to existing history; `--from-genesis` overwrites it with one full genesis-to-latest scan.

## 2.2.0 - 2026-05-18

- Added `install --read-only` for channel-state read commands and commands that do not depend on channel state. This
  mode installs only the bridge deployment, bridge ABI manifest, DApp deployment, and storage layout artifacts.
- Kept default `install` as full mode for proof-backed and channel-mutating commands, and made deployment artifact
  validation mode-aware before command execution.
- Extended `help doctor` with per-command availability so read-only installs clearly report which commands are usable
  and which commands still require full install.
- Added private-state CLI E2E coverage for the read-only install mode before the full install flow.

## 2.1.2 - 2026-05-15

- Fixed wallet lifecycle recovery log lookups so account-specific registration and exit event scans
  use the same chunked `eth_getLogs` path as the rest of RPC workspace recovery.
- Removed synthetic wallet lifecycle epoch fallback creation; wallet recovery now requires
  lifecycle registration events to be found in RPC log history instead of fabricating epochs from
  current registration state.
- Fixed RPC log request pacing so every `eth_getLogs` call passes through a shared async limiter
  instead of relying on a race-prone timestamp throttle during concurrent scans.
- Added progress output for the wallet lifecycle registered/exited event scans that run before
  note-delivery recovery in `wallet recover-workspace`.
- Added `set rpc` for per-network RPC configuration with built-in `eth_getLogs` scan-limit tables
  for Ankr, Chainstack, Chainnodes, QuickNode, and Alchemy, using 90% of the provider reference
  request-rate values.
- Simplified note-mutating command post-processing so accepted note transactions wait for the
  receipt block, then refresh channel and wallet workspaces from their recovery indexes instead of
  manually applying note lifecycle metadata.
- Extended wallet recovery to persist public creation/spend linkage from commitment and
  nullifier storage observations so raw evidence export can package stored metadata without
  running its own log scan.
- Fixed raw evidence spend linkage so nullifier observation transactions are used as the spend
  transition references and included with their transaction, receipt, and event evidence.
- Redesigned the bundled investigator GUI around purpose-first disclosure requests, an interactive
  SVG note-linkage graph, node detail overlays, and Markdown ASCII-art linkage report export.
- Updated private-state documentation to reflect `set rpc` as the only CLI RPC configuration path
  for ordinary bridge-facing and wallet commands.
- Split the CLI entrypoint into command dispatch modules and moved the shared runtime implementation
  under `lib/runtime.mjs`; the published package now includes the `commands/` modules.
- Removed the `channel get-meta` workspace mirror lookup fallback so contract lookup errors surface
  directly instead of being hidden behind `null` metadata.
- Changed `channel join` to derive the wallet lifecycle epoch from the accepted join receipt instead
  of rescanning full account registration and exit history.
- Changed investigator numeric block filters to reject invalid values instead of silently treating
  them as absent filters.

## 2.1.1 - 2026-05-14

- Changed `channel recover-workspace --from-genesis` to move any existing local channel workspace
  to `workspace-rebuild-backups/` before writing the current-format workspace. The clean rebuild
  path is limited to workspace files and preserves local account and wallet key secrets under
  `secrets/`.
- Added channel workspace recovery checkpointing at the existing RPC log chunk boundary so
  interrupted RPC recovery can resume from the last completed chunk.
- Changed mirror recovery to fall back to a newer verified full mirror checkpoint when no matching
  delta bundle exists for the local recovery index.
- Changed `wallet recover-workspace` to use the same bounded channel-workspace freshness preflight
  as other wallet commands. `wallet recover-workspace --from-genesis` now restarts received-note
  scanning from channel genesis but does not rebuild the channel workspace from genesis.
- Added received-note recovery checkpointing at the existing RPC log chunk boundary so ordinary
  `wallet recover-workspace` resumes from the last completed chunk after an interruption.

## 2.1.0 - 2026-05-14

- Required current epoch-aware wallet workspaces for wallet commands and backup imports. Local
  wallet metadata must include the wallet index and epoch metadata; users with older local
  workspaces should rebuild them with `wallet recover-workspace`.
- Required current epoch-aware evidence bundle note paths in the investigator and removed the
  special-case legacy evidence layout branch.
- Consolidated the static evidence investigator into the CLI package under `cli/investigator/`
  and removed the duplicate top-level investigator copy.
- Simplified wallet command argument validation by removing unused schema fallback wrappers.

## 2.0.0 - 2026-05-13

- Split wallet export/import into `wallet export backup`, `wallet export viewing-key`,
  `wallet export spending-key`, `wallet import backup`, `wallet import viewing-key`, and
  `wallet import spending-key`.
- Changed wallet backups so they exclude spending keys, viewing keys, key derivation material,
  and plaintext note `owner`, `value`, and `salt` fields. Backups retain commitments,
  nullifiers, encrypted note payloads, and channel workspace cache files.
- Replaced the previous full-control wallet workspace format with separate note-tracking,
  spending-key metadata, and viewing-key metadata files. The CLI now loads only the current
  wallet metadata format.
- Added action-impact acknowledgements for bridge-facing, channel, and note-mutating commands.
  The warning output covers public event exposure, private note-state impact, note provenance
  boundaries, illegal-use prohibition, CEX deposit-address warnings, secret-recovery limits, and
  channel policy acceptance.
- Added full-note raw evidence export through `wallet get-notes --export-evidence` with an explicit
  plaintext-export acknowledgement. Evidence bundles include note plaintext facts, derived
  commitments and nullifiers, creation/spend transaction references, receipts, events, calldata, and
  filtering indexes, while excluding viewing keys, spending keys, wallet secrets, account private
  keys, and `.key` files.
- Made local wallet workspaces epoch-aware. `channel exit` now marks the active wallet epoch as
  exited and retains its local note metadata instead of deleting the wallet workspace, while
  `wallet recover-workspace` and `wallet get-notes --export-evidence` can still use retained exited
  epochs for historical disclosure.
- Added a local static evidence investigator GUI and bundled it with the NPM package. The new
  top-level `private-state-cli investigator` command prints the bundled HTML path, prints the file
  URL, and opens the GUI in the default browser.
- Clarified wallet authority recovery in the NPM README: viewing-key rederivation needs the original
  L1 private key and channel context, while spending-key rederivation additionally needs the same
  wallet secret source used at `channel join`.
- Added a `channel join` success warning that losing both the spending-key file and wallet secret
  source prevents spending-key rederivation.
- Aligned README terminology around `private-state DApp`, `private-state CLI`, `viewing key`,
  `spending key`, `wallet secret source`, `user-controlled selective disclosure`, and
  `privacy-preserving note semantics`.
- Added LLM-assistant guidance requiring strong user warnings and explicit confirmation before an
  assistant runs commands that require `--acknowledge-*` options on a user's behalf.
- Simplified internal CLI code paths by removing a dead `loadWallet` parameter and redundant
  `channel join` result aliases.

## 1.2.1 - 2026-05-11

- Changed pre-command automatic recovery from an RPC log request time estimate to a fixed
  7,200-block recovery delta budget.

## 1.2.0 - 2026-05-08

- Added optional channel workspace mirror recovery. `channel recover-workspace` now accepts
  `--source rpc|mirror`, with `rpc` remaining the default when `--source` is omitted.
- Added `channel set-workspace-mirror` so a channel leader can register the official workspace
  mirror base URL stored in `BridgeCore`.
- Added mirror checkpoint validation that checks signed checkpoint metadata before downloading
  bundles, then validates downloaded checkpoint or delta bundle contents against on-chain channel
  metadata before replaying the remaining RPC log delta to the latest block.
- Documented the static server protocol for channel workspace mirrors.
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
- Reworked workspace mirror recovery around leader-signed checkpoint manifests and
  delta bundles. When a local recovery index exists, the CLI prechecks the mirror checkpoint and
  downloads only the matching delta bundle instead of a full workspace bundle.
- Removed the version segment from workspace mirror URLs and kept the protocol version only in
  manifest and bundle metadata.
- Added `channel publish-workspace-mirror` to build static mirror files when the local workspace is
  current and ahead of the registered mirror checkpoint.
- Added `channel publish-workspace-mirror --force` so a channel leader can repair an unreadable or
  invalid remote mirror manifest by publishing a full checkpoint without using that manifest as a
  delta base.
- Required mirror bundle `sizeBytes` and enforce it as the download limit before verifying bundle
  contents.
- Kept streaming checkpoint or delta bundle download progress with an estimated remaining time.

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

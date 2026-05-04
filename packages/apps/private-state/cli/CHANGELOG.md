# Changelog

## Unreleased

- Changed the channel-bound L2 identity derivation signing domain and mode from password wording
  to wallet-secret wording. Existing local wallets from the pre-1.0.0 cleanup path are not
  compatibility targets.
- Centralized CLI command option schemas used by validation, while keeping the existing command
  implementations in the single CLI entrypoint.
- Replaced local wallet recovery hint string matching with typed CLI error codes for local RPC,
  wallet, artifact, registration, and stale-workspace failures.
- Removed unused replay/synthetic snapshot helpers from the CLI end-to-end script.
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

# Repository Source and Public Documentation Review

## Scope

This review covers repository-owned tracked source code and public documentation only.
It excludes Git submodules, vendored third-party source, generated artifacts, build
outputs, binary fixtures, deployment broadcasts, private environment files, and
untracked files.

## Audience Baseline

Public repository-level documentation is treated as developer-facing material for
external integrators, auditors, operators, and contributors who need to understand,
verify, run, or extend the contracts, bridge tooling, and DApp packages. DApp public
documentation is additionally treated as user-facing or integrator-facing material
when it describes privacy terms, workflow, or CLI behavior.

## Review Record

Findings below were recorded during the review and then consolidated into this final
record. This document intentionally does not include a remediation plan.

## Source Code Findings

### Private-State DApp Contracts

- `packages/apps/private-state/src/PrivateStateController.sol` contains an unused
  internal helper, `_prepareOutputNote(...)`. Repository-wide references only point to
  its definition, while all active mint and transfer paths use `_prepareMintOutput(...)`
  or `_prepareTransferOutput(...)`. This is dead code inside the final user-facing
  DApp contract.
- The private-state symbolic-path checker passed `mintNotes1` through `mintNotes6`
  and `transferNotes1To1` through `transferNotes4To1`, but it crashed before checking
  `redeemNotes1` through `redeemNotes4` because the redeem functions use inline
  assembly `if` syntax for the zero-receiver guard. Manual review indicates those
  redeem functions still have one successful path, but the current assembly shape
  creates a tooling blind spot for the required user-facing path check.
- `packages/common/src/network-config.mjs` exposes `base-*`, `arb-*`, and `op-*`
  entries through `APP_NETWORKS`, and `packages/apps/private-state/scripts/deploy/deploy-private-state.mjs`
  accepts any `resolveAppNetwork(...)` name even though its help text and public app
  documentation restrict deployment to `anvil`, `sepolia`, and `mainnet`. The source
  therefore contains over-broad network configuration that is not supported by the
  public deployment surface.

### Private-State CLI

- `packages/apps/private-state/cli/lib/runtime.mjs` has grown into a 15,419-line
  multi-responsibility module. It imports command parsing, human/JSON rendering,
  runtime installation, terms gating, browser-wallet request helpers, wallet storage,
  channel workspace recovery, note scanning, Groth16 proof execution, Tokamak snapshot
  generation, and guidance rendering into one file. The command files under
  `packages/apps/private-state/cli/commands/` are thin dispatch wrappers, so most
  domain boundaries remain inside the monolithic runtime module. This is an
  over-engineered maintenance surface rather than a small cohesive runtime layer.

### Groth16 Tooling

- Circuit rendering and setup helper logic is repeated across `packages/groth16/lib/circuit-install.mjs`,
  `packages/groth16/mpc-setup/generate_update_tree_setup_from_dusk.mjs`, and
  `packages/groth16/lib/local-trusted-setup.mjs`. The repeated responsibilities include
  rendering `circuit_updateTree.circom`, ensuring circuit dependencies, stripping ANSI
  output, and computing the next power-of-two exponent. These paths are security- and
  reproducibility-sensitive because they determine the circuit and setup artifacts, so
  duplicated implementations increase the chance that install-time and MPC-generation
  behavior diverge.

### Bridge Contracts

- `bridge/src/DAppManager.sol` and `bridge/src/ChannelManager.sol` independently
  implement the same DApp function metadata hash domains and `_hashFunctionMetadata(...)`
  procedure. `DAppManager` uses it to derive registered function leaves and roots, while
  `ChannelManager` uses a local copy to verify execution-time function metadata proofs.
  This is repeated protocol logic inside the bridge trust boundary; any future change to
  instance-layout or event-log metadata hashing would need to be kept byte-identical in
  both contracts.

### Package Manifests

- The root `package.json` declares `"fs": "^0.0.1-security"` even though repository
  source imports Node's built-in filesystem module through `node:fs` or, in the
  TypeScript synthesizer example, through the built-in `fs` specifier. The external
  `fs` package is not used by repo-owned source.
- The root `package.json` declares `msgpackr`, but repository-wide source references
  only the manifest and lockfile entries. No repo-owned source imports or requires
  `msgpackr`.
- The root `package.json` declares `js-sha3`, but repository-wide source references only
  the manifest and lockfile entries. No repo-owned source imports or requires `js-sha3`.

## Public Documentation Findings

### Bridge Documentation

- `bridge/README.md` states that `DAppManager.deleteDApp(...)` is available only on
  Sepolia and that mainnet and every non-Sepolia network reject it. The implementation in
  `bridge/src/DAppManager.sol` allows deletion on both Sepolia (`11155111`) and local
  Anvil (`31337`), and `docs/bridge/gas-assessment.md` documents the operation as
  "Sepolia/local only". The bridge README is therefore inconsistent with both code and
  another public document.
- `bridge/docs/dev/current-implementation.md` says DApp registration consumes selected
  example groups such as `privateStateMint`, `privateStateTransfer`, and
  `privateStateRedeem`. The active private-state registration materializer and public
  README examples use the actual group names `mintNotes`, `transferNotes`, and
  `redeemNotes`, so this developer reference is stale.

### Private-State DApp Documentation

- `docs/dapps/private-state/contract-spec.md` documents `NoteValueEncrypted` as the
  controller's event model but omits `StorageKeyObserved` from
  `PrivateStateController.sol` and `LiquidBalanceStorageWriteObserved` from
  `L2AccountingVault.sol`. These events are asserted by `test/private-state/PrivateStateController.t.sol`,
  decoded by `packages/apps/private-state/cli/lib/runtime.mjs`, consumed by
  `bridge/src/ChannelManager.sol`, and included in the monitoring packet generator, so the
  public contract spec is incomplete for integrators and auditors.
- `docs/dapps/private-state/workflow.md` says `wallet redeem-notes` chooses the fixed
  redeem arity from the selected note count and submits the matching `redeemNotesN` call.
  The current CLI registry describes `wallet redeem-notes` as redeeming one tracked note,
  and `packages/apps/private-state/cli/lib/runtime.mjs` rejects any note count other than
  one with `wallet redeem-notes supports exactly one input note with the currently
  registered DApp.` The workflow overstates the user-facing redeem support.
- `packages/apps/private-state/cli/assets/service-terms.md` links to
  `privacy-notice.md`, but that file does not exist beside the packaged Terms asset. The
  canonical privacy notice exists at `docs/dapps/private-state/privacy-notice.md`, so the
  packaged Markdown link is broken when read from the CLI asset directory or an npm package
  extraction.

### Audience and Public-Document Quality

- `checklist.md` is a tracked Markdown document written mostly in Korean and framed as a
  domestic exchange delisting-risk avoidance, promotional, and exchange-communication
  checklist. Its contents target internal marketing, regulatory positioning, and exchange
  submission preparation rather than the public repository audience of external
  integrators, auditors, operators, and contributors. This audience and language level are
  not appropriate for public technical documentation in this repository.
- `checklist.md` also contains stale GitHub links to
  `packages/apps/private-state/docs/security-model.md`,
  `packages/apps/private-state/docs/workflow.md`, and `bridge/docs/whitepaper.md`. The
  current public documents live at `docs/dapps/private-state/security-model.md`,
  `docs/dapps/private-state/workflow.md`, and `docs/whitepaper.md`.

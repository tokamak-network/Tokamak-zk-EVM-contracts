# Tokamak-zk-EVM Submodule Interaction Inventory

This temporary document is an operational map of how repository-owned code interacts with the
top-level `submodules/Tokamak-zk-EVM` worktree.

Its purpose is to answer two questions quickly:

1. Which parent-repository entrypoints affect the Tokamak submodule at all.
2. Whether each interaction is a read, a direct write or mirror, or a delegated install or
   worktree mutation through `git` or `tokamak-cli`.

This is not a design document. It is a boundary and side-effect inventory for maintenance work.

## Scope

Included:

- repository-owned scripts and CLIs under `apps/`, `bridge/`, and `scripts/`
- direct file-path imports from the parent repository into the submodule
- direct writes into `submodules/Tokamak-zk-EVM/**`
- delegated mutations such as `git` operations and `tokamak-cli --install`
- wrapper entrypoints that trigger the interactions above

Excluded:

- code inside `submodules/`
- writes that stay entirely in repository-owned paths
- the removed top-level `submodules/TokamakL2JS` submodule

## Current State

The repository currently interacts with `Tokamak-zk-EVM` in four ways:

1. Read-only consumption of submodule code, manifests, and generated outputs.
2. Mirroring parent-repository deployment or launch artifacts into stable in-submodule paths.
3. Delegating install or runtime refresh through submodule-owned `tokamak-cli` executions.
4. Updating or clearing the submodule worktree itself with `git` or filesystem deletion.

The repository no longer directly refreshes `submodules/Tokamak-zk-EVM/dist/**` by copying setup or
backend artifacts from parent-repository scripts. That refresh is now delegated to
`tokamak-cli --install`, and `--skip-install` paths only validate that the expected installed files
already exist.

The repository-level ZK reflection helpers no longer interact with the top-level submodule at all.
They now consume the installed `@tokamak-zk-evm/cli` runtime cache and the published
`@tokamak-zk-evm/subcircuit-library` package instead.

## No Longer In Scope

The following repository-owned files used to read Tokamak artifacts from the submodule, but no
longer cross the parent-repository/submodule boundary:

- [scripts/generate-tokamak-shared-constants.js](/Users/jehyuk/Documents/repo/Tokamak-zk-EVM-contracts/scripts/generate-tokamak-shared-constants.js:1)
  now reads `setupParams.json` and `frontendCfg.json` from `@tokamak-zk-evm/subcircuit-library`.
- [scripts/generate-tokamak-verifier-params.js](/Users/jehyuk/Documents/repo/Tokamak-zk-EVM-contracts/scripts/generate-tokamak-verifier-params.js:1)
  now reads `setupParams.json` from `@tokamak-zk-evm/subcircuit-library`.
- [scripts/zk/reflect-submodule-updates.mjs](/Users/jehyuk/Documents/repo/Tokamak-zk-EVM-contracts/scripts/zk/reflect-submodule-updates.mjs:1)
  now refreshes the installed `@tokamak-zk-evm/cli` runtime, consumes `sigma_verify.json` directly,
  and no longer reads or mutates the top-level Tokamak submodule.

## Read-Only Consumers

These files depend on the submodule but do not write into it.

### `apps/private-state/scripts/deploy/generate-synthesizer-launch-inputs.ts`

Relevant references:

- direct imports from the submodule Synthesizer sources and examples:
  [apps/private-state/scripts/deploy/generate-synthesizer-launch-inputs.ts](/Users/jehyuk/Documents/repo/Tokamak-zk-EVM-contracts/apps/private-state/scripts/deploy/generate-synthesizer-launch-inputs.ts:20)

Role:

- reads Synthesizer constants, RPC helpers, example utilities, and private-state storage helpers
  from `submodules/Tokamak-zk-EVM/packages/frontend/synthesizer/**`
- uses those submodule-owned helpers to build launch inputs that are later mirrored back into the
  submodule

### `scripts/zk/lib/tokamak-artifacts.mjs`

Relevant references:

- shared parsing and metadata helpers:
  [scripts/zk/lib/tokamak-artifacts.mjs](/Users/jehyuk/Documents/repo/Tokamak-zk-EVM-contracts/scripts/zk/lib/tokamak-artifacts.mjs:16)
- function-definition builder over Synthesizer and preprocess outputs:
  [scripts/zk/lib/tokamak-artifacts.mjs](/Users/jehyuk/Documents/repo/Tokamak-zk-EVM-contracts/scripts/zk/lib/tokamak-artifacts.mjs:218)

Role:

- reads manifests, snapshots, preprocess outputs, and Synthesizer output files that live under the
  submodule or are copied out of it
- derives bridge registration metadata from those files
- no longer refreshes `dist/**` directly

Primary consumers:

- [apps/private-state/scripts/e2e/run-bridge-private-state-cli-e2e.mjs](/Users/jehyuk/Documents/repo/Tokamak-zk-EVM-contracts/apps/private-state/scripts/e2e/run-bridge-private-state-cli-e2e.mjs:31)
- [apps/private-state/scripts/e2e/run-bridge-private-state-e2e.mjs](/Users/jehyuk/Documents/repo/Tokamak-zk-EVM-contracts/apps/private-state/scripts/e2e/run-bridge-private-state-e2e.mjs:40)

## Direct Writers and Mirrors Into the Submodule

These files create or overwrite files under `submodules/Tokamak-zk-EVM/**`.

### `apps/private-state/scripts/deploy/generate-synthesizer-launch-inputs.ts`

Relevant references:

- submodule launch file write:
  [apps/private-state/scripts/deploy/generate-synthesizer-launch-inputs.ts](/Users/jehyuk/Documents/repo/Tokamak-zk-EVM-contracts/apps/private-state/scripts/deploy/generate-synthesizer-launch-inputs.ts:418)
- manifest writes:
  [apps/private-state/scripts/deploy/generate-synthesizer-launch-inputs.ts](/Users/jehyuk/Documents/repo/Tokamak-zk-EVM-contracts/apps/private-state/scripts/deploy/generate-synthesizer-launch-inputs.ts:755)

Files written:

- `submodules/Tokamak-zk-EVM/packages/frontend/synthesizer/.vscode/launch.json`
- `submodules/Tokamak-zk-EVM/packages/frontend/synthesizer/examples/privateState/mintNotes/cli-launch-manifest.json`
- `submodules/Tokamak-zk-EVM/packages/frontend/synthesizer/examples/privateState/transferNotes/cli-launch-manifest.json`
- `submodules/Tokamak-zk-EVM/packages/frontend/synthesizer/examples/privateState/redeemNotes/cli-launch-manifest.json`

Why it exists:

- parent-repository deployment state is converted into stable in-submodule launch inputs so the
  submodule can consume local mirrored files without referencing parent-repository paths

### `apps/private-state/scripts/deploy/write-deploy-artifacts.sh`

Relevant references:

- in-submodule deployment mirror root:
  [apps/private-state/scripts/deploy/write-deploy-artifacts.sh](/Users/jehyuk/Documents/repo/Tokamak-zk-EVM-contracts/apps/private-state/scripts/deploy/write-deploy-artifacts.sh:6)
- copy operations:
  [apps/private-state/scripts/deploy/write-deploy-artifacts.sh](/Users/jehyuk/Documents/repo/Tokamak-zk-EVM-contracts/apps/private-state/scripts/deploy/write-deploy-artifacts.sh:64)
  [apps/private-state/scripts/deploy/write-deploy-artifacts.sh](/Users/jehyuk/Documents/repo/Tokamak-zk-EVM-contracts/apps/private-state/scripts/deploy/write-deploy-artifacts.sh:99)

Files written:

- `submodules/Tokamak-zk-EVM/packages/frontend/synthesizer/scripts/deployment/private-state/deployment.<chain-id>.latest.json`
- `submodules/Tokamak-zk-EVM/packages/frontend/synthesizer/scripts/deployment/private-state/storage-layout.<chain-id>.latest.json`

Why it exists:

- it mirrors parent-repository deployment outputs into a stable location that submodule-owned
  private-state helpers can consume without climbing out of the submodule

## Tooling and Worktree Mutators

These files may not write individual files themselves, but they cause the submodule to change by
running `git`, clearing the worktree, or invoking submodule-owned tooling.

### `apps/private-state/cli/private-state-bridge-cli.mjs`

Relevant references:

- submodule path constants:
  [apps/private-state/cli/private-state-bridge-cli.mjs](/Users/jehyuk/Documents/repo/Tokamak-zk-EVM-contracts/apps/private-state/cli/private-state-bridge-cli.mjs:69)
- install and uninstall entrypoints:
  [apps/private-state/cli/private-state-bridge-cli.mjs](/Users/jehyuk/Documents/repo/Tokamak-zk-EVM-contracts/apps/private-state/cli/private-state-bridge-cli.mjs:877)

Mutations:

- `git submodule sync -- submodules/Tokamak-zk-EVM`
- `git submodule update --init --recursive submodules/Tokamak-zk-EVM`
- submodule-side `git fetch`, `git switch`, `git restore`, and `git pull`
- `tokamak-cli --install`
- destructive worktree clearing for `uninstall-zk-evm`, leaving `.git` in place

Operational effect:

- this is the most invasive repository-owned entrypoint touching the top-level Tokamak submodule

### `apps/private-state/scripts/e2e/run-bridge-private-state-cli-e2e.mjs`

Relevant references:

- install flag description:
  [apps/private-state/scripts/e2e/run-bridge-private-state-cli-e2e.mjs](/Users/jehyuk/Documents/repo/Tokamak-zk-EVM-contracts/apps/private-state/scripts/e2e/run-bridge-private-state-cli-e2e.mjs:135)
- installed-artifact validation message:
  [apps/private-state/scripts/e2e/run-bridge-private-state-cli-e2e.mjs](/Users/jehyuk/Documents/repo/Tokamak-zk-EVM-contracts/apps/private-state/scripts/e2e/run-bridge-private-state-cli-e2e.mjs:428)

Mutations:

- optionally runs `tokamak-cli --install`
- otherwise only verifies that the expected installed setup files already exist

Important current behavior:

- this script no longer copies setup files into `dist/` directly

### `apps/private-state/scripts/e2e/run-bridge-private-state-e2e.mjs`

Relevant references:

- install flag description:
  [apps/private-state/scripts/e2e/run-bridge-private-state-e2e.mjs](/Users/jehyuk/Documents/repo/Tokamak-zk-EVM-contracts/apps/private-state/scripts/e2e/run-bridge-private-state-e2e.mjs:124)
- installed-artifact validation message:
  [apps/private-state/scripts/e2e/run-bridge-private-state-e2e.mjs](/Users/jehyuk/Documents/repo/Tokamak-zk-EVM-contracts/apps/private-state/scripts/e2e/run-bridge-private-state-e2e.mjs:489)

Mutations:

- optionally runs `tokamak-cli --install`
- otherwise only verifies that the expected installed setup files already exist

Important current behavior:

- this script no longer copies setup files into `dist/` directly

## Indirect Trigger Paths

These entrypoints matter because they trigger one of the direct writers or delegated mutators above.

### `apps/private-state/scripts/deploy/deploy-private-state.sh`

Relevant references:

- deployment-artifact mirror:
  [apps/private-state/scripts/deploy/deploy-private-state.sh](/Users/jehyuk/Documents/repo/Tokamak-zk-EVM-contracts/apps/private-state/scripts/deploy/deploy-private-state.sh:108)
- Synthesizer launch-input generation:
  [apps/private-state/scripts/deploy/deploy-private-state.sh](/Users/jehyuk/Documents/repo/Tokamak-zk-EVM-contracts/apps/private-state/scripts/deploy/deploy-private-state.sh:110)

Effect:

- deployment writes mirrored deployment metadata and regenerated launch manifests into the submodule

### `bridge/scripts/deploy-bridge.sh`

Relevant reference:

- bridge-side refresh orchestration:
  [bridge/scripts/deploy-bridge.sh](/Users/jehyuk/Documents/repo/Tokamak-zk-EVM-contracts/bridge/scripts/deploy-bridge.sh:145)

Effect:

- bridge deployment can rerun the installed `@tokamak-zk-evm/cli` runtime refresh

## Boundary Notes

- The dependency direction remains parent repository -> submodule only.
- Repository-owned code is responsible for mirroring deployment artifacts into stable in-submodule
  paths before submodule-owned helpers consume them.
- Submodule code should not be changed to read parent-repository deployment or storage-layout files
  directly.
- Thin wrapper scripts that only forward into a shared parent-repository helper are not useful
  submodule-boundary documentation unless they add a distinct side effect.

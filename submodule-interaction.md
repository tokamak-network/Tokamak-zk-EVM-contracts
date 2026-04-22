# Tokamak-zk-EVM Remaining Dependency Inventory

This temporary document tracks the remaining repository-owned dependency surface on the top-level
`submodules/Tokamak-zk-EVM` worktree.

Its purpose is operational:

1. Show which repository entrypoints still block complete removal of `submodules/Tokamak-zk-EVM`.
2. Separate active blockers from dependency surfaces that have already been removed or migrated to
   published packages and installed CLI runtime paths.

This is not a design document. It is a removal checklist for the remaining submodule boundary.

## Current Status

The repository no longer depends on the top-level Tokamak submodule for:

- reflected verifier and shared-constant generation under `scripts/zk/`
- `sigma_verify.json` provisioning
- bridge-side DApp registration runtime execution
- private-state compatibility tests

Those flows now use:

- `@tokamak-zk-evm/cli`
- `@tokamak-zk-evm/subcircuit-library`
- `tokamak-l2js`
- repo-owned example inputs under `apps/private-state/examples/synthesizer/privateState/`

The repository still depends on `submodules/Tokamak-zk-EVM` in three ways:

1. direct writes into stable in-submodule Synthesizer paths
2. submodule bootstrap, install, update, or uninstall logic
3. documentation and git metadata that still declare the top-level submodule

## Already Removed

The following repository-owned surfaces no longer cross the parent-repository/submodule boundary:

- [scripts/generate-tokamak-shared-constants.js](/Users/jehyuk/Documents/repo/Tokamak-zk-EVM-contracts/scripts/generate-tokamak-shared-constants.js:1)
  now reads `setupParams.json` and `frontendCfg.json` from `@tokamak-zk-evm/subcircuit-library`.
- [scripts/generate-tokamak-verifier-params.js](/Users/jehyuk/Documents/repo/Tokamak-zk-EVM-contracts/scripts/generate-tokamak-verifier-params.js:1)
  now reads `setupParams.json` from `@tokamak-zk-evm/subcircuit-library`.
- [scripts/zk/reflect-submodule-updates.mjs](/Users/jehyuk/Documents/repo/Tokamak-zk-EVM-contracts/scripts/zk/reflect-submodule-updates.mjs:1)
  now refreshes the installed `@tokamak-zk-evm/cli` runtime and reads `sigma_verify.json`
  directly from `~/.tokamak-zk-evm`.
- [bridge/scripts/admin-add-dapp.mjs](/Users/jehyuk/Documents/repo/Tokamak-zk-EVM-contracts/bridge/scripts/admin-add-dapp.mjs:1)
  now consumes repo-owned example inputs under
  `apps/private-state/examples/synthesizer/privateState/` and runs the installed CLI runtime.
- `apps/private-state/scripts/synthesizer-compat-test/`
  was removed from this repository and is no longer part of the local submodule boundary.

## Migrated To Submodule

These scripts no longer belong to the parent-repository dependency surface, even if some parent
entrypoints still invoke them through the checked-out submodule.

### `submodules/Tokamak-zk-EVM/packages/frontend/synthesizer/node-cli/scripts/generate-synthesizer-launch-inputs.ts`

Status: moved into the submodule, standalone

Current role:

- lives under the Synthesizer `node-cli` workspace
- reads local deployment and storage-layout manifests from
  `packages/frontend/synthesizer/node-cli/scripts/deployment/private-state/`
- writes launch inputs into `packages/frontend/synthesizer/node-cli/examples/privateState/`

Parent-repository impact:

- this script is no longer a parent-owned blocker
- the remaining blocker is any parent entrypoint that still assumes a checked-out submodule in
  order to invoke it

## Active Blockers

These files still have to be removed, rewritten, or migrated before the top-level Tokamak
submodule can be deleted.

### `apps/private-state/scripts/deploy/write-deploy-artifacts.sh`

Relevant references:

- in-submodule deployment mirror root:
  [apps/private-state/scripts/deploy/write-deploy-artifacts.sh](/Users/jehyuk/Documents/repo/Tokamak-zk-EVM-contracts/apps/private-state/scripts/deploy/write-deploy-artifacts.sh:6)

Current role:

- copies repository-owned deployment and storage-layout manifests into
  `submodules/Tokamak-zk-EVM/packages/frontend/synthesizer/scripts/deployment/private-state/`

Removal impact:

- this mirror flow must move upstream or disappear before the top-level submodule is removed

### `apps/private-state/scripts/deploy/deploy-private-state.sh`

Relevant references:

- launch-input generation through the submodule workspace:
  [apps/private-state/scripts/deploy/deploy-private-state.sh](/Users/jehyuk/Documents/repo/Tokamak-zk-EVM-contracts/apps/private-state/scripts/deploy/deploy-private-state.sh:1)

Current role:

- deploys the private-state contracts only
- no longer invokes `write-deploy-artifacts.sh`
- no longer invokes `generate-synthesizer-launch-inputs.ts`

Removal impact:

- this wrapper no longer mirrors artifacts into the submodule, but it still belongs to the
  remaining parent-repository deploy surface

### `apps/private-state/cli/private-state-bridge-cli.mjs`

Relevant references:

- submodule path constants:
  [apps/private-state/cli/private-state-bridge-cli.mjs](/Users/jehyuk/Documents/repo/Tokamak-zk-EVM-contracts/apps/private-state/cli/private-state-bridge-cli.mjs:69)
- submodule bootstrap and install logic:
  [apps/private-state/cli/private-state-bridge-cli.mjs](/Users/jehyuk/Documents/repo/Tokamak-zk-EVM-contracts/apps/private-state/cli/private-state-bridge-cli.mjs:961)

Current role:

- bootstraps `submodules/Tokamak-zk-EVM` from `.gitmodules`
- updates the submodule worktree with `git submodule` commands and direct submodule-side git
- runs `tokamak-cli --install` through the submodule checkout
- implements `uninstall-zk-evm` by clearing the checked-out submodule worktree

Removal impact:

- this is the largest remaining runtime blocker
- install and uninstall behavior must be rewritten around the published CLI package and installed
  runtime cache, not a checked-out submodule

### `apps/private-state/scripts/e2e/run-bridge-private-state-cli-e2e.mjs`

Relevant references:

- submodule root constant:
  [apps/private-state/scripts/e2e/run-bridge-private-state-cli-e2e.mjs](/Users/jehyuk/Documents/repo/Tokamak-zk-EVM-contracts/apps/private-state/scripts/e2e/run-bridge-private-state-cli-e2e.mjs:51)
- stale submodule install guidance:
  [apps/private-state/scripts/e2e/run-bridge-private-state-cli-e2e.mjs](/Users/jehyuk/Documents/repo/Tokamak-zk-EVM-contracts/apps/private-state/scripts/e2e/run-bridge-private-state-cli-e2e.mjs:428)

Current role:

- still assumes a checked-out `submodules/Tokamak-zk-EVM` root
- still invokes the submodule-owned `generate-synthesizer-launch-inputs.ts` through the checked-out
  `node-cli` workspace
- still triggers deploy-side scripts that mirror artifacts into the submodule

Removal impact:

- must be rewritten to use installed CLI runtime paths and repo-owned example inputs only, without
  invoking submodule-owned scripts from the parent repository

### `apps/private-state/scripts/e2e/run-bridge-private-state-e2e.mjs`

Relevant references:

- submodule root constant:
  [apps/private-state/scripts/e2e/run-bridge-private-state-e2e.mjs](/Users/jehyuk/Documents/repo/Tokamak-zk-EVM-contracts/apps/private-state/scripts/e2e/run-bridge-private-state-e2e.mjs:58)
- stale submodule install guidance:
  [apps/private-state/scripts/e2e/run-bridge-private-state-e2e.mjs](/Users/jehyuk/Documents/repo/Tokamak-zk-EVM-contracts/apps/private-state/scripts/e2e/run-bridge-private-state-e2e.mjs:489)

Current role:

- still assumes a checked-out `submodules/Tokamak-zk-EVM` root
- still validates or explains setup in terms of submodule-local install state

Removal impact:

- must be rewritten to use installed CLI runtime paths and repo-owned example inputs only

## Git And Documentation Surfaces

These files are not the root cause, but they cannot remain once the runtime blockers above are
gone.

### Git metadata

- [.gitmodules](/Users/jehyuk/Documents/repo/Tokamak-zk-EVM-contracts/.gitmodules:11)
- `submodules/Tokamak-zk-EVM/`
- `.git/modules/submodules/Tokamak-zk-EVM/`

These can be removed only after no repository-owned code still expects the top-level submodule.

### Documentation and help text

Representative stale references:

- [README.md](/Users/jehyuk/Documents/repo/Tokamak-zk-EVM-contracts/README.md:9)
- [apps/private-state/README.md](/Users/jehyuk/Documents/repo/Tokamak-zk-EVM-contracts/apps/private-state/README.md:65)

These references should be cleaned up after the runtime and deploy blockers are removed.

## Removal Order

The remaining safe removal order is:

1. remove or migrate `write-deploy-artifacts.sh`
2. rewrite `private-state-bridge-cli.mjs` install and uninstall flows around the published CLI
3. rewrite both private-state E2E runners to stop referencing `submodules/Tokamak-zk-EVM`
4. remove `.gitmodules`, `submodules/Tokamak-zk-EVM`, and `.git/modules/submodules/Tokamak-zk-EVM`
5. delete stale documentation and help text that still mentions the top-level submodule

## Boundary Note

The remaining dependency direction is still parent repository -> submodule only.

The goal of this inventory is to drive that remaining surface to zero so the top-level Tokamak
submodule can be removed completely.

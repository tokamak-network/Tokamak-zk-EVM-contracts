# Tokamak-zk-EVM Submodule Write Interactions

This temporary note lists the repository-owned code paths that create, copy, overwrite, or otherwise
mutate files inside the top-level `submodules/Tokamak-zk-EVM` worktree.

The focus is intentionally narrow:

- Included: code that writes into `submodules/Tokamak-zk-EVM/**`
- Included: code that mutates the submodule worktree through `git` or `tokamak-cli --install`
- Included: wrapper scripts that trigger those writes indirectly
- Excluded: read-only consumers of submodule files
- Excluded: writes into repository-owned paths outside the submodule
- Excluded: the removed top-level `submodules/TokamakL2JS` submodule

## Summary

The repository currently mutates the `Tokamak-zk-EVM` submodule in three distinct ways:

1. It mirrors repository-owned deployment metadata into stable paths under the submodule.
2. It refreshes submodule-local build artifacts under `dist/` by copying binaries, libraries, or setup files.
3. It mutates the submodule worktree itself by running `git` operations or `tokamak-cli --install`.

## Direct File Writers Inside `submodules/Tokamak-zk-EVM`

### `apps/private-state/scripts/deploy/generate-synthesizer-launch-inputs.ts`

Relevant references:

- `synthesizerRoot` points at `submodules/Tokamak-zk-EVM/packages/frontend/synthesizer`:
  [apps/private-state/scripts/deploy/generate-synthesizer-launch-inputs.ts](/Users/jehyuk/Documents/repo/Tokamak-zk-EVM-contracts/apps/private-state/scripts/deploy/generate-synthesizer-launch-inputs.ts:60)
- Generic JSON writer:
  [apps/private-state/scripts/deploy/generate-synthesizer-launch-inputs.ts](/Users/jehyuk/Documents/repo/Tokamak-zk-EVM-contracts/apps/private-state/scripts/deploy/generate-synthesizer-launch-inputs.ts:188)

This script writes generated app-specific Synthesizer inputs directly into the submodule so that the
submodule can consume mirrored local copies instead of climbing back into the parent repository.

Files it writes:

- `submodules/Tokamak-zk-EVM/packages/frontend/synthesizer/.vscode/launch.json`
  [apps/private-state/scripts/deploy/generate-synthesizer-launch-inputs.ts](/Users/jehyuk/Documents/repo/Tokamak-zk-EVM-contracts/apps/private-state/scripts/deploy/generate-synthesizer-launch-inputs.ts:418)
- `submodules/Tokamak-zk-EVM/packages/frontend/synthesizer/examples/privateState/mintNotes/cli-launch-manifest.json`
  [apps/private-state/scripts/deploy/generate-synthesizer-launch-inputs.ts](/Users/jehyuk/Documents/repo/Tokamak-zk-EVM-contracts/apps/private-state/scripts/deploy/generate-synthesizer-launch-inputs.ts:755)
- `submodules/Tokamak-zk-EVM/packages/frontend/synthesizer/examples/privateState/transferNotes/cli-launch-manifest.json`
  [apps/private-state/scripts/deploy/generate-synthesizer-launch-inputs.ts](/Users/jehyuk/Documents/repo/Tokamak-zk-EVM-contracts/apps/private-state/scripts/deploy/generate-synthesizer-launch-inputs.ts:756)
- `submodules/Tokamak-zk-EVM/packages/frontend/synthesizer/examples/privateState/redeemNotes/cli-launch-manifest.json`
  [apps/private-state/scripts/deploy/generate-synthesizer-launch-inputs.ts](/Users/jehyuk/Documents/repo/Tokamak-zk-EVM-contracts/apps/private-state/scripts/deploy/generate-synthesizer-launch-inputs.ts:757)

Operational effect:

- It overwrites the Synthesizer launch configuration used by local debugging and scripted replay.
- It regenerates per-example manifest files that tell the submodule where to find mirrored
  `previousState`, `transaction`, `blockInfo`, and `contractCode` inputs.

Primary callers:

- Direct deployment flow:
  [apps/private-state/scripts/deploy/deploy-private-state.sh](/Users/jehyuk/Documents/repo/Tokamak-zk-EVM-contracts/apps/private-state/scripts/deploy/deploy-private-state.sh:110)
- CLI E2E flow, which invokes the same script via `npx --prefix <submodule>`:
  [apps/private-state/scripts/e2e/run-bridge-private-state-cli-e2e.mjs](/Users/jehyuk/Documents/repo/Tokamak-zk-EVM-contracts/apps/private-state/scripts/e2e/run-bridge-private-state-cli-e2e.mjs:520)

### `apps/private-state/scripts/deploy/write-deploy-artifacts.sh`

Relevant references:

- Submodule mirror root:
  [apps/private-state/scripts/deploy/write-deploy-artifacts.sh](/Users/jehyuk/Documents/repo/Tokamak-zk-EVM-contracts/apps/private-state/scripts/deploy/write-deploy-artifacts.sh:6)
- Destination file names:
  [apps/private-state/scripts/deploy/write-deploy-artifacts.sh](/Users/jehyuk/Documents/repo/Tokamak-zk-EVM-contracts/apps/private-state/scripts/deploy/write-deploy-artifacts.sh:27)
- Copy operations:
  [apps/private-state/scripts/deploy/write-deploy-artifacts.sh](/Users/jehyuk/Documents/repo/Tokamak-zk-EVM-contracts/apps/private-state/scripts/deploy/write-deploy-artifacts.sh:64),
  [apps/private-state/scripts/deploy/write-deploy-artifacts.sh](/Users/jehyuk/Documents/repo/Tokamak-zk-EVM-contracts/apps/private-state/scripts/deploy/write-deploy-artifacts.sh:99)

This script mirrors deployment outputs produced in the parent repository into the submodule's
private-state deployment folder.

Files it creates or overwrites:

- `submodules/Tokamak-zk-EVM/packages/frontend/synthesizer/scripts/deployment/private-state/deployment.<chain-id>.latest.json`
- `submodules/Tokamak-zk-EVM/packages/frontend/synthesizer/scripts/deployment/private-state/storage-layout.<chain-id>.latest.json`

Operational effect:

- It ensures the submodule can consume app deployment and storage-layout metadata from a stable
  in-submodule location.
- It is the concrete implementation of the repository-to-submodule mirroring rule used by the
  private-state app.

Primary caller:

- Direct deployment flow:
  [apps/private-state/scripts/deploy/deploy-private-state.sh](/Users/jehyuk/Documents/repo/Tokamak-zk-EVM-contracts/apps/private-state/scripts/deploy/deploy-private-state.sh:108)

### `scripts/zk/lib/tokamak-artifacts.mjs`

Relevant references:

- Dist write targets:
  [scripts/zk/lib/tokamak-artifacts.mjs](/Users/jehyuk/Documents/repo/Tokamak-zk-EVM-contracts/scripts/zk/lib/tokamak-artifacts.mjs:46)
- Library directory refresh:
  [scripts/zk/lib/tokamak-artifacts.mjs](/Users/jehyuk/Documents/repo/Tokamak-zk-EVM-contracts/scripts/zk/lib/tokamak-artifacts.mjs:56)
- Binary copy logic:
  [scripts/zk/lib/tokamak-artifacts.mjs](/Users/jehyuk/Documents/repo/Tokamak-zk-EVM-contracts/scripts/zk/lib/tokamak-artifacts.mjs:68)

This helper copies backend build outputs from submodule source-tree locations into the submodule's
runtime `dist/` tree.

Paths it mutates:

- `submodules/Tokamak-zk-EVM/dist/backend-lib/icicle/**`
- `submodules/Tokamak-zk-EVM/dist/bin/trusted-setup`
- `submodules/Tokamak-zk-EVM/dist/bin/preprocess`
- `submodules/Tokamak-zk-EVM/dist/bin/prove`
- `submodules/Tokamak-zk-EVM/dist/bin/verify`

Operational effect:

- It mirrors backend release binaries into the exact locations expected by downstream repository
  tooling.
- On macOS it also patches the copied binaries with an additional rpath after the copy step, which
  is another mutation inside the submodule `dist/` tree.

Known callers:

- Bridge DApp registration flow:
  [bridge/scripts/admin-add-dapp.mjs](/Users/jehyuk/Documents/repo/Tokamak-zk-EVM-contracts/bridge/scripts/admin-add-dapp.mjs:501)
- Private-state CLI E2E flow:
  [apps/private-state/scripts/e2e/run-bridge-private-state-cli-e2e.mjs](/Users/jehyuk/Documents/repo/Tokamak-zk-EVM-contracts/apps/private-state/scripts/e2e/run-bridge-private-state-cli-e2e.mjs:1149)
- Private-state bridge E2E flow:
  [apps/private-state/scripts/e2e/run-bridge-private-state-e2e.mjs](/Users/jehyuk/Documents/repo/Tokamak-zk-EVM-contracts/apps/private-state/scripts/e2e/run-bridge-private-state-e2e.mjs:884)

### `apps/private-state/scripts/e2e/run-bridge-private-state-cli-e2e.mjs`

Relevant references:

- Setup source and destination directories:
  [apps/private-state/scripts/e2e/run-bridge-private-state-cli-e2e.mjs](/Users/jehyuk/Documents/repo/Tokamak-zk-EVM-contracts/apps/private-state/scripts/e2e/run-bridge-private-state-cli-e2e.mjs:110)
- Copy loop:
  [apps/private-state/scripts/e2e/run-bridge-private-state-cli-e2e.mjs](/Users/jehyuk/Documents/repo/Tokamak-zk-EVM-contracts/apps/private-state/scripts/e2e/run-bridge-private-state-cli-e2e.mjs:436)

This E2E runner copies trusted-setup outputs from a source directory inside the submodule into the
submodule runtime resource directory.

Paths it mutates:

- `submodules/Tokamak-zk-EVM/dist/resource/setup/output/combined_sigma.rkyv`
- `submodules/Tokamak-zk-EVM/dist/resource/setup/output/sigma_preprocess.rkyv`
- `submodules/Tokamak-zk-EVM/dist/resource/setup/output/sigma_verify.rkyv`

Operational effect:

- It refreshes the installed setup artifacts that later Tokamak CLI stages expect under `dist/`.
- The write is local to the submodule even though the copy is orchestrated from the parent
  repository.
- In the same flow it also refreshes submodule-installed outputs more broadly by running
  `tokamak-cli --install`:
  [apps/private-state/scripts/e2e/run-bridge-private-state-cli-e2e.mjs](/Users/jehyuk/Documents/repo/Tokamak-zk-EVM-contracts/apps/private-state/scripts/e2e/run-bridge-private-state-cli-e2e.mjs:1151)

### `apps/private-state/scripts/e2e/run-bridge-private-state-e2e.mjs`

Relevant references:

- Setup source and destination directories:
  [apps/private-state/scripts/e2e/run-bridge-private-state-e2e.mjs](/Users/jehyuk/Documents/repo/Tokamak-zk-EVM-contracts/apps/private-state/scripts/e2e/run-bridge-private-state-e2e.mjs:61)
- Copy loop:
  [apps/private-state/scripts/e2e/run-bridge-private-state-e2e.mjs](/Users/jehyuk/Documents/repo/Tokamak-zk-EVM-contracts/apps/private-state/scripts/e2e/run-bridge-private-state-e2e.mjs:496)

This runner performs the same setup-artifact refresh as the CLI E2E script, but in the older
bridge-oriented E2E flow.

Paths it mutates:

- `submodules/Tokamak-zk-EVM/dist/resource/setup/output/combined_sigma.rkyv`
- `submodules/Tokamak-zk-EVM/dist/resource/setup/output/sigma_preprocess.rkyv`
- `submodules/Tokamak-zk-EVM/dist/resource/setup/output/sigma_verify.rkyv`

Operational effect:

- It refreshes the installed trusted-setup payload under `dist/resource/setup/output`.
- In the same flow it also reruns `tokamak-cli --install`, which can regenerate additional
  submodule-local installed outputs under `dist/`:
  [apps/private-state/scripts/e2e/run-bridge-private-state-e2e.mjs](/Users/jehyuk/Documents/repo/Tokamak-zk-EVM-contracts/apps/private-state/scripts/e2e/run-bridge-private-state-e2e.mjs:887)

## Worktree Mutators

The following files do not just overwrite generated files. They can change the submodule checkout
itself or repopulate its installed outputs.

### `scripts/zk/reflect-submodule-updates.mjs`

Relevant references:

- Submodule root and CLI path:
  [scripts/zk/reflect-submodule-updates.mjs](/Users/jehyuk/Documents/repo/Tokamak-zk-EVM-contracts/scripts/zk/reflect-submodule-updates.mjs:17)
- Git worktree update:
  [scripts/zk/reflect-submodule-updates.mjs](/Users/jehyuk/Documents/repo/Tokamak-zk-EVM-contracts/scripts/zk/reflect-submodule-updates.mjs:188)
- Tokamak install:
  [scripts/zk/reflect-submodule-updates.mjs](/Users/jehyuk/Documents/repo/Tokamak-zk-EVM-contracts/scripts/zk/reflect-submodule-updates.mjs:194)

This is the main bridge-side refresh orchestrator.

Mutations it performs:

- `git fetch origin dev` inside `submodules/Tokamak-zk-EVM`
- `git checkout -B dev origin/dev` inside `submodules/Tokamak-zk-EVM`
- `git pull --ff-only origin dev` inside `submodules/Tokamak-zk-EVM`
- `tokamak-cli --install` inside `submodules/Tokamak-zk-EVM`

Operational effect:

- It can replace the checked-out commit and branch state of the submodule.
- It can regenerate installed outputs under the submodule `dist/` tree through the Tokamak CLI.

Primary caller:

- Bridge deployment script:
  [bridge/scripts/deploy-bridge.sh](/Users/jehyuk/Documents/repo/Tokamak-zk-EVM-contracts/bridge/scripts/deploy-bridge.sh:145)

### `apps/private-state/cli/private-state-bridge-cli.mjs`

Relevant references:

- Submodule path constants:
  [apps/private-state/cli/private-state-bridge-cli.mjs](/Users/jehyuk/Documents/repo/Tokamak-zk-EVM-contracts/apps/private-state/cli/private-state-bridge-cli.mjs:69)
- `install-zk-evm` entrypoint:
  [apps/private-state/cli/private-state-bridge-cli.mjs](/Users/jehyuk/Documents/repo/Tokamak-zk-EVM-contracts/apps/private-state/cli/private-state-bridge-cli.mjs:877)
- `uninstall-zk-evm` destructive cleanup:
  [apps/private-state/cli/private-state-bridge-cli.mjs](/Users/jehyuk/Documents/repo/Tokamak-zk-EVM-contracts/apps/private-state/cli/private-state-bridge-cli.mjs:889)
- Submodule sync and update:
  [apps/private-state/cli/private-state-bridge-cli.mjs](/Users/jehyuk/Documents/repo/Tokamak-zk-EVM-contracts/apps/private-state/cli/private-state-bridge-cli.mjs:950)
- Branch switch, restore, and pull:
  [apps/private-state/cli/private-state-bridge-cli.mjs](/Users/jehyuk/Documents/repo/Tokamak-zk-EVM-contracts/apps/private-state/cli/private-state-bridge-cli.mjs:916)

This CLI exposes the most invasive repository-owned submodule mutation surface.

Mutations performed by `install-zk-evm`:

- Runs `git submodule sync -- submodules/Tokamak-zk-EVM`
- Runs `git submodule update --init --recursive submodules/Tokamak-zk-EVM`
- Runs `git fetch origin dev` inside the submodule
- Runs `git switch dev` or `git switch --track origin/dev`
- Optionally runs `git restore --source origin/dev --staged --worktree .` when the worktree was
  previously cleared but only contains deletion entries
- Runs `git pull --ff-only origin dev`
- Runs `tokamak-cli --install`

Mutations performed by `uninstall-zk-evm`:

- Iterates through every entry in `submodules/Tokamak-zk-EVM`
- Deletes every entry other than `.git`

Operational effect:

- `install-zk-evm` is a full bootstrap and fast-forward mechanism for the submodule checkout and its
  installed outputs.
- `uninstall-zk-evm` intentionally clears the submodule worktree contents while preserving the
  submodule metadata directory.

### `bridge/scripts/admin-add-dapp.mjs`

Relevant references:

- Submodule update helper:
  [bridge/scripts/admin-add-dapp.mjs](/Users/jehyuk/Documents/repo/Tokamak-zk-EVM-contracts/bridge/scripts/admin-add-dapp.mjs:347)
- Tokamak install helper:
  [bridge/scripts/admin-add-dapp.mjs](/Users/jehyuk/Documents/repo/Tokamak-zk-EVM-contracts/bridge/scripts/admin-add-dapp.mjs:353)
- Main execution path that calls both:
  [bridge/scripts/admin-add-dapp.mjs](/Users/jehyuk/Documents/repo/Tokamak-zk-EVM-contracts/bridge/scripts/admin-add-dapp.mjs:500)

This bridge registration script is not only a metadata reader. Before it assembles DApp definitions,
it also refreshes the `Tokamak-zk-EVM` checkout and installed outputs.

Mutations it performs:

- `git fetch origin dev` inside `submodules/Tokamak-zk-EVM`
- `git checkout -B dev origin/dev` inside `submodules/Tokamak-zk-EVM`
- `git pull --ff-only origin dev` inside `submodules/Tokamak-zk-EVM`
- `tokamak-cli --install` inside `submodules/Tokamak-zk-EVM`
- `ensureTokamakDistBackendBinaries(tokamakSubmoduleRoot)`, which refreshes `dist/bin` and
  `dist/backend-lib/icicle`

Operational effect:

- DApp registration can implicitly rewrite the submodule checkout and the installed runtime payload
  it depends on.

## Indirect Writers and Trigger Paths

These files matter because they do not write into the submodule themselves, but they trigger a
writer listed above.

### `apps/private-state/scripts/deploy/deploy-private-state.sh`

Relevant references:

- Calls the deployment-artifact mirror:
  [apps/private-state/scripts/deploy/deploy-private-state.sh](/Users/jehyuk/Documents/repo/Tokamak-zk-EVM-contracts/apps/private-state/scripts/deploy/deploy-private-state.sh:108)
- Calls the Synthesizer launch-input generator:
  [apps/private-state/scripts/deploy/deploy-private-state.sh](/Users/jehyuk/Documents/repo/Tokamak-zk-EVM-contracts/apps/private-state/scripts/deploy/deploy-private-state.sh:110)

Operational effect:

- Running this deployment script writes mirrored deployment metadata and regenerated Synthesizer
  launch manifests into the submodule.

### `bridge/scripts/deploy-bridge.sh`

Relevant reference:

- Calls the bridge-side submodule refresh helper:
  [bridge/scripts/deploy-bridge.sh](/Users/jehyuk/Documents/repo/Tokamak-zk-EVM-contracts/bridge/scripts/deploy-bridge.sh:145)

Operational effect:

- Running bridge deployment can update the `Tokamak-zk-EVM` checkout and rerun `tokamak-cli
  --install` through `scripts/zk/reflect-submodule-updates.mjs`.

## Non-Writers Worth Distinguishing

The following code interacts with `submodules/Tokamak-zk-EVM` but is not included in the mutation
list above because it is read-only in this context:

- `apps/private-state/scripts/synthesizer-compat-test/common.ts` importing submodule-local
  dependencies and running the Synthesizer CLI
- `scripts/generate-tokamak-verifier-params.js` and `scripts/generate-tokamak-shared-constants.js`
  reading `dist/resource/qap-compiler/*`
- `scripts/zk/rkyv-to-json/Cargo.toml` and `tokamak-zkp/foundry.toml` referencing submodule paths as
  read inputs

## Practical Takeaway

If a future change needs to understand why a file under `submodules/Tokamak-zk-EVM` changed, start
with this order:

1. Check whether the change is a mirrored app artifact under
   `packages/frontend/synthesizer/scripts/deployment/private-state` or
   `packages/frontend/synthesizer/examples/privateState`.
2. Check whether the change is an installed runtime artifact under `dist/bin`, `dist/backend-lib`,
   or `dist/resource/setup/output`.
3. Check whether the submodule checkout itself was moved or repopulated by `git` operations or
   `tokamak-cli --install`.

# Tokamak-zk-EVM Submodule Interaction Inventory

This document lists only repository-owned scripts that still interact with the top-level
`submodules/Tokamak-zk-EVM` checkout.

The list is intentionally simple:

1. scripts that read from the submodule
2. scripts that write to the submodule

Submodule-owned scripts are not listed here. Documentation-only references are also excluded.

## Scripts That Read From The Submodule

### `apps/private-state/scripts/e2e/run-bridge-private-state-cli-e2e.mjs`

Relevant references:

- [apps/private-state/scripts/e2e/run-bridge-private-state-cli-e2e.mjs](/Users/jehyuk/Documents/repo/Tokamak-zk-EVM-contracts/apps/private-state/scripts/e2e/run-bridge-private-state-cli-e2e.mjs:103)
- [apps/private-state/scripts/e2e/run-bridge-private-state-cli-e2e.mjs](/Users/jehyuk/Documents/repo/Tokamak-zk-EVM-contracts/apps/private-state/scripts/e2e/run-bridge-private-state-cli-e2e.mjs:105)
- [apps/private-state/scripts/e2e/run-bridge-private-state-cli-e2e.mjs](/Users/jehyuk/Documents/repo/Tokamak-zk-EVM-contracts/apps/private-state/scripts/e2e/run-bridge-private-state-cli-e2e.mjs:517)

What it reads:

- the checked-out submodule root only for the moved Synthesizer generator
- Synthesizer `node-cli` example manifests under
  `submodules/Tokamak-zk-EVM/packages/frontend/synthesizer/node-cli/examples/privateState/`

## Scripts That Write To The Submodule

### `apps/private-state/scripts/e2e/run-bridge-private-state-cli-e2e.mjs`

Relevant references:

- [apps/private-state/scripts/e2e/run-bridge-private-state-cli-e2e.mjs](/Users/jehyuk/Documents/repo/Tokamak-zk-EVM-contracts/apps/private-state/scripts/e2e/run-bridge-private-state-cli-e2e.mjs:517)

What it writes:

- Synthesizer `node-cli` launch inputs by invoking the submodule-owned
  `generate-synthesizer-launch-inputs.ts`

## Immediate Removal Targets

If the goal is to remove the top-level Tokamak submodule completely, the remaining parent-repository
targets are:

1. stop reading Synthesizer inputs from `submodules/Tokamak-zk-EVM/` in `run-bridge-private-state-cli-e2e.mjs`
2. stop invoking the submodule-owned `generate-synthesizer-launch-inputs.ts` from the parent repository
3. remove `.gitmodules`, `submodules/Tokamak-zk-EVM/`, and `.git/modules/submodules/Tokamak-zk-EVM/`

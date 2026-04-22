# Tokamak-zk-EVM Submodule Interaction Inventory

This document lists only repository-owned scripts that still interact with the top-level
`submodules/Tokamak-zk-EVM` checkout.

The list is intentionally simple:

1. scripts that read from the submodule
2. scripts that write to the submodule

Submodule-owned scripts are not listed here. Documentation-only references are also excluded.

## Scripts That Read From The Submodule

### `apps/private-state/cli/private-state-bridge-cli.mjs`

Relevant references:

- [apps/private-state/cli/private-state-bridge-cli.mjs](/Users/jehyuk/Documents/repo/Tokamak-zk-EVM-contracts/apps/private-state/cli/private-state-bridge-cli.mjs:69)
- [apps/private-state/cli/private-state-bridge-cli.mjs](/Users/jehyuk/Documents/repo/Tokamak-zk-EVM-contracts/apps/private-state/cli/private-state-bridge-cli.mjs:3585)

What it reads:

- the checked-out submodule root
- `submodules/Tokamak-zk-EVM/tokamak-cli`
- files under `submodules/Tokamak-zk-EVM/dist/resource/**`

### `apps/private-state/scripts/e2e/run-bridge-private-state-cli-e2e.mjs`

Relevant references:

- [apps/private-state/scripts/e2e/run-bridge-private-state-cli-e2e.mjs](/Users/jehyuk/Documents/repo/Tokamak-zk-EVM-contracts/apps/private-state/scripts/e2e/run-bridge-private-state-cli-e2e.mjs:51)
- [apps/private-state/scripts/e2e/run-bridge-private-state-cli-e2e.mjs](/Users/jehyuk/Documents/repo/Tokamak-zk-EVM-contracts/apps/private-state/scripts/e2e/run-bridge-private-state-cli-e2e.mjs:100)
- [apps/private-state/scripts/e2e/run-bridge-private-state-cli-e2e.mjs](/Users/jehyuk/Documents/repo/Tokamak-zk-EVM-contracts/apps/private-state/scripts/e2e/run-bridge-private-state-cli-e2e.mjs:108)

What it reads:

- the checked-out submodule root
- `submodules/Tokamak-zk-EVM/tokamak-cli`
- Synthesizer `node-cli` example manifests under
  `submodules/Tokamak-zk-EVM/packages/frontend/synthesizer/node-cli/examples/privateState/`
- setup and step artifacts under `submodules/Tokamak-zk-EVM/dist/resource/**`

### `apps/private-state/scripts/e2e/run-bridge-private-state-e2e.mjs`

Relevant references:

- [apps/private-state/scripts/e2e/run-bridge-private-state-e2e.mjs](/Users/jehyuk/Documents/repo/Tokamak-zk-EVM-contracts/apps/private-state/scripts/e2e/run-bridge-private-state-e2e.mjs:58)
- [apps/private-state/scripts/e2e/run-bridge-private-state-e2e.mjs](/Users/jehyuk/Documents/repo/Tokamak-zk-EVM-contracts/apps/private-state/scripts/e2e/run-bridge-private-state-e2e.mjs:446)

What it reads:

- the checked-out submodule root
- `submodules/Tokamak-zk-EVM/tokamak-cli`
- setup and step artifacts under `submodules/Tokamak-zk-EVM/dist/**`

## Scripts That Write To The Submodule

### `apps/private-state/scripts/deploy/write-deploy-artifacts.sh`

Relevant references:

- [apps/private-state/scripts/deploy/write-deploy-artifacts.sh](/Users/jehyuk/Documents/repo/Tokamak-zk-EVM-contracts/apps/private-state/scripts/deploy/write-deploy-artifacts.sh:6)

What it writes:

- deployment manifests into
  `submodules/Tokamak-zk-EVM/packages/frontend/synthesizer/scripts/deployment/private-state/`

### `apps/private-state/cli/private-state-bridge-cli.mjs`

Relevant references:

- [apps/private-state/cli/private-state-bridge-cli.mjs](/Users/jehyuk/Documents/repo/Tokamak-zk-EVM-contracts/apps/private-state/cli/private-state-bridge-cli.mjs:879)
- [apps/private-state/cli/private-state-bridge-cli.mjs](/Users/jehyuk/Documents/repo/Tokamak-zk-EVM-contracts/apps/private-state/cli/private-state-bridge-cli.mjs:898)
- [apps/private-state/cli/private-state-bridge-cli.mjs](/Users/jehyuk/Documents/repo/Tokamak-zk-EVM-contracts/apps/private-state/cli/private-state-bridge-cli.mjs:918)

What it writes:

- the submodule worktree through bootstrap, update, and uninstall flows
- submodule runtime artifacts by running `tokamak-cli --install`

### `apps/private-state/scripts/e2e/run-bridge-private-state-cli-e2e.mjs`

Relevant references:

- [apps/private-state/scripts/e2e/run-bridge-private-state-cli-e2e.mjs](/Users/jehyuk/Documents/repo/Tokamak-zk-EVM-contracts/apps/private-state/scripts/e2e/run-bridge-private-state-cli-e2e.mjs:461)
- [apps/private-state/scripts/e2e/run-bridge-private-state-cli-e2e.mjs](/Users/jehyuk/Documents/repo/Tokamak-zk-EVM-contracts/apps/private-state/scripts/e2e/run-bridge-private-state-cli-e2e.mjs:467)
- [apps/private-state/scripts/e2e/run-bridge-private-state-cli-e2e.mjs](/Users/jehyuk/Documents/repo/Tokamak-zk-EVM-contracts/apps/private-state/scripts/e2e/run-bridge-private-state-cli-e2e.mjs:512)

What it writes:

- submodule runtime artifacts by running `tokamak-cli --synthesize`, `--preprocess`, and `--install`
- Synthesizer `node-cli` launch inputs by invoking the submodule-owned
  `generate-synthesizer-launch-inputs.ts`

### `apps/private-state/scripts/e2e/run-bridge-private-state-e2e.mjs`

Relevant references:

- [apps/private-state/scripts/e2e/run-bridge-private-state-e2e.mjs](/Users/jehyuk/Documents/repo/Tokamak-zk-EVM-contracts/apps/private-state/scripts/e2e/run-bridge-private-state-e2e.mjs:621)
- [apps/private-state/scripts/e2e/run-bridge-private-state-e2e.mjs](/Users/jehyuk/Documents/repo/Tokamak-zk-EVM-contracts/apps/private-state/scripts/e2e/run-bridge-private-state-e2e.mjs:623)
- [apps/private-state/scripts/e2e/run-bridge-private-state-e2e.mjs](/Users/jehyuk/Documents/repo/Tokamak-zk-EVM-contracts/apps/private-state/scripts/e2e/run-bridge-private-state-e2e.mjs:625)
- [apps/private-state/scripts/e2e/run-bridge-private-state-e2e.mjs](/Users/jehyuk/Documents/repo/Tokamak-zk-EVM-contracts/apps/private-state/scripts/e2e/run-bridge-private-state-e2e.mjs:877)

What it writes:

- submodule runtime artifacts by running `tokamak-cli --synthesize`, `--preprocess`,
  `--prove`, `--extract-proof`, `--verify`, and `--install`

## Immediate Removal Targets

If the goal is to remove the top-level Tokamak submodule completely, the remaining parent-repository
targets are:

1. remove or migrate `apps/private-state/scripts/deploy/write-deploy-artifacts.sh`
2. rewrite `apps/private-state/cli/private-state-bridge-cli.mjs`
3. rewrite `apps/private-state/scripts/e2e/run-bridge-private-state-cli-e2e.mjs`
4. rewrite `apps/private-state/scripts/e2e/run-bridge-private-state-e2e.mjs`
5. remove `.gitmodules`, `submodules/Tokamak-zk-EVM/`, and `.git/modules/submodules/Tokamak-zk-EVM/`

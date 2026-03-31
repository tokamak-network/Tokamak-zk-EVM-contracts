# Repository Script Guide

This directory now contains only repository-level helpers that are still part of the current workflow.

## Current Areas

- `scripts/zk/`
  Maintains bridge-facing verifier artifacts, reflected Tokamak constants, and metadata extraction helpers used by bridge deployment and DApp registration.

- `scripts/generate-tokamak-shared-constants.js`
  Refreshes repository-owned shared constants from the latest reflected Tokamak setup.

- `scripts/generate-tokamak-verifier-key.js`
  Regenerates the Tokamak verifier key artifact from the reflected `sigma_verify.rkyv` data.

- `scripts/generate-tokamak-verifier-params.js`
  Refreshes the hardcoded verifier parameters inside `tokamak-zkp/TokamakVerifier.sol`.

- `scripts/artifacts/`
  Stores long-lived generated artifacts that are intentionally kept under version control.

## Removed Legacy Families

The old root-level deployment and upgrade wrappers were removed because they targeted an obsolete bridge layout that no longer matches the current repository.

Current deployment and upgrade entrypoints now live under:

- `bridge/scripts/`
- `apps/private-state/scripts/`

## Current Entrypoints

For bridge deployment and upgrades, use:

- `bridge/scripts/deploy-bridge.sh`
- `bridge/scripts/DeployBridgeStack.s.sol`
- `bridge/scripts/UpgradeBridgeStack.s.sol`

For private-state deployment and local flows, use:

- `apps/private-state/scripts/deploy/`
- `apps/private-state/scripts/anvil/`
- `apps/private-state/scripts/e2e/`

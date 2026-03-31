# Repository Script Guide

This directory now contains only repository-level helpers that are still part of the current workflow.

## Current Areas

- `script/zk/`
  Maintains bridge-facing verifier artifacts, reflected Tokamak constants, and metadata extraction helpers used by bridge deployment and DApp registration.

- `script/generate-tokamak-shared-constants.js`
  Refreshes repository-owned shared constants from the latest reflected Tokamak setup.

- `script/generate-tokamak-verifier-key.js`
  Regenerates the Tokamak verifier key artifact from the reflected `sigma_verify.rkyv` data.

- `script/generate-tokamak-verifier-params.js`
  Refreshes the hardcoded verifier parameters inside `tokamak-zkp/TokamakVerifier.sol`.

- `script/artifacts/`
  Stores long-lived generated artifacts that are intentionally kept under version control.

## Removed Legacy Families

The old root-level deployment and upgrade wrappers were removed because they targeted an obsolete bridge layout that no longer matches the current repository.

Current deployment and upgrade entrypoints now live under:

- `bridge/script/`
- `apps/private-state/script/`

## Current Entrypoints

For bridge deployment and upgrades, use:

- `bridge/script/deploy-bridge.sh`
- `bridge/script/DeployBridgeStack.s.sol`
- `bridge/script/UpgradeBridgeStack.s.sol`

For private-state deployment and local flows, use:

- `apps/private-state/script/deploy/`
- `apps/private-state/script/anvil/`
- `apps/private-state/script/e2e/`

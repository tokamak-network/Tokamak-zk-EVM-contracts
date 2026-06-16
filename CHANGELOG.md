# Changelog

All notable changes to this repository should be recorded here.

This project follows a package-oriented changelog model:

- root workspace changes are recorded under "Workspace"
- `@tokamak-private-dapps/common-library` changes are recorded under "Common Library"
- `@tokamak-private-dapps/groth16` changes are recorded under "Groth16"
- `@tokamak-private-dapps/private-state-cli` changes are recorded under "Private-State CLI"
- bridge and DApp behavior changes are recorded under "Bridge" and "Private-State DApp"

## Unreleased

### Workspace

- Removed tracked local planning and manual-verification notes from the remote clone surface while
  keeping local-only notes ignored.
- Aligned public documentation with current private-state CLI behavior, bridge event paths, and
  current bridge gas/test/size measurements.
- Revised public private-state README terminology to use ordinary-user Ethereum mainnet wording for bridge boundaries.
- Added an automatic npm publish workflow for the private DApp packages.
- Added package-level release readiness checks for npm deployment.
- Added the private-state CLI package to the automatic npm publish workflow.
- Documented the repository as a private npm workspace rather than a publishable package.
- Added repository-level dual-license files for `MIT OR Apache-2.0`.
- Added search and AI-answer discovery material.

### Common Library

- Added npm package metadata for repository, license, and package discovery.

### Groth16

- Added npm package metadata for repository, license, and package discovery.
- Marked `packages/groth16/circuits` as an internal, private build package.

### Private-State CLI

- Added network-scoped install and consent behavior so anvil and Sepolia installs and sensitive
  exports can run non-interactively while mainnet and network-omitted flows remain protected.
- Expanded the installed-package private-state CLI E2E to cover raw evidence export, investigator
  packaging, help/metadata commands, channel metadata inspection, and final channel operation
  abandonment.
- Updated CLI and DApp documentation to describe selected-network transaction submission and
  mainnet-only evidence/export confirmations.
- Revised user-facing CLI terminology in help, guide, README, fee descriptions, and agent guidance to avoid unnecessary
  developer shorthand around Ethereum mainnet, channel-local addresses, and Join Tolls.
- Added npm package metadata, release readiness, and automated publishing coverage.
- Updated channel balance proof generation to use only the fixed Groth16 runtime workspace proof paths.
- Added npm-installed CLI E2E coverage for local tarball package specs before publication.
- Clarified that channel Join Tolls are paid directly from the Ethereum wallet, not from bridge deposits.

### Bridge

- Centralized DApp function metadata hashing for registration and execution-time proof checks while
  preserving the public ABI, storage layout, and proof acceptance behavior.
- Refactored bridge artifact upload orchestration and access-check helpers without changing deployed
  bridge behavior.
- Updated bridge audit, monitoring, and gas documentation to match current tests, contract sizes,
  event paths, and E2E receipt measurements.
- Added a bridge deployment `.env.example`.
- Updated bridge documentation references to point at existing documents.
- Added `bridge/CHANGELOG.md` to track mainnet bridge deployments, deployed source commits,
  and pending bridge changes that are not yet included in mainnet.

### Private-State DApp

- Added basic metadata to the local CLI assistant HTML entrypoint.

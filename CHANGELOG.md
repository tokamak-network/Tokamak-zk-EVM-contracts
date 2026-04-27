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

- Added npm package metadata, release readiness, and automated publishing coverage.

### Bridge

- Added a bridge deployment `.env.example`.
- Updated bridge documentation references to point at existing documents.

### Private-State DApp

- Added basic metadata to the local CLI assistant HTML entrypoint.

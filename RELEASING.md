# Release Process

This repository is a private npm workspace at the root. The root `package.json`
is not a publishable package.

## Versioned Packages

The publishable package boundaries are:

- `packages/common` as `@tokamak-private-dapps/common-library`
- `packages/groth16` as `@tokamak-private-dapps/groth16`

`packages/groth16/circuits` is an internal build package. It is marked
`private` and must not be published independently.

## Version Policy

- Use semantic versioning for published npm packages.
- Keep `@tokamak-private-dapps/groth16` dependency ranges aligned with
  `@tokamak-private-dapps/common-library` releases.
- Record user-visible bridge, DApp, package, and tooling changes in
  `CHANGELOG.md` before tagging a release.
- Tag releases from the repository root with package-aware names:
  - `common-vX.Y.Z`
  - `groth16-vX.Y.Z`
  - `workspace-vYYYY.MM.DD` for non-package repository snapshots when needed

## Pre-Release Checklist

1. Confirm `git status --short` contains only intentional changes.
2. Run `npm install --package-lock-only` after package metadata or dependency
   changes.
3. Run `npm run test:bridge:unit`.
4. Run `npm run test:private-state:cli-e2e` when bridge, Groth16, private-state,
   deployment, or CLI behavior changes.
5. Verify relative Markdown links.
6. Update `CHANGELOG.md`.
7. Commit and tag the release.

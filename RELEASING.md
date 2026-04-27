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
- Record user-visible bridge, DApp, package, and tooling changes in the root
  `CHANGELOG.md`.
- Record package-consumer changes in each publishable package changelog:
  - `packages/common/CHANGELOG.md`
  - `packages/groth16/CHANGELOG.md`
- Tag releases from the repository root with package-aware names:
  - `common-vX.Y.Z`
  - `groth16-vX.Y.Z`
  - `workspace-vYYYY.MM.DD` for non-package repository snapshots when needed

## Automatic npm Publishing

Publishable packages are published automatically from `main` by
`.github/workflows/publish-private-dapp-packages.yml`.

For each package, the workflow:

1. Reads the package manifest.
2. Compares the local version with the version already published on npm.
3. Fails if the local version is behind npm.
4. Skips publishing if the local version is equal to npm.
5. Runs `npm run release:check` when the local version is newer.
6. Runs `npm publish --dry-run`.
7. Publishes to npm with public access.

The workflow expects npm trusted publishing to be configured for the package
scope and GitHub repository environment.

## Pre-Release Checklist

1. Confirm `git status --short` contains only intentional changes.
2. Run `npm install --package-lock-only` after package metadata or dependency
   changes.
3. Run `npm run test:bridge:unit`.
4. Run `npm run test:private-state:cli-e2e` when bridge, Groth16, private-state,
   deployment, or CLI behavior changes.
5. Verify relative Markdown links.
6. Update `CHANGELOG.md`.
7. Update the package changelog for every package whose version changes.
8. Commit and tag the release.

## Package Changelog Format

Use this format in package-level changelogs:

```md
## 0.1.1 - 2026-04-27

- Short package-consumer change
```

The top package changelog entry must match that package's `package.json`
version before the automatic publish workflow can publish it.

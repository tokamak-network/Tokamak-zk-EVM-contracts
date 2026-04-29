# Changelog

## 0.1.2 - 2026-04-29

- Added public Google Drive CRS lookup by exact Groth16 package version.
- Enforced latest public CRS version checks against package and npm latest versions.
- Validated CRS archive provenance versions during install and publish flows.
- Included CRS version check scripts in the published package.

## 0.1.1 - 2026-04-28

- Removed the `./prover/updateTree/generateProof` public export so npm consumers use the `tokamak-groth16` CLI as the package entrypoint.
- Fixed Docker-mode `snarkjs` execution so successful Docker runs do not fall through to host `snarkjs`.
- Disabled host `snarkjs` fallback when the installed Groth16 runtime requires Docker mode.

## 0.1.0 - 2026-04-27

- Added the Groth16 package for Tokamak private DApp proof generation and runtime installation.

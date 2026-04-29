# Changelog

## 0.1.3 - 2026-04-29

- Rejected Groth16 CRS archive names and provenance versions that are not canonical major.minor compatibility versions.
- Introduced major.minor Groth16 compatible backend version metadata for CRS and verifier compatibility checks.
- Documented strict Groth16 package, verifier contract, and CRS version management rules.
- Verified public Google Drive CRS archive selections against embedded provenance before installation.
- Skipped Drive folder listing candidates whose file IDs do not match the advertised Groth16 archive version.

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

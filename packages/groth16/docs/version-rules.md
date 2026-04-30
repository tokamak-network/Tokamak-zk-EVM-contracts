# Groth16 Version Rules

This package has three different versioned surfaces. They intentionally do not all use the same precision.

## Versioned Elements

### Groth16 Package And CLI

The npm package `@tokamak-private-dapps/groth16` and its `tokamak-groth16` CLI use a full semantic version:

```text
MAJOR.MINOR.PATCH
```

This is the package release version. It changes for any published package change, including code-only fixes that do not
change the proving setup.

### Groth16 CRS

The public Groth16 CRS uses only a compatibility version:

```text
MAJOR.MINOR
```

The CRS version identifies the circuit/proving setup compatibility class. It must not include a patch component in newly
published CRS provenance or archive names. A package patch release must continue to use the same CRS compatibility version
when the circuit and proving setup are unchanged.

### Bridge Groth16 Verifier Contract

The bridge `Groth16Verifier` contract stores `compatibleBackendVersion` as:

```text
MAJOR.MINOR
```

The verifier version must match the CRS compatibility version that generated the verifier key. It must not track package
patch releases.

## Compatibility Rule

All Groth16 compatibility checks between package, CRS, and verifier contract compare only canonical `MAJOR.MINOR`.

Examples:

- Package `0.1.3`, CRS `0.1`, and verifier `0.1` are compatible.
- Package `0.2.0`, CRS `0.1`, and verifier `0.1` are incompatible.

Package-version normalization accepts exact semantic versions such as `MAJOR.MINOR.PATCH`, then derives the
`MAJOR.MINOR` compatibility prefix. CRS archive names, CRS provenance, and verifier contracts must store the canonical
`MAJOR.MINOR` form and must not be accepted with a patch component.

## Increment Rules

### Patch Version

Increment `PATCH` when the npm package changes but the circuit, CRS, and verifier key remain valid.

Patch-only changes include:

- CLI bug fixes.
- Download, cache, or Google Drive selection fixes.
- Documentation changes.
- Error message changes.
- Packaging or release tooling changes.
- Runtime orchestration changes that do not alter proof inputs, constraints, metadata semantics required by verification,
  the proving key, or the verification key.

Patch-only changes must not require a new MPC setup, a new CRS upload, or a bridge verifier redeploy.

### Minor Version

Increment `MINOR` when the Groth16 circuit compatibility class changes.

Minor changes include:

- Any change to Circom templates or rendered circuit contents.
- Any change to public signals, public input ordering, or proof verification semantics.
- Any change to Merkle tree depth or field encoding that affects the circuit.
- Any change that modifies the R1CS, proving key, verification key, or trusted setup output.
- Any change in setup tooling or dependency behavior that can produce a different verifier key for the same package.
- Any change to CRS provenance semantics required by proof generation or verification.

A minor change requires a new CRS generation, a new public CRS upload, a verifier refresh, and a bridge verifier upgrade.

### Major Version

Increment `MAJOR` when the proof system, bridge contract interface, security model, or operational compatibility changes
in a way that cannot be represented as a minor circuit compatibility update.

Major changes include:

- Incompatible proof protocol changes.
- Incompatible verifier contract API changes.
- Protocol migrations that require coordinated DApp or bridge state handling.
- Security model changes that invalidate existing operational assumptions.

## Package Metadata

`packages/groth16/package.json` contains:

```json
{
  "tokamakPrivateDapps": {
    "groth16CompatibleBackendVersion": "0.1"
  }
}
```

This value is the canonical package compatibility version. It must equal the package `MAJOR.MINOR` prefix. A package
`0.1.3` may declare only `0.1`; it must not declare `0.2` or `0.1.3`.

Release tooling must fail if the configured compatible backend version does not match the package major.minor.

## CRS Archive And Provenance

New public CRS archives must be named:

```text
tokamak-private-dapps-groth16-vMAJOR.MINOR-YYYYMMDDTHHMMSSZ.zip
```

New `zkey_provenance.json` files must store:

```json
{
  "backend_version": "MAJOR.MINOR"
}
```

CRS archives whose names or provenance use `MAJOR.MINOR.PATCH` are invalid and must not be selected, downloaded, or
published.

The Drive file name and file ID advertised by the public folder listing are not trusted by themselves. Selection must
download the candidate archive and validate embedded provenance and hashes before using it.

## Bridge Deployment

Bridge deployment resolves the latest Groth16 npm package version, normalizes it to `MAJOR.MINOR`, verifies that the
latest public CRS archive has the same compatibility version, and deploys or upgrades `Groth16Verifier` with that
canonical compatibility version.

A Groth16 package patch release must not trigger a verifier redeploy when the CRS compatibility version is unchanged.

## Private-State CLI

`private-state-cli --install` installs the selected Groth16 package version. If `--groth16-cli-version` is omitted, the
CLI resolves the npm registry `latest` version. The installed package version remains full `MAJOR.MINOR.PATCH`.

The Groth16 CRS download uses the installed package compatibility version, not the full package version. For example,
installing package `0.1.3` downloads a CRS compatible with `0.1`.

Before proof generation, private-state CLI reads the target channel's `grothVerifierCompatibleBackendVersion()` and
requires it to already be canonical `MAJOR.MINOR`. It then compares that value with the locally installed Groth16 CRS
compatibility version, which must also be canonical `MAJOR.MINOR`. The same rule applies to Tokamak zk-EVM: private-state
CLI reads the target channel's `tokamakVerifierCompatibleBackendVersion()` and compares it with the installed
`@tokamak-zk-evm/cli` package's canonical `tokamakZkEvm.compatibleBackendVersion`.

## CI Checks

CI checks must compare the latest valid public CRS archive compatibility version against:

- The local Groth16 package compatibility version for repository checks.
- The npm `latest` Groth16 package version normalized to `MAJOR.MINOR` for published-package checks.

CI must not require the public CRS patch component to match the package patch component.

## Operational Playbooks

For a patch-only Groth16 release:

1. Bump the package patch version.
2. Keep `tokamakPrivateDapps.groth16CompatibleBackendVersion` unchanged.
3. Do not regenerate CRS.
4. Do not redeploy the bridge verifier.
5. Verify that CI normalizes the package version and CRS version to the same `MAJOR.MINOR`.

For a minor Groth16 release:

1. Bump the package minor version.
2. Update `tokamakPrivateDapps.groth16CompatibleBackendVersion` to the new `MAJOR.MINOR`.
3. Regenerate the Groth16 CRS.
4. Upload a CRS archive named with the new `MAJOR.MINOR`.
5. Refresh the generated verifier contract.
6. Deploy or upgrade the bridge verifier with the new `compatibleBackendVersion`.
7. Register or update affected DApp/channel references as required by the bridge deployment model.

For a major Groth16 release:

1. Write a migration plan before publishing artifacts.
2. Bump the package major version.
3. Generate and upload new CRS artifacts.
4. Deploy compatible bridge verifier contracts.
5. Coordinate DApp and channel migration explicitly.

# Private-State Bridge E2E

`run-bridge-private-state-cli-e2e.mjs` executes the bridge-coupled private-state participant scenario through command-line entrypoints.
It keeps bridge deployment, DApp registration, and canonical-asset minting in existing helper commands because the
current private-state CLI intentionally starts at user-facing bridge and note flows rather than admin bootstrap flows.

The participant flow runs through an npm-installed `private-state-cli` binary, not the repository source file. By
default, the harness installs the exact `@tokamak-private-dapps/private-state-cli` version declared in
`packages/apps/private-state/cli/package.json` from the npm registry. Set `PRIVATE_STATE_CLI_E2E_PACKAGE_SPEC` to test a
different published tag, version, local tarball, or package spec before publishing a new CLI version.

The scenario combines:

- L1 ERC-20 funding into the bridge vault
- Groth-backed L1 -> L2 accounting deposits
- Tokamak proof-backed private-state mint / transfer / redeem steps
- Groth-backed L2 -> L1 withdrawal
- Final ERC-20 claim on L1

## Scenario

The harness uses three participants:

1. `A`, `B`, and `C` each fund the shared `bridgeTokenVault` and deposit `3` tokens into the channel `channelTokenVault` accounting tree.
2. `A`, `B`, and `C` each call `mintNotes1` with self-mint ciphertext outputs.
3. `A` calls `transferNotes1To2` and splits its `3`-token note into:
   - `1` token to `B`
   - `2` tokens to `C`
   The CLI harness verifies that `transfer-notes` does not write recipient wallet inbox sidecars and that recipients
   recover those notes later through `get-my-notes`.
4. `B` calls `transferNotes2To1` and transfers:
   - its own `3`-token note
   - the `1`-token note received from `A`
   into one `4`-token note for `C`.
   The CLI harness verifies that `C` recovers the new note from Ethereum event logs before redeeming it.
5. `C` redeems all notes. With the current Tokamak setup capacity, the harness realizes that as three `redeemNotes1` calls over:
   - the `2`-token note received directly from `A`
   - the `4`-token note received from `B`
   - its own minted `3`-token note
6. `C` withdraws `9` tokens from the channel `channelTokenVault` accounting tree back into the shared `bridgeTokenVault` and then claims the ERC-20 balance on L1.

## Run

```bash
node packages/apps/private-state/scripts/e2e/run-bridge-private-state-cli-e2e.mjs
```

To test an unpublished local package build, pack the CLI and point the harness at the tarball:

```bash
npm pack ./packages/apps/private-state/cli --pack-destination /tmp/private-state-cli-pack
PRIVATE_STATE_CLI_E2E_PACKAGE_SPEC=/tmp/private-state-cli-pack/tokamak-private-dapps-private-state-cli-<version>.tgz \
  npm run test:private-state:cli-e2e
```

To test unpublished package dependencies together, set `PRIVATE_STATE_CLI_E2E_PACKAGE_SPECS` to a newline-separated,
comma-separated, or JSON-array list of npm package specs. The harness installs every listed package into the temporary
consumer project before executing the `private-state-cli` binary.

Optional flag:

- `--keep-anvil`: leave the local anvil process running after success
- `--skip-install`: skip Tokamak runtime and private-state artifact installation after npm package installation
- `--skip-groth-setup`: skip bridge Groth16 refresh during local redeploy

## Outputs

The CLI-driven harness writes its final summary under:

`packages/apps/private-state/scripts/e2e/output/private-state-bridge-cli/summary.json`

After a successful run, the harness prunes temporary CLI e2e artifacts and leaves only:

- the CLI e2e `summary.json`
- the channel workspace created for the test under `~/tokamak-private-channels/workspace/<network>/<channel>/channel/`
- the participant wallets created for the test under `~/tokamak-private-channels/workspace/<network>/<channel>/wallets/`

To keep disk usage bounded, the harness archives only the step-local Tokamak outputs it actually consumes downstream
(`synthesizer`, `preprocess`, and where needed `prove`) instead of copying the full shared `resource/setup/output`
directory into every step artifact bundle.

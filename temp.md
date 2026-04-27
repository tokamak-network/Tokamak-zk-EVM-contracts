# Repository Script Review Findings

1. Unused private-state E2E note-delivery exports after genesis E2E removal
   - File: `packages/apps/private-state/scripts/e2e/private-state-note-delivery.mjs`
   - Finding: After removing `packages/apps/private-state/scripts/e2e/run-bridge-private-state-e2e.mjs`, the remaining CLI E2E imports only `deriveNoteReceiveKeyMaterial`, `encryptMintNoteValueForOwner`, `computeEncryptedNoteSalt`, and `encryptNoteValueForRecipient` from this helper. `encryptedNoteValueTuple` was used by the removed genesis E2E script and now has no repository reference. `decryptEncryptedNoteValue` and `decryptMintEncryptedNoteValue` are also not imported by the remaining E2E code; the production CLI keeps separate internal implementations of those operations.
   - Recommendation: Remove the unused E2E helper exports and any private helper code that becomes unreachable from the remaining four imported exports, or move shared note-delivery logic into a production module if the CLI and E2E should use one implementation.

2. Duplicate Groth16 MPC setup utility logic
   - Files: `packages/groth16/mpc-setup/generate_update_tree_setup_from_dusk.mjs`, `packages/groth16/mpc-setup/verify_update_tree_phase1_provenance.mjs`
   - Finding: Both scripts duplicate command resolution, `snarkjs` execution wrapping, tool checks, file hashing, HTTPS download handling, redirect handling, and Google Drive confirmed-download URL extraction.
   - Recommendation: Move the shared process/download/hash helpers into a package-local `packages/groth16/mpc-setup/lib/` module and keep each entrypoint focused on its specific generation or verification workflow.

3. Large inline Node blocks inside bridge deployment shell script
   - File: `bridge/scripts/deploy-bridge.sh`
   - Finding: The script contains multiple inline Node programs for runtime discovery, verifier refresh, constant refresh, manifest generation, artifact synchronization, and deployment JSON finalization. This is not dead code, but it makes the deployment workflow harder to test and maintain.
   - Recommendation: Gradually move the inline Node blocks into importable `bridge/scripts/lib/*.mjs` helpers, leaving the shell script as an orchestration layer.

4. Manual provenance verification script has low discoverability
   - File: `packages/groth16/mpc-setup/verify_update_tree_phase1_provenance.mjs`
   - Finding: The script is documented in `packages/groth16/mpc-setup/README.md`, but it is not exposed through `packages/groth16/package.json` scripts or package binaries. It appears to be a valid manual verification tool, not unused logic.
   - Recommendation: Add an npm script such as `mpc:verify-update-tree-phase1` if this verification should be part of regular operator or CI workflows.

5. Groth16 trusted-setup path is retained for compatibility
   - Files: `packages/groth16/cli/tokamak-groth16-cli.mjs`, `packages/groth16/lib/proof-runtime.mjs`, `bridge/scripts/deploy-bridge.sh`
   - Finding: The current default Groth16 setup source is public Drive MPC, but `--trusted-setup` and `BRIDGE_GROTH_SOURCE=trusted` still copy packaged CRS artifacts from `packages/groth16/trusted-setup/crs`. This looks like an intentional compatibility path for older or offline workflows.
   - Recommendation: Keep it only if trusted setup fallback is still an explicit operator requirement. Otherwise, mark it deprecated before removal because it affects package files and bridge deployment behavior.

6. Groth16 CLI accepts `--docker` for command parity only
   - Files: `packages/groth16/cli/tokamak-groth16-cli.mjs`, `packages/groth16/lib/proof-runtime.mjs`
   - Finding: `--docker` is accepted during Groth16 runtime install, but the help text states that the Groth16 runtime uses packaged native Circom binaries. The runtime records `dockerRequested` in the manifest without switching behavior.
   - Recommendation: Treat this as compatibility glue with the Tokamak CLI UX. If it is kept, the help text should remain explicit that it is accepted but behaviorally inert.

7. Bridge deployment mode compatibility logic remains active
   - File: `bridge/scripts/deploy-bridge.sh`
   - Finding: The deploy script supports `upgrade` and `redeploy-proxy`. The `upgrade` path requires an existing UUPS proxy artifact, while `redeploy-proxy` bootstraps or replaces proxy deployments. This appears to be current migration/bootstrap compatibility rather than unused code.
   - Recommendation: Keep while networks may need proxy bootstrapping or replacement. If all supported networks have stable proxy artifacts, consider documenting a future removal path for `redeploy-proxy`.

8. Root-level legacy deployment wrappers were already removed
   - File: `scripts/README.md`
   - Finding: The repository explicitly documents that old root-level deployment and upgrade wrappers were removed because they targeted an obsolete bridge layout. Current entrypoints live under `bridge/scripts/` and `packages/apps/private-state/scripts/`.
   - Recommendation: No cleanup is needed for those removed wrappers. The README is useful context and should remain aligned with current deployment entrypoints.

9. No clearly unused repository-owned script entrypoint was found
    - Scope: `scripts/`, `bridge/scripts/`, `packages/common`, `packages/groth16`, and `packages/apps/private-state`
    - Finding: Referenced scripts are reachable through package scripts, Makefile targets, GitHub Actions, README/operator docs, package exports, direct CLI bins, or other scripts. Submodule scripts under `lib/` are external upstream code and were not treated as removable repository-owned logic.
    - Recommendation: Do not remove scripts based only on the current reference scan. Prefer targeted refactors for the duplicate helper logic listed above.

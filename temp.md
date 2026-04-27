# Repository Script Review Findings

1. Large inline Node blocks inside bridge deployment shell script
   - File: `bridge/scripts/deploy-bridge.sh`
   - Finding: The script contains multiple inline Node programs for runtime discovery, verifier refresh, constant refresh, manifest generation, artifact synchronization, and deployment JSON finalization. This is not dead code, but it makes the deployment workflow harder to test and maintain.
   - Recommendation: Gradually move the inline Node blocks into importable `bridge/scripts/lib/*.mjs` helpers, leaving the shell script as an orchestration layer.

2. Manual provenance verification script has low discoverability
   - File: `packages/groth16/mpc-setup/verify_update_tree_phase1_provenance.mjs`
   - Finding: The script is documented in `packages/groth16/mpc-setup/README.md`, but it is not exposed through `packages/groth16/package.json` scripts or package binaries. It appears to be a valid manual verification tool, not unused logic.
   - Recommendation: Add an npm script such as `mpc:verify-update-tree-phase1` if this verification should be part of regular operator or CI workflows.

3. Groth16 trusted-setup path is retained for compatibility
   - Files: `packages/groth16/cli/tokamak-groth16-cli.mjs`, `packages/groth16/lib/proof-runtime.mjs`, `bridge/scripts/deploy-bridge.sh`
   - Finding: The current default Groth16 setup source is public Drive MPC, but `--trusted-setup` and `BRIDGE_GROTH_SOURCE=trusted` still copy packaged CRS artifacts from `packages/groth16/trusted-setup/crs`. This looks like an intentional compatibility path for older or offline workflows.
   - Recommendation: Keep it only if trusted setup fallback is still an explicit operator requirement. Otherwise, mark it deprecated before removal because it affects package files and bridge deployment behavior.

4. Groth16 CLI accepts `--docker` for command parity only
   - Files: `packages/groth16/cli/tokamak-groth16-cli.mjs`, `packages/groth16/lib/proof-runtime.mjs`
   - Finding: `--docker` is accepted during Groth16 runtime install, but the help text states that the Groth16 runtime uses packaged native Circom binaries. The runtime records `dockerRequested` in the manifest without switching behavior.
   - Recommendation: Treat this as compatibility glue with the Tokamak CLI UX. If it is kept, the help text should remain explicit that it is accepted but behaviorally inert.

5. Bridge deployment mode compatibility logic remains active
   - File: `bridge/scripts/deploy-bridge.sh`
   - Finding: The deploy script supports `upgrade` and `redeploy-proxy`. The `upgrade` path requires an existing UUPS proxy artifact, while `redeploy-proxy` bootstraps or replaces proxy deployments. This appears to be current migration/bootstrap compatibility rather than unused code.
   - Recommendation: Keep while networks may need proxy bootstrapping or replacement. If all supported networks have stable proxy artifacts, consider documenting a future removal path for `redeploy-proxy`.

6. Root-level legacy deployment wrappers were already removed
   - File: `scripts/README.md`
   - Finding: The repository explicitly documents that old root-level deployment and upgrade wrappers were removed because they targeted an obsolete bridge layout. Current entrypoints live under `bridge/scripts/` and `packages/apps/private-state/scripts/`.
   - Recommendation: No cleanup is needed for those removed wrappers. The README is useful context and should remain aligned with current deployment entrypoints.

7. No clearly unused repository-owned script entrypoint was found
    - Scope: `scripts/`, `bridge/scripts/`, `packages/common`, `packages/groth16`, and `packages/apps/private-state`
    - Finding: Referenced scripts are reachable through package scripts, Makefile targets, GitHub Actions, README/operator docs, package exports, direct CLI bins, or other scripts. Submodule scripts under `lib/` are external upstream code and were not treated as removable repository-owned logic.
    - Recommendation: Do not remove scripts based only on the current reference scan. Prefer targeted refactors for the duplicate helper logic listed above.

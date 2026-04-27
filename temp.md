# Repository Script Review Findings

1. Groth16 standalone prover writes default outputs inside the package
   - Files: `packages/groth16/prover/updateTree/generateProof.mjs`, `packages/groth16/package.json`
   - Finding: The published bin `tokamak-groth16-update-tree-proof` defaults to package-local files when flags are omitted: `prover/updateTree/input_example.json`, `prover/updateTree/witness.wtns`, `prover/updateTree/proof.json`, `prover/updateTree/public.json`, `prover/updateTree/solidity_fixture.json`, and `prover/updateTree/.tmp/updateTree.verification_key.json`. It also compiles the circuit into `packages/groth16/circuits/build` unless `--skip-compile` is provided.
   - Recommendation: Move default prover outputs and temporary verification-key export into the Groth16 user workspace (`~/tokamak-private-channels/groth16` by default, or `TOKAMAK_GROTH16_WORKSPACE_ROOT`). Keep package-local paths only as explicit developer overrides.

2. Groth16 circuits package compiles into its own package directory
   - Files: `packages/groth16/circuits/package.json`, `packages/groth16/circuits/run-circom-2.0.mjs`
   - Finding: `npm --prefix packages/groth16/circuits run compile` writes generated R1CS/WASM/SYM files under `packages/groth16/circuits/build`. This is acceptable for repository development, but it is not a user-local default for an npm-installed package.
   - Recommendation: Keep this as a developer build script only, or add a workspace-aware output option and make published runtime flows compile into the Groth16 workspace instead of the installed package directory.

3. Groth16 MPC setup and publisher write generated artifacts inside the package
   - Files: `packages/groth16/mpc-setup/generate_update_tree_setup_from_dusk.mjs`, `packages/groth16/mpc-setup/publish_update_tree_setup.mjs`
   - Finding: The setup generator writes temporary downloads/intermediates to `packages/groth16/mpc-setup/.tmp`, final CRS outputs to `packages/groth16/mpc-setup/crs`, rewrites `packages/groth16/circuits/src/circuit_updateTree.circom`, and compiles into `packages/groth16/circuits/build/updateTree`. The publisher mutates `packages/groth16/mpc-setup/crs/zkey_provenance.json` and writes archives/results into `packages/groth16/mpc-setup/.tmp`.
   - Recommendation: Treat these as repository maintainer/publishing tools, not user runtime commands. If they remain shipped in the npm package, require explicit `--output-dir`/`--work-dir` paths or default them to a user-local workspace/cache directory.

4. Private-state local tooling writes logs and E2E output inside the app directory
   - Files: `packages/apps/private-state/scripts/anvil/start-anvil.mjs`, `packages/apps/private-state/scripts/anvil/stop-anvil.mjs`, `packages/apps/private-state/scripts/e2e/run-bridge-private-state-cli-e2e.mjs`
   - Finding: The local anvil helpers write `packages/apps/private-state/deploy/anvil.pid` and `packages/apps/private-state/deploy/anvil.log`. The CLI E2E script writes summaries, diagnostics, generated launch inputs, temp JSON, and copied resource outputs under `packages/apps/private-state/scripts/e2e/output/private-state-bridge-cli`.
   - Recommendation: Keep these paths only for repository-local test workflows. If private-state tooling is packaged for users, route these outputs through a user-local workspace or require explicit output/log paths.

5. Repository deployment helpers write generated deployment artifacts under the repository root
   - Files: `bridge/scripts/deploy-bridge.mjs`, `packages/apps/private-state/scripts/deploy/write-deploy-artifacts.mjs`, `scripts/deployment/lib/deployment-layout.mjs`
   - Finding: Bridge and DApp deployment helpers write timestamped deployment snapshots, ABI manifests, Groth16 mirrors, and Tokamak zk proof mirrors under `deployment/chain-id-*/...`. `deploy-bridge.mjs` also refreshes generated Solidity and verifier constants under `bridge/src/generated/`, `bridge/src/verifiers/`, and `bridge/src/ChannelManager.sol`.
   - Recommendation: This is appropriate for repository-owned deployment publishing, but not for npm package runtime defaults. Any user-installed deployment CLI should default to a user-local artifact root or require an explicit output root.

6. Groth16 trusted-setup source is retained for compatibility
   - Files: `packages/groth16/cli/tokamak-groth16-cli.mjs`, `packages/groth16/lib/proof-runtime.mjs`, `bridge/scripts/deploy-bridge.mjs`
   - Finding: The current default Groth16 setup source is public Drive MPC, but `--trusted-setup` and `BRIDGE_GROTH_SOURCE=trusted` still use packaged CRS artifacts from `packages/groth16/trusted-setup/crs` as an install source. The installed runtime CRS lives in the Groth16 workspace (`~/tokamak-private-channels/groth16` by default, or `TOKAMAK_GROTH16_WORKSPACE_ROOT`), not inside the package directory.
   - Recommendation: Keep the packaged trusted setup source only if trusted setup fallback is still an explicit operator requirement. Otherwise, mark it deprecated before removal because it affects package files and bridge deployment behavior.

7. Groth16 CLI accepts `--docker` for command parity only
   - Files: `packages/groth16/cli/tokamak-groth16-cli.mjs`, `packages/groth16/lib/proof-runtime.mjs`
   - Finding: `--docker` is accepted during Groth16 runtime install, but the help text states that the Groth16 runtime uses packaged native Circom binaries. The runtime records `dockerRequested` in the manifest without switching behavior.
   - Recommendation: Treat this as compatibility glue with the Tokamak CLI UX. If it is kept, the help text should remain explicit that it is accepted but behaviorally inert.

8. Bridge deployment mode compatibility logic remains active
   - File: `bridge/scripts/deploy-bridge.mjs`
   - Finding: The deploy script supports `upgrade` and `redeploy-proxy`. The `upgrade` path requires an existing UUPS proxy artifact, while `redeploy-proxy` bootstraps or replaces proxy deployments. This appears to be current migration/bootstrap compatibility rather than unused code.
   - Recommendation: Keep while networks may need proxy bootstrapping or replacement. If all supported networks have stable proxy artifacts, consider documenting a future removal path for `redeploy-proxy`.

9. Root-level legacy deployment wrappers were already removed
   - File: `scripts/README.md`
   - Finding: The repository explicitly documents that old root-level deployment and upgrade wrappers were removed because they targeted an obsolete bridge layout. Current entrypoints live under `bridge/scripts/` and `packages/apps/private-state/scripts/`.
   - Recommendation: No cleanup is needed for those removed wrappers. The README is useful context and should remain aligned with current deployment entrypoints.

10. No clearly unused repository-owned script entrypoint was found
    - Scope: `scripts/`, `bridge/scripts/`, `packages/common`, `packages/groth16`, and `packages/apps/private-state`
    - Finding: Referenced scripts are reachable through package scripts, Makefile targets, GitHub Actions, README/operator docs, package exports, direct CLI bins, or other scripts. Submodule scripts under `lib/` are external upstream code and were not treated as removable repository-owned logic.
    - Recommendation: Do not remove scripts based only on the current reference scan.

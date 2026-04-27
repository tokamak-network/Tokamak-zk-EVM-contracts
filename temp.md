# Repository Script Review Findings

1. Groth16 CLI accepts `--docker` for command parity only
   - Files: `packages/groth16/cli/tokamak-groth16-cli.mjs`, `packages/groth16/lib/proof-runtime.mjs`
   - Finding: `--docker` is accepted during Groth16 runtime install, but the help text states that the Groth16 runtime uses packaged native Circom binaries. The runtime records `dockerRequested` in the manifest without switching behavior.
   - Recommendation: Treat this as compatibility glue with the Tokamak CLI UX. If it is kept, the help text should remain explicit that it is accepted but behaviorally inert.

2. Bridge deployment mode compatibility logic remains active
   - File: `bridge/scripts/deploy-bridge.mjs`
   - Finding: The deploy script supports `upgrade` and `redeploy-proxy`. The `upgrade` path requires an existing UUPS proxy artifact, while `redeploy-proxy` bootstraps or replaces proxy deployments. This appears to be current migration/bootstrap compatibility rather than unused code.
   - Recommendation: Keep while networks may need proxy bootstrapping or replacement. If all supported networks have stable proxy artifacts, consider documenting a future removal path for `redeploy-proxy`.

3. Root-level legacy deployment wrappers were already removed
   - File: `scripts/README.md`
   - Finding: The repository explicitly documents that old root-level deployment and upgrade wrappers were removed because they targeted an obsolete bridge layout. Current entrypoints live under `bridge/scripts/` and `packages/apps/private-state/scripts/`.
   - Recommendation: No cleanup is needed for those removed wrappers. The README is useful context and should remain aligned with current deployment entrypoints.

4. No clearly unused repository-owned script entrypoint was found
    - Scope: `scripts/`, `bridge/scripts/`, `packages/common`, `packages/groth16`, and `packages/apps/private-state`
    - Finding: Referenced scripts are reachable through package scripts, Makefile targets, GitHub Actions, README/operator docs, package exports, direct CLI bins, or other scripts. Submodule scripts under `lib/` are external upstream code and were not treated as removable repository-owned logic.
    - Recommendation: Do not remove scripts based only on the current reference scan.

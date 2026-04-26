# Repository Script Audit

This note records the current audit findings for repository scripts, focusing on duplicated logic, unused logic, and compatibility leftovers.

## Findings

1. Latest `tokamak-l2js` installation and `MT_DEPTH` resolution logic is duplicated.
   - `bridge/scripts/resolve-latest-mt-depth.mjs` resolves and temporarily installs latest `tokamak-l2js` to read `MT_DEPTH`.
   - `packages/groth16/mpc-setup/generate_update_tree_setup_from_dusk.mjs` has a similar responsibility for Groth16 circuit generation.
   - This should be centralized if both bridge and Groth16 setup continue to depend on latest published `tokamak-l2js`.

2. `bridge/scripts/deploy-bridge.sh` repeats inline Node runtime-path resolution.
   - The script imports `@tokamak-private-dapps/common-library/tokamak-runtime-paths` in several separate inline Node blocks.
   - This is not immediately removable because previous design direction embedded deployment flow into the bridge deploy script.
   - It is still a maintainability cost.

3. Bridge deployment keeps a compatibility fallback for Tokamak setup version metadata.
   - `bridge/scripts/deploy-bridge.sh` falls back to the Tokamak CLI package version when `build-metadata-mpc-setup.json` is missing.
   - If current deployment requires setup metadata, this fallback should be replaced with a fail-fast error.

## Keep For Now

1. `scripts/artifacts/lib/deployment-layout.mjs`
   - This is still used by bridge/admin artifact upload flows.
   - The `tokamak-zkp` names inside it are deployment artifact layout names, not a live dependency on a root `tokamak-zkp` folder.
   - It should not be deleted without replacing its bridge/admin callers.

## Suggested Cleanup Order

1. Share the `tokamak-l2js` latest-version and `MT_DEPTH` resolver.
2. Decide whether bridge deployment metadata fallbacks should remain or fail fast.

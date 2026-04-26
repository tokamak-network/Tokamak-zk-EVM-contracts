# Repository Script Audit

This note records the current audit findings for repository scripts, focusing on duplicated logic, unused logic, and compatibility leftovers.

## Findings

1. Public Groth16 CRS download logic is duplicated.
   - `packages/common/src/artifact-cache.mjs` and `packages/groth16/lib/public-drive-crs.mjs` both contain Google Drive folder scraping, archive selection, zip extraction, provenance parsing, and hash validation logic for the same Groth16 MPC artifacts.
   - The better ownership boundary is to keep Groth16 CRS-specific logic in the Groth16 package and have private-state installation call that package API, or extract only generic Drive/zip helpers into common code.

2. Network configuration is duplicated between JavaScript and shell.
   - `packages/common/src/network-config.mjs` and `packages/common/src/network-config.sh` both define network-to-chain and Alchemy mappings.
   - The shell file is still used by private-state anvil/deploy scripts, so it is not dead.
   - The duplication creates drift risk when adding or changing networks.

3. Latest `tokamak-l2js` installation and `MT_DEPTH` resolution logic is duplicated.
   - `bridge/scripts/resolve-latest-mt-depth.mjs` resolves and temporarily installs latest `tokamak-l2js` to read `MT_DEPTH`.
   - `packages/groth16/mpc-setup/generate_update_tree_setup_from_dusk.mjs` has a similar responsibility for Groth16 circuit generation.
   - This should be centralized if both bridge and Groth16 setup continue to depend on latest published `tokamak-l2js`.

4. `bridge/scripts/deploy-bridge.sh` repeats inline Node runtime-path resolution.
   - The script imports `@tokamak-private-dapps/common-library/tokamak-runtime-paths` in several separate inline Node blocks.
   - This is not immediately removable because previous design direction embedded deployment flow into the bridge deploy script.
   - It is still a maintainability cost.

5. Bridge deployment keeps a compatibility fallback for Tokamak setup version metadata.
   - `bridge/scripts/deploy-bridge.sh` falls back to the Tokamak CLI package version when `build-metadata-mpc-setup.json` is missing.
   - If current deployment requires setup metadata, this fallback should be replaced with a fail-fast error.

## Keep For Now

1. `scripts/artifacts/lib/deployment-layout.mjs`
   - This is still used by bridge/admin artifact upload flows.
   - The `tokamak-zkp` names inside it are deployment artifact layout names, not a live dependency on a root `tokamak-zkp` folder.
   - It should not be deleted without replacing its bridge/admin callers.

2. Private-state anvil and deploy shell scripts
   - They are still invoked by package scripts, Makefile targets, or e2e flows.
   - They depend on `packages/common/src/network-config.sh`, so that shell helper remains active until those scripts are rewritten to call a JavaScript helper.

## Suggested Cleanup Order

1. Consolidate Groth16 CRS Drive download logic under one owner.
2. Consolidate network configuration so one source of truth generates or serves both JS and shell consumers.
3. Share the `tokamak-l2js` latest-version and `MT_DEPTH` resolver.
4. Decide whether bridge deployment metadata fallbacks should remain or fail fast.

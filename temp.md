# Repository Script Audit

This note records the current audit findings for repository scripts, focusing on duplicated logic, unused logic, and compatibility leftovers.

## Findings

1. Bridge deployment keeps a compatibility fallback for Tokamak setup version metadata.
   - `bridge/scripts/deploy-bridge.sh` falls back to the Tokamak CLI package version when `build-metadata-mpc-setup.json` is missing.
   - If current deployment requires setup metadata, this fallback should be replaced with a fail-fast error.

## Keep For Now

1. `scripts/artifacts/lib/deployment-layout.mjs`
   - This is still used by bridge/admin artifact upload flows.
   - The `tokamak-zkp` names inside it are deployment artifact layout names, not a live dependency on a root `tokamak-zkp` folder.
   - It should not be deleted without replacing its bridge/admin callers.

## Suggested Cleanup Order

1. Decide whether bridge deployment metadata fallbacks should remain or fail fast.

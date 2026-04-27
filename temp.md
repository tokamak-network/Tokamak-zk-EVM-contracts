# Repository Script Audit

This note records the current audit findings for repository scripts, focusing on duplicated logic, unused logic, and compatibility leftovers.

## Findings

No unresolved findings remain.

## Keep For Now

1. `scripts/artifacts/lib/deployment-layout.mjs`
   - This is still used by bridge/admin artifact upload flows.
   - The `tokamak-zkp` names inside it are deployment artifact layout names, not a live dependency on a root `tokamak-zkp` folder.
   - It should not be deleted without replacing its bridge/admin callers.

## Suggested Cleanup Order

No cleanup items remain.

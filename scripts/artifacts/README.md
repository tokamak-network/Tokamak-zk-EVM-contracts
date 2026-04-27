# Script Artifacts

This directory stores long-lived generated artifacts that remain relevant to current repository workflows or are still kept for historical reference.

## Contents

### `contracts/`

Legacy network-specific contract manifests from the removed root deployment flow.

They are no longer the authoritative source for current bridge deployments. Current bridge deployment outputs live under:

- `deployment/chain-id-<chain-id>/bridge/<timestamp>/`

## Convention

- Long-lived generated artifacts belong under `scripts/artifacts/`.
- Temporary execution output belongs under an `output/` directory and should remain ignored by Git.

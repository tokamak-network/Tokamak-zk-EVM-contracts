---
name: deployment-remote-source-integrity
description: Use before deploying the bridge, deploying a DApp, registering a DApp, or uploading bridge/DApp deployment metadata from this repository. It enforces that deployment metadata can point users to source code that already exists on the remote repository.
---

# Deployment Remote Source Integrity

Use this skill before any operation that deploys the bridge, deploys a DApp, registers a DApp,
or uploads `bridge.*.json` or `deployment.*.*.json` metadata.

## Hard Rule

Do not deploy or register unless the exact local `HEAD` commit is already present on the remote
repository that will be written into deployment metadata.

If the check fails, stop before deployment and tell the user to push the commit first. Do not
infer permission to push unless the user explicitly requested it.

## Required Check

Run this immediately before the deployment or registration command:

```bash
git fetch --prune --tags origin
head_sha="$(git rev-parse HEAD)"
git branch -r --contains "$head_sha"
git tag --contains "$head_sha"
```

The check passes only if at least one remote-tracking branch or fetched tag contains `HEAD`.
If both lists are empty, the commit is not known to the remote and deployment must stop.

## Dirty Worktree

If deployment-relevant source, generated verifier code, deployment scripts, metadata helpers, or
artifact upload scripts are modified in the working tree, do not deploy from that dirty state.
Commit those changes first, then apply the remote-presence check above.

## Branch Labels

Deployment metadata may record branch labels such as a normal branch name, `tagged`,
`detached head`, `CI`, or `unknown`. These labels do not replace the remote-presence check.
The commit hash is the source-of-truth for whether `sourceUrl` can resolve.

## Completion Note

In the final response for a deployment or registration task, state which commit was checked and
whether it was found on the remote before the deployment proceeded.

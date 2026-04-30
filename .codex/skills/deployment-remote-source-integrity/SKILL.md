---
name: deployment-remote-source-integrity
description: Use before deploying the bridge, deploying a DApp, registering a DApp, or uploading bridge/DApp deployment metadata from this repository. It enforces that deployment metadata can point users to source code that already exists on the remote repository.
---

# Deployment Remote Source Integrity

Use this skill before any operation that deploys the bridge, deploys a DApp, registers a DApp,
or uploads `bridge.*.json` or `deployment.*.*.json` metadata.

## Entry Scripts

Use these repository entrypoints for deployment and registration work:

- Bridge deployment: `node bridge/scripts/deploy-bridge.mjs ...`
- Private-state DApp deployment: `node packages/apps/private-state/scripts/deploy/deploy-private-state.mjs ...`
- Private-state DApp deployment artifact writing: `node packages/apps/private-state/scripts/deploy/write-deploy-artifacts.mjs <chain-id>`
- DApp registration: `node bridge/scripts/admin-add-dapp.mjs ...`
- Combined private-state DApp deploy-and-register wrapper: `node bridge/scripts/deploy-and-add-dapp.mjs ...`

The combined wrapper does not bypass any of this skill's checks. Apply the bridge/DApp deployment
and DApp registration checks before running it.

## Hard Rule

Do not deploy or register unless the exact local `HEAD` commit is already present on the remote
`main` branch of the repository that will be written into deployment metadata.

If the check fails, stop before deployment and tell the user to push the commit first. Do not
infer permission to push unless the user explicitly requested it.

## Required Remote Main Check

Run this immediately before the deployment or registration command:

```bash
git fetch --prune origin main
head_sha="$(git rev-parse HEAD)"
git merge-base --is-ancestor "$head_sha" origin/main
```

The check passes only if `origin/main` contains `HEAD`. A tag or another remote branch is not
enough. If this command fails, the commit is not present on remote `main` and deployment must stop.

## Contract Code Diff Check

Before bridge deployment or DApp deployment, compare the current execution commit with the commit
recorded in the latest existing deployment metadata:

- Bridge deployment metadata: latest `bridge.*.json` for the target chain.
- DApp deployment metadata: latest `deployment.*.*.json` for the target app and chain.
- Previous commit field: `.sourceCode.repository.commit`.
- Current commit: `git rev-parse HEAD`.

If the previous deployment metadata has no source commit, or the previous commit cannot be fetched
or resolved locally, stop and ask the user before deployment unless they explicitly requested a
forced deployment.

For the diff, compare deployment-relevant Solidity contract sources only:

- Bridge: `bridge/src/**/*.sol`
- Private-state DApp: `packages/apps/private-state/src/**/*.sol`

Use a command equivalent to:

```bash
git fetch --prune origin main
previous_sha="<commit from latest deployment metadata>"
current_sha="$(git rev-parse HEAD)"
git diff --name-only "$previous_sha" "$current_sha" -- ':(glob)bridge/src/**/*.sol'
git diff --name-only "$previous_sha" "$current_sha" -- ':(glob)packages/apps/private-state/src/**/*.sol'
```

Apply the bridge path for bridge deployment and the DApp path for DApp deployment. If the relevant
diff is empty, refuse to deploy because there is no substantive contract-code change. Proceed only
when the user explicitly requested a forced deployment in the current task.

DApp registration alone does not require this contract-code diff check unless it also runs a DApp
deployment through the combined wrapper.

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

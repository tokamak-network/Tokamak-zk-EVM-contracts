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

## External NPM Dependencies

Before running any entry script, upgrade its external npm dependencies from the npm registry. Do
not use `npm ci`, and do not rely on `package-lock.json` to choose dependency versions. Use
`npm install --no-save --package-lock=false <package>@latest ...` so the deployment uses registry
latest without rewriting package manifests or lockfiles.

Entry script dependency sets:

- `bridge/scripts/deploy-bridge.mjs`
  - `@ethereumjs/util`
  - `@tokamak-private-dapps/common-library`
  - `@tokamak-private-dapps/groth16`
  - `@tokamak-zk-evm/cli`
  - `@tokamak-zk-evm/subcircuit-library`
  - `@tokamak-zk-evm/synthesizer-node`
  - `@google-cloud/local-auth`
  - `dotenv`
  - `ethers`
  - `googleapis`
  - `yauzl`
  - `yazl`
- `packages/apps/private-state/scripts/deploy/deploy-private-state.mjs`
  - `@tokamak-private-dapps/common-library`
  - `dotenv`
- `packages/apps/private-state/scripts/deploy/write-deploy-artifacts.mjs`
  - no external npm dependency beyond the repository-local helpers and the `forge` executable
- `bridge/scripts/admin-add-dapp.mjs`
  - `@tokamak-private-dapps/common-library`
  - `@tokamak-zk-evm/cli`
  - `@tokamak-zk-evm/subcircuit-library`
  - `@tokamak-zk-evm/synthesizer-node`
  - `@google-cloud/local-auth`
  - `ethers`
  - `googleapis`
- `bridge/scripts/deploy-and-add-dapp.mjs`
  - union of the private-state DApp deploy dependencies and DApp registration dependencies

For a bridge deployment, run:

```bash
npm install --no-save --package-lock=false \
  @ethereumjs/util@latest \
  @tokamak-private-dapps/common-library@latest \
  @tokamak-private-dapps/groth16@latest \
  @tokamak-zk-evm/cli@latest \
  @tokamak-zk-evm/subcircuit-library@latest \
  @tokamak-zk-evm/synthesizer-node@latest \
  @google-cloud/local-auth@latest \
  dotenv@latest \
  ethers@latest \
  googleapis@latest \
  yauzl@latest \
  yazl@latest
```

For a private-state DApp deployment, run:

```bash
npm install --no-save --package-lock=false \
  @tokamak-private-dapps/common-library@latest \
  dotenv@latest
```

For a DApp registration, run:

```bash
npm install --no-save --package-lock=false \
  @tokamak-private-dapps/common-library@latest \
  @tokamak-zk-evm/cli@latest \
  @tokamak-zk-evm/subcircuit-library@latest \
  @tokamak-zk-evm/synthesizer-node@latest \
  @google-cloud/local-auth@latest \
  ethers@latest \
  googleapis@latest
```

## Bridge Deployment Mode

Bridge deployment supports `upgrade` and `redeploy-proxy` modes through
`node bridge/scripts/deploy-bridge.mjs --mode <mode>`.

- Sepolia: prefer `upgrade` whenever the existing deployment artifact makes upgrade mode usable.
  Use `redeploy-proxy` only when upgrade mode cannot be used because the target network has no
  usable proxy deployment artifact yet, or when the user explicitly requests a forced proxy
  redeployment.
- Mainnet: if a bridge proxy is already deployed, use `upgrade` mode only. Do not run
  `redeploy-proxy` against mainnet once a proxy exists, even if the user request is informal or
  ambiguous. Stop and ask for clarification if the available metadata does not make proxy
  existence clear.

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

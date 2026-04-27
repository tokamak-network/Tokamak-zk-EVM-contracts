# private-state CLI

Command-line client for the Tokamak private-state DApp.

## Install

```bash
npm install -g @tokamak-private-dapps/private-state-cli
```

Install the local Tokamak zk-EVM runtime workspace and public private-state deployment artifacts:

```bash
private-state-cli --install
```

`--install` downloads public deployment artifacts from the configured artifact index. It does not read repository-local
`deployment/` outputs by default. Repository development workflows that need local anvil artifacts can opt in explicitly:

```bash
private-state-cli --install --include-local-artifacts
```

Run the CLI with:

```bash
private-state-cli <command> ...
```

## Commands

The normal private-state flow is:

1. `create-channel`
2. `deposit-bridge`
3. `join-channel`
4. `deposit-channel`
5. `mint-notes`
6. `transfer-notes`
7. `get-my-notes`
8. `redeem-notes`
9. `withdraw-channel`
10. `withdraw-bridge`

Use `private-state-cli --help` for the full command list and required options.

## Workspace

The CLI stores user workspaces under:

```text
~/tokamak-private-channels/workspace/<network>/<channel>/
```

Wallet data is encrypted with the password supplied to `join-channel` or `recover-wallet`.

## Artifacts

Proof-backed commands require installed bridge, DApp, and Groth16 artifacts. Run `private-state-cli --install` before
using bridge-facing commands on a new machine.

Release order matters for npm publication. `@tokamak-private-dapps/common-library` and
`@tokamak-private-dapps/groth16` must be published before this package version.

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

Check the installed package and runtime state with:

```bash
private-state-cli --doctor
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

`private-state-cli --doctor` reports the CLI package version, dependency versions recorded by the last
`private-state-cli --install`, current dependency versions through `tokamak-l2js`, and Tokamak zk-EVM runtime
install mode, Docker mode, and CUDA runtime metadata.

## Workspace

The CLI stores user workspaces under:

```text
~/tokamak-private-channels/workspace/<network>/<channel>/
```

Wallet data is encrypted with the password supplied to `join-channel` or `recover-wallet`.

## Artifacts

Proof-backed commands require installed bridge, DApp, and Groth16 artifacts. Run `private-state-cli --install` before
using bridge-facing commands on a new machine.

Channel balance commands such as `deposit-channel` and `withdraw-channel` use the installed Groth16 runtime workspace
directly. Proof generation writes to the fixed workspace paths under `~/tokamak-private-channels/groth16/proof`; the CLI
does not pass custom `--zkey`, proof-output, or public-output paths to the Groth16 prover.

Release order matters for npm publication. `@tokamak-private-dapps/common-library` and
`@tokamak-private-dapps/groth16` must be published before this package version.

## FAQ

### What does this package install?

It installs the `private-state-cli` terminal command and the local files needed by that command.
It does not install bridge contracts, app contracts, or local deployment outputs.

### When should I run `private-state-cli --install`?

Run it once on a new machine, or after public bridge, DApp, Groth16, or Tokamak zk-EVM runtime artifacts are updated.

### Does this package publish private user data?

No. User wallets and channel workspaces are created locally under `~/tokamak-private-channels/`.
Bridge-facing commands still submit public transactions and proof-backed state transitions to the selected network.

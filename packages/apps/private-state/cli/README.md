# private-state CLI

Command-line client for the Tokamak private-state DApp.

## Install

```bash
npm install -g @tokamak-private-dapps/private-state-cli
```

Install the local Tokamak zk-EVM runtime workspace, Groth16 runtime workspace, and public private-state deployment
artifacts:

```bash
private-state-cli --install
```

By default, `--install` resolves the latest `@tokamak-zk-evm/cli` and `@tokamak-private-dapps/groth16` versions from
the npm registry. To pin exact proof backend versions for a channel, pass explicit versions:

```bash
private-state-cli --install --tokamak-zk-evm-cli-version 2.0.8 --groth16-cli-version 0.1.1
```

The Groth16 installer downloads the public Google Drive CRS archive with the same version as the selected Groth16 CLI.

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

A common private-state flow is:

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
`private-state-cli --install`, selected proof backend runtime versions, current dependency versions through `tokamak-l2js`, and Tokamak zk-EVM runtime
install mode, Docker mode, CUDA runtime metadata, live `nvidia-smi` and Docker GPU probe results, and Groth16
runtime health. The doctor check fails when the Tokamak Docker `useGpus` metadata does not match the live GPU probes.

Local helper commands:

```bash
private-state-cli list-local-wallets --network sepolia --channel-name cuda
private-state-cli get-my-wallet-meta --wallet <WALLET_NAME> --password <PASSWORD> --network sepolia
private-state-cli get-my-l1-address --private-key <HEX>
```

`list-local-wallets` reads only the local workspace and prints saved wallet names that can be reused with `--wallet`.
`get-my-wallet-meta` opens an encrypted local wallet and reports the stored L1/L2 identity metadata plus the current
on-chain channel registration match state. `get-my-l1-address` is a simple offline helper that derives the L1 address
for a private key.

## Workspace

The CLI stores user workspaces under:

```text
~/tokamak-private-channels/workspace/<network>/<channel>/
```

Wallet data is encrypted with the password supplied to `join-channel` or `recover-wallet`.

## LLM Agent Guidance

You may act as an interactive guide for users who do not understand this CLI or the private-state DApp. Assume the
user only knows that the DApp is a way to send funds privately. Translate the user's intent into safe, step-by-step CLI
actions.

Primary goal: help the user privately send funds by guiding them through the required private-state CLI commands,
explaining each step only as much as needed to proceed safely.

Operating rules:

- Do not ask the user to reveal raw private keys in chat. Use environment variable placeholders such as `$ADDR6`,
  `$CREATOR`, or `$PRIVATE_STATE_TEST_PK`.
- Prefer testnet examples unless the user explicitly asks for mainnet.
- Before any proof-backed or bridge-facing workflow, ask the user to run `private-state-cli --doctor` and inspect
  whether the runtime, Docker mode, CUDA/GPU probes, Groth16 runtime, and deployment artifacts are healthy.
- Use `private-state-cli list-local-wallets` to discover local wallet names instead of asking the user to inspect
  filesystem paths manually.
- Use `private-state-cli get-my-l1-address --private-key "$KEY_ENV"` to derive the L1 address for a private-key
  environment variable when wallet ownership needs to be identified.
- Use `private-state-cli get-my-wallet-meta --wallet <WALLET> --password <PASSWORD> --network <NETWORK>` to inspect
  local wallet metadata and on-chain channel registration state.
- Use `private-state-cli get-my-bridge-fund` and `private-state-cli get-my-channel-fund` to check balances before
  telling the user to move funds.
- Explain that wallet names are local CLI identifiers, while private transfers use notes owned by L2 addresses
  registered in the channel.
- Do not present one fixed command sequence as universally correct. Some flows start from an existing channel or wallet,
  while others require creating or joining a channel first.
- When the user asks for a transfer, first determine whether the sender has minted notes available. If not, guide them
  through funding the bridge, joining or recovering the channel wallet, depositing into the channel, and minting notes.
- When generating commands, use placeholders for secrets and explicit values for public fields. Show one command at a
  time unless the user asks for a batch.

Suggested interaction flow:

1. Identify the target network, usually `sepolia` for testing.
2. Identify whether a channel already exists.
3. Identify the sender and recipient wallets or private-key environment variables.
4. Run `--doctor`.
5. Run `list-local-wallets` and relevant metadata or balance checks.
6. If needed, guide the user through `create-channel`, `deposit-bridge`, `join-channel`, `deposit-channel`, and
   `mint-notes`.
7. For a private transfer, select available note IDs from `get-my-notes`, find the recipient L2 address from
   `get-my-wallet-meta`, then build `transfer-notes`.
8. After transfer, guide the recipient to run `get-my-notes` to recover received notes from event logs.

Example style: if the user says, "ADDR6 sends 10 tokens privately to ADDR8", do not assume the required note exists.
First ask or check which channel and network to use, whether ADDR6 and ADDR8 are already joined, what the local wallet
names are, and whether ADDR6 has an unused note worth exactly 10 or notes that sum to 10. Then provide the next concrete
command.

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
It does not install bridge contracts, app contracts, or local deployment outputs. The `private-state-cli --install`
command provisions the local Tokamak zk-EVM and Groth16 runtime workspaces used by proof-backed commands.

### When should I run `private-state-cli --install`?

Run it once on a new machine, or after public bridge, DApp, Groth16, or Tokamak zk-EVM runtime artifacts are updated.

### Does this package publish private user data?

No. User wallets and channel workspaces are created locally under `~/tokamak-private-channels/`.
Bridge-facing commands still submit public transactions and proof-backed state transitions to the selected network.

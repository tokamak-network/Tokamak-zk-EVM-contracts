# private-state CLI

Command-line client for the Tokamak private-state DApp.

The full private-state DApp documentation is published with the repository:

- https://github.com/tokamak-network/Tokamak-zk-EVM-contracts/tree/main/packages/apps/private-state/docs

## Tokamak-Operated Mainnet Channels

The table below lists private-state mainnet channels directly opened by Tokamak Network. Dates are
UTC.

| Channel name | Channel creator / leader | Created at | Genesis block | Channel manager |
| --- | --- | --- | ---: | --- |
| `the-great-first-channel` | [`0x32e6EE3d9820F0843E3e596132368747d36425F0`](https://etherscan.io/address/0x32e6EE3d9820F0843E3e596132368747d36425F0) | 2026-05-04 01:30:59 UTC | `25018368` | [`0x3108d92A38bFb4B3396DE7ad4D92318a8fbE61D7`](https://etherscan.io/address/0x3108d92A38bFb4B3396DE7ad4D92318a8fbE61D7) |

## Install

```bash
npm install -g @tokamak-private-dapps/private-state-cli
```

Install the local Tokamak zk-EVM runtime workspace, Groth16 runtime workspace, and public private-state deployment
artifacts:

```bash
private-state-cli install
```

By default, `install` resolves the latest `@tokamak-zk-evm/cli` from the npm registry and uses the bundled
`@tokamak-private-dapps/groth16` dependency version selected by the installed private-state CLI package. To pin exact
proof backend versions for a channel, pass explicit versions:

```bash
private-state-cli install --tokamak-zk-evm-cli-version 2.1.0 --groth16-cli-version 0.2.0
```

The Groth16 installer downloads the public Google Drive CRS archive whose major.minor compatibility version matches the
selected Groth16 CLI package version.
The Tokamak zk-EVM installer requires the selected CLI package to declare
`tokamakZkEvm.compatibleBackendVersion` as a canonical major.minor version matching the selected package version.

`install` downloads public deployment artifacts from the configured artifact index. It does not read repository-local
`deployment/` outputs by default. Repository development workflows that need local anvil artifacts can opt in explicitly:

```bash
private-state-cli install --include-local-artifacts
```

Run the CLI with:

```bash
private-state-cli <command> ...
```

Check the installed package and runtime state with:

```bash
private-state-cli help doctor
```

Print only the installed CLI package version with:

```bash
private-state-cli --version
```

Check npm registry for a newer CLI package and update a global npm install when possible:

```bash
private-state-cli help update
```

`update` keeps `--version` suitable for scripts by using a separate command for registry checks. If the CLI is running
from a repository checkout or npm does not report a global install, it does not edit local source files; it prints the
recommended `npm install -g @tokamak-private-dapps/private-state-cli@latest` command instead.

Remove all local private-state CLI data with:

```bash
private-state-cli uninstall
```

`uninstall` is intentionally interactive. It requires typing
`I understand that the wallet secrets deleted due to this decision cannot be recovered` before deleting
`~/tokamak-private-channels/`, the Tokamak zk-EVM runtime cache, and the global CLI npm package when npm reports that it
is globally installed.

## Commands

A common private-state flow is:

1. `channel create`
2. `account deposit-bridge`
3. `channel join`
4. `wallet deposit-channel`
5. `wallet mint-notes`
6. `wallet transfer-notes`
7. `wallet get-notes`
8. `wallet redeem-notes`
9. `wallet withdraw-channel`
10. `channel exit`
11. `account withdraw-bridge`

Use `private-state-cli help commands` for the full command list and required options. `private-state-cli --help`
continues to print the same command list for shell compatibility.

Workspace recovery commands use the saved recovery index by default. If the local workspace is missing, corrupted, or
does not contain a usable index, `channel recover-workspace` and `wallet recover-workspace` stop with an explicit error instead of
silently replaying logs from channel genesis. Use `--source rpc --from-genesis` only when you intentionally want to
rebuild channel workspace state from the channel creation block:

```bash
private-state-cli channel recover-workspace --channel-name <CHANNEL> --network mainnet --source rpc --from-genesis
private-state-cli wallet recover-workspace --channel-name <CHANNEL> --network mainnet --account <ACCOUNT> --from-genesis
```

`channel create` is the exception: after the channel is created on-chain, the CLI initializes that new local workspace
by replaying from the channel's genesis block because no prior recovery index can exist for a new channel.

`channel join` refreshes stale channel workspace state through the saved recovery index before submitting the
registration transaction. For a channel that was created elsewhere, run `channel recover-workspace --source rpc --from-genesis`
once before joining, or recover from a registered workspace mirror; later joins and wallet commands resume from the
saved index instead of silently replaying from genesis.

Wallet getter commands that need channel state, including `wallet get-meta`, `wallet get-channel-fund`, and
`wallet get-notes`, refresh stale local workspaces through saved recovery indexes before reading state. `wallet get-notes`
also refreshes received-note logs through the saved wallet note recovery index. Automatic refresh never replays from
channel genesis and only runs when the recovery delta fits within the 7,200-block pre-command budget. If a saved index
is missing, unusable, or too far behind, the command stops and asks the user to run the appropriate recovery command
with `--from-genesis` explicitly when needed.

Channel leaders can optionally register a workspace mirror server so users can bootstrap recovery
from a signed checkpoint and download only the local-to-checkpoint delta when a local recovery index
already exists. The channel leader can build the static mirror files with
`channel publish-workspace-mirror` and then deploy the output directory to the registered mirror
host. If the existing mirror manifest is unreadable or invalid, the leader can use
`channel publish-workspace-mirror --force` to write a full checkpoint without trusting that remote
manifest as a delta base. The CLI protocol is documented at
https://github.com/tokamak-network/Tokamak-zk-EVM-contracts/blob/main/packages/apps/private-state/docs/channel-workspace-mirror-protocol.md.

Back up a local wallet with:

```bash
private-state-cli wallet export --network mainnet --wallet <WALLET> --output ./wallet-backup.zip
```

The default export stores the encrypted wallet, wallet metadata, and wallet-local secret. The encrypted `wallet.json`
contains the wallet's current key material and tracked note state. The export intentionally excludes account secrets
because wallet commands restore the L1 signer from the encrypted `wallet.json`; account secrets are only needed for
account-level bridge-vault commands and optional `--tx-submitter` use. After importing a default export on a new machine,
run `channel recover-workspace` before using wallet commands that need channel state:

```bash
private-state-cli wallet import --input ./wallet-backup.zip
private-state-cli channel recover-workspace --channel-name <CHANNEL> --network mainnet --source rpc --from-genesis
```

For a wider backup that can run wallet commands immediately when the imported channel workspace cache is still
chain-aligned, add `--include-notes`:

```bash
private-state-cli wallet export --network mainnet --wallet <WALLET> --output ./wallet-backup.zip --include-notes
```

Use `--all` to export every local mainnet wallet into one ZIP:

```bash
private-state-cli wallet export --all --output ./mainnet-wallets.zip
```

Estimate live transaction costs before sending commands with:

```bash
private-state-cli help transaction-fees --network mainnet --rpc-url <RPC_URL>
```

`help transaction-fees` uses the measured gas data packaged in `assets/tx-fees.json`, the selected network's live fee data,
and live ETH/USD pricing to print an ETH/USD fee table for transaction-sending commands. The table separates typical
cost, based on the RPC `gasPrice`, from worst-case cost, based on `maxFeePerGas` when the network reports EIP-1559 fee
data.

Proof-backed note commands can use a separate L1 transaction submitter:

```bash
private-state-cli wallet mint-notes --wallet <WALLET> --network mainnet --amounts '[1]' --tx-submitter <ACCOUNT>
```

`--tx-submitter <ACCOUNT>` is available on `wallet mint-notes`, `wallet transfer-notes`, and `wallet redeem-notes`. The wallet still proves
note ownership and builds the ZK proof, but the selected local account submits `executeChannelTransaction` and pays gas.
Use this option when you want stronger privacy by avoiding a direct on-chain link between the note owner's wallet L1
account and the proof-submission transaction.

Channel policy warning:

- `channel create` commits to an immutable channel policy: verifier bindings, DApp execution metadata, function layout,
  managed storage vector, and refund policy are fixed for that channel.
- `channel join` means the user accepts the channel's current policy. Later policy-level fixes require a new channel or
  migration; the existing channel is intentionally not mutated in place without renewed user consent.
- Before sending a channel-creation transaction or a first channel-registration transaction, the CLI prints the policy
  snapshot that will be accepted: DApp metadata digest, digest schema, Groth16 verifier address, Groth16 compatible
  backend version, Tokamak verifier address, and Tokamak compatible backend version.
- Users and operators must review this snapshot before signing. If any digest, schema, verifier address, or compatible
  backend version is unexpected or has not been reviewed, do not create or join the channel. A later correction creates
  a new channel; it does not rewrite the policy of an already-created channel.

`private-state-cli help doctor` reports the CLI package version, dependency versions recorded by the last
`private-state-cli install`, selected proof backend runtime versions, current dependency versions through `tokamak-l2js`, and Tokamak zk-EVM runtime
install mode, Docker mode, CUDA runtime metadata, live `nvidia-smi` and Docker GPU probe results, and Groth16
runtime health. The doctor check fails when the Tokamak Docker `useGpus` metadata does not match the live GPU probes.

Local helper commands:

```bash
private-state-cli account import --account <ACCOUNT_NAME> --network sepolia --private-key-file <PATH>
private-state-cli account get-l1-address --account <ACCOUNT_NAME> --network sepolia
private-state-cli wallet list --network sepolia --channel-name cuda
private-state-cli wallet get-meta --wallet <WALLET_NAME> --network sepolia
private-state-cli wallet export --network sepolia --wallet <WALLET_NAME> --output ./wallet-backup.zip
private-state-cli wallet import --input ./wallet-backup.zip
```

`account import` is the only supported way to bring an L1 signing key into the CLI: it reads `--private-key-file` once
and stores a protected local account secret for later `--account` use. The source file does not need `0600` permissions.
`channel join` imports `--wallet-secret-path <PATH>` into the protected wallet-local default secret while creating the
encrypted local wallet. `wallet list` reads only the local workspace and prints saved wallet names that can be reused with
`--wallet`.
`wallet get-meta` opens an encrypted local wallet and reports the stored L1/L2 identity metadata plus the current
on-chain channel registration match state. `account get-l1-address` is a simple offline helper that derives the L1
address for a local account.

### Wallet Secret Source File

`channel join` needs a wallet secret source file because the CLI no longer accepts raw wallet secrets on the command
line. The source file is arbitrary high-entropy secret text that the CLI reads once and imports into the protected
wallet-local canonical secret.

Create one before joining a channel:

```bash
openssl rand -hex 32 > ./wallet-secret.txt
private-state-cli channel join --channel-name <CHANNEL> --network sepolia --account <ACCOUNT> --wallet-secret-path ./wallet-secret.txt
```

The import source file does not need `0600` permissions. The canonical wallet-local secret written by the CLI remains
protected: macOS/Linux uses `0600`, while Windows uses ACL repair and inspection when possible.

## Workspace

The CLI stores user workspaces under:

```text
~/tokamak-private-channels/workspace/<network>/<channel>/
```

Wallet data is encrypted with the wallet-local default secret file under
`~/tokamak-private-channels/secrets/<network>/wallets/<wallet>/secret`.

Bridge-facing commands accept optional `--rpc-url <URL>`. When `--rpc-url` is provided, the CLI stores it in
`~/tokamak-private-channels/secrets/<network>/.env` as `RPC_URL=<URL>` with protected canonical secret permissions.
When `--rpc-url` is omitted, the CLI reads `RPC_URL` from that file. The `anvil` network falls back to
`http://127.0.0.1:8545` when no saved RPC URL exists. Canonical CLI secrets are checked on read: macOS/Linux uses
`0600`, while Windows uses ACL repair and inspection when possible.

## LLM Agent Guidance

You may act as an interactive guide for users who do not understand this CLI or the private-state DApp. Assume the
user only knows that the DApp is a way to send funds privately. Translate the user's intent into safe, step-by-step CLI
actions.

Primary goal: help the user privately send funds by guiding them through the required private-state CLI commands,
explaining each step only as much as needed to proceed safely.

Operating rules:

- Do not ask the user to reveal raw private keys or wallet secrets in chat. Use `account import --private-key-file`
  once, then use `--account` for L1 signing commands. Wallet commands use wallet-local default secret files.
- Treat `private key file`, `account`, `wallet secret`, `wallet`, `network RPC URL`, and `channel policy` as
  new concepts unless the user has already demonstrated that they understand them. Define each term before using it
  in an instruction.
- Explain local-secret handling in plain language:
  - A private key file is a local file that contains the user's L1 wallet private key. The CLI reads it once during
    `account import` and stores a protected local account secret.
  - An account is the local nickname created by `account import`. After import, signing commands should use
    `--account <NAME>` instead of asking for the raw key again.
  - A wallet secret source file is a separate high-entropy local secret chosen by the user for this private-state
    wallet. It is not the L1 private key. `channel join` imports it once and uses it to protect and recover the
    channel-local wallet.
  - A wallet is the encrypted local private-state wallet created during `channel join`. Its deterministic name is
    `<channelName>-<l1Address>`.
  - The network RPC URL is the endpoint used to read and write chain state. It can be supplied once with `--rpc-url`
    on a bridge-facing command, after which the CLI saves it under the selected network.
  - A workspace recovery index is the saved block pointer and state-root hash that lets the CLI resume log scanning
    without replaying the channel from its creation block. If it is missing, explain `--from-genesis` before using it
    because genesis replay can take much longer.
- When the user does not have a network RPC URL yet, explain that they need an Ethereum JSON-RPC endpoint for the
  selected network. They can obtain one from an infrastructure provider such as Alchemy, Infura, QuickNode, or from
  their own node. Ask the user to create or select the endpoint in that provider's UI, then paste only the endpoint URL
  into the CLI command that accepts `--rpc-url`; do not ask for provider account passwords, API dashboards, seed phrases,
  private keys, or wallet secrets.
- When a user wants to join a channel, do not jump straight to `channel join`. Walk them through:
  1. choose the network and channel name
  2. run `private-state-cli install`
  3. run `private-state-cli help doctor`
  4. obtain or confirm a network RPC URL for the selected network
  5. prepare a private key source file locally, without pasting the key into chat
  6. run `account import --account <NAME> --network <NETWORK> --private-key-file <PATH>`
  7. prepare a wallet secret source file locally, for example with `openssl rand -hex 32 > ./wallet-secret.txt`
  8. inspect the channel with `channel get-meta` if it already exists, or create it with `channel create` if the user is
     the channel creator
  9. explain the immutable policy warning printed by the CLI
  10. run `channel join --channel-name <CHANNEL> --network <NETWORK> --account <ACCOUNT> --wallet-secret-path <PATH>`
- Before asking the user to create a file, explain what will be inside that file, who should be able to read it, and
  whether losing it prevents wallet recovery.
- Prefer testnet examples unless the user explicitly asks for mainnet.
- Before any proof-backed or bridge-facing workflow, ask the user to run `private-state-cli help doctor` and inspect
  whether the runtime, Docker mode, CUDA/GPU probes, Groth16 runtime, and deployment artifacts are healthy.
- Use `private-state-cli wallet list` to discover local wallet names instead of asking the user to inspect
  filesystem paths manually.
- Use `private-state-cli account get-l1-address --account <ACCOUNT> --network <NETWORK>` to derive the L1 address
  for a local account when wallet ownership needs to be identified.
- Use `private-state-cli wallet get-meta --wallet <WALLET> --network <NETWORK>` to inspect
  local wallet metadata and on-chain channel registration state.
- Use `private-state-cli account get-bridge-fund` and `private-state-cli wallet get-channel-fund` to check balances before
  telling the user to move funds.
- Explain that wallet names are local CLI identifiers, while private transfers use notes owned by L2 addresses
  registered in the channel.
- Explain `--tx-submitter <ACCOUNT>` when the user wants stronger privacy for `wallet mint-notes`, `wallet transfer-notes`, or
  `wallet redeem-notes`: the wallet owner still proves note ownership, but another imported local L1 account can submit the
  on-chain `executeChannelTransaction` and pay gas.
- Before guiding a user through `channel create` or `channel join`, explain that channel policy is immutable after
  creation and that joining a channel means accepting its current verifier, DApp metadata, function layout, managed
  storage vector, and refund policy.
- Do not present one fixed command sequence as universally correct. Some flows start from an existing channel or wallet,
  while others require creating or joining a channel first.
- When the user asks for a transfer, first determine whether the sender has minted notes available. If not, guide them
  through funding the bridge, joining or recovering the channel wallet, depositing into the channel, and minting notes.
- When generating commands, use placeholders for secrets and explicit values for public fields. Show one command at a
  time unless the user asks for a batch.

Suggested interaction flow:

1. Identify the target network, usually `sepolia` for testing.
2. Identify whether a channel already exists.
3. Identify the sender and recipient wallets or local account names.
4. Run `help doctor`.
5. Run `wallet list` and relevant metadata or balance checks.
6. If needed, guide the user through `channel create`, `account deposit-bridge`, `channel join`, `wallet deposit-channel`, and
   `wallet mint-notes`.
7. For a private transfer, select available note IDs from `wallet get-notes`, find the recipient L2 address from
   `wallet get-meta`, then build `wallet transfer-notes`.
8. After transfer, guide the recipient to run `wallet get-notes`; it refreshes received notes from the saved recovery index when the delta fits the 7,200-block pre-command budget. If the index is missing or too far behind, explain `wallet recover-workspace --from-genesis`.

Example onboarding explanation for `channel join`:

> First we need two different local secrets. Your L1 private key proves which Ethereum account pays gas and signs
> bridge transactions. We import it once into a local account nickname, so later commands can say `--account alice`
> instead of handling the raw key again. Separately, the wallet secret protects the encrypted private-state wallet for
> this channel. It is not sent on-chain and it is not the same as your L1 private key. If you lose the wallet secret,
> recovering this channel wallet can become impossible.

Example style: if the user says, "ADDR6 sends 10 tokens privately to ADDR8", do not assume the required note exists.
First ask or check which channel and network to use, whether ADDR6 and ADDR8 are already joined, what the local wallet
names are, and whether ADDR6 has an unused note worth exactly 10 or notes that sum to 10. Then provide the next concrete
command.

## Artifacts

Proof-backed commands require installed bridge, DApp, and Groth16 artifacts. Run `private-state-cli install` before
using bridge-facing commands on a new machine.

Channel balance commands such as `wallet deposit-channel` and `wallet withdraw-channel` use the installed Groth16 runtime workspace
directly. Proof generation writes to the fixed workspace paths under `~/tokamak-private-channels/groth16/proof`; the CLI
does not pass custom `--zkey`, proof-output, or public-output paths to the Groth16 prover.
Before proof generation, the CLI compares the target channel's verifier compatibility versions with the installed
Tokamak zk-EVM and Groth16 major.minor compatibility versions.

Release order matters for npm publication. `@tokamak-private-dapps/common-library` and
`@tokamak-private-dapps/groth16` must be published before this package version.

## FAQ

### What does this package install?

It installs the `private-state-cli` terminal command and the local files needed by that command.
It does not install bridge contracts, app contracts, or local deployment outputs. The `private-state-cli install`
command provisions the local Tokamak zk-EVM and Groth16 runtime workspaces used by proof-backed commands.

### When should I run `private-state-cli install`?

Run it once on a new machine, or after public bridge, DApp, Groth16, or Tokamak zk-EVM runtime artifacts are updated.

### Does this package publish private user data?

No. User wallets and channel workspaces are created locally under `~/tokamak-private-channels/`.
Bridge-facing commands still submit public transactions and proof-backed state transitions to the selected network.

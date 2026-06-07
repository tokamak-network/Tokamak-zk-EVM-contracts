# private-state CLI

Command-line client for the Tokamak private-state DApp.

The full private-state DApp documentation is published with the repository:

- https://github.com/tokamak-network/Tokamak-zk-EVM-contracts/tree/main/docs/dapps/private-state

## Terminology And Exchange Boundary

This npm README uses the same terminology as the repository README:

- `Tokamak Private App Channels`: Ethereum-settled, validity-proven execution domains for bridge-coupled DApps.
- `private-state DApp`: the current reference DApp that programs confidential application state inside a channel.
- `canonical Tokamak Network Token`: the L1 asset whose custody remains anchored on Ethereum.
- `self-custody L1 wallet`: a user-controlled L1 account, not an exchange deposit address.
- `L1-transparent bridge edge`: public bridge deposit and withdrawal transactions involving the canonical token.
- `channel-local accounting balance`: liquid application balance inside a channel before or after note use.
- `private-state note`: a channel-local application note, not an exchange-supported token or deposit asset.
- `proof-backed confidential application state`: DApp state advanced by accepted proof-backed channel transitions.
- `user-controlled selective disclosure`: optional user disclosure from local wallet state; Tokamak does not hold a master viewing key.
- `viewing key`: the note-receive private key used to decrypt note-delivery events for the registered note-receive public key.
- `spending key`: the channel-bound L2 private key used to authorize proof-backed note use.

Tokamak Private App Channels are not an exchange deposit network. Exchange-facing token transfers and bridge
entry or exit remain public L1 activity. Internal private-state note counterparty relationships and note provenance are
not public by default and are not reconstructed by Tokamak on a user's behalf.

## Address And Key-Safety Warnings

Do not use an exchange deposit address as a private-state wallet address. Private-state notes are not
supported exchange assets. Always withdraw TON to a self-custody L1 wallet before using a channel.

Bridge deposits and withdrawals are public L1 events. Internal note transfers are private by design and are not
automatically reconstructible by Tokamak, exchanges, or public observers.

This CLI does not send your spending key, wallet secret, or private note plaintext to Tokamak.

## Tokamak-Operated Mainnet Channels

The table below lists private-state mainnet channels directly opened by Tokamak Network. Dates are
UTC.

| Channel name | Channel creator / leader | Created at | Genesis block | Channel manager |
| --- | --- | --- | ---: | --- |
| `the-great-first-channel` | [`0x32e6EE3d9820F0843E3e596132368747d36425F0`](https://etherscan.io/address/0x32e6EE3d9820F0843E3e596132368747d36425F0) | 2026-05-04 01:30:59 UTC | `25018368` | [`0x3108d92A38bFb4B3396DE7ad4D92318a8fbE61D7`](https://etherscan.io/address/0x3108d92A38bFb4B3396DE7ad4D92318a8fbE61D7) |

## Install

### Prerequisites

Before installing this package, prepare the private-state CLI prerequisites:

- Node.js 18 or newer and npm for installing and running `private-state-cli`.
- Outbound HTTPS access to the npm registry, the public private-state deployment artifact index, and the public
  Groth16 CRS archive source.
- A writable home-directory workspace under `~/tokamak-private-channels/` for private-state artifacts, Groth16
  workspace files, account secrets, wallet key files, channel workspaces, and proof outputs.
- For `private-state-cli install --read-only`, no proof runtime prerequisites are needed because read-only mode installs
  only public bridge and private-state DApp artifacts.
- For `private-state-cli install --include-local-artifacts`, run the command from a repository or deployment workspace
  that contains the local `deployment/` artifacts you intentionally want to install.
- For `private-state-cli install --docker`, the private-state Groth16 Docker path requires Docker to be installed and
  running. The Groth16 Docker path is supported on Linux hosts and Windows hosts with Docker Desktop; macOS hosts should
  use the native Groth16 path.

Full `private-state-cli install` also installs and invokes `@tokamak-zk-evm/cli`. The operating-system, native build
toolchain, Docker, CUDA, and network prerequisites for the Tokamak zk-EVM CLI are intentionally not duplicated here.
Read the [`@tokamak-zk-evm/cli` README](https://github.com/tokamak-network/Tokamak-zk-EVM/tree/main/packages/cli#readme)
before running full install, especially when using `--docker` or a GPU-enabled host.

```bash
npm install -g @tokamak-private-dapps/private-state-cli
```

Install the full local Tokamak zk-EVM runtime workspace, Groth16 runtime workspace, and public private-state deployment
artifacts needed by transaction-sending channel commands:

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

For read-only channel recovery, channel metadata lookup, wallet recovery, wallet metadata lookup, bridge balance
lookup, bridge deposit, bridge withdrawal, and local helper commands, install only the read-only artifact subset:

```bash
private-state-cli install --read-only
```

Read-only install materializes only `bridge.<chainId>.json`, `bridge-abi-manifest.<chainId>.json`,
`deployment.<chainId>.latest.json`, and `storage-layout.<chainId>.latest.json`. It does not install the Tokamak
zk-EVM runtime, Groth16 runtime, Groth16 zkey, callable DApp ABI, or DApp registration artifact, so commands that
create or mutate channel state require a later full `private-state-cli install`.

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
`~/tokamak-private-channels/`, including local account secrets and wallet key files, the Tokamak zk-EVM runtime cache,
and the global CLI npm package when npm reports that it is globally installed.

## Commands

A common note-use flow after channel policy review is:

1. `channel create`
2. `channel join`
3. `account deposit-bridge`
4. `wallet deposit-channel`
5. `wallet mint-notes`
6. `wallet transfer-notes`
7. `wallet get-notes`
8. `wallet redeem-notes`
9. `wallet withdraw-channel`
10. `channel exit`
11. `account withdraw-bridge`

`channel join` pays any join toll directly from the L1 wallet; `account deposit-bridge` funds later channel liquidity and does not pay the join toll.

Use `private-state-cli help commands` for the full command list and required options. `private-state-cli --help`
continues to print the same command list for shell compatibility. Add `--json` to either form to print the command
reference as structured JSON on stdout.

### Action-impact acknowledgement

Transaction-sending bridge, channel, and note commands require `--acknowledge-action-impact`. Before submitting any
transaction, the CLI prints a static action-impact summary covering whether the command emits public L1 events, whether
it changes private-state note state, which addresses or amounts become public, which note facts are not public by default,
illegal-use prohibition, secret-recovery limits, and channel policy acceptance. In non-interactive contexts, such as
scripts and LLM-assisted execution, the command fails unless the flag is present.

Static warning scope:

| Command | Public surface | Private-state note state | Not public by default |
|---|---|---|---|
| `account deposit-bridge` | L1 account, bridge vault, amount, approval/funding txs | No note change | No note plaintext or provenance is created |
| `account withdraw-bridge` | L1 recipient/account, bridge vault, amount, withdrawal tx | No note change | Prior private-state note path is not reconstructed |
| `channel join` | L1 account, L2 address, note-receive public key, join toll, channel id | No note change | Wallet secret, spending key, viewing key, and note plaintext |
| `wallet deposit-channel` | L1 submitter, registered L2 address, amount, channel id, accounting update | No note change | No note provenance is created |
| `wallet mint-notes` | L1 submitter, registered L2 address, commitments, encrypted note events, root update | Creates notes | Note owner, value, salt, and later provenance |
| `wallet transfer-notes` | L1 submitter, input nullifiers, output commitments, encrypted note events, root update | Spends and creates notes | Sender-recipient relationship, note plaintext, and provenance |
| `wallet redeem-notes` | L1 submitter, input nullifier, accounting update, root update | Consumes notes | Prior path by which the note was received |
| `wallet withdraw-channel` | L1 submitter, registered L2 address, amount, channel id, accounting update | No direct note spend | Prior private-state note path behind the liquid balance |

`account deposit-bridge` and `account withdraw-bridge` also print an exchange-controlled address warning. Do not use an
exchange-controlled address as a self-custody bridge source or as the direct bridge withdrawal target
unless the user explicitly understands the compliance implications. Prefer a self-custody L1 wallet.

Workspace recovery commands use saved recovery indexes by default. If the local channel workspace is missing,
corrupted, or does not contain a usable index, `channel recover-workspace` stops with an explicit error instead of
silently replaying logs from channel genesis. When the channel has a registered workspace mirror, recover from the
mirror first:

```bash
private-state-cli channel recover-workspace --channel-name <CHANNEL> --network mainnet --source mirror
```

Use `channel recover-workspace --source rpc --from-genesis` only when no compatible workspace mirror is available and
you intentionally want to rebuild channel workspace state from the channel creation block:

```bash
private-state-cli channel recover-workspace --channel-name <CHANNEL> --network mainnet --source rpc --from-genesis
```

When `channel recover-workspace --from-genesis` is used, the CLI treats the local channel workspace as a clean rebuild target.
If `~/tokamak-private-channels/workspace/<network>/<channel>` already exists, it is moved under
`~/tokamak-private-channels/workspace-rebuild-backups/` before the current-format workspace is
created. This backup step is workspace-only; files under `~/tokamak-private-channels/secrets/`,
including account private keys and wallet viewing/spending key files, are not removed.
During RPC recovery, the CLI writes a usable channel workspace checkpoint after each RPC log chunk. If an RPC recovery
run is interrupted, the next non-`--from-genesis` RPC recovery resumes from the last completed chunk. Mirror recovery
can also start from that local checkpoint: it uses a matching delta bundle when one is available, otherwise a newer
verified full mirror checkpoint replaces the local checkpoint before RPC catch-up.

Use `channel recover-workspace --source rpc --output-raw` when you need to preserve the raw JSON-RPC request and
response history for inspection. The CLI appends calls to method-specific JSON files, and splits `eth_getLogs` into
event-specific files such as `eth_getLogs.CurrentRootVectorObserved.json`, under
`~/tokamak-private-channels/workspace/<network>/<channel>/channel/rpcCallHistory/`. Indexed recovery appends to the
existing history, while `--from-genesis` overwrites it with one full genesis-to-latest scan.

`channel create` is the exception: after the channel is created on-chain, the CLI initializes that new local workspace
by replaying from the channel's genesis block because no prior recovery index can exist for a new channel.

`channel join` refreshes stale channel workspace state through the saved recovery index before submitting the
registration transaction. For a channel that was created elsewhere, recover from a registered workspace mirror first.
Use `channel recover-workspace --source rpc --from-genesis` only when no compatible mirror is available; later joins
and wallet commands resume from the saved index instead of silently replaying from genesis.

Wallet commands that need channel state, including `wallet recover-workspace`, `wallet get-meta`,
`wallet get-channel-fund`, and `wallet get-notes`, refresh stale local channel workspaces through saved recovery
indexes before reading state. `wallet get-notes` and `wallet recover-workspace` also refresh received-note logs
through the saved wallet note recovery index. Wallet note freshness is measured against the fresh channel workspace
frontier, not the provider's latest L1 block, so unrelated new L1 blocks do not make a wallet stale by themselves.
Automatic refresh never replays from channel genesis and only runs when the recovery delta fits within the 7,200-block
pre-command budget. If a saved index is missing, unusable, or too far behind, the command stops and asks the user to
run the appropriate recovery command first.

Wallet note-delivery recovery checkpoints after each RPC log chunk by updating
`noteReceiveLastScannedBlock`. If an ordinary `wallet recover-workspace` run is interrupted during note recovery, the
next run resumes from the last completed chunk. This does not add a special resume path for
`wallet recover-workspace --from-genesis`; that command intentionally starts received-note scanning from channel
genesis after the channel workspace has passed the same freshness preflight used by other wallet commands.

Local wallet workspaces are epoch-aware. Each successful channel registration creates a wallet epoch under the
canonical wallet directory. `channel exit` does not delete the local wallet workspace; it marks the active epoch as
exited with the exit transaction, block, and timestamp, then keeps that epoch read-only for historical note inspection
and evidence export. If the same account later joins the same channel again, the new registration is a separate active
epoch under the same canonical wallet name.

The current CLI only supports this epoch-aware wallet workspace layout. If a local wallet directory was created by an
older CLI and does not contain `wallet-index.metadata.json` plus `epochs/<epoch-id>/` metadata files, rebuild it with
`wallet recover-workspace` before using wallet commands.

Channel leaders can optionally register a workspace mirror server so users can bootstrap recovery
from a signed checkpoint and download only the local-to-checkpoint delta when a local recovery index
already exists. The channel leader can build the static mirror files with
`channel recover-workspace --publish-workspace-mirror --leader-account <ACCOUNT> --output <PATH>` after
recovering the channel workspace, and then deploy the output directory to the registered mirror host.
If the existing mirror manifest is unreadable or invalid, add `--force` to write a full checkpoint
without trusting that remote manifest as a delta base. The CLI protocol is documented at
https://github.com/tokamak-network/Tokamak-zk-EVM-contracts/blob/main/docs/dapps/private-state/channel-workspace-mirror-protocol.md.

Back up a local wallet with:

```bash
private-state-cli wallet export backup --network mainnet --wallet <WALLET> --output ./wallet-backup.zip
```

The backup export stores note-tracking metadata and the channel workspace cache, but it does not include spending keys,
viewing keys, key derivation material, or plaintext note secrets. Note records in the backup keep commitments,
nullifiers, and encrypted note payloads only; `owner`, `value`, and `salt` are excluded.
Importing this backup restores encrypted tracking state and channel cache files, not wallet authority.

```bash
private-state-cli wallet import backup --input ./wallet-backup.zip
```

Export viewing and spending authority separately:

```bash
private-state-cli wallet export viewing-key --network mainnet --wallet <WALLET> --output ./wallet-viewing.key
private-state-cli wallet export spending-key --network mainnet --wallet <WALLET> --output ./wallet-spending.key
```

Import those capabilities only when the target machine should receive them:

```bash
private-state-cli wallet import viewing-key --input ./wallet-viewing.key
private-state-cli wallet import spending-key --input ./wallet-spending.key
```

A backup plus a viewing key can reconstruct the wallet's readable note view from encrypted events, but it still cannot
spend notes. A backup plus a spending key is still missing event-log decryption authority. A normal operational restore
imports the backup, the viewing key, and the spending key, and still needs the relevant local L1 account secret for
commands that submit bridge or channel-registration transactions.

Export a local full-note evidence bundle with:

```bash
private-state-cli wallet get-notes --network mainnet --wallet <WALLET> --export-evidence ./wallet-evidence.zip --acknowledge-full-note-plaintext-export
```

This ZIP is an input for `private-state-cli investigator`. It contains plaintext for all locally known
notes, derived commitments and nullifiers, creation and spend transaction references, transaction calldata, receipts,
events, and indexes for filtering by note, nullifier, transaction, block range, or available counterparty metadata. It
includes all local epochs for the selected wallet, including exited epochs retained after `channel exit`. It does not
include viewing keys, spending keys, wallet secret material, account private keys, or `.key` files. Do not submit the
raw ZIP as an exchange or auditor package unless full wallet-history disclosure is intended.

Open the local evidence investigator with:

```bash
private-state-cli investigator
```

The command prints the bundled investigator HTML path and file URL, then opens the static browser GUI. Load the raw
evidence ZIP in that GUI, choose the disclosure request type, inspect the interactive note-linkage graph, and export a
narrower user-consent disclosure ZIP. The graph view renders every matched note as a node and shows creation, spend,
and local note-to-note linkage edges when the raw bundle contains enough local evidence. The GUI can also export a
Markdown ASCII-art linkage report with a compact graph section and per-note detail sections. The GUI runs locally in the
browser and does not send files over the network.

The investigator accepts current epoch-aware evidence bundles only. If a bundle was generated by an older CLI, rebuild
the wallet workspace with `wallet recover-workspace` and export a new bundle with `wallet get-notes --export-evidence`.

Estimate live transaction costs before sending commands with:

```bash
private-state-cli help transaction-fees --network mainnet
```

`help transaction-fees` uses the measured gas data packaged in `assets/tx-fees.json`, the selected network's live fee data,
and live ETH/USD pricing to print an ETH/USD fee table for transaction-sending commands. The table separates typical
cost, based on the RPC `gasPrice`, from worst-case cost, based on `maxFeePerGas` when the network reports EIP-1559 fee
data. AI agents answering user questions about gas, transaction fees, transaction cost, or USD cost should run
`private-state-cli help transaction-fees --network <NETWORK> --json` and answer from the returned table.

Proof-backed note commands can use a separate L1 transaction submitter:

```bash
private-state-cli wallet mint-notes --wallet <WALLET> --network mainnet --amounts '[1]' --acknowledge-action-impact --tx-submitter <ACCOUNT>
```

`--tx-submitter <ACCOUNT>` is available on `wallet mint-notes`, `wallet transfer-notes`, and `wallet redeem-notes`. The wallet still proves
note ownership and builds the ZK proof, but the selected local account submits `executeChannelTransaction` and pays gas.
Use this option when a separate imported local account should submit the L1 transaction and pay gas for a proof-backed
note command.

`wallet transfer-notes` takes JSON arrays for note selection and outputs. `--note-ids` is a JSON array of input note
commitment IDs from `wallet get-notes`; `--recipients` is a JSON array of recipient L2 addresses; `--amounts` is a JSON
array of token amounts. Quote decimal amounts to avoid shell or JSON ambiguity. The recipient count must match the
amount count, only `1->1`, `1->2`, and `2->1` transfer shapes are supported, and the output amount sum must equal the
selected input note value sum.

```bash
private-state-cli wallet transfer-notes \
  --wallet <WALLET> \
  --network mainnet \
  --note-ids '["0xNOTE1","0xNOTE2"]' \
  --recipients '["0xL2RECIPIENT1","0xL2RECIPIENT2"]' \
  --amounts '["1.5","2"]' \
  --acknowledge-action-impact \
  --tx-submitter <ACCOUNT>
```

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
`private-state-cli install`, selected proof backend runtime versions when full mode was installed, current dependency
versions through `tokamak-l2js`, Tokamak zk-EVM runtime install mode, Docker mode, CUDA runtime metadata, live
`nvidia-smi` and Docker GPU probe results, Groth16 runtime health, deployment artifact readiness, and per-command
availability. In read-only install mode, proof runtime checks are skipped and proof-backed or channel-mutating
commands are reported unavailable until full install is completed.

Local helper commands:

```bash
private-state-cli secret create-private-key-source --output ./ethereum-private-key.txt
private-state-cli account import --account <ACCOUNT_NAME> --network mainnet --private-key-file ./ethereum-private-key.txt
private-state-cli account get-l1-address --account <ACCOUNT_NAME> --network mainnet
private-state-cli secret create-wallet-secret-source --output ./wallet-secret.txt
private-state-cli wallet list --network mainnet --channel-name <CHANNEL>
private-state-cli wallet get-meta --wallet <WALLET_NAME> --network mainnet
private-state-cli wallet export backup --network mainnet --wallet <WALLET_NAME> --output ./wallet-backup.zip
private-state-cli wallet import backup --input ./wallet-backup.zip
```

`secret create-private-key-source` prompts in the terminal with masked input and creates a local source file for
`account import`. `account import` is the only supported way to bring an Ethereum signing key into the CLI: it reads
`--private-key-file` once and stores a protected local account secret for later `--account` use. The source file does
not need `0600` permissions. `secret create-wallet-secret-source` prompts in the terminal with masked input by default
and creates a local wallet secret source file for `channel join`. Use `--random` only when a random wallet secret is
explicitly wanted. `channel join` reads `--wallet-secret-path <PATH>` once while creating the channel-bound spending key and then stores
wallet backup metadata, viewing-key metadata, and spending-key metadata as separate files. `wallet list` reads only the local workspace and prints saved wallet names that can be reused with
`--wallet`.
`wallet get-meta` opens the wallet metadata and reports the stored L1/L2 identity metadata plus the current
on-chain channel registration match state, including the registered note-receive public key when present. On
epoch-aware wallet workspaces it also reports the selected wallet epoch and whether that epoch is active or exited.
`account get-l1-address` is a simple offline helper that derives the L1 address for a local account.

### Wallet Secret Source File

`channel join` needs a wallet secret source file because the CLI no longer accepts raw wallet secrets on the command
line. The source file is secret text that the CLI reads once for channel-bound spending-key derivation. It is not
persisted in the wallet workspace.

Create one before joining a channel:

```bash
private-state-cli secret create-wallet-secret-source --output ./wallet-secret.txt
private-state-cli channel join --channel-name <CHANNEL> --network mainnet --account <ACCOUNT> --wallet-secret-path ./wallet-secret.txt --acknowledge-action-impact
```

The default helper flow lets the user type a wallet secret so it can be retained more easily. If random generation is
explicitly wanted, run `private-state-cli secret create-wallet-secret-source --output ./wallet-secret.txt --random`.

The import source file does not need `0600` permissions. The CLI does not persist a wallet-local secret:
it reads the source once for channel-bound L2 spending-key derivation. The join flow stores the viewing key and
spending key as separate protected key files under the CLI secret root; macOS/Linux uses `0600`, while Windows uses ACL
repair and inspection when possible.

Keep the wallet secret source separately backed up if you expect to rederive the spending key later. The viewing key can
be rederived from the same L1 private key and channel context because it comes from the note-receive typed-data signing
flow. The spending key needs the same L1 private key, the same channel context, and the same wallet secret source. If the
spending-key file is lost and the wallet secret source is also lost, the CLI cannot reconstruct the spending key and the
notes for that wallet cannot be spent, transferred, or redeemed through the normal note flow.

`wallet recover-workspace` restores the viewing key by default. Add `--wallet-secret-path <PATH>` only when the
account is currently active in the channel and you need to rederive the spending key. In that mode, the CLI checks the
derived L2 address and channel token-vault storage key against the current on-chain registration before received-note
recovery starts, then stores the protected spending-key file. Exited or non-active accounts must be recovered without
`--wallet-secret-path`; that restores viewing/evidence history but not spending authority. The wallet secret source is
read for derivation and is not stored.

### Wallet Backup, Viewing, And Spending Authority

The wallet workspace is split so that a backup is not a full-control wallet export. Backup metadata stores the
recoverable local view of the channel: commitments, nullifiers, encrypted note-delivery payloads, scan checkpoints,
operation history, and the channel workspace cache. It deliberately omits plaintext note fields and key material.

The viewing key is the note-receive private key. It lets `wallet get-notes` decrypt bridge-propagated encrypted
note-delivery events and rebuild the user's readable note view. Sharing it gives read access to notes addressed to the
registered note-receive public key, but not spending authority.

The spending key is the channel-bound L2 private key. It authorizes proof-backed use of the wallet identity. Commands
that create or consume notes, such as `wallet mint-notes`, `wallet transfer-notes`, and `wallet redeem-notes`, need both
the viewing key and the spending key because the CLI refreshes the readable note workspace after accepted note
transactions and then proves authorized note use when inputs are consumed.

Key recovery is intentionally split. Recreating the viewing key requires the original L1 private key and the same channel
context. Recreating the spending key requires the original L1 private key, the same channel context, and the same wallet
secret source used at `channel join`. `wallet recover-workspace --wallet-secret-path <PATH>` performs this spending-key
rederivation only for active channel registrations. Importing `wallet-viewing.key` or `wallet-spending.key` restores the
corresponding capability without rerunning derivation, but a backup ZIP alone never restores either capability.

`wallet get-notes --export-evidence <PATH> --acknowledge-full-note-plaintext-export` writes a local raw evidence ZIP.
The bundle is not a key export. It includes plaintext note facts for locally known notes so that
`private-state-cli investigator` can create narrower consent-disclosure packages without requiring viewing-key or
spending-key sharing.

## Workspace

The CLI stores user workspaces under:

```text
~/tokamak-private-channels/workspace/<network>/<channel>/
```

Wallet backup metadata lives under the channel workspace. Viewing and spending private keys live as separate protected
key files under `~/tokamak-private-channels/secrets/<network>/wallets/<wallet>/`.

Configure the network RPC endpoint before bridge-facing or wallet recovery commands:

```bash
private-state-cli set rpc --network mainnet --rpc-url <RPC_URL> --provider alchemy
```

The CLI writes `~/tokamak-private-channels/workspace/<network>/rpc-config.env` and later commands read `RPC_URL`,
`LOG_CHUNK_SIZE`, `LOG_REQUESTS_PER_SECOND`, and `RPC_BLOCK_RANGE_CAP` from that file. Built-in provider limits are
set to 90% of the provider reference values: Ankr `27 calls/s, 3000 blocks`; Chainstack `22.5 calls/s, 100 blocks`;
Chainnodes `22.5 calls/s, 20000 blocks`; QuickNode `13.5 calls/s, 5 blocks`; Alchemy `7.497 calls/s, 10 blocks`.
If the provider is not listed, use
`--log-requests-per-second <N>` and `--block-range-cap <N>` instead of `--provider`.

### Slow Workspace Recovery

`channel recover-workspace` and `wallet recover-workspace` scan on-chain logs with `eth_getLogs`. If recovery is
unexpectedly slow, first check the RPC scan limits saved by `set rpc`. The main speed factors are the provider's
`eth_getLogs` block range cap and the allowed log request rate. A small block range cap can turn the same channel scan
into thousands of RPC calls.

For example, an Alchemy free-tier-style cap of `10` blocks is much slower for long recovery scans than Ankr's built-in
`3000` block setting or Chainnodes' built-in `20000` block setting. When recovery is too slow, re-run `set rpc` with a
provider that supports a larger `eth_getLogs` block range cap, or provide explicit values:

```bash
private-state-cli set rpc --network mainnet --rpc-url <RPC_URL> --provider ankr
private-state-cli set rpc --network mainnet --rpc-url <RPC_URL> --log-requests-per-second <N> --block-range-cap <N>
```

If an RPC provider rejects the configured range or rate during recovery, run `set rpc` again with limits that match the
provider's documented `eth_getLogs` policy, then retry the recovery command.

Canonical CLI secrets are checked on read: macOS/Linux uses `0600`, while Windows uses ACL repair and inspection when
possible.

## LLM Agent Guidance

LLM agents that guide users through this CLI should read [`agents.md`](agents.md) before suggesting or running
commands. That file contains the agent-specific operating rules, including secret-handling boundaries, onboarding
sequence, acknowledgement handling, recovery behavior, and error-response policy.

When `--json` is used, the CLI follows one output contract for all commands:

- the final success result is one JSON object on stdout
- command failures are one JSON object on stdout with `ok: false`
- progress, warning, and informational events are JSON Lines on stderr
- human-readable mode remains the default when `--json` is omitted

Agents should parse stdout for the final result and may stream stderr JSONL events to explain progress to the user.

## Artifacts

Proof-backed and channel-mutating commands require full installed bridge, DApp, and Groth16 artifacts. Run
`private-state-cli install` before creating, joining, exiting, or mutating channels on a new machine. Channel-state read
commands and commands unrelated to channel state can run after `private-state-cli install --read-only`.

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
command defaults to full mode, which provisions local Tokamak zk-EVM and Groth16 runtime workspaces used by
proof-backed commands. `private-state-cli install --read-only` installs only the public bridge and private-state DApp
artifacts needed by channel-state read commands and commands that do not depend on channel state.

### When should I run `private-state-cli install`?

Run full install once on a machine that will create, join, exit, or mutate channels. Run read-only install on a machine
that only needs channel recovery, wallet recovery, metadata lookup, bridge balance lookup, bridge deposit or withdrawal,
and local import/export/helper commands. Re-run the relevant mode after public bridge, DApp, Groth16, or Tokamak zk-EVM
runtime artifacts are updated.

### Does this package publish private user data?

No. User wallets and channel workspaces are created locally under `~/tokamak-private-channels/`.
Bridge-facing commands still submit public transactions and proof-backed state transitions to the selected network.
For the current `private-state` DApp, commitments, nullifiers, and encrypted note-delivery events are
part of the DApp-programmed public disclosure surface, while note plaintext, note ownership, and note
provenance remain controlled by user-held secrets and implemented wallet tooling.

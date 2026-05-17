# private-state CLI

Command-line client for the Tokamak private-state DApp.

The full private-state DApp documentation is published with the repository:

- https://github.com/tokamak-network/Tokamak-zk-EVM-contracts/tree/main/packages/apps/private-state/docs

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
`~/tokamak-private-channels/`, including local account secrets and wallet key files, the Tokamak zk-EVM runtime cache,
and the global CLI npm package when npm reports that it is globally installed.

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
silently replaying logs from channel genesis. Use `channel recover-workspace --source rpc --from-genesis` only when
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

`channel create` is the exception: after the channel is created on-chain, the CLI initializes that new local workspace
by replaying from the channel's genesis block because no prior recovery index can exist for a new channel.

`channel join` refreshes stale channel workspace state through the saved recovery index before submitting the
registration transaction. For a channel that was created elsewhere, run `channel recover-workspace --source rpc --from-genesis`
once before joining, or recover from a registered workspace mirror; later joins and wallet commands resume from the
saved index instead of silently replaying from genesis.

Wallet commands that need channel state, including `wallet recover-workspace`, `wallet get-meta`,
`wallet get-channel-fund`, and `wallet get-notes`, refresh stale local channel workspaces through saved recovery
indexes before reading state. `wallet get-notes` and `wallet recover-workspace` also refresh received-note logs
through the saved wallet note recovery index. Automatic refresh never replays from channel genesis and only runs when
the recovery delta fits within the 7,200-block pre-command budget. If a saved index is missing, unusable, or too far
behind, the command stops and asks the user to run the appropriate recovery command first.

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
`channel publish-workspace-mirror` and then deploy the output directory to the registered mirror
host. If the existing mirror manifest is unreadable or invalid, the leader can use
`channel publish-workspace-mirror --force` to write a full checkpoint without trusting that remote
manifest as a delta base. The CLI protocol is documented at
https://github.com/tokamak-network/Tokamak-zk-EVM-contracts/blob/main/packages/apps/private-state/docs/channel-workspace-mirror-protocol.md.

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
data.

Proof-backed note commands can use a separate L1 transaction submitter:

```bash
private-state-cli wallet mint-notes --wallet <WALLET> --network mainnet --amounts '[1]' --acknowledge-action-impact --tx-submitter <ACCOUNT>
```

`--tx-submitter <ACCOUNT>` is available on `wallet mint-notes`, `wallet transfer-notes`, and `wallet redeem-notes`. The wallet still proves
note ownership and builds the ZK proof, but the selected local account submits `executeChannelTransaction` and pays gas.
Use this option when a separate imported local account should submit the L1 transaction and pay gas for a proof-backed
note command.

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
private-state-cli wallet export backup --network sepolia --wallet <WALLET_NAME> --output ./wallet-backup.zip
private-state-cli wallet import backup --input ./wallet-backup.zip
```

`account import` is the only supported way to bring an L1 signing key into the CLI: it reads `--private-key-file` once
and stores a protected local account secret for later `--account` use. The source file does not need `0600` permissions.
`channel join` reads `--wallet-secret-path <PATH>` once while creating the channel-bound spending key and then stores
wallet backup metadata, viewing-key metadata, and spending-key metadata as separate files. `wallet list` reads only the local workspace and prints saved wallet names that can be reused with
`--wallet`.
`wallet get-meta` opens the wallet metadata and reports the stored L1/L2 identity metadata plus the current
on-chain channel registration match state, including the registered note-receive public key when present. On
epoch-aware wallet workspaces it also reports the selected wallet epoch and whether that epoch is active or exited.
`account get-l1-address` is a simple offline helper that derives the L1 address for a local account.

### Wallet Secret Source File

`channel join` needs a wallet secret source file because the CLI no longer accepts raw wallet secrets on the command
line. The source file is arbitrary high-entropy secret text that the CLI reads once for channel-bound spending-key
derivation. It is not persisted in the wallet workspace.

Create one before joining a channel:

```bash
openssl rand -hex 32 > ./wallet-secret.txt
private-state-cli channel join --channel-name <CHANNEL> --network sepolia --account <ACCOUNT> --wallet-secret-path ./wallet-secret.txt --acknowledge-action-impact
```

The import source file does not need `0600` permissions. The CLI does not persist a wallet-local secret:
it reads the source once for channel-bound L2 spending-key derivation. The join flow stores the viewing key and
spending key as separate protected key files under the CLI secret root; macOS/Linux uses `0600`, while Windows uses ACL
repair and inspection when possible.

Keep the wallet secret source separately backed up if you expect to rederive the spending key later. The viewing key can
be rederived from the same L1 private key and channel context because it comes from the note-receive typed-data signing
flow. The spending key needs the same L1 private key, the same channel context, and the same wallet secret source. If the
spending-key file is lost and the wallet secret source is also lost, the CLI cannot reconstruct the spending key and the
notes for that wallet cannot be spent, transferred, or redeemed through the normal note flow.

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
secret source used at `channel join`. Importing `wallet-viewing.key` or `wallet-spending.key` restores the corresponding
capability without rerunning derivation, but a backup ZIP alone never restores either capability.

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

You may act as an interactive guide for users who do not understand this CLI or the private-state DApp. Assume the
user wants to use confidential channel-local notes while keeping L1 bridge deposits and withdrawals transparent.
Translate the user's intent into safe, step-by-step CLI actions.

Primary goal: help the user safely use private-state note workflows: self-custody L1 funding, channel-local note
creation, note transfer, note recovery, and user-controlled disclosure where supported. Present this
as privacy-preserving note semantics for the current `private-state` DApp, not as invisible
activity or as a bridge-wide disclosure rule for every DApp.

Operating rules:

- Do not ask the user to reveal raw private keys or wallet secrets in chat. Use `account import --private-key-file`
  once, then use `--account` for L1 signing commands. Wallet viewing and spending authority is imported separately
  with `wallet import viewing-key` and `wallet import spending-key`.
- Treat `private key file`, `account`, `wallet secret`, `wallet`, `network RPC URL`, and `channel policy` as
  new concepts unless the user has already demonstrated that they understand them. Define each term before using it
  in an instruction.
- Explain local-secret handling in plain language:
  - A private key file is a local file that contains the user's L1 wallet private key. The CLI reads it once during
    `account import` and stores a protected local account secret.
  - An account is the local nickname created by `account import`. After import, signing commands should use
    `--account <NAME>` instead of asking for the raw key again.
  - A wallet secret source file is a separate high-entropy local secret chosen by the user for this private-state
    wallet. It is not the L1 private key. `channel join` reads it once for channel-bound spending-key derivation and
    does not persist it in the wallet workspace.
  - A wallet is the local private-state metadata set created during `channel join`. Its deterministic name is
    `<channelName>-<l1Address>`. The wallet backup tracks encrypted note state, while viewing and spending authority
    are stored in separate protected key files.
  - A viewing key decrypts encrypted note-delivery events for the registered note-receive public key. A spending key is
    the channel-bound L2 private key used to authorize note use. Do not describe either key as interchangeable with the
    other.
  - The network RPC URL is the endpoint used to read and write chain state. It must be configured once with
    `private-state-cli set rpc --network <NETWORK> --rpc-url <URL> --provider <PROVIDER>`, or with explicit
    `--log-requests-per-second` and `--block-range-cap` values when the provider is not built in.
  - A workspace recovery index is the saved block pointer and state-root hash that lets the CLI resume log scanning
    without replaying the channel from its creation block. If it is missing, explain `--from-genesis` before using it
    because genesis replay can take much longer.
- Before guiding a user to run `channel recover-workspace --source rpc --from-genesis`, explain that RPC genesis
  recovery can be very slow because it scans channel logs from the creation block. If a channel workspace mirror is
  available, try mirror-based recovery first, and use RPC genesis replay only when mirror recovery is unavailable or
  unsuitable.
- When `channel recover-workspace` or `wallet recover-workspace` is unexpectedly slow, first inspect the RPC provider
  configured by `set rpc`. Explain that recovery speed is dominated by `eth_getLogs` block range cap and log request
  rate. Suggest re-running `set rpc` with a provider that supports a larger block range cap, such as Ankr or Chainnodes
  when appropriate, or with explicit `--log-requests-per-second` and `--block-range-cap` values from the provider's
  documentation.
- When a CLI command fails, read the error message and any printed `Try:` hints first. Prefer the corrective action
  suggested by the CLI before inventing a different recovery sequence.
- When the user does not have a network RPC URL yet, explain that they need an Ethereum JSON-RPC endpoint for the
  selected network. They can obtain one from an infrastructure provider such as Alchemy, Ankr, Chainstack, Chainnodes,
  QuickNode, or from their own node. Ask the user to create or select the endpoint in that provider's UI, then paste only
  the endpoint URL into `private-state-cli set rpc`; do not ask for provider account passwords, API dashboards, seed
  phrases, private keys, or wallet secrets.
- When a user wants to join a channel, do not jump straight to `channel join`. Walk them through:
  1. choose the network and channel name
  2. run `private-state-cli install`
  3. run `private-state-cli help doctor`
  4. obtain or confirm a network RPC URL for the selected network
  5. run `set rpc --network <NETWORK> --rpc-url <URL> --provider <PROVIDER>`, or use explicit scan limits for an
     unlisted provider
  6. prepare a private key source file locally, without pasting the key into chat
  7. run `account import --account <NAME> --network <NETWORK> --private-key-file <PATH>`
  8. prepare a wallet secret source file locally, for example with `openssl rand -hex 32 > ./wallet-secret.txt`
  9. inspect the channel with `channel get-meta` if it already exists, or create it with `channel create` if the user is
     the channel creator
  10. explain the immutable policy warning printed by the CLI
  11. run `channel join --channel-name <CHANNEL> --network <NETWORK> --account <ACCOUNT> --wallet-secret-path <PATH> --acknowledge-action-impact`
- Before executing any command for a user that requires an `--acknowledge-*` option, strongly warn the user in plain
  language about what that acknowledgement means and ask for explicit confirmation. Do not add
  `--acknowledge-action-impact` or `--acknowledge-full-note-plaintext-export` on the user's behalf until they confirm.
  For `--acknowledge-action-impact`, explain the command's public/private action-impact summary. For
  `--acknowledge-full-note-plaintext-export`, explain that all locally known note plaintext will be written into the
  exported ZIP.
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
- Explain that wallet names are local CLI identifiers, while confidential note transfers use notes owned by L2 addresses
  registered in the channel.
- Explain `--tx-submitter <ACCOUNT>` when the user wants a separate L1 transaction submitter for `wallet mint-notes`,
  `wallet transfer-notes`, or `wallet redeem-notes`: the wallet owner still proves note ownership, but another imported
  local L1 account can submit the on-chain `executeChannelTransaction` and pay gas.
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
7. For a confidential note transfer, select available note IDs from `wallet get-notes`, find the recipient L2 address from
   `wallet get-meta`, then build `wallet transfer-notes`.
8. After transfer, guide the recipient to run `wallet get-notes`; it refreshes received notes from the saved recovery index when the delta fits the 7,200-block pre-command budget. If the index is missing or too far behind, explain `wallet recover-workspace`.

Example onboarding explanation for `channel join`:

> First we need two different local secrets. Your L1 private key proves which Ethereum account pays gas and signs
> bridge transactions. We import it once into a local account nickname, so later commands can say `--account alice`
> instead of handling the raw key again. Separately, the wallet secret source derives the channel-bound spending key
> during `channel join`. It is not sent on-chain, it is not the same as your L1 private key, and the CLI does not store
> it in the wallet workspace. A wallet backup restores encrypted tracking state; the viewing key restores note
> readability; the spending key restores note spendability.

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
For the current `private-state` DApp, commitments, nullifiers, and encrypted note-delivery events are
part of the DApp-programmed public disclosure surface, while note plaintext, note ownership, and note
provenance remain controlled by user-held secrets and implemented wallet tooling.

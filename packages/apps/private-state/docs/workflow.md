# Private-State Workflow

This document consolidates the CLI-to-DApp and bridge-to-DApp workflows for the `private-state`
DApp. It describes the normal user command flow, the local workspace model, the proof input bundle,
and the bridge metadata coupling that makes the DApp executable through a private app channel.

The workflow has two layers:

- user-facing commands, such as mint, transfer, redeem, and withdraw
- bridge-facing proof and metadata checks that decide whether the resulting state transition is
  accepted

A command can be well formed from the user's point of view and still fail at the bridge layer if the
proof input, metadata digest, storage vector, or event layout does not match the channel policy.

## 1. CLI Role

The private-state CLI is an off-chain protocol participant, not a thin transaction sender.

It:

- derives channel-specific identities
- manages wallet metadata plus separate viewing-key and spending-key capabilities
- reconstructs channel snapshots
- assembles Tokamak proof inputs
- generates proofs locally
- submits bridge-coupled transactions
- scans bridge-propagated logs for encrypted note delivery

This role matters because the contracts do not store a complete user wallet. The CLI is responsible
for reconstructing the user's actionable view from accepted bridge outputs, encrypted note payloads,
wallet metadata, and user-held key files.

## 2. Normal Command Flow

The normal flow is:

1. `set rpc`
2. `account import`
3. `channel create`
4. `account deposit-bridge`
5. `channel join`
6. `wallet deposit-channel`
7. `wallet mint-notes`
8. `wallet transfer-notes`
9. `wallet get-notes`
10. `wallet redeem-notes`
11. `wallet withdraw-channel`
12. `channel exit`
13. `account withdraw-bridge`

`channel create` is permissionless at the bridge level. The caller becomes the channel leader and
chooses the initial join toll. `channel join` binds the user's L1 identity to a channel-specific L2
identity and registers the note-receive public key for encrypted note delivery.

`set rpc` is the per-network RPC configuration step. It stores the endpoint URL plus fixed
`eth_getLogs` scan limits under the local workspace. Ordinary bridge-facing and wallet commands read
that configuration instead of accepting per-command RPC URL overrides.

Users should run this flow from a self-custody L1 wallet. An exchange deposit address is
not a private-state wallet address: the exchange does not hold the user's channel workspace, wallet
spending key, viewing key, or recovery context.

Joining an existing channel requires a recovered local channel workspace. If the workspace has no
usable recovery index, the user must explicitly run
`channel recover-workspace --source rpc --from-genesis` once or recover from a registered workspace
mirror; `channel join` then refreshes from that index instead of silently replaying the channel from
genesis.

The flow moves value through three representations:

1. L1 custody in the bridge vault
2. liquid L2 accounting balance in `L2AccountingVault`
3. private notes in `PrivateStateController`

Deposits and withdrawals move between the first two representations. Mint and redeem move between
the second and third. Transfer moves value between notes without touching L1 custody.

`channel exit` is the registration cleanup step. It is separate from `wallet withdraw-channel` because
withdrawing liquid channel balance only moves value back to the shared bridge vault. Exiting removes
the user's channel registration, frees the reserved token-vault leaf binding, and applies the
channel's toll-refund schedule. Both the CLI and the bridge require the channel balance to be zero
before this cleanup can succeed.

## 3. Channel Policy Review

Before creating or joining a channel, the CLI should display the immutable channel policy that the
user is about to accept:

- DApp id and label
- DApp metadata digest and digest schema
- function root
- Groth16 verifier address and compatible backend version
- Tokamak verifier address and compatible backend version
- channel manager address and bridge registry binding
- join toll and refund policy

If the bridge owner later discovers that a bad DApp metadata or verifier snapshot was used, the
expected response is to announce the affected channel, stop using it, register corrected metadata or
verifiers for future channels, and create a fresh channel. Existing channel policy is intentionally
not rewritten in place.

Example: if a channel was created with the wrong function root, later fixing the DApp registry does
not rewrite that channel. A user should move to a new channel whose policy snapshot contains the
correct function root.

For the current `private-state` DApp, the channel leader's role is limited by this policy snapshot.
The leader can open the channel and manage exposed channel-level configuration, such as toll-related
policy, but does not custody user TON, does not hold user wallet secret source files, viewing keys,
or spending keys, does not intermediate note transfers, and does not have a protocol backdoor for
reconstructing every private note history. Availability services such as workspace mirrors may help
users recover channel state, but they do not replace user-held secrets and do not become custody or
viewing authorities.

The public monitoring surface is also bounded by this DApp's programmed disclosure policy. Bridge
deposits, withdrawals, channel joins, accepted transitions, commitments, nullifiers, encrypted note
events, verifier snapshots, and channel policy are publicly observable for the current
`private-state` DApp. Internal note provenance and sender-recipient relationships are not
automatically reconstructed from public data alone; selective disclosure is controlled by the user
within the limits of implemented wallet tooling.

## 4. Workspace And Wallet Artifacts

The CLI stores local state in two layers:

- channel workspace
- per-user wallet metadata and separate key files

The channel workspace contains:

- current state snapshot
- block info
- managed contract codes
- deployment and storage-layout manifest paths
- channel metadata

The wallet metadata is split across non-authorizing state and authority metadata. The note-tracking
metadata contains:

- note-receive registration metadata
- tracked note commitments, nullifiers, and encrypted note payloads
- last scanned encrypted-note event block
- local wallet operation history

The viewing-key metadata and spending-key metadata are stored separately and contain public
information derived from the corresponding secret, such as the registered note-receive public key or
the L2 public identity. The private viewing key and private spending key live as protected key files
outside the backup metadata.

The channel workspace is shared context for the channel. Wallet note metadata is user-specific
context, but it is no longer a full-control secret bundle. Losing the workspace is recoverable if
the wallet and chain data can reconstruct it. Losing the viewing-key or spending-key files removes
the corresponding capability until the user reimports or rederives that key material.

`wallet export backup` and `wallet import backup` are the non-authorizing backup boundary for this
local state. A backup contains wallet note-tracking metadata and the channel workspace cache, but it
does not contain spending keys, viewing keys, key derivation material, or plaintext note `owner`,
`value`, and `salt` fields. It preserves commitments, nullifiers, and encrypted note payloads.

`wallet export viewing-key` / `wallet import viewing-key` and `wallet export spending-key` /
`wallet import spending-key` move those capabilities independently. Importing only the backup does
not grant either viewing or spending authority.

That separation affects how wallet commands behave. `wallet get-meta` and `wallet list` can inspect
local registration metadata without decrypting notes. `wallet get-notes` can list encrypted-only
tracked notes from backup metadata, but it needs the viewing key to refresh and decrypt received
note events or compute note-value totals. Commands that create or consume notes, such as
`wallet mint-notes`, `wallet transfer-notes`, and `wallet redeem-notes`, need both the viewing key
and the spending key: the viewing key lets the CLI refresh the readable note workspace after
accepted note transactions, while the spending key authorizes proof-backed note use.

## 5. Bridge Registration Model

The bridge does not discover DApp behavior at runtime. It executes against pre-registered metadata.

The registration payload includes:

- managed storage vector
- pre-allocated storage keys
- user storage slots
- supported function list
- preprocess hash per function
- instance layout offsets
- storage-write metadata
- observed event-log metadata

This metadata is stored by `DAppManager`. A channel snapshots the DApp metadata digest, digest
schema, function root, verifier snapshot, and managed storage binding when the channel is created.
Existing channels do not automatically inherit later DApp metadata changes.

This is the bridge-level definition of "the DApp supported by this channel." It is not enough for a
Solidity function to exist in the deployed contract. The function must also be represented in the
channel's accepted function root and metadata layout.

## 6. Managed Storage Vector

For `private-state`, the managed storage vector must match the storage-layout manifest.

The current managed storage contracts are:

- `PrivateStateController`
- `L2AccountingVault`

The bridge treats this vector as ordered. The same order must be used by:

- DApp registration metadata
- channel creation
- CLI snapshots
- Synthesizer examples
- proof preprocess metadata

Example: if the controller is index `0` and the accounting vault is index `1` during registration,
then every root vector, storage-write descriptor, and proof input must keep that same order. Swapping
the order changes the meaning of the public inputs.

## 7. Function Metadata

Each registered function has:

- `entryContract`
- `functionSig`
- `preprocessInputHash`
- offsets for entry contract, function selector, current root vector, and updated root vector
- storage-write descriptors
- event-log descriptors

The bridge looks up the function at runtime by `preprocessInputHash`, not merely by selector. Any
change in generated preprocess layout can make a function unusable until the DApp metadata is
updated for future channels and a new channel is created against that updated policy.

This is why bridge support is stricter than ABI support. Two calls with the same Solidity selector
can still be incompatible with a channel if the proof preprocessing layout changed.

## 8. Proof Input Bundle

Before proof generation, the CLI materializes a transaction bundle containing:

- `previous_state_snapshot.json`
- `transaction.json` or transaction RLP input
- `block_info.json`
- `contract_codes.json`

These inputs must match the registered function metadata for the active DApp and channel.

The bundle is the bridge-checkable explanation of the private transaction. The raw private intent is
not what L1 verifies. L1 verifies a proof and the public inputs derived from this bundle.

`wallet deposit-channel` and `wallet withdraw-channel` are channel-token-vault accounting exceptions. They
generate the Groth16 `updateTree` proof from the current wallet snapshot and always consume the
installed Groth16 runtime workspace. The prover writes `proof.json` and `public.json` to the fixed
workspace proof directory rather than to per-operation output paths.

## 9. Snapshot Rules

For `private-state`, the snapshot must contain the full managed storage vector:

- controller storage
- L2 accounting vault storage

The CLI reconstructs this from real channel state rather than from a synthetic example. Stale or
mismatched deployment manifests, storage-layout manifests, bridge ABI manifests, or channel metadata
can make valid user intent fail because the bridge metadata model is strict.

Example: if the wallet builds a proof against an old controller address while the channel was created
with a newer managed storage vector, the proof can be rejected even if the user's intended transfer
would have been valid under the old local files.

## 10. Mint Flow

For `wallet mint-notes`, the CLI:

1. parses the amount vector
2. chooses the currently registered `mintNotes1` or `mintNotes2` entrypoint from the vector length
3. derives encrypted self-mint outputs for the wallet owner
4. encrypts those outputs to the wallet's note-receive public key
5. sends fixed-arity calldata to the DApp controller through the bridge execution path
6. refreshes the channel workspace and wallet note workspace from their recovery indexes after the
   transaction's receipt block is visible through the configured RPC provider

The contract then derives note salts from the encrypted payloads.

Self-mint still uses the encrypted delivery path. This keeps note reconstruction uniform: the wallet
recovers self-minted notes and received transfer notes through the same event scanning logic.

## 11. Transfer Flow

For `wallet transfer-notes`, the CLI:

1. resolves recipient note-receive public keys from channel registration by recipient L2 address
2. encrypts each output value to the recipient's registered note-receive key
3. builds fixed-arity `TransferOutput` calldata
4. submits the proof-backed bridge transaction

The sender does not send plaintext note payloads to the recipient through sidecar inbox files.

This makes Ethereum logs the shared delivery surface. The recipient still needs the note-receive
private key to decide whether a candidate encrypted payload belongs to them.

## 12. Redeem Flow

For `wallet redeem-notes`, the CLI:

1. chooses the fixed redeem arity from the selected note count
2. reconstructs plaintext notes from wallet state
3. submits the matching `redeemNotesN` call

Redemption converts notes back into liquid accounting balance rather than directly into L1 custody.

To leave the bridge, the user redeems notes first and then runs the channel and bridge withdrawal
flow. Redeem alone does not release canonical tokens.

## 13. Event Recovery Protocol

The CLI scans bridge-propagated Ethereum logs for encrypted note events.

Recovery flow:

1. fetch `NoteValueEncrypted` logs that belong to the channel execution stream
2. inspect the ciphertext scheme marker
3. decrypt with the note-receive private key
4. reconstruct note plaintext as:
   - owner = wallet L2 address
   - value = decrypted value
   - salt = hash(encrypted payload)
5. recompute commitment and nullifier
6. confirm current bridge/controller state before classifying the note as `unused` or `spent`

The same event decryption path is used for transferred note outputs and self-minted note outputs.

This classification step is necessary because decryption alone is not enough. The wallet must also
check accepted state to determine whether the reconstructed note is still unused.

## 14. Storage Writes And Event Logs

Each storage-write descriptor records:

- which managed storage address index is affected
- where the write starts inside the public user output vector

The bridge runtime expects the public-user section to encode storage writes in a fixed order:

- key lower word
- key upper word
- value lower word
- value upper word

The bridge also registers per-function event-log descriptors:

- `startOffsetWords`
- `topicCount`

At channel execution time, `ChannelManager` decodes the appended event-log section from the public
user output vector and re-emits those logs on Ethereum. This is how encrypted note delivery leaves
the proving environment and becomes observable to the recipient wallet.

## 15. Proof Acceptance Path

At runtime `ChannelManager.executeChannelTransaction(...)`:

1. hashes the preprocess input
2. resolves the registered function key
3. verifies that the function is allowed for the channel through the channel function root
4. checks root-vector and public-block consistency
5. observes storage writes and event logs from the public user vector
6. re-emits observed events on Ethereum
7. updates the current root vector hash

The bridge-DApp contract is therefore layout-based as well as ABI-based.

## 16. Failure Modes

The bridge can reject a transaction even when the Solidity calldata is correct if:

- the preprocess hash differs from the registered example
- the managed storage vector order differs
- the app block hash context differs
- the storage-write offsets were extracted incorrectly
- the emitted event-log metadata does not match the actual public user layout

These failures usually appear as bridge-level metadata mismatch errors rather than Solidity revert
reasons from the DApp controller.

## 17. Registered vs Supported Shapes

The CLI may know how to build more Solidity entrypoints than the currently registered DApp allows
on a network.

The effective support set is the intersection of:

- Solidity support
- bridge DApp registration support
- available proof-generation capacity
- CLI-exposed UX support

Not every Solidity entrypoint is always registered on a public network. Bridge registration can be
limited by Synthesizer generation and qap-compiler output limits.

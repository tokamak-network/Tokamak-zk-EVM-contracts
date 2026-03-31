# Bridge to DApp Protocol

## 1. Registration Model

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

This metadata is stored by `DAppManager` and copied into each new `ChannelManager` at channel creation time.

## 2. Managed Storage Vector

For `private-state`, the managed storage vector must match the storage-layout manifest.

Current managed storage contracts:

- `PrivateStateController`
- `L2AccountingVault`

The bridge treats this vector as ordered. The same order must be used by:

- DApp registration metadata
- channel creation
- CLI snapshots
- Synthesizer examples
- proof preprocess metadata

## 3. Function Metadata

Each registered function has:

- `entryContract`
- `functionSig`
- `preprocessInputHash`
- offsets for entry contract, function selector, current root vector, and updated root vector
- storage-write descriptors
- event-log descriptors

The bridge looks up the function at runtime by `preprocessInputHash`, not merely by selector.

That means any change in generated preprocess layout can make a function unusable until the DApp is re-registered.

## 4. Storage-Write Metadata

Each storage-write descriptor records:

- which managed storage address index is affected
- where the write starts inside the public user output vector

The current bridge runtime expects the public-user section to encode storage writes in a fixed order:

- key lower word
- key upper word
- value lower word
- value upper word

This metadata must therefore point to the storage-key position, not the value position.

## 5. Event-Log Metadata

The bridge also registers per-function event-log descriptors:

- `startOffsetWords`
- `topicCount`

At channel execution time, `ChannelManager` decodes the appended event-log section from the public user output vector and re-emits those logs on Ethereum.

This is how encrypted note delivery leaves the proving environment and becomes observable to the recipient wallet.

## 6. Channel Registration Protocol

Each L1 user registers channel identity metadata through `ChannelManager.registerChannelTokenVaultIdentity(...)`.

The registration stores:

- `l2Address`
- `channelTokenVaultKey`
- `leafIndex`
- `noteReceivePubKey`

It also maintains lookup by recipient L2 address, so senders can resolve recipient note-receive public keys during transfer construction.

## 7. Channel Creation Semantics

When the bridge creates a channel, it:

1. loads the DApp managed storage vector
2. loads the registered function set
3. initializes a zero-filled root vector
4. deploys a `ChannelManager`
5. copies function metadata, storage-write metadata, and event-log metadata into the channel-local cache

Existing channels do not automatically inherit later DApp metadata changes. Re-registration affects future channels and any logic that explicitly reloads metadata, not already-created channel-local caches.

## 8. Proof Acceptance Path

At runtime `ChannelManager.executeChannelTransaction(...)`:

1. hashes the preprocess input
2. resolves the registered function key
3. verifies that the function is allowed for the channel
4. checks root-vector and public-block consistency
5. observes storage writes and event logs from the public user vector
6. re-emits observed events on Ethereum
7. updates the current root vector hash

Therefore the bridge-DApp contract is not just ABI-based. It is also layout-based.

## 9. Failure Modes

The bridge can reject a transaction even when the Solidity calldata is correct if:

- the preprocess hash differs from the registered example
- the managed storage vector order differs
- the app block hash context differs
- the storage-write offsets were extracted incorrectly
- the emitted event-log metadata does not match the actual public user layout

These failures usually appear as bridge-level metadata mismatch errors rather than Solidity revert reasons from the DApp controller.

## 10. Network-Specific DApp Management Policy

The current bridge policy is:

- Sepolia allows owner-controlled DApp deletion and re-registration
- non-Sepolia chains reject DApp deletion

This policy exists to support test deployment iteration. It is not part of the private-state application logic itself.

## 11. Registration Coverage Limits

Not every Solidity entrypoint is always registered on a public test network.

Bridge registration is currently limited by the capacity of:

- Synthesizer generation
- qap-compiler output limits

Therefore the effective bridge-supported function set can be smaller than the full Solidity function family.

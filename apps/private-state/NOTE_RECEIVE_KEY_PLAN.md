# Private-State Recipient Note Delivery Plan

This document records both the intended recipient note-delivery architecture and the current implementation status.

## Problem Statement

The current `transferNotes` model lets the sender choose the recipient output note salt.

That creates a recovery and liveness problem:

- the recipient cannot spend a note without reconstructing its plaintext
- the plaintext requires the recipient note salt
- if the sender does not share the recipient salt, the recipient cannot use the note

The current bridge CLI avoids this by writing recipient note plaintext into deterministic inbox sidecar files under the
local workspace. That is sufficient for the current CLI-only workflow, but it is not a protocol-level solution and does
not survive a future browser-wallet deployment model.

## Constraints

This plan assumes the following constraints.

- The only public communication channel is Ethereum.
- A recipient-discoverable note delivery path is required.
- Users must not manage a separate long-lived note-receive key manually.
- The long-term target includes MetaMask-backed web usage.
- We intentionally accept the protocol assumption that signing one fixed message with the same Ethereum account always
  returns the same signature bytes.

That last assumption is strong and should be treated as an explicit protocol dependency rather than as a general
property of Ethereum wallets.

## Design Goal

Introduce an on-chain recipient note delivery path that:

- lets the sender encrypt recipient note data for the recipient only
- binds the on-chain recipient note to that encrypted payload
- removes sender control over recipient note salt
- avoids requiring users to back up or track a new independent key pair

## High-Level Plan

### 1. Deterministic Note-Receive Auxiliary Key

Each user derives a note-receive auxiliary key pair from their Ethereum key by signing one fixed channel-scoped
message.

Canonical signing method:

- `eth_signTypedData_v4`

This plan intentionally fixes the derivation flow to the MetaMask typed-data off-chain signing method. The system must
not mix this derivation with `personal_sign` or other signing RPCs.

Recommended typed-data fields:

- protocol label: `PRIVATE_STATE_NOTE_RECEIVE_KEY_V1`
- chain id
- channel id or channel name
- DApp label: `private-state`
- the user's Ethereum address

Derivation flow:

1. The wallet signs the fixed message with the user's Ethereum key.
2. The signature bytes are hashed to a 32-byte seed.
3. The seed is reduced into a valid secp256k1 private scalar.
4. The corresponding public key becomes the note-receive public key.

This gives the user a channel-scoped note-receive key pair without introducing a second independently managed secret.
The same wallet can reproduce the same auxiliary key later by signing the same message again.

The typed-data schema should be versioned and frozen. The derived note-receive key is invalid if any of the following
change without a migration:

- the EIP-712 domain
- the primary type name
- field ordering
- field encoding
- the MetaMask signing RPC method

### 1A. On-Chain Public-Key Shape

The bridge registration state should introduce a dedicated public-key struct for readability:

```solidity
struct NoteReceivePubKey {
    bytes32 x;
    uint8 yParity;
}
```

That struct should then be embedded inside the channel registration record rather than flattened into loose fields.

Recommended channel registration shape:

```solidity
struct ChannelTokenVaultRegistration {
    bool exists;
    address l2Address;
    bytes32 channelTokenVaultKey;
    uint256 leafIndex;
    NoteReceivePubKey noteReceivePubKey;
}
```

### 2. Channel Registration Stores the Auxiliary Public Key

When a user registers for the channel, the channel registration state must also store the derived note-receive public
key.

That public key becomes the canonical encryption target for incoming private-state notes.

The sender never guesses or reconstructs the recipient key from the recipient address alone. The sender reads the
registered note-receive public key from channel state.

### 2A. Sender Lookup Path

The sender-facing lookup path must be keyed by recipient `l2Address`, not only by the recipient's L1 registration
address.

Reason:

- private-state transfers target recipient L2 note owners
- the transfer CLI and future web flow naturally identify recipients by L2 address
- requiring the sender to know the recipient's L1 registration address would add an unnecessary lookup dependency and
  make the UX worse

Therefore the bridge registration layer should maintain a second lookup path:

```solidity
mapping(address l2Address => NoteReceivePubKey) private _noteReceivePubKeysByL2Address;
```

or an equivalent registration index that returns the full registration record by `l2Address`.

Recommended view methods:

```solidity
function getChannelTokenVaultRegistrationByL2Address(address l2Address)
    external
    view
    returns (BridgeStructs.ChannelTokenVaultRegistration memory);

function getNoteReceivePubKeyByL2Address(address l2Address)
    external
    view
    returns (BridgeStructs.NoteReceivePubKey memory);
```

The second method is optional if the first already exists and is cheap to consume, but at least one `l2Address`
lookup path must exist.

Concrete bridge-side changes:

- add `BridgeStructs.NoteReceivePubKey`
- extend `BridgeStructs.ChannelTokenVaultRegistration`
- extend `ChannelManager.registerChannelTokenVaultIdentity(...)` to accept the note-receive public key
- extend `BridgeCore.getChannelTokenVaultRegistration(...)` and all ABI consumers to return the new field
- maintain an `l2Address -> registration` or `l2Address -> noteReceivePubKey` lookup path
- expose that `l2Address` lookup through `ChannelManager` and `BridgeCore`
- extend the channel registration event to include the note-receive public key

This key belongs in the bridge channel registration layer, not in `PrivateStateController`, because it is channel user
identity metadata rather than DApp-local note state.

### 3. Sender Encrypts Recipient Note Data Off-Chain

For recipient-facing outputs, the sender encrypts a compact note payload to the recipient note-receive public key using
an ECIES-style flow.

Recommended construction:

- curve agreement: ECDH on secp256k1
- one fresh ephemeral key pair per encrypted recipient note
- symmetric encryption: authenticated AEAD

#### Canonical ECIES Profile

This plan narrows the construction to a fixed ciphertext shape so that transfer entrypoints stay fixed-arity and do not
need dynamic bytes payloads.

Curve and agreement:

- secp256k1
- sender creates one fresh ephemeral secp256k1 key pair per recipient note
- shared secret = ECDH(senderEphemeralPriv, recipientNoteReceivePubKey)

Key derivation:

- HKDF-SHA256
- domain string: `PRIVATE_STATE_NOTE_ECIES_V1`

Symmetric encryption:

- `AES-256-GCM`

Associated data:

- protocol label: `PRIVATE_STATE_TRANSFER_NOTE_V1`
- chain id
- channel id
- recipient L2 owner address

Plaintext:

- note value only

The recipient already knows the owner address, and the salt will be derived from the ciphertext hash. Therefore the
plaintext does not need to carry owner or salt.

#### Fixed Ciphertext Struct

To keep the calldata fixed-shape and avoid per-field decode overhead inside transfer entrypoints, recipient note
ciphertext should be represented as an opaque three-word payload:

```solidity
bytes32[3] encryptedNoteValue;
```

The serialized hash for salt derivation should be:

```solidity
keccak256(abi.encode(encryptedNoteValue))
```

The off-chain ECIES packing is:

- word 0: `ephemeralPubKeyX`
- word 1: packed `yParity || nonce || tag || reserved`
- word 2: `ciphertextValue`

The contract does not decode those words. It only hashes the opaque payload and emits it.

### 4. Bind the On-Chain Note to the Ciphertext

The transfer entrypoint should stop accepting the recipient note salt directly.

For recipient-facing outputs:

- the sender supplies a fixed `bytes32[3] encryptedNoteValue`
- the contract computes `ciphertextHash = keccak256(serializedEncryptedNoteValue)`
- the contract sets `salt = ciphertextHash`
- the recipient note commitment is then computed from:
  - recipient owner
  - note value
  - `salt = keccak256(serializedEncryptedNoteValue)`

This is the cheapest consistency binding available under the current architecture.

It guarantees:

- the sender cannot hide the salt
- the ciphertext and the on-chain note are bound together
- any ciphertext change changes the note salt and commitment

It does not guarantee that the ciphertext decrypts to a truthful payload unless the sender behaves honestly. The design
only enforces ciphertext-to-note binding, not full semantic correctness of the encrypted plaintext.

#### Transfer API Shape

To avoid mixed success modes inside transfer entrypoints, every transfer output should use the same encrypted-value
shape, including sender change outputs.

That means the transfer API should conceptually change from:

- `Note[N] calldata outputs`

to:

- `TransferOutput[N] calldata outputs`

where:

```solidity
struct TransferOutput {
    address owner;
    uint256 value;
    bytes32[3] encryptedNoteValue;
}
```

The sender encrypts change outputs to their own registered note-receive public key. This keeps the transfer path
uniform and avoids a branch that treats self-outputs differently from recipient outputs.

### 5. Publish Ciphertext on Ethereum

The ciphertext must be published on Ethereum so the recipient can discover the incoming note.

The current preferred channel is an event log emitted by the transfer path.

The event should carry only enough information for the recipient wallet to scan and attempt decryption, while the
on-chain state transition remains bound to the ciphertext hash through the salt rule above.

The event must not reveal any recipient-identifying note metadata such as:

- recipient owner address
- note commitment
- ciphertext hash as a separate field

Those values are either privacy-sensitive or derivable locally by the recipient from the ciphertext itself.

Recommended DApp event shape:

```solidity
event NoteValueEncrypted(
    bytes32[3] encryptedNoteValue
);
```

Each transfer output emits one such event after its commitment is registered.

## Implementation Status

The Synthesizer prerequisite is no longer pending. The `tokamak-zk-evm` submodule already exposes the updated
`instance.json -> a_pub_user` format with appended DApp event-log records, and the implementation status is now:

### 1. Private-State DApp Contracts

Completed.

Implemented changes:

- `PrivateStateController` transfer entrypoints now use `TransferOutput`
- each transfer output carries an opaque `bytes32[3] encryptedNoteValue`
- transfer output salts are derived inside the contract from the encrypted payload
- one `NoteValueEncrypted(bytes32[3])` event is emitted per transfer output

### 2. Private-State Synthesizer Example Regeneration

Completed.

Implemented changes:

- the private-state example inputs are generated from the app deploy flow
- per-function `previous_state_snapshot.json`, `transaction.json`, `block_info.json`, and `contract_codes.json` are
  regenerated under the Synthesizer package
- the corresponding `cli-launch-manifest.json` files and VS Code launch entries are updated from the same flow

### 3. Bridge Contract Update and Deployment

Completed.

Implemented changes:

- the bridge contracts now support note-receive public keys and DApp event-log metadata
- the updated bridge stack has been deployed to Sepolia

### 4. Bridge Metadata Upload

Completed, subject to current Synthesizer capacity limits.

Current Sepolia registration status:

- registered examples: `mintNotes1`, `mintNotes2`, `mintNotes3`, `mintNotes4`, `transferNotes1To1`,
  `transferNotes1To2`, `transferNotes2To1`, `redeemNotes1`, `redeemNotes2`
- currently skipped due to `qap-compiler` capacity: `mintNotes5`, `mintNotes6`, `transferNotes1To3`,
  `transferNotes2To2`, `transferNotes3To1`, `transferNotes3To2`, `transferNotes4To1`, `redeemNotes3`,
  `redeemNotes4`

Latest Sepolia deployment and registration artifacts:

- controller: `0xE787f8aBf3848daDD80512028086Ea2aafA26CC1`
- vault: `0x703aa404333DCA0B12921a5a47A9bbf6c8950db2`
- registration tx: `0xa42e1b56ef7522d02a8746cd923a64431abfb004d3a21185605d1a4f2cd86c6e`

### 5. CLI Changes

Completed for the intended delivery model.

Implemented changes:

- channel registration submits the derived `NoteReceivePubKey`
- `transfer-notes` resolves recipient note-receive keys from bridge channel state and encrypts transfer outputs
- `transfer-notes` no longer treats recipient wallet sidecar writes as the canonical delivery path
- `get-my-notes` scans Ethereum logs for `NoteValueEncrypted`, decrypts matching outputs, reconstructs notes, and
  caches the last scanned block

### 6. E2E and CLI-E2E Stabilization

Still pending as a formal completion criterion.

The core feature path is implemented, but this document should not claim that the full bridge e2e and CLI-e2e matrix
has been re-run and stabilized for every private-state example variant.

## DApp Contract Update Plan

The private-state DApp changes are implemented in `PrivateStateController` and in the app-local metadata generation
path. This section describes the DApp-side contract and registration-output changes. Bridge and CLI changes are covered
separately below.

### A. Transfer Output Shape and Salt Derivation

Every transfer entrypoint now stops accepting a caller-chosen recipient salt and instead accepts an encrypted output
payload:

```solidity
struct TransferOutput {
    address owner;
    uint256 value;
    bytes32[3] encryptedNoteValue;
}
```

That implies the following contract-side updates:

- replace transfer output calldata shapes from `Note` to `TransferOutput`
- derive `salt = keccak256(serializedEncryptedNoteValue)` inside the contract
- compute output commitments from `(owner, value, derivedSalt)` rather than from caller-supplied salt
- apply the same output shape to sender change notes so that transfer entrypoints keep one successful path only

### B. Contract Execution Delta

For each `transferNotes*` function, the new logic adds only the minimum extra work required by the new delivery model:

- read an opaque `bytes32[3]` ciphertext payload from calldata
- compute one `keccak256` over the fixed serialized ciphertext
- emit one ciphertext-bearing DApp event per output

This plan does not add:

- recipient inbox storage
- note-delivery nonce storage
- on-chain decryption
- on-chain ciphertext semantic validation

### C. DApp Event Shape

The DApp must emit a ciphertext delivery event for each transfer output, but the event must not leak recipient note
ownership or note identifiers.

Required privacy rule:

- do not emit recipient owner address
- do not emit note commitment
- do not emit ciphertext hash as a separate field

Recommended event shape:

```solidity
event NoteValueEncrypted(
    bytes32[3] encryptedNoteValue
);
```

The ciphertext hash remains available implicitly because both the sender and the recipient can compute it from
`encryptedNoteValue`.

### D. DApp Metadata Generation

The app-local function metadata generation path now describes event-log outputs in addition to storage writes.

Current DApp-side status:

- transfer function metadata already declares emitted event-log records
- `mintNotes*` and `redeemNotes*` remain note-delivery-log free
- the app deploy flow now regenerates the Synthesizer example inputs directly after deployment

## Bridge Contract Update Plan

The Synthesizer update is already complete, and `instance.json -> a_pub_user` now includes DApp event-log records in
addition to the existing storage-write records.

Given that current output format, the bridge execution flow now behaves as follows.

### A. Channel Registration and Recipient-Key Lookup

The bridge registration layer is responsible for storing and serving the recipient note-receive public key.

Implemented bridge-side shape:

```solidity
struct NoteReceivePubKey {
    bytes32 x;
    uint8 yParity;
}

struct ChannelTokenVaultRegistration {
    bool exists;
    address l2Address;
    bytes32 channelTokenVaultKey;
    uint256 leafIndex;
    NoteReceivePubKey noteReceivePubKey;
}
```

Implemented registration-path changes:

- add `BridgeStructs.NoteReceivePubKey`
- extend `BridgeStructs.ChannelTokenVaultRegistration`
- extend `ChannelManager.registerChannelTokenVaultIdentity(...)` to accept the note-receive public key
- extend bridge-facing registration getters to return the new field
- maintain an `l2Address -> registration` or `l2Address -> noteReceivePubKey` lookup path
- expose a view path so senders can resolve `NoteReceivePubKey` by recipient `l2Address`
- extend the registration event to include the note-receive public key

The lookup must be keyed by recipient `l2Address`, because private-state transfer flows naturally identify recipients by
L2 owner address rather than by the L1 registration address.

### B. Bridge Function Metadata

The bridge-side function metadata no longer assumes that `a_pub_user` contains storage writes only.

The correct shape should be expressed in two layers, because the bridge already has two metadata forms:

- registration input metadata: `BridgeStructs.DAppFunctionMetadata`
- runtime lookup metadata: `BridgeStructs.FunctionConfig`

That distinction matters because `DAppFunctionMetadata` currently carries an `InstanceLayout`, while `FunctionConfig`
stores only fixed-size hot-path fields. Variable-length arrays such as `storageWrites` are already stored outside
`FunctionConfig`, and `eventLogs` should follow the same pattern rather than being embedded into `FunctionConfig`.

Implemented registration metadata shape:

```solidity
struct EventLogMetadata {
    uint16 startOffsetWords;
    uint8 topicCount;
}

struct InstanceLayout {
    uint8 entryContractOffsetWords;
    uint8 functionSigOffsetWords;
    uint8 currentRootVectorOffsetWords;
    uint8 updatedRootVectorOffsetWords;
    StorageWriteMetadata[] storageWrites;
    EventLogMetadata[] eventLogs;
}
```

Implemented runtime storage shape:

```solidity
struct FunctionConfig {
    bytes32 preprocessInputHash;
    uint8 entryContractOffsetWords;
    uint8 functionSigOffsetWords;
    uint8 currentRootVectorOffsetWords;
    uint8 updatedRootVectorOffsetWords;
    bool exists;
}
```

Recommended separate runtime stores:

```solidity
mapping(uint256 => mapping(bytes32 => StorageWriteMetadata[])) private _functionStorageWrites;
mapping(uint256 => mapping(bytes32 => EventLogMetadata[])) private _functionEventLogs;
```

Why this shape is better:

- `EventLogMetadata` is a better name than `EventLogLayout`, because the struct is describing one decoded event record
  shape, not the whole layout section
- `InstanceLayout.eventLogs` makes the registration input explicit and parallel to `storageWrites`
- `FunctionConfig` remains a compact fixed-size hot-path struct instead of becoming a mixed fixed/dynamic container
- `EventLogMetadata[]` is handled with the same storage discipline as `StorageWriteMetadata[]`

Current bridge ownership of this metadata:

- `BridgeStructs` defines `EventLogMetadata`, `InstanceLayout`, and `FunctionConfig`
- `DAppManager.registerDApp(...)` receives `DAppFunctionMetadata.instanceLayout.eventLogs`
- `DAppManager` persists a runtime copy of those event descriptors into a dedicated function-event-log store
- `ChannelManager` copies those event descriptors into a channel-local event-log cache when the channel is created
- `ChannelManager.executeChannelTransaction(...)` loads the cached event descriptors and uses them to decode the
  event-log section from `payload.aPubUser`

### C. Bridge Runtime Emission

`ChannelManager.executeChannelTransaction(...)` now observes storage writes and the appended event-log section.

Current behavior:

1. decode the storage-write section as today
2. decode the appended event-log section from `payload.aPubUser`
3. immediately emit those logs on Ethereum

Because the event signature and topic count are DApp-defined, the bridge should not try to map them into a fixed
Solidity event type. Instead, it should format and emit raw logs using assembly `log0` through `log4` depending on the
decoded topic count.

That preserves the DApp event identity as seen by downstream indexers.

### D. Current Bridge Management Policy

The current bridge implementation also includes a temporary owner-controlled DApp deletion path for test deployments.

Current behavior:

- `DAppManager.deleteDApp(...)` is available while `dAppDeletionEnabled` is true
- `disableDAppDeletionForever()` can permanently close that path
- deletion is blocked when the DApp already has active channels

Deployment policy:

- Sepolia keeps this path available as a test-deployment-only operational tool
- mainnet deployment and upgrade flows call `disableDAppDeletionForever()` and keep DApp deletion permanently disabled

This policy is operational scaffolding for test deployments rather than part of the private-state note-delivery design
itself.

## CLI Update Plan

The private-state CLI has changed in three areas.

### A. Channel Registration CLI

Current `register-channel` behavior:

1. build the fixed EIP-712 typed data for note-receive key derivation
2. sign it through the MetaMask-compatible off-chain signing method
3. derive the auxiliary secp256k1 note-receive key pair
4. submit the derived `NoteReceivePubKey` during channel registration
5. persist enough local metadata to reproduce the same typed-data request later

The persisted wallet metadata must store at least:

- note-receive key derivation version
- the exact typed-data payload template inputs
- the registered compressed public key

### B. Transfer CLI

Current `transfer-notes` behavior:

1. query each recipient's `NoteReceivePubKey` from channel registration state by recipient `l2Address`
2. derive or recover the sender's own note-receive public key for change outputs
3. encrypt each transfer output value into an opaque `bytes32[3] encryptedNoteValue`
4. build the new transfer calldata with encrypted outputs
5. submit the channel transaction

The legacy `incoming-notes.json` sidecar flow is no longer used.

### C. Recipient Recovery CLI

Current recipient note recovery behavior:

1. rebuild the deterministic note-receive auxiliary private key from the fixed typed-data signature
2. scan bridge-propagated DApp logs for `NoteValueEncrypted`
3. attempt ECIES decryption for logs targeting the current channel
4. reconstruct note plaintext using:
   - owner = local wallet L2 address
   - value = decrypted note value
   - salt = ciphertext hash
5. absorb recovered notes into the encrypted wallet state

This replaces the old sender-written `incoming-notes.json` sidecar path entirely.

## Recipient Recovery Flow

When the recipient later wants to recover received notes:

1. Re-derive the note-receive auxiliary private key by signing the fixed typed-data registration message again.
2. Scan Ethereum logs for bridge-propagated `NoteValueEncrypted` records for the current channel.
3. Attempt ECIES decryption using the auxiliary private key.
4. If decryption succeeds:
   - read the note value from the decrypted payload
   - compute `salt = keccak256(serializedEncryptedNoteValue)`
   - reconstruct the note plaintext as:
     - `owner = recipient L2 address`
     - `value = decrypted value`
     - `salt = keccak256(serializedEncryptedNoteValue)`
5. Recompute the note commitment locally and optionally confirm that the controller state recognizes that commitment as
   existing before persisting the recovered note into wallet state.

## Why This Plan Was Chosen

This plan is the current preferred direction because it satisfies the main constraints better than the alternatives.

### Compared with sender-shared plaintext or salt

- no sender cooperation is needed after transfer submission
- the recipient can recover later from Ethereum alone

### Compared with a separately managed encryption key

- the user does not need to back up a second long-lived key manually
- the auxiliary key is recoverable from the user's Ethereum signing key

### Compared with on-chain inbox storage

- storage growth is avoided
- placement overhead is lower
- only the ciphertext hash is used in the commitment path

### Compared with stronger on-chain ciphertext validation

- placements remain much lower
- the contract only needs one extra hash per recipient output
- there is no on-chain re-encryption or zero-knowledge proof of ciphertext correctness

## Non-Goals

This plan does not attempt to solve all possible privacy problems.

It does not provide:

- proof that the ciphertext plaintext is truthful beyond the ciphertext-hash binding
- universal wallet compatibility outside the fixed-signature assumption
- support for accounts that cannot reproduce the fixed signature deterministically

## Open Risks and Assumptions

The main protocol assumption is that the chosen wallet flow returns the same signature bytes for the same fixed message
and account over time.

If that assumption fails:

- the user may derive a different auxiliary private key later
- recipient note recovery breaks

For that reason, the exact signing method must be fixed and versioned at the protocol level.

This plan fixes the derivation method to:

- `eth_signTypedData_v4`

The system must not silently substitute:

- `personal_sign`
- `eth_sign`
- hardware-wallet-specific alternate signing flows

for the same derivation rule without an explicit migration.

## Remaining Scope

The following work remains outside the already implemented core path:

1. increase supported private-state function coverage beyond the current Synthesizer capacity ceiling
2. re-run and stabilize the full bridge e2e and CLI-e2e matrix against the current deployed contracts and fixtures

This document describes the implemented architecture plus the remaining gaps to full operational completion.

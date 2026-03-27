# Private-State Recipient Note Delivery Plan

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

To keep the calldata fixed-shape, recipient note ciphertext should be represented as:

```solidity
struct EncryptedNoteValue {
    bytes32 ephemeralPubKeyX;
    uint8 ephemeralPubKeyYParity;
    bytes12 nonce;
    bytes32 ciphertextValue;
    bytes16 tag;
}
```

The serialized hash for salt derivation should be:

```solidity
keccak256(
    abi.encode(
        encrypted.ephemeralPubKeyX,
        encrypted.ephemeralPubKeyYParity,
        encrypted.nonce,
        encrypted.ciphertextValue,
        encrypted.tag
    )
)
```

This gives a fixed-size note ciphertext without dynamic memory or variable-length calldata.

### 4. Bind the On-Chain Note to the Ciphertext

The transfer entrypoint should stop accepting the recipient note salt directly.

For recipient-facing outputs:

- the sender supplies a fixed `EncryptedNoteValue`
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
    EncryptedNoteValue encryptedValue;
}
```

The sender encrypts change outputs to their own registered note-receive public key. This keeps the transfer path
uniform and avoids a branch that treats self-outputs differently from recipient outputs.

### 5. Publish Ciphertext on Ethereum

The ciphertext must be published on Ethereum so the recipient can discover the incoming note.

The current preferred channel is an event log emitted by the transfer path.

The event should carry enough information for the recipient wallet to scan and attempt decryption, while the on-chain
state transition remains bound to the ciphertext hash through the salt rule above.

Recommended DApp event shape:

```solidity
event NoteValueEncrypted(
    address indexed owner,
    bytes32 indexed commitment,
    bytes32 indexed ciphertextHash,
    EncryptedNoteValue encryptedValue
);
```

Each transfer output emits one such event after its commitment is registered.

## Bridge Log Propagation Plan

This plan assumes the pending Synthesizer update is complete and that `instance.json -> a_pub_user` now includes DApp
event-log records in addition to the existing storage-write records.

Under that assumption, the bridge execution flow should change as follows.

### 6. Bridge Function Metadata

The bridge-side function metadata must stop assuming that `a_pub_user` contains storage writes only.

`BridgeStructs.InstanceLayout` should gain explicit event-log layout metadata, for example:

```solidity
struct EventLogLayout {
    uint16 startOffsetWords;
}
```

or an equivalent event-log section descriptor.

The exact shape can follow the final Synthesizer output format, but the bridge metadata must explicitly tell
`executeChannelTransaction` where the log records begin.

### 7. Bridge Runtime Emission

`ChannelManager.executeChannelTransaction(...)` currently observes storage writes and emits bridge-local storage-write
events only.

After the Synthesizer update, it should:

1. decode the storage-write section as today
2. decode the appended event-log section from `payload.aPubUser`
3. immediately emit those logs on Ethereum

Because the event signature and topic count are DApp-defined, the bridge should not try to map them into a fixed
Solidity event type. Instead, it should format and emit raw logs using assembly `log0` through `log4` depending on the
decoded topic count.

That preserves the DApp event identity as seen by downstream indexers.

### 8. DApp Metadata Generation

The DApp registration metadata generation path must also be updated so the bridge learns the new event-log layout.

That affects:

- DApp metadata generation scripts
- DApp registration helpers used by bridge e2e flows
- any `buildFunctionDefinition(...)` or equivalent helper that currently assumes storage writes are the only observable
  user outputs

The DApp metadata that is registered through `DAppManager.registerDApp(...)` must include both:

- storage-write layout metadata
- event-log layout metadata

## CLI Update Plan

The private-state CLI will need changes in three areas.

### 9. Channel Registration CLI

The `register-channel` flow must:

1. build the fixed EIP-712 typed data for note-receive key derivation
2. sign it through the MetaMask-compatible off-chain signing method
3. derive the auxiliary secp256k1 note-receive key pair
4. submit the derived `NoteReceivePubKey` during channel registration
5. persist enough local metadata to reproduce the same typed-data request later

The persisted wallet metadata must store at least:

- note-receive key derivation version
- the exact typed-data payload template inputs
- the registered compressed public key

### 10. Transfer CLI

The `transfer-notes` flow must stop writing plaintext recipient notes into local inbox sidecars as the canonical
delivery mechanism.

Instead it should:

1. query each recipient's `NoteReceivePubKey` from channel registration state by recipient `l2Address`
2. derive or recover the sender's own note-receive public key for change outputs
3. encrypt each transfer output value into an `EncryptedNoteValue`
4. build the new transfer calldata with encrypted outputs
5. submit the channel transaction

The current `incoming-notes.json` sidecar flow should then become a legacy compatibility path rather than the primary
delivery path.

### 11. Recipient Recovery CLI

Wallet-backed commands that need note discovery should:

1. rebuild the deterministic note-receive auxiliary private key from the fixed typed-data signature
2. scan bridge-propagated DApp logs for `NoteValueEncrypted`
3. attempt ECIES decryption for logs targeting the current channel
4. reconstruct note plaintext using:
   - owner = local wallet L2 address
   - value = decrypted note value
   - salt = ciphertext hash
5. absorb recovered notes into the encrypted wallet state

This replaces the sender-written `incoming-notes.json` sidecar as the long-term recovery path.

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
5. Recompute the note commitment locally and match it against the expected incoming output note commitment.

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

## Planned Implementation Scope

The expected implementation work is:

1. add `BridgeStructs.NoteReceivePubKey`
2. extend channel registration state and registration ABI with `NoteReceivePubKey`
3. add deterministic typed-data-based note-receive key derivation to the CLI and future web client flow
4. replace sender-provided transfer output salt with `keccak256(serializedEncryptedNoteValue)`
5. add fixed-shape `EncryptedNoteValue` calldata to transfer entrypoints
6. add ciphertext-bearing transfer event logs in the DApp
7. extend bridge function metadata so `executeChannelTransaction(...)` can decode event-log sections from
   `payload.aPubUser`
8. emit raw bridge-side logs for those DApp events in `executeChannelTransaction(...)`
9. update wallet recovery and note discovery flows to scan and decrypt bridge-propagated ciphertext logs
10. retire `incoming-notes.json` as the primary delivery mechanism once the log-based path is live

This document describes the current intended direction only. It is not yet implemented.

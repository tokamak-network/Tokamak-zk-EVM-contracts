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

Recommended fixed message fields:

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

### 2. Channel Registration Stores the Auxiliary Public Key

When a user registers for the channel, the channel registration state must also store the derived note-receive public
key.

That public key becomes the canonical encryption target for incoming private-state notes.

The sender never guesses or reconstructs the recipient key from the recipient address alone. The sender reads the
registered note-receive public key from channel state.

### 3. Sender Encrypts Recipient Note Data Off-Chain

For recipient-facing outputs, the sender encrypts a compact note payload to the recipient note-receive public key using
an ECIES-style flow.

Recommended construction:

- curve agreement: ECDH on secp256k1
- one fresh ephemeral key pair per encrypted recipient note
- symmetric encryption: authenticated AEAD

The ciphertext should carry:

- the ephemeral public key
- the AEAD nonce or IV
- the encrypted payload
- the authentication tag

The encrypted payload should be minimal.

The recipient already knows:

- their own output owner address

The recipient can derive:

- note salt from the ciphertext hash

Therefore the payload only needs the note value plus a domain tag if desired.

Recommended plaintext payload:

- `PRIVATE_STATE_TRANSFER_NOTE_V1`
- note value

### 4. Bind the On-Chain Note to the Ciphertext

The transfer entrypoint should stop accepting the recipient note salt directly.

For recipient-facing outputs:

- the sender supplies the ciphertext
- the contract computes `ciphertextHash = keccak256(ciphertext)`
- the contract sets `salt = ciphertextHash`
- the recipient note commitment is then computed from:
  - recipient owner
  - note value
  - `salt = keccak256(ciphertext)`

This is the cheapest consistency binding available under the current architecture.

It guarantees:

- the sender cannot hide the salt
- the ciphertext and the on-chain note are bound together
- any ciphertext change changes the note salt and commitment

It does not guarantee that the ciphertext decrypts to a truthful payload unless the sender behaves honestly. The design
only enforces ciphertext-to-note binding, not full semantic correctness of the encrypted plaintext.

### 5. Publish Ciphertext on Ethereum

The ciphertext must be published on Ethereum so the recipient can discover the incoming note.

The current preferred channel is an event log emitted by the transfer path.

The event should carry enough information for the recipient wallet to scan and attempt decryption, while the on-chain
state transition remains bound to the ciphertext hash through the salt rule above.

## Recipient Recovery Flow

When the recipient later wants to recover received notes:

1. Re-derive the note-receive auxiliary private key by signing the fixed registration message again.
2. Scan Ethereum logs for transfer ciphertexts that might target this channel and this user.
3. Attempt ECIES decryption using the auxiliary private key.
4. If decryption succeeds:
   - read the note value from the decrypted payload
   - compute `salt = keccak256(ciphertext)`
   - reconstruct the note plaintext as:
     - `owner = recipient L2 address`
     - `value = decrypted value`
     - `salt = keccak256(ciphertext)`
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

For that reason, the exact signing method must be fixed and versioned at the protocol level. The system must not mix:

- `personal_sign`
- `eth_signTypedData_v4`
- hardware-wallet-specific signing flows

for the same derivation rule without an explicit migration.

## Planned Implementation Scope

The expected implementation work is:

1. extend channel registration state with the note-receive public key
2. add deterministic note-receive key derivation to the CLI and future web client flow
3. extend recipient output handling so recipient salt is derived from ciphertext hash rather than caller-provided salt
4. add ciphertext-bearing transfer event logs
5. update wallet recovery and note discovery flows to scan and decrypt incoming ciphertext logs

This document describes the current intended direction only. It is not yet implemented.

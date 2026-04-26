# Function Constraints

This document lists the constraints that each user-facing function family must satisfy.

## 1. Global Constraints

These constraints apply across the DApp:

- every user-facing function uses a fixed arity
- every successful path is intended to be unique
- zero owner addresses are rejected
- zero note values are rejected
- commitment re-creation is rejected
- nullifier reuse is rejected
- all accounting updates must remain inside the BLS12-381 scalar field bounds

## 2. Mint Functions

### Supported Entry Points

- `mintNotes1`
- `mintNotes2`
- `mintNotes3`
- `mintNotes4`
- `mintNotes5`
- `mintNotes6`

### Constraints

- owner is always `msg.sender`
- each output value must be strictly positive
- output salt is not caller-supplied; it is derived from `encryptedNoteValue`
- every output emits one `NoteValueEncrypted` event
- `sum(output values)` must be available in the caller's liquid accounting balance
- each derived commitment must be new

### Operational Note

Bridge registration coverage may be smaller than Solidity support on a given network because function examples can still be skipped by Synthesizer or qap-compiler capacity limits.

## 3. Transfer Functions

### Supported Solidity Entry Points

- `transferNotes1To1`
- `transferNotes1To2`
- `transferNotes1To3`
- `transferNotes2To1`
- `transferNotes2To2`
- `transferNotes3To1`
- `transferNotes3To2`
- `transferNotes4To1`

### Constraints

- every input note must be owned by `msg.sender`
- every input commitment must exist
- every input nullifier must be unused
- every output value must be strictly positive
- every output salt is derived from `encryptedNoteValue`
- every output emits one `NoteValueEncrypted` event
- total value is conserved exactly:
  - `sum(inputs) == sum(outputs)`

### Registration Note

The bridge can only execute transfer shapes that are currently registered for the active DApp deployment. Solidity support and registered support are not always identical.

## 4. Redeem Functions

### Supported Entry Points

- `redeemNotes1`
- `redeemNotes2`
- `redeemNotes3`
- `redeemNotes4`

### Constraints

- `receiver` must be non-zero
- each input note must be owned by `msg.sender`
- each input commitment must exist
- each input nullifier must be unused
- every input nullifier is consumed exactly once
- the total redeemed value is credited to `receiver` in `L2AccountingVault`

## 5. Contract Helper Constraints

### `computeNoteCommitment`

- rejects zero owner
- rejects zero value
- accepts caller-provided salt only as a helper input

### `computeNullifier`

- rejects zero owner
- rejects zero value
- accepts caller-provided salt only as a helper input

## 6. CLI-Imposed Constraints

The CLI may intentionally restrict available shapes further than Solidity does.

Examples:

- some assistant flows expose only the transfer shapes that are currently registered on the selected network
- wallet recovery and note scanning assume current workspace metadata is consistent with the active bridge deployment

Therefore three layers of support must be distinguished:

- Solidity entrypoint support
- DApp registration support
- CLI/assistant UX support

## 7. Snapshot and Proof Constraints

Any proof input bundle used for a private-state function must satisfy:

- `previous_state_snapshot.json` contains the full managed storage vector
- `block_info.json` matches the channel's public block context model
- `contract_codes.json` matches the runtime code of the managed storage contracts
- the function preprocess hash must match the bridge-registered metadata for that function

If any of those differ, the bridge can reject the transaction even if the Solidity entrypoint itself is valid.

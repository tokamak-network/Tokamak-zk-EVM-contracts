# Contract Specification

## 1. Contract Set

The `private-state` DApp is implemented with two storage contracts:

- `L2AccountingVault`
- `PrivateStateController`

`PrivateStateController` is the user-facing application entrypoint.
`L2AccountingVault` is an accounting-only balance store controlled by the controller.

## 2. L2AccountingVault

### Purpose

`L2AccountingVault` tracks per-account liquid balances on L2. It is not a custody vault.

### Storage

- `mapping(address => uint256) liquidBalances`
- `address immutable controller`

### Rules

- only the controller may mutate balances
- zero address is rejected
- zero amount is rejected
- all credits are bounded by the BLS12-381 scalar field order
- debits must not underflow

### Semantics

- `creditLiquidBalance(account, amount)` increases accounting balance
- `debitLiquidBalance(account, amount)` decreases accounting balance

No direct user-facing `deposit` or `withdraw` functions exist on the vault itself.

## 3. PrivateStateController

### Purpose

`PrivateStateController` defines the note lifecycle:

- mint notes from liquid balance
- transfer notes
- redeem notes back into liquid balance
- expose note commitment and nullifier reconstruction helpers

### Storage

- `mapping(bytes32 => bool) commitmentExists`
- `mapping(bytes32 => bool) nullifierUsed`
- `L2AccountingVault immutable l2AccountingVault`

### Note Shapes

```solidity
struct Note {
    address owner;
    uint256 value;
    bytes32 salt;
}

struct TransferOutput {
    address owner;
    uint256 value;
    bytes32[3] encryptedNoteValue;
}

struct MintOutput {
    uint256 value;
    bytes32[3] encryptedNoteValue;
}
```

### Event Model

The controller emits:

```solidity
event NoteValueEncrypted(bytes32[3] encryptedNoteValue);
```

One event is emitted for each encrypted output in mint and transfer paths.

The event intentionally does not include:

- recipient owner
- commitment
- nullifier
- ciphertext hash as a separate field

The opaque encrypted payload is the delivery object. The note salt is derived from it rather than emitted separately.

## 4. Mint Semantics

Mint entrypoints are fixed-arity:

- `mintNotes1`
- `mintNotes2`
- `mintNotes3`
- `mintNotes4`
- `mintNotes5`
- `mintNotes6`

Each output:

- uses `msg.sender` as the owner
- stores `value`
- derives `salt = hash(encryptedNoteValue)`
- derives `commitment = H(owner, value, salt)`

The total minted value is debited from `L2AccountingVault.liquidBalances[msg.sender]`.

## 5. Transfer Semantics

Transfer entrypoints are fixed-shape note transforms:

- `transferNotes1To1`
- `transferNotes1To2`
- `transferNotes1To3`
- `transferNotes2To1`
- `transferNotes2To2`
- `transferNotes3To1`
- `transferNotes3To2`
- `transferNotes4To1`

Each output:

- carries an `owner`
- carries a `value`
- carries an opaque encrypted payload
- derives `salt = hash(encryptedNoteValue)`
- derives commitment from `(owner, value, salt)`

Each input note:

- must belong to `msg.sender`
- must already exist as a commitment
- must not already be nullified

The contract enforces exact conservation:

- `sum(input values) == sum(output values)`

## 6. Redeem Semantics

Redeem entrypoints are fixed-arity:

- `redeemNotes1`
- `redeemNotes2`
- `redeemNotes3`
- `redeemNotes4`

Each redeem path:

- validates each input note
- nullifies each input
- sums redeemed value
- credits `receiver` in `L2AccountingVault`

## 7. Commitment and Nullifier Construction

The controller exposes:

- `computeNoteCommitment(value, owner, salt)`
- `computeNullifier(value, owner, salt)`

The fixed domains are:

- `PRIVATE_STATE_NOTE_COMMITMENT`
- `PRIVATE_STATE_NULLIFIER`

The implementation writes fixed-shape words into memory and hashes them in a direct assembly path.

## 8. Public Constraints Embedded in Storage

The controller stores two public truth tables:

- whether a commitment currently exists
- whether a nullifier was already used

These are used by:

- note spending
- wallet reconciliation
- event-driven note recovery

## 9. Managed Storage Vector

For bridge coupling, the DApp's managed storage vector is defined by the storage-layout manifest rather than by arbitrary deployment addresses.

For the current DApp, the managed storage contracts are:

- `PrivateStateController`
- `L2AccountingVault`

This same storage vector must be used consistently by:

- bridge DApp registration
- Synthesizer launch inputs
- CLI workspace snapshots
- compatibility fixtures

## 10. Deployment Artifacts

Successful deployments write app-local artifacts under `packages/apps/private-state/deploy`:

- deployment manifests
- storage-layout manifests
- callable ABI JSON files
- proving-key metadata
- Synthesizer layout artifacts

These artifacts drive both bridge registration and CLI proof-generation workflows.

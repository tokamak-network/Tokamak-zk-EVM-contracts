# Contract Specification

## 1. Contract Set

The `private-state` DApp is implemented with two storage contracts:

- `L2AccountingVault`
- `PrivateStateController`

`PrivateStateController` is the user-facing application entrypoint.
`L2AccountingVault` is an accounting-only balance store controlled by the controller.

The split is intentional. `PrivateStateController` owns the note lifecycle and exposes the functions
that users model in the proving environment. `L2AccountingVault` owns only liquid accounting
balances. Keeping the accounting store separate makes the bridge-coupled vault surface explicit and
keeps note logic from becoming implicit custody logic.

## 2. L2AccountingVault

### Purpose

`L2AccountingVault` tracks per-account liquid balances on L2. It is not a custody vault.

In this document, "liquid" means bridge-accountable value that is immediately usable for minting
notes or for bridge withdrawal accounting. It does not mean that the L2 vault holds the canonical
token. Canonical custody remains in the L1 bridge vault.

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

Example: a bridge-accepted deposit increases liquid balance through the bridge execution path. A user
does not call `L2AccountingVault` directly to mint assets. Conversely, redeeming notes credits liquid
balance inside this vault, but the user still needs the bridge withdrawal flow to move canonical
tokens back to L1.

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

This event is deliberately small. It tells recipients that an encrypted delivery object exists, but
it does not reveal who the recipient is or which note commitment was produced. The recipient's CLI
must decrypt candidate payloads, reconstruct the note, and check the resulting commitment against
accepted state.

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

The important effect is a value-form conversion. Minting does not create new bridge value. It debits
the caller's liquid accounting balance inside the channel and creates note commitments that represent
the same total value.

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

Transfer is therefore a note reshape, not a mint. The input notes are consumed by writing their
nullifiers, and the output notes are created by writing new commitments. The sender cannot increase
total value by choosing more outputs or larger output values.

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

Redeem is the reverse value-form conversion of mint. It consumes private notes and recreates liquid
accounting balance. It still does not transfer canonical tokens to L1 by itself.

## 7. Commitment and Nullifier Construction

The controller exposes:

- `computeNoteCommitment(value, owner, salt)`
- `computeNullifier(value, owner, salt)`

The fixed domains are:

- `PRIVATE_STATE_NOTE_COMMITMENT`
- `PRIVATE_STATE_NULLIFIER`

The implementation writes fixed-shape words into memory and hashes them in a direct assembly path.

Domain separation prevents the same plaintext tuple from being interpreted as both a commitment and
a nullifier under the same hash domain. The helper functions exist so off-chain tools can reproduce
the exact identifiers that the contract uses.

## 8. Public Constraints Embedded in Storage

The controller stores two public truth tables:

- whether a commitment currently exists
- whether a nullifier was already used

These are used by:

- note spending
- wallet reconciliation
- event-driven note recovery

Together these mappings define note liveness. A note can be considered available for use only when
its commitment exists and its nullifier has not been used. Wallets should treat both mappings as
part of state reconciliation, not as optional display data.

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

The order matters because bridge public inputs refer to storage trees by index. If two tools use the
same addresses in a different order, they are no longer describing the same root vector.

## 10. Deployment Artifacts

Successful deployments write chain-scoped app artifacts under
`deployment/chain-id-<chain-id>/dapps/private-state/<timestamp>/`:

- deployment manifests
- storage-layout manifests
- callable ABI JSON files
- DApp registration manifests after bridge registration
- source snapshots used by the registration artifact

These artifacts drive both bridge registration and CLI proof-generation workflows.

# Background Theory

## 1. System Model

`private-state` is a bridge-coupled zk-note payment DApp for the Tokamak Network Token.

The system is split across two domains:

- L1 holds canonical custody of the token through the bridge vault.
- The proving-based L2 holds only accounting state and note state.

The DApp never treats L2 as a second canonical custody layer. The L2 side stores balances, commitments, nullifiers, and proof-linked state roots only.

## 2. zk-L2 Assumptions

The DApp is designed for the Tokamak proving environment rather than for direct public Ethereum execution.

The important assumptions are:

- Users generate proofs locally from private transaction inputs.
- L1 verifies proofs and accepts resulting state transitions.
- Raw user calldata is not treated as public protocol state by default.
- Runtime `keccak256(...)` behavior in the modeled L2 environment is mirrored by TokamakL2JS Poseidon-based hashing rather than Ethereum L1 hashing semantics.
- Transaction signing and public-key recovery follow the Tokamak L2 EdDSA-compatible model exposed by `tokamak-l2js`.

This means that privacy review must focus on state, events, public inputs, and proof-linked metadata rather than on public mempool calldata alone.

## 3. Value Representation

The DApp uses two value representations:

- liquid accounting balance in `L2AccountingVault`
- discrete zk-notes in `PrivateStateController`

Liquid balance is the only form that can cross the bridge accounting boundary directly. Notes are the private-state application object used for transferability inside the channel.

## 4. Notes

A note plaintext is:

- `owner`
- `value`
- `salt`

From that plaintext the DApp derives:

- note commitment
- nullifier

The current contract implementation treats commitments and nullifiers as cryptographic digests over fixed-shape inputs.

## 5. Accounting to Note Flow

The normal user flow is:

1. deposit canonical token into the shared bridge vault on L1
2. join a channel-specific L2 identity
3. move value into the channel L2 accounting balance
4. mint notes from liquid balance
5. transfer notes by consuming old notes and creating new ones
6. redeem notes back into liquid balance
7. move value back to the shared bridge vault
8. withdraw the canonical token to the user's L1 wallet

The system therefore separates:

- bridge liquidity management
- L2 accounting management
- note lifecycle management

## 6. Why Notes Need an Auxiliary Delivery Channel

The recipient cannot spend a note without reconstructing its plaintext.

If the sender were allowed to choose and keep the output salt privately, the recipient could end up with a note that exists on-chain but cannot be reconstructed locally. That would break liveness.

The implemented solution binds encrypted note data to the note itself:

- the sender publishes an opaque `bytes32[3] encryptedNoteValue`
- the contract derives `salt = hash(encryptedNoteValue)`
- the note commitment is computed from `(owner, value, salt)`

That removes sender control over an undisclosed recipient salt and makes the note reconstructible from the encrypted payload.

## 7. Note-Receive Auxiliary Keys

The DApp uses a second channel-scoped key family for note delivery:

- `noteReceivePubKey`
- `noteReceivePrivateKey`

These are not separately backed up by the user. They are deterministically derived from the user's Ethereum key through a fixed EIP-712 typed-data signing flow.

This gives the protocol a recipient-discoverable encryption target without forcing the user to manage an independent long-lived secret manually.

## 8. Ownership vs Readability

The implementation distinguishes between:

- reading note contents
- owning a note in the stronger sense of being able to use it

Reading note contents depends on the note-receive key.

Using a note depends on the channel-bound L2 identity, because note spending, transfer, and redemption require the wallet's derived `l2PrivateKey`.

Under the current CLI model, losing the wallet password means losing the ability to derive the channel-bound `l2PrivateKey`, which means losing note ownership in the stronger sense even if note ciphertexts can still be recognized or decrypted.

## 9. Protocol Assumptions and Risks

The note-receive derivation model depends on a frozen signing rule:

- the exact EIP-712 domain
- type name
- field order
- field encoding
- signing RPC method

The implementation fixes this derivation to a MetaMask-compatible typed-data signing path. If a wallet later returns different signature bytes for the same account and typed data, deterministic recovery would break.

That assumption is therefore a protocol dependency, not a generic property of all Ethereum wallets.

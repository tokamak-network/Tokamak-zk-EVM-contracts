# Private-State Background Theory

## 1. System Model

`private-state` is a bridge-coupled zk-note payment DApp for the Tokamak Network Token.

The system is split across two domains:

- L1 holds canonical custody of the token through the bridge vault.
- The proving-based L2 holds only accounting state and note state.

The DApp never treats L2 as a second canonical custody layer. The L2 side stores balances, commitments, nullifiers, and proof-linked state roots only.

This split is the first idea to keep in mind while reading the rest of the documentation. A user can
have value represented in several ways while using the channel, but the only canonical token custody
is still the L1 bridge vault. The L2 objects are accounting and privacy objects that become valid
only when the bridge accepts the corresponding proof-backed state transition.

Example: after a user deposits into the bridge and moves value into the channel, the user's L1 token
is held by the L1 vault. The L2 accounting balance records that the user can mint notes or later
withdraw through the bridge path. It is not a separate token contract that independently owns the
canonical asset.

The DApp is therefore an opt-in application-state layer, not a change to the TON asset itself. TON
remains a transparent L1 asset at exchange and bridge custody edges. A private-state note is a
channel-local representation inside this DApp, and it is not a separate asset that an exchange
supports as a deposit network.

Users are expected to enter a channel from a self-custody L1 wallet. An exchange deposit
address should not be treated as a private-state wallet address because the exchange does not hold
the user's channel-local spending key, viewing key, or private-state workspace.

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

`Liquid balance` means a public per-L2-address accounting value inside the channel's accounting
vault. It is the form used for bridge-coupled deposit and withdrawal accounting.

`Note` means a discrete private-state object that carries value in a form suitable for private
transfer. A note can move between users inside the DApp, but it cannot be withdrawn to L1 directly.
It must first be redeemed back into liquid balance.

Example: if Alice has `100` units of liquid balance, she may mint two notes of `40` and `60`. Those
notes can be transferred privately inside the channel. If Alice or a later recipient wants to exit to
L1, the relevant notes must first be redeemed into liquid balance, and then the liquid balance can be
withdrawn through the bridge.

## 4. Notes

A note plaintext is:

- `owner`
- `value`
- `salt`

From that plaintext the DApp derives:

- note commitment
- nullifier

The current contract implementation treats commitments and nullifiers as cryptographic digests over fixed-shape inputs.

The three fields have different roles:

- `owner` is the L2 address that is allowed to spend the note.
- `value` is the amount represented by the note.
- `salt` separates otherwise identical notes and binds the note to the encrypted delivery payload.

The `commitment` is the public marker that says "this note exists" without revealing the plaintext.
The `nullifier` is the public marker that says "this note has been consumed" without revealing the
plaintext. A note is usable only if its commitment exists and its nullifier has not yet been used.

Example: two notes may have the same owner and value. They remain distinct because their salts differ,
which produces different commitments and nullifiers.

## 5. Accounting to Note Flow

The normal user flow is:

1. join a channel-specific L2 identity, paying any join toll directly from the L1 wallet
2. deposit canonical token into the shared bridge vault on L1 for channel liquidity
3. move that value into the channel L2 accounting balance
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

The problem is not only secrecy. It is recoverability. A recipient must be able to learn enough
private note data to later prove ownership and spend or redeem the note. A system that creates a
valid commitment but withholds the plaintext from the recipient would preserve a public state
transition while destroying the recipient's practical ability to use the note.

The implemented solution binds encrypted note data to the note itself:

- the sender publishes an opaque `bytes32[3] encryptedNoteValue`
- the contract derives `salt = hash(encryptedNoteValue)`
- the note commitment is computed from `(owner, value, salt)`

That removes sender control over an undisclosed recipient salt and makes the note reconstructible from the encrypted payload.

Example: if Bob receives a note, Bob's CLI scans bridge-propagated logs, decrypts the encrypted
payload with Bob's note-receive key, derives the salt from that payload, and reconstructs the same
commitment that the contract stored. Bob does not need Alice to send an extra sidecar file later.

## 7. Note-Receive Auxiliary Keys

The DApp uses a second channel-scoped key family for note delivery:

- `noteReceivePubKey`
- `noteReceivePrivateKey`

The public key is registered on-chain during channel join. The private key is the wallet's viewing
key: it decrypts encrypted note-delivery events for that registered channel identity, but it does
not authorize note spending.

The CLI can derive the viewing key from the user's Ethereum key through a fixed EIP-712 typed-data
signing flow, and it can also export or import the viewing key as a separate protected `.key` file.
This gives the protocol a recipient-discoverable encryption target while keeping viewing authority
separate from spending authority.

## 8. Ownership vs Readability

The implementation distinguishes between:

- reading note contents
- owning a note in the stronger sense of being able to use it

Reading note contents depends on the note-receive key.

Using a note depends on the channel-bound L2 identity, because note spending, transfer, and redemption require the wallet's derived `l2PrivateKey`.

Under the current CLI model, the wallet backup does not contain the viewing key, the spending key,
or plaintext note `owner`, `value`, and `salt` fields. A backup restores encrypted tracking state,
commitments, nullifiers, and channel cache data. The viewing key restores readability. The spending
key restores spendability.

This distinction is important for recovery language. A user may still be able to see that an
encrypted output was meant for them, but that is not enough to spend the note. Spendability requires
the L2 private key that corresponds to the note owner.

The same distinction defines the DApp's disclosure model. Public observers can see bridge-edge
activity, channel registration, accepted transitions, commitments, nullifiers, and encrypted delivery
events. They do not automatically obtain the note plaintext or the user's complete note provenance
chain. In the current private-state design, selective disclosure is user-controlled and depends on
evidence the user can produce from local wallet state and implemented tooling.

## 9. Protocol Assumptions and Risks

The note-receive derivation model depends on a frozen signing rule:

- the exact EIP-712 domain
- type name
- field order
- field encoding
- signing RPC method

The implementation fixes this derivation to a MetaMask-compatible typed-data signing path. If a wallet later returns different signature bytes for the same account and typed data, deterministic recovery would break.

That assumption is therefore a protocol dependency, not a generic property of all Ethereum wallets.

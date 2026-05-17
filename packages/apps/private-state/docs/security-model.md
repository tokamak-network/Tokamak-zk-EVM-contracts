# Private-State Security Model

This document describes the security model for the `private-state` DApp. It includes the bridge
security assumptions inherited by the DApp, the local CLI security model, and the note-specific
risks that follow from finite leaf projection.

The document separates three questions that are easy to confuse:

- who has custody of canonical tokens
- who can produce or recover the secrets needed to use notes
- whether the finite Merkle leaf domain can block an otherwise valid state transition

The first question is answered by the bridge. The second is answered by the CLI wallet and key
derivation model. The third is a capacity and liveness issue inherited from the bridge storage model.

## 1. Security Boundaries

The DApp inherits the bridge's core security boundary:

- L1 keeps canonical token custody through the shared bridge vault.
- The DApp stores L2 accounting state and private note state only.
- Users generate proofs locally from private inputs.
- L1 accepts state transitions only after bridge-side proof and metadata checks pass.
- A channel is governed by the DApp metadata, verifier snapshot, function root, managed storage
  vector, and join-toll policy that were fixed when that channel was created.

In this document, `security boundary` means the line beyond which the DApp does not claim direct
control. For example, `private-state` can define how notes are minted, transferred, and redeemed, but
it does not define who may upgrade the bridge root contracts or whether the canonical token keeps
exact-transfer behavior.

The DApp itself adds three local secret domains:

- the user's Ethereum private key
- the channel-bound L2 private key
- the channel-scoped note-receive private key

The wallet secret source file is not a persisted wallet unlock password. The CLI reads it once
during `channel join`, combines it with the user's Ethereum signer and channel context, and derives
the channel-bound L2 private key. After that point, wallet backup metadata, viewing authority, and
spending authority are managed as separate artifacts.

## 2. Bridge-Inherited Security Model

`private-state` is not a standalone custody system. It relies on the bridge for custody, verifier
selection, DApp metadata registration, channel creation, and proof acceptance.

The important inherited properties are:

- Ethereum is the custody and validity anchor.
- DApp execution is admitted through registered bridge metadata, not through arbitrary runtime ABI
  interpretation.
- Existing channels keep their own immutable policy snapshot.
- Future DApp metadata or verifier updates affect future channels, not already-created channels.
- The canonical asset must behave like an exact-transfer token.
- The bridge owner remains a privileged root operator for UUPS upgrades and future policy updates.

For `private-state`, this means a user should treat channel creation and channel joining as policy
acceptance. The user is accepting the channel's DApp metadata digest, function root, verifier
snapshot, compatible backend versions, managed storage vector, and join-toll policy.

If a bad policy is discovered after a channel is created, the expected recovery path is operational:
announce the affected channel, stop using it, redeem or withdraw through supported flows, and create
a new channel with corrected policy. The existing channel's policy is not meant to be silently
rewritten by a later bridge upgrade.

## 3. Public Policy And Operator Authority

The current `private-state` DApp adopts a user-controlled privacy and disclosure model. It should be
presented as an opt-in application channel used from self-custody wallets, not as a private
exchange deposit network and not as a change to TON's L1 transfer rules.

For this DApp, the public monitoring surface includes:

- L1 bridge deposits and withdrawal claims
- channel creation and immutable policy snapshots
- channel join and token-vault identity registration
- accepted proof-backed transitions
- root-vector movement and observed storage writes
- commitments, nullifiers, and encrypted note-delivery events surfaced by the DApp
- bridge verifier, DApp metadata, and upgrade events

That monitoring surface is intentionally not the same as a complete note provenance graph. It is the
specific disclosure surface programmed by the current `private-state` DApp, not a bridge-wide rule
for every DApp. Public observers can see that accepted activity occurred and can inspect the
bridge-visible outputs, but they do not automatically learn every note plaintext, sender-recipient
relationship, or note ownership history.

The channel leader's authority is limited by the bridge and DApp policy snapshot. For
`private-state`, the leader does not custody user TON, does not hold user wallet secret source
files, does not hold note-spending keys, does not hold note-receive private keys, does not
intermediate user note transfers, and does not have a protocol backdoor to reconstruct all private
note provenance. Channel
leaders may operate public metadata or availability services, such as a workspace mirror, but those
services are availability aids rather than custody or viewing authorities.

Selective disclosure is therefore user-controlled in the current DApp. A user may disclose selected
wallet-derived evidence where implemented tooling supports it. Documentation and external
communication should not imply that Tokamak, a channel leader, an exchange, or an auditor
can reconstruct every private-state transfer from public logs alone.

## 4. Finite Leaf Projection Inherited From The Bridge

The bridge maps storage keys into a finite Merkle leaf domain. Let:

- `d` be the Merkle tree depth
- `N = 2^d` be the leaf domain size
- `t` be the channel operating period
- `lambda` be the average arrival rate of new storage keys that attempt to occupy leaves
- `mu(t) = lambda t` be the expected number of arrived keys

The operational risk is time-dependent. A live channel accumulates storage keys, so the relevant
question is not only whether a static set of keys collides. It is whether at least one collision
appears during the channel's lifetime.

In this document, `leaf collision` means that two different storage keys project to the same finite
Merkle leaf index. It does not mean that the original 256-bit storage keys are equal. The collision
comes from compressing a large key space into a finite tree domain.

Example: if two unrelated storage keys both map to leaf index `42`, the bridge-managed tree cannot
represent them as two independent live leaves at that index. A proof that needs to write the second
key may become unacceptable even if the DApp-level Solidity logic is otherwise valid.

Under a Poissonized occupancy model, each leaf receives an independent Poisson count with mean
`mu(t) / N`. No collision has occurred by time `t` exactly when every leaf has received zero or one
arrival:

$$
\Pr[\text{no collision by } t]
= \left(e^{-\mu(t)/N}\left(1+\frac{\mu(t)}{N}\right)\right)^N
= e^{-\mu(t)}\left(1+\frac{\mu(t)}{2^d}\right)^{2^d}
$$

Therefore:

$$
\Pr[\text{at least one leaf collision by } t]
= 1 - e^{-\mu(t)}\left(1+\frac{\mu(t)}{2^d}\right)^{2^d}
$$

For `mu(t) << 2^d`, this is approximated by:

$$
\Pr[\text{at least one leaf collision by } t]
\approx 1 - \exp\left(-\frac{\mu(t)^2}{2\cdot 2^d}\right)
$$

The graph below uses `lambda = 1/minute`, so `mu(t) = 1440t` when `t` is measured in days.

![General channel lifespan leaf collision probability](../../../../bridge/docs/assets/general_leaf_collision_probability_lifespan_days_lambda1m_d12_36_step6.svg)

For the current `d = 36` setting, this model gives a materially longer but still finite
channel-lifespan capacity limit. It is not a statement that any particular note is likely to fail
immediately. It is a statement that a channel with growing storage usage should not be treated as
collision-free forever.

## 5. Future Nullifier Collision Probability

The note-specific risk is different from the general channel collision risk.

The important distinction is between a retryable creation-time failure and a post-creation liveness
failure.

When a note is created, the DApp immediately writes its commitment. If the commitment leaf collides
with an existing occupied leaf, the transaction cannot be accepted in the normal flow. That failure
happens before the note becomes a valid unused note. The user or wallet can construct a different
output, for example by changing the encrypted payload and therefore the salt, and retry.

The nullifier has a different timing profile. A note's nullifier is already determined by the note
plaintext:

- `owner`
- `value`
- `salt`

However, the nullifier is not written until the note is spent, transferred, or redeemed. Therefore an
accepted unused note has a fixed future nullifier leaf that remains exposed while the note is held.
If a later unrelated storage key occupies that leaf before the owner spends the note, the owner
cannot change the nullifier without changing the note itself. But changing the note would also change
the commitment, so it would no longer be the already-accepted note.

This is why future nullifier collision is more severe than commitment collision:

- commitment collision is detected before the note becomes valid, so it is a retryable creation
  failure
- future nullifier collision can occur after the note is already valid, so it can strand an otherwise
  valid unused note

Example: Alice mints a note and the commitment is accepted. The note is now real channel state. Alice
waits before redeeming it. During that waiting period, other channel activity introduces new storage
keys. If one of those keys lands on Alice's future nullifier leaf, Alice's later redeem attempt may
fail because the nullifier write cannot be accepted for that already-occupied leaf. Alice cannot
choose a new nullifier for that same note.

Assume:

- the note has already been accepted
- the note commitment collision was already avoided at creation time
- the remaining target is one fixed future nullifier leaf
- future storage keys arrive as a Poisson process with rate `lambda`
- each future key is effectively uniform over `N = 2^d` leaves

For one future key:

$$
\Pr[\text{collision with the note's future nullifier leaf}]
= \frac{1}{N}
= 2^{-d}
$$

Let `M(t)` be the number of future keys that arrive before the note is spent:

$$
M(t) \sim \operatorname{Poisson}(\lambda t)
$$

By Poisson thinning, the number of future keys that hit this one nullifier leaf is:

$$
M_{\text{hit}}(t) \sim \operatorname{Poisson}\left(\frac{\lambda t}{N}\right)
$$

Therefore:

$$
\Pr[\text{future nullifier collision by } t]
= 1 - \Pr[M_{\text{hit}}(t)=0]
= 1 - \exp\left(-\frac{\lambda t}{N}\right)
$$

Substituting `N = 2^d`:

$$
\Pr[\text{future nullifier collision by } t]
= 1 - \exp\left(-\lambda t \cdot 2^{-d}\right)
$$

If `t` is measured in days and `lambda = 1/minute`, the plotted model is:

$$
\Pr[\text{future nullifier collision by day } t]
= 1 - \exp\left(-1440t\cdot 2^{-d}\right)
$$

The expected collision time for one fixed future nullifier leaf is:

$$
\mathbb{E}[T] = \frac{2^d}{\lambda}
$$

![Future nullifier collision probability](assets/future_nullifier_collision_probability_days_lambda1m_d12_36_step6_logy.svg)

This risk is lower than the general channel-wide probability of any leaf collision because it tracks
one fixed target leaf, not any pair among all occupied leaves. It is still security-relevant because
the consequence is note liveness loss: a valid unused note may later become unspendable.

The practical conclusion is that note age matters. A note that is created and redeemed quickly has
less exposure to future unrelated storage keys. A note held for a long time remains exposed for a
longer period.

## 6. Separated Wallet Capabilities

The current CLI separates wallet state from wallet authority. This separation is part of the user
security model because a backup should not, by itself, become a transferable full-control wallet.

The wallet workspace contains non-authorizing wallet backup metadata:

- channel and registration metadata
- note commitments and nullifiers
- encrypted note-delivery payloads
- note scan checkpoints and local operation history
- channel workspace cache needed for local reconstruction

The backup metadata intentionally excludes spending keys, viewing keys, derivation material, and
plaintext note `owner`, `value`, and `salt` fields. A third party that obtains only a wallet backup
can inspect or restore the encrypted tracking state, but cannot decrypt note events or spend notes.

Viewing authority is exported and imported separately with `wallet export viewing-key` and
`wallet import viewing-key`. The viewing key is the channel-scoped note-receive private key. It lets
the holder decrypt encrypted note-delivery events and reconstruct note plaintext for notes addressed
to the registered note-receive public key. It does not authorize note spending.

Spending authority is exported and imported separately with `wallet export spending-key` and
`wallet import spending-key`. The spending key is the channel-bound L2 private key. It authorizes
proof-backed note use and L2 channel-accounting operations for the registered wallet identity. It
does not, by itself, decrypt encrypted note-delivery events.

This creates three operational restore levels:

- backup only: restore encrypted tracking state and channel cache, with no viewing or spending
  authority
- backup plus viewing key: reconstruct the note view from encrypted events, but do not spend notes
- backup plus viewing key plus spending key: operate the wallet in the normal CLI note flow

Commands that only inspect registration metadata can run from backup metadata. Commands that decrypt
or refresh received notes require the viewing key. Commands that create or consume notes require the
spending key and also require the viewing key so the CLI can refresh the readable note workspace from
event logs after accepted note transactions.

## 7. Channel-Bound L2 Identity

The channel-bound L2 identity is derived by asking the Ethereum signer to sign a deterministic
message that includes:

- a fixed domain string
- the channel name
- the wallet secret source content

From that signature, the CLI derives:

- `l2PrivateKey`
- `l2PublicKey`
- `l2Address`

The resulting `l2PrivateKey` is the wallet's spending key. It is stored as a protected key file and
can be moved separately from wallet backup metadata. If both the spending-key file and the
derivation inputs needed to recreate it are lost, notes cannot be spent, transferred, or redeemed.
Under the CLI's strict ownership definition, losing the spending key means losing note ownership in
the spendable sense.

## 8. Note-Receive Auxiliary Keys

The note-receive key pair is different from the channel-bound L2 identity.

It is derived from a fixed EIP-712 typed-data signing flow over:

- protocol label
- chain id
- channel id
- channel name
- DApp label
- Ethereum account

The resulting note-receive public key is registered on-chain during channel registration.

The two key families have different roles:

- `l2PrivateKey` proves note ownership and is required for spending, transfer, and redemption flows.
- `noteReceivePrivateKey` decrypts encrypted note-delivery payloads from emitted events and supports
  recipient-side note discovery.

This separation allows incoming note delivery to be recovered from Ethereum logs without using the
note-spending key as the delivery key.

Example: Bob can use the note-receive private key to discover that an encrypted output belongs to
him. Bob still needs the L2 private key to transfer or redeem that note. Discovery and spendability
are deliberately separate.

## 9. Recovery Model

If wallet backup metadata is lost, recovery is still possible if the user retains:

- the Ethereum private key
- the correct channel context
- the viewing key, or the ability to reproduce the registered note-receive key
- the spending key, or the derivation inputs needed to recreate it

With those inputs, the CLI can reconstruct or restore:

- the channel-bound L2 identity
- the note-receive key material
- wallet backup metadata from on-chain registration and bridge-propagated event logs

Importing a backup alone does not grant wallet authority. The imported backup restores encrypted
tracking state, commitments, nullifiers, and channel cache files. The user must also import the
viewing key to decrypt note events and the spending key to operate notes.

If the viewing key is lost:

- existing backup metadata can still preserve encrypted note payloads and public note markers
- new event-log recovery cannot decrypt notes addressed to that viewing key
- notes are not spendable through the normal CLI note flow unless their plaintext is otherwise
  available to the wallet tooling

If the spending key is lost:

- readable notes remain readable if the viewing key is present
- the notes can no longer be spent, transferred, or redeemed
- note ownership, in the strict spendable sense, is lost

This can look counterintuitive. A user may still see note data but be unable to spend it. The reason
is that readable note plaintext is not the same as the L2 private key required to authorize note use.

If both the viewing key and spending key are stolen, the attacker can reconstruct the user's note
view and operate spendable notes. A backup file increases the attacker's convenience by providing
local note-tracking state, but it is not the authority-bearing artifact by itself.

## 10. Protocol Risks And Recommendations

The note-receive derivation model depends on deterministic reproduction of the same typed-data
signature bytes for the same account and typed-data payload. If that property fails for a wallet
implementation, the same note-receive private key may not be recoverable later and encrypted note
delivery recovery can fail.

Operational recommendations:

- protect viewing-key and spending-key exports as sensitive authority-bearing files
- keep wallet backups separate from key exports when storing or transmitting them
- treat a backup plus viewing key plus spending key as a full operational wallet restore set
- protect the wallet secret source file if it is kept after `channel join`, because it may help
  recreate the spending key with the same account and channel context
- back up the Ethereum private key separately from the local workspace
- do not assume that being able to read a note implies being able to spend it
- treat long-lived unused notes as having increasing future-nullifier exposure
- prefer redeeming or rotating notes when a channel is expected to run for a long time

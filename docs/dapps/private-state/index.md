# Private-State DApp Documentation

This directory contains the design, protocol, security, and implementation documents for the `private-state` DApp.

## Quick Answers

### What is the private-state DApp?

`private-state` is a bridge-coupled zk-note payment DApp for Tokamak Private App Channels. It keeps
canonical token custody on L1 through the bridge, while channel-local accounting balances, note
commitments, nullifiers, and encrypted note-delivery events live in proof-backed confidential
application state.

The official TON airdrop campaign for Tonnel, the public name for `the-great-first-channel`, is
<https://airdrop.tonnel.io>.

### What privacy does it provide?

The DApp provides privacy-preserving note semantics, not invisible activity. It hides note ownership
and note-transfer meaning from public contract state, but observers can still see the public
disclosure surface that this DApp programs: accepted bridge transitions, changed storage
commitments, nullifier usage, and encrypted note-delivery events. Recipients need local secret
material to decide which encrypted notes are theirs.

### Is it an exchange deposit network?

No. TON custody and exchange-facing TON transfers remain on the transparent L1 token surface.
`private-state` is an opt-in application channel used from a self-custody L1 wallet after the user
has left any exchange custody path. Private-state notes are channel-local application
state, not exchange-supported deposit assets.

### Who controls disclosure in the current private-state DApp?

The current `private-state` DApp uses a user-controlled disclosure model. Tokamak, the bridge
operator, and the channel leader are not designed to hold the user's spending key, viewing key, or a
master viewing key. A user may selectively disclose evidence
from local wallet state where implemented tooling supports it, but public logs alone are not meant to
reconstruct every private note provenance chain.

### How are wallet backups different from wallet keys?

Wallet backups are non-authorizing recovery artifacts. They contain wallet note-tracking metadata,
commitments, nullifiers, encrypted note-delivery payloads, scan checkpoints, and channel workspace
cache files, but they do not contain viewing keys, spending keys, derivation material, or plaintext
note `owner`, `value`, and `salt` fields. Viewing keys and spending keys are exported and imported
as separate protected `.key` files so read access and spend authority can be shared or restored
independently.

### How should this DApp be positioned?

Use the following positioning terms consistently:

- `proof-backed confidential application state`: private-state activity is accepted through proofs,
  not through a trusted operator transcript.
- `L1-transparent bridge edge`: bridge deposits, withdrawals, and custody movements remain on the
  transparent L1 surface.
- `user-controlled private note state`: note ownership and note recovery depend on user-held local
  secrets.
- `selective disclosure capable architecture`: disclosure is user-controlled where implemented
  wallet tooling supports selected evidence export.
- `privacy-preserving DApp channel`: this is an opt-in DApp channel, not an exchange
  deposit network and not a change to TON's L1 transfer rules.
- `TON custody remains anchored on L1`: the canonical token stays under the bridge's L1 custody
  boundary while channel-local state records accounting and notes.
- `internal note transfer privacy, transparent L1 entry/exit`: note-transfer provenance is private
  by design, while bridge entry and exit remain public L1 events.

### What should users check before joining a channel?

Users should review the channel's immutable policy snapshot before joining. The important fields are
the DApp metadata digest, digest schema, function metadata root, verifier addresses, compatible
backend versions, join toll, refund policy, and channel operator role. Joining a channel means
accepting that policy for the channel lifetime.

## Reading Order

1. [Private-State Background Theory](background-theory.md)
   Start here. Defines the custody model, zk-L2 assumptions, liquid accounting balance, notes, note
   commitments, nullifiers, and the ownership-versus-readability distinction.
2. [Private-State Contract Specification](contract-spec.md)
   Maps the concepts from the background document to the two Solidity contracts, their storage, and
   their public state-transition semantics.
3. [Private-State Function Constraints](function-constraints.md)
   Explains why the user-facing entrypoints are fixed-arity and lists the validity constraints that
   each mint, transfer, and redeem shape must satisfy.
4. [Private-State Security Model](security-model.md)
   Documents bridge-inherited security assumptions, finite leaf collision risk, future nullifier collision probability, separated wallet capabilities, channel-bound L2 derivation, note-receive key derivation, and recovery behavior.
5. [Private-State Workflow](workflow.md)
   Describes the CLI workflow, wallet/workspace artifacts, bridge registration metadata, proof input bundle format, event recovery flow, and bridge-DApp execution coupling.
6. [Channel Workspace Mirror Protocol](channel-workspace-mirror-protocol.md)
   Defines the optional static server protocol that channel leaders can use to publish signed
   workspace checkpoints and delta bundles for old channels.

The intended reading path moves from concepts, to contracts, to per-function constraints, to
security assumptions, and finally to end-to-end workflow. A reader who only needs operational
sequence can read [Workflow](workflow.md) after the first three sections of
[Background Theory](background-theory.md), but security-sensitive operation requires the full set.

## Scope

These documents cover:

- the protocol background and trust assumptions
- the private-state contract interfaces and invariants
- the bridge-coupled execution model
- the CLI and proof-generation workflow
- the note-receive key architecture
- the fixed-circuit function shape used by the implementation

They do not replace operator runbooks or deployment command references. Operational quickstart material remains in the app README and script help output.

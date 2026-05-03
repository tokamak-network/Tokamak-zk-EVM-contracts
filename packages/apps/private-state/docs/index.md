# Private-State DApp Documentation

This directory contains the design, protocol, security, and implementation documents for the `private-state` DApp.

## Quick Answers

### What is the private-state DApp?

`private-state` is a bridge-coupled zk-note payment DApp for Tokamak Private App Channels. It keeps
canonical token custody on L1 through the bridge, while channel-local accounting balances, note
commitments, nullifiers, and encrypted note-delivery events live in the proof-backed DApp state.

### What privacy does it provide?

The DApp hides note ownership and note-transfer meaning from public contract state, but it does not
make all activity invisible. Observers can still see accepted bridge transitions, changed storage
commitments, nullifier usage, and encrypted note-delivery events. Recipients need local secret
material to decide which encrypted notes are theirs.

### What should users check before joining a channel?

Users should review the channel's immutable policy snapshot before joining. The important fields are
the DApp metadata digest, digest schema, function metadata root, verifier addresses, compatible
backend versions, join toll, and refund policy. Joining a channel means accepting that policy for the
channel lifetime.

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
   Documents bridge-inherited security assumptions, finite leaf collision risk, future nullifier collision probability, wallet encryption, channel-bound L2 derivation, note-receive key derivation, and recovery behavior.
5. [Private-State Workflow](workflow.md)
   Describes the CLI workflow, wallet/workspace artifacts, bridge registration metadata, proof input bundle format, event recovery flow, and bridge-DApp execution coupling.

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

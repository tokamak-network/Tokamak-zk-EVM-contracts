# Private-State Documentation

This directory contains the design, protocol, security, and implementation documents for the `private-state` DApp.

## Reading Order

1. [Background Theory](background-theory.md)
   Start here. Defines the custody model, zk-L2 assumptions, liquid accounting balance, notes, note
   commitments, nullifiers, and the ownership-versus-readability distinction.
2. [Contract Specification](contract-spec.md)
   Maps the concepts from the background document to the two Solidity contracts, their storage, and
   their public state-transition semantics.
3. [Function Constraints](function-constraints.md)
   Explains why the user-facing entrypoints are fixed-arity and lists the validity constraints that
   each mint, transfer, and redeem shape must satisfy.
4. [Security Model](security-model.md)
   Documents bridge-inherited security assumptions, finite leaf collision risk, future nullifier collision probability, wallet encryption, channel-bound L2 derivation, note-receive key derivation, and recovery behavior.
5. [Workflow](workflow.md)
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

# Private-State Documentation

This directory contains the design, protocol, security, and implementation documents for the `private-state` DApp.

## Reading Order

1. [Background Theory](background-theory.md)
   Explains the custody model, zk-L2 assumptions, note/accounting split, and the protocol trust model.
2. [Contract Specification](contract-spec.md)
   Defines the on-chain storage layout, contract responsibilities, public data model, and event model.
3. [Function Constraints](function-constraints.md)
   Lists the fixed-arity entrypoints and the constraints that each user-facing function must satisfy.
4. [Security Model](security-model.md)
   Documents bridge-inherited security assumptions, finite leaf collision risk, future nullifier collision probability, wallet encryption, channel-bound L2 derivation, note-receive key derivation, and recovery behavior.
5. [Workflow](workflow.md)
   Describes the CLI workflow, wallet/workspace artifacts, bridge registration metadata, proof input bundle format, event recovery flow, and bridge-DApp execution coupling.

## Scope

These documents cover:

- the protocol background and trust assumptions
- the private-state contract interfaces and invariants
- the bridge-coupled execution model
- the CLI and proof-generation workflow
- the note-receive key architecture
- the fixed-circuit function shape used by the implementation

They do not replace operator runbooks or deployment command references. Operational quickstart material remains in the app README and script help output.

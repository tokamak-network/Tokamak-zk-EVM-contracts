# Private-State Documentation

This directory contains the design, protocol, security, and implementation documents for the `private-state` DApp.

## Reading Order

1. [Background Theory](background-theory.md)
   Explains the custody model, zk-L2 assumptions, note/accounting split, and the protocol trust model.
2. [Contract Specification](contract-spec.md)
   Defines the on-chain storage layout, contract responsibilities, public data model, and event model.
3. [Function Constraints](function-constraints.md)
   Lists the fixed-arity entrypoints and the constraints that each user-facing function must satisfy.
4. [Optimization Techniques](optimization.md)
   Describes the bytecode and Synthesizer-placement optimization rules used by the contracts and generators.
5. [CLI Security Model](cli-security.md)
   Documents wallet encryption, channel-bound L2 derivation, note-receive key derivation, and the recovery model.
6. [CLI to DApp Protocol](cli-dapp-protocol.md)
   Describes the wallet/workspace artifacts, calldata construction rules, proof input bundle format, and event recovery flow.
7. [Bridge to DApp Protocol](bridge-dapp-protocol.md)
   Describes DApp registration metadata, managed storage vectors, channel registration, bridge event propagation, and execution coupling.

## Scope

These documents cover:

- the protocol background and trust assumptions
- the private-state contract interfaces and invariants
- the bridge-coupled execution model
- the CLI and proof-generation workflow
- the note-receive key architecture
- the fixed-circuit and placement-optimization rules used by the implementation

They do not replace operator runbooks or deployment command references. Operational quickstart material remains in the app README and script help output.

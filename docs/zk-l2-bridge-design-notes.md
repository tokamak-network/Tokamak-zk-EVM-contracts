# ZK-L2 Ethereum Bridge Design Notes

## 1. Purpose

This document records the stable design direction of the Tokamak Private App Channels
bridge. It is not a line-by-line description of the current Solidity code, and it is
not a formal mathematical specification.

Its intended use is:

- to explain the architecture to future developers
- to preserve the main design decisions behind the bridge
- to remain useful even when small implementation details change

Concrete ABI details, calldata layouts, event payload formats, and short-lived
implementation techniques should be documented elsewhere.

## 2. System View

The system is an Ethereum-settled bridge for many application-specific private-state
channels.

Each channel is:

- tied to one DApp definition
- tied to one L1 token vault
- represented on L1 by a compact commitment to its current L2 state
- advanced only through proof-backed state transitions after genesis

The bridge treats Ethereum as the canonical settlement layer. Off-chain execution may
prepare candidate updates, but only proof-verified updates accepted by the bridge
become authoritative.

## 3. State Model

### 3.1 Root-vector state

The L2 state of a channel is modeled as an ordered vector of Merkle roots.

The vector contains:

- exactly one token-vault root
- zero or more application-storage roots

The bridge keeps only a compact commitment to the current root vector in channel
storage. The full vector is treated as transition data that must be made observable
whenever a proof-backed update is accepted.

### 3.2 Genesis and post-genesis updates

Each channel starts from a deterministic genesis root vector.

After genesis, a channel-state commitment may change only through:

- a Groth16-backed token-vault update
- a Tokamak-zkp-backed channel transaction update

No administrative or convenience path should be allowed to bypass that rule.

## 4. DApp Model

### 4.1 DApp-wide storage surface

A DApp is registered as:

- a shared ordered storage-domain vector
- a set of supported functions
- function-specific proof metadata

All functions of the same DApp must share the same storage-domain vector. This is a
deliberate design decision.

The consequences are:

- the root-vector length of a channel is fixed once its DApp is chosen
- the token-vault storage domain has one fixed position for the whole DApp
- function-specific proof interpretation may vary, but the channel-wide storage
  surface does not

This shared-storage rule is important because it keeps the state model stable across
all functions of the same channel.

### 4.2 Function metadata

Each function carries metadata that allows the bridge to interpret the proof-bound
public inputs for that function.

Conceptually, the function metadata contains:

- a function identifier
- a preprocess commitment
- a layout description for the public inputs
- a description of which storage writes may appear in the public inputs

The exact encoding of that metadata is an implementation detail. The stable design
point is that the bridge must not hardcode function-specific proof layout assumptions
 that are expected to evolve with the synthesizer.

## 5. Channel Model

When a channel is created, it chooses exactly one registered DApp.

The channel then inherits:

- the DApp's shared storage-domain vector
- the DApp's fixed token-vault position
- the DApp's supported function set
- the per-function proof-interpretation metadata needed at runtime

The channel also fixes its own channel-scoped metadata, such as the block-context
commitment used by Tokamak verification.

The important architectural boundary is:

- DApp metadata describes what functions and storage surfaces are valid for the
  application
- channel metadata describes the concrete instance of that application running on L1

## 6. Proof Systems and Responsibilities

### 6.1 Groth16 path

The Groth16 path is reserved for token-vault balance updates.

Its job is to justify transitions of the distinguished token-vault root and the
associated L1 settlement changes. This path is responsible for:

- L1-to-L2 deposit settlement
- L2-to-L1 withdrawal settlement
- maintaining the authorization link between a user and the user's registered
  token-vault key

At the design level, the Groth path should affect only the token-vault component of
the channel state.

### 6.2 Tokamak path

The Tokamak path is reserved for general channel transaction execution.

Its job is to justify DApp function execution against:

- the channel's current state commitment
- the channel's block-context commitment
- the selected function's preprocess commitment
- the selected function's proof-layout metadata

The bridge should accept a Tokamak transition only when it can bind the proof to:

- the correct function
- the correct channel context
- the correct pre-state
- the correct post-state

## 7. Observability

The bridge intentionally stores a compact state commitment rather than a full
historical archive of channel roots.

That choice shifts some responsibility to the observability layer. Whenever a
proof-backed transition is accepted, enough information must be made available for
off-chain observers to reconstruct:

- the pre-state root vector
- the relevant storage writes produced by the accepted transition

This observability requirement applies to both proof systems:

- Groth updates should make the token-vault storage update observable
- Tokamak updates should make the decoded storage writes of the accepted function
  observable

The exact event schema is not a stable design concern. The stable design concern is
that accepted state transitions remain inspectable off-chain.

## 8. Token-Vault Registration Model

Each channel has one L1 token vault and one distinguished L2 token-vault storage
domain.

Users who want to participate in L1 settlement for that channel must register a
channel-specific L2 token-vault key. The bridge derives a token-vault position from
that key according to the bridge's Merkle-tree indexing rule.

The stable registration requirements are:

- a user has at most one registered token-vault key per channel
- registered token-vault keys are globally unique
- derived token-vault positions are unique within a channel

This registration model provides the authorization anchor for Groth-backed deposit
and withdrawal.

## 9. Soundness Principles

The following soundness principles should remain true even if implementation details
change.

### 9.1 Proof-backed root transitions only

After genesis, a channel-state commitment must change only through an accepted proof.

### 9.2 DApp binding

A Tokamak proof must be bound to the metadata of the DApp function it claims to
execute. A proof valid for one function must not be reusable as if it were valid for
another.

### 9.3 Channel binding

A proof must be bound to the channel instance in which it is submitted. In practice,
this means that channel-scoped metadata used by proof verification must not be
interchangeable across channels.

### 9.4 Pre-state binding

The bridge must not apply a post-state unless the proof is shown to start from the
channel's actual current state commitment.

### 9.5 Token-vault isolation

The distinguished token-vault storage domain has special settlement meaning. Any
design that lets arbitrary non-vault logic mutate the token-vault state without the
intended proof discipline should be treated as suspicious.

## 10. Design Preferences

The current design prefers the following tradeoffs.

### 10.1 Stable abstractions over transient wiring

Documents should describe:

- shared DApp storage vectors
- channel-scoped proof context
- proof-backed state transitions
- observability requirements

rather than:

- exact ABI parameter lists
- exact synthesizer word layouts
- exact event signatures
- exact cache structures

### 10.2 Metadata-driven proof interpretation

Where the synthesizer may evolve, the bridge should prefer metadata-driven proof
interpretation over hardcoded assumptions. Hardcoding is acceptable only for facts
expected to remain protocol-level constants rather than tool-output conventions.

### 10.3 Compact on-chain state, rich off-chain reconstruction

The bridge prefers to keep compact state commitments on-chain and expose enough
accepted-transition data for off-chain observers to reconstruct richer history.

## 11. Open Design Questions

The following topics are intentionally left open for later work.

- governance and lifecycle rules for changing channel-scoped proof context
- migration rules when the synthesizer changes proof layouts materially
- operational procedures for rotating or replacing supported DApps
- longer-term archival strategy for off-chain reconstruction data
- whether additional formal guarantees should be imposed on DApp metadata shape

## 12. Summary

The stable architectural picture is:

- one DApp defines one shared storage surface and a set of supported functions
- one channel selects one DApp and one channel-scoped proof context
- one channel state is one root-vector commitment
- Groth controls token-vault settlement transitions
- Tokamak controls general channel transaction transitions
- the bridge keeps compact commitments on-chain and relies on observable transition
  data for richer off-chain reconstruction

That model should remain recognizable even if the concrete contracts, scripts, or
proof-input encodings continue to evolve.

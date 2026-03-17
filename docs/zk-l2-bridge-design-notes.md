# ZK-L2 Ethereum Bridge Design Notes

## Status

- Document type: living design notes
- Scope: zk-proof-based Ethereum Layer 2 bridge architecture
- Last updated: 2026-03-17
- Authoring mode: incremental capture of design ideas, decisions, and open questions

## Purpose

This document is the working design notebook for the bridge system. It is intended to absorb new ideas as they are introduced, while keeping the overall architecture coherent and auditable.

The document separates:

- fixed assumptions
- current design decisions
- architecture structure
- lifecycle flows
- data model and state commitments
- unresolved questions and risks
- chronological input log

## Documentation Rules

- Preserve the substance of each user input, even when the wording is informal.
- Normalize terminology when different phrases refer to the same concept.
- Distinguish clearly between assumptions, decisions, proposals, and open questions.
- Keep all prose and comments in English.
- Prefer architecture-level clarity over premature implementation detail.

## Working Terminology

- `L1`: Ethereum mainnet or the canonical settlement layer
- `L2`: the zk-proof-based execution and accounting layer
- `Bridge`: the cross-layer system that binds L1 custody to L2 state transitions
- `Canonical custody`: the asset balance that remains authoritative on L1
- `L2 accounting state`: the mirrored balance or state representation accepted by the bridge after proof verification
- `State root`: the commitment to the accepted L2 bridge-related state
- `Proof`: the zk proof that binds a proposed state transition to the bridge rules

## Design Goals

- Keep canonical asset custody on L1.
- Let L2 carry execution and accounting state, not independent canonical custody.
- Accept L2 state transitions only when they are bound to proof verification.
- Make the bridge architecture convertible into fixed, circuit-friendly execution paths.
- Preserve a clean separation between protocol rules, operational roles, and user-facing flows.

## Fixed Assumptions

The following assumptions are currently treated as the baseline unless later inputs explicitly revise them:

- L1 is the canonical settlement and custody domain.
- L2 is primarily an execution and accounting domain.
- Bridge acceptance must be proof-gated rather than trust-gated.
- Public outputs should reveal commitments and state transitions, not full private execution details.
- The architecture should remain compatible with zk-oriented execution constraints.
- `docs/spec.md` is currently an important source of structure and constraints, but it is not treated as immutable truth.
- Future user instructions may refine, replace, or override any provisional interpretation derived from `docs/spec.md`.

## Provisional Interpretation of `docs/spec.md`

This section translates the mathematical model in `docs/spec.md` into plain English. It is a working interpretation, not a final protocol commitment.

### What the spec appears to define

The spec appears to model the bridge as a system with three main layers:

1. An admin registry layer that defines which application functions exist, which storage addresses those functions touch, which storage keys are pre-allocated, which user slots are relevant, and which proof configuration is bound to each function.
2. A per-channel state layer that binds a set of users and application functions to a structured storage universe, a validated value set, and a time-ordered sequence of proposed and verified state roots.
3. A bridge-core layer that lifts each per-channel relation into a channel-scoped global namespace and exposes the resulting channel-indexed getter surface.

### Plain-English reading of the admin registry

The `Bridge Admin Manager` in `docs/spec.md` looks like a control-plane registry for the L2 application surface that the bridge is willing to recognize.

In practical terms, it says the bridge should know:

- which function signatures are supported
- which storage contracts or storage addresses each function depends on
- which storage keys are reserved and fixed before user activity
- which user storage slots matter for bridge-visible state
- which proof configuration belongs to each function
- how many public inputs the Tokamak zk-EVM proof expects
- how large each channel Merkle tree is

This suggests that the bridge does not treat the L2 application as an opaque black box. Instead, it maintains a structured, pre-declared model of the parts of L2 state that are eligible for bridge validation.

### Plain-English reading of the channel model

The `Channel` section appears to define an isolated application-specific or session-specific L2 state domain.

Each channel has:

- a participant set
- a supported function set
- a derived set of storage addresses touched by those functions
- a derived set of pre-allocated keys and user slots
- a mapping from each user and storage address to one channel-specific storage key
- a validated value table over both pre-allocated keys and user keys
- a history of verified state roots
- a history of proposed but not yet verified state roots, organized by fork ID

The spec therefore seems to treat a channel as the bridge-visible boundary of L2 execution. The bridge does not need to store every internal execution detail directly, but it does need a committed state structure for each channel that can be checked, updated, and queried.

### Plain-English reading of state progression

The spec distinguishes between two kinds of state-root progression:

- `VerifiedStateRoots`: state roots that have already been accepted by the bridge
- `ProposedStateRoots`: candidate state roots that are tracked before they become verified

The model also introduces:

- `StateIndices`: a strictly ordered timeline for state versions
- `ForkIds`: separate branches of unverified proposed states

This implies a bridge architecture with both final and non-final state:

- verified state is the canonical bridge-accepted view
- proposed state is a staging area for candidate transitions
- forks allow multiple unverified candidate trajectories before one is accepted or the verified state is copied into a fresh branch

### Plain-English reading of the proof model

The spec seems to define two proof-driven update paths:

1. A single-leaf update path through `updateSingleStateLeaf(...)`, backed by a Groth16 proof and a compact public input vector.
2. A full multi-storage transition path through `verifyProposedStateRoots(...)`, backed by a Tokamak zk-EVM proof, preprocess data, and a larger public input vector.

This is an important structural signal. It suggests the system may need both:

- a narrow proof path for updating one committed leaf in a storage tree
- a broader proof path for validating a full batched execution result across all app storages in the channel

The spec does not yet prove why both paths must exist, but it clearly models them as first-class mechanisms.

### Plain-English reading of the bridge core

The `Bridge Core` section appears to be a channel aggregator. It does not redefine the state rules. Instead, it lifts each per-channel relation into a global bridge namespace.

In practical terms, this means the bridge core likely serves as:

- the registry of channel IDs
- the entry point for channel-scoped queries
- the canonical place where per-channel state is exposed to L1-side bridge logic

## Rough Layer 2 System Structure Derived from the Spec

This section is the first rough architecture draft derived from `docs/spec.md`. It should be treated as provisional and overrideable.

### 1. Control Plane on L1

The bridge needs an L1-side control plane that registers the execution surface the bridge recognizes.

Likely responsibilities:

- register bridge-recognized application functions
- bind each function to the storage addresses it can affect
- declare pre-allocated keys and relevant user storage slots
- bind proof configuration metadata to each function
- define proof-system parameters such as public input length and Merkle tree depth

### 2. Channelized L2 State Domains

The L2 system is provisionally modeled as a set of channels rather than as one undifferentiated global state pool.

Each channel likely represents a bridge-recognized execution domain with:

- a known participant set
- a known application surface
- a closed storage universe derived from that application surface
- channel-local user storage keys
- a validated storage-value table
- a verified state-root timeline
- one or more proposed-state forks

Under this reading, a channel is the bridge-facing container for L2 app state.

### 3. L2 Application Execution Layer

Although the spec is written from the bridge perspective, it implicitly assumes an L2 execution environment that produces updates to the channel state.

That execution layer likely contains:

- user-invoked application functions
- storage contracts or addresses that hold bridge-relevant application state
- a mapping from application execution results to channel storage updates

The spec does not describe the full transaction lifecycle, mempool rules, sequencing policy, or privacy machinery. It only constrains the state interface that the bridge must understand.

### 4. Proof Generation and Verification Layer

A separate proof layer likely sits between L2 execution and L1 bridge acceptance.

Its provisional role is:

- derive the witness for a channel state transition
- produce either a leaf-level proof or a full proposed-state proof
- submit proof-linked public inputs that bind storage keys, storage values, and resulting roots
- let the bridge decide whether a proposed root becomes verified

### 5. Canonical vs Non-Canonical State

The rough system structure should distinguish clearly between:

- canonical channel state, represented by verified roots
- non-canonical candidate state, represented by proposed roots organized in forks

This means the L2 system may need two operational views at once:

- the last bridge-accepted state
- one or more speculative next states under construction or verification

### 6. Storage Model

The spec suggests a storage model that is more structured than a generic account/state trie abstraction.

At minimum, the bridge-visible storage model seems to require:

- storage addresses as first-class entities
- reserved pre-allocated keys
- user-derived channel keys
- validated values per `(storage address, key)` pair
- Merkle commitments over bridge-recognized storage tables

This is a strong sign that the bridge architecture is storage-centric, not only balance-centric.

## Provisional Constraints Implied by `docs/spec.md`

The following constraints appear to be materially implied by the current spec text:

- Every supported function must be associated with at least one storage address.
- Every supported function must have exactly one proof configuration pair.
- Channel user keys must be unique per user and storage address.
- Pre-allocated keys and user channel keys must remain disjoint.
- Every recognized storage key must map to exactly one validated value.
- State-root history is indexed and ordered, not just stored as a single latest root.
- Verified roots and proposed roots are vector-complete across the full application storage set at a given index.
- Root progression is intended to advance by index and change the committed root, not repeat the same root at the next index.
- Proposed-state forks are explicit objects in the model, not accidental side effects.
- When verified state gets ahead of proposed state, the system must be able to create a fresh fork synchronized from verified state.

## Initial Design Reading

My current reading is that `docs/spec.md` is not just a bridge contract specification. It is closer to a bridge-facing state model for a private or partially private L2 application environment.

Under that reading, the rough system shape is:

- L1 admin registry defines what L2 execution surface is admissible.
- L2 execution happens inside channel-bounded application state domains.
- Channel state is represented as storage-key/value commitments across one or more storage addresses.
- Candidate transitions are tracked as proposed roots, potentially across multiple forks.
- Proof verification promotes one proposed trajectory into the verified bridge-visible state history.
- The bridge core exposes all of this through channel-scoped relations and getters.

This is the best current interpretation of the spec, but it should remain easy to revise as new instructions arrive.

## Current Architecture Skeleton

### 1. L1 Bridge Layer

Responsible for:

- canonical asset custody
- deposit acceptance
- withdrawal settlement
- proof verification
- accepted state-root progression
- bridge configuration and emergency controls

### 2. L2 Execution and Accounting Layer

Responsible for:

- user-level execution
- private or reduced-disclosure transaction handling
- bridge-relevant accounting transitions
- production of the state transition witness for proof generation

### 3. Proof and Coordination Layer

Responsible for:

- collecting or deriving the transition witness
- generating proofs
- submitting proofs and bridge-linked public inputs
- coordinating state-root advancement

## Core Lifecycle Flows

### Deposit Flow

Initial placeholder:

1. User deposits assets into the L1 bridge custody domain.
2. The bridge records the deposit event or commitment.
3. The L2 side incorporates the deposit into the next valid accounting transition.
4. The bridge accepts the updated L2-related state only after proof verification.

### L2 State Transition Flow

Initial placeholder:

1. Users execute L2 actions.
2. The system derives the resulting bridge-relevant state transition.
3. A proof is generated for the transition.
4. The bridge verifies the proof and advances the accepted state root.

### Withdrawal Flow

Initial placeholder:

1. The user obtains a valid withdrawal entitlement from the accepted L2 state.
2. The withdrawal claim is submitted to the L1 bridge.
3. The bridge verifies that the claim is authorized by the accepted state and protocol rules.
4. The bridge releases the canonical assets from L1 custody.

## State Model

The exact state model is still open, but the document will track at least the following categories:

- canonical L1 custody balances
- L2 accounting balances
- accepted state roots
- proposed state roots
- deposit records or commitments
- withdrawal claims or nullifiers
- operator or prover configuration
- emergency or governance controls

## Security and Correctness Invariants

These are the initial invariants that should remain visible throughout the design process:

- No asset leaves L1 custody without a bridge-authorized settlement path.
- No L2 balance transition becomes canonical for bridge purposes without proof verification.
- Deposit and withdrawal accounting must remain conservation-safe across layers.
- State-root progression must be well-defined and non-ambiguous.
- Replay of already-consumed bridge actions must be impossible or explicitly prevented.
- Administrative powers must be explicit, minimal, and justified.

## Open Questions

- The exact trust and operator model is not defined yet.
- The exact batching and proof-submission model is not defined yet.
- The exact withdrawal authorization model is not defined yet.
- The exact data-availability assumptions are not defined yet.
- The exact failure and recovery model is not defined yet.

## Decisions Log

This section will record finalized architectural decisions once they become stable.

Currently no finalized bridge-specific decisions have been recorded in this working note.

## Input Log

### 2026-03-17

- The design target is a bridge for operating a zk-proof-based Ethereum Layer 2.
- The documentation process will be incremental and should absorb spontaneous design ideas while maintaining a coherent system structure.
- The current task is to read `docs/spec.md`, understand its definitions and constraints, and translate them into a rough Layer 2 system structure in English.
- The structure derived from `docs/spec.md` is provisional and may be overridden by future user instructions.

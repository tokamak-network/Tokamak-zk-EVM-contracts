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


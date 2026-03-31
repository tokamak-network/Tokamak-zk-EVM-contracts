# Contract Optimization Techniques

This document summarizes the implementation techniques used to keep `private-state` compatible with fixed circuits and to reduce Synthesizer placement cost.

## 1. Fixed-Arity Entry Points

The contracts do not expose one generic mint, transfer, or redeem entrypoint with dynamic loops and mode switches.

Instead they expose:

- `mintNotes1..6`
- `transferNotes1To1`, `transferNotes1To2`, `transferNotes1To3`, `transferNotes2To1`, `transferNotes2To2`, `transferNotes3To1`, `transferNotes3To2`, `transferNotes4To1`
- `redeemNotes1..4`

This removes dynamic branching and reduces both bytecode indirection and placement-heavy loop scaffolding in hot paths.

## 2. One Successful Path per Function

Each user-facing function is designed around one successful state transition only.

The pattern is:

- validate inputs
- derive commitments/nullifiers
- enforce the single state-balance relation
- apply storage updates
- emit encrypted-note events if needed

Failure branches exist only for guard conditions.

## 3. Fixed-Shape Encrypted Outputs

Encrypted note delivery uses `bytes32[3] encryptedNoteValue`.

This avoids:

- dynamic byte arrays
- per-output ABI shape variation
- contract-side decode logic

The contract treats the payload as opaque and only derives its hash for salt binding.

## 4. Salt Derivation Inside the Contract

The contract no longer accepts caller-chosen salts for encrypted outputs.

Instead:

- `salt = hash(encryptedNoteValue)`

This design is cheaper than keeping extra note-delivery storage or validating ciphertext semantics on-chain.

## 5. Assembly for Fixed-Shape Hash Inputs

Commitment and nullifier helpers use direct memory staging in `memory-safe` assembly.

Benefits:

- avoids `abi.encode(...)` scaffolding
- hashes a known four-word layout directly
- reduces placement-heavy generic encoding work

This is especially relevant in the Tokamak proving environment, where generic encoding/decoding overhead can dominate placement cost even when the logical state change is simple.

## 6. Minimize Contract Boundaries

The DApp uses only two storage contracts:

- controller
- accounting vault

This keeps the managed storage vector small while still separating note state from accounting balances.

The split exists because:

- `L2AccountingVault` provides a reusable accounting-only balance domain
- `PrivateStateController` handles commitments, nullifiers, and encrypted-note events

## 7. No On-Chain Ciphertext Semantics Validation

The contracts do not try to prove:

- that a ciphertext decrypts to a truthful plaintext
- that the sender encrypted to the intended recipient correctly

They enforce only the cheaper invariant:

- ciphertext and note salt are cryptographically bound

That keeps placement cost low and avoids a much more expensive on-chain validation path.

## 8. Placement-Aware Generator Rules

The off-chain generators and bridge registration pipeline are also part of optimization discipline.

Important rules:

- use the actual managed storage vector from the storage-layout manifest
- keep fixed-shape examples per function family
- avoid synthetic storage-vector mismatches between CLI and registration examples
- keep function preprocess metadata aligned with the exact generated input layout

If the generator emits a different storage vector or event-layout shape than the CLI runtime path, the bridge can reject otherwise valid transactions due to preprocess mismatch.

## 9. Limits Still Present

The current implementation still encounters capacity limits in some higher-arity examples.

In practice this means:

- Solidity can support more shapes than are currently registered on a target network
- qap-compiler or Synthesizer capacity can still force a smaller deployed function set

This is an optimization and tooling limit, not a correctness issue in the contract logic itself.

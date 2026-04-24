# zk-L2 App DApp Design Checklist

Use this checklist when creating or reviewing a new DApp project under `apps/`.

## 1. zk-L2 Privacy Assumption

Treat the following as fixed system assumptions:

- Every user transaction is converted locally into a proof before publication.
- L1 verifies proofs rather than the raw transaction body.
- The original transaction body is visible only to the caller.
- Other users and L1 observers see proofs and the resulting state transitions, not the original calldata.
- The target DApp functions do not execute under raw Ethereum L1 cryptographic semantics.
- Under the TokamakL2JS execution spec, runtime `keccak256` behavior is replaced by Poseidon-based hashing.
- Under the same spec, transaction signatures and public-key recovery follow EdDSA-compatible semantics rather than Ethereum ECDSA assumptions.

Design implications:

- Do not justify plaintext leakage by assuming direct L1 execution.
- Do not add calldata privacy workarounds whose only purpose is to hide data from public L1 mempools.
- Focus privacy review on the data that becomes state, events, or proof-linked public outputs.
- Do not mirror contract execution off-chain with default L1 helpers when the modeled computation depends on hashing or signature recovery.
- When reproducing contract-side runtime hashes off-chain, use `tokamak-l2js` Poseidon helpers:
  - `poseidon(msg)` for byte-oriented runtime inputs.
  - `poseidonChainCompress(inVals)` for field-element sequences that are already split.
- Treat `ecrecover`-style reasoning as invalid for this environment. When the spec requires public-key recovery, use `getEddsaPublicKey(...)` instead.
- Distinguish runtime hashes from Solidity compile-time constants. A compile-time constant such as `bytes32 constant X = keccak256("...")` remains the Solidity-compiled literal, while a runtime `keccak256(...)` execution must be modeled with the TokamakL2 Poseidon replacement semantics.

## 2. Bridge-Managed Custody and Accounting

Treat the following as mandatory across every DApp under `apps/`:

- L1 is the canonical asset custody domain.
- L2 is an accounting domain whose state root is recorded and advanced by the L1 bridge.
- Users may deposit to and withdraw from the L1 bridge custody vault directly.
- Users must not interact directly with an L2 token custody vault, because L2 should not hold canonical custody in this model.
- L2 accounting balance changes must be accepted only as part of proof-verified bridge state transitions.

Required design implications:

- Do not add user-facing L2 `deposit` or `withdraw` functions that independently move assets.
- Model L2 asset state as accounting balances, not as a second canonical custody layer.
- Treat deposit and withdrawal as proof-backed L1 bridge operations that also update the accepted L2 state root.
- Ensure the proof statement or public inputs bind L2 balance deltas to the corresponding L1 bridge custody delta.

Preferred naming:

- L1 custody contract: `L1BridgeAssetVault`
- L2 mirrored balance contract: `L2AccountingVault`

If a DApp must keep the historical `TokenVault` name for compatibility, document clearly that the L2 contract is accounting-only and not direct custody.

## 3. Standard L2 Accounting Vault Shape

Every DApp under `apps/` must use the same L2 accounting vault storage pattern.

Required properties:

- One canonical per-user accounting balance mapping.
- No direct ERC-20 `transferFrom` or `transfer` entrypoints for end users.
- No user-facing deposit or withdrawal functions on L2.
- Mutations restricted to bridge-coupled state transitions or the app's canonical coordinator logic, depending on the proving architecture.
- Every credit and debit path must enforce overflow and underflow checks against the BLS12-381 scalar field, not just native `uint256` arithmetic.
- Credit paths must reject any update that would raise a stored balance above `BLS12-381 scalar field order - 1`.
- Debit paths must reject any update that would drive a stored balance below zero under the same field-bound accounting model.

Review questions:

- Does the L2 vault store accounting balances only?
- Can any user bypass the bridge flow and mutate L2 balances directly?
- Does the DApp introduce a second L2-specific vault shape instead of reusing the standard one?
- Are all L2 vault credit and debit mutations guarded against BLS12-381 scalar-field overflow and underflow?

## 4. Circuit-Convertible User Entry Points

Every final user-facing function must be convertible into a fixed circuit.

Required rule:

- Each function must have exactly one successful symbolic execution path.

Allowed:

- Conditionals that only guard failure.
- Loops used for linear processing when they do not introduce alternate successful branches.
- Internal helper functions, as long as the external entrypoint still has one successful path.

Disallowed patterns in final user-facing functions:

- Two or more successful modes in one function.
- Optional success branches such as `if (...) { do A } else { do B }` where both branches can finish successfully.
- Direct-owner path plus delegated-signature path inside the same user-facing function.
- Feature flags that select different successful settlement logic.

Preferred refactors:

- Split different successful behaviors into separate external functions.
- Move optional behavior behind explicit pre-processing and then call one canonical state transition entrypoint.
- Convert branchy success logic into prevalidated data that feeds a single transition path.

## 5. Symbolic-Path Checking Tool

Run the checker on every final user-facing contract:

```bash
python3 .codex/skills/app-dapp-zk-l2/scripts/check_unique_success_paths.py \
  apps/<dapp>/src/<Contract>.sol --contract <Contract>
```

What it does:

- Scans external/public state-changing functions.
- Flags conditional structures that can create more than one successful path.
- Treats revert-only guards as acceptable.
- Treats loops conservatively and reports loop bodies with branchy or unsupported control flow.

What it does not do:

- It does not prove correctness.
- It does not replace manual review.
- It intentionally errs on the side of flagging suspicious branching for inspection.

Use the tool output as a gate for review, then verify flagged functions manually.

## 6. Storage Layout Guidance

If the DApp is likely to maintain large or fast-growing state, prefer splitting storage across multiple addresses.

Why:

- The target L2 imposes a practical storage capacity limit per address.
- Spreading state across several contracts improves long-term scalability.
- Smaller state domains are easier to migrate, inspect, and reason about.

Prefer separate storage addresses when:

- The app tracks multiple independent state families.
- One state family can grow without bound.
- Some state is hot and frequently updated while other state is archival.
- Different submodules need different upgrade or replacement cadence.

Typical split patterns:

- L1 bridge custody store
- L2 accounting vault
- Note or commitment store
- Nullifier or spent-state store
- Order, market, or position store
- Metadata or indexing store

Review questions:

- Which state families can grow independently?
- Which state must remain atomically consistent?
- Which state can be isolated behind a coordinator without duplicating truth?
- Is any field duplicated across stores when one canonical source would suffice?

## 7. Function-Level Bytecode Discipline

Every DApp under `apps/` should keep contract bytecode lean by minimizing each function to the operations that are strictly necessary for the intended state transition.

Required review rules:

- Do not keep generic helper paths that only exist for convenience if a fixed-arity or direct path is materially smaller.
- Avoid copying fixed-size calldata into dynamic memory unless another hard requirement makes it necessary.
- Avoid internal dispatch layers that only forward to one concrete implementation path.
- Do not use loops for repeated work inside user-facing contract hot paths. If the arity is fixed, unroll the work into a flat implementation.
- Re-check reusable abstractions when they add loops, memory allocation, or intermediate data structures that the concrete function does not actually need.
- If a user-facing function can be expressed as a simpler fixed-shape flow, prefer the simpler flow.

Review questions:

- Which operations in this function are essential to the state transition?
- Which operations only support abstraction, copying, or generic plumbing?
- Can any dynamic allocation, copying, or generic iteration be removed without weakening validation?
- Does the current factoring reduce bytecode, or does it only move complexity around?

Deployment and fixture rules:

- Every DApp deployment flow must write one storage-layout manifest under `apps/<dapp>/deploy`.
- The manifest must include each deployed contract address plus the compiler-reported storage layout for that contract.
- Example and replay generators must read that manifest when computing statically known storage keys.
- Do not keep hardcoded default `preAllocatedKeys` that are not derived from the actual deployed storage layout and actual pre-state.

## 8. Placement Discipline

Treat Synthesizer placements as a primary optimization target for every user-facing contract function.

Definition:

- A placement is a circuit-side resource allocation emitted by the Synthesizer while modeling EVM execution.
- Placement count is not the same as Solidity line count, opcode count, gas cost, or bytecode size.
- A small Solidity helper can still be placement-heavy if it triggers calldata copying, repeated storage access, repeated hashing, or external-call proof logic.

Required implementation rule:

- Every DApp contract function should be implemented to minimize placement usage while preserving correctness and the single-success-path rule.
- When analyzing placement cost, distinguish raw memory movement from encoding and decoding work. Fixed-shape word copies are often cheap; ABI scaffolding, packing, unpacking, and dynamic shape conversion are the usual placement sink.

Allowed optimization techniques:

- Inline fixed-arity logic when generic helper layers only add scaffolding.
- Remove avoidable calldata-to-memory copies.
- Remove avoidable ABI encoding, ABI decoding, packing, unpacking, and generic shape-conversion steps before optimizing plain fixed-shape memory copies.
- Remove generic dynamic-array helpers when the entrypoint arity is fixed.
- Replace fixed-arity loops with flat, explicitly repeated operations so that loop control does not consume placements.
- Collapse repeated validation or repeated hashing when the same intermediate value can be reused.
- Use assembly when it materially reduces placement usage and does not weaken validation or make the control flow ambiguous.
- For fixed-shape hash inputs, replace `abi.encode(...)+keccak256(...)` scaffolding with `memory-safe` assembly that stages words directly in memory and hashes the exact byte span.
- When doing manual memory staging for hashing, reserve scratch space from the free-memory pointer and advance it after use so future assembly blocks cannot collide with the same offsets.
- Do not spend placements on explicit zero-hash guards for commitments, nullifiers, or similar cryptographic digests unless the design has a concrete reason to treat a zero digest as semantically special.

Review questions:

- Which placements are caused by the function itself, and which are caused by subcalls into storage/helper contracts?
- Is the function paying placements for abstraction rather than for state-transition requirements?
- Is the expensive part really the memory movement, or is it the encoding/decoding logic wrapped around that movement?
- Can fixed-arity calldata access replace generic loops or dynamic copies?
- Is any remaining loop in a fixed-arity user-facing function paying avoidable placement overhead?
- Can a shared intermediate hash or decoded field be computed once and reused?
- Would an assembly block remove measurable placement-heavy scaffolding without obscuring correctness?
- Is any fixed-shape runtime hash still paying placement overhead for generic ABI encoding that could be replaced with direct `mstore` plus `keccak256(ptr, len)`?
- Is the function still paying placements for a zero-hash guard on a cryptographic digest that can be treated as practically impossible instead?

## 9. Placement Analysis Methodology

Use this process when a function appears placement-heavy or when reviewing a new DApp entrypoint.

1. Generate or rerun the relevant Synthesizer example so that fresh analysis artifacts are written.
2. Inspect the Synthesizer analysis outputs produced by the published `@tokamak-zk-evm/synthesizer-node` or `@tokamak-zk-evm/cli` runtime.
   - `step_log.json`
   - `message_code_addresses.json`
3. If the example reaches full circuit generation, also inspect:
   - `outputs/placementVariables.json`
   - `outputs/instance.json`
   - `outputs/permutation.json`
4. Separate pre-transaction or signature-validation placements from placements triggered by the target contract function.
5. Partition placements by executing contract address first.
   - entrypoint controller
   - note registry
   - nullifier store
   - accounting vault
   - other subcalls
6. Map placement ranges back to source-level logic blocks.
   - function dispatch and calldata decoding
   - validation blocks
   - hash construction
   - storage reads
   - storage writes
   - output registration
   - event emission
7. Report exact counts for each logic block whenever possible.
   - Do not stop at qualitative labels such as "heavy" or "dominant".
   - Prefer explicit counts per block and per subcall boundary.
8. Distinguish between controller-side placements and placements paid because the architecture crosses contract boundaries.
9. Use the results to decide whether to:
   - inline logic
   - specialize fixed-arity paths
   - remove helper indirection
   - reduce repeated hashing
   - merge or redesign storage boundaries

Output expectation:

- A placement analysis should identify the function's total placements, subtract setup overhead, then give exact placement counts per internal logic stage and per external subcall domain.

## 10. Synthesizer Pre-State Fidelity

When a DApp ships Synthesizer launch inputs or compatibility tests, the stored pre-state inputs must represent real pre-state only.

Required rules:

- `previous_state_snapshot.json` and config `registeredKeys` must contain only storage keys that exist in the actual state before the transaction runs.
- Do not pre-register future write targets just because the tested transaction will touch them.
- Derive any statically known `preAllocatedKeys` from the DApp-local deployed storage-layout manifest under `apps/<dapp>/deploy`, not from hardcoded slot defaults.
- Registered keys must include the real from-side consumed keys needed by the transaction, such as a sender liquid-balance slot for mint or consumed note-commitment slots for transfer and redeem.
- To-side keys are optional in compatibility fixtures. Receiver or output-side storage may remain absent even if execution later reads or writes those slots.
- Apply the same rule to L2 vault balance mappings. The debited from-side balance slot is required when present in real pre-state; receiver-side balance slots are not mandatory fixture inputs.
- Do not patch configs by replaying once, collecting unregistered-storage warnings, and feeding those keys back into the snapshot as if they were part of pre-state, except for the required real from-side consumed keys.
- If an optional to-side key is absent from real pre-state, leave it absent rather than falsifying the snapshot.

## 11. Admin and Controller Wiring

Preferred default:

- no `owner` role on DApp contracts
- no mutable `setController` or `bindController`
- constructor-bound immutable controller addresses

If a controller is required:

- register it through deployment-time constructor arguments
- avoid post-deployment admin wiring
- when circular dependencies exist, solve them with deterministic address prediction and CREATE2 in the deployment script rather than by reintroducing mutable admin hooks

Review questions:

- Does the design still rely on an owner role that could have been removed?
- Is the controller relationship immutable after deployment?

## 11. Synthesizer Compatibility Test Scripts

Every DApp under `apps/` must provide function-level Synthesizer compatibility scripts.

Required structure:

- Store them under `apps/<dapp>/scripts/synthesizer-compat-test`.
- Provide one entry script per user-facing function.
- It is acceptable for those entry scripts to delegate to a shared helper, but the function-level entry scripts must still exist.

Required test method:

- Use the published `@tokamak-zk-evm/synthesizer-node` or `@tokamak-zk-evm/cli` entrypoint for Synthesizer execution.
- Keep `block_info.json` and `contract_codes.json` fixed while testing a given function.
- Vary `previous_state_snapshot.json` and transaction RLP across multiple valid private-input configurations for the same function.
- Run the Synthesizer CLI once per variant.
- Assert that:
  - `outputs/instance.json -> a_pub_function`
  - `outputs/permutation.json`
  remain identical across all tested variants for that function.

Review questions:

- Does every user-facing function have a dedicated Synthesizer compatibility entry script?
- Do the tests hold `block_info.json` and `contract_codes.json` fixed while varying only previous state and transaction witnesses?
- Do the tests explicitly compare `a_pub_function` and `permutation.json` across variants?
- Is the tested variation broad enough to cover multiple valid private-input configurations for the same function?
- If address prediction is used, is the deployment flow deterministic and explicitly documented?

## 11. Review Output

When reporting on a new app design, explicitly answer:

1. What information becomes public state or events despite the zk-L2 privacy assumption?
2. Does the design keep canonical custody on L1 and L2 balances as accounting-only state?
3. Does the app reuse the standard L2 accounting vault shape?
4. Which external functions are the final user-facing entrypoints?
5. Does each such function have exactly one successful symbolic path?
6. Does each final user-facing function contain only the operations strictly required for its state transition, or is there avoidable bytecode-heavy scaffolding left to remove?
7. Does each final user-facing function also minimize Synthesizer placement usage, or is there avoidable placement-heavy scaffolding left to remove?
8. If a function is placement-heavy, what are the exact placement counts by logic block and by external subcall domain?
9. Did the checker flag anything, and if so, why is it acceptable or how should it be refactored?
10. Should storage remain in one address or be split across multiple addresses?
11. Are deployment scripts stored under `apps/<dapp>/scripts/deploy` instead of the bridge deployment script tree?
12. Are app deployment secrets and network settings isolated in `apps/.env`, with shared app-level signer and provider-key-plus-network variables plus DApp-specific namespaced values only where needed, with `APPS_NETWORK=anvil` defaulting to localhost and `APPS_RPC_URL_OVERRIDE` reserved for nonstandard RPC overrides?
13. Does the DApp provide a local terminal CLI under `apps/<dapp>/cli`, limited to `mainnet`, `sepolia`, and `anvil`, and does that CLI read per-function `calldata.json` templates plus deployment manifests and callable ABI JSON files?
14. Does the DApp also provide concise DApp-local command wrappers, preferably through `apps/<dapp>/Makefile`, for anvil workflows, tests, and public-network deployment?
15. If duplicate callable function names exist across contracts, is the CLI folder naming collision handled explicitly and documented?
16. Was contract-level admin ownership removed where it was not strictly necessary?
17. If a controller exists, is it wired immutably at deployment time rather than through a mutable admin step?
18. Does the DApp provide local anvil helpers under `apps/<dapp>/scripts/anvil` when local-chain testing is required, and does it write manifests and callable ABI JSON files into `apps/<dapp>/deploy`?

---
name: app-dapp-zk-l2
description: Create or review new DApp projects under `apps/` in this repository. Use when adding app-level smart contracts, storage layouts, bridge-coupled vault models, or user-facing entrypoints that must assume a zero-knowledge proof based L2 privacy model, remain convertible into fixed circuits, and scale storage across multiple contract addresses when needed.
---

# App Dapp Zk L2

Follow this skill whenever a new DApp is created under `apps/` or when an existing app-level DApp is reworked in a way that changes user-facing contract flows, state layout, or note/accounting models.

## Documentation Writing Quality

When writing or editing DApp documentation, every sentence, paragraph, section, and
document must have a logical flow. The writing must carry the reader smoothly from the
problem or thesis, through the reasoning, to the conclusion. Do not leave a statement
hanging after presenting a fact. Explain why the fact matters, what it enables, what risk
it creates, or what conclusion follows from it.

Each paragraph should give the reader a reason to continue. Avoid writing lists of true
statements that do not explain their own relevance. Prefer a progression such as:

1. introduce the problem, concept, or claim
2. define the terms needed to understand it
3. explain the mechanism or reasoning
4. give a concrete example when the concept is not common
5. state the resulting implication or conclusion

For any concept or term that is not ordinary, universal, or already established in the
same document, define it accurately and clearly before relying on it. When a definition
is subtle, include an example that shows how the term is used in the system. The example
should reduce ambiguity, not add another unexplained abstraction.

Before finishing documentation work, review the edited text as a third-party reader:

- Can the reader tell why each sentence is present?
- Does each paragraph have a clear conclusion or implication?
- Does each section follow naturally from the previous section?
- Are nonstandard terms defined before they are used as premises?
- Are examples included where a new concept would otherwise be hard to internalize?

## Workflow

1. Read [references/design-checklist.md](references/design-checklist.md) before proposing or reviewing the contract architecture.
2. Treat the zk-L2 execution model as a hard assumption:
   - Raw transaction contents are private to the caller.
   - Public outputs are limited to proofs and resulting state transitions.
   - Do not add calldata-hiding mechanisms as if the contracts were executing directly on public L1.
   - Do not assume the runtime cryptographic primitives are the same as Ethereum L1.
   - Under the TokamakL2JS execution spec, runtime `keccak256` behavior is replaced by Poseidon-based hashing, and transaction-signature semantics use EdDSA rather than Ethereum ECDSA.
   - When mirroring contract execution off-chain in CLIs, example generators, replay tools, or tests, use the `tokamak-l2js` cryptographic helpers that match the L2 spec instead of L1 defaults.
   - Use `poseidon(msg)` when the contract-side hash input is byte-oriented, and use `poseidonChainCompress(inVals)` when the modeled input is already a field-element sequence.
   - Treat `ecrecover`-style assumptions as invalid in this environment. When the spec requires public-key recovery, use `getEddsaPublicKey(...)`.
3. Treat bridge-managed custody as a hard architectural rule for every DApp under `apps/`:
   - L1 keeps the canonical asset custody.
   - L2 keeps accounting state only.
   - Users may interact directly with the L1 bridge custody vault, but not with the L2 accounting vault.
   - L2 accounting balances may change only through state transitions that the L1 bridge accepts after proof verification.
   - Do not add user-facing L2 deposit or L2 withdraw functions that move assets independently of the L1 bridge flow.
4. Identify the final user-facing functions first.
   - Design those functions so successful execution has one symbolic path only.
   - Split multi-mode behavior into separate functions instead of keeping several successful branches inside one entrypoint.
5. Run the symbolic-path checker on every final user-facing contract after each substantial edit:

```bash
python3 .codex/skills/app-dapp-zk-l2/scripts/check_unique_success_paths.py \
  apps/<dapp>/src/<Contract>.sol --contract <Contract>
```

6. If storage growth is likely to be material, prefer splitting storage across multiple contract addresses rather than forcing all state into one address.
7. Optimize contract bytecode at the function level across every DApp under `apps/`:
   - Keep each contract function limited to the operations that are strictly necessary for its state transition.
   - Remove avoidable dynamic-array copies, generic dispatch layers, mode-switch helpers, and other scaffolding when a fixed-arity or direct path is sufficient.
   - For repeated work in user-facing contract functions, do not use loops. Flatten and unroll the logic into a fixed-arity path instead, even when the loop body is branch-free.
   - Prefer specialized helper functions when they materially reduce bytecode and do not reintroduce multiple successful symbolic paths.
   - Review whether reusable abstractions are actually paying for themselves; if they only add indirection and bytecode, inline or split them.
   - Treat Synthesizer placements as a first-class optimization budget. Placements are the circuit-side resource units emitted while the Synthesizer models EVM execution. Every user-facing function should be implemented to minimize placement usage, not just Solidity source length.
   - When a function is placement-heavy, identify whether the cost comes from calldata copying, loop control, helper indirection, repeated hashing, repeated storage calls, or external contract boundaries.
   - Do not treat memory usage by itself as a placement problem. Plain memory movement such as direct `calldataload` plus `mstore` of fixed-size words is often cheap. The placement-heavy part is usually the encoding or decoding scaffolding wrapped around the memory movement.
   - Prioritize removing ABI encoding, ABI decoding, packing, unpacking, and generic shape-conversion work before trying to optimize raw memory copies that are already fixed-shape word moves.
   - Treat loop control itself as avoidable placement overhead in hot paths. If a function arity is known at compile time, encode each repeated operation explicitly instead of iterating.
   - If direct low-level coding materially reduces placement usage without violating correctness or the single-success-path rule, assembly blocks are allowed.
   - For fixed-shape runtime hash inputs, do not default to `keccak256(abi.encode(...))` or equivalent scaffolding when the input words are already known statically. Prefer `memory-safe` assembly that writes each word directly with `mstore` and then calls `keccak256(ptr, len)`.
   - For repeated mapping reads/writes in hot note or account paths, actively consider `memory-safe` assembly that computes the mapping storage key once and reuses it for `sload`, `sstore`, and any required storage-key observation log. This can remove placement-heavy duplicate key hashing and high-level mapping scaffolding while preserving the same storage layout.
   - When using assembly for hash-input staging, allocate scratch space from the current free-memory pointer (`mload(0x40)`) and advance the free-memory pointer afterward. Do not reuse ad hoc offsets such as `0x00` or `0x80` in ways that can collide with future manual memory management.
   - Apply the same discipline to any L2-runtime hash mirror that is modeled off-chain. If the contract executes a fixed-shape runtime hash, the off-chain generator or test harness should mirror the same fixed-shape input layout rather than rebuild it through avoidable generic encoding layers.
   - Do not add explicit zero-hash guards by default for note commitments, nullifiers, or similar cryptographic digests. Treat a zero hash output as practically impossible unless the task explicitly requires a defensive zero-value guard for some non-cryptographic reason.
8. Every DApp under `apps/` must use the same L2 accounting vault shape:
   - Prefer naming such as `L1BridgeAssetVault` for L1 custody and `L2AccountingVault` for the L2 mirror state.
   - The L2 vault is not a real token custody contract.
   - Keep its storage layout standardized across DApps and restrict it to bridge-coupled accounting concerns.
   - If an app needs extra per-user accounting, build it around the shared L2 accounting vault pattern rather than inventing a custom direct-custody vault.
   - Every L2 vault mutation must enforce both overflow and underflow safety against the BLS12-381 scalar field, not only against native `uint256` wraparound.
   - On credit paths, reject any balance increase that would make the stored balance exceed `BLS12-381 scalar field order - 1`.
   - On debit paths, reject any subtraction that would move the stored balance below zero under the same field-bound accounting model.
9. Remove contract-level owner roles from app contracts by default:
   - Do not add `Ownable` or similar admin roles unless the task explicitly requires an operational admin path.
   - If a DApp needs a controller, bind that relationship at deployment time rather than through a mutable owner-controlled setter.
   - Prefer constructor-bound immutable controller addresses.
   - When the controller and storage contracts depend on each other, use deterministic address prediction and CREATE2 in the app-local deployment flow instead of adding post-deployment controller registration.
10. Keep DApp deployment assets isolated from bridge deployment assets:
   - Store each DApp deployment script under `apps/<dapp>/scripts/deploy`.
   - Store local anvil helpers under `apps/<dapp>/scripts/anvil` when the DApp needs a local development chain workflow.
   - Store app deployment parameters in `apps/.env`.
   - Share the deployment signer and target network across DApps through common app-level variables.
   - Prefer an app-level provider key plus network name, then derive the RPC URL and chain ID inside the DApp deployment script.
   - Default `APPS_NETWORK=anvil` to `http://127.0.0.1:8545` for local development.
   - Keep `APPS_RPC_URL_OVERRIDE` only as an advanced option for nonstandard local or custom RPC endpoints.
   - Namespace only DApp-specific deployment values, for example `PRIVATE_STATE_CANONICAL_ASSET`.
   - Do not add per-DApp owner env variables in the default app deployment model.
   - Do not reuse the bridge deployment script directory or the bridge deployment `.env` for app deployment.
   - Write deployment manifests, one deployed-contract storage-layout manifest, and callable ABI JSON files into `apps/<dapp>/deploy`.
   - The storage-layout manifest must contain the deployed contract addresses plus the compiler-reported storage layout for each deployed contract.
   - Repository-owned code under `apps/`, `bridge/`, `scripts/`, or other root modules must use the published Tokamak zk-EVM npm packages instead of a top-level Tokamak zk-EVM source checkout.
   - If external Tokamak tooling needs deployment or storage-layout artifacts from this repository, publish or copy those artifacts through an explicit repository-owned export flow instead of making that tooling read parent-repository paths implicitly.
11. Provide a DApp-local CLI under `apps/<dapp>/cli`:
   - Use a terminal CLI, not a browser application.
   - Include target-network selection limited to `mainnet`, `sepolia`, and `anvil`, plus optional private-key input for signed transactions.
   - Resolve contract addresses from `apps/<dapp>/deploy/deployment.<chain-id>.latest.json`.
   - Load callable ABIs from `apps/<dapp>/deploy/*.callable-abi.json`.
   - Keep one function template folder per callable function under `apps/<dapp>/cli/functions/<function-name>/calldata.json`.
   - If duplicate function names exist across contracts, explicitly document how collisions are resolved instead of silently overwriting folders.
12. Provide concise DApp-local command wrappers:
   - Prefer `apps/<dapp>/Makefile`.
   - Include short commands for local anvil start/bootstrap/stop, local tests, and public-network deployment.
   - Prefer targets such as `make anvil-start`, `make anvil-bootstrap`, `make anvil-stop`, `make test`, `make deploy-sepolia`, `make deploy-mainnet`, and `make cli-list`.
   - If a command must target a different network than the one stored in `apps/.env`, create a temporary env override inside the wrapper instead of requiring the operator to edit `apps/.env`.
13. Require Synthesizer compatibility tests for every user-facing DApp function:
   - Store them under `apps/<dapp>/scripts/synthesizer-compat-test`.
   - Provide one entry script per user-facing function, even if the scripts delegate to shared helpers.
   - Use the published `@tokamak-zk-evm/synthesizer-node` or `@tokamak-zk-evm/cli` entrypoint for Synthesizer execution.
   - Ensure the generated transactions, hash expectations, and storage-key derivations mirror the TokamakL2 runtime spec rather than raw Ethereum L1 execution assumptions.
   - In particular, when a contract uses runtime `keccak256(...)`, model the resulting value with the TokamakL2 Poseidon replacement semantics in the test harness and example generator.
   - Hold `block_info.json` and `contract_codes.json` fixed for a given function test.
   - Vary `previous_state_snapshot.json` and the transaction RLP across multiple valid private-input configurations for the same function.
   - Keep `previous_state_snapshot.json` faithful to actual pre-state only. Do not pre-register storage keys that exist only because the tested transaction will write them later.
   - Derive any statically known `preAllocatedKeys` from the deployed contracts' storage-layout manifest under `apps/<dapp>/deploy`. Do not rely on hardcoded default keys.
   - Registered keys must include the real from-side keys that the transaction consumes from pre-state, such as the debited liquid-balance slot in mint or the consumed note-commitment slots in transfer and redeem.
   - To-side keys are optional in compatibility fixtures. For example, receiver or output-side slots may remain absent even if the transaction will read-then-write them during execution.
   - Apply the same rule to L2 vault balance keys. Register the debited from-side balance key when it exists in pre-state, but do not treat receiver-side balance keys as mandatory fixture inputs.
   - Do not absorb unregistered-storage warnings back into the config as synthetic `registeredKeys` beyond the required from-side consumed keys. If an optional key is not present in the actual pre-state, leave it absent and fix the modeling issue elsewhere.
   - For each variant, run the Synthesizer CLI and assert that `outputs/instance.json -> a_pub_function` and `outputs/permutation.json` remain identical across the tested variants for that function.
   - Treat the absence of these scripts as a missing DApp deliverable, not as optional test coverage.
14. Keep the review explicit in the final response:
   - State whether the entrypoints satisfy the zk-L2 privacy assumption.
   - State whether the successful symbolic path for each user-facing function appears unique.
   - State whether the implementation keeps function bytecode focused on strictly necessary operations or still contains avoidable scaffolding.
   - State whether the implementation also minimizes Synthesizer placement usage or still contains avoidable placement-heavy logic.
   - State whether the app respects bridge-managed custody and avoids direct user interaction with the L2 accounting vault.
   - State whether every L2 vault mutation is guarded against BLS12-381 scalar-field overflow and underflow.
   - State whether storage should remain centralized or be split across addresses.
   - State whether deployment scripts and env configuration are isolated under the DApp folder and `apps/.env`.
   - State whether admin ownership was removed and whether any remaining controller wiring is immutable and deployment-bound.
   - State whether the DApp exposes a local CLI under `apps/<dapp>/cli` that reads `calldata.json` templates, deployment manifests, and callable ABI files.
   - State whether the DApp also exposes concise DApp-local command wrappers for anvil workflows, tests, and deployment.
   - State whether the DApp also exposes per-function Synthesizer compatibility scripts under `apps/<dapp>/scripts/synthesizer-compat-test`.

## Resources

- [references/design-checklist.md](references/design-checklist.md)
  Use for the architectural rules and review checklist that apply to every new DApp under `apps/`.
- `scripts/check_unique_success_paths.py`
  Use as a conservative static analyzer for successful symbolic path uniqueness in external/public state-changing functions.

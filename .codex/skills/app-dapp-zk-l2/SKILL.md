---
name: app-dapp-zk-l2
description: Create or review new DApp projects under `apps/` in this repository. Use when adding app-level smart contracts, storage layouts, bridge-coupled vault models, or user-facing entrypoints that must assume a zero-knowledge proof based L2 privacy model, remain convertible into fixed circuits, and scale storage across multiple contract addresses when needed.
---

# App Dapp Zk L2

Follow this skill whenever a new DApp is created under `apps/` or when an existing app-level DApp is reworked in a way that changes user-facing contract flows, state layout, or note/accounting models.

## Workflow

1. Read [references/design-checklist.md](references/design-checklist.md) before proposing or reviewing the contract architecture.
2. Treat the zk-L2 execution model as a hard assumption:
   - Raw transaction contents are private to the caller.
   - Public outputs are limited to proofs and resulting state transitions.
   - Do not add calldata-hiding mechanisms as if the contracts were executing directly on public L1.
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
   - Treat loop control itself as avoidable placement overhead in hot paths. If a function arity is known at compile time, encode each repeated operation explicitly instead of iterating.
   - If direct low-level coding materially reduces placement usage without violating correctness or the single-success-path rule, assembly blocks are allowed.
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
   - Store each DApp deployment script under `apps/<dapp>/script/deploy`.
   - Store local anvil helpers under `apps/<dapp>/script/anvil` when the DApp needs a local development chain workflow.
   - Store app deployment parameters in `apps/.env`.
   - Share the deployment signer and target network across DApps through common app-level variables.
   - Prefer an app-level provider key plus network name, then derive the RPC URL and chain ID inside the DApp deployment script.
   - Default `APPS_NETWORK=anvil` to `http://127.0.0.1:8545` for local development.
   - Keep `APPS_RPC_URL_OVERRIDE` only as an advanced option for nonstandard local or custom RPC endpoints.
   - Namespace only DApp-specific deployment values, for example `PRIVATE_STATE_CANONICAL_ASSET`.
   - Do not add per-DApp owner env variables in the default app deployment model.
   - Do not reuse the bridge deployment script directory or the bridge deployment `.env` for app deployment.
   - Write deployment manifests and callable ABI JSON files into `apps/<dapp>/deploy`.
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
   - Store them under `apps/<dapp>/script/synthesizer-compat-test`.
   - Provide one entry script per user-facing function, even if the scripts delegate to shared helpers.
   - Use `submodules/Tokamak-zk-EVM/packages/frontend/synthesizer/src/interface/cli/index.ts` as the execution entrypoint.
   - Hold `block_info.json` and `contract_codes.json` fixed for a given function test.
   - Vary `previous_state_snapshot.json` and the transaction RLP across multiple valid private-input configurations for the same function.
   - Keep `previous_state_snapshot.json` faithful to actual pre-state only. Do not pre-register storage keys that exist only because the tested transaction will write them later.
   - Do not absorb unregistered-storage warnings back into the config as synthetic `registeredKeys`. If a key is not present in the actual pre-state, leave it absent and fix the modeling issue elsewhere.
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
   - State whether the DApp also exposes per-function Synthesizer compatibility scripts under `apps/<dapp>/script/synthesizer-compat-test`.

## Resources

- [references/design-checklist.md](references/design-checklist.md)
  Use for the architectural rules and review checklist that apply to every new DApp under `apps/`.
- `scripts/check_unique_success_paths.py`
  Use as a conservative static analyzer for successful symbolic path uniqueness in external/public state-changing functions.

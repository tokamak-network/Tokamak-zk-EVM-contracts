# zk-L2 App DApp Design Checklist

Use this checklist when creating or reviewing a new DApp project under `apps/`.

## 1. zk-L2 Privacy Assumption

Treat the following as fixed system assumptions:

- Every user transaction is converted locally into a proof before publication.
- L1 verifies proofs rather than the raw transaction body.
- The original transaction body is visible only to the caller.
- Other users and L1 observers see proofs and the resulting state transitions, not the original calldata.

Design implications:

- Do not justify plaintext leakage by assuming direct L1 execution.
- Do not add calldata privacy workarounds whose only purpose is to hide data from public L1 mempools.
- Focus privacy review on the data that becomes state, events, or proof-linked public outputs.

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

Review questions:

- Does the L2 vault store accounting balances only?
- Can any user bypass the bridge flow and mutate L2 balances directly?
- Does the DApp introduce a second L2-specific vault shape instead of reusing the standard one?

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

## 7. Admin and Controller Wiring

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
- If address prediction is used, is the deployment flow deterministic and explicitly documented?

## 8. Review Output

When reporting on a new app design, explicitly answer:

1. What information becomes public state or events despite the zk-L2 privacy assumption?
2. Does the design keep canonical custody on L1 and L2 balances as accounting-only state?
3. Does the app reuse the standard L2 accounting vault shape?
4. Which external functions are the final user-facing entrypoints?
5. Does each such function have exactly one successful symbolic path?
6. Did the checker flag anything, and if so, why is it acceptable or how should it be refactored?
7. Should storage remain in one address or be split across multiple addresses?
8. Are deployment scripts stored under `apps/<dapp>/script/deploy` instead of the bridge deployment script tree?
9. Are app deployment secrets and network settings isolated in `apps/.env`, with shared app-level signer and provider-key-plus-network variables plus DApp-specific namespaced values only where needed, with `APPS_NETWORK=anvil` defaulting to localhost and `APPS_RPC_URL_OVERRIDE` reserved for nonstandard RPC overrides?
10. Does the DApp provide a local terminal CLI under `apps/<dapp>/cli`, limited to `mainnet`, `sepolia`, and `anvil`, and does that CLI read per-function `calldata.json` templates plus deployment manifests and callable ABI JSON files?
11. If duplicate callable function names exist across contracts, is the CLI folder naming collision handled explicitly and documented?
12. Was contract-level admin ownership removed where it was not strictly necessary?
13. If a controller exists, is it wired immutably at deployment time rather than through a mutable admin step?
14. Does the DApp provide local anvil helpers under `apps/<dapp>/script/anvil` when local-chain testing is required, and does it write manifests and callable ABI JSON files into `apps/<dapp>/deploy`?

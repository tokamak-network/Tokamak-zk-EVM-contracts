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

## 2. Circuit-Convertible User Entry Points

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

## 3. Symbolic-Path Checking Tool

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

## 4. Storage Layout Guidance

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

- Asset custody store
- Note or commitment store
- Nullifier or spent-state store
- Order, market, or position store
- Metadata or indexing store

Review questions:

- Which state families can grow independently?
- Which state must remain atomically consistent?
- Which state can be isolated behind a coordinator without duplicating truth?
- Is any field duplicated across stores when one canonical source would suffice?

## 5. Review Output

When reporting on a new app design, explicitly answer:

1. What information becomes public state or events despite the zk-L2 privacy assumption?
2. Which external functions are the final user-facing entrypoints?
3. Does each such function have exactly one successful symbolic path?
4. Did the checker flag anything, and if so, why is it acceptable or how should it be refactored?
5. Should storage remain in one address or be split across multiple addresses?

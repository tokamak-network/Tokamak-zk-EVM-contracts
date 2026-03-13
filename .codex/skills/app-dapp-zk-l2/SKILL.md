---
name: app-dapp-zk-l2
description: Create or review new DApp projects under `apps/` in this repository. Use when adding app-level smart contracts, storage layouts, or user-facing entrypoints that must assume a zero-knowledge proof based L2 privacy model, remain convertible into fixed circuits, and scale storage across multiple contract addresses when needed.
---

# App Dapp Zk L2

Follow this skill whenever a new DApp is created under `apps/` or when an existing app-level DApp is reworked in a way that changes user-facing contract flows, state layout, or note/accounting models.

## Workflow

1. Read [references/design-checklist.md](references/design-checklist.md) before proposing or reviewing the contract architecture.
2. Treat the zk-L2 execution model as a hard assumption:
   - Raw transaction contents are private to the caller.
   - Public outputs are limited to proofs and resulting state transitions.
   - Do not add calldata-hiding mechanisms as if the contracts were executing directly on public L1.
3. Identify the final user-facing functions first.
   - Design those functions so successful execution has one symbolic path only.
   - Split multi-mode behavior into separate functions instead of keeping several successful branches inside one entrypoint.
4. Run the symbolic-path checker on every final user-facing contract after each substantial edit:

```bash
python3 .codex/skills/app-dapp-zk-l2/scripts/check_unique_success_paths.py \
  apps/<dapp>/src/<Contract>.sol --contract <Contract>
```

5. If storage growth is likely to be material, prefer splitting storage across multiple contract addresses rather than forcing all state into one address.
6. Keep the review explicit in the final response:
   - State whether the entrypoints satisfy the zk-L2 privacy assumption.
   - State whether the successful symbolic path for each user-facing function appears unique.
   - State whether storage should remain centralized or be split across addresses.

## Resources

- [references/design-checklist.md](references/design-checklist.md)
  Use for the architectural rules and review checklist that apply to every new DApp under `apps/`.
- `scripts/check_unique_success_paths.py`
  Use as a conservative static analyzer for successful symbolic path uniqueness in external/public state-changing functions.

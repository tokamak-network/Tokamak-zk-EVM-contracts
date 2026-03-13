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
7. Every DApp under `apps/` must use the same L2 accounting vault shape:
   - Prefer naming such as `L1BridgeAssetVault` for L1 custody and `L2AccountingVault` for the L2 mirror state.
   - The L2 vault is not a real token custody contract.
   - Keep its storage layout standardized across DApps and restrict it to bridge-coupled accounting concerns.
   - If an app needs extra per-user accounting, build it around the shared L2 accounting vault pattern rather than inventing a custom direct-custody vault.
8. Keep DApp deployment assets isolated from bridge deployment assets:
   - Store each DApp deployment script under `apps/<dapp>/script/deploy`.
   - Store app deployment parameters in `apps/.env`.
   - Share the deployment signer and target network across DApps through common app-level variables.
   - Keep the shared deployment signer as the initial owner for DApp contracts created through that deployment flow.
   - Namespace only DApp-specific deployment values, for example `PRIVATE_STATE_CANONICAL_ASSET`.
   - Do not add per-DApp owner env variables unless an explicit post-deployment ownership transfer requirement exists.
   - Do not reuse the bridge deployment script directory or the bridge deployment `.env` for app deployment.
9. Keep the review explicit in the final response:
   - State whether the entrypoints satisfy the zk-L2 privacy assumption.
   - State whether the successful symbolic path for each user-facing function appears unique.
   - State whether the app respects bridge-managed custody and avoids direct user interaction with the L2 accounting vault.
   - State whether storage should remain centralized or be split across addresses.
   - State whether deployment scripts and env configuration are isolated under the DApp folder and `apps/.env`.

## Resources

- [references/design-checklist.md](references/design-checklist.md)
  Use for the architectural rules and review checklist that apply to every new DApp under `apps/`.
- `scripts/check_unique_success_paths.py`
  Use as a conservative static analyzer for successful symbolic path uniqueness in external/public state-changing functions.

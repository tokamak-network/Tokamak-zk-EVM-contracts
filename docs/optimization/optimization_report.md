# Optimization Report

## Source Series (gas usage by snapshot commit)
| date | commits | change summary | gas usage | mini-report |
|---|---|---|---:|---|
| 2026-02-13 | `0dc0989` | Added the initial section-based gas breakdown and baseline verifier snapshot. | 1,201,029 | [mini-report](mini-reports/2026-02-13_0dc0989.md) |
| 2026-02-13 | `874b29e`<br>`aa30297`<br>`579e1f4`<br>`50030b0` | Added Rust comparison and equation-placement clarification, then optimized `computeAPUB` (dead `modexp` removal, `omega^i` reuse, batch inversion). | 980,360 | [mini-report](mini-reports/2026-02-13_50030b0.md) |
| 2026-02-14 | `73daa15` | Consolidated Step 4 MSM usage (`prepareLHSA`/`prepareLHSC`/`prepareRHS*`/aggregation) to reduce precompile overhead. | 930,866 | [mini-report](mini-reports/2026-02-14_73daa15.md) |
| 2026-02-15 | `2f59123`<br>`6f5394b` | Expanded measured-gas checkpointing and then refactored Step 4 into a single 22-term MSM for `[LHS]+[AUX]`. | 821,775 | [mini-report](mini-reports/2026-02-15_6f5394b.md) |

## Notes
- Source rows are included only when gas decreases by at least 5% versus the immediately previous snapshot.
- Snapshot values are taken from `docs/tokamak-verifier-gas-sections.md` (Measured Gas checkpoints).
- Latest snapshot commit `f483cc4` reports `785,531`, which is `4.41%` lower than `821,775`; below the 5% threshold, so no new Source Series row was added.

# Optimization Report

## Source Series (gas usage by snapshot commit)
| date | commits | change summary | gas usage | mini-report |
|---|---|---|---:|---|
| 2026-02-13 | `0dc0989` | Added the initial section-based gas breakdown and baseline verifier snapshot. | 1,201,029 | [mini-report](mini-reports/2026-02-13_0dc0989.md) |
| 2026-02-13 | `874b29e`<br>`aa30297`<br>`579e1f4`<br>`50030b0` | Added Rust comparison and equation-placement clarification, then optimized `computeAPUB` (dead `modexp` removal, `omega^i` reuse, batch inversion). | 980,360 | [mini-report](mini-reports/2026-02-13_50030b0.md) |
| 2026-02-14 | `73daa15` | Consolidated Step 4 MSM usage (`prepareLHSA`/`prepareLHSC`/`prepareRHS*`/aggregation) to reduce precompile overhead. | 930,866 | [mini-report](mini-reports/2026-02-14_73daa15.md) |
| 2026-02-15 | `2f59123`<br>`6f5394b`<br>`d03c5b6`<br>`f483cc4` | Expanded measured-gas checkpointing, refactored Step 4 into one 22-term MSM, refreshed gas/report baselines, and tightened `computeAPUB` loop/memory arithmetic. | 785,531 | [mini-report](mini-reports/2026-02-15_f483cc4.md) |
| 2026-02-15 | `65ad49e`<br>`a33c220`<br>`1e4c03e`<br>`a5273e9`<br>`e476a81`<br>`8c1455f`<br>`ae99e6b` | Folded verifier/spec sync updates, switched fixture loading to JSON inputs, and added build-time VK code generation from `sigma_verify.json`; measured snapshot dropped to a lower runtime profile. | 655,104 | [mini-report](mini-reports/2026-02-15_ae99e6b.md) |

## Notes
- Source rows are created only when gas decreases by at least 5% versus the immediately previous snapshot.
- Commits with <5% incremental decrease are folded into the latest Source Series row.
- Snapshot values are taken from `docs/tokamak-verifier-gas-sections.md` (Measured Gas checkpoints).

# Lessons

## 2026-02-13
- When comments and code disagree, treat runtime operations as source of truth and explicitly annotate any algebraic term relocation across sections (for example, `-kappa1*Vxy*[1]` moved from `prepareLHSA` to `prepareLHSC:d[1]`).
- Before concluding a formula mismatch, expand the final aggregated equation path (`LHS = LHS_B + kappa2*(LHS_A + LHS_C)`) and verify whether the missing term is reintroduced elsewhere.

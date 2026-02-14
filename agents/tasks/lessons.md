# Lessons

## 2026-02-13
- When comments and code disagree, treat runtime operations as source of truth and explicitly annotate any algebraic term relocation across sections (for example, `-kappa1*Vxy*[1]` moved from `prepareLHSA` to `prepareLHSC:d[1]`).
- Before concluding a formula mismatch, expand the final aggregated equation path (`LHS = LHS_B + kappa2*(LHS_A + LHS_C)`) and verify whether the missing term is reintroduced elsewhere.

## 2026-02-14
- When reasoning about gas impact, distinguish symbolic parameters from actual loop bounds in code. In `computeAPUB`, loop length is controlled by `numPublicInputs`, not directly by `n`; verify both assignments before estimating savings.
- When proof format ownership changes for a term (e.g., `A_fix` moving from `_proof` to `_preprocessed`), update all three together: calldata source offsets, length validation, and section comments/spec notes. Partial migration causes silent malformed loads and expensive downstream precompile failures.
- When `verifier-spec.md` formula ownership changes (e.g., a term moving from `[LHS]` to final pairing RHS), update both artifacts in lockstep: the spec's summary coefficient table and the Solidity aggregation implementation. Keeping only one side updated introduces algebraic inconsistency.
- When domain terminology changes in the proof format, rename code identifiers to the canonical term end-to-end (constants, load paths, and pairing usage). Mixed naming like `A_fix` vs `O_pub,fix` increases integration errors even when data layout is identical.
- In polynomial-evaluation code, if two parameters are semantically the same domain size (e.g., `n` and `numPublicInputs`), model them as a single variable (`l_free`) to avoid divergence bugs and reduce maintenance overhead.

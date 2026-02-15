# TokamakVerifier Gas Profiling Todo

## 2026-02-15 Update Plan (Build-time VK Codegen from sigma_verify.json)
- [x] Add a deterministic codegen script that reads `src/verifier/TokamakVerifierKey/sigma_verify.json` and emits Solidity VK constants.
- [x] Introduce a generated Solidity key module and wire `TokamakVerifier._loadVerificationKey()` to consume generated constants instead of hardcoded literal values.
- [x] Add npm scripts so build/test paths can regenerate VK constants before compilation.
- [x] Run codegen + `forge build` + focused verifier tests to validate no functional regression.
- [x] Record review note with exact validation commands and outcomes.

### 2026-02-15 Review Note (Build-time VK Codegen from sigma_verify.json)
- Validation commands:
  - `npm run gen:tokamak-vk`
  - `forge build`
  - `forge test --match-contract testTokamakVerifier --offline -vv`
- Result:
  - Generated VK module successfully from `sigma_verify.json`.
  - `TokamakVerifier` compiles with generated constants wired into `_loadVerificationKey()`.
  - `testTokamakVerifier` suite passed (`5 passed, 0 failed`).

## 2026-02-14 Update Plan (computeAPUB l_free Unification)
- [x] Add `OMEGA_64` constant for the 64-sized free-input domain.
- [x] Refactor `computeAPUB()` to replace separate `n`/`numPublicInputs` with single `l_free`.
- [x] Set `l_free = 64` and switch the domain root to `OMEGA_64`.
- [x] Update loop bounds/comments/denominator scaling to use `l_free` consistently.
- [x] Run focused verifier test for compile/runtime sanity.

### 2026-02-14 Review Note (computeAPUB l_free Unification)
- Validation command:
  - `forge test --match-contract testTokamakVerifier --match-test testVerifier --offline`
- Result:
  - Contract compiles successfully.
  - Existing fixture still fails at `loadProof: Proof is invalid` due the currently-mismatched preprocessed-proof format in tests.

## 2026-02-14 Update Plan (Naming Sync: A_fix -> O_pub,fix in loadProof)
- [x] Replace `A_fix` naming in `loadProof()` with `O_pub,fix` to match latest proof-format semantics.
- [x] Rename memory slot constants from `PROOF_POLY_A_FIX_*` to `PROOF_POLY_OPUB_FIX_*`.
- [x] Update final pairing accumulation to read from renamed `O_pub,fix` slots.
- [x] Compile/test verifier path to confirm no build regressions.

### 2026-02-14 Review Note (Naming Sync: A_fix -> O_pub,fix)
- Validation command:
  - `forge test --match-contract testTokamakVerifier --match-test testVerifier --offline`
- Result:
  - Build succeeds.
  - Existing fixture still fails at `loadProof: Proof is invalid` because test vectors are not migrated to the new preprocessed input shape.

## 2026-02-14 Update Plan (Spec Sync: Pairing Equation Revision)
- [x] Read updated `docs/verifier-spec.md` final pairing equation and identify affected algebraic ownership (`A_fix` movement from LHS to RHS pairing side).
- [x] Update `docs/verifier-spec.md` summary coefficient table to match revised `LHS_B` and remove stale `A_fix` term from `[LHS]_1+[AUX]_1`.
- [x] Update `src/verifier/TokamakVerifier.sol` Step4 MSM to match new summary (22 terms, no `A_fix` term in LHS aggregation).
- [x] Update `src/verifier/TokamakVerifier.sol` final pairing implementation to pair `([O_{pub,fix}] + [O_{pub,free}])` against `[γ]_2`.
- [x] Compile/run focused verifier test and capture compatibility status.

### 2026-02-14 Review Note (Spec Sync: Pairing Equation Revision)
- Validation commands:
  - `forge test --match-contract testTokamakVerifier --match-test testVerifier --offline`
  - `forge test --match-contract testTokamakVerifier --match-test testVerifier --offline -vvvv`
- Result:
  - Build succeeds.
  - Existing fixture still fails at `loadProof: Proof is invalid` (fixture not yet migrated to new preprocessed format carrying `A_fix/O_pub,fix`).

## 2026-02-14 Update Plan (A Source Split: A_fix from preprocessed, A_free from proof)
- [x] Rewire `loadProof()` so `A_fix` is decoded from `_preprocessedPart1/_preprocessedPart2`.
- [x] Keep `A_free` decoded from `_proof` and restore proof length/offset layout accordingly.
- [x] Add strict length guards for the new preprocessed format (`6/6` words).
- [x] Run verifier test path and capture compatibility outcome.

### 2026-02-14 Review Note (A Source Split)
- Validation commands:
  - `forge test --match-contract testTokamakVerifier --match-test testVerifier --offline`
  - `forge test --match-contract testTokamakVerifier --match-test testVerifier --offline -vvvv`
- Result:
  - Build succeeds.
  - Existing fixture reverts at `loadProof: Proof is invalid` because it still supplies old preprocessed shape (without `A_fix` words).

## 2026-02-14 Update Plan (Proof Format Split: A_fix/A_free)
- [x] Identify all `A` commitment load/use paths in `TokamakVerifier.sol` and define safe memory slots for `A_fix`.
- [x] Update proof decoding format in `loadProof()` from single `A` to `A_fix` + `A_free` (length/offset changes included).
- [x] Update Step 4 MSM assembly to apply separate coefficients to `A_fix` and `A_free`.
- [x] Compile and run verifier test path to confirm code-level integration status.
- [x] Record review note and compatibility impact.

### 2026-02-14 Review Note (Proof Format Split: A_fix/A_free)
- Validation command:
  - `forge test --match-contract testTokamakVerifier --match-test testVerifier --offline -vvvv`
- Result:
  - Contract compiles successfully.
  - Existing fixture test fails with `loadProof: Proof is invalid` because test vectors still use old proof lengths (`38/42`) while verifier now requires new format (`40/44`) and shifted scalar offsets.

## 2026-02-14 Update Plan (Refresh Gas Doc for Latest Verifier)
- [x] Align `docs/tokamak-verifier-gas-sections.md` function references and section descriptions with current `TokamakVerifier.sol`.
- [x] Update residual/hotspot/verification notes to include latest (`HEAD`) metrics.
- [x] Refresh Rust comparison table and functional-difference summary to match current Step 4 implementation (`prepareLhsAuxSingleMSM`).
- [x] Re-validate measured numbers against latest trace output and finalize review note.

### 2026-02-14 Review Note (Refresh Gas Doc for Latest Verifier)
- Validation command:
  - `NO_PROXY='*' no_proxy='*' forge test --match-contract testTokamakVerifier --match-test testVerifier -vvvv --offline`
- Confirmed latest trace values still match doc:
  - `verify = 821,775`
  - precompile subtotal = `601,120`
  - sequence: `modexp x7`, `g1msm x3`, `pairing x1`

## 2026-02-14 Update Plan (Single-MSM LHS+AUX Refactor)
- [x] Refactor `TokamakVerifier.sol` to compute `[LHS]_1 + [AUX]_1` using a single 22-term MSM call based on `docs/verifier-spec.md` summary table.
- [x] Wire the new flow into `verify()` and keep pairing inputs behaviorally equivalent.
- [x] Run verifier tests and confirm functional correctness.
- [x] Measure gas with `forge test -vvvv --offline` and compute savings vs current (`73daa15`) baseline.
- [x] Record optimization details and measured gas deltas in `docs/tokamak-verifier-gas-sections.md`.
- [x] Add review note to this task file.

### 2026-02-14 Review Note (Single-MSM LHS+AUX Refactor)
- Validation commands:
  - `NO_PROXY='*' no_proxy='*' forge test --match-contract testTokamakVerifier --match-test testVerifier -vvvv --offline`
  - `NO_PROXY='*' no_proxy='*' forge test --match-contract testTokamakVerifier --offline`
- Verified results:
  - `TokamakVerifier::verify` gas: `930,866 -> 821,775` (`-109,091`)
  - precompile subtotal: `707,649 -> 601,120` (`-106,529`)
  - call counts after refactor: `0x0c` MSM `3`, `0x0b` G1ADD `0`, `0x05` modexp `7`, pairing `1`

## 2026-02-14 Update Plan (TokamakVerifier Dead Code Cleanup)
- [x] Remove unused constants and stale memory slots left after Step 4 refactor.
- [x] Remove unused local assembly helper functions in `verify`.
- [x] Run verifier tests and trace sanity-check gas behavior.
- [x] Record validation note in this task file.

### 2026-02-14 Review Note (TokamakVerifier Dead Code Cleanup)
- Validation commands:
  - `NO_PROXY='*' no_proxy='*' forge test --match-contract testTokamakVerifier --offline`
  - `NO_PROXY='*' no_proxy='*' forge test --match-contract testTokamakVerifier --match-test testVerifier -vvvv --offline`
- Verified results:
  - all `testTokamakVerifier` tests passed (5/5)
  - `TokamakVerifier::verify` remained `821,775` gas after cleanup (no behavioral regression observed)

## 2026-02-14 Update Plan (Measured Gas Table Expansion)
- [x] Extract section-level precompile gas for optimization checkpoint `50030b0` (`computeAPUB` optimized).
- [x] Reconfirm section-level precompile gas for current checkpoint `73daa15` (MSM consolidation).
- [x] Update `docs/tokamak-verifier-gas-sections.md` so `Measured Gas` table includes per-section values across all optimization checkpoints.
- [x] Verify table totals and section sums match trace-derived subtotals.
- [x] Add a short review note in this file with validation commands and outcomes.

### 2026-02-14 Review Note
- Validation commands:
  - `NO_PROXY='*' no_proxy='*' forge test --match-contract testTokamakVerifier --match-test testVerifier -vvvv --offline` at `50030b0`
  - `NO_PROXY='*' no_proxy='*' forge test --match-contract testTokamakVerifier --match-test testVerifier -vvvv --offline` at `73daa15`
- Verified checkpoints:
  - `50030b0`: `verify = 980,360`, precompile subtotal = `750,108`
  - `73daa15`: `verify = 930,866`, precompile subtotal = `707,649`
- Section table in `docs/tokamak-verifier-gas-sections.md` updated with three aligned columns (baseline / `50030b0` / `73daa15`) and matching subtotals.

## Plan
- [x] Read `src/verifier/TokamakVerifier.sol` and define functional sections of `verify` pipeline.
- [x] Measure baseline gas of `test/verifier/Verifier.t.sol::testVerifier`.
- [x] Collect section-level gas data using trace/profiling and derive per-section gas estimates with clear assumptions.
- [x] Write markdown report with section descriptions and gas table.
- [x] Add review section with validation method and limitations.
- [x] Compare each Solidity section against Rust workspace members (`verify`, `verify-rust`).
- [x] Document functional differences section-by-section in report.

## Progress
- [x] Baseline verify gas captured (`1,201,029` in call trace).
- [x] Precompile sequence extracted and section-mapped.
- [x] Report written to `docs/tokamak-verifier-gas-sections.md`.
- [x] Rust comparison and functional-diff summary appended to report.

## Review
- Measurement method:
  - `NO_PROXY='*' no_proxy='*' forge test --match-contract testTokamakVerifier --match-test testVerifier -vvvv --offline`
  - trace parsing into `cache/verify_precompile_sequence.txt`
- Core results:
  - `verify` gas: `1,201,029`
  - precompile subtotal: `972,284`
  - residual non-precompile: `228,745`
- Rust comparison results:
  - `_loadVerificationKey`/input parsing path differs by architecture (hardcoded VK vs runtime JSON load)
  - `prepareLHSA` formula mismatch (`-kappa1*vy*[G]` term presence)
  - `prepareAggregatedCommitment` omega usage mismatch (`omega_mi^{-1}` vs `omega_smax^{-1}` on chi branch)
- Limitations:
  - Internal Yul local-function boundary별 정확 total gas는 trace만으로 직접 분리 불가.
  - 따라서 섹션별 정량은 precompile 중심의 정확값 + residual 설명으로 정리함.

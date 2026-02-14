# TokamakVerifier Gas Profiling Todo

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

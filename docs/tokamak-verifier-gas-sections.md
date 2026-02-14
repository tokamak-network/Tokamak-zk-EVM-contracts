# TokamakVerifier Gas Section Breakdown (Baseline)

## Scope
- Target: `src/verifier/TokamakVerifier.sol` (`verify` path)
- Baseline run: `test/verifier/Verifier.t.sol::testVerifier`
- Command:
  - `NO_PROXY='*' no_proxy='*' forge test --match-contract testTokamakVerifier --match-test testVerifier -vvvv --offline`

## Baseline
- `TokamakVerifier::verify(...)` gas: **1,201,029**
- Reference: full `testVerifier()` gas is `2,487,015` (includes test wrapper and ABI encoding overhead)

## Functional Sections
1. Verification key load
- `_loadVerificationKey()` (`src/verifier/TokamakVerifier.sol:484`)

2. Step 1: Proof loading and validation
- `loadProof()` (`src/verifier/TokamakVerifier.sol:775`)

3. Step 2: Transcript/challenge initialization
- `initializeTranscript()` (`src/verifier/TokamakVerifier.sol:1016`)

4. Step 3: Query/scalar preparation
- `prepareQueries()` (`src/verifier/TokamakVerifier.sol:1099`)
- `computeLagrangeK0Eval()` (`src/verifier/TokamakVerifier.sol:1123`)
- `computeAPUB()` (`src/verifier/TokamakVerifier.sol:1159`)

5. Step 4: Aggregated commitment construction
- `prepareLhsAuxSingleMSM()` (`src/verifier/TokamakVerifier.sol:1301`)
- `prepareRHS1()` (`src/verifier/TokamakVerifier.sol:1424`)
- `prepareRHS2()` (`src/verifier/TokamakVerifier.sol:1437`)

6. Step 5: Final pairing check
- `finalPairing()` (`src/verifier/TokamakVerifier.sol:1479`)

## Measured Gas (Trace-Exact, Precompile-Attributed)
- The values below are exact precompile gas totals aggregated from `-vvvv` traces in section execution order.
- Checkpoints:
  - Baseline: original implementation (`verify = 1,201,029`)
  - After `computeAPUB` optimization (`50030b0`, `verify = 980,360`)
  - After MSM call consolidation (`73daa15`, `verify = 930,866`)
  - After single-call `LHS+AUX` MSM refactor (`HEAD`, `verify = 821,775`)

| Section | Baseline | After `computeAPUB` Opt (`50030b0`) | After MSM Consolidation (`73daa15`) | After Single-MSM `LHS+AUX` (`HEAD`) |
|---|---:|---:|---:|---:|
| `prepareQueries` | 74,850 | 74,850 | 74,850 | 600 |
| `computeLagrangeK0Eval` | 1,554 | 1,554 | 1,554 | 1,554 |
| `computeAPUB` | 223,730 | 1,554 | 1,554 | 1,554 |
| `prepareLHSA` | 49,500 | 49,500 | 45,840 | 0 |
| `prepareLHSB` | 12,200 | 12,200 | 12,200 | 0 |
| `prepareLHSC` | 86,250 | 86,250 | 61,992 | 0 |
| `prepareLhsAuxSingleMSM` | 0 | 0 | 0 | 172,656 |
| `prepareRHS1` | 36,750 | 36,750 | 30,528 | 30,528 |
| `prepareRHS2` | 36,750 | 36,750 | 30,528 | 30,528 |
| `prepareAggregatedCommitment` | 87,000 | 87,000 | 84,903 | 0 |
| `finalPairing` | 363,700 | 363,700 | 363,700 | 363,700 |
| **Precompile subtotal** | **972,284** | **750,108** | **707,649** | **601,120** |

### Precompile Call Counts
- Baseline:
  - `0x0c` (BLS12-381 G1MSM): `31` calls, `372,000` gas
  - `0x0b` (BLS12-381 G1ADD): `28` calls, `10,500` gas
  - `0x05` (`modexp`): `288` calls, `226,084` gas
  - `0x0f` (pairing): `1` call, `363,700` gas
- After single-call `LHS+AUX` MSM refactor (`HEAD`):
  - `0x0c` (BLS12-381 G1MSM): `3` calls, `233,712` gas
  - `0x0b` (BLS12-381 G1ADD): `0` calls, `0` gas
  - `0x05` (`modexp`): `7` calls, `3,708` gas
  - `0x0f` (pairing): `1` call, `363,700` gas

## Residual (Non-Precompile)
- `verify` total `1,201,029` - precompile subtotal `972,284` = **228,745 gas**
- This residual includes:
  - `_loadVerificationKey`
  - `loadProof`
  - `initializeTranscript`
  - Arithmetic and memory manipulation overhead in each section (`mulmod`, `addmod`, `mstore`, `keccak256`, calldata decoding, etc.)

## Hotspots for Optimization (Priority)
1. `computeAPUB`
- Heavy concentration of `modexp` calls (the majority of the `288` total)
- Largest hotspot within Step 3

2. `finalPairing`
- Single call but very large absolute cost (`363,700` gas)

3. Step 4 (`prepareLHS*`, `prepareRHS*`, `prepareAggregatedCommitment`)
- Many G1MSM/G1ADD calls, cumulative `308,450` gas

## Verification Notes
- Repeated runs with the same input reproduce `verify = 1,201,029`.
- Since `testVerifier()` gas (`2,487,015`) includes wrapper/encoding overhead, optimization should be tracked against `verify` gas (`1,201,029`).

## Applied Optimization: `computeAPUB`
- Target function: `computeAPUB()` (`src/verifier/TokamakVerifier.sol:1159`)
- Measurement command:
  - `NO_PROXY='*' no_proxy='*' forge test --match-contract testTokamakVerifier --match-test testVerifier -vvvv --offline`

### What Was Optimized
1. Remove dead `modexp`
- Removed unused `inv_n := modexp(n, p-2)` in `computeAPUB`.

2. Reuse `omega^i` from first pass
- First pass now tracks `omega_power` iteratively and stores `(value, omega^i)` for non-zero inputs.
- This removes per-term `omega^i` recomputation in the second pass (both repeated `mulmod` for small `i` and `modexp` for large `i`).

3. Batch inversion for denominators
- Replaced per-term inversion `inv(denominator_full_i)` with one inversion of the total product and right-to-left recovery.
- Effectively reduces many expensive `modexp` inversions to one inversion plus `mulmod` reconstruction.

### Gas Impact (Measured)
| Variant | `verify` gas | Saved vs baseline |
|---|---:|---:|
| Baseline (no optimization) | 1,201,029 | - |
| + Step 1 (remove dead `modexp`) | 1,199,427 | 1,602 |
| + Step 2 (`omega^i` reuse) | 1,159,203 | 41,826 |
| + Step 3 (batch inversion) | **980,360** | **220,669** |

### Net Result
- `TokamakVerifier::verify(...)`: `1,201,029 -> 980,360`
- Total reduction: **220,669 gas** (**-18.37%**)

## Applied Optimization: MSM Call Consolidation (Step 4)
- Target functions:
  - `prepareLHSA()` (`src/verifier/TokamakVerifier.sol`)
  - `prepareLHSC()` (`src/verifier/TokamakVerifier.sol`)
  - `prepareRHS1()` (`src/verifier/TokamakVerifier.sol`)
  - `prepareRHS2()` (`src/verifier/TokamakVerifier.sol`)
  - `prepareAggregatedCommitment()` (`src/verifier/TokamakVerifier.sol`)

### What Was Optimized
1. Added packed MSM helpers
- Added `msmStoreTerm(...)` and `g1msmFromBuffer(...)` helpers to build and execute multi-term MSM calls.

2. Replaced repeated `1-point MSM + G1ADD/G1SUB` chains
- `prepareLHSA`: collapsed into one 5-term MSM.
- `prepareLHSC`: collapsed into one 7-term MSM (negative terms encoded with `R_MOD - coeff`).
- `prepareRHS1` / `prepareRHS2`: each collapsed into one 3-term MSM.
- `prepareAggregatedCommitment`:
  - LHS aggregation collapsed into one 3-term MSM.
  - AUX aggregation collapsed into one 6-term MSM.

3. Reduced precompile call overhead in Step 4
- Fewer `0x0c` calls and significantly fewer `0x0b` calls by avoiding intermediate point additions/subtractions.

### Gas Impact (Measured)
| Variant | `verify` gas | Saved vs previous |
|---|---:|---:|
| After `computeAPUB` optimization | 980,360 | - |
| + MSM call consolidation | **930,866** | **49,494** |

### Cumulative Net Result
- `TokamakVerifier::verify(...)`: `1,201,029 -> 930,866`
- Total reduction from original baseline: **270,163 gas** (**-22.49%**)

## Applied Optimization: Single-MSM `[LHS]+[AUX]` Refactor (Step 4)
- Target functions:
  - `prepareQueries()` (`src/verifier/TokamakVerifier.sol`)
  - `prepareLhsAuxSingleMSM()` (`src/verifier/TokamakVerifier.sol`)
  - `verify()` Step 4 call path (`src/verifier/TokamakVerifier.sol`)

### What Was Optimized
1. Replaced split LHS/AUX assembly path with one 22-term MSM
- Removed the runtime path that separately built `LHS_A`, `LHS_B`, `LHS_C`, `AUX`, then added `LHS + AUX`.
- Added `prepareLhsAuxSingleMSM()` to directly compute `[LHS]_1 + [AUX]_1` in a single `0x0c` call using the expanded coefficient table from `docs/verifier-spec.md`.

2. Removed now-unnecessary `[F]`/`[G]` point materialization in Step 3
- `prepareQueries()` now computes only scalar queries (`t_n(chi)`, `t_smax(zeta)`, `t_mI(chi)`).
- `[F]`/`[G]` contributions are folded into the one-shot MSM coefficients.

3. Updated Step 4 execution order
- `verify()` now runs:
  - `prepareLhsAuxSingleMSM()`
  - `prepareRHS1()`
  - `prepareRHS2()`
- This preserves pairing inputs while reducing precompile call count.

### Gas Impact (Measured)
| Variant | `verify` gas | Saved vs previous |
|---|---:|---:|
| After MSM consolidation (`73daa15`) | 930,866 | - |
| + Single-MSM `[LHS]+[AUX]` refactor (`HEAD`) | **821,775** | **109,091** |

### Cumulative Net Result
- `TokamakVerifier::verify(...)`: `1,201,029 -> 821,775`
- Total reduction from original baseline: **379,254 gas** (**-31.58%**)

## Rust Code Comparison (Section-by-Section)
- Reference workspace members:
  - `packages/backend/crates/verify-rust`
  - `packages/backend/crates/verify`
- Reference files:
  - `verify-rust/src/lib.rs`
  - `verify/src/verify/mod.rs`
- Note:
  - In `HEAD`, Solidity fuses prior Step 4 paths into `prepareLhsAuxSingleMSM()`.
  - Rows for `prepareLHSA` / `prepareLHSB` / `prepareLHSC` / `prepareAggregatedCommitment` are kept as conceptual-equation mapping references.

| Solidity section | Rust counterpart | Comparison |
|---|---|---|
| `_loadVerificationKey()` | `verify-rust/src/lib.rs` `VerifierContext::new` / `verify/src/verify/mod.rs` `Verifier::new` | **Implementation-path difference**. Solidity hardcodes VK constants and loads them into memory. Rust loads/parses VK JSON at runtime. The verification goal is the same, but the input path differs. |
| `loadProof()` | `verify-rust/src/lib.rs` `load_proof` / `verify/src/verify/mod.rs` `deserialize_proof` | **Functional difference exists**. Rust returns explicit parse/shape/length errors during deserialization. Solidity strongly validates only proof part lengths (38/42) and `smax`; `preprocessed`/`publicInputs` lengths are not explicitly validated (missing entries become zero via `calldataload`). |
| `initializeTranscript()` | `verify-rust/src/lib.rs` `compute_challenges` / transcript update path in `verify/src/verify/mod.rs` | **Mostly equivalent**. Commit order (U,V,W,QAX,QAY,B -> R -> QCX,QCY -> Vxy,R1,R2,R3) and challenge flow match. |
| `prepareQueries()` | `verify-rust/src/lib.rs` `prepare_query` / `verify/src/verify/mod.rs` `prepare_query` | **Implementation-path difference**. In `HEAD`, Solidity computes only scalar queries (`t_n`, `t_smax`, `t_mi`) here and folds `[F]`/`[G]` effects into `prepareLhsAuxSingleMSM()`. The full equation target remains equivalent. |
| `computeLagrangeK0Eval()` | `verify-rust/src/lib.rs` `compute_lagrange_k0_eval` / same in `verify/src/verify/mod.rs` | **Equivalent**. Uses `L_0(chi)=(chi^m_i-1)/(m_i*(chi-1))`. |
| `computeAPUB()` | `verify-rust/src/lib.rs` `compute_A_pub` / `verify/src/verify/mod.rs` `compute_a_pub` | **Functionally equivalent, optimization strategy differs**. Rust uses straightforward full iteration; Solidity uses a sparse two-pass strategy over non-zero public inputs plus a small-index fast path. |
| `prepareLhsAuxSingleMSM()` | `verify-rust/src/lib.rs` `prepare_lhs_a`/`prepare_lhs_b`/`prepare_lhs_c`/`prepare_aggregated_commitment` (and corresponding functions in `verify/src/verify/mod.rs`) | **Equivalent target, different construction strategy**. Solidity fuses the expanded `[LHS]+[AUX]` linear combination into one 22-term MSM, while Rust keeps multi-step composition. |
| `prepareLHSA()` | `verify-rust/src/lib.rs` `prepare_lhs_a` / `verify/src/verify/mod.rs` `prepare_lhs_a` | **Section-level grouping difference**. Rust keeps `-kappa1*vy*[G]` directly inside `LHS_A`: `u*vy - w + (v - g*vy)*kappa1 - q_ax*t_n - q_ay*t_smax`. Solidity computes `prepareLHSA` as `u*vy - w + kappa1*v - q_ax*t_n - q_ay*t_smax`, and moves `-kappa1*vy*[1]` to `prepareLHSC` scalar `d` (as `d[1]`). |
| `prepareLHSB()` | `verify-rust/src/lib.rs` `prepare_lhs_b` / `verify/src/verify/mod.rs` `prepare_lhs_b` | **Equivalent**. `(1 + kappa2*kappa1^4)*[A]`. |
| `prepareLHSC()` | `verify-rust/src/lib.rs` `prepare_lhs_c` / `verify/src/verify/mod.rs` `prepare_lhs_c` | **Mostly equivalent**. Scalar composition and combination flow for `a,b,c,d` align. |
| `prepareRHS1()` / `prepareRHS2()` | `verify-rust/src/lib.rs` `prepare_rhs_1`, `prepare_rhs_2` / same in `verify/src/verify/mod.rs` | **Equivalent**. Uses `kappa2`, `kappa2^2`, `kappa2^3` for chi/zeta commitment aggregation. |
| `prepareAggregatedCommitment()` | `verify-rust/src/lib.rs` `prepare_aggregated_commitment` / same in `verify/src/verify/mod.rs` | **Key functional difference exists**. Solidity uses `omega_mi^{-1}` (`OMEGA_MI_1`) for chi-branch terms (`M_chi`, `N_chi`). Both Rust implementations use `omega_smax_inv` for the chi branch as well. |
| `finalPairing()` | `verify-rust/src/lib.rs` `check_pairing` / `verify/src/verify/mod.rs` `check_pairing` | **Same mathematical target**. Rust validates with library pairing APIs; Solidity manually encodes and calls precompile `0x0f`. |

## Functional Differences Summary
1. Input-validation strictness
- Rust applies stronger on-curve/deserialization/length validation (`validate_inputs` path).
- Solidity primarily validates proof-part lengths and `smax`; other issues often surface later as pairing failure.

2. `LHS_A` formula composition (implementation grouping)
- Rust includes `-kappa1 * vy * [G]` inside `LHS_A`.
- Solidity moves this term out of `prepareLHSA()` and applies it in `prepareLHSC()` through `d[1]` (`d` includes `-kappa1 * vy`).
- Therefore, this is a section-level rearrangement, not necessarily a whole-equation mismatch.

## Clarification: `-kappa1*vy*[1]` Term Placement
- Solidity comments under `prepareLHSA()` previously suggested the term was still inside `LHS_A`, but the executed operations in that function do not apply `-kappa1*vy*[1]`.
- The term is applied in `prepareLHSC()` when adding `d[1]`, where `d := -(kappa1^3*r1 + kappa2*r2 + kappa2^2*r3 + kappa1*vy + kappa1^4*A_pub)`.
- This matches a deliberate algebraic regrouping strategy: keep `prepareLHSA()` as a compact point combination and collect `[1]`-coefficient terms in `d`.

3. Omega selection in aggregated commitment
- Rust (`verify-rust`/`verify`) uses `omega_smax_inv` for chi-branch terms.
- Solidity uses `omega_mi^{-1}` for chi terms and `omega_smax^{-1}` for part of zeta terms.

4. `A_pub` computation strategy
- Mathematical target is the same.
- Solidity adds sparse/non-zero optimization paths not present in the straightforward Rust iteration.

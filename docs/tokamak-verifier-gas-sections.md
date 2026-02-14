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
- `_loadVerificationKey()` (`src/verifier/TokamakVerifier.sol:418`)

2. Step 1: Proof loading and validation
- `loadProof()` (`src/verifier/TokamakVerifier.sol:562`)

3. Step 2: Transcript/challenge initialization
- `initializeTranscript()` (`src/verifier/TokamakVerifier.sol:803`)

4. Step 3: Query/scalar preparation
- `prepareQueries()` (`src/verifier/TokamakVerifier.sol:886`)
- `computeLagrangeK0Eval()` (`src/verifier/TokamakVerifier.sol:910`)
- `computeAPUB()` (`src/verifier/TokamakVerifier.sol:946`)

5. Step 4: Aggregated commitment construction
- `prepareLhsAuxSingleMSM()` (`src/verifier/TokamakVerifier.sol:1088`)
- `prepareRHS1()` (`src/verifier/TokamakVerifier.sol:1211`)
- `prepareRHS2()` (`src/verifier/TokamakVerifier.sol:1224`)

6. Step 5: Final pairing check
- `finalPairing()` (`src/verifier/TokamakVerifier.sol:1266`)

## Measured Gas (Section Total, `HEAD`)
- The table below is section-total gas (not only precompile gas).
- `_loadVerificationKey`, `loadProof`, and `initializeTranscript` are now explicitly measured.
- Measurement method:
  - Temporary checkpoint instrumentation (`gas()` delta at each section boundary) in `verify`.
  - Profiling call from `0x0000000000000000000000000000000000001234`.
  - Command:
    - `NO_PROXY='*' no_proxy='*' forge test --match-contract testTokamakVerifier --match-test testProfileSectionGas -vv --offline`

| Section | `HEAD` total gas |
|---|---:|
| `_loadVerificationKey` | 6,623 |
| `loadProof` | 1,880 |
| `initializeTranscript` | 8,468 |
| `prepareQueries` | 1,411 |
| `computeLagrangeK0Eval` | 2,291 |
| `computeAPUB` | 155,436 |
| `prepareLhsAuxSingleMSM` | 177,474 |
| `prepareRHS1` | 30,959 |
| `prepareRHS2` | 30,959 |
| `finalPairing` | 365,095 |
| **Section subtotal** | **780,596** |
| **`verify` total** | **785,531** |
| **Unattributed glue overhead** | **4,935** |

## Historical Checkpoints (Precompile-Only View)
- The table below is kept for historical comparison across optimization commits.
- These values are exact precompile gas totals aggregated from `-vvvv` traces.

| Section | Baseline | After `computeAPUB` Opt (`50030b0`) | After MSM Consolidation (`73daa15`) | After Single-MSM `LHS+AUX` (`6f5394b`) |
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
- After single-call `LHS+AUX` MSM refactor (`6f5394b`):
  - `0x0c` (BLS12-381 G1MSM): `3` calls, `233,712` gas
  - `0x0b` (BLS12-381 G1ADD): `0` calls, `0` gas
  - `0x05` (`modexp`): `7` calls, `3,708` gas
  - `0x0f` (pairing): `1` call, `363,700` gas

## Residual / Overhead Notes
- In the historical precompile-only view:
  - Baseline residual: `1,201,029 - 972,284 = 228,745`
  - `HEAD` residual: `785,531 - 601,120 = 184,411`
- In the section-total `HEAD` view:
  - Unattributed glue overhead: `785,531 - 780,596 = 4,935`
  - This includes boundary code not assigned to one section (step transitions and final return glue).

## Hotspots for Optimization (Priority)
1. `finalPairing`
- Single call but very large absolute cost (`363,700` gas)

2. `computeAPUB`
- Dominant non-pairing section in total gas (`155,436` gas) due heavy finite-field arithmetic loops.

3. `prepareLhsAuxSingleMSM`
- Single 22-term MSM call plus setup (`177,474` gas total).

## Verification Notes
- Repeated runs with the same input reproduce `verify = 785,531` on `HEAD`.
- `testVerifier()` wrapper gas is currently `2,071,517`; optimization tracking should use internal `verify` gas (`785,531`).
- Historical checkpoints are kept for trend comparison (`1,201,029 -> 980,360 -> 930,866 -> 821,775 -> 785,531`).

## Applied Optimization: `computeAPUB` Loop Fusion / Arithmetic Hoist
- Target function: `computeAPUB()` (`src/verifier/TokamakVerifier.sol:946`)
- Measurement command:
  - `NO_PROXY='*' no_proxy='*' forge test --match-contract testTokamakVerifier --match-test testVerifier -vvvv --offline`

### What Was Optimized
1. Merged non-zero passes
- Combined denominator construction and prefix-product building into the first non-zero scan.
- Removed separate denominator/prefix loops.

2. Reduced temporary memory footprint
- Stored `numeratorBase = a_j * omega^j` directly (32-byte slot), instead of storing both `(value, omega^j)` pairs (64-byte slots).

3. Hoisted shared factor
- Applied `(chi^n - 1)` once at the end to the accumulated raw sum, instead of multiplying this factor per contribution.

### Gas Impact (Measured)
| Variant | `verify` gas | Saved vs previous |
|---|---:|---:|
| After single-MSM `[LHS]+[AUX]` refactor (`6f5394b`) | 821,775 | - |
| + `computeAPUB` loop/memory tightening (`HEAD`) | **785,531** | **36,244** |

### Cumulative Net Result
- `TokamakVerifier::verify(...)`: `1,201,029 -> 785,531`
- Total reduction from original baseline: **415,498 gas** (**-34.60%**)

## Applied Optimization: `computeAPUB`
- Target function: `computeAPUB()` (`src/verifier/TokamakVerifier.sol:946`)
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
| + Single-MSM `[LHS]+[AUX]` refactor (`6f5394b`) | **821,775** | **109,091** |

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

| Solidity section | Rust counterpart | Comparison |
|---|---|---|
| `_loadVerificationKey()` | `verify-rust/src/lib.rs` `VerifierContext::new` / `verify/src/verify/mod.rs` `Verifier::new` | **Implementation-path difference**. Solidity hardcodes VK constants and loads them into memory. Rust loads/parses VK JSON at runtime. The verification goal is the same, but the input path differs. |
| `loadProof()` | `verify-rust/src/lib.rs` `load_proof` / `verify/src/verify/mod.rs` `deserialize_proof` | **Functional difference exists**. Rust returns explicit parse/shape/length errors during deserialization. Solidity strongly validates only proof part lengths (38/42) and `smax`; `preprocessed`/`publicInputs` lengths are not explicitly validated (missing entries become zero via `calldataload`). |
| `initializeTranscript()` | `verify-rust/src/lib.rs` `compute_challenges` / transcript update path in `verify/src/verify/mod.rs` | **Mostly equivalent**. Commit order (U,V,W,QAX,QAY,B -> R -> QCX,QCY -> Vxy,R1,R2,R3) and challenge flow match. |
| `prepareQueries()` | `verify-rust/src/lib.rs` `prepare_query` / `verify/src/verify/mod.rs` `prepare_query` | **Implementation-path difference**. In `HEAD`, Solidity computes only scalar queries (`t_n`, `t_smax`, `t_mi`) here and folds `[F]`/`[G]` effects into `prepareLhsAuxSingleMSM()`. Equation target remains equivalent. |
| `computeLagrangeK0Eval()` | `verify-rust/src/lib.rs` `compute_lagrange_k0_eval` / same in `verify/src/verify/mod.rs` | **Equivalent**. Uses `L_0(chi)=(chi^m_i-1)/(m_i*(chi-1))`. |
| `computeAPUB()` | `verify-rust/src/lib.rs` `compute_A_pub` / `verify/src/verify/mod.rs` `compute_a_pub` | **Functionally equivalent, optimization strategy differs**. Rust uses straightforward full iteration; Solidity uses a sparse two-pass strategy over non-zero public inputs plus a small-index fast path. |
| `prepareLhsAuxSingleMSM()` | `verify-rust/src/lib.rs` `prepare_lhs_a` + `prepare_lhs_b` + `prepare_lhs_c` + `prepare_aggregated_commitment` (and same path in `verify/src/verify/mod.rs`) | **Equivalent target, different construction strategy**. Solidity fuses expanded `[LHS]+[AUX]` into one 22-term MSM; Rust keeps multi-step composition and then aggregates. |
| `prepareRHS1()` / `prepareRHS2()` | `verify-rust/src/lib.rs` `prepare_rhs_1`, `prepare_rhs_2` / same in `verify/src/verify/mod.rs` | **Equivalent**. Uses `kappa2`, `kappa2^2`, `kappa2^3` for chi/zeta commitment aggregation. |
| `finalPairing()` | `verify-rust/src/lib.rs` `check_pairing` / `verify/src/verify/mod.rs` `check_pairing` | **Same mathematical target**. Rust validates with library pairing APIs; Solidity manually encodes and calls precompile `0x0f`. |

## Functional Differences Summary
1. Input-validation strictness
- Rust applies stronger on-curve/deserialization/length validation (`validate_inputs` path).
- Solidity primarily validates proof-part lengths and `smax`; other issues often surface later as pairing failure.

2. Step 4 construction strategy
- Rust composes `LHS_A`, `LHS_B`, `LHS_C`, and `AUX` in separate stages.
- Solidity `HEAD` computes the same final `[LHS]+[AUX]` linear combination directly as one 22-term MSM.

3. Omega selection in aggregated commitment terms
- Rust (`verify-rust`/`verify`) uses `omega_smax_inv` for chi-branch terms.
- Solidity uses `omega_mi^{-1}` for chi terms and `omega_smax^{-1}` for part of zeta terms.

4. `A_pub` computation strategy
- Mathematical target is the same.
- Solidity adds sparse/non-zero optimization paths not present in the straightforward Rust iteration.

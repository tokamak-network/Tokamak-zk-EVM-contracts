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
- `loadProof()` (`src/verifier/TokamakVerifier.sol:758`)

3. Step 2: Transcript/challenge initialization
- `initializeTranscript()` (`src/verifier/TokamakVerifier.sol:999`)

4. Step 3: Query/scalar preparation
- `prepareQueries()` (`src/verifier/TokamakVerifier.sol:1088`)
- `computeLagrangeK0Eval()` (`src/verifier/TokamakVerifier.sol:1142`)
- `computeAPUB()` (`src/verifier/TokamakVerifier.sol:1178`)

5. Step 4: Aggregated commitment construction
- `prepareLHSA()` (`src/verifier/TokamakVerifier.sol:1297`)
- `prepareLHSB()` (`src/verifier/TokamakVerifier.sol:1330`)
- `prepareLHSC()` (`src/verifier/TokamakVerifier.sol:1344`)
- `prepareRHS1()` (`src/verifier/TokamakVerifier.sol:1419`)
- `prepareRHS2()` (`src/verifier/TokamakVerifier.sol:1430`)
- `prepareAggregatedCommitment()` (`src/verifier/TokamakVerifier.sol:1458`)

6. Step 5: Final pairing check
- `finalPairing()` (`src/verifier/TokamakVerifier.sol:1540`)

## Measured Gas (Trace-Exact, Precompile-Attributed)
- The values below are exact precompile gas totals aggregated from the `-vvvv` trace in section execution order.

| Section | Gas |
|---|---:|
| `prepareQueries` | 74,850 |
| `computeLagrangeK0Eval` | 1,554 |
| `computeAPUB` | 223,730 |
| `prepareLHSA` | 49,500 |
| `prepareLHSB` | 12,200 |
| `prepareLHSC` | 86,250 |
| `prepareRHS1` | 36,750 |
| `prepareRHS2` | 36,750 |
| `prepareAggregatedCommitment` | 87,000 |
| `finalPairing` | 363,700 |
| **Precompile subtotal** | **972,284** |

### Precompile Call Counts
- `0x0c` (BLS12-381 G1MSM): `31` calls, `372,000` gas
- `0x0b` (BLS12-381 G1ADD): `28` calls, `10,500` gas
- `0x05` (`modexp`): `288` calls, `226,084` gas
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
| `prepareQueries()` | `verify-rust/src/lib.rs` `prepare_query` / `verify/src/verify/mod.rs` `prepare_query` | **Mostly equivalent**. Structure of `[F]`, `[G]`, `t_n(chi)`, `t_smax(zeta)`, `t_mi(chi)` is consistent. |
| `computeLagrangeK0Eval()` | `verify-rust/src/lib.rs` `compute_lagrange_k0_eval` / same in `verify/src/verify/mod.rs` | **Equivalent**. Uses `L_0(chi)=(chi^m_i-1)/(m_i*(chi-1))`. |
| `computeAPUB()` | `verify-rust/src/lib.rs` `compute_A_pub` / `verify/src/verify/mod.rs` `compute_a_pub` | **Functionally equivalent, optimization strategy differs**. Rust uses straightforward full iteration; Solidity uses a sparse two-pass strategy over non-zero public inputs plus a small-index fast path. |
| `prepareLHSA()` | `verify-rust/src/lib.rs` `prepare_lhs_a` / `verify/src/verify/mod.rs` `prepare_lhs_a` | **Key functional difference exists**. Rust includes `-kappa1*vy*[G]` as part of `u*vy - w + (v - g*vy)*kappa1 - q_ax*t_n - q_ay*t_smax`. Solidity currently computes through `+kappa1*[V]` in this section and does not visibly include the `-[G]` term here. |
| `prepareLHSB()` | `verify-rust/src/lib.rs` `prepare_lhs_b` / `verify/src/verify/mod.rs` `prepare_lhs_b` | **Equivalent**. `(1 + kappa2*kappa1^4)*[A]`. |
| `prepareLHSC()` | `verify-rust/src/lib.rs` `prepare_lhs_c` / `verify/src/verify/mod.rs` `prepare_lhs_c` | **Mostly equivalent**. Scalar composition and combination flow for `a,b,c,d` align. |
| `prepareRHS1()` / `prepareRHS2()` | `verify-rust/src/lib.rs` `prepare_rhs_1`, `prepare_rhs_2` / same in `verify/src/verify/mod.rs` | **Equivalent**. Uses `kappa2`, `kappa2^2`, `kappa2^3` for chi/zeta commitment aggregation. |
| `prepareAggregatedCommitment()` | `verify-rust/src/lib.rs` `prepare_aggregated_commitment` / same in `verify/src/verify/mod.rs` | **Key functional difference exists**. Solidity uses `omega_mi^{-1}` (`OMEGA_MI_1`) for chi-branch terms (`M_chi`, `N_chi`). Both Rust implementations use `omega_smax_inv` for the chi branch as well. |
| `finalPairing()` | `verify-rust/src/lib.rs` `check_pairing` / `verify/src/verify/mod.rs` `check_pairing` | **Same mathematical target**. Rust validates with library pairing APIs; Solidity manually encodes and calls precompile `0x0f`. |

## Functional Differences Summary
1. Input-validation strictness
- Rust applies stronger on-curve/deserialization/length validation (`validate_inputs` path).
- Solidity primarily validates proof-part lengths and `smax`; other issues often surface later as pairing failure.

2. `LHS_A` formula composition
- Rust includes `-kappa1 * vy * [G]`.
- Solidity does not visibly include this term inside `prepareLHSA()`.

3. Omega selection in aggregated commitment
- Rust (`verify-rust`/`verify`) uses `omega_smax_inv` for chi-branch terms.
- Solidity uses `omega_mi^{-1}` for chi terms and `omega_smax^{-1}` for part of zeta terms.

4. `A_pub` computation strategy
- Mathematical target is the same.
- Solidity adds sparse/non-zero optimization paths not present in the straightforward Rust iteration.

# TokamakVerifier Gas Section Breakdown (Baseline)

## Scope
- Target: `src/verifier/TokamakVerifier.sol` (`verify` path)
- Baseline run: `test/verifier/Verifier.t.sol::testVerifier`
- Command:
  - `NO_PROXY='*' no_proxy='*' forge test --match-contract testTokamakVerifier --match-test testVerifier -vvvv --offline`

## Baseline
- `TokamakVerifier::verify(...)` gas: **1,201,029**
- (참고) `testVerifier()` 전체 가스: `2,487,015` (테스트 래퍼/ABI 인코딩 포함)

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

## Measured Gas (Trace-exact, Precompile-attributed)
- 아래 수치는 `-vvvv` trace에서 precompile call gas를 섹션 순서로 집계한 **정확값**이다.

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

## Residual (Non-precompile)
- `verify` total `1,201,029` - precompile subtotal `972,284` = **228,745 gas**
- 이 잔여 가스에는 다음이 섞여 있다.
  - `_loadVerificationKey`
  - `loadProof`
  - `initializeTranscript`
  - 각 섹션의 산술/메모리 조작 오버헤드 (`mulmod`, `addmod`, `mstore`, `keccak256`, calldata decode 등)

## Hotspots For Optimization (Priority)
1. `computeAPUB`
- `modexp` 호출이 집중됨 (`288` 중 대부분).
- Step 3 내부 최대 병목.

2. `finalPairing`
- 단일 호출이지만 `363,700` gas로 절대량이 큼.

3. Step 4 (`prepareLHS*`, `prepareRHS*`, `prepareAggregatedCommitment`)
- G1MSM/G1ADD 다수 호출로 누적 `308,450` gas.

## Verification Notes
- 동일 입력으로 재측정 시 `verify`는 `1,201,029`로 재현됨.
- 테스트 함수 가스(`2,487,015`)는 래퍼/ABI 인코딩 비용이 포함되므로, 최적화 대상은 `verify` 가스(`1,201,029`)를 기준으로 본다.

## Rust Code Comparison (Section-by-Section)
- Reference workspace members:
  - `packages/backend/crates/verify-rust`
  - `packages/backend/crates/verify`
- Reference files:
  - `verify-rust/src/lib.rs`
  - `verify/src/verify/mod.rs`

| Solidity section | Rust 대응 코드 | 비교 결과 |
|---|---|---|
| `_loadVerificationKey()` | `verify-rust/src/lib.rs`의 `VerifierContext::new` / `verify/src/verify/mod.rs`의 `Verifier::new` | **구현 방식 차이**. Solidity는 VK 상수를 컨트랙트 코드에 하드코딩해 메모리에 로드. Rust는 JSON VK를 런타임 로드/파싱. 기능 목표(동일 VK 사용)는 같지만 입력 경로가 다름. |
| `loadProof()` | `verify-rust/src/lib.rs`의 `load_proof` / `verify/src/verify/mod.rs`의 `deserialize_proof` | **기능 차이 존재**. Rust는 역직렬화 단계에서 구조/길이/필드 파싱 에러를 명시적으로 리턴. Solidity는 proof part1/part2 길이(38/42)와 `smax`만 강검증하고, preprocessed/publicInputs 길이는 명시 검증하지 않음(부족분은 `calldataload` 0으로 읽힘). |
| `initializeTranscript()` | `verify-rust/src/lib.rs`의 `compute_challenges` / `verify/src/verify/mod.rs`의 transcript 업데이트 구간 | **대체로 동일**. 커밋 순서(U,V,W,QAX,QAY,B -> R -> QCX,QCY -> Vxy,R1,R2,R3)와 challenge 생성 흐름이 동일. |
| `prepareQueries()` | `verify-rust/src/lib.rs`의 `prepare_query` / `verify/src/verify/mod.rs`의 `prepare_query` | **대체로 동일**. `[F]`, `[G]`, `t_n(chi)`, `t_smax(zeta)`, `t_mi(chi)` 계산 구조 동일. |
| `computeLagrangeK0Eval()` | `verify-rust/src/lib.rs`의 `compute_lagrange_k0_eval` / `verify/src/verify/mod.rs`의 동명 함수 | **동일**. `L_0(chi)=(chi^m_i-1)/(m_i*(chi-1))` 형태로 계산. |
| `computeAPUB()` | `verify-rust/src/lib.rs`의 `compute_A_pub` / `verify/src/verify/mod.rs`의 `compute_a_pub` | **기능은 동일, 구현 최적화 방식 차이**. Rust는 일반식 합산(전 입력 순회), Solidity는 non-zero public input만 모아 2-pass 처리 + small-index fast path를 사용. |
| `prepareLHSA()` | `verify-rust/src/lib.rs`의 `prepare_lhs_a` / `verify/src/verify/mod.rs`의 `prepare_lhs_a` | **핵심 기능 차이 존재**. Rust는 `u*vy - w + (v - g*vy)*kappa1 - q_ax*t_n - q_ay*t_smax`로 `-kappa1*vy*[G]` 항을 포함. Solidity는 현재 `+kappa1*[V]`까지만 계산하고 해당 `-[G]` 항이 이 섹션에 없음. |
| `prepareLHSB()` | `verify-rust/src/lib.rs`의 `prepare_lhs_b` / `verify/src/verify/mod.rs`의 `prepare_lhs_b` | **동일**. `(1 + kappa2*kappa1^4)*[A]`. |
| `prepareLHSC()` | `verify-rust/src/lib.rs`의 `prepare_lhs_c` / `verify/src/verify/mod.rs`의 `prepare_lhs_c` | **대체로 동일**. `a,b,c,d` 스칼라 구성과 조합 구조 동일. |
| `prepareRHS1()` / `prepareRHS2()` | `verify-rust/src/lib.rs`의 `prepare_rhs_1`, `prepare_rhs_2` / `verify/src/verify/mod.rs` 동명 함수 | **동일**. `kappa2`, `kappa2^2`, `kappa2^3` 계수로 chi/zeta 쪽 commitment 집계. |
| `prepareAggregatedCommitment()` | `verify-rust/src/lib.rs`의 `prepare_aggregated_commitment` / `verify/src/verify/mod.rs`의 동명 함수 | **핵심 기능 차이 존재**. Solidity는 chi 계열(`M_chi`, `N_chi`)에 `omega_mi^{-1}`(`OMEGA_MI_1`) 사용. Rust 두 구현은 chi 계열에도 `omega_smax_inv`를 사용. |
| `finalPairing()` | `verify-rust/src/lib.rs`의 `check_pairing` / `verify/src/verify/mod.rs`의 `check_pairing` | **동일한 수학식 목표**. Rust는 라이브러리 pairing API로 검증, Solidity는 precompile `0x0f`에 직접 인코딩해 호출. |

## Functional Differences Summary
1. 입력 검증 강도
- Rust: 포인트 on-curve/직렬화/길이 검증이 더 강함 (`validate_inputs` 포함).
- Solidity: proof part 길이/smax 검증 위주, 나머지는 pairing 실패로 늦게 드러남.

2. `LHS_A` 식 구성
- Rust: `-kappa1 * vy * [G]` 포함.
- Solidity: 해당 항이 `prepareLHSA()`에 직접 보이지 않음.

3. Aggregated commitment의 omega 선택
- Rust(verify-rust/verify): chi 계열에도 `omega_smax_inv` 사용.
- Solidity: chi 계열에 `omega_mi^{-1}` 사용, zeta의 일부에 `omega_smax^{-1}` 사용.

4. `A_pub` 계산 전략
- 수학적으로 같은 목표지만, Solidity는 non-zero sparse 최적화 경로를 적용.

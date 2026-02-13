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

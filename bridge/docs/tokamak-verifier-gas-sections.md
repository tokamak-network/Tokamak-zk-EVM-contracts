# TokamakVerifier Gas Section Breakdown

## Scope
- Target: `tokamak-zkp/TokamakVerifier.sol` (`verify` path)
- Primary test: `test/verifier/Verifier.t.sol::testVerifier`
- Trace command (current snapshot):
  - `NO_PROXY='*' no_proxy='*' forge test --match-contract testTokamakVerifier --match-test testVerifier -vvvvv --offline`

## Current Snapshot (`ae99e6b`)
- `TokamakVerifier::verify(...)` gas: **655,104**
- `testVerifier()` gas (wrapper): **1,629,187**
- Console delta (`gasBefore - gasAfter`): **1,625,655**

## Functional Sections
1. Verification key load
- `_loadVerificationKey()` (`tokamak-zkp/TokamakVerifier.sol:429`)

2. Step 1: Proof loading and validation
- `loadProof()` (`tokamak-zkp/TokamakVerifier.sol:593`)

3. Step 2: Transcript/challenge initialization
- `initializeTranscript()` (`tokamak-zkp/TokamakVerifier.sol:848`)

4. Step 3: Query/scalar preparation
- `prepareQueries()` (`tokamak-zkp/TokamakVerifier.sol:931`)
- `computeLagrangeK0Eval()` (`tokamak-zkp/TokamakVerifier.sol:955`)
- `computeAPUB()` (`tokamak-zkp/TokamakVerifier.sol:991`)

5. Step 4: Aggregated commitment construction
- `prepareLhsAuxSingleMSM()` (`tokamak-zkp/TokamakVerifier.sol:1121`)
- `prepareRHS1()` (`tokamak-zkp/TokamakVerifier.sol:1248`)
- `prepareRHS2()` (`tokamak-zkp/TokamakVerifier.sol:1261`)

6. Step 5: Final pairing check
- `finalPairing()` (`tokamak-zkp/TokamakVerifier.sol:1303`)

## Measured Gas

### A. Exact totals (`HEAD`, trace-derived)
| Metric | Gas |
|---|---:|
| `verify` total | **655,104** |
| Precompile subtotal | **601,495** |
| Residual (non-precompile) | **53,609** |

### B. Precompile call counts (`HEAD`)
| Precompile | Calls | Gas |
|---|---:|---:|
| `modexp` (`0x05`) | 7 | 3,708 |
| G1ADD (`0x0b`) | 1 | 375 |
| G1MSM (`0x0c`) | 3 | 233,712 |
| Pairing (`0x0f`) | 1 | 363,700 |
| **Total** | **12** | **601,495** |

### C. Precompile gas by verifier section (`HEAD`)
| Section | Precompile gas |
|---|---:|
| `prepareQueries` | 600 |
| `computeLagrangeK0Eval` | 1,554 |
| `computeAPUB` | 1,554 |
| `prepareLhsAuxSingleMSM` | 172,656 |
| `prepareRHS1` | 30,528 |
| `prepareRHS2` | 30,528 |
| `finalPairing` (`pairing` + one G1ADD) | 364,075 |
| **Precompile subtotal** | **601,495** |

### D. Last instrumented section-total snapshot (`f483cc4`)
- Full per-section totals (`_loadVerificationKey`, `loadProof`, `initializeTranscript`, etc.) were last measured at `f483cc4` using temporary section-boundary gas instrumentation.
- That instrumented `verify` total was **785,531**.

## Snapshot History (`verify` gas)
| Snapshot commit | `verify` gas | Delta vs previous |
|---|---:|---:|
| `0dc0989` | 1,201,029 | - |
| `50030b0` | 980,360 | -220,669 |
| `73daa15` | 930,866 | -49,494 |
| `f483cc4` | 785,531 | -145,335 |
| `ae99e6b` | **655,104** | **-130,427** |

## Net Reduction
- Baseline to current: `1,201,029 -> 655,104`
- Absolute reduction: **545,925 gas**
- Relative reduction: **-45.46%**

## Notes
- Current VK loading is generated from `tokamak-zkp/TokamakVerifierKey/sigma_verify.json` at build time, then loaded in `_loadVerificationKey()`.
- The latest trace includes one explicit G1ADD (`0x0b`) before final pairing; previous snapshots had zero G1ADD in this path.
- Reporting series should use the snapshot values in this document's Measured Gas / Snapshot History sections.

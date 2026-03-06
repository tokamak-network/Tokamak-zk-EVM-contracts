# Bridge Groth16 Circuit Pseudocode (Mar 2026)

## Scope and Source Alignment

This document defines the pseudocode for the Groth16 circuit shape currently used by the bridge verification flow.

- Bridge verifier path:
  - `src/BridgeProofManager.sol`
  - `src/verifier/Groth16Verifier16Leaves.sol`
  - `src/verifier/Groth16Verifier32Leaves.sol`
  - `src/verifier/Groth16Verifier64Leaves.sol`
  - `src/verifier/Groth16Verifier128Leaves.sol`
- Required public signal lengths in bridge runtime:
  - 16 leaves: `33`
  - 32 leaves: `65`
  - 64 leaves: `129`
  - 128 leaves: `257`

Note:
- `groth16/circuits/src/circuit_N4.circom` to `circuit_N8.circom` include `fixed_prefix` and `contract_address` as public inputs.
- Those files imply larger public signal lengths (`35/67/131/259` for N=4/5/6/7).
- This pseudocode intentionally follows the bridge-active verifier shape (`root + keys + values`) because that is what bridge contracts enforce today.

## Pseudocode Format

The format below is intentionally strict:
- Uppercase section keywords.
- Deterministic indexing.
- Explicit public signal order.
- Minimal free-text inside the code block.

```text
CIRCUIT BridgeStorageMerkleBinary

PARAMETERS
  N: int                      # tree depth
  TREE_SIZE = 2^N

PUBLIC_INPUTS
  storage_keys_l2mpt[TREE_SIZE]   # uint256 field elements
  storage_values[TREE_SIZE]       # uint256 field elements

PUBLIC_OUTPUTS
  merkle_root

INTERNAL_SIGNALS
  leaf_hash[TREE_SIZE]
  level_nodes[N][TREE_SIZE / 2]   # jagged usage; only prefix is used per level

CONSTRAINTS
  FOR i IN [0, TREE_SIZE):
    leaf_hash[i] = Poseidon2(storage_keys_l2mpt[i], storage_values[i])

  current_nodes = leaf_hash
  current_size = TREE_SIZE

  FOR level IN [0, N):
    next_size = current_size / 2

    FOR j IN [0, next_size):
      level_nodes[level][j] = Poseidon2(current_nodes[2*j], current_nodes[2*j + 1])

    current_nodes = level_nodes[level]
    current_size = next_size

  merkle_root = current_nodes[0]

PUBLIC_SIGNAL_ORDER
  pub[0] = merkle_root
  FOR i IN [0, TREE_SIZE):
    pub[1 + i] = storage_keys_l2mpt[i]
  FOR i IN [0, TREE_SIZE):
    pub[1 + TREE_SIZE + i] = storage_values[i]

PUBLIC_SIGNAL_LENGTH
  len(pub) = 1 + 2 * TREE_SIZE
```

## Parameter Table Used by Bridge

| Tree leaves | N | Public signals |
|---|---:|---:|
| 16 | 4 | 33 |
| 32 | 5 | 65 |
| 64 | 6 | 129 |
| 128 | 7 | 257 |

## Human Editing Guidelines

1. Keep section names unchanged: `PARAMETERS`, `PUBLIC_INPUTS`, `PUBLIC_OUTPUTS`, `INTERNAL_SIGNALS`, `CONSTRAINTS`, `PUBLIC_SIGNAL_ORDER`, `PUBLIC_SIGNAL_LENGTH`.
2. Keep all indices 0-based and half-open ranges (`[start, end)`).
3. If you change leaf hashing or tree branching, update all of these together:
   - `CONSTRAINTS`
   - `PUBLIC_SIGNAL_ORDER`
   - `PUBLIC_SIGNAL_LENGTH`
   - parameter table
4. Always mark newly introduced signals as `PUBLIC_INPUTS`, `PUBLIC_OUTPUTS`, or `INTERNAL_SIGNALS`.
5. Keep variable names stable unless you intentionally want downstream converters to change naming.
6. Do not mix bridge-active and prefix/address circuit variants in one pseudocode block; choose one variant and keep it consistent.

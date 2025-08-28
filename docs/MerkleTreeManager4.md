# MerkleTreeManager4

## Overview

`MerkleTreeManager4` is an implementation of a quaternary Merkle tree manager that constructs 4-ary Merkle trees instead of binary Merkle trees. It uses the `keccak256` hash function to hash 4 inputs at each level, providing more efficient tree construction and verification for certain use cases.

## Key Features

- **Quaternary Tree Structure**: Each internal node has exactly 4 children instead of 2
- **Poseidon4Yul Hashing**: Uses the Yul-optimized Poseidon4 hash function for efficient hashing
- **Multi-Channel Support**: Maintains separate Merkle trees for different channels
- **RLC (Random Linear Combination)**: Implements RLC for leaf computation using the previous root
- **Incremental Updates**: Supports adding leaves incrementally while maintaining the tree structure

## Architecture

### Tree Structure

```
Level 0 (Root):                    [R]
Level 1:                    [A] [B] [C] [D]
Level 2:              [E][F][G][H] [I][J][K][L] [M][N][O][P] [Q][R][S][T]
Level 3: [U][V][W][X] [Y][Z][AA][BB] [CC][DD][EE][FF] [GG][HH][II][JJ] ...
```

### Hash Function

The contract uses `Poseidon4Yul` which takes 4 inputs and produces a single hash output:

```solidity
function hashFour(bytes32 _a, bytes32 _b, bytes32 _c, bytes32 _d) public view returns (bytes32)
```

### Leaf Computation

Leaves are computed using RLC (Random Linear Combination):

```
gamma = Poseidon4Yul(prevRoot, l2Addr, 0, 0)
leaf = l2Addr + gamma * balance (mod FIELD_SIZE)
```

## Usage

### Deployment

```solidity
// Deploy Poseidon4Yul hasher
Poseidon4Yul poseidonHasher = new Poseidon4Yul();

// Deploy MerkleTreeManager4 with desired depth
        MerkleTreeManager4 merkleTree = new MerkleTreeManager4();

// Set bridge address
merkleTree.setBridge(bridgeAddress);
```

### Initializing a Channel

```solidity
// Initialize a new channel
merkleTree.initializeChannel(channelId);
```

### Setting Address Mappings

```solidity
// Map L1 addresses to L2 addresses
merkleTree.setAddressPair(channelId, l1Address, l2Address);
```

### Adding Users

```solidity
// Add users with their initial balances
address[] memory l1Addresses = [user1, user2, user3];
uint256[] memory balances = [100, 200, 300];
merkleTree.addUsers(channelId, l1Addresses, balances);
```

### Verifying Proofs

```solidity
// Verify a Merkle proof
bool isValid = merkleTree.verifyProof(channelId, proof, leaf, leafIndex, root);
```

## Advantages of Quaternary Trees

1. **Higher Branching Factor**: More children per node means shorter tree height
2. **Efficient for Large Datasets**: Better suited for applications with many leaves
3. **Reduced Proof Size**: Shorter paths from leaf to root
4. **Better Gas Efficiency**: Fewer hash operations for the same number of leaves

## Comparison with Binary Trees

| Aspect | Binary Tree (MerkleTreeManager2) | Quaternary Tree (MerkleTreeManager4) |
|--------|-----------------------------------|--------------------------------------|
| Children per node | 2 | 4 |
| Tree height | log₂(n) | log₄(n) |
| Hash function | Poseidon2Yul | Poseidon4Yul |
| Max depth | 32 | 16 |
| Max leaves (depth 4) | 16 | 256 |

## Gas Optimization

The quaternary structure provides gas savings through:
- Fewer hash operations per leaf insertion
- Shorter proof verification paths
- More efficient tree traversal

## Security Considerations

- **Field Size**: All values must be within the BLS12-381 field size
- **Depth Limits**: Maximum depth is limited to 16 for quaternary trees
- **Bridge Access Control**: Only the bridge contract can modify tree state
- **RLC Security**: Uses cryptographically secure random linear combinations

## Testing

Run the test suite:

```bash
forge test --match-contract MerkleTreeManager4Test
```

## Deployment

Use the provided deployment script:

```bash
forge script script/DeployMerkleTreeManager4.s.sol --rpc-url <RPC_URL> --broadcast
```

## Dependencies

- `@poseidon/Poseidon4Yul.sol` - Quaternary Poseidon hash function
- `@poseidon/Field.sol` - Field arithmetic utilities
- `@openzeppelin/access/Ownable.sol` - Access control

## License

MIT License

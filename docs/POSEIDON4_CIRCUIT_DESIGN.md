# Poseidon4 Circuit Design for Groth16 Implementation

## Circuit Architecture

### High-Level Design

```
┌─────────────────────────────────────────────────────────────┐
│                    Groth16 Circuit                          │
│                                                             │
│  Public Inputs:                                             │
│  • merkle_root (Fr)                                         │
│  • participant_count (Fr)                                   │
│  • channel_id (Fr)                                          │
│                                                             │
│  Private Inputs:                                            │
│  • participants[N] = {l1_addr, l2_addr, balance}            │
│  • intermediate_hashes[levels][nodes]                       │
│                                                             │
│  Constraints:                                               │
│  1. Direct Leaf Computation (Poseidon4)                     │
│  2. Merkle Tree Construction (Poseidon4)                    │
│  3. Root Verification                                       │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Circuit Components

#### 1. Storage-Based Leaf Computation Module

**Functionality**: Compute Poseidon4-based leaf values for storage key-value pairs

```circom
template StorageLeafComputation(max_leaves) {
    // Public inputs
    signal input channel_id;
    signal input active_leaves;
    
    // Private inputs - storage key-value pairs
    signal input storage_keys[max_leaves];
    signal input storage_values[max_leaves];
    
    // Outputs
    signal output leaf_values[max_leaves];
    
    // Components - Poseidon4 hash for each leaf
    component poseidon4[max_leaves];
    
    for (var i = 0; i < max_leaves; i++) {
        poseidon4[i] = Poseidon(4);
        
        // New RLC formula: Poseidon4(key, value, 0, 0)
        poseidon4[i].inputs[0] <== storage_keys[i];
        poseidon4[i].inputs[1] <== storage_values[i];
        poseidon4[i].inputs[2] <== 0;
        poseidon4[i].inputs[3] <== 0;
        
        leaf_values[i] <== poseidon4[i].out;
    }
    
    // Ensure active_leaves is within bounds
    component lt = LessThan(16); // max 65535 leaves
    lt.in[0] <== active_leaves;
    lt.in[1] <== max_leaves + 1;
    lt.out === 1;
}
```

#### 2. Poseidon4 Merkle Tree Module

**Functionality**: Construct quaternary Merkle tree using Poseidon4 hash

```circom
template Poseidon4MerkleTree(tree_depth, max_leaves) {
    signal input leaves[max_leaves];
    signal input leaf_count;
    signal output root;
    
    // Internal signals for tree computation
    var total_nodes = (4^tree_depth - 1) / 3; // Sum of geometric series
    signal tree_nodes[total_nodes];
    
    // Poseidon4 hash components
    component poseidon4[total_nodes / 4];
    
    // Level-by-level tree construction
    var node_index = 0;
    var leaves_processed = 0;
    
    // Level 0: Process leaves into first level nodes
    for (var i = 0; i < max_leaves / 4; i++) {
        poseidon4[i] = Poseidon(4);
        
        // Handle variable number of leaves
        component is_active[4];
        for (var j = 0; j < 4; j++) {
            is_active[j] = LessThan(32);
            is_active[j].in[0] <== leaves_processed;
            is_active[j].in[1] <== leaf_count;
            
            // Use actual leaf if active, zero otherwise
            poseidon4[i].inputs[j] <== is_active[j].out * leaves[leaves_processed];
            leaves_processed++;
        }
        
        tree_nodes[node_index] <== poseidon4[i].out;
        node_index++;
    }
    
    // Remaining levels: Hash 4 children into 1 parent
    var prev_level_start = 0;
    var prev_level_size = max_leaves / 4;
    
    for (var level = 1; level < tree_depth; level++) {
        var curr_level_size = prev_level_size / 4;
        
        for (var i = 0; i < curr_level_size; i++) {
            var hash_index = prev_level_start + prev_level_size + i;
            poseidon4[hash_index] = Poseidon(4);
            
            // Get 4 children from previous level
            for (var j = 0; j < 4; j++) {
                var child_index = prev_level_start + (i * 4) + j;
                poseidon4[hash_index].inputs[j] <== tree_nodes[child_index];
            }
            
            tree_nodes[node_index] <== poseidon4[hash_index].out;
            node_index++;
        }
        
        prev_level_start += prev_level_size;
        prev_level_size = curr_level_size;
    }
    
    // Root is the final computed node
    root <== tree_nodes[node_index - 1];
}
```

#### 3. Main Circuit Template

```circom
pragma circom 2.0.0;

include "poseidon.circom";
include "comparators.circom";

template TokamakStorageMerkleProof(max_leaves, tree_depth) {
    // Ensure max_leaves matches tree capacity
    assert(max_leaves <= 4^tree_depth);
    
    // Public inputs
    signal input merkle_root;
    signal input active_leaves;
    signal input channel_id;
    
    // Private inputs - storage data
    signal input storage_keys[max_leaves];
    signal input storage_values[max_leaves];
    
    // Compute storage-based leaves
    component storage_leaves = StorageLeafComputation(max_leaves);
    storage_leaves.channel_id <== channel_id;
    storage_leaves.active_leaves <== active_leaves;
    
    for (var i = 0; i < max_leaves; i++) {
        storage_leaves.storage_keys[i] <== storage_keys[i];
        storage_leaves.storage_values[i] <== storage_values[i];
    }
    
    // Compute Poseidon4 Merkle tree
    component merkle_tree = Poseidon4MerkleTree(tree_depth, max_leaves);
    merkle_tree.leaf_count <== active_leaves;
    
    for (var i = 0; i < max_leaves; i++) {
        merkle_tree.leaves[i] <== storage_leaves.leaf_values[i];
    }
    
    // Verify computed root matches public input
    merkle_root === merkle_tree.root;
}

// Instantiate for MAX_MT_LEAVES from backend
component main = TokamakStorageMerkleProof(16, 2); // 16 max leaves, depth 2
```

### Circuit Optimization Strategies

#### 1. Constraint Reduction Techniques

**Selective Computation**: Only compute hashes for active participants
```circom
// Instead of computing all possible hashes
for (var i = 0; i < max_participants; i++) {
    component is_active = LessThan(8);
    is_active.in[0] <== i;
    is_active.in[1] <== participant_count;
    
    // Only perform computation if participant is active
    leaf_values[i] <== is_active.out * computed_leaf + (1 - is_active.out) * 0;
}
```

**Batch Processing**: Process multiple operations in single constraint
```circom
// Combine multiple field operations
signal combined <== a + b * c + d * e * f;
// Instead of separate constraints for each operation
```

#### 2. Memory Optimization

**Streaming Computation**: Avoid storing all intermediate values
```circom
// Instead of storing full tree
signal tree_nodes[total_nodes];

// Use streaming approach
signal current_level[level_size];
signal next_level[level_size / 4];
```

**Compressed Representation**: Use bit packing for addresses
```circom
// Pack L2 address (160 bits) efficiently in field element
component address_packer = Num2Bits(160);
address_packer.in <== l2_addresses[i];
```

### Gas Cost Projections

#### Circuit Size Analysis

| Participants | Poseidon2 Ops | Poseidon4 Ops | Total Constraints | Proving Time | Proof Size |
|--------------|---------------|---------------|-------------------|--------------|------------|
| 4            | 4             | 20            | ~25,000           | 1-2s         | 192 bytes  |
| 16           | 16            | 80            | ~100,000          | 5-10s        | 192 bytes  |
| 64           | 64            | 320           | ~400,000          | 20-30s       | 192 bytes  |

#### Verification Gas Costs

**BN254 Groth16 Verification:**
- 2 pairings: ~68,000 gas
- EC operations: ~10,000 gas
- Field operations: ~5,000 gas
- **Total: ~83,000 gas (constant)**

### Implementation Roadmap

#### Phase 1: Basic Circuit
```bash
# Setup circom environment
npm install -g circom
npm install snarkjs

# Create basic circuit
mkdir tokamak-circuits
cd tokamak-circuits
cat > merkle.circom << 'EOF'
pragma circom 2.0.0;
include "poseidon.circom";

template SimpleMerkle() {
    signal input leaves[4];
    signal output root;
    
    component hasher = Poseidon(4);
    for (var i = 0; i < 4; i++) {
        hasher.inputs[i] <== leaves[i];
    }
    root <== hasher.out;
}

component main = SimpleMerkle();
EOF

# Compile circuit
circom merkle.circom --r1cs --wasm --sym
```

#### Phase 2: RLC Integration 
- Implement RLC computation in circuit
- Test with actual participant data
- Benchmark constraint count

#### Phase 3: Full Tree Implementation
- Complete quaternary tree logic
- Handle variable participant counts
- Optimize for gas costs

#### Phase 4: Integration Testing
- Generate proofs for test data
- Deploy verifier contract
- End-to-end testing with bridge

### Security Considerations

#### Circuit Vulnerabilities

1. **Underconstraint Bugs**: Missing constraints allow invalid proofs
   - Use formal verification tools
   - Extensive property-based testing
   - Circuit audit by experts

2. **Overflow/Underflow**: Field arithmetic edge cases
   - Careful range checking
   - Explicit bounds verification
   - Test with boundary values

3. **Trusted Setup**: Groth16 ceremony compromise
   - Use established ceremonies (Zcash, Tornado Cash)
   - Consider universal setups (PLONK)
   - Multi-party computation for custom setups

#### Mitigation Strategies

```circom
// Range checking for balances
component balance_check = LessThan(64);
balance_check.in[0] <== balances[i];
balance_check.in[1] <== 2^63; // Prevent overflow
balance_check.out === 1;

// Uniqueness constraints for addresses
component addr_unique = IsEqual();
for (var i = 0; i < max_participants; i++) {
    for (var j = i + 1; j < max_participants; j++) {
        addr_unique.in[0] <== l2_addresses[i];
        addr_unique.in[1] <== l2_addresses[j];
        addr_unique.out === 0; // Must be different
    }
}
```

### Performance Benchmarks

#### Expected Performance Metrics

| Metric | Small (4p) | Medium (16p) | Large (64p) |
|--------|------------|--------------|-------------|
| Constraints | 25K | 100K | 400K |
| Proving Time | 1-2s | 5-10s | 20-30s |
| Memory Usage | 100MB | 300MB | 800MB |
| Gas Cost | 83K | 83K | 83K |


The Groth16 solution provides substantial gas savings that increase with channel size, making it particularly beneficial for larger channels while maintaining constant verification costs.
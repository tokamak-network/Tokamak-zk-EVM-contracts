pragma circom 2.0.0;

include "../node_modules/poseidon-bls12381-circom/circuits/poseidon255.circom";

// Parameterized Poseidon Merkle Tree based on tree depth N
// Tree capacity: 2^N leaves
template Poseidon2MerkleTree(N) {
    var nLeaves = 2 ** N;
    signal input leaves[nLeaves];
    signal output root;
    
    // Calculate total number of components needed across all levels
    var totalComponents = 0;
    var temp = nLeaves;
    for (var level = 0; level < N; level++) {
        temp = temp \ 2;
        totalComponents += temp;
    }
    
    component hashers[totalComponents];
    
    // Signals to store outputs for each level
    signal levelOutputs[N][nLeaves \ 2];
    
    var componentIndex = 0;
    var currentLevelSize = nLeaves;
    
    for (var level = 0; level < N; level++) {
        var nextLevelSize = currentLevelSize \ 2;
        
        for (var i = 0; i < nextLevelSize; i++) {
            hashers[componentIndex] = Poseidon255(2);
            
            if (level == 0) {
                // First level: use input leaves
                hashers[componentIndex].in[0] <== leaves[i*2 + 0];
                hashers[componentIndex].in[1] <== leaves[i*2 + 1];
            } else {
                // Subsequent levels: use previous level outputs
                hashers[componentIndex].in[0] <== levelOutputs[level-1][i*2 + 0];
                hashers[componentIndex].in[1] <== levelOutputs[level-1][i*2 + 1];
            }
            
            levelOutputs[level][i] <== hashers[componentIndex].out;
            componentIndex++;
        }
        
        currentLevelSize = nextLevelSize;
    }
    
    // Root is the single output from the last level
    root <== levelOutputs[N-1][0];
}

// Parameterized Tokamak Storage Merkle Proof based on tree depth N
template TokamakStorageMerkleProof(N) {
    var nLeaves = 2 ** N;
    
    // Public inputs - Fixed prefix, contract address, L2MPT storage keys and values
    signal input fixed_prefix;                 // Fixed prefix for contract identification
    signal input contract_address;             // Contract address
    signal input storage_keys_L2MPT[nLeaves];  // L2MPT storage keys
    signal input storage_values[nLeaves];      // Storage values
    
    // Public output - the computed Merkle root
    signal output merkle_root;
    
    // Step 1: Compute contract identifier
    // contract_id = poseidon2(fixed_prefix, contract_address)
    component contract_id_hash = Poseidon255(2);
    contract_id_hash.in[0] <== fixed_prefix;
    contract_id_hash.in[1] <== contract_address;
    signal contract_id <== contract_id_hash.out;
    
    // Step 2: Compute intermediate leaf values
    // intermediate = poseidon2(storage_key_L2MPT, storage_value)
    component intermediate_hash[nLeaves];
    signal intermediate_values[nLeaves];
    
    for (var i = 0; i < nLeaves; i++) {
        intermediate_hash[i] = Poseidon255(2);
        intermediate_hash[i].in[0] <== storage_keys_L2MPT[i];
        intermediate_hash[i].in[1] <== storage_values[i];
        intermediate_values[i] <== intermediate_hash[i].out;
    }
    
    // Step 3: Compute final leaves
    // leaf = poseidon2(contract_id, intermediate_value)
    component leaf_hash[nLeaves];
    signal leaf_values[nLeaves];
    
    for (var i = 0; i < nLeaves; i++) {
        leaf_hash[i] = Poseidon255(2);
        leaf_hash[i].in[0] <== contract_id;
        leaf_hash[i].in[1] <== intermediate_values[i];
        leaf_values[i] <== leaf_hash[i].out;
    }
    
    // Step 4: Compute Merkle tree
    component merkle_tree = Poseidon2MerkleTree(N);
    
    for (var i = 0; i < nLeaves; i++) {
        merkle_tree.leaves[i] <== leaf_values[i];
    }
    
    // Output the computed root
    merkle_root <== merkle_tree.root;
}

// Example configurations:
// N=2: 2^2 = 4 leaves   (suitable for small channels)
// N=3: 2^3 = 8 leaves   (suitable for medium channels)  
// N=4: 2^4 = 16 leaves  (suitable for large channels)

// Change this line to configure for different tree depths:
component main{public [fixed_prefix, contract_address, storage_keys_L2MPT, storage_values]} = TokamakStorageMerkleProof(4);

// Tree depth N=4 gives us 16 leaves, which can support:
// - 16 users with 1 storage slot each, OR
// - 8 users with 2 storage slots each, OR
// - 4 users with 4 storage slots each, OR
// - 2 users with 8 storage slots each, OR
// - 1 user with 16 storage slots
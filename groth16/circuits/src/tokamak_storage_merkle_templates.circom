include "../node_modules/poseidon-bls12381-circom/circuits/poseidon255.circom";

// Shared Poseidon Merkle tree template parameterized by tree depth N.
// Tree capacity: 2^N leaves.
template Poseidon2MerkleTree(N) {
    var nLeaves = 2 ** N;
    signal input leaves[nLeaves];
    signal output root;

    // Calculate total number of components needed across all levels.
    var totalComponents = 0;
    var temp = nLeaves;
    for (var level = 0; level < N; level++) {
        temp = temp \ 2;
        totalComponents += temp;
    }

    component hashers[totalComponents];

    // Signals to store outputs for each level.
    signal levelOutputs[N][nLeaves \ 2];

    var componentIndex = 0;
    var currentLevelSize = nLeaves;

    for (var level = 0; level < N; level++) {
        var nextLevelSize = currentLevelSize \ 2;

        for (var i = 0; i < nextLevelSize; i++) {
            hashers[componentIndex] = Poseidon255(2);

            if (level == 0) {
                // First level: use input leaves.
                hashers[componentIndex].in[0] <== leaves[i * 2 + 0];
                hashers[componentIndex].in[1] <== leaves[i * 2 + 1];
            } else {
                // Subsequent levels: use previous level outputs.
                hashers[componentIndex].in[0] <== levelOutputs[level - 1][i * 2 + 0];
                hashers[componentIndex].in[1] <== levelOutputs[level - 1][i * 2 + 1];
            }

            levelOutputs[level][i] <== hashers[componentIndex].out;
            componentIndex++;
        }

        currentLevelSize = nextLevelSize;
    }

    // Root is the single output from the last level.
    root <== levelOutputs[N - 1][0];
}

// Shared single-leaf template for Tokamak storage inputs.
template TokamakStorageLeaf() {
    signal input contract_id;
    signal input storage_key_L2MPT;
    signal input storage_value;
    signal output leaf;

    // intermediate = poseidon2(storage_key_L2MPT, storage_value)
    component intermediate_hash = Poseidon255(2);
    intermediate_hash.in[0] <== storage_key_L2MPT;
    intermediate_hash.in[1] <== storage_value;

    // leaf = poseidon2(contract_id, intermediate_value)
    component leaf_hash = Poseidon255(2);
    leaf_hash.in[0] <== contract_id;
    leaf_hash.in[1] <== intermediate_hash.out;
    leaf <== leaf_hash.out;
}

// Shared Tokamak storage Merkle proof template parameterized by tree depth N.
template TokamakStorageMerkleProof(N) {
    var nLeaves = 2 ** N;

    // Public inputs.
    signal input fixed_prefix;                 // Fixed prefix for contract identification.
    signal input contract_address;             // Contract address.
    signal input storage_keys_L2MPT[nLeaves];  // L2MPT storage keys.
    signal input storage_values[nLeaves];      // Storage values.

    // Public output.
    signal output merkle_root;

    // Step 1: Compute contract identifier.
    // contract_id = poseidon2(fixed_prefix, contract_address)
    component contract_id_hash = Poseidon255(2);
    contract_id_hash.in[0] <== fixed_prefix;
    contract_id_hash.in[1] <== contract_address;
    signal contract_id <== contract_id_hash.out;

    // Step 2: Compute leaves from per-entry storage inputs.
    component storage_leaf[nLeaves];
    signal leaf_values[nLeaves];

    for (var i = 0; i < nLeaves; i++) {
        storage_leaf[i] = TokamakStorageLeaf();
        storage_leaf[i].contract_id <== contract_id;
        storage_leaf[i].storage_key_L2MPT <== storage_keys_L2MPT[i];
        storage_leaf[i].storage_value <== storage_values[i];
        leaf_values[i] <== storage_leaf[i].leaf;
    }

    // Step 3: Compute Merkle tree.
    component merkle_tree = Poseidon2MerkleTree(N);

    for (var i = 0; i < nLeaves; i++) {
        merkle_tree.leaves[i] <== leaf_values[i];
    }

    // Output the computed root.
    merkle_root <== merkle_tree.root;
}

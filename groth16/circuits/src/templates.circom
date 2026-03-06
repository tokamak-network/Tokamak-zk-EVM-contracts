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
template computeLeaf() {
    signal input storage_key;
    signal input storage_value;
    signal output leaf;

    // leaf = poseidon2(storage_key, storage_value)
    component leaf_hash = Poseidon255(2);
    leaf_hash.in[0] <== storage_key;
    leaf_hash.in[1] <== storage_value;
    leaf <== leaf_hash.out;
}

// Shared Tokamak storage Merkle proof template parameterized by tree depth N.
template updateTree(N) {
    var nLeaves = 2 ** N;

    // Public inputs.
    signal input storage_keys[nLeaves];  // L2MPT storage keys.
    signal input storage_values[nLeaves];      // Storage values.

    // Public output.
    signal output merkle_root;

    // Step 1: Compute leaves from per-entry storage inputs.
    component storage_leaf[nLeaves];
    signal leaf_values[nLeaves];

    for (var i = 0; i < nLeaves; i++) {
        storage_leaf[i] = computeLeaf();
        storage_leaf[i].storage_key <== storage_keys[i];
        storage_leaf[i].storage_value <== storage_values[i];
        leaf_values[i] <== storage_leaf[i].leaf;
    }

    // Step 2: Compute Merkle tree.
    component merkle_tree = Poseidon2MerkleTree(N);

    for (var i = 0; i < nLeaves; i++) {
        merkle_tree.leaves[i] <== leaf_values[i];
    }

    // Output the computed root.
    merkle_root <== merkle_tree.root;
}

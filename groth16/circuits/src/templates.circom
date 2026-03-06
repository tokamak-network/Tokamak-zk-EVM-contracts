pragma circom 2.2.2;

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

// Rebuilds a Merkle root from one leaf and its sibling path.
template verifyMerkleProof(N) {
    signal input leaf;
    signal input leaf_index;
    signal input proof[N]; // Sibling node at each tree level (bottom-up).
    signal output root;

    signal index_bits[N];
    signal index_acc[N + 1];
    signal left_nodes[N];
    signal right_nodes[N];
    signal level_hashes[N + 1];
    component hashers[N];

    index_acc[0] <== 0;
    level_hashes[0] <== leaf;

    var bit_weight = 1;
    for (var i = 0; i < N; i++) {
        // Decompose leaf_index into N binary bits.
        index_bits[i] * (index_bits[i] - 1) === 0;
        index_acc[i + 1] <== index_acc[i] + index_bits[i] * bit_weight;
        bit_weight = bit_weight * 2;

        // If bit is 0: hash(current, sibling), else hash(sibling, current).
        left_nodes[i] <== level_hashes[i] + index_bits[i] * (proof[i] - level_hashes[i]);
        right_nodes[i] <== proof[i] + index_bits[i] * (level_hashes[i] - proof[i]);

        hashers[i] = Poseidon255(2);
        hashers[i].in[0] <== left_nodes[i];
        hashers[i].in[1] <== right_nodes[i];
        level_hashes[i + 1] <== hashers[i].out;
    }

    // Constrain index range: 0 <= leaf_index < 2^N.
    leaf_index === index_acc[N];
    root <== level_hashes[N];
}

// Verifies one-leaf update consistency using before/after Merkle proofs.
template updateTree(N) {
    // Public inputs for the target leaf update.
    signal input leaf_index;
    signal input storage_key;
    signal input storage_value_before;
    signal input storage_value_after;
    signal input proof_before[N];
    signal input proof_after[N];

    // Public outputs: old and new roots derived from proofs.
    signal output root_before;
    signal output root_after;

    // Compute the updated leaf values.
    component leaf_before = computeLeaf();
    leaf_before.storage_key <== storage_key;
    leaf_before.storage_value <== storage_value_before;

    component leaf_after = computeLeaf();
    leaf_after.storage_key <== storage_key;
    leaf_after.storage_value <== storage_value_after;

    // 1) Verify the pre-update Merkle proof.
    component merkle_before = verifyMerkleProof(N);
    merkle_before.leaf <== leaf_before.leaf;
    merkle_before.leaf_index <== leaf_index;

    // 2) Verify the post-update Merkle proof.
    component merkle_after = verifyMerkleProof(N);
    merkle_after.leaf <== leaf_after.leaf;
    merkle_after.leaf_index <== leaf_index;

    for (var i = 0; i < N; i++) {
        merkle_before.proof[i] <== proof_before[i];
        merkle_after.proof[i] <== proof_after[i];

        // 3) Every path sibling node must stay equal across proofs.
        proof_before[i] === proof_after[i];
    }

    root_before <== merkle_before.root;
    root_after <== merkle_after.root;
}

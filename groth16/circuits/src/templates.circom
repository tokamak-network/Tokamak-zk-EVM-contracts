pragma circom 2.2.2;

include "../node_modules/poseidon-bls12381-circom/circuits/poseidon255.circom";

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

// Computes a Merkle root from pre-allocated key/value inputs and zero-filled leaves.
template computeInitialRoot(N_PRE_ALLOC_KEYS, N_LEVELS) {
    signal input pre_allocated_keys[N_PRE_ALLOC_KEYS];
    signal input pre_allocated_values[N_PRE_ALLOC_KEYS];
    signal output root;

    // Derive the leaf count from the level count: N_LEAVES = 2**N_LEVELS.
    var N_LEAVES = 2**N_LEVELS;

    // Compile-time guard: N_LEAVES must be strictly greater than N_PRE_ALLOC_KEYS.
    assert(N_LEAVES > N_PRE_ALLOC_KEYS);

    // Build leaves:
    // - First N_PRE_ALLOC_KEYS leaves use provided (key, value).
    // - Remaining leaves use (0, 0).
    signal tree_nodes[(2 * N_LEAVES) - 1];
    for (var i = 0; i < N_LEAVES; i++) {
        if (i < N_PRE_ALLOC_KEYS) {
            tree_nodes[(N_LEAVES - 1) + i] <== computeLeaf()(
                storage_key <== pre_allocated_keys[i],
                storage_value <== pre_allocated_values[i]
            );
        } else {
            tree_nodes[(N_LEAVES - 1) + i] <== computeLeaf()(storage_key <== 0, storage_value <== 0);
        }
    }

    // Build parent nodes bottom-up.
    component node_hashers[N_LEAVES - 1];
    for (var i = 0; i < (N_LEAVES - 1); i++) {
        var node_idx = (N_LEAVES - 2) - i;
        node_hashers[i] = Poseidon255(2);
        node_hashers[i].in[0] <== tree_nodes[(2 * node_idx) + 1];
        node_hashers[i].in[1] <== tree_nodes[(2 * node_idx) + 2];
        tree_nodes[node_idx] <== node_hashers[i].out;
    }

    root <== tree_nodes[0];
}

// Rebuilds a Merkle root from one leaf and its sibling path.
template verifyMerkleProof(N) {
    signal input leaf;
    signal input leaf_index;
    signal input expected_root;
    signal input proof[N]; // Sibling node at each tree level (bottom-up).

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
        index_bits[i] <-- (leaf_index \ bit_weight) % 2;
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

    // Constrain the reconstructed root to the provided public root.
    expected_root === level_hashes[N];
}

// Verifies one-leaf update consistency using before/after Merkle proofs.
template updateTree(N) {
    // Input visibility is determined by component main{public [...]} in circuit_N*.circom.
    signal input root_before;          // [PUBLIC]
    signal input root_after;           // [PUBLIC]
    signal input leaf_index;           // [PRIVATE]
    signal input storage_key;          // [PUBLIC]
    signal input storage_value_before; // [PUBLIC]
    signal input storage_value_after;  // [PUBLIC]
    signal input proof[N];             // [PRIVATE]

    // Compute the updated leaf values.
    component leaf_before = computeLeaf();
    leaf_before.storage_key <== storage_key;
    leaf_before.storage_value <== storage_value_before;

    component leaf_after = computeLeaf();
    leaf_after.storage_key <== storage_key;
    leaf_after.storage_value <== storage_value_after;

    // Enforce an actual update happened.
    signal value_delta;
    signal value_delta_inv;
    value_delta <== storage_value_after - storage_value_before;
    value_delta_inv <-- 1 / value_delta;
    value_delta * value_delta_inv === 1;

    // 1) Verify the pre-update Merkle proof.
    component merkle_before = verifyMerkleProof(N);
    merkle_before.leaf <== leaf_before.leaf;
    merkle_before.leaf_index <== leaf_index;
    merkle_before.expected_root <== root_before;

    // 2) Verify the post-update Merkle proof.
    component merkle_after = verifyMerkleProof(N);
    merkle_after.leaf <== leaf_after.leaf;
    merkle_after.leaf_index <== leaf_index;
    merkle_after.expected_root <== root_after;

    // 3) Path nodes are shared for before/after; one proof array is sufficient.
    for (var i = 0; i < N; i++) {
        merkle_before.proof[i] <== proof[i];
        merkle_after.proof[i] <== proof[i];
    }
}

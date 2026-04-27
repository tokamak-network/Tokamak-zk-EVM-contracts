pragma circom 2.2.2;

include "../node_modules/poseidon-bls12381-circom/circuits/poseidon255.circom";

// Derives the Merkle leaf index as the lower N bits of storage_key.
template deriveLeafIndexFromStorageKey(N) {
    signal input storage_key;
    signal input leaf_index;

    signal key_bits[255];
    signal key_acc[256];
    signal leaf_index_bits[N];
    signal leaf_index_acc[N + 1];

    key_acc[0] <== 0;
    leaf_index_acc[0] <== 0;
    var bit_weight = 1;
    for (var i = 0; i < 255; i++) {
        key_bits[i] <-- (storage_key \ bit_weight) % 2;
        key_bits[i] * (key_bits[i] - 1) === 0;
        key_acc[i + 1] <== key_acc[i] + key_bits[i] * bit_weight;

        if (i < N) {
            leaf_index_bits[i] <== key_bits[i];
            leaf_index_acc[i + 1] <== leaf_index_acc[i] + key_bits[i] * bit_weight;
        }

        bit_weight = bit_weight * 2;
    }

    storage_key === key_acc[255];
    leaf_index === leaf_index_acc[N];
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

    component leaf_index_constraint = deriveLeafIndexFromStorageKey(N);
    leaf_index_constraint.storage_key <== storage_key;
    leaf_index_constraint.leaf_index <== leaf_index;

    // Enforce an actual update happened.
    signal value_delta;
    signal value_delta_inv;
    value_delta <== storage_value_after - storage_value_before;
    value_delta_inv <-- 1 / value_delta;
    value_delta * value_delta_inv === 1;

    // 1) Verify the pre-update Merkle proof.
    component merkle_before = verifyMerkleProof(N);
    merkle_before.leaf <== storage_value_before;
    merkle_before.leaf_index <== leaf_index;
    merkle_before.expected_root <== root_before;

    // 2) Verify the post-update Merkle proof.
    component merkle_after = verifyMerkleProof(N);
    merkle_after.leaf <== storage_value_after;
    merkle_after.leaf_index <== leaf_index;
    merkle_after.expected_root <== root_after;

    // 3) Path nodes are shared for before/after; one proof array is sufficient.
    for (var i = 0; i < N; i++) {
        merkle_before.proof[i] <== proof[i];
        merkle_after.proof[i] <== proof[i];
    }
}

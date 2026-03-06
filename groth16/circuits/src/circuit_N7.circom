pragma circom 2.2.2;

include "./templates.circom";

component main{public [leaf_index, storage_key, storage_value_before, storage_value_after, proof_before, proof_after]} = updateTree(7);

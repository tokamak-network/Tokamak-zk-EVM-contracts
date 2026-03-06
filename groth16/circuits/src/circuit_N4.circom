pragma circom 2.2.2;

include "./templates.circom";

component main{public [root_before, root_after, leaf_index, storage_key, storage_value_before, storage_value_after, proof]} = updateTree(4);

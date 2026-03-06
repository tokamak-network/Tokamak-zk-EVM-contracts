pragma circom 2.0.0;

include "./templates.circom";

component main{public [storage_keys, storage_values]} = updateTree(4);

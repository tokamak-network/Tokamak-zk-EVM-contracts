pragma circom 2.2.2;

include "./templates.circom";

component main{public [storage_keys, storage_values]} = updateTree(4);

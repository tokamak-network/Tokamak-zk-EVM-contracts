pragma circom 2.2.3;

include "./templates.circom";

component main{public [storage_keys, storage_values]} = updateTree(5);

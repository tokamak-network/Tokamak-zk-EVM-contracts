pragma circom 2.2.2;

include "./templates.circom";

component main{public [root_before, root_after, storage_key_before, storage_value_before, storage_key_after, storage_value_after]} = updateTree(10);

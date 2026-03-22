pragma circom 2.2.2;

include "./templates.circom";

// This entrypoint is rendered by the updateTree trusted-setup generator.
// The generator injects the latest tokamak-l2js MT_DEPTH into the updateTree depth parameter.
component main{public [root_before, root_after, leaf_index, storage_key_before, storage_value_before, storage_key_after, storage_value_after]} = updateTree(__MT_DEPTH__);

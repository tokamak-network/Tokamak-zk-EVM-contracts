pragma circom 2.0.0;

include "./tokamak_storage_merkle_templates.circom";

component main{public [fixed_prefix, contract_address, storage_keys_L2MPT, storage_values]} = TokamakStorageMerkleProof(4);

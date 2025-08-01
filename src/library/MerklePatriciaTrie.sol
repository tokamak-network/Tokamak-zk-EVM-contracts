// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

library MerklePatriciaTrie {
    // Empty trie hash (keccak256(RLP([])))
    bytes32 constant EMPTY_TRIE_HASH = 0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421;
    
    struct StorageLeaf {
        bytes32 storageKey;  // The storage slot key
        uint256 slot;        // The slot number
        address participant; // The participant address
        uint256 value;       // The stored value
    }
    
    /**
     * @dev Computes a simplified MPT root from storage leaves
     * @param leaves Array of storage leaves
     * @return The computed root hash
     */
    function computeStorageRoot(StorageLeaf[] memory leaves) internal pure returns (bytes32) {
        if (leaves.length == 0) {
            return EMPTY_TRIE_HASH;
        }
        
        // Sort leaves by storage key for deterministic ordering
        _sortLeavesByKey(leaves);
        
        // Create leaf hashes matching the off-chain format
        bytes32[] memory leafHashes = new bytes32[](leaves.length);
        for (uint256 i = 0; i < leaves.length; i++) {
            // Match the serialization format: [key, slot, address, value]
            leafHashes[i] = keccak256(abi.encodePacked(
                leaves[i].storageKey,
                leaves[i].slot,
                leaves[i].participant,
                leaves[i].value
            ));
        }
        
        // Build Merkle tree from leaves
        return _computeMerkleRoot(leafHashes);
    }
    
    /**
     * @dev Computes storage key matching the TypeScript getStorageKey function
     * For mapping(bytes32(address) => uint256) at slot s: key = keccak256(bytes32(address) || slot)
     * @param participant The participant address
     * @param slot The storage slot
     * @return The storage key
     */
    function computeStorageKey(address participant, uint256 slot) internal pure returns (bytes32) {
        // Create 64-byte array with both values padded to 32 bytes
        bytes memory packed = abi.encodePacked(
            bytes32(uint256(uint160(participant))),  // Pad address to 32 bytes
            bytes32(slot)                             // Pad slot to 32 bytes
        );
        return keccak256(packed);
    }
    
    // For single slot (matching off-chain getStorageKey([slot]))
    function computeStorageKey(uint256 slot) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(bytes32(slot)));
    }
    
    /**
     * @dev Builds a binary Merkle tree from leaf hashes
     */
    function _computeMerkleRoot(bytes32[] memory leaves) private pure returns (bytes32) {
        uint256 n = leaves.length;
        
        if (n == 1) {
            return leaves[0];
        }
        
        // Create a working array
        bytes32[] memory tree = new bytes32[](n);
        for (uint256 i = 0; i < n; i++) {
            tree[i] = leaves[i];
        }
        
        // Build tree bottom-up
        while (n > 1) {
            uint256 halfN = (n + 1) / 2;
            for (uint256 i = 0; i < halfN; i++) {
                if (2 * i + 1 < n) {
                    tree[i] = keccak256(abi.encodePacked(tree[2 * i], tree[2 * i + 1]));
                } else {
                    // For odd number of nodes, hash with empty
                    tree[i] = keccak256(abi.encodePacked(tree[2 * i], bytes32(0)));
                }
            }
            n = halfN;
        }
        
        return tree[0];
    }
    
    /**
     * @dev Sorts storage leaves by their storage key
     */
    function _sortLeavesByKey(StorageLeaf[] memory leaves) private pure {
        uint256 n = leaves.length;
        for (uint256 i = 0; i < n - 1; i++) {
            for (uint256 j = 0; j < n - i - 1; j++) {
                if (uint256(leaves[j].storageKey) > uint256(leaves[j + 1].storageKey)) {
                    StorageLeaf memory temp = leaves[j];
                    leaves[j] = leaves[j + 1];
                    leaves[j + 1] = temp;
                }
            }
        }
    }
    
    /**
     * @dev Verifies a Merkle proof for a storage value
     * @param proof Array of sibling hashes
     * @param root The root hash to verify against
     * @param leaf The storage leaf to verify
     * @return Whether the proof is valid
     */
    function verifyStorageProof(
        bytes32[] calldata proof,
        bytes32 root,
        StorageLeaf memory leaf
    ) internal pure returns (bool) {
        bytes32 computedHash = keccak256(abi.encodePacked(
            leaf.storageKey,
            leaf.slot,
            leaf.participant,
            leaf.value
        ));
        
        for (uint256 i = 0; i < proof.length; i++) {
            bytes32 proofElement = proof[i];
            
            if (computedHash <= proofElement) {
                // Current hash goes left
                computedHash = keccak256(abi.encodePacked(computedHash, proofElement));
            } else {
                // Current hash goes right
                computedHash = keccak256(abi.encodePacked(proofElement, computedHash));
            }
        }
        
        return computedHash == root;
    }
    
    /**
     * @dev Creates a leaf hash from balance data (for compatibility)
     */
    function createBalanceLeaf(address participant, uint256 balance, uint256 balanceSlot) 
        internal 
        pure 
        returns (bytes32) 
    {
        bytes32 storageKey = computeStorageKey(participant, balanceSlot);
        return keccak256(abi.encodePacked(
            storageKey,
            balanceSlot,
            participant,
            balance
        ));
    }
}
// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

library MerklePatriciaTrie {
    // Node types in MPT
    uint8 constant LEAF_NODE = 0;
    uint8 constant EXTENSION_NODE = 1;
    uint8 constant BRANCH_NODE = 2;
    
    // Empty node hash
    bytes32 constant EMPTY_HASH = 0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421;
    
    struct LeafData {
        address participant;
        uint256 balance;
    }
    
    /**
     * @dev Computes the root hash of a Merkle Patricia Trie from leaf data
     * @param leaves Array of leaf data containing participant addresses and balances
     * @return The computed MPT root hash
     */
    function computeRoot(LeafData[] memory leaves) internal pure returns (bytes32) {
        if (leaves.length == 0) {
            return EMPTY_HASH;
        }
        
        // For simplicity, we'll implement a modified MPT that's ZK-friendly
        // In a full implementation, this would build the complete trie structure
        
        // Sort leaves by key (address) for deterministic ordering
        _sortLeaves(leaves);
        
        // Build the trie
        return _buildTrie(leaves);
    }
    
    /**
     * @dev Computes the root hash from pre-hashed leaves (for backward compatibility)
     * @param leafHashes Array of pre-computed leaf hashes
     * @return The computed root hash
     */
    function computeRoot(bytes32[] memory leafHashes) internal pure returns (bytes32) {
        if (leafHashes.length == 0) {
            return EMPTY_HASH;
        }
        
        // Simple binary Merkle tree for pre-hashed leaves
        uint256 n = leafHashes.length;
        bytes32[] memory tree = new bytes32[](n);
        
        // Copy leaf hashes
        for (uint256 i = 0; i < n; i++) {
            tree[i] = leafHashes[i];
        }
        
        // Build tree bottom-up
        while (n > 1) {
            uint256 halfN = (n + 1) / 2;
            for (uint256 i = 0; i < halfN; i++) {
                if (2 * i + 1 < n) {
                    tree[i] = keccak256(abi.encodePacked(tree[2 * i], tree[2 * i + 1]));
                } else {
                    tree[i] = tree[2 * i];
                }
            }
            n = halfN;
        }
        
        return tree[0];
    }
    
    /**
     * @dev Verifies a Merkle proof with index
     * @param proof Array of sibling hashes
     * @param root The root hash to verify against
     * @param leaf The leaf hash to verify
     * @param index The index of the leaf in the tree
     * @return Whether the proof is valid
     */
    function verifyProof(
        bytes32[] calldata proof,
        bytes32 root,
        bytes32 leaf,
        uint256 index
    ) internal pure returns (bool) {
        bytes32 computedHash = leaf;
        
        for (uint256 i = 0; i < proof.length; i++) {
            bytes32 proofElement = proof[i];
            
            if (index & 1 == 0) {
                // Current node is left child
                computedHash = keccak256(abi.encodePacked(computedHash, proofElement));
            } else {
                // Current node is right child
                computedHash = keccak256(abi.encodePacked(proofElement, computedHash));
            }
            
            index = index >> 1;
        }
        
        return computedHash == root;
    }
    
    /**
     * @dev Builds a simplified MPT from sorted leaves
     */
    function _buildTrie(LeafData[] memory leaves) private pure returns (bytes32) {
        // For ZK-friendliness, we implement a simplified version
        // that maintains deterministic structure
        
        bytes32[] memory nodes = new bytes32[](leaves.length);
        
        // Create leaf nodes
        for (uint256 i = 0; i < leaves.length; i++) {
            // Key is the hash of the address
            bytes32 key = keccak256(abi.encodePacked(leaves[i].participant));
            // Value is the encoded balance
            bytes memory value = abi.encode(leaves[i].balance);
            // Leaf node = hash(leafPrefix + key + value)
            nodes[i] = keccak256(abi.encodePacked(LEAF_NODE, key, value));
        }
        
        // Build tree from leaf nodes
        return _buildMerkleTree(nodes);
    }
    
    /**
     * @dev Builds a binary Merkle tree from nodes
     */
    function _buildMerkleTree(bytes32[] memory nodes) private pure returns (bytes32) {
        uint256 n = nodes.length;
        
        if (n == 1) {
            return nodes[0];
        }
        
        // Build tree level by level
        while (n > 1) {
            uint256 halfN = (n + 1) / 2;
            for (uint256 i = 0; i < halfN; i++) {
                if (2 * i + 1 < n) {
                    // Branch node with two children
                    nodes[i] = keccak256(abi.encodePacked(BRANCH_NODE, nodes[2 * i], nodes[2 * i + 1]));
                } else {
                    // Single child, create extension node
                    nodes[i] = keccak256(abi.encodePacked(EXTENSION_NODE, nodes[2 * i]));
                }
            }
            n = halfN;
        }
        
        return nodes[0];
    }
    
    /**
     * @dev Sorts leaves by participant address (bubble sort for simplicity)
     */
    function _sortLeaves(LeafData[] memory leaves) private pure {
        uint256 n = leaves.length;
        for (uint256 i = 0; i < n - 1; i++) {
            for (uint256 j = 0; j < n - i - 1; j++) {
                if (uint160(leaves[j].participant) > uint160(leaves[j + 1].participant)) {
                    LeafData memory temp = leaves[j];
                    leaves[j] = leaves[j + 1];
                    leaves[j + 1] = temp;
                }
            }
        }
    }
    
    /**
     * @dev Creates a leaf hash for MPT-style storage
     * @param participant The participant address
     * @param balance The balance amount
     * @return The leaf hash
     */
    function createLeafHash(address participant, uint256 balance) internal pure returns (bytes32) {
        bytes32 key = keccak256(abi.encodePacked(participant));
        bytes memory value = abi.encode(balance);
        return keccak256(abi.encodePacked(LEAF_NODE, key, value));
    }
    
    /**
     * @dev Generates a Merkle proof for a leaf at given index
     * @param leaves All leaf hashes
     * @param index The index of the leaf to prove
     * @return proof Array of sibling hashes
     */
    function generateProof(
        bytes32[] memory leaves,
        uint256 index
    ) internal pure returns (bytes32[] memory proof) {
        require(index < leaves.length, "Index out of bounds");
        
        // Calculate proof size
        uint256 proofSize = 0;
        uint256 n = leaves.length;
        while (n > 1) {
            proofSize++;
            n = (n + 1) / 2;
        }
        
        proof = new bytes32[](proofSize);
        
        // Build the tree and collect proof
        bytes32[] memory currentLevel = new bytes32[](leaves.length);
        for (uint256 i = 0; i < leaves.length; i++) {
            currentLevel[i] = leaves[i];
        }
        
        uint256 currentIndex = index;
        uint256 proofIndex = 0;
        n = leaves.length;
        
        while (n > 1) {
            uint256 halfN = (n + 1) / 2;
            bytes32[] memory nextLevel = new bytes32[](halfN);
            
            for (uint256 i = 0; i < halfN; i++) {
                if (2 * i + 1 < n) {
                    nextLevel[i] = keccak256(abi.encodePacked(currentLevel[2 * i], currentLevel[2 * i + 1]));
                    
                    // Collect proof element
                    if (2 * i == currentIndex) {
                        proof[proofIndex++] = currentLevel[2 * i + 1];
                    } else if (2 * i + 1 == currentIndex) {
                        proof[proofIndex++] = currentLevel[2 * i];
                    }
                } else {
                    nextLevel[i] = currentLevel[2 * i];
                }
            }
            
            currentLevel = nextLevel;
            currentIndex = currentIndex / 2;
            n = halfN;
        }
        
        // Resize proof array to actual size
        assembly {
            mstore(proof, proofIndex)
        }
        
        return proof;
    }
}
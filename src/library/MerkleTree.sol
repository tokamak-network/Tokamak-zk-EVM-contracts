// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

library MerkleTree {
    function computeRoot(bytes32[] memory leaves) internal pure returns (bytes32) {
        uint256 n = leaves.length;
        if (n == 0) return bytes32(0);
        
        while (n > 1) {
            uint256 halfN = (n + 1) / 2;
            for (uint256 i = 0; i < halfN; i++) {
                uint256 left = 2 * i;
                uint256 right = left + 1;
                
                if (right < n) {
                    leaves[i] = keccak256(abi.encodePacked(leaves[left], leaves[right]));
                } else {
                    leaves[i] = leaves[left];
                }
            }
            n = halfN;
        }
        
        return leaves[0];
    }
    
    /**
     * @dev Verifies a Merkle proof proving the existence of a leaf in a Merkle tree.
     * @param proof Merkle proof containing sibling hashes on the path from the leaf to the root
     * @param root Merkle root
     * @param leaf Leaf of Merkle tree
     * @param index Index of the leaf in the original array (0-based)
     * @return bool indicating whether the proof is valid
     */
    function verifyProof(
        bytes32[] calldata proof,
        bytes32 root,
        bytes32 leaf,
        uint256 index
    ) internal pure returns (bool) {
        bytes32 computedHash = leaf;
        uint256 currentIndex = index;
        
        for (uint256 i = 0; i < proof.length; i++) {
            bytes32 proofElement = proof[i];
            
            if (currentIndex % 2 == 0) {
                // Current node is a left child
                computedHash = keccak256(abi.encodePacked(computedHash, proofElement));
            } else {
                // Current node is a right child
                computedHash = keccak256(abi.encodePacked(proofElement, computedHash));
            }
            
            currentIndex = currentIndex / 2;
        }
        
        return computedHash == root;
    }
    
    /**
     * @dev Alternative verifyProof without index (uses sorting to determine order)
     * This maintains deterministic ordering but doesn't require tracking indices
     */
    function verifyProofNoIndex(
        bytes32[] calldata proof,
        bytes32 root,
        bytes32 leaf
    ) internal pure returns (bool) {
        bytes32 computedHash = leaf;
        
        for (uint256 i = 0; i < proof.length; i++) {
            bytes32 proofElement = proof[i];
            
            if (computedHash <= proofElement) {
                // Ensure smaller value is first for consistent ordering
                computedHash = keccak256(abi.encodePacked(computedHash, proofElement));
            } else {
                computedHash = keccak256(abi.encodePacked(proofElement, computedHash));
            }
        }
        
        return computedHash == root;
    }
}
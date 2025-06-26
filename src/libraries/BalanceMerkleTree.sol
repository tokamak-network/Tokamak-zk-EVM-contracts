// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

/**
 * @title BalanceMerkleTree
 * @dev Helper library for creating and verifying balance Merkle trees
 * This is primarily for off-chain use, but verification functions can be used on-chain
 */
library BalanceMerkleTree {
    
    /**
     * @dev Represents a balance entry in the Merkle tree
     */
    struct BalanceLeaf {
        address participant;
        address token;
        uint256 amount;
    }
    
    /**
     * @dev Computes the hash of a balance leaf
     * @param participant The participant address
     * @param token The token address (address(0) for ETH)
     * @param amount The balance amount
     * @return The leaf hash
     */
    function computeLeafHash(
        address participant,
        address token,
        uint256 amount
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(participant, token, amount));
    }
    
    /**
     * @dev Computes the hash of two nodes in the Merkle tree
     * @param left The left node hash
     * @param right The right node hash
     * @return The parent node hash
     */
    function computeNodeHash(bytes32 left, bytes32 right) internal pure returns (bytes32) {
        return left < right 
            ? keccak256(abi.encodePacked(left, right))
            : keccak256(abi.encodePacked(right, left));
    }
    
    /**
     * @dev Verifies a Merkle proof for a balance
     * @param root The Merkle root
     * @param participant The participant address
     * @param token The token address
     * @param amount The balance amount
     * @param proof The Merkle proof
     * @return Whether the proof is valid
     */
    function verifyBalance(
        bytes32 root,
        address participant,
        address token,
        uint256 amount,
        bytes32[] memory proof
    ) internal pure returns (bool) {
        bytes32 leaf = computeLeafHash(participant, token, amount);
        bytes32 computedHash = leaf;
        
        for (uint256 i = 0; i < proof.length; i++) {
            computedHash = computeNodeHash(computedHash, proof[i]);
        }
        
        return computedHash == root;
    }
    
    /**
     * @dev Computes the Merkle root from an array of balance leaves
     * Note: This is primarily for off-chain use due to gas costs
     * @param leaves Array of balance leaves
     * @return The Merkle root
     */
    function computeMerkleRoot(BalanceLeaf[] memory leaves) internal pure returns (bytes32) {
        uint256 n = leaves.length;
        if (n == 0) return bytes32(0);
        if (n == 1) return computeLeafHash(leaves[0].participant, leaves[0].token, leaves[0].amount);
        
        // Create array of leaf hashes
        bytes32[] memory nodes = new bytes32[](n);
        for (uint256 i = 0; i < n; i++) {
            nodes[i] = computeLeafHash(leaves[i].participant, leaves[i].token, leaves[i].amount);
        }
        
        // Build tree bottom-up
        while (n > 1) {
            uint256 newN = (n + 1) / 2;
            for (uint256 i = 0; i < newN; i++) {
                uint256 left = 2 * i;
                uint256 right = left + 1;
                
                if (right < n) {
                    nodes[i] = computeNodeHash(nodes[left], nodes[right]);
                } else {
                    nodes[i] = nodes[left];
                }
            }
            n = newN;
        }
        
        return nodes[0];
    }
}

/**
 * @title BalanceMerkleTreeExample
 * @dev Example contract showing how to use the BalanceMerkleTree library
 */
contract BalanceMerkleTreeExample {
    using BalanceMerkleTree for *;
    
    bytes32 public balanceRoot;
    
    /**
     * @dev Example of verifying a balance claim
     */
    function claimBalance(
        address token,
        uint256 amount,
        bytes32[] calldata proof
    ) external view returns (bool) {
        return BalanceMerkleTree.verifyBalance(
            balanceRoot,
            msg.sender,
            token,
            amount,
            proof
        );
    }
    
    /**
     * @dev Example of updating the balance root (only for demonstration)
     */
    function updateBalanceRoot(bytes32 newRoot) external {
        balanceRoot = newRoot;
    }
}
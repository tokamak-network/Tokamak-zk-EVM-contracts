// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

library MPTStorageLib {
    // ========== Storage Key Computation ==========

    /**
     * @dev Computes the storage key for a user's balance in an ERC20 contract
     * @param user The user's address
     * @param slot The storage slot number
     * @return The computed storage key
     */
    function computeStorageKey(address user, uint256 slot) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(user, slot));
    }

    /**
     * @dev Computes the storage key for a simple storage slot
     * @param slot The storage slot number
     * @return The slot as bytes32
     */
    function computeSimpleStorageKey(uint256 slot) internal pure returns (bytes32) {
        return bytes32(slot);
    }

    // ========== Storage Leaf Serialization ==========

    /**
     * @dev Serializes storage leaves in the format expected by the L2 node
     * Format: [storageKey, slot, l1Address, value]
     */
    function serializeStorageLeaf(bytes32 storageKey, uint256 slot, address l1Address, bytes32 value)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodePacked(storageKey, slot, l1Address, value);
    }

    /**
     * @dev Computes the leaf value for the Merkle tree
     * This should match the L2 node's leaf computation
     */
    function computeMerkleLeaf(address participant, uint256 tokenBalance) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(participant, tokenBalance));
    }

    // ========== RLC Computation (Placeholder) ==========

    /**
     * @dev Placeholder for Random Linear Combination computation
     * In practice, this would need to match the L2 node's RLC implementation
     */
    function computeRLC(uint256 slot, address l2Address, uint256 value, bytes32 prevRoot)
        internal
        pure
        returns (bytes32)
    {
        // Simplified version - actual implementation would use field arithmetic
        return keccak256(abi.encodePacked(slot, l2Address, value, prevRoot));
    }
}

// ========== Interface for Token Storage Reading ==========

interface IStorageReader {
    function getStorageAt(address target, bytes32 slot) external view returns (bytes32);
}

// ========== Storage Reader Implementation ==========

contract StorageReader is IStorageReader {
    /**
     * @dev Reads a storage slot from any contract
     * Note: This only works for public storage variables
     */
    function getStorageAt(address target, bytes32 slot) external view override returns (bytes32) {
        bytes32 value;
        assembly {
            // Load the value from the target contract's storage
            let ptr := mload(0x40)
            mstore(ptr, slot)
            mstore(add(ptr, 0x20), target)
            value := sload(keccak256(ptr, 0x40))
        }
        return value;
    }

    /**
     * @dev Gets ERC20 balance for a user
     * Assumes standard ERC20 storage layout (mapping at slot 0)
     */
    function getERC20Balance(address token, address user) external view returns (uint256) {
        bytes32 slot = keccak256(abi.encodePacked(user, uint256(0)));
        bytes32 value = this.getStorageAt(token, slot);
        return uint256(value);
    }

    /**
     * @dev Batch read storage slots for multiple users
     */
    function batchReadStorage(address target, address[] calldata users, uint256 slot)
        external
        view
        returns (bytes32[] memory values)
    {
        values = new bytes32[](users.length);
        for (uint256 i = 0; i < users.length; i++) {
            bytes32 storageKey = keccak256(abi.encodePacked(users[i], slot));
            values[i] = this.getStorageAt(target, storageKey);
        }
    }
}

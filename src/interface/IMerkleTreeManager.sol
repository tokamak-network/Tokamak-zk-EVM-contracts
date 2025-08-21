// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

/**
 * @title IMerkleTreeManager
 * @author Tokamak Ooo project
 * @notice Interface for Merkle tree manager contracts - Unified incremental merkle tree for tracking user balances with RLC
 * @dev This interface defines the contract for managing Merkle trees that track user balances using
 *      RLC (Random Linear Combination) for security. The interface is designed to work with both
 *      binary and quaternary Merkle tree implementations, providing flexibility in tree structure
 *      while maintaining consistent functionality for balance tracking and proof verification.
 */
interface IMerkleTreeManager {
    // ============ Structs ============

    /**
     * @dev User data structure
     * @param l1Address Layer 1 address of the user
     * @param l2Address Layer 2 address of the user
     * @param balance User's balance
     */
    struct UserData {
        address l1Address;
        address l2Address;
        uint256 balance;
    }

    // ============ Write Functions ============

    /**
     * @dev set the bridge address
     * @param _bridge bridge address
     */
    function setBridge(address _bridge) external;

    /**
     * @dev initialize the channel
     * @param channelId channelId
     */
    function initializeChannel(uint256 channelId) external;

    /**
     * @dev Set L1 to L2 address mapping
     * @param channelId channelId
     * @param l1Address The L1 address
     * @param l2Address The corresponding L2 address
     */
    function setAddressPair(uint256 channelId, address l1Address, address l2Address) external;

    /**
     * @dev Add all users with their initial balances
     * @param l1Addresses Array of L1 addresses
     * @param balances Array of corresponding balances
     */
    function addUsers(uint256 channelId, address[] calldata l1Addresses, uint256[] calldata balances) external;

    // ============ View Functions ============

    /**
     * @dev Hash two nodes together using the appropriate hasher
     * @param _left The left node
     * @param _right The right node
     * @return The hash of the two nodes
     * @dev For binary trees, this uses Poseidon2. For quaternary trees, this
     *      typically uses Poseidon4Yul with the two inputs plus two zero values.
     */
    function hashLeftRight(bytes32 _left, bytes32 _right) external view returns (bytes32);

    /**
     * @dev Verify a merkle proof
     * @param proof Array of proof elements
     * @param leaf The leaf to verify
     * @param leafIndex The index of the leaf
     * @param root The root to verify against
     * @return True if the proof is valid
     */
    function verifyProof(uint256 channelId, bytes32[] calldata proof, bytes32 leaf, uint256 leafIndex, bytes32 root)
        external
        view
        returns (bool);

    /**
     * @dev Compute leaf value for verification
     * @param l2Address The L2 address
     * @param balance The balance
     * @param prevRoot The previous root used in RLC calculation
     * @return The computed leaf value
     */
    function computeLeafForVerification(address l2Address, uint256 balance, bytes32 prevRoot)
        external
        view
        returns (bytes32);

    /**
     * @dev Check if a root exists in history
     * @param _root The root to check
     * @return True if the root exists in history
     */
    function isKnownRoot(uint256 channelId, bytes32 _root) external view returns (bool);

    /**
     * @dev Get the latest root
     * @return The latest merkle tree root
     */
    function getLatestRoot(uint256 channelId) external view returns (bytes32);

    /**
     * @dev Get user balance for an L1 address
     * @param l1Address The L1 address to query
     * @return The user's balance
     */
    function getBalance(uint256 channelId, address l1Address) external view returns (uint256);

    /**
     * @dev Get L2 address for an L1 address
     * @param channelId channelId
     * @param l1Address The L1 address to query
     * @return The corresponding L2 address
     */
    function getL2Address(uint256 channelId, address l1Address) external view returns (address);

    /**
     * @dev Get the last root in sequence
     * @return The last root in the root sequence
     */
    function getLastRootInSequence(uint256 channelId) external view returns (bytes32);

    /**
     * @dev Get all roots in sequence (for debugging)
     * @return Array of all roots in sequence
     */
    function getRootSequence(uint256 channelId) external view returns (bytes32[] memory);

    /**
     * @dev Get all user addresses in order
     * @return l1Addresses Array of L1 addresses
     * @return l2Addresses Array of corresponding L2 addresses
     */
    function getUserAddresses(uint256 channelId)
        external
        view
        returns (address[] memory l1Addresses, address[] memory l2Addresses);

    /**
     * @dev Get current root (alias for getLatestRoot)
     * @return The current merkle tree root
     */
    function getCurrentRoot(uint256 channelId) external view returns (bytes32);

    /**
     * @dev Get the length of root sequence
     * @return The number of roots in the sequence
     */
    function getRootSequenceLength(uint256 channelId) external view returns (uint256);

    /**
     * @dev Get zero subtree root at given depth
     * @param i The depth level
     * @return The precomputed zero value at that depth
     */
    function zeros(uint256 i) external pure returns (bytes32);
}

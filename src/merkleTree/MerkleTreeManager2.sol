// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IMerkleTreeManager} from "../interface/IMerkleTreeManager.sol";
import "@openzeppelin/access/Ownable.sol";

/**
 * @title MerkleTreeManager
 * @dev Multi-channel incremental merkle tree for tracking user balances with RLC
 * Each channel maintains its own independent merkle tree and state
 */
contract MerkleTreeManager is IMerkleTreeManager, Ownable {
    // Constants
    uint256 public constant BALANCE_SLOT = 0;
    uint32 public constant ROOT_HISTORY_SIZE = 30;

    address public bridge;
    bool public bridgeSet;

    modifier onlyBridge() {
        require(msg.sender == bridge, "Only bridge can call");
        _;
    }

    // Immutable configuration
    uint32 public immutable depth;

    // Tree storage - per channel
    mapping(uint256 => mapping(uint256 => bytes32)) public cachedSubtrees; // channelId => index => subtree
    mapping(uint256 => mapping(uint256 => bytes32)) public roots; // channelId => rootIndex => root
    mapping(uint256 => uint32) public currentRootIndex; // channelId => currentRootIndex
    mapping(uint256 => uint32) public nextLeafIndex; // channelId => nextLeafIndex

    // User data storage - per channel
    mapping(uint256 => UserData[]) private channelUsers; // channelId => users array
    mapping(uint256 => mapping(address => uint256)) public userIndex; // channelId => l1Address => index
    mapping(uint256 => mapping(address => address)) public l1ToL2; // channelId => l1Address => l2Address

    // State tracking - per channel
    mapping(uint256 => bytes32[]) private channelRootSequence; // channelId => rootSequence
    mapping(uint256 => uint256) public nonce; // channelId => nonce
    mapping(uint256 => bool) public channelInitialized; // channelId => initialized

    // Errors
    error LeftValueOutOfRange(bytes32 left);
    error RightValueOutOfRange(bytes32 right);
    error DepthTooSmall(uint32 depth);
    error DepthTooLarge(uint32 depth);
    error MerkleTreeFull(uint32 nextIndex);
    error IndexOutOfBounds(uint256 index);
    error ChannelAlreadyInitialized(uint256 channelId);
    error ChannelNotInitialized(uint256 channelId);
    error UsersAlreadyAdded(uint256 channelId);
    error L2AddressNotSet();
    error LengthMismatch();
    error NoRoots();
    error NoLeaves();

    // Events
    event BridgeSet(address indexed bridge);
    event ChannelInitialized(uint256 indexed channelId, bytes32 initialRoot);
    event UsersAdded(uint256 indexed channelId, uint256 count, bytes32 newRoot);
    event LeafInserted(uint256 indexed channelId, uint32 leafIndex, bytes32 leaf, bytes32 newRoot);

    constructor(uint32 _depth) Ownable(msg.sender) {
        if (_depth == 0) revert DepthTooSmall(_depth);
        if (_depth >= 32) revert DepthTooLarge(_depth);

        depth = _depth;
    }

    /**
     * @dev Set the bridge address (can only be called once by owner)
     * Call this after deploying the Bridge contract
     */
    function setBridge(address _bridge) external onlyOwner {
        require(!bridgeSet, "Bridge already set");
        require(_bridge != address(0), "Invalid bridge address");

        bridge = _bridge;
        bridgeSet = true;

        emit BridgeSet(_bridge);
    }

    /**
     * @dev Initialize a new channel
     */
    function initializeChannel(uint256 channelId) external onlyBridge {
        if (channelInitialized[channelId]) revert ChannelAlreadyInitialized(channelId);

        // Initialize with zero tree
        roots[channelId][0] = zeros(depth);

        // First root in sequence is the slot number (0)
        channelRootSequence[channelId].push(bytes32(BALANCE_SLOT));

        channelInitialized[channelId] = true;

        emit ChannelInitialized(channelId, bytes32(BALANCE_SLOT));
    }

    /**
     * @dev Set L1 to L2 address mapping for a channel
     */
    function setAddressPair(uint256 channelId, address l1Address, address l2Address) external onlyBridge {
        if (!channelInitialized[channelId]) revert ChannelNotInitialized(channelId);
        l1ToL2[channelId][l1Address] = l2Address;
    }

    /**
     * @dev Add all users with their initial balances to a specific channel
     */
    function addUsers(uint256 channelId, address[] calldata l1Addresses, uint256[] calldata balances)
        external
        onlyBridge
    {
        if (!channelInitialized[channelId]) revert ChannelNotInitialized(channelId);
        if (l1Addresses.length != balances.length) revert LengthMismatch();
        if (channelUsers[channelId].length != 0) revert UsersAlreadyAdded(channelId);

        // Add each user
        for (uint256 i = 0; i < l1Addresses.length; i++) {
            address l1Addr = l1Addresses[i];
            address l2Addr = l1ToL2[channelId][l1Addr];
            if (l2Addr == address(0)) revert L2AddressNotSet();

            // Compute RLC leaf using current state of rootSequence for this channel
            bytes32 leaf = _computeLeaf(channelId, uint256(uint160(l2Addr)), balances[i]);

            // Insert into tree and get new root
            (uint32 leafIndex, bytes32 newRoot) = _insertAndGetRoot(channelId, leaf);

            // Update rootSequence immediately after each insertion
            channelRootSequence[channelId].push(newRoot);
            nonce[channelId]++;

            // Store user data
            channelUsers[channelId].push(UserData({l1Address: l1Addr, l2Address: l2Addr, balance: balances[i]}));
            userIndex[channelId][l1Addr] = i;

            emit LeafInserted(channelId, leafIndex, leaf, newRoot);
        }

        emit UsersAdded(channelId, l1Addresses.length, getLatestRoot(channelId));
    }

    /**
     * @dev Insert a leaf into the tree and return both index and new root
     */
    function _insertAndGetRoot(uint256 channelId, bytes32 _leaf) internal returns (uint32 index, bytes32 newRoot) {
        uint32 _nextLeafIndex = nextLeafIndex[channelId];
        if (_nextLeafIndex >= uint32(2) ** depth) {
            revert MerkleTreeFull(_nextLeafIndex);
        }

        uint32 currentIndex = _nextLeafIndex;
        bytes32 currentHash = _leaf;
        bytes32 left;
        bytes32 right;

        for (uint32 i = 0; i < depth; i++) {
            if (currentIndex % 2 == 0) {
                left = currentHash;
                right = zeros(i);
                cachedSubtrees[channelId][i] = currentHash;
            } else {
                left = cachedSubtrees[channelId][i];
                right = currentHash;
            }
            currentHash = hashLeftRight(left, right);
            currentIndex /= 2;
        }

        uint32 newRootIndex = (currentRootIndex[channelId] + 1) % ROOT_HISTORY_SIZE;
        currentRootIndex[channelId] = newRootIndex;
        roots[channelId][newRootIndex] = currentHash;
        nextLeafIndex[channelId] = _nextLeafIndex + 1;

        return (_nextLeafIndex, currentHash);
    }

    /**
     * @dev Hash two nodes together using keccak256
     */
    function hashLeftRight(bytes32 _left, bytes32 _right) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(_left, _right));
    }

    /**
     * @dev Compute RLC leaf value for a specific channel using keccak256
     */
    function _computeLeaf(uint256 channelId, uint256 l2Addr, uint256 balance) private view returns (bytes32) {
        bytes32[] storage rootSequence = channelRootSequence[channelId];

        // Use the most recent root in the sequence
        uint256 prevRoot = (rootSequence.length == 0) ? BALANCE_SLOT : uint256(rootSequence[rootSequence.length - 1]);

        // Compute gamma = keccak256(prevRoot, l2Addr)
        bytes32 gamma = keccak256(abi.encodePacked(bytes32(prevRoot), bytes32(l2Addr)));

        // Compute RLC: l2Addr + uint256(gamma) * balance (mod 2^256)
        uint256 rlc = addmod(l2Addr, mulmod(uint256(gamma), balance, type(uint256).max), type(uint256).max);

        return bytes32(rlc);
    }

    /**
     * @dev Verify a merkle proof for a specific channel
     */
    function verifyProof(uint256 channelId, bytes32[] calldata proof, bytes32 leaf, uint256 leafIndex, bytes32 root)
        external
        view
        returns (bool)
    {
        if (!channelInitialized[channelId]) revert ChannelNotInitialized(channelId);

        bytes32 computedHash = leaf;
        uint256 index = leafIndex;

        for (uint256 i = 0; i < proof.length; i++) {
            if (index % 2 == 0) {
                computedHash = hashLeftRight(computedHash, proof[i]);
            } else {
                computedHash = hashLeftRight(proof[i], computedHash);
            }
            index = index / 2;
        }

        return computedHash == root;
    }

    /**
     * @dev Compute leaf value for verification using keccak256
     */
    function computeLeafForVerification(address l2Address, uint256 balance, bytes32 prevRoot)
        external
        pure
        returns (bytes32)
    {
        uint256 l2Addr = uint256(uint160(l2Address));

        // Compute gamma using keccak256
        bytes32 gamma = keccak256(abi.encodePacked(prevRoot, bytes32(l2Addr)));

        // Compute RLC
        uint256 rlc = addmod(l2Addr, mulmod(uint256(gamma), balance, type(uint256).max), type(uint256).max);

        return bytes32(rlc);
    }

    /**
     * @dev Check if a root exists in history for a specific channel
     */
    function isKnownRoot(uint256 channelId, bytes32 _root) public view returns (bool) {
        if (!channelInitialized[channelId]) revert ChannelNotInitialized(channelId);
        if (_root == bytes32(0)) return false;

        uint32 _currentRootIndex = currentRootIndex[channelId];
        uint32 i = _currentRootIndex;

        do {
            if (_root == roots[channelId][i]) return true;
            if (i == 0) {
                i = ROOT_HISTORY_SIZE;
            }
            i--;
        } while (i != _currentRootIndex);

        return false;
    }

    /**
     * @dev Get the latest root for a specific channel
     */
    function getLatestRoot(uint256 channelId) public view returns (bytes32) {
        if (!channelInitialized[channelId]) revert ChannelNotInitialized(channelId);
        return roots[channelId][currentRootIndex[channelId]];
    }

    /**
     * @dev Get user balance for a specific channel
     */
    function getBalance(uint256 channelId, address l1Address) external view returns (uint256) {
        if (!channelInitialized[channelId]) revert ChannelNotInitialized(channelId);

        uint256 idx = userIndex[channelId][l1Address];
        UserData[] storage users = channelUsers[channelId];

        if (idx >= users.length || users[idx].l1Address != l1Address) {
            return 0;
        }
        return users[idx].balance;
    }

    /**
     * @dev Get L2 address for an L1 address in a specific channel
     */
    function getL2Address(uint256 channelId, address l1Address) external view returns (address) {
        return l1ToL2[channelId][l1Address];
    }

    /**
     * @dev Get the last root in sequence for a specific channel
     */
    function getLastRootInSequence(uint256 channelId) external view returns (bytes32) {
        if (!channelInitialized[channelId]) revert ChannelNotInitialized(channelId);

        bytes32[] storage rootSequence = channelRootSequence[channelId];
        if (rootSequence.length == 0) revert NoRoots();
        return rootSequence[rootSequence.length - 1];
    }

    /**
     * @dev Get all roots for a specific channel (for debugging)
     */
    function getRootSequence(uint256 channelId) external view returns (bytes32[] memory) {
        if (!channelInitialized[channelId]) revert ChannelNotInitialized(channelId);
        return channelRootSequence[channelId];
    }

    /**
     * @dev Get user addresses in order for a specific channel
     */
    function getUserAddresses(uint256 channelId)
        external
        view
        returns (address[] memory l1Addresses, address[] memory l2Addresses)
    {
        if (!channelInitialized[channelId]) revert ChannelNotInitialized(channelId);

        UserData[] storage users = channelUsers[channelId];
        l1Addresses = new address[](users.length);
        l2Addresses = new address[](users.length);

        for (uint256 i = 0; i < users.length; i++) {
            l1Addresses[i] = users[i].l1Address;
            l2Addresses[i] = users[i].l2Address;
        }
    }

    /**
     * @dev Get current root for a specific channel (alias for getLatestRoot)
     */
    function getCurrentRoot(uint256 channelId) external view returns (bytes32) {
        return getLatestRoot(channelId);
    }

    /**
     * @dev Get root at specific index in sequence for a specific channel
     */
    function getRootAtIndex(uint256 channelId, uint256 index) external view returns (bytes32) {
        if (!channelInitialized[channelId]) revert ChannelNotInitialized(channelId);

        bytes32[] storage rootSequence = channelRootSequence[channelId];
        require(index < rootSequence.length, "Index out of bounds");
        return rootSequence[index];
    }

    /**
     * @dev Get the length of root sequence for a specific channel
     */
    function getRootSequenceLength(uint256 channelId) external view returns (uint256) {
        if (!channelInitialized[channelId]) revert ChannelNotInitialized(channelId);
        return channelRootSequence[channelId].length;
    }

    /**
     * @dev Get zero subtree root at given depth using keccak256
     */
    function zeros(uint256 i) public pure returns (bytes32) {
        if (i == 0) return bytes32(0);

        // Compute zero hash for depth i by hashing two zero hashes from depth i-1
        bytes32 prevZero = zeros(i - 1);
        return keccak256(abi.encodePacked(prevZero, prevZero));
    }
}

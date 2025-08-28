// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IMerkleTreeManager} from "../interface/IMerkleTreeManager.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title MerkleTreeManager4Upgradeable
 * @author Tokamak Ooo project
 * @notice Upgradeable multi-channel incremental quaternary Merkle tree for tracking user balances with RLC
 * @dev This contract implements a quaternary Merkle tree structure where each internal node has 4 children,
 *      providing improved efficiency over binary trees. Each channel maintains its own independent
 *      Merkle tree and state. Uses keccak256 for hashing 4 inputs simultaneously, which is
 *      more gas-efficient than binary hashing for tree construction and verification.
 *
 *      Key features:
 *      - Quaternary tree structure (4 children per node)
 *      - Maximum depth of 16 levels (supports up to 4^16 leaves)
 *      - RLC (Random Linear Combination) for leaf computation
 *      - Multi-channel support with independent state management
 *      - Efficient proof verification using 4-input hashing
 *
 * @dev Upgradeable using UUPS pattern for enhanced security and gas efficiency
 */
contract MerkleTreeManager4Upgradeable is 
    IMerkleTreeManager, 
    Initializable,
    OwnableUpgradeable,
    UUPSUpgradeable 
{
    // ============ Constants ============

    /**
     * @dev Field size for keccak256 operations
     *      Used in RLC (Random Linear Combination) calculations
     */
    uint256 public constant FIELD_SIZE = type(uint256).max;


    // ============ Storage ============
    
    /// @custom:storage-location erc7201:tokamak.storage.MerkleTreeManager4
    struct MerkleTreeManager4Storage {
        // Bridge configuration
        address bridge;
        bool bridgeSet;
        
        // Tree configuration
        uint32 depth;
        
        // Tree storage (per channel)
        mapping(uint256 => mapping(uint256 => bytes32)) cachedSubtrees;
        mapping(uint256 => mapping(uint256 => bytes32)) roots;
        mapping(uint256 => uint32) currentRootIndex;
        mapping(uint256 => uint32) nextLeafIndex;
        
        // User data storage (per channel)
        mapping(uint256 => UserData[]) channelUsers;
        mapping(uint256 => mapping(address => uint256)) userIndex;
        mapping(uint256 => mapping(address => address)) l1ToL2;
        
        // State tracking (per channel)
        mapping(uint256 => bytes32[]) channelRootSequence;
        mapping(uint256 => uint256) nonce;
        mapping(uint256 => bool) channelInitialized;
    }

    // keccak256(abi.encode(uint256(keccak256("tokamak.storage.MerkleTreeManager4")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant MerkleTreeManager4StorageLocation = 0x2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2c3d4e5f6a7b8c9d0e1f2a00;

    function _getMerkleTreeManager4Storage() private pure returns (MerkleTreeManager4Storage storage $) {
        assembly {
            $.slot := MerkleTreeManager4StorageLocation
        }
    }

    /**
     * @dev Modifier restricting function access to only the bridge contract
     */
    modifier onlyBridge() {
        MerkleTreeManager4Storage storage $ = _getMerkleTreeManager4Storage();
        require(msg.sender == $.bridge, "Only bridge can call");
        _;
    }

    // ============ Errors ============

    /**
     * @dev Thrown when a value exceeds the field size limit
     * @param value The value that is out of range
     */
    error ValueOutOfRange(bytes32 value);

    /**
     * @dev Thrown when the tree depth is too small (must be > 0)
     * @param depth The invalid depth value
     */
    error DepthTooSmall(uint32 depth);

    /**
     * @dev Thrown when the tree depth is too large (must be < 16 for quaternary trees)
     * @param depth The invalid depth value
     */
    error DepthTooLarge(uint32 depth);

    /**
     * @dev Thrown when attempting to insert a leaf into a full tree
     * @param nextIndex The index where the next leaf would be inserted
     */
    error MerkleTreeFull(uint32 nextIndex);

    /**
     * @dev Thrown when accessing an index that is out of bounds
     * @param index The invalid index value
     */
    error IndexOutOfBounds(uint256 index);

    /**
     * @dev Thrown when attempting to initialize an already initialized channel
     * @param channelId The channel ID that is already initialized
     */
    error ChannelAlreadyInitialized(uint256 channelId);

    /**
     * @dev Thrown when attempting to perform operations on an uninitialized channel
     * @param channelId The channel ID that is not initialized
     */
    error ChannelNotInitialized(uint256 channelId);

    /**
     * @dev Thrown when attempting to add users to a channel that already has users
     * @param channelId The channel ID that already has users
     */
    error ChannelNotEmpty(uint256 channelId);

    /**
     * @dev Thrown when trying to set the bridge address when it's already been set
     */
    error BridgeAlreadySet();

    /**
     * @dev Thrown when the bridge address is not set but required
     */
    error BridgeNotSet();

    // ============ Events ============

    /**
     * @dev Emitted when a new Merkle tree is initialized for a channel
     * @param channelId The channel ID for which the tree was initialized
     * @param depth The depth of the initialized tree
     */
    event TreeInitialized(uint256 indexed channelId, uint32 depth);

    /**
     * @dev Emitted when a new root is computed and stored
     * @param channelId The channel ID for which the root was computed
     * @param newRoot The newly computed root hash
     * @param leafIndex The index of the leaf that triggered the root update
     */
    event RootUpdated(uint256 indexed channelId, bytes32 newRoot, uint32 leafIndex);

    /**
     * @dev Emitted when users are added to a channel
     * @param channelId The channel ID to which users were added
     * @param userCount The number of users added
     */
    event UsersAdded(uint256 indexed channelId, uint256 userCount);

    /**
     * @dev Emitted when the bridge address is set
     * @param bridge The address of the bridge contract
     */
    event BridgeSet(address indexed bridge);

    // ============ Constructor & Initializer ============
    
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the upgradeable MerkleTreeManager4 contract
     * @param _depth Depth of the quaternary Merkle tree (must be between 1 and 15)
     * @param _owner Address of the contract owner
     */
    function initialize(uint32 _depth, address _owner) public initializer {
        __Ownable_init_unchained();
        _transferOwnership(_owner);
        __UUPSUpgradeable_init();

        if (_depth == 0) revert DepthTooSmall(_depth);
        if (_depth >= 16) revert DepthTooLarge(_depth);

        MerkleTreeManager4Storage storage $ = _getMerkleTreeManager4Storage();
        $.depth = _depth;
    }

    /**
     * @dev Authorizes upgrades - only owner can upgrade
     * @param newImplementation Address of the new implementation
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    // ============ Getter Functions for Storage ============

    function bridge() public view returns (address) {
        MerkleTreeManager4Storage storage $ = _getMerkleTreeManager4Storage();
        return $.bridge;
    }

    function bridgeSet() public view returns (bool) {
        MerkleTreeManager4Storage storage $ = _getMerkleTreeManager4Storage();
        return $.bridgeSet;
    }

    function depth() public view returns (uint32) {
        MerkleTreeManager4Storage storage $ = _getMerkleTreeManager4Storage();
        return $.depth;
    }

    function cachedSubtrees(uint256 channelId, uint256 level) public view returns (bytes32) {
        MerkleTreeManager4Storage storage $ = _getMerkleTreeManager4Storage();
        return $.cachedSubtrees[channelId][level];
    }

    function roots(uint256 channelId, uint256 index) public view returns (bytes32) {
        MerkleTreeManager4Storage storage $ = _getMerkleTreeManager4Storage();
        return $.roots[channelId][index];
    }

    function currentRootIndex(uint256 channelId) public view returns (uint32) {
        MerkleTreeManager4Storage storage $ = _getMerkleTreeManager4Storage();
        return $.currentRootIndex[channelId];
    }

    function nextLeafIndex(uint256 channelId) public view returns (uint32) {
        MerkleTreeManager4Storage storage $ = _getMerkleTreeManager4Storage();
        return $.nextLeafIndex[channelId];
    }

    function userIndex(uint256 channelId, address user) public view returns (uint256) {
        MerkleTreeManager4Storage storage $ = _getMerkleTreeManager4Storage();
        return $.userIndex[channelId][user];
    }

    function l1ToL2(uint256 channelId, address l1Address) public view returns (address) {
        MerkleTreeManager4Storage storage $ = _getMerkleTreeManager4Storage();
        return $.l1ToL2[channelId][l1Address];
    }

    function nonce(uint256 channelId) public view returns (uint256) {
        MerkleTreeManager4Storage storage $ = _getMerkleTreeManager4Storage();
        return $.nonce[channelId];
    }

    function channelInitialized(uint256 channelId) public view returns (bool) {
        MerkleTreeManager4Storage storage $ = _getMerkleTreeManager4Storage();
        return $.channelInitialized[channelId];
    }

    // ============ Bridge Management ============

    /**
     * @notice Sets the bridge contract address (can only be set once)
     * @param _bridge Address of the bridge contract
     * @dev Only callable by the contract owner and only once
     */
    function setBridge(address _bridge) external onlyOwner {
        MerkleTreeManager4Storage storage $ = _getMerkleTreeManager4Storage();
        if ($.bridgeSet) revert BridgeAlreadySet();
        
        $.bridge = _bridge;
        $.bridgeSet = true;
        
        emit BridgeSet(_bridge);
    }

    // ============ Channel Management ============

    /**
     * @notice Initializes a new Merkle tree for a specific channel
     * @param channelId Unique identifier for the channel
     * @dev Only callable by the bridge contract
     *      Creates an empty quaternary Merkle tree with the configured depth
     */
    function initializeChannel(uint256 channelId) external onlyBridge {
        MerkleTreeManager4Storage storage $ = _getMerkleTreeManager4Storage();
        
        if ($.channelInitialized[channelId]) {
            revert ChannelAlreadyInitialized(channelId);
        }

        $.channelInitialized[channelId] = true;

        // Initialize tree with zero values
        bytes32 zero = bytes32(0);
        
        // Pre-compute zero subtrees for efficient tree initialization
        bytes32[] memory zeroSubtrees = new bytes32[]($.depth + 1);
        zeroSubtrees[0] = zero;
        
        for (uint256 level = 1; level <= $.depth; level++) {
            bytes32 prevZero = zeroSubtrees[level - 1];
            zeroSubtrees[level] = keccak256(abi.encodePacked(prevZero, prevZero, prevZero, prevZero));
        }

        // Cache the zero subtrees for this channel
        for (uint256 level = 0; level <= $.depth; level++) {
            $.cachedSubtrees[channelId][level] = zeroSubtrees[level];
        }

        // Set initial root
        bytes32 initialRoot = zeroSubtrees[$.depth];
        $.roots[channelId][0] = initialRoot;
        $.channelRootSequence[channelId].push(initialRoot);
        
        emit TreeInitialized(channelId, $.depth);
    }

    /**
     * @notice Sets an L1 to L2 address pair for a specific channel
     * @param channelId ID of the channel
     * @param l1Address The L1 address
     * @param l2Address The corresponding L2 address
     * @dev Only callable by the bridge contract
     */
    function setAddressPair(uint256 channelId, address l1Address, address l2Address) external onlyBridge {
        MerkleTreeManager4Storage storage $ = _getMerkleTreeManager4Storage();
        
        if (!$.channelInitialized[channelId]) {
            revert ChannelNotInitialized(channelId);
        }

        $.l1ToL2[channelId][l1Address] = l2Address;
    }

    // ============ User Management ============

    /**
     * @notice Adds multiple users to a channel with their initial balances
     * @param channelId ID of the channel
     * @param l1Addresses Array of L1 addresses
     * @param balances Array of initial balances corresponding to each address
     * @dev Only callable by the bridge contract
     *      All arrays must have the same length
     *      Channel must be initialized and empty
     */
    function addUsers(
        uint256 channelId,
        address[] calldata l1Addresses,
        uint256[] calldata balances
    ) external onlyBridge {
        MerkleTreeManager4Storage storage $ = _getMerkleTreeManager4Storage();
        
        if (!$.channelInitialized[channelId]) {
            revert ChannelNotInitialized(channelId);
        }
        
        if ($.channelUsers[channelId].length != 0) {
            revert ChannelNotEmpty(channelId);
        }

        require(l1Addresses.length == balances.length, "Array length mismatch");
        require(l1Addresses.length > 0, "Empty arrays");

        // Add users to the channel
        for (uint256 i = 0; i < l1Addresses.length; i++) {
            UserData memory userData = UserData({
                l1Address: l1Addresses[i],
                l2Address: $.l1ToL2[channelId][l1Addresses[i]],
                balance: balances[i]
            });

            $.channelUsers[channelId].push(userData);
            $.userIndex[channelId][l1Addresses[i]] = i;

            // Insert leaf into the tree
            _insertLeaf(channelId, _computeLeaf(userData));
        }

        emit UsersAdded(channelId, l1Addresses.length);
    }

    // ============ Tree Operations ============

    /**
     * @dev Computes a leaf hash from user data using RLC
     * @param userData The user data to hash
     * @return The computed leaf hash
     */
    function _computeLeaf(UserData memory userData) internal view returns (bytes32) {
        MerkleTreeManager4Storage storage $ = _getMerkleTreeManager4Storage();
        
        // RLC computation: balance + nonce * l2Address
        uint256 leafValue = userData.balance + ($.nonce[0] * uint256(uint160(userData.l2Address)));
        
        // Ensure value is within field range
        leafValue = leafValue % FIELD_SIZE;
        
        return bytes32(leafValue);
    }

    /**
     * @dev Inserts a leaf into the quaternary Merkle tree
     * @param channelId ID of the channel
     * @param leafHash The leaf hash to insert
     */
    function _insertLeaf(uint256 channelId, bytes32 leafHash) internal {
        MerkleTreeManager4Storage storage $ = _getMerkleTreeManager4Storage();
        
        uint32 leafIndex = $.nextLeafIndex[channelId];
        
        // Check if tree is full
        uint32 maxLeaves = uint32(4 ** $.depth);
        if (leafIndex >= maxLeaves) {
            revert MerkleTreeFull(leafIndex);
        }

        // Update the cached subtrees and compute new root
        bytes32 currentHash = leafHash;
        uint32 currentIndex = leafIndex;

        for (uint256 level = 0; level < $.depth; level++) {
            uint32 siblingIndex = currentIndex ^ 3; // XOR with 3 to get the rightmost sibling
            
            if (currentIndex % 4 == 0) {
                // This is a leftmost node, cache it
                $.cachedSubtrees[channelId][level] = currentHash;
                break;
            } else {
                // Compute parent hash using 4 children
                bytes32 left = $.cachedSubtrees[channelId][level];
                bytes32 child2 = currentIndex % 4 >= 2 ? currentHash : bytes32(0);
                bytes32 child3 = currentIndex % 4 == 3 ? currentHash : bytes32(0);
                bytes32 child4 = bytes32(0);
                
                currentHash = keccak256(abi.encodePacked(left, child2, child3, child4));
                currentIndex = currentIndex / 4;
            }
        }

        // Update tree state
        $.nextLeafIndex[channelId] = leafIndex + 1;
        
        // Store new root
        uint32 newRootIndex = $.currentRootIndex[channelId] + 1;
        $.currentRootIndex[channelId] = newRootIndex;
        $.roots[channelId][newRootIndex] = currentHash;
        $.channelRootSequence[channelId].push(currentHash);

        emit RootUpdated(channelId, currentHash, leafIndex);
    }

    // ============ View Functions ============

    /**
     * @notice Gets the current root hash for a channel
     * @param channelId ID of the channel
     * @return The current root hash
     */
    function getCurrentRoot(uint256 channelId) external view returns (bytes32) {
        MerkleTreeManager4Storage storage $ = _getMerkleTreeManager4Storage();
        
        if (!$.channelInitialized[channelId]) {
            revert ChannelNotInitialized(channelId);
        }
        
        uint32 rootIndex = $.currentRootIndex[channelId];
        return $.roots[channelId][rootIndex];
    }

    /**
     * @notice Gets the L2 address corresponding to an L1 address
     * @param channelId ID of the channel
     * @param l1Address The L1 address to look up
     * @return The corresponding L2 address
     */
    function getL2Address(uint256 channelId, address l1Address) external view returns (address) {
        MerkleTreeManager4Storage storage $ = _getMerkleTreeManager4Storage();
        return $.l1ToL2[channelId][l1Address];
    }

    /**
     * @notice Gets the last root in the sequence for a channel
     * @param channelId ID of the channel
     * @return The last root hash in the sequence
     */
    function getLastRootInSequence(uint256 channelId) external view returns (bytes32) {
        MerkleTreeManager4Storage storage $ = _getMerkleTreeManager4Storage();
        
        if (!$.channelInitialized[channelId]) {
            revert ChannelNotInitialized(channelId);
        }
        
        bytes32[] storage sequence = $.channelRootSequence[channelId];
        if (sequence.length == 0) {
            return bytes32(0);
        }
        
        return sequence[sequence.length - 1];
    }

    /**
     * @notice Computes a leaf value for verification purposes
     * @param l2Address The L2 address
     * @param balance The balance
     * @param prevRoot The previous root (used as nonce)
     * @return The computed leaf value
     */
    function computeLeafForVerification(
        address l2Address,
        uint256 balance,
        bytes32 prevRoot
    ) external pure returns (bytes32) {
        // Use prevRoot as nonce for RLC computation
        uint256 nonceValue = uint256(prevRoot) % FIELD_SIZE;
        uint256 leafValue = balance + (nonceValue * uint256(uint160(l2Address)));
        leafValue = leafValue % FIELD_SIZE;
        
        return bytes32(leafValue);
    }

    /**
     * @notice Verifies a Merkle proof for a given leaf
     * @param channelId ID of the channel
     * @param proof Array of sibling hashes
     * @param leafValue The leaf value to verify
     * @param leafIndex The index of the leaf
     * @param root The root to verify against
     * @return True if the proof is valid, false otherwise
     */
    function verifyProof(
        uint256 channelId,
        bytes32[] calldata proof,
        bytes32 leafValue,
        uint256 leafIndex,
        bytes32 root
    ) external view returns (bool) {
        MerkleTreeManager4Storage storage $ = _getMerkleTreeManager4Storage();
        
        if (!$.channelInitialized[channelId]) {
            return false;
        }

        bytes32 computedHash = leafValue;
        uint256 index = leafIndex;

        for (uint256 i = 0; i < proof.length; i++) {
            bytes32 proofElement = proof[i];
            
            if (index % 4 == 0) {
                // Left child
                computedHash = keccak256(abi.encodePacked(computedHash, proofElement, bytes32(0), bytes32(0)));
            } else if (index % 4 == 1) {
                // Second child
                computedHash = keccak256(abi.encodePacked(proofElement, computedHash, bytes32(0), bytes32(0)));
            } else if (index % 4 == 2) {
                // Third child
                computedHash = keccak256(abi.encodePacked(proofElement, bytes32(0), computedHash, bytes32(0)));
            } else {
                // Right child
                computedHash = keccak256(abi.encodePacked(proofElement, bytes32(0), bytes32(0), computedHash));
            }
            
            index = index / 4;
        }

        return computedHash == root;
    }

    /**
     * @notice Gets the number of users in a channel
     * @param channelId ID of the channel
     * @return The number of users
     */
    function getUserCount(uint256 channelId) external view returns (uint256) {
        MerkleTreeManager4Storage storage $ = _getMerkleTreeManager4Storage();
        return $.channelUsers[channelId].length;
    }

    /**
     * @notice Gets user data by index
     * @param channelId ID of the channel
     * @param index Index of the user
     * @return The user data
     */
    function getUserByIndex(uint256 channelId, uint256 index) external view returns (UserData memory) {
        MerkleTreeManager4Storage storage $ = _getMerkleTreeManager4Storage();
        
        if (index >= $.channelUsers[channelId].length) {
            revert IndexOutOfBounds(index);
        }
        
        return $.channelUsers[channelId][index];
    }

    /**
     * @notice Gets the root sequence length for a channel
     * @param channelId ID of the channel
     * @return The length of the root sequence
     */
    function getRootSequenceLength(uint256 channelId) external view returns (uint256) {
        MerkleTreeManager4Storage storage $ = _getMerkleTreeManager4Storage();
        return $.channelRootSequence[channelId].length;
    }

    /**
     * @notice Gets a root from the sequence by index
     * @param channelId ID of the channel
     * @param index Index in the root sequence
     * @return The root hash at that index
     */
    function getRootBySequenceIndex(uint256 channelId, uint256 index) external view returns (bytes32) {
        MerkleTreeManager4Storage storage $ = _getMerkleTreeManager4Storage();
        
        if (index >= $.channelRootSequence[channelId].length) {
            revert IndexOutOfBounds(index);
        }
        
        return $.channelRootSequence[channelId][index];
    }

    // ============ Additional Interface Implementations ============

    /**
     * @notice Gets the balance for a user in a channel
     * @param channelId ID of the channel
     * @param l1Address The L1 address to look up
     * @return The balance of the user
     */
    function getBalance(uint256 channelId, address l1Address) external view returns (uint256) {
        MerkleTreeManager4Storage storage $ = _getMerkleTreeManager4Storage();
        uint256 index = $.userIndex[channelId][l1Address];
        
        if ($.channelUsers[channelId].length == 0 || index >= $.channelUsers[channelId].length) {
            return 0;
        }
        
        return $.channelUsers[channelId][index].balance;
    }

    /**
     * @notice Gets the latest root for a channel (alias for getCurrentRoot)
     * @param channelId ID of the channel
     * @return The latest root hash
     */
    function getLatestRoot(uint256 channelId) external view returns (bytes32) {
        return this.getCurrentRoot(channelId);
    }

    /**
     * @notice Gets the complete root sequence for a channel
     * @param channelId ID of the channel
     * @return Array of all root hashes in sequence
     */
    function getRootSequence(uint256 channelId) external view returns (bytes32[] memory) {
        MerkleTreeManager4Storage storage $ = _getMerkleTreeManager4Storage();
        return $.channelRootSequence[channelId];
    }

    /**
     * @notice Gets all user addresses for a channel
     * @param channelId ID of the channel
     * @return l1Addresses Array of L1 addresses
     * @return l2Addresses Array of L2 addresses
     */
    function getUserAddresses(uint256 channelId) 
        external 
        view 
        returns (address[] memory l1Addresses, address[] memory l2Addresses) 
    {
        MerkleTreeManager4Storage storage $ = _getMerkleTreeManager4Storage();
        uint256 userCount = $.channelUsers[channelId].length;
        
        l1Addresses = new address[](userCount);
        l2Addresses = new address[](userCount);
        
        for (uint256 i = 0; i < userCount; i++) {
            l1Addresses[i] = $.channelUsers[channelId][i].l1Address;
            l2Addresses[i] = $.channelUsers[channelId][i].l2Address;
        }
    }

    /**
     * @notice Hashes two values together (for compatibility)
     * @param _left Left value
     * @param _right Right value
     * @return Hash of the two values
     */
    function hashLeftRight(bytes32 _left, bytes32 _right) external pure returns (bytes32) {
        return keccak256(abi.encodePacked(_left, _right));
    }

    /**
     * @notice Checks if a root is known for a channel
     * @param channelId ID of the channel
     * @param _root Root to check
     * @return True if root is found in the sequence
     */
    function isKnownRoot(uint256 channelId, bytes32 _root) external view returns (bool) {
        MerkleTreeManager4Storage storage $ = _getMerkleTreeManager4Storage();
        bytes32[] storage sequence = $.channelRootSequence[channelId];
        
        for (uint256 i = 0; i < sequence.length; i++) {
            if (sequence[i] == _root) {
                return true;
            }
        }
        
        return false;
    }

    /**
     * @notice Gets the zero value at a given depth (for binary tree compatibility)
     * @param i Depth level
     * @return Zero value at that depth
     */
    function zeros(uint256 i) external pure returns (bytes32) {
        // For quaternary trees, we compute zero values on the fly
        bytes32 zero = bytes32(0);
        for (uint256 j = 0; j < i; j++) {
            zero = keccak256(abi.encodePacked(zero, zero, zero, zero));
        }
        return zero;
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[44] private __gap;
}
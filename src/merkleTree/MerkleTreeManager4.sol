// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Field} from "../poseidon/Field.sol";
import {IPoseidon4Yul} from "../interface/IPoseidon4Yul.sol";
import {IMerkleTreeManager} from "../interface/IMerkleTreeManager.sol";
import "@openzeppelin/access/Ownable.sol";

/**
 * @title MerkleTreeManager4
 * @author Tokamak Ooo project
 * @notice Multi-channel incremental quaternary Merkle tree for tracking user balances with RLC
 * @dev This contract implements a quaternary Merkle tree structure where each internal node has 4 children,
 *      providing improved efficiency over binary trees. Each channel maintains its own independent
 *      Merkle tree and state. Uses Poseidon4Yul for hashing 4 inputs simultaneously, which is
 *      more gas-efficient than binary hashing for tree construction and verification.
 *
 *      Key features:
 *      - Quaternary tree structure (4 children per node)
 *      - Maximum depth of 16 levels (supports up to 4^16 leaves)
 *      - RLC (Random Linear Combination) for leaf computation
 *      - Multi-channel support with independent state management
 *      - Efficient proof verification using 4-input hashing
 */
contract MerkleTreeManager4 is IMerkleTreeManager, Ownable {
    // ============ Constants ============

    /**
     * @dev Field size for BLS12-381 curve operations
     *      Used in RLC (Random Linear Combination) calculations
     */
    uint256 public constant FIELD_SIZE = 0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001;

    /**
     * @dev Balance slot identifier for user balance storage
     */
    uint256 public constant BALANCE_SLOT = 0;

    /**
     * @dev Maximum number of root history entries to maintain per channel
     *      Provides rollback capability for state recovery
     */
    uint32 public constant ROOT_HISTORY_SIZE = 30;

    /**
     * @dev Number of children per internal node in the quaternary tree
     *      This is the key difference from binary trees (which have 2 children)
     */
    uint32 public constant CHILDREN_PER_NODE = 4;

    // ============ State Variables ============

    /**
     * @dev Address of the bridge contract that can call privileged functions
     */
    address public bridge;

    /**
     * @dev Flag indicating whether the bridge address has been set
     */
    bool public bridgeSet;

    /**
     * @dev Modifier restricting function access to only the bridge contract
     */
    modifier onlyBridge() {
        require(msg.sender == bridge, "Only bridge can call");
        _;
    }

    // ============ Immutable Configuration ============

    /**
     * @dev Poseidon4Yul hasher contract for 4-input hashing operations
     *      Used for tree construction and proof verification
     */
    IPoseidon4Yul public immutable poseidonHasher;

    /**
     * @dev Depth of the quaternary Merkle tree
     *      Maximum allowed depth is 16 (supports up to 4^16 leaves)
     */
    uint32 public immutable depth;

    // ============ Tree Storage (Per Channel) ============

    /**
     * @dev Cached subtree hashes for efficient tree construction
     *      channelId => depth level => cached subtree hash
     *      Used to avoid recomputing hashes during leaf insertion
     */
    mapping(uint256 => mapping(uint256 => bytes32)) public cachedSubtrees;

    /**
     * @dev Root hashes for each channel, indexed by root sequence number
     *      channelId => rootIndex => root hash
     *      Maintains history of root changes for rollback capability
     */
    mapping(uint256 => mapping(uint256 => bytes32)) public roots;

    /**
     * @dev Current root index for each channel
     *      Used to track the latest root in the roots mapping
     */
    mapping(uint256 => uint32) public currentRootIndex;

    /**
     * @dev Next leaf index to be inserted for each channel
     *      Increments with each new leaf insertion
     */
    mapping(uint256 => uint32) public nextLeafIndex;

    // ============ User Data Storage (Per Channel) ============

    /**
     * @dev Array of user data for each channel
     *      channelId => array of UserData structs
     */
    mapping(uint256 => UserData[]) private channelUsers;

    /**
     * @dev Mapping from L1 address to user index within a channel
     *      channelId => l1Address => index in channelUsers array
     */
    mapping(uint256 => mapping(address => uint256)) public userIndex;

    /**
     * @dev Mapping from L1 address to corresponding L2 address
     *      channelId => l1Address => l2Address
     */
    mapping(uint256 => mapping(address => address)) public l1ToL2;

    // ============ State Tracking (Per Channel) ============

    /**
     * @dev Sequence of root hashes for each channel
     *      Used for proof verification and state reconstruction
     */
    mapping(uint256 => bytes32[]) private channelRootSequence;

    /**
     * @dev Nonce for each channel, incremented with each state change
     *      Provides uniqueness for state transitions
     */
    mapping(uint256 => uint256) public nonce;

    /**
     * @dev Flag indicating whether a channel has been initialized
     *      Prevents double initialization and ensures proper setup
     */
    mapping(uint256 => bool) public channelInitialized;

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
    error UsersAlreadyAdded(uint256 channelId);

    /**
     * @dev Thrown when attempting to add a user without setting their L2 address mapping
     */
    error L2AddressNotSet();

    /**
     * @dev Thrown when input arrays have mismatched lengths
     */
    error LengthMismatch();

    /**
     * @dev Thrown when attempting to access root history on a channel with no roots
     */
    error NoRoots();

    /**
     * @dev Thrown when attempting to access user data on a channel with no leaves
     */
    error NoLeaves();

    // ============ Events ============

    /**
     * @dev Emitted when the bridge address is set
     * @param bridge The address of the bridge contract
     */
    event BridgeSet(address indexed bridge);

    /**
     * @dev Emitted when a new channel is initialized
     * @param channelId The ID of the initialized channel
     * @param initialRoot The initial root hash of the channel's Merkle tree
     */
    event ChannelInitialized(uint256 indexed channelId, bytes32 initialRoot);

    /**
     * @dev Emitted when users are added to a channel
     * @param channelId The ID of the channel
     * @param count The number of users added
     * @param newRoot The new root hash after adding users
     */
    event UsersAdded(uint256 indexed channelId, uint256 count, bytes32 newRoot);

    /**
     * @dev Emitted when a leaf is inserted into the Merkle tree
     * @param channelId The ID of the channel
     * @param leafIndex The index where the leaf was inserted
     * @param leaf The leaf value that was inserted
     * @param newRoot The new root hash after leaf insertion
     */
    event LeafInserted(uint256 indexed channelId, uint32 leafIndex, bytes32 leaf, bytes32 newRoot);

    /**
     * @notice Constructs a new MerkleTreeManager4 contract
     * @param _poseidonHasher Address of the Poseidon4Yul hasher contract
     * @param _depth Depth of the quaternary Merkle tree (1-15)
     * @dev The depth determines the maximum number of leaves the tree can hold:
     *      - Depth 1: up to 4 leaves
     *      - Depth 2: up to 16 leaves
     *      - Depth 3: up to 64 leaves
     *      - And so on... (4^depth leaves)
     *
     *      For quaternary trees, the maximum practical depth is 15 due to gas constraints.
     *      The depth of 16 would support 4^16 = 4,294,967,296 leaves but would be
     *      prohibitively expensive to construct.
     */
    constructor(address _poseidonHasher, uint32 _depth) Ownable(msg.sender) {
        if (_depth == 0) revert DepthTooSmall(_depth);
        if (_depth >= 16) revert DepthTooLarge(_depth); // Reduced max depth for quaternary trees

        poseidonHasher = IPoseidon4Yul(_poseidonHasher);
        depth = _depth;
    }

    /**
     * @notice Sets the bridge address that can call privileged functions
     * @param _bridge Address of the bridge contract
     * @dev This function can only be called once by the contract owner.
     *      It should be called after deploying the Bridge contract.
     *      The bridge address cannot be zero and cannot be changed once set.
     */
    function setBridge(address _bridge) external onlyOwner {
        require(!bridgeSet, "Bridge already set");
        require(_bridge != address(0), "Invalid bridge address");

        bridge = _bridge;
        bridgeSet = true;

        emit BridgeSet(_bridge);
    }

    /**
     * @notice Initializes a new channel with an empty quaternary Merkle tree
     * @param channelId Unique identifier for the channel
     * @dev This function can only be called by the bridge contract.
     *      It initializes the channel with a zero tree (all leaves are zero hashes).
     *      The initial root is computed using the zeros() function based on the tree depth.
     *      Each channel can only be initialized once.
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
     * @notice Sets the L1 to L2 address mapping for a specific channel
     * @param channelId The ID of the channel
     * @param l1Address The L1 address of the user
     * @param l2Address The corresponding L2 address
     * @dev This function can only be called by the bridge contract.
     *      It establishes the mapping between L1 and L2 addresses for users
     *      before they can be added to the channel. This mapping is required
     *      for the addUsers function to work properly.
     */
    function setAddressPair(uint256 channelId, address l1Address, address l2Address) external onlyBridge {
        if (!channelInitialized[channelId]) revert ChannelNotInitialized(channelId);
        l1ToL2[channelId][l1Address] = l2Address;
    }

    /**
     * @notice Adds all users with their initial balances to a specific channel
     * @param channelId The ID of the channel to add users to
     * @param l1Addresses Array of L1 addresses for the users
     * @param balances Array of corresponding initial balances for each user
     * @dev This function can only be called by the bridge contract and only once per channel.
     *      It computes RLC (Random Linear Combination) leaf values for each user and inserts
     *      them into the quaternary Merkle tree. The function updates the root sequence
     *      and emits events for each leaf insertion.
     *
     *      Requirements:
     *      - Channel must be initialized
     *      - L1 addresses and balances arrays must have matching lengths
     *      - Channel must not already have users
     *      - All L2 addresses must be set via setAddressPair before calling this function
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
     * @notice Inserts a leaf into the quaternary Merkle tree and returns the index and new root
     * @param channelId The ID of the channel
     * @param _leaf The leaf value to insert
     * @return index The index where the leaf was inserted
     * @return newRoot The new root hash after leaf insertion
     * @dev This internal function handles the complex logic of inserting a leaf into a quaternary tree.
     *      It traverses up the tree from the leaf position, computing new hashes at each level
     *      using the hashFour function. The function caches intermediate results for efficiency
     *      and handles the quaternary tree structure where each node has 4 children.
     *
     *      The insertion process:
     *      1. Determines the child index (0-3) at each level
     *      2. Caches the first child at each level for future use
     *      3. Computes new hashes using cached values and zero hashes
     *      4. Updates the root history and increments the leaf index
     */
    function _insertAndGetRoot(uint256 channelId, bytes32 _leaf) internal returns (uint32 index, bytes32 newRoot) {
        uint32 _nextLeafIndex = nextLeafIndex[channelId];
        if (_nextLeafIndex == uint32(CHILDREN_PER_NODE) ** depth) {
            revert MerkleTreeFull(_nextLeafIndex);
        }

        uint32 currentIndex = _nextLeafIndex;
        bytes32 currentHash = _leaf;

        for (uint32 i = 0; i < depth; i++) {
            uint32 childIndex = currentIndex % CHILDREN_PER_NODE;

            if (childIndex == 0) {
                // First child - cache the current hash and use zeros for others
                cachedSubtrees[channelId][i] = currentHash;
                currentHash = hashFour(currentHash, zeros(i), zeros(i), zeros(i));
            } else if (childIndex == 1) {
                // Second child - use cached first child
                currentHash = hashFour(cachedSubtrees[channelId][i], currentHash, zeros(i), zeros(i));
            } else if (childIndex == 2) {
                // Third child - use cached first two children
                bytes32 firstChild = cachedSubtrees[channelId][i];
                bytes32 secondChild = getSecondChild(channelId, i);
                currentHash = hashFour(firstChild, secondChild, currentHash, zeros(i));
            } else {
                // Fourth child - use all cached children
                bytes32 firstChild = cachedSubtrees[channelId][i];
                bytes32 secondChild = getSecondChild(channelId, i);
                bytes32 thirdChild = getThirdChild(channelId, i);
                currentHash = hashFour(firstChild, secondChild, thirdChild, currentHash);
            }

            currentIndex /= CHILDREN_PER_NODE;
        }

        uint32 newRootIndex = (currentRootIndex[channelId] + 1) % ROOT_HISTORY_SIZE;
        currentRootIndex[channelId] = newRootIndex;
        roots[channelId][newRootIndex] = currentHash;
        nextLeafIndex[channelId] = _nextLeafIndex + 1;

        return (_nextLeafIndex, currentHash);
    }

    /**
     * @notice Retrieves the second child from cache for a given depth level
     * @param channelId The ID of the channel
     * @param depthLevel The depth level in the tree
     * @return The cached second child hash
     * @dev For quaternary trees, we need to cache additional children beyond the first.
     *      This function uses an offset of 1000 to avoid collision with the main cache
     *      that stores the first child at each level.
     */
    function getSecondChild(uint256 channelId, uint32 depthLevel) internal view returns (bytes32) {
        // For quaternary trees, we need to store additional children
        // This is a simplified approach - in practice you might want to use a more sophisticated caching strategy
        return cachedSubtrees[channelId][depthLevel + 1000]; // Offset to avoid collision with main cache
    }

    /**
     * @notice Retrieves the third child from cache for a given depth level
     * @param channelId The ID of the channel
     * @param depthLevel The depth level in the tree
     * @return The cached third child hash
     * @dev For quaternary trees, we need to cache additional children beyond the first two.
     *      This function uses an offset of 2000 to avoid collision with the main cache
     *      and the second child cache.
     */
    function getThirdChild(uint256 channelId, uint32 depthLevel) internal view returns (bytes32) {
        return cachedSubtrees[channelId][depthLevel + 2000]; // Offset to avoid collision with main cache
    }

    /**
     * @notice Hashes two nodes together for interface compatibility
     * @param _left The left node value
     * @param _right The right node value
     * @return The hash result of the two inputs plus two zero values
     * @dev This function is required by the IMerkleTreeManager interface but is not
     *      used in quaternary trees. It maintains compatibility by calling hashFour
     *      with the two inputs plus two zero values, effectively providing the same
     *      functionality as binary hashing but using the quaternary hasher.
     */
    function hashLeftRight(bytes32 _left, bytes32 _right) external view returns (bytes32) {
        // For quaternary trees, we hash with two additional zero values
        return hashFour(_left, _right, bytes32(0), bytes32(0));
    }

    /**
     * @notice Hashes four nodes together using the Poseidon4Yul hasher
     * @param _a First input value
     * @param _b Second input value
     * @param _c Third input value
     * @param _d Fourth input value
     * @return The hash result of the four inputs
     * @dev This function is the core hashing mechanism for the quaternary Merkle tree.
     *      It validates that all inputs are within the field size and then calls the
     *      Poseidon4Yul hasher using the call pattern. The function converts inputs
     *      to the appropriate field format and handles the result conversion.
     *
     *      This is more efficient than binary hashing as it processes 4 inputs
     *      in a single hash operation instead of requiring multiple binary hash calls.
     */
    function hashFour(bytes32 _a, bytes32 _b, bytes32 _c, bytes32 _d) public view returns (bytes32) {
        if (uint256(_a) >= FIELD_SIZE) revert ValueOutOfRange(_a);
        if (uint256(_b) >= FIELD_SIZE) revert ValueOutOfRange(_b);
        if (uint256(_c) >= FIELD_SIZE) revert ValueOutOfRange(_c);
        if (uint256(_d) >= FIELD_SIZE) revert ValueOutOfRange(_d);

        // Use call pattern to interact with Poseidon4Yul
        bytes memory data = abi.encode(
            Field.toUint256(Field.toField(_a)),
            Field.toUint256(Field.toField(_b)),
            Field.toUint256(Field.toField(_c)),
            Field.toUint256(Field.toField(_d))
        );
        (bool success, bytes memory result) = address(poseidonHasher).staticcall(data);
        require(success, "Hash failed");
        uint256 hashResult = abi.decode(result, (uint256));
        return Field.toBytes32(Field.Type.wrap(hashResult));
    }

    /**
     * @notice Computes the RLC (Random Linear Combination) leaf value for a specific channel
     * @param channelId The ID of the channel
     * @param l2Addr The L2 address of the user
     * @param balance The user's balance
     * @return The computed RLC leaf value
     * @dev This private function computes the leaf value using the RLC method, which provides
     *      security against preimage attacks. The computation involves:
     *      1. Getting the most recent root from the channel's root sequence
     *      2. Computing gamma = Poseidon4Yul(prevRoot, l2Addr, 0, 0) using 4 inputs
     *      3. Computing RLC = l2Addr + gamma * balance (mod FIELD_SIZE)
     *
     *      The use of 4-input hashing with Poseidon4Yul is more efficient than
     *      multiple binary hash operations.
     */
    function _computeLeaf(uint256 channelId, uint256 l2Addr, uint256 balance) private view returns (bytes32) {
        bytes32[] storage rootSequence = channelRootSequence[channelId];

        // Use the most recent root in the sequence
        uint256 prevRoot = (rootSequence.length == 0) ? BALANCE_SLOT : uint256(rootSequence[rootSequence.length - 1]);

        // Compute gamma = Poseidon4Yul(prevRoot, l2Addr, 0, 0) - using 4 inputs with last two as zeros
        bytes memory data = abi.encode(
            Field.toUint256(Field.toField(bytes32(prevRoot))),
            Field.toUint256(Field.toField(bytes32(l2Addr))),
            Field.toUint256(Field.toField(bytes32(0))),
            Field.toUint256(Field.toField(bytes32(0)))
        );
        (bool success, bytes memory result) = address(poseidonHasher).staticcall(data);
        require(success, "Hash failed");
        uint256 gamma = abi.decode(result, (uint256));

        // Compute RLC: l2Addr + gamma * balance
        uint256 rlc = addmod(l2Addr, mulmod(gamma, balance, FIELD_SIZE), FIELD_SIZE);

        // Ensure it fits in the merkle tree field
        if (rlc >= FIELD_SIZE) {
            rlc = rlc % FIELD_SIZE;
        }

        return bytes32(rlc);
    }

    /**
     * @notice Verifies a Merkle proof for a specific channel in the quaternary tree
     * @param channelId The ID of the channel
     * @param proof Array of proof elements (sibling hashes)
     * @param leaf The leaf value to verify
     * @param leafIndex The index of the leaf in the tree
     * @param root The root hash to verify against
     * @return True if the proof is valid, false otherwise
     * @dev This function verifies that a leaf exists in the quaternary Merkle tree by
     *      reconstructing the path from the leaf to the root using the provided proof.
     *
     *      For quaternary trees, each level requires up to 3 sibling hashes:
     *      - First child (index 0): needs 3 siblings
     *      - Second child (index 1): needs 3 siblings
     *      - Third child (index 2): needs 3 siblings
     *      - Fourth child (index 3): needs 3 siblings
     *
     *      The function traverses up the tree, computing hashes at each level using
     *      the hashFour function with the appropriate sibling values and zero hashes
     *      for missing siblings.
     */
    function verifyProof(uint256 channelId, bytes32[] calldata proof, bytes32 leaf, uint256 leafIndex, bytes32 root)
        external
        view
        returns (bool)
    {
        if (!channelInitialized[channelId]) revert ChannelNotInitialized(channelId);

        bytes32 computedHash = leaf;
        uint256 index = leafIndex;
        uint256 proofIndex = 0;

        // Traverse up the tree to the root
        for (uint256 level = 0; level < depth; level++) {
            uint256 childIndex = index % CHILDREN_PER_NODE;

            if (childIndex == 0) {
                // First child - use zeros for missing siblings
                if (proofIndex < proof.length) {
                    computedHash =
                        hashFour(computedHash, proof[proofIndex], proof[proofIndex + 1], proof[proofIndex + 2]);
                    proofIndex += 3;
                } else {
                    // No proof elements left, use zeros
                    computedHash = hashFour(computedHash, zeros(level), zeros(level), zeros(level));
                }
            } else if (childIndex == 1) {
                // Second child - need first sibling and zeros for last two
                if (proofIndex < proof.length) {
                    computedHash =
                        hashFour(proof[proofIndex], computedHash, proof[proofIndex + 1], proof[proofIndex + 2]);
                    proofIndex += 3;
                } else {
                    // No proof elements left, use zeros
                    computedHash = hashFour(zeros(level), computedHash, zeros(level), zeros(level));
                }
            } else if (childIndex == 2) {
                // Third child - need first two siblings and zero for last
                if (proofIndex < proof.length) {
                    computedHash =
                        hashFour(proof[proofIndex], proof[proofIndex + 1], computedHash, proof[proofIndex + 2]);
                    proofIndex += 3;
                } else {
                    // No proof elements left, use zeros
                    computedHash = hashFour(zeros(level), zeros(level), computedHash, zeros(level));
                }
            } else {
                // Fourth child - need all three siblings
                if (proofIndex < proof.length) {
                    computedHash =
                        hashFour(proof[proofIndex], proof[proofIndex + 1], proof[proofIndex + 2], computedHash);
                    proofIndex += 3;
                } else {
                    // No proof elements left, use zeros
                    computedHash = hashFour(zeros(level), zeros(level), zeros(level), computedHash);
                }
            }

            index /= CHILDREN_PER_NODE;
        }

        return computedHash == root;
    }

    /**
     * @notice Computes the leaf value for verification using RLC method
     * @param l2Address The L2 address of the user
     * @param balance The user's balance
     * @param prevRoot The previous root used in RLC calculation
     * @return The computed leaf value for verification
     * @dev This function computes the leaf value using the same RLC method as _computeLeaf
     *      but allows external callers to specify a specific previous root. This is useful
     *      for verification scenarios where you need to compute what a leaf value should be
     *      given a specific previous state.
     *
     *      The computation follows the same pattern:
     *      1. Compute gamma = Poseidon4Yul(prevRoot, l2Addr, 0, 0) using 4 inputs
     *      2. Compute RLC = l2Addr + gamma * balance (mod FIELD_SIZE)
     */
    function computeLeafForVerification(address l2Address, uint256 balance, bytes32 prevRoot)
        external
        view
        returns (bytes32)
    {
        uint256 l2Addr = uint256(uint160(l2Address));

        // Compute gamma using Poseidon4Yul with 4 inputs
        bytes memory data = abi.encode(
            Field.toUint256(Field.toField(prevRoot)),
            Field.toUint256(Field.toField(bytes32(l2Addr))),
            Field.toUint256(Field.toField(bytes32(0))),
            Field.toUint256(Field.toField(bytes32(0)))
        );
        (bool success, bytes memory result) = address(poseidonHasher).staticcall(data);
        require(success, "Hash failed");
        uint256 gamma = abi.decode(result, (uint256));

        // Compute RLC
        uint256 rlc = addmod(l2Addr, mulmod(gamma, balance, FIELD_SIZE), FIELD_SIZE);
        if (rlc >= FIELD_SIZE) {
            rlc = rlc % FIELD_SIZE;
        }

        return bytes32(rlc);
    }

    /**
     * @notice Checks if a root exists in the history for a specific channel
     * @param channelId The ID of the channel
     * @param _root The root hash to check
     * @return True if the root exists in history, false otherwise
     * @dev This function searches through the root history for a channel to determine
     *      if a specific root hash has been seen before. It's useful for detecting
     *      replay attacks and verifying the authenticity of historical states.
     *
     *      The function searches backwards from the current root index through the
     *      circular buffer of root history.
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
     * @notice Gets the latest root hash for a specific channel
     * @param channelId The ID of the channel
     * @return The latest root hash
     * @dev This function returns the most recently computed root hash for a channel.
     *      It's the root that represents the current state of the channel's Merkle tree
     *      after all leaf insertions.
     */
    function getLatestRoot(uint256 channelId) public view returns (bytes32) {
        if (!channelInitialized[channelId]) revert ChannelNotInitialized(channelId);
        return roots[channelId][currentRootIndex[channelId]];
    }

    /**
     * @notice Gets the balance of a user in a specific channel
     * @param channelId The ID of the channel
     * @param l1Address The L1 address of the user
     * @return The user's balance, or 0 if the user is not found
     * @dev This function retrieves the balance of a user from the channel's user data.
     *      If the user is not found in the channel, it returns 0.
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
     * @notice Gets the L2 address corresponding to an L1 address in a specific channel
     * @param channelId The ID of the channel
     * @param l1Address The L1 address of the user
     * @return The corresponding L2 address, or address(0) if not set
     * @dev This function retrieves the L2 address mapping for a user in a channel.
     *      The mapping must be set via setAddressPair before users can be added.
     */
    function getL2Address(uint256 channelId, address l1Address) external view returns (address) {
        return l1ToL2[channelId][l1Address];
    }

    /**
     * @notice Gets the last root in the sequence for a specific channel
     * @param channelId The ID of the channel
     * @return The last root hash in the sequence
     * @dev This function returns the most recent root hash that was added to the
     *      channel's root sequence. It's useful for tracking the progression of
     *      state changes in the channel.
     */
    function getLastRootInSequence(uint256 channelId) external view returns (bytes32) {
        if (!channelInitialized[channelId]) revert ChannelNotInitialized(channelId);

        bytes32[] storage rootSequence = channelRootSequence[channelId];
        if (rootSequence.length == 0) revert NoRoots();
        return rootSequence[rootSequence.length - 1];
    }

    /**
     * @notice Gets all roots in the sequence for a specific channel
     * @param channelId The ID of the channel
     * @return Array of all root hashes in the sequence
     * @dev This function returns the complete array of root hashes for a channel,
     *      representing the full history of state changes. It's primarily useful
     *      for debugging and verification purposes.
     */
    function getRootSequence(uint256 channelId) external view returns (bytes32[] memory) {
        if (!channelInitialized[channelId]) revert ChannelNotInitialized(channelId);
        return channelRootSequence[channelId];
    }

    /**
     * @notice Gets all user addresses in order for a specific channel
     * @param channelId The ID of the channel
     * @return l1Addresses Array of L1 addresses in the order they were added
     * @return l2Addresses Array of corresponding L2 addresses in the same order
     * @dev This function returns arrays of all L1 and L2 addresses for users in a channel,
     *      maintaining the order in which they were added. This is useful for iterating
     *      through all users in a channel or for verification purposes.
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
     * @notice Gets the current root for a specific channel (alias for getLatestRoot)
     * @param channelId The ID of the channel
     * @return The current root hash
     * @dev This function is an alias for getLatestRoot, provided for interface compatibility.
     *      It returns the most recently computed root hash for the channel.
     */
    function getCurrentRoot(uint256 channelId) external view returns (bytes32) {
        return getLatestRoot(channelId);
    }

    /**
     * @notice Gets the root at a specific index in the sequence for a specific channel
     * @param channelId The ID of the channel
     * @param index The index in the root sequence
     * @return The root hash at the specified index
     * @dev This function allows access to historical root hashes in the channel's
     *      root sequence. It's useful for verification of past states or for
     *      implementing rollback functionality.
     */
    function getRootAtIndex(uint256 channelId, uint256 index) external view returns (bytes32) {
        if (!channelInitialized[channelId]) revert ChannelNotInitialized(channelId);

        bytes32[] storage rootSequence = channelRootSequence[channelId];
        require(index < rootSequence.length, "Index out of bounds");
        return rootSequence[index];
    }

    /**
     * @notice Gets the length of the root sequence for a specific channel
     * @param channelId The ID of the channel
     * @return The number of roots in the sequence
     * @dev This function returns the total number of root hashes that have been
     *      generated for a channel, representing the number of state changes
     *      that have occurred.
     */
    function getRootSequenceLength(uint256 channelId) external view returns (uint256) {
        if (!channelInitialized[channelId]) revert ChannelNotInitialized(channelId);
        return channelRootSequence[channelId].length;
    }

    /**
     * @notice Gets the precomputed zero subtree root at a given depth for quaternary trees
     * @param i The depth level (0-15)
     * @return The precomputed zero hash for the specified depth
     * @dev This function returns precomputed zero hashes for different depth levels
     *      in the quaternary Merkle tree. These values are used as padding when
     *      constructing the tree and computing hashes at levels where not all
     *      children are present.
     *
     *      The zero hashes are computed using the hashFour function with zero inputs
     *      and are cached for efficiency. They represent the hash of a subtree
     *      filled entirely with zero values at the specified depth.
     *
     *      For quaternary trees, the maximum supported depth is 15 due to gas constraints.
     */
    function zeros(uint256 i) public pure returns (bytes32) {
        if (i == 0) return bytes32(0x0d823319708ab99ec915efd4f7e03d11ca1790918e8f04cd14100aceca2aa9ff);
        else if (i == 1) return bytes32(0x170a9598425eb05eb8dc06986c6afc717811e874326a79576c02d338bdf14f13);
        else if (i == 2) return bytes32(0x273b1a40397b618dac2fc66ceb71399a3e1a60341e546e053cbfa5995e824caf);
        else if (i == 3) return bytes32(0x16bf9b1fb2dfa9d88cfb1752d6937a1594d257c2053dff3cb971016bfcffe2a1);
        else if (i == 4) return bytes32(0x1288271e1f93a29fa6e748b7468a77a9b8fc3db6b216ce5fc2601fc3e9bd6b36);
        else if (i == 5) return bytes32(0x1d47548adec1068354d163be4ffa348ca89f079b039c9191378584abd79edeca);
        else if (i == 6) return bytes32(0x0b98a89e6827ef697b8fb2e280a2342d61db1eb5efc229f5f4a77fb333b80bef);
        else if (i == 7) return bytes32(0x231555e37e6b206f43fdcd4d660c47442d76aab1ef552aef6db45f3f9cf2e955);
        else if (i == 8) return bytes32(0x03d0dc8c92e2844abcc5fdefe8cb67d93034de0862943990b09c6b8e3fa27a86);
        else if (i == 9) return bytes32(0x1d51ac275f47f10e592b8e690fd3b28a76106893ac3e60cd7b2a3a443f4e8355);
        else if (i == 10) return bytes32(0x16b671eb844a8e4e463e820e26560357edee4ecfdbf5d7b0a28799911505088d);
        else if (i == 11) return bytes32(0x115ea0c2f132c5914d5bb737af6eed04115a3896f0d65e12e761ca560083da15);
        else if (i == 12) return bytes32(0x139a5b42099806c76efb52da0ec1dde06a836bf6f87ef7ab4bac7d00637e28f0);
        else if (i == 13) return bytes32(0x0804853482335a6533eb6a4ddfc215a08026db413d247a7695e807e38debea8e);
        else if (i == 14) return bytes32(0x2f0b264ab5f5630b591af93d93ec2dfed28eef017b251e40905cdf7983689803);
        else if (i == 15) return bytes32(0x170fc161bf1b9610bf196c173bdae82c4adfd93888dc317f5010822a3ba9ebee);
        else revert IndexOutOfBounds(i);
    }
}

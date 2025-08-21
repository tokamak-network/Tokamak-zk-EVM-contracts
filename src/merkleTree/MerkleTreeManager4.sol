// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Field} from "@poseidon/Field.sol";
import {IPoseidon4Yul} from "../interface/IPoseidon4Yul.sol";
import {IMerkleTreeManager} from "../interface/IMerkleTreeManager.sol";
import "@openzeppelin/access/Ownable.sol";

/**
 * @title MerkleTreeManager4
 * @dev Multi-channel incremental quaternary merkle tree for tracking user balances with RLC
 * Each channel maintains its own independent merkle tree and state
 * Uses Poseidon4Yul for hashing 4 inputs instead of 2
 */
contract MerkleTreeManager4 is IMerkleTreeManager, Ownable {
    // Constants
    uint256 public constant FIELD_SIZE = 0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001;
    uint256 public constant BALANCE_SLOT = 0;
    uint32 public constant ROOT_HISTORY_SIZE = 30;
    uint32 public constant CHILDREN_PER_NODE = 4; // Quaternary tree

    address public bridge;
    bool public bridgeSet;

    modifier onlyBridge() {
        require(msg.sender == bridge, "Only bridge can call");
        _;
    }

    // Immutable configuration
    IPoseidon4Yul public immutable poseidonHasher;
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
    error ValueOutOfRange(bytes32 value);
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

    constructor(address _poseidonHasher, uint32 _depth) Ownable(msg.sender) {
        if (_depth == 0) revert DepthTooSmall(_depth);
        if (_depth >= 16) revert DepthTooLarge(_depth); // Reduced max depth for quaternary trees

        poseidonHasher = IPoseidon4Yul(_poseidonHasher);
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
     * @dev Insert a leaf into the quaternary tree and return both index and new root
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
     * @dev Get the second child from cache for a given depth
     */
    function getSecondChild(uint256 channelId, uint32 depthLevel) internal view returns (bytes32) {
        // For quaternary trees, we need to store additional children
        // This is a simplified approach - in practice you might want to use a more sophisticated caching strategy
        return cachedSubtrees[channelId][depthLevel + 1000]; // Offset to avoid collision with main cache
    }

    /**
     * @dev Get the third child from cache for a given depth
     */
    function getThirdChild(uint256 channelId, uint32 depthLevel) internal view returns (bytes32) {
        return cachedSubtrees[channelId][depthLevel + 2000]; // Offset to avoid collision with main cache
    }

    /**
     * @dev Hash two nodes together (required by interface, but not used in quaternary trees)
     * This function maintains compatibility with the interface
     */
    function hashLeftRight(bytes32 _left, bytes32 _right) external view returns (bytes32) {
        // For quaternary trees, we hash with two additional zero values
        return hashFour(_left, _right, bytes32(0), bytes32(0));
    }

    /**
     * @dev Hash four nodes together using Poseidon4Yul
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
     * @dev Compute RLC leaf value for a specific channel
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
     * @dev Verify a merkle proof for a specific channel in quaternary tree
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
                    computedHash = hashFour(computedHash, proof[proofIndex], proof[proofIndex + 1], proof[proofIndex + 2]);
                    proofIndex += 3;
                } else {
                    // No proof elements left, use zeros
                    computedHash = hashFour(computedHash, zeros(level), zeros(level), zeros(level));
                }
            } else if (childIndex == 1) {
                // Second child - need first sibling and zeros for last two
                if (proofIndex < proof.length) {
                    computedHash = hashFour(proof[proofIndex], computedHash, proof[proofIndex + 1], proof[proofIndex + 2]);
                    proofIndex += 3;
                } else {
                    // No proof elements left, use zeros
                    computedHash = hashFour(zeros(level), computedHash, zeros(level), zeros(level));
                }
            } else if (childIndex == 2) {
                // Third child - need first two siblings and zero for last
                if (proofIndex < proof.length) {
                    computedHash = hashFour(proof[proofIndex], proof[proofIndex + 1], computedHash, proof[proofIndex + 2]);
                    proofIndex += 3;
                } else {
                    // No proof elements left, use zeros
                    computedHash = hashFour(zeros(level), zeros(level), computedHash, zeros(level));
                }
            } else {
                // Fourth child - need all three siblings
                if (proofIndex < proof.length) {
                    computedHash = hashFour(proof[proofIndex], proof[proofIndex + 1], proof[proofIndex + 2], computedHash);
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
     * @dev Compute leaf value for verification
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
     * @dev Get zero subtree root at given depth for quaternary tree
     * These are precomputed zero values for quaternary trees
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

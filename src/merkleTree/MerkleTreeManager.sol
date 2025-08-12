// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Field} from "@poseidon/src/Field.sol";
import {Poseidon2} from "@poseidon/src/Poseidon2.sol";

/**
 * @title MerkleTreeManager
 * @dev Unified incremental merkle tree for tracking user balances with RLC
 * FIXED: rootSequence is now updated after each insertion to maintain RLC chain
 */
contract MerkleTreeManager {
    // Constants
    uint256 public constant FIELD_SIZE = 21888242871839275222246405745257275088548364400416034343698204186575808495617;
    uint256 public constant BLS_FIELD_MODULUS = 0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001;
    uint256 public constant BALANCE_SLOT = 0;
    uint32 public constant ROOT_HISTORY_SIZE = 30;

    // Structs
    struct UserData {
        address l1Address;
        address l2Address;
        uint256 balance;
    }

    // Immutable configuration
    Poseidon2 public immutable poseidonHasher;
    uint32 public immutable depth;

    // Tree storage
    mapping(uint256 => bytes32) public cachedSubtrees;
    mapping(uint256 => bytes32) public roots;
    uint32 public currentRootIndex = 0;
    uint32 public nextLeafIndex = 0;

    // User data storage
    UserData[] public users;
    mapping(address => uint256) public userIndex;
    mapping(address => address) public l1ToL2;

    // State tracking
    bytes32[] public rootSequence;
    uint256 public nonce;

    // Errors
    error LeftValueOutOfRange(bytes32 left);
    error RightValueOutOfRange(bytes32 right);
    error DepthTooSmall(uint32 depth);
    error DepthTooLarge(uint32 depth);
    error MerkleTreeFull(uint32 nextIndex);
    error IndexOutOfBounds(uint256 index);
    error AlreadyInitialized();
    error NotInitialized();
    error UsersAlreadyAdded();
    error L2AddressNotSet();
    error LengthMismatch();
    error NoRoots();
    error NoLeaves();

    // Events
    event Initialized(bytes32 initialRoot);
    event UsersAdded(uint256 count, bytes32 newRoot);
    event LeafInserted(uint32 leafIndex, bytes32 leaf, bytes32 newRoot);

    constructor(address _poseidonHasher, uint32 _depth) {
        if (_depth == 0) revert DepthTooSmall(_depth);
        if (_depth >= 32) revert DepthTooLarge(_depth);

        poseidonHasher = Poseidon2(_poseidonHasher);
        depth = _depth;

        // Initialize with zero tree
        roots[0] = zeros(depth);

        // First root in sequence is the slot number (0)
        rootSequence.push(bytes32(BALANCE_SLOT));

        emit Initialized(bytes32(BALANCE_SLOT));
    }

    /**
     * @dev Set L1 to L2 address mapping
     */
    function setAddressPair(address l1Address, address l2Address) external {
        l1ToL2[l1Address] = l2Address;
    }

    /**
     * @dev Add all users with their initial balances
     * FIXED: Now properly maintains RLC chain by updating rootSequence after each insertion
     */
    function addUsers(address[] calldata l1Addresses, uint256[] calldata balances) external {
        if (l1Addresses.length != balances.length) revert LengthMismatch();
        if (users.length != 0) revert UsersAlreadyAdded();

        // Add each user
        for (uint256 i = 0; i < l1Addresses.length; i++) {
            address l1Addr = l1Addresses[i];
            address l2Addr = l1ToL2[l1Addr];
            if (l2Addr == address(0)) revert L2AddressNotSet();

            // FIXED: Compute RLC leaf using current state of rootSequence
            bytes32 leaf = _computeLeaf(uint256(uint160(l2Addr)), balances[i]);

            // Insert into tree and get new root
            (uint32 leafIndex, bytes32 newRoot) = _insertAndGetRoot(leaf);

            // FIXED: Update rootSequence immediately after each insertion
            rootSequence.push(newRoot);
            nonce++;

            // Store user data
            users.push(UserData({l1Address: l1Addr, l2Address: l2Addr, balance: balances[i]}));
            userIndex[l1Addr] = i;

            emit LeafInserted(leafIndex, leaf, newRoot);
        }

        emit UsersAdded(l1Addresses.length, getLatestRoot());
    }

    /**
     * @dev Insert a leaf into the tree and return both index and new root
     * FIXED: Returns the new root so we can update rootSequence immediately
     */
    function _insertAndGetRoot(bytes32 _leaf) internal returns (uint32 index, bytes32 newRoot) {
        uint32 _nextLeafIndex = nextLeafIndex;
        if (_nextLeafIndex == uint32(2) ** depth) {
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
                cachedSubtrees[i] = currentHash;
            } else {
                left = cachedSubtrees[i];
                right = currentHash;
            }
            currentHash = hashLeftRight(left, right);
            currentIndex /= 2;
        }

        uint32 newRootIndex = (currentRootIndex + 1) % ROOT_HISTORY_SIZE;
        currentRootIndex = newRootIndex;
        roots[newRootIndex] = currentHash;
        nextLeafIndex = _nextLeafIndex + 1;

        return (_nextLeafIndex, currentHash);
    }

    /**
     * @dev Hash two nodes together
     */
    function hashLeftRight(bytes32 _left, bytes32 _right) public view returns (bytes32) {
        if (uint256(_left) >= FIELD_SIZE) revert LeftValueOutOfRange(_left);
        if (uint256(_right) >= FIELD_SIZE) revert RightValueOutOfRange(_right);

        return Field.toBytes32(poseidonHasher.hash_2(Field.toField(_left), Field.toField(_right)));
    }

    /**
     * @dev Compute RLC leaf value
     * FIXED: Now correctly uses the most recent root in the sequence
     */
    function _computeLeaf(uint256 l2Addr, uint256 balance) private view returns (bytes32) {
        // Use the most recent root in the sequence
        uint256 prevRoot = (rootSequence.length == 0) ? BALANCE_SLOT : uint256(rootSequence[rootSequence.length - 1]);

        // Compute gamma = Poseidon2(prevRoot, l2Addr)
        uint256 gamma = uint256(
            Field.toBytes32(poseidonHasher.hash_2(Field.toField(bytes32(prevRoot)), Field.toField(bytes32(l2Addr))))
        );

        // Compute RLC: l2Addr + gamma * balance
        uint256 rlc = addmod(l2Addr, mulmod(gamma, balance, BLS_FIELD_MODULUS), BLS_FIELD_MODULUS);

        // Ensure it fits in the merkle tree field
        if (rlc >= FIELD_SIZE) {
            rlc = rlc % FIELD_SIZE;
        }

        return bytes32(rlc);
    }

    /**
     * @dev Verify a merkle proof
     */
    function verifyProof(bytes32[] calldata proof, bytes32 leaf, uint256 leafIndex, bytes32 root)
        external
        view
        returns (bool)
    {
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
     * @dev Compute leaf value for verification
     */
    function computeLeafForVerification(address l2Address, uint256 balance, bytes32 prevRoot)
        external
        view
        returns (bytes32)
    {
        uint256 l2Addr = uint256(uint160(l2Address));

        // Compute gamma
        uint256 gamma =
            uint256(Field.toBytes32(poseidonHasher.hash_2(Field.toField(prevRoot), Field.toField(bytes32(l2Addr)))));

        // Compute RLC
        uint256 rlc = addmod(l2Addr, mulmod(gamma, balance, BLS_FIELD_MODULUS), BLS_FIELD_MODULUS);
        if (rlc >= FIELD_SIZE) {
            rlc = rlc % FIELD_SIZE;
        }

        return bytes32(rlc);
    }

    /**
     * @dev Check if a root exists in history
     */
    function isKnownRoot(bytes32 _root) public view returns (bool) {
        if (_root == bytes32(0)) return false;

        uint32 _currentRootIndex = currentRootIndex;
        uint32 i = _currentRootIndex;

        do {
            if (_root == roots[i]) return true;
            if (i == 0) {
                i = ROOT_HISTORY_SIZE;
            }
            i--;
        } while (i != _currentRootIndex);

        return false;
    }

    /**
     * @dev Get the latest root
     */
    function getLatestRoot() public view returns (bytes32) {
        return roots[currentRootIndex];
    }

    /**
     * @dev Get user balance
     */
    function getBalance(address l1Address) external view returns (uint256) {
        uint256 idx = userIndex[l1Address];
        if (idx >= users.length || users[idx].l1Address != l1Address) {
            return 0;
        }
        return users[idx].balance;
    }

    /**
     * @dev Get L2 address for an L1 address
     */
    function getL2Address(address l1Address) external view returns (address) {
        return l1ToL2[l1Address];
    }

    /**
     * @dev Get the last root in sequence
     */
    function getLastRootInSequence() external view returns (bytes32) {
        if (rootSequence.length == 0) revert NoRoots();
        return rootSequence[rootSequence.length - 1];
    }

    /**
     * @dev Get all roots (for debugging)
     */
    function getRootSequence() external view returns (bytes32[] memory) {
        return rootSequence;
    }

    /**
     * @dev Get user addresses in order
     */
    function getUserAddresses() external view returns (address[] memory l1Addresses, address[] memory l2Addresses) {
        l1Addresses = new address[](users.length);
        l2Addresses = new address[](users.length);

        for (uint256 i = 0; i < users.length; i++) {
            l1Addresses[i] = users[i].l1Address;
            l2Addresses[i] = users[i].l2Address;
        }
    }

    /**
     * @dev Get current root (alias for getLatestRoot)
     */
    function getCurrentRoot() external view returns (bytes32) {
        return getLatestRoot();
    }

    /**
     * @dev Get root at specific index in sequence
     */
    function getRootAtIndex(uint256 index) external view returns (bytes32) {
        require(index < rootSequence.length, "Index out of bounds");
        return rootSequence[index];
    }

    /**
     * @dev Get the length of root sequence
     */
    function getRootSequenceLength() external view returns (uint256) {
        return rootSequence.length;
    }

    /**
     * @dev Get zero subtree root at given depth
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
        else if (i == 16) return bytes32(0x0b2e7665b17622cc0243b6fa35110aa7dd0ee3cc9409650172aa786ca5971439);
        else if (i == 17) return bytes32(0x12d5a033cbeff854c5ba0c5628ac4628104be6ab370699a1b2b4209e518b0ac5);
        else if (i == 18) return bytes32(0x1bc59846eb7eafafc85ba9a99a89562763735322e4255b7c1788a8fe8b90bf5d);
        else if (i == 19) return bytes32(0x1b9421fbd79f6972a348a3dd4721781ec25a5d8d27342942ae00aba80a3904d4);
        else if (i == 20) return bytes32(0x087fde1c4c9c27c347f347083139eee8759179d255ec8381c02298d3d6ccd233);
        else if (i == 21) return bytes32(0x1e26b1884cb500b5e6bbfdeedbdca34b961caf3fa9839ea794bfc7f87d10b3f1);
        else if (i == 22) return bytes32(0x09fc1a538b88bda55a53253c62c153e67e8289729afd9b8bfd3f46f5eecd5a72);
        else if (i == 23) return bytes32(0x14cd0edec3423652211db5210475a230ca4771cd1e45315bcd6ea640f14077e2);
        else if (i == 24) return bytes32(0x1d776a76bc76f4305ef0b0b27a58a9565864fe1b9f2a198e8247b3e599e036ca);
        else if (i == 25) return bytes32(0x1f93e3103fed2d3bd056c3ac49b4a0728578be33595959788fa25514cdb5d42f);
        else if (i == 26) return bytes32(0x138b0576ee7346fb3f6cfb632f92ae206395824b9333a183c15470404c977a3b);
        else if (i == 27) return bytes32(0x0745de8522abfcd24bd50875865592f73a190070b4cb3d8976e3dbff8fdb7f3d);
        else if (i == 28) return bytes32(0x2ffb8c798b9dd2645e9187858cb92a86c86dcd1138f5d610c33df2696f5f6860);
        else if (i == 29) return bytes32(0x2612a1395168260c9999287df0e3c3f1b0d8e008e90cd15941e4c2df08a68a5a);
        else if (i == 30) return bytes32(0x10ebedce66a910039c8edb2cd832d6a9857648ccff5e99b5d08009b44b088edf);
        else if (i == 31) return bytes32(0x213fb841f9de06958cf4403477bdbff7c59d6249daabfee147f853db7c808082);
        else revert IndexOutOfBounds(i);
    }
}

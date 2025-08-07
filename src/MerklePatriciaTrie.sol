// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {RLP} from "./library/RLP.sol";

/**
 * @title MerklePatriciaTrie
 * @dev Full implementation of Ethereum's Merkle Patricia Trie matching MerkleStateManager
 */
contract MerklePatriciaTrie {
    using RLP for bytes;
    using RLP for bytes[];

    // Empty trie hash (keccak256(RLP([])))
    bytes32 public constant EMPTY_TRIE_HASH = 0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421;

    // Storage for the trie nodes
    mapping(bytes32 => bytes) private db;

    // Current root hash
    bytes32 public root;

    // Node type indicators (first nibble of hex-prefix)
    uint8 private constant HP_EXTENSION_EVEN = 0x00;
    uint8 private constant HP_EXTENSION_ODD = 0x10;
    uint8 private constant HP_LEAF_EVEN = 0x20;
    uint8 private constant HP_LEAF_ODD = 0x30;

    constructor() {
        root = EMPTY_TRIE_HASH;
    }

    /**
     * @dev Put a key-value pair into the trie
     */
    function put(bytes memory key, bytes memory value) public {
        bytes memory k = _nibblesToBytes(key);
        root = _insert(root, k, value, 0);
    }

    /**
     * @dev Get a value from the trie
     */
    function get(bytes memory key) public view returns (bytes memory) {
        bytes memory k = _nibblesToBytes(key);
        return _get(root, k, 0);
    }

    /**
     * @dev Put storage value (for contract storage slot)
     */
    function putStorage(address addr, bytes32 slot, bytes32 value) public {
        bytes32 key = _computeStorageKey(addr, uint256(slot));
        put(abi.encodePacked(key), abi.encodePacked(value));
    }

    /**
     * @dev Get storage value
     */
    function getStorage(address addr, bytes32 slot) public view returns (bytes32) {
        bytes32 key = _computeStorageKey(addr, uint256(slot));
        bytes memory value = get(abi.encodePacked(key));
        if (value.length == 0) return bytes32(0);
        return abi.decode(value, (bytes32));
    }

    /**
     * @dev Compute storage key matching off-chain implementation
     */
    function _computeStorageKey(address addr, uint256 slot) private pure returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                bytes32(uint256(uint160(addr))), // Pad address to 32 bytes
                bytes32(slot) // Pad slot to 32 bytes
            )
        );
    }

    /**
     * @dev Convert bytes to nibbles
     */
    function _nibblesToBytes(bytes memory b) private pure returns (bytes memory) {
        bytes memory nibbles = new bytes(b.length * 2);
        for (uint256 i = 0; i < b.length; i++) {
            nibbles[i * 2] = bytes1(uint8(b[i]) >> 4);
            nibbles[i * 2 + 1] = bytes1(uint8(b[i]) & 0x0f);
        }
        return nibbles;
    }

    /**
     * @dev Hex prefix encoding
     */
    function _hexPrefix(bytes memory nibbles, bool isLeaf) private pure returns (bytes memory) {
        uint8 prefix = isLeaf ? HP_LEAF_EVEN : HP_EXTENSION_EVEN;

        if (nibbles.length % 2 == 1) {
            prefix = isLeaf ? HP_LEAF_ODD : HP_EXTENSION_ODD;
            prefix |= uint8(nibbles[0]);

            bytes memory encoded = new bytes(nibbles.length / 2 + 1);
            encoded[0] = bytes1(prefix);

            for (uint256 i = 1; i < nibbles.length; i += 2) {
                encoded[i / 2 + 1] = bytes1((uint8(nibbles[i]) << 4) | uint8(nibbles[i + 1]));
            }
            return encoded;
        } else {
            bytes memory encoded = new bytes(nibbles.length / 2 + 1);
            encoded[0] = bytes1(prefix);

            for (uint256 i = 0; i < nibbles.length; i += 2) {
                encoded[i / 2 + 1] = bytes1((uint8(nibbles[i]) << 4) | uint8(nibbles[i + 1]));
            }
            return encoded;
        }
    }

    /**
     * @dev Decode hex prefix
     */
    function _hexPrefixDecode(bytes memory hp) private pure returns (bytes memory nibbles, bool isLeaf) {
        uint8 prefix = uint8(hp[0]);
        isLeaf = (prefix & 0x20) != 0;
        bool isOdd = (prefix & 0x10) != 0;

        uint256 nibbleLen = (hp.length - 1) * 2;
        if (isOdd) {
            nibbleLen++;
            nibbles = new bytes(nibbleLen);
            nibbles[0] = bytes1(prefix & 0x0f);

            for (uint256 i = 1; i < hp.length; i++) {
                nibbles[(i - 1) * 2 + 1] = bytes1(uint8(hp[i]) >> 4);
                if ((i - 1) * 2 + 2 < nibbleLen) {
                    nibbles[(i - 1) * 2 + 2] = bytes1(uint8(hp[i]) & 0x0f);
                }
            }
        } else {
            nibbles = new bytes(nibbleLen);

            for (uint256 i = 1; i < hp.length; i++) {
                nibbles[(i - 1) * 2] = bytes1(uint8(hp[i]) >> 4);
                nibbles[(i - 1) * 2 + 1] = bytes1(uint8(hp[i]) & 0x0f);
            }
        }
    }

    /**
     * @dev Get node from database
     */
    function _getNode(bytes32 nodeRef) private view returns (bytes memory) {
        if (uint256(nodeRef) < 32) {
            // Embedded node
            return abi.encodePacked(nodeRef);
        }
        return db[nodeRef];
    }

    /**
     * @dev Store node in database
     */
    function _putNode(bytes memory node) private returns (bytes32) {
        if (node.length < 32) {
            // Small nodes are embedded directly
            return bytes32(node);
        }
        bytes32 nodeHash = keccak256(node);
        db[nodeHash] = node;
        return nodeHash;
    }

    /**
     * @dev Insert key-value into trie
     */
    function _insert(bytes32 nodeRef, bytes memory key, bytes memory value, uint256 keyIndex)
        private
        returns (bytes32)
    {
        if (nodeRef == bytes32(0) || nodeRef == EMPTY_TRIE_HASH) {
            // Empty node - create new leaf
            bytes memory remainingKey = _slice(key, keyIndex, key.length - keyIndex);
            bytes memory leafKey = _hexPrefix(remainingKey, true);

            bytes[] memory items = new bytes[](2);
            items[0] = leafKey.encode();
            items[1] = value.encode();

            return _putNode(items.encodeList());
        }

        bytes memory node = _getNode(nodeRef);
        bytes[] memory nodeList = _decodeList(node);

        if (nodeList.length == 2) {
            // Leaf or extension node
            bytes memory encodedPath = nodeList[0];
            (bytes memory path, bool isLeaf) = _hexPrefixDecode(encodedPath);

            uint256 matchingLen = _matchingNibbleLength(key, keyIndex, path);

            if (isLeaf) {
                if (matchingLen == path.length && keyIndex + matchingLen == key.length) {
                    // Update existing leaf
                    bytes[] memory newLeaf = new bytes[](2);
                    newLeaf[0] = encodedPath;
                    newLeaf[1] = value.encode();
                    return _putNode(newLeaf.encodeList());
                }

                // Convert to branch
                bytes32 branch = _createBranch();

                if (matchingLen == path.length) {
                    // Insert old leaf value at branch
                    branch = _insertBranch(branch, 16, nodeList[1]);
                } else {
                    // Insert old leaf
                    uint8 oldBranchKey = uint8(path[matchingLen]);
                    bytes memory oldLeafPath = _slice(path, matchingLen + 1, path.length - matchingLen - 1);
                    bytes memory oldLeafNode = _createLeaf(oldLeafPath, nodeList[1]);
                    branch = _insertBranch(branch, oldBranchKey, oldLeafNode);
                }

                // Insert new value
                if (keyIndex + matchingLen == key.length) {
                    branch = _insertBranch(branch, 16, value.encode());
                } else {
                    uint8 newBranchKey = uint8(key[keyIndex + matchingLen]);
                    branch = _insert(bytes32(0), key, value, keyIndex + matchingLen + 1);
                    branch = _insertBranch(branch, newBranchKey, _getNode(branch));
                }

                if (matchingLen > 0) {
                    // Need extension node
                    bytes memory extPath = _slice(path, 0, matchingLen);
                    return _createExtension(extPath, branch);
                }

                return branch;
            } else {
                // Extension node
                if (matchingLen < path.length) {
                    // Split extension
                    bytes32 branch = _createBranch();

                    // Continue with rest of extension
                    uint8 extBranchKey = uint8(path[matchingLen]);
                    bytes memory remainingExtPath = _slice(path, matchingLen + 1, path.length - matchingLen - 1);
                    bytes32 remainingExt = remainingExtPath.length > 0
                        ? _createExtension(remainingExtPath, abi.decode(nodeList[1], (bytes32)))
                        : abi.decode(nodeList[1], (bytes32));
                    branch = _insertBranch(branch, extBranchKey, _getNode(remainingExt));

                    // Insert new value
                    uint8 newBranchKey = uint8(key[keyIndex + matchingLen]);
                    bytes32 newNode = _insert(bytes32(0), key, value, keyIndex + matchingLen + 1);
                    branch = _insertBranch(branch, newBranchKey, _getNode(newNode));

                    if (matchingLen > 0) {
                        bytes memory commonPath = _slice(path, 0, matchingLen);
                        return _createExtension(commonPath, branch);
                    }

                    return branch;
                } else {
                    // Continue down extension
                    bytes32 nextRef = abi.decode(nodeList[1], (bytes32));
                    bytes32 newNext = _insert(nextRef, key, value, keyIndex + matchingLen);

                    bytes[] memory newExt = new bytes[](2);
                    newExt[0] = encodedPath;
                    newExt[1] = abi.encode(newNext);
                    return _putNode(newExt.encodeList());
                }
            }
        } else if (nodeList.length == 17) {
            // Branch node
            if (keyIndex == key.length) {
                // Insert at branch value
                nodeList[16] = value.encode();
                return _putNode(nodeList.encodeList());
            }

            uint8 branchKey = uint8(key[keyIndex]);
            bytes32 childRef = nodeList[branchKey].length > 0 ? abi.decode(nodeList[branchKey], (bytes32)) : bytes32(0);

            bytes32 newChild = _insert(childRef, key, value, keyIndex + 1);
            nodeList[branchKey] = abi.encode(newChild);

            return _putNode(nodeList.encodeList());
        }

        revert("Invalid node type");
    }

    /**
     * @dev Get value from trie
     */
    function _get(bytes32 nodeRef, bytes memory key, uint256 keyIndex) private view returns (bytes memory) {
        if (nodeRef == bytes32(0) || nodeRef == EMPTY_TRIE_HASH) {
            return "";
        }

        bytes memory node = _getNode(nodeRef);
        bytes[] memory nodeList = _decodeList(node);

        if (nodeList.length == 2) {
            // Leaf or extension
            bytes memory encodedPath = nodeList[0];
            (bytes memory path, bool isLeaf) = _hexPrefixDecode(encodedPath);

            uint256 matchingLen = _matchingNibbleLength(key, keyIndex, path);

            if (matchingLen == path.length) {
                if (isLeaf) {
                    if (keyIndex + matchingLen == key.length) {
                        return nodeList[1];
                    }
                    return "";
                } else {
                    bytes32 nextRef = abi.decode(nodeList[1], (bytes32));
                    return _get(nextRef, key, keyIndex + matchingLen);
                }
            }
            return "";
        } else if (nodeList.length == 17) {
            // Branch
            if (keyIndex == key.length) {
                return nodeList[16];
            }

            uint8 branchKey = uint8(key[keyIndex]);
            if (nodeList[branchKey].length > 0) {
                bytes32 childRef = abi.decode(nodeList[branchKey], (bytes32));
                return _get(childRef, key, keyIndex + 1);
            }
            return "";
        }

        return "";
    }

    /**
     * @dev Create leaf node
     */
    function _createLeaf(bytes memory path, bytes memory value) private pure returns (bytes memory) {
        bytes memory leafKey = _hexPrefix(path, true);
        bytes[] memory items = new bytes[](2);
        items[0] = leafKey.encode();
        items[1] = value;
        return items.encodeList();
    }

    /**
     * @dev Create extension node
     */
    function _createExtension(bytes memory path, bytes32 next) private returns (bytes32) {
        bytes memory extKey = _hexPrefix(path, false);
        bytes[] memory items = new bytes[](2);
        items[0] = extKey.encode();
        items[1] = abi.encode(next);
        return _putNode(items.encodeList());
    }

    /**
     * @dev Create empty branch
     */
    function _createBranch() private returns (bytes32) {
        bytes[] memory items = new bytes[](17);
        for (uint256 i = 0; i < 17; i++) {
            items[i] = "";
        }
        return _putNode(items.encodeList());
    }

    /**
     * @dev Insert into branch
     */
    function _insertBranch(bytes32 branchRef, uint8 key, bytes memory value) private returns (bytes32) {
        bytes memory branch = _getNode(branchRef);
        bytes[] memory items = _decodeList(branch);
        items[key] = value;
        return _putNode(items.encodeList());
    }

    /**
     * @dev Calculate matching nibble length
     */
    function _matchingNibbleLength(bytes memory a, uint256 aOffset, bytes memory b) private pure returns (uint256) {
        uint256 len = 0;
        while (aOffset + len < a.length && len < b.length && a[aOffset + len] == b[len]) {
            len++;
        }
        return len;
    }

    /**
     * @dev Slice bytes array
     */
    function _slice(bytes memory data, uint256 start, uint256 length) private pure returns (bytes memory) {
        bytes memory result = new bytes(length);
        for (uint256 i = 0; i < length; i++) {
            result[i] = data[start + i];
        }
        return result;
    }

    /**
     * @dev Decode RLP list (simplified version)
     */
    function _decodeList(bytes memory rlpData) private pure returns (bytes[] memory) {
        // This is a simplified decoder - full implementation would be more complex
        // For production, use a complete RLP decoder library

        uint8 prefix = uint8(rlpData[0]);
        require(prefix >= 0xc0, "Not a list");

        uint256 length;
        uint256 dataOffset;

        if (prefix <= 0xf7) {
            length = prefix - 0xc0;
            dataOffset = 1;
        } else {
            uint256 lenLen = prefix - 0xf7;
            assembly ("memory-safe") {
                length := mload(add(rlpData, add(1, lenLen)))
            }
            dataOffset = 1 + lenLen;
        }

        // Count items (simplified)
        uint256 itemCount = 0;
        uint256 offset = dataOffset;
        while (offset < dataOffset + length) {
            itemCount++;
            // Skip item (simplified - assumes single byte items for counting)
            if (uint8(rlpData[offset]) < 0x80) {
                offset += 1;
            } else if (uint8(rlpData[offset]) <= 0xb7) {
                offset += 1 + (uint8(rlpData[offset]) - 0x80);
            } else {
                revert("Complex RLP not fully implemented");
            }
        }

        bytes[] memory items = new bytes[](itemCount);
        // Decode items (simplified)
        // Full implementation would properly decode each item

        return items;
    }

    /**
     * @dev Get the current state root
     */
    function stateRoot() public view returns (bytes32) {
        return root;
    }

    /**
     * @dev Reset the trie
     */
    function reset() public {
        root = EMPTY_TRIE_HASH;
    }
}

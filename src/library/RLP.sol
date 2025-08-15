// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

/**
 * @title RLP
 * @dev RLP encoding/decoding library for Merkle Patricia Trie
 */
library RLP {
    // Structs for decoded data
    struct RLPItem {
        uint256 len;
        uint256 memPtr;
    }

    struct Iterator {
        RLPItem item;
        uint256 nextPtr;
    }

    // Custom errors
    error InvalidRLPData();
    error InvalidRLPListData();

    // ========== Encoding Functions (existing) ==========

    function encode(bytes memory item) internal pure returns (bytes memory) {
        if (item.length == 1 && uint8(item[0]) <= 0x7f) {
            return item;
        } else if (item.length <= 55) {
            bytes memory result = new bytes(item.length + 1);
            result[0] = bytes1(uint8(0x80 + item.length));
            for (uint256 i = 0; i < item.length; i++) {
                result[i + 1] = item[i];
            }
            return result;
        } else {
            return encodeLongItem(item);
        }
    }

    function encodeLongItem(bytes memory item) private pure returns (bytes memory) {
        uint256 length = item.length;
        uint256 lenLen = 0;
        uint256 temp = length;

        while (temp != 0) {
            lenLen++;
            temp /= 256;
        }

        bytes memory result = new bytes(1 + lenLen + length);
        result[0] = bytes1(uint8(0xb7 + lenLen));

        for (uint256 i = 0; i < lenLen; i++) {
            result[lenLen - i] = bytes1(uint8(length / (256 ** i)));
        }

        for (uint256 i = 0; i < length; i++) {
            result[i + 1 + lenLen] = item[i];
        }

        return result;
    }

    function encodeList(bytes[] memory items) internal pure returns (bytes memory) {
        uint256 totalLen = 0;
        for (uint256 i = 0; i < items.length; i++) {
            totalLen += items[i].length;
        }

        bytes memory list = new bytes(totalLen);
        uint256 offset = 0;
        for (uint256 i = 0; i < items.length; i++) {
            for (uint256 j = 0; j < items[i].length; j++) {
                list[offset + j] = items[i][j];
            }
            offset += items[i].length;
        }

        if (totalLen <= 55) {
            bytes memory result = new bytes(totalLen + 1);
            result[0] = bytes1(uint8(0xc0 + totalLen));
            for (uint256 i = 0; i < totalLen; i++) {
                result[i + 1] = list[i];
            }
            return result;
        } else {
            return encodeLongList(list, totalLen);
        }
    }

    function encodeLongList(bytes memory list, uint256 length) private pure returns (bytes memory) {
        uint256 lenLen = 0;
        uint256 temp = length;

        while (temp != 0) {
            lenLen++;
            temp /= 256;
        }

        bytes memory result = new bytes(1 + lenLen + length);
        result[0] = bytes1(uint8(0xf7 + lenLen));

        for (uint256 i = 0; i < lenLen; i++) {
            result[lenLen - i] = bytes1(uint8(length / (256 ** i)));
        }

        for (uint256 i = 0; i < length; i++) {
            result[i + 1 + lenLen] = list[i];
        }

        return result;
    }

    // ========== Decoding Functions ==========

    /**
     * @dev Convert bytes to RLPItem. This assumes the bytes are RLP encoded.
     */
    function toRLPItem(bytes memory item) internal pure returns (RLPItem memory) {
        if (item.length == 0) {
            revert InvalidRLPData();
        }

        uint256 memPtr;
        assembly {
            memPtr := add(item, 0x20)
        }

        return RLPItem(item.length, memPtr);
    }

    /**
     * @dev Decode an RLPItem into bytes. This will decode the item regardless of whether it's a list or data.
     */
    function toBytes(RLPItem memory item) internal pure returns (bytes memory) {
        uint256 memPtr = item.memPtr;
        uint256 offset = _payloadOffset(memPtr);
        uint256 len = _itemLength(memPtr);
        uint256 payloadLen = len - offset;

        bytes memory result = new bytes(payloadLen);
        uint256 destPtr;
        assembly {
            destPtr := add(result, 0x20)
            let srcPtr := add(memPtr, offset)

            // Copy word by word
            for { let i := 0 } lt(i, payloadLen) { i := add(i, 0x20) } {
                mstore(add(destPtr, i), mload(add(srcPtr, i)))
            }
        }

        return result;
    }

    /**
     * @dev Decode an RLPItem into a list of RLPItems.
     */
    function toList(RLPItem memory item) internal pure returns (RLPItem[] memory) {
        if (!isList(item)) {
            revert InvalidRLPListData();
        }

        uint256 itemCount = numItems(item);
        RLPItem[] memory result = new RLPItem[](itemCount);

        uint256 memPtr = item.memPtr;
        uint256 currPtr = memPtr + _payloadOffset(memPtr);
        uint256 dataLen;
        for (uint256 i = 0; i < itemCount; i++) {
            dataLen = _itemLength(currPtr);
            result[i] = RLPItem(dataLen, currPtr);
            currPtr += dataLen;
        }

        return result;
    }

    /**
     * @dev Decode bytes into a list of bytes arrays (complete decoder).
     */
    function decode(bytes memory data) internal pure returns (bytes[] memory) {
        RLPItem memory rlpItem = toRLPItem(data);

        if (isList(rlpItem)) {
            RLPItem[] memory items = toList(rlpItem);
            bytes[] memory result = new bytes[](items.length);

            for (uint256 i = 0; i < items.length; i++) {
                result[i] = toBytes(items[i]);
            }

            return result;
        } else {
            // Single item, return as array with one element
            bytes[] memory result = new bytes[](1);
            result[0] = toBytes(rlpItem);
            return result;
        }
    }

    /**
     * @dev Decode bytes into a single bytes item (for non-list items).
     */
    function decodeSingle(bytes memory data) internal pure returns (bytes memory) {
        RLPItem memory rlpItem = toRLPItem(data);
        return toBytes(rlpItem);
    }

    /**
     * @dev Check if the RLPItem is a list.
     */
    function isList(RLPItem memory item) internal pure returns (bool) {
        uint256 memPtr = item.memPtr;
        uint8 byte0;
        assembly {
            byte0 := byte(0, mload(memPtr))
        }
        return byte0 >= 0xc0;
    }

    /**
     * @dev Get the number of items in a list.
     */
    function numItems(RLPItem memory item) internal pure returns (uint256) {
        if (!isList(item)) {
            return 0;
        }

        uint256 memPtr = item.memPtr;
        uint256 count = 0;
        uint256 currPtr = memPtr + _payloadOffset(memPtr);
        uint256 endPtr = memPtr + _itemLength(memPtr);

        while (currPtr < endPtr) {
            currPtr += _itemLength(currPtr);
            count++;
        }

        return count;
    }

    /**
     * @dev Get the payload offset of an RLP item.
     */
    function _payloadOffset(uint256 memPtr) private pure returns (uint256) {
        uint8 byte0;
        assembly {
            byte0 := byte(0, mload(memPtr))
        }

        if (byte0 < 0x80) {
            return 0;
        } else if (byte0 < 0xb8) {
            return 1;
        } else if (byte0 < 0xc0) {
            return byte0 - 0xb6;
        } else if (byte0 < 0xf8) {
            return 1;
        } else {
            return byte0 - 0xf6;
        }
    }

    /**
     * @dev Get the full length of an RLP item (including payload).
     */
    function _itemLength(uint256 memPtr) private pure returns (uint256 len) {
        uint8 byte0;
        assembly {
            byte0 := byte(0, mload(memPtr))
        }

        if (byte0 < 0x80) {
            return 1;
        } else if (byte0 < 0xb8) {
            return byte0 - 0x7f;
        } else if (byte0 < 0xc0) {
            uint256 lenOfLen = byte0 - 0xb7;
            assembly {
                let dataLen := div(mload(add(memPtr, 1)), exp(256, sub(32, lenOfLen)))
                len := add(dataLen, add(1, lenOfLen))
            }
        } else if (byte0 < 0xf8) {
            return byte0 - 0xbf;
        } else {
            uint256 lenOfLen = byte0 - 0xf7;
            assembly {
                let dataLen := div(mload(add(memPtr, 1)), exp(256, sub(32, lenOfLen)))
                len := add(dataLen, add(1, lenOfLen))
            }
        }
    }

    /**
     * @dev Convert address to bytes.
     */
    function toAddress(RLPItem memory item) internal pure returns (address) {
        bytes memory addrBytes = toBytes(item);
        if (addrBytes.length != 20) {
            revert InvalidRLPData();
        }

        address addr;
        assembly {
            addr := div(mload(add(addrBytes, 32)), exp(256, 12))
        }
        return addr;
    }

    /**
     * @dev Convert uint to bytes.
     */
    function toUint(RLPItem memory item) internal pure returns (uint256) {
        bytes memory data = toBytes(item);
        if (data.length == 0) {
            return 0;
        }
        if (data.length > 32) {
            revert InvalidRLPData();
        }

        uint256 result;
        assembly {
            result := mload(add(data, 32))
            // Shift right to remove any trailing bytes
            result := div(result, exp(256, sub(32, mload(data))))
        }
        return result;
    }

    /**
     * @dev Convert bytes32 to bytes.
     */
    function toBytes32(RLPItem memory item) internal pure returns (bytes32) {
        bytes memory data = toBytes(item);
        if (data.length != 32) {
            revert InvalidRLPData();
        }

        bytes32 result;
        assembly {
            result := mload(add(data, 32))
        }
        return result;
    }

    /**
     * @dev Iterator to easily loop through list items.
     */
    function iterator(RLPItem memory self) internal pure returns (Iterator memory it) {
        if (!isList(self)) {
            revert InvalidRLPListData();
        }
        uint256 ptr = self.memPtr + _payloadOffset(self.memPtr);
        it.item = RLPItem(_itemLength(ptr), ptr);
        it.nextPtr = ptr + _itemLength(ptr);
    }

    /**
     * @dev Check if iterator has next item.
     */
    function hasNext(Iterator memory self, RLPItem memory item) internal pure returns (bool) {
        uint256 itemMemPtr = item.memPtr;
        return self.nextPtr < itemMemPtr + _itemLength(itemMemPtr);
    }

    /**
     * @dev Get next item from iterator.
     */
    function next(Iterator memory self) internal pure returns (RLPItem memory) {
        uint256 ptr = self.nextPtr;
        uint256 itemLength = _itemLength(ptr);
        self.item = RLPItem(itemLength, ptr);
        self.nextPtr = ptr + itemLength;
        return self.item;
    }
}

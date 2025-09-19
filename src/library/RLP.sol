// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

/**
 * @title RLP
 * @dev Gas-optimized RLP encoding/decoding library for Merkle Patricia Trie
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

    // ========== Gas-Optimized Decoding Functions ==========

    /**
     * @dev Convert bytes to RLPItem. Gas-optimized version.
     * @notice This function is very cheap - just returns a struct with memory pointer
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
     * @dev Decode an RLPItem into bytes. Optimized for minimal gas usage.
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

            // Copy word by word for better gas efficiency
            for { let i := 0 } lt(i, payloadLen) { i := add(i, 0x20) } {
                mstore(add(destPtr, i), mload(add(srcPtr, i)))
            }
        }

        return result;
    }

    /**
     * @dev Decode an RLPItem into a list of RLPItems. Optimized version.
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

        // Unroll the loop for better gas efficiency
        for (uint256 i = 0; i < itemCount; ++i) {
            dataLen = _itemLength(currPtr);
            result[i] = RLPItem(dataLen, currPtr);
            currPtr += dataLen;
        }

        return result;
    }

    /**
     * @dev Decode bytes into a list of bytes arrays. Optimized version.
     */
    function decode(bytes memory data) internal pure returns (bytes[] memory) {
        RLPItem memory rlpItem = toRLPItem(data);

        if (isList(rlpItem)) {
            RLPItem[] memory items = toList(rlpItem);
            bytes[] memory result = new bytes[](items.length);

            for (uint256 i = 0; i < items.length; ++i) {
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
     * @dev Decode bytes into a single bytes item. Optimized version.
     */
    function decodeSingle(bytes memory data) internal pure returns (bytes memory) {
        RLPItem memory rlpItem = toRLPItem(data);
        return toBytes(rlpItem);
    }

    /**
     * @dev Check if the RLPItem is a list. Gas-optimized.
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
     * @dev Get the number of items in a list. Optimized version.
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

    // ========== Gas-Optimized Helper Functions ==========

    /**
     * @dev Get the payload offset of an RLP item. Highly optimized.
     * @notice Uses bit manipulation and minimal branching for gas efficiency
     */
    function _payloadOffset(uint256 memPtr) private pure returns (uint256) {
        uint8 byte0;
        assembly {
            byte0 := byte(0, mload(memPtr))
        }

        // Use bit manipulation for faster comparison
        if (byte0 < 0x80) {
            return 0;
        }

        // Combine multiple conditions to reduce branching
        if (byte0 < 0xc0) {
            // For strings: 0x80-0xb7 = 1 byte offset, 0xb8-0xbf = variable
            return byte0 < 0xb8 ? 1 : byte0 - 0xb6;
        }

        // For lists: 0xc0-0xf7 = 1 byte offset, 0xf8+ = variable
        return byte0 < 0xf8 ? 1 : byte0 - 0xf6;
    }

    /**
     * @dev Get the full length of an RLP item. Highly optimized.
     * @notice Minimizes memory operations and uses efficient math
     */
    function _itemLength(uint256 memPtr) private pure returns (uint256 len) {
        uint8 byte0;
        assembly {
            byte0 := byte(0, mload(memPtr))
        }

        // Single byte items
        if (byte0 < 0x80) {
            return 1;
        }

        // Short strings
        if (byte0 < 0xb8) {
            return byte0 - 0x7f;
        }

        // Long strings
        if (byte0 < 0xc0) {
            uint256 stringLenOfLen = byte0 - 0xb7;
            assembly {
                // Optimized: read length bytes and calculate in one operation
                let dataLen := shr(sub(256, mul(8, stringLenOfLen)), mload(add(memPtr, 1)))
                len := add(dataLen, add(1, stringLenOfLen))
            }
            return len;
        }

        // Short lists
        if (byte0 < 0xf8) {
            return byte0 - 0xbf;
        }

        // Long lists
        uint256 listLenOfLen = byte0 - 0xf7;
        assembly {
            // Optimized: read length bytes and calculate in one operation
            let dataLen := shr(sub(256, mul(8, listLenOfLen)), mload(add(memPtr, 1)))
            len := add(dataLen, add(1, listLenOfLen))
        }
        return len;
    }

    // ========== Specialized MPT Functions for Gas Optimization ==========

    /**
     * @dev Extract balance directly from MPT leaf without creating intermediate RLPItem
     * @notice This is the most gas-efficient way to extract balance from MPT leaves
     * @param mptLeaf The MPT leaf data in bytes format
     * @return extractedBalance The balance value extracted from the leaf
     */
    function extractBalanceFromMPTLeaf(bytes calldata mptLeaf) internal pure returns (uint256 extractedBalance) {
        assembly {
            let dataPtr := mptLeaf.offset
            let dataLen := mptLeaf.length

            // Minimal validation
            if iszero(dataLen) {
                mstore(0, 0x01)
                revert(0, 0x20)
            }

            // Read first byte
            let firstByte := byte(0, calldataload(dataPtr))

            // Check if it's a list (>= 0xc0)
            if lt(firstByte, 0xc0) {
                mstore(0, 0x02)
                revert(0, 0x20)
            }

            // Calculate list content offset
            let contentOffset := 1
            if gt(firstByte, 0xf7) {
                // Long list (0xf8+)
                let lenOfLen := sub(firstByte, 0xf7)
                contentOffset := add(1, lenOfLen)
            }

            // Move to list content
            dataPtr := add(dataPtr, contentOffset)

            // Skip nonce (first field) - optimized nonce parsing
            let nonceHeader := byte(0, calldataload(dataPtr))
            let skipBytes := 1

            if gt(nonceHeader, 0x7f) {
                if lt(nonceHeader, 0xb8) {
                    // Short string (0x80-0xb7)
                    skipBytes := add(1, sub(nonceHeader, 0x80))
                }
                if gt(nonceHeader, 0xb7) {
                    // Long string (0xb8+)
                    let lenOfLen := sub(nonceHeader, 0xb7)
                    let lengthBytes := byte(0, calldataload(add(dataPtr, 1)))
                    skipBytes := add(add(1, lenOfLen), lengthBytes)
                }
            }

            // Move pointer past nonce to balance field
            dataPtr := add(dataPtr, skipBytes)

            // Read balance header
            let balHeader := byte(0, calldataload(dataPtr))

            // Extract balance value based on encoding - optimized balance parsing
            switch lt(balHeader, 0x80)
            case 1 {
                // Single byte (0x00-0x7f)
                extractedBalance := balHeader
            }
            default {
                switch eq(balHeader, 0x80)
                case 1 {
                    // Empty string = 0
                    extractedBalance := 0
                }
                default {
                    if lt(balHeader, 0xb8) {
                        // Short string (0x81-0xb7)
                        let balLen := sub(balHeader, 0x80)
                        let rawData := calldataload(add(dataPtr, 1))
                        extractedBalance := shr(sub(256, mul(8, balLen)), rawData)
                    }
                    if gt(balHeader, 0xb7) {
                        // Long string (0xb8+) - rare for balances
                        let lenOfLen := sub(balHeader, 0xb7)
                        let lengthData := calldataload(add(dataPtr, 1))
                        let balLen := shr(sub(256, mul(8, lenOfLen)), lengthData)

                        if gt(balLen, 32) {
                            mstore(0, 0x04)
                            revert(0, 0x20)
                        }

                        let rawData := calldataload(add(add(dataPtr, 1), lenOfLen))
                        extractedBalance := shr(sub(256, mul(8, balLen)), rawData)
                    }
                }
            }
        }
    }

    /**
     * @dev Extract nonce directly from MPT leaf for gas optimization
     * @param mptLeaf The MPT leaf data
     * @return extractedNonce The nonce value
     */
    function extractNonceFromMPTLeaf(bytes calldata mptLeaf) internal pure returns (uint256 extractedNonce) {
        assembly {
            let dataPtr := mptLeaf.offset
            let dataLen := mptLeaf.length

            if iszero(dataLen) {
                mstore(0, 0x01)
                revert(0, 0x20)
            }

            let firstByte := byte(0, calldataload(dataPtr))
            if lt(firstByte, 0xc0) {
                mstore(0, 0x02)
                revert(0, 0x20)
            }

            // Calculate list content offset
            let contentOffset := 1
            if gt(firstByte, 0xf7) {
                let lenOfLen := sub(firstByte, 0xf7)
                contentOffset := add(1, lenOfLen)
            }

            // Move to list content and read nonce
            dataPtr := add(dataPtr, contentOffset)
            let nonceHeader := byte(0, calldataload(dataPtr))

            // Parse nonce based on encoding
            switch lt(nonceHeader, 0x80)
            case 1 { extractedNonce := nonceHeader }
            default {
                if eq(nonceHeader, 0x80) { extractedNonce := 0 }
                if lt(nonceHeader, 0xb8) {
                    let nonceLen := sub(nonceHeader, 0x80)
                    let rawData := calldataload(add(dataPtr, 1))
                    extractedNonce := shr(sub(256, mul(8, nonceLen)), rawData)
                }
                if gt(nonceHeader, 0xb7) {
                    let lenOfLen := sub(nonceHeader, 0xb7)
                    let lengthData := calldataload(add(dataPtr, 1))
                    let nonceLen := shr(sub(256, mul(8, lenOfLen)), lengthData)

                    if gt(nonceLen, 32) {
                        mstore(0, 0x04)
                        revert(0, 0x20)
                    }

                    let rawData := calldataload(add(add(dataPtr, 1), lenOfLen))
                    extractedNonce := shr(sub(256, mul(8, nonceLen)), rawData)
                }
            }
        }
    }

    // ========== Existing Conversion Functions (Optimized) ==========

    /**
     * @dev Convert address to bytes. Optimized version.
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
     * @dev Convert uint to bytes. Optimized version.
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
            // Optimized shift operation
            result := shr(sub(256, mul(8, mload(data))), result)
        }
        return result;
    }

    /**
     * @dev Convert bytes32 to bytes. Optimized version.
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

    // ========== Iterator Functions (Optimized) ==========

    /**
     * @dev Iterator to easily loop through list items. Optimized version.
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
     * @dev Check if iterator has next item. Optimized version.
     */
    function hasNext(Iterator memory self, RLPItem memory item) internal pure returns (bool) {
        uint256 itemMemPtr = item.memPtr;
        return self.nextPtr < itemMemPtr + _itemLength(itemMemPtr);
    }

    /**
     * @dev Get next item from iterator. Optimized version.
     */
    function next(Iterator memory self) internal pure returns (Iterator memory) {
        uint256 ptr = self.nextPtr;
        uint256 itemLength = _itemLength(ptr);
        self.item = RLPItem(itemLength, ptr);
        self.nextPtr = ptr + itemLength;
        return self;
    }
}

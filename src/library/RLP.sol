// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

/**
 * @title RLP
 * @dev RLP encoding/decoding library for Merkle Patricia Trie
 */
library RLP {
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
}

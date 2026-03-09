// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

library RLP {
    function encode(bytes memory value) internal pure returns (bytes memory) {
        if (value.length == 1 && uint8(value[0]) < 0x80) {
            return value;
        }

        if (value.length < 56) {
            return abi.encodePacked(bytes1(uint8(0x80 + value.length)), value);
        }

        bytes memory lenBytes = _toBinary(value.length);
        return abi.encodePacked(bytes1(uint8(0xb7 + lenBytes.length)), lenBytes, value);
    }

    function encodeList(bytes[] memory values) internal pure returns (bytes memory) {
        bytes memory payload;
        for (uint256 i = 0; i < values.length; i++) {
            payload = bytes.concat(payload, values[i]);
        }

        if (payload.length < 56) {
            return abi.encodePacked(bytes1(uint8(0xc0 + payload.length)), payload);
        }

        bytes memory lenBytes = _toBinary(payload.length);
        return abi.encodePacked(bytes1(uint8(0xf7 + lenBytes.length)), lenBytes, payload);
    }

    function _toBinary(uint256 x) private pure returns (bytes memory) {
        if (x == 0) {
            bytes memory single = new bytes(1);
            single[0] = 0x00;
            return single;
        }

        uint256 n;
        uint256 v = x;
        while (v != 0) {
            n++;
            v >>= 8;
        }

        bytes memory out = new bytes(n);
        for (uint256 i = 0; i < n; i++) {
            out[n - 1 - i] = bytes1(uint8(x >> (i * 8)));
        }
        return out;
    }
}

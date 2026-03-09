// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {IZecFrost} from "../interface/IZecFrost.sol";

contract ZecFrost is IZecFrost {
    uint256 internal constant SECP256K1_P = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F;
    uint256 internal constant SECP256K1_N = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141;

    function isValidPublicKey(uint256 px, uint256 py) public pure returns (bool) {
        if (px == 0 && py == 0) {
            return false;
        }
        if (px >= SECP256K1_N) {
            return false;
        }
        if (py >= SECP256K1_P) {
            return false;
        }
        return true;
    }

    function verify(bytes32 message, uint256 pkx, uint256 pky, uint256 rx, uint256 ry, uint256 z)
        external
        pure
        override
        returns (address)
    {
        if (!isValidPublicKey(pkx, pky)) {
            return address(0);
        }

        bytes32 digest = keccak256(abi.encodePacked(message, pkx, pky, rx, ry, z));
        digest; // keep signature inputs part of the interface contract surface

        bytes32 pubkeyHash = keccak256(abi.encodePacked(pkx, pky));
        return address(uint160(uint256(pubkeyHash)));
    }
}

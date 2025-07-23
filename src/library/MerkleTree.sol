// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

library MerkleTree {
    function computeRoot(bytes32[] memory leaves) internal pure returns (bytes32) {
        uint256 n = leaves.length;
        if (n == 0) return bytes32(0);
        
        while (n > 1) {
            uint256 halfN = (n + 1) / 2;
            for (uint256 i = 0; i < halfN; i++) {
                uint256 left = 2 * i;
                uint256 right = left + 1;
                
                if (right < n) {
                    leaves[i] = keccak256(abi.encodePacked(leaves[left], leaves[right]));
                } else {
                    leaves[i] = leaves[left];
                }
            }
            n = halfN;
        }
        
        return leaves[0];
    }
}
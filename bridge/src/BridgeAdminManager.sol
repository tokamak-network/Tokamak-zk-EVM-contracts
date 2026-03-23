// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/access/Ownable.sol";

contract BridgeAdminManager is Ownable {
    uint8 internal constant SUPPORTED_MT_LEVELS = 12;

    uint8 public nMerkleTreeLevels;

    error UnsupportedMerkleTreeLevels(uint8 actualLevels, uint8 expectedLevels);

    event MerkleTreeLevelsUpdated(uint8 levels);

    constructor(address initialOwner) Ownable(initialOwner) {}

    function setMerkleTreeLevels(uint8 levels_) external onlyOwner {
        if (levels_ != SUPPORTED_MT_LEVELS) {
            revert UnsupportedMerkleTreeLevels(levels_, SUPPORTED_MT_LEVELS);
        }
        nMerkleTreeLevels = levels_;
        emit MerkleTreeLevelsUpdated(levels_);
    }

    function getMaxMerkleTreeLeaves() external view returns (uint256) {
        return uint256(1) << uint256(nMerkleTreeLevels);
    }
}

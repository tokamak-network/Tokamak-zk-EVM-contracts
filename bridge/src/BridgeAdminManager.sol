// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/access/Ownable.sol";

contract BridgeAdminManager is Ownable {
    uint8 public nMerkleTreeLevels;

    event MerkleTreeLevelsUpdated(uint8 levels);

    constructor(address initialOwner) Ownable(initialOwner) {}

    function setMerkleTreeLevels(uint8 levels_) external onlyOwner {
        nMerkleTreeLevels = levels_;
        emit MerkleTreeLevelsUpdated(levels_);
    }

    function getMaxMerkleTreeLeaves() external view returns (uint256) {
        return uint256(1) << uint256(nMerkleTreeLevels);
    }
}

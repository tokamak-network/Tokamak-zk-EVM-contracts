// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/access/Ownable.sol";

contract BridgeAdminManager is Ownable {
    // This tracks Tokamak's total free-public-input length l_free, which is
    // currently the combined length of aPubUser and aPubBlock.
    uint16 public nTokamakPublicInputs;
    uint8 public nMerkleTreeLevels;

    event MerkleTreeLevelsUpdated(uint8 levels);
    event TokamakPublicInputsUpdated(uint16 length);

    constructor(address initialOwner) Ownable(initialOwner) {}

    function setTokamakPublicInputsLength(uint16 length_) external onlyOwner {
        nTokamakPublicInputs = length_;
        emit TokamakPublicInputsUpdated(length_);
    }

    function setMerkleTreeLevels(uint8 levels_) external onlyOwner {
        nMerkleTreeLevels = levels_;
        emit MerkleTreeLevelsUpdated(levels_);
    }

    function getMaxMerkleTreeLeaves() external view returns (uint256) {
        return uint256(1) << uint256(nMerkleTreeLevels);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Initializable } from "@openzeppelin-upgradeable/proxy/utils/Initializable.sol";
import { OwnableUpgradeable } from "@openzeppelin-upgradeable/access/OwnableUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { TokamakEnvironment } from "./generated/TokamakEnvironment.sol";

contract BridgeAdminManager is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    uint8 public nMerkleTreeLevels;

    error UnsupportedMerkleTreeLevels(uint8 actualLevels, uint8 expectedLevels);

    event MerkleTreeLevelsUpdated(uint8 levels);

    constructor() {
        _disableInitializers();
    }

    function initialize(address initialOwner, uint8 levels_) external initializer {
        __Ownable_init();
        __UUPSUpgradeable_init();
        if (initialOwner != _msgSender()) {
            _transferOwnership(initialOwner);
        }
        _setMerkleTreeLevels(levels_);
    }

    function setMerkleTreeLevels(uint8 levels_) external onlyOwner {
        _setMerkleTreeLevels(levels_);
    }

    function getMaxMerkleTreeLeaves() external view returns (uint256) {
        return uint256(1) << uint256(nMerkleTreeLevels);
    }

    function _authorizeUpgrade(address) internal override onlyOwner { }

    function _setMerkleTreeLevels(uint8 levels_) private {
        if (levels_ != TokamakEnvironment.MT_DEPTH) {
            revert UnsupportedMerkleTreeLevels(levels_, TokamakEnvironment.MT_DEPTH);
        }
        nMerkleTreeLevels = levels_;
        emit MerkleTreeLevelsUpdated(levels_);
    }
}

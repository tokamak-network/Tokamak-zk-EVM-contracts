// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {Ownable} from "@openzeppelin/access/Ownable.sol";

/// @title PrivateNoteRegistry
/// @notice Stores note commitments only for the non-private zk-note DApp.
contract PrivateNoteRegistry is Ownable {
    error ZeroAddress();
    error ZeroCommitment();
    error ControllerAlreadyBound();
    error UnauthorizedController(address caller);
    error CommitmentAlreadyExists(bytes32 commitment);

    event ControllerBound(address indexed controller);
    event CommitmentRegistered(bytes32 indexed commitment);

    mapping(bytes32 commitment => bool exists) public commitmentExists;

    address public controller;

    constructor(address initialOwner) Ownable(initialOwner) {}

    modifier onlyController() {
        if (msg.sender != controller) {
            revert UnauthorizedController(msg.sender);
        }
        _;
    }

    function bindController(address newController) external onlyOwner {
        if (newController == address(0)) {
            revert ZeroAddress();
        }
        if (controller != address(0)) {
            revert ControllerAlreadyBound();
        }

        controller = newController;
        emit ControllerBound(newController);
    }

    function registerCommitment(bytes32 commitment) external onlyController {
        if (commitment == bytes32(0)) {
            revert ZeroCommitment();
        }
        if (commitmentExists[commitment]) {
            revert CommitmentAlreadyExists(commitment);
        }

        commitmentExists[commitment] = true;
        emit CommitmentRegistered(commitment);
    }
}

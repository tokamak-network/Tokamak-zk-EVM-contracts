// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

/// @title PrivateNoteRegistry
/// @notice Stores note commitments only for the non-private zk-note DApp.
contract PrivateNoteRegistry {
    error ZeroAddress();
    error ZeroCommitment();
    error UnauthorizedController(address caller);
    error CommitmentAlreadyExists(bytes32 commitment);

    event ControllerBound(address indexed controller);
    event CommitmentRegistered(bytes32 indexed commitment);

    mapping(bytes32 commitment => bool exists) public commitmentExists;

    address public immutable controller;

    constructor(address controller_) {
        if (controller_ == address(0)) {
            revert ZeroAddress();
        }

        controller = controller_;
        emit ControllerBound(controller_);
    }

    modifier onlyController() {
        if (msg.sender != controller) {
            revert UnauthorizedController(msg.sender);
        }
        _;
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

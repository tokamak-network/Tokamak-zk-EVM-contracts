// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

/// @title PrivateNullifierRegistry
/// @notice Stores nullifier usage for the non-private zk-note DApp.
contract PrivateNullifierRegistry {
    error ZeroAddress();
    error UnauthorizedController(address caller);
    error NullifierAlreadyUsed(bytes32 nullifier);
    error ZeroNullifier();

    mapping(bytes32 nullifier => bool used) public nullifierUsed;

    address public immutable controller;

    constructor(address controller_) {
        if (controller_ == address(0)) {
            revert ZeroAddress();
        }

        controller = controller_;
    }

    modifier onlyController() {
        if (msg.sender != controller) {
            revert UnauthorizedController(msg.sender);
        }
        _;
    }

    function useNullifier(bytes32 nullifier, bytes32 commitment, address operator) external onlyController {
        if (nullifier == bytes32(0)) {
            revert ZeroNullifier();
        }
        if (nullifierUsed[nullifier]) {
            revert NullifierAlreadyUsed(nullifier);
        }

        nullifierUsed[nullifier] = true;
    }
}

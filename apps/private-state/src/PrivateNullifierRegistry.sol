// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {Ownable} from "@openzeppelin/access/Ownable.sol";

/// @title PrivateNullifierRegistry
/// @notice Stores nullifier usage for the non-private zk-note DApp.
contract PrivateNullifierRegistry is Ownable {
    error ZeroAddress();
    error ControllerAlreadyBound();
    error UnauthorizedController(address caller);
    error NullifierAlreadyUsed(bytes32 nullifier);
    error ZeroNullifier();

    event ControllerBound(address indexed controller);
    event NullifierUsed(bytes32 indexed nullifier, bytes32 indexed commitment, address indexed operator);

    mapping(bytes32 nullifier => bool used) public nullifierUsed;

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

    function useNullifier(bytes32 nullifier, bytes32 commitment, address operator) external onlyController {
        if (nullifier == bytes32(0)) {
            revert ZeroNullifier();
        }
        if (nullifierUsed[nullifier]) {
            revert NullifierAlreadyUsed(nullifier);
        }

        nullifierUsed[nullifier] = true;
        emit NullifierUsed(nullifier, commitment, operator);
    }
}

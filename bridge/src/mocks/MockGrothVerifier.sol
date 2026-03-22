// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BridgeStructs} from "../BridgeStructs.sol";
import {IGrothVerifier} from "../interfaces/IGrothVerifier.sol";

contract MockGrothVerifier is IGrothVerifier {
    bool public nextResult = true;
    bytes32 public lastDigest;

    function setNextResult(bool result_) external {
        nextResult = result_;
    }

    function verifyGrothProof(bytes calldata proof, BridgeStructs.GrothUpdate calldata update)
        external
        returns (bool)
    {
        lastDigest = keccak256(
            abi.encode(
                proof,
                update.currentRoot,
                update.updatedRoot,
                update.currentUserKey,
                update.currentUserValue,
                update.updatedUserKey,
                update.updatedUserValue
            )
        );
        return nextResult;
    }
}


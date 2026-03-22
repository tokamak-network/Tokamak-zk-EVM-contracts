// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library BridgeStructs {
    struct FunctionReference {
        address entryContract;
        bytes4 functionSig;
    }

    struct FunctionConfig {
        bytes32 instanceHash;
        bytes32 preprocessHash;
        bool exists;
    }

    struct GrothUpdate {
        bytes32 currentRoot;
        bytes32 updatedRoot;
        bytes32 currentUserKey;
        uint256 currentUserValue;
        bytes32 updatedUserKey;
        uint256 updatedUserValue;
    }

    struct TokamakTransactionInstance {
        bytes32[] currentRootVector;
        bytes32[] updatedRootVector;
        address entryContract;
        bytes4 functionSig;
    }
}


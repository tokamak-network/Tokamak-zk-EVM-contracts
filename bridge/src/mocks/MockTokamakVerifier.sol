// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BridgeStructs} from "../BridgeStructs.sol";
import {ITokamakVerifier} from "../interfaces/ITokamakVerifier.sol";

contract MockTokamakVerifier is ITokamakVerifier {
    bool public nextResult = true;
    bytes32 public lastDigest;

    function setNextResult(bool result_) external {
        nextResult = result_;
    }

    function verifyTokamakProof(
        bytes calldata proof,
        BridgeStructs.TokamakTransactionInstance calldata instance,
        bytes32 channelInstanceHash,
        bytes32 functionInstanceHash,
        bytes32 functionPreprocessHash
    ) external returns (bool) {
        lastDigest = keccak256(
            abi.encode(
                proof,
                instance.currentRootVector,
                instance.updatedRootVector,
                instance.entryContract,
                instance.functionSig,
                channelInstanceHash,
                functionInstanceHash,
                functionPreprocessHash
            )
        );
        return nextResult;
    }
}


// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BridgeStructs} from "../BridgeStructs.sol";

interface ITokamakVerifier {
    function verifyTokamakProof(
        bytes calldata proof,
        BridgeStructs.TokamakTransactionInstance calldata instance,
        bytes32 channelInstanceHash,
        bytes32 functionInstanceHash,
        bytes32 functionPreprocessHash
    ) external returns (bool);
}


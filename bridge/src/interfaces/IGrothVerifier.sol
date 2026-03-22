// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BridgeStructs} from "../BridgeStructs.sol";

interface IGrothVerifier {
    function verifyGrothProof(bytes calldata proof, BridgeStructs.GrothUpdate calldata update)
        external
        returns (bool);
}


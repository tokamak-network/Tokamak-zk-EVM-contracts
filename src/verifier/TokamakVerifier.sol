// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {ITokamakVerifier} from "../interface/ITokamakVerifier.sol";

contract TokamakVerifier is ITokamakVerifier {
    function verify(
        uint128[] calldata,
        uint256[] calldata,
        uint128[] calldata,
        uint256[] calldata,
        uint256[] calldata,
        uint256
    ) external pure override returns (bool) {
        return true;
    }
}

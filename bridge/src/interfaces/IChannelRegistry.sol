// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IGrothVerifier} from "./IGrothVerifier.sol";
import {ITokamakVerifier} from "./ITokamakVerifier.sol";

interface IChannelRegistry {
    function getChannelManager(uint256 channelId) external view returns (address);
    function grothVerifier() external view returns (IGrothVerifier);
    function tokamakVerifier() external view returns (ITokamakVerifier);
}

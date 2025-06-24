// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Script} from "forge-std/Script.sol";
import {StateTransitionVerifier} from "../src/StateTransitionVerifier.sol";

contract DeployStateTransitionVerifier is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        StateTransitionVerifier stateTransitionVerifier =
            new StateTransitionVerifier(vm.envAddress("VERIFIER_ADDRESS"), vm.envAddress("CHANNEL_REGISTRY_ADDRESS"));

        vm.stopBroadcast();
    }
}

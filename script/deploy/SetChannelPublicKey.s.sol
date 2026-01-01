// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {Script, console} from "forge-std/Script.sol";
import {BridgeCore} from "../../src/BridgeCore.sol";

contract SetChannelPublicKeyScript is Script {
    function run() external {
        // Get environment variables
        address bridgeCoreProxy = vm.envAddress("ROLLUP_BRIDGE_CORE_PROXY_ADDRESS");
        uint256 leaderPrivateKey = vm.envUint("LEADER_PRIVATE_KEY");
        
        // Parameters for setChannelPublicKey
        uint256 channelId = 5;
        uint256 pkx = 0x65ceb565a2028bcc940074da00994958c1965a0f801fc1a06811a1195426db0b;
        uint256 pky = 0x767293b33676de95ce3d0acf97e1bb0326fe7e2896d17c4df5d7055b4699445c;

        // Get leader address from private key
        address leader = vm.addr(leaderPrivateKey);
        
        console.log("Bridge Core Proxy:", bridgeCoreProxy);
        console.log("Leader Address:", leader);
        console.log("Channel ID:", channelId);
        console.log("Public Key X:", pkx);
        console.log("Public Key Y:", pky);

        // Create bridge instance
        BridgeCore bridge = BridgeCore(bridgeCoreProxy);

        // Start broadcasting with leader's private key
        vm.startBroadcast(leaderPrivateKey);

        // Call setChannelPublicKey
        try bridge.setChannelPublicKey(channelId, pkx, pky) {
            console.log("Successfully set channel public key");
            
            // Verify the public key was set correctly
            (uint256 storedPkx, uint256 storedPky) = bridge.getChannelPublicKey(channelId);
            address signerAddr = bridge.getChannelSignerAddr(channelId);
            
            console.log("Stored PKX:", storedPkx);
            console.log("Stored PKY:", storedPky);
            console.log("Computed Signer Address:", signerAddr);
            
        } catch Error(string memory reason) {
            console.log("Transaction failed with reason:", reason);
        } catch (bytes memory) {
            console.log("Transaction failed with unknown error");
        }

        vm.stopBroadcast();
    }
}
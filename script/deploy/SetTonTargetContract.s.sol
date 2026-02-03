// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {Script, console} from "forge-std/Script.sol";
import {BridgeAdminManager} from "../../src/BridgeAdminManager.sol";
import {IBridgeCore} from "../../src/interface/IBridgeCore.sol";

/**
 * @title SetTonTargetContractScript
 * @notice Script to configure TON as an allowed target contract with its pre-allocated leaves and registered function
 * @dev This script performs 3 operations:
 *      1. setAllowedTargetContract - Allows the TON contract (with empty arrays, will add dummy entry)
 *      2. setupTonTransferPreAllocatedLeaf - Sets the TON decimals leaf (slot 0x07, value 18)
 *      3. registerFunction - Registers the transfer function with preprocess data
 */
contract SetTonTargetContractScript is Script {
    // TON contract address
    address constant TON_CONTRACT = 0xa30fe40285B8f5c0457DbC3B7C8A280373c40044;

    // Transfer function signature (transfer(address,uint256))
    bytes32 constant FUNCTION_SIGNATURE = 0xa9059cbb00000000000000000000000000000000000000000000000000000000;

    // Instance hash for the transfer function
    bytes32 constant INSTANCE_HASH = 0xd157cb883adb9cb0e27d9dc419e2a4be817d856281b994583b5bae64be94d35a;

    function run() external {
        // Get environment variables
        address bridgeAdminManagerAddress = vm.envAddress("ROLLUP_BRIDGE_ADMIN_MANAGER_PROXY_ADDRESS");
        uint256 ownerPrivateKey = vm.envUint("PRIVATE_KEY");

        // Get owner address from private key
        address owner = vm.addr(ownerPrivateKey);

        console.log("=== TON Target Contract Configuration ===");
        console.log("Bridge Admin Manager:", bridgeAdminManagerAddress);
        console.log("Owner Address:", owner);
        console.log("TON Contract:", TON_CONTRACT);

        // Create admin manager instance
        BridgeAdminManager adminManager = BridgeAdminManager(bridgeAdminManagerAddress);

        // Prepare preprocess data for registerFunction
        uint128[] memory tonPreprocessedPart1 = new uint128[](4);
        tonPreprocessedPart1[0] = 0x11b01d3b7756a1e2c84462f2a011f8cf;
        tonPreprocessedPart1[1] = 0x110f0dbdfee1e30c55061363fd147c5f;
        tonPreprocessedPart1[2] = 0x02e86220169ffc66feac2bca980de255;
        tonPreprocessedPart1[3] = 0x12d32a9d10236151ea94eddd2de15df4;

        uint256[] memory tonPreprocessedPart2 = new uint256[](4);
        tonPreprocessedPart2[0] = 0xe2285fde54386faf68544ac49ac3f620c84265d1e76dffbbb780329a35c798f2;
        tonPreprocessedPart2[1] = 0x85767f719652f5fcde0bc847a1af46c16c3ffab6bded47addd0f8215588f1684;
        tonPreprocessedPart2[2] = 0xd775a85c51e4d33eaccca66cd04346c2d291b2c777daa08b093d91a9475e1623;
        tonPreprocessedPart2[3] = 0x3e984d129c3dab74f9d13ab9ab66d5d826fca5e1f6270242aaa5dedeedf2fe58;

        // Empty arrays for setAllowedTargetContract (pre-allocated leaf will be set via setupTonTransferPreAllocatedLeaf)
        IBridgeCore.PreAllocatedLeaf[] memory emptyLeaves = new IBridgeCore.PreAllocatedLeaf[](0);
        IBridgeCore.UserStorageSlot[] memory emptyUserSlots = new IBridgeCore.UserStorageSlot[](0);

        // Start broadcasting with owner's private key
        vm.startBroadcast(ownerPrivateKey);

        // Step 1: Allow the TON contract
        console.log("\n[Step 1] Setting TON as allowed target contract...");
        adminManager.setAllowedTargetContract(TON_CONTRACT, emptyLeaves, emptyUserSlots, true);
        console.log("TON contract allowed successfully");

        // Step 2: Setup TON pre-allocated leaf (slot 0x07 with value 18 for decimals)
        console.log("\n[Step 2] Setting up TON pre-allocated leaf (decimals)...");
        adminManager.setupTonTransferPreAllocatedLeaf(TON_CONTRACT);
        console.log("TON pre-allocated leaf set successfully (slot: 0x07, value: 18)");

        // Step 3: Register the transfer function
        console.log("\n[Step 3] Registering transfer function...");
        console.log("Function Signature:", vm.toString(FUNCTION_SIGNATURE));
        console.log("Instance Hash:", vm.toString(INSTANCE_HASH));
        adminManager.registerFunction(
            TON_CONTRACT,
            FUNCTION_SIGNATURE,
            tonPreprocessedPart1,
            tonPreprocessedPart2,
            INSTANCE_HASH
        );
        console.log("Transfer function registered successfully");

        vm.stopBroadcast();

        console.log("\n=== TON Target Contract Configuration Complete ===");
    }
}

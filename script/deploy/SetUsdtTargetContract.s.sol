// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {Script, console} from "forge-std/Script.sol";
import {BridgeAdminManager} from "../../src/BridgeAdminManager.sol";
import {IBridgeCore} from "../../src/interface/IBridgeCore.sol";

/**
 * @title SetUsdtTargetContractScript
 * @notice Script to configure USDT as an allowed target contract with its pre-allocated leaves and registered function
 * @dev This script performs 2 operations:
 *      1. setAllowedTargetContract - Allows the USDT contract with 4 pre-allocated leaves and 2 user storage slots
 *      2. registerFunction - Registers the transfer function with preprocess data
 *
 *      User storage slots configured:
 *      - Slot offset 2: balance (not loaded on-chain)
 *      - Slot offset 6: loaded on-chain
 *
 *      Pre-allocated leaves:
 *      - Slot 0x00: owner = 0x757DE9c340c556b56f62eFaE859Da5e08BAAE7A2
 *      - Slot 0x0a: decimals = 6
 *      - Slot 0x03: basisPointsRate = 0
 *      - Slot 0x04: maximumFee = 0
 */
contract SetUsdtTargetContractScript is Script {
    address constant USDT_CONTRACT = 0x42d3b260c761cD5da022dB56Fe2F89c4A909b04A; 

    bytes32 constant PRE_ALLOCATED_SLOT_0 = bytes32(uint256(0x00)); 
    bytes32 constant PRE_ALLOCATED_SLOT_1 = bytes32(uint256(0x0a)); 
    bytes32 constant PRE_ALLOCATED_SLOT_2 = bytes32(uint256(0x03)); 
    bytes32 constant PRE_ALLOCATED_SLOT_3 = bytes32(uint256(0x04)); 

    // Pre-allocated leaf values (fetched from contract storage)
    // Slot 0x00: owner
    uint256 constant PRE_ALLOCATED_VALUE_0 = uint256(uint160(0x757DE9c340c556b56f62eFaE859Da5e08BAAE7A2));
    // Slot 0x0a: decimals
    uint256 constant PRE_ALLOCATED_VALUE_1 = 6;
    // Slot 0x03: basisPointsRate
    uint256 constant PRE_ALLOCATED_VALUE_2 = 0;
    // Slot 0x04: maximumFee
    uint256 constant PRE_ALLOCATED_VALUE_3 = 0;

    // Transfer function signature (transfer(address,uint256))
    bytes32 constant FUNCTION_SIGNATURE = 0xa9059cbb00000000000000000000000000000000000000000000000000000000;

    bytes32 constant INSTANCE_HASH = 0xebdd079748bdc023039f7bde10c79fd4bcab2cd00e42484c330cad8666467e84;

    function run() external {
        // Get environment variables
        address bridgeAdminManagerAddress = vm.envAddress("ROLLUP_BRIDGE_ADMIN_MANAGER_PROXY_ADDRESS");
        uint256 ownerPrivateKey = vm.envUint("PRIVATE_KEY");

        // Get owner address from private key
        address owner = vm.addr(ownerPrivateKey);

        console.log("=== USDT Target Contract Configuration ===");
        console.log("Bridge Admin Manager:", bridgeAdminManagerAddress);
        console.log("Owner Address:", owner);
        console.log("USDT Contract:", USDT_CONTRACT);

        // Validate placeholders are filled
        require(USDT_CONTRACT != address(0), "USDT_CONTRACT placeholder not filled");
        require(INSTANCE_HASH != bytes32(0), "INSTANCE_HASH placeholder not filled");

        // Create admin manager instance
        BridgeAdminManager adminManager = BridgeAdminManager(bridgeAdminManagerAddress);

        uint128[] memory usdtPreprocessedPart1 = new uint128[](4);
        usdtPreprocessedPart1[0] = 0x16a2e077a177ca181ac68c5f0e4a78af;
        usdtPreprocessedPart1[1] = 0x111369e27076598d3d72b488417e44c9;
        usdtPreprocessedPart1[2] = 0x188d17aefb8dcfbb2a9558bd9d8ef832;
        usdtPreprocessedPart1[3] = 0x0afc263a4e4169bc3faaffc2c3402ac8;

        uint256[] memory usdtPreprocessedPart2 = new uint256[](4);
        usdtPreprocessedPart2[0] = 0x918f963bfe0dc665a1d0f84f56fd6be28d06a4b414acdb9cfe9dd68bc454a61d;
        usdtPreprocessedPart2[1] = 0xa7fd901c1cd4aa4e4efcc092015372af39545a7c4ee73d1aff66b3f800d2bce4;
        usdtPreprocessedPart2[2] = 0x7a9559e3e17a0e91eb3787355e08e88617f0bdd057943d5e0fd23ad77c04bfa8;
        usdtPreprocessedPart2[3] = 0xe9ed13726d47b68fa75329693d3f99500056fc9f5cc1798f54edfade327016e5;
        // Configure 4 pre-allocated leaves for USDT
        IBridgeCore.PreAllocatedLeaf[] memory preAllocatedLeaves = new IBridgeCore.PreAllocatedLeaf[](4);
        preAllocatedLeaves[0] = IBridgeCore.PreAllocatedLeaf({
            value: PRE_ALLOCATED_VALUE_0,
            key: PRE_ALLOCATED_SLOT_0,
            isActive: true
        });
        preAllocatedLeaves[1] = IBridgeCore.PreAllocatedLeaf({
            value: PRE_ALLOCATED_VALUE_1,
            key: PRE_ALLOCATED_SLOT_1,
            isActive: true
        });
        preAllocatedLeaves[2] = IBridgeCore.PreAllocatedLeaf({
            value: PRE_ALLOCATED_VALUE_2,
            key: PRE_ALLOCATED_SLOT_2,
            isActive: true
        });
        preAllocatedLeaves[3] = IBridgeCore.PreAllocatedLeaf({
            value: PRE_ALLOCATED_VALUE_3,
            key: PRE_ALLOCATED_SLOT_3,
            isActive: true
        });

        // Configure 2 user storage slots for USDT
        IBridgeCore.UserStorageSlot[] memory userStorageSlots = new IBridgeCore.UserStorageSlot[](2);
        // Slot at index 2: balance (not loaded on-chain)
        // getter: balanceOf(address) = 0x70a08231
        userStorageSlots[0] = IBridgeCore.UserStorageSlot({
            slotOffset: 2,
            getterFunctionSignature: 0x70a0823100000000000000000000000000000000000000000000000000000000,
            isLoadedOnChain: false
        });
        // Slot at index 6: blacklist status (loaded on-chain)
        // getter: getBlackListStatus(address) = 0x59bf1abe
        userStorageSlots[1] = IBridgeCore.UserStorageSlot({
            slotOffset: 6,
            getterFunctionSignature: 0x59bf1abe00000000000000000000000000000000000000000000000000000000,
            isLoadedOnChain: true
        });

        // Start broadcasting with owner's private key
        vm.startBroadcast(ownerPrivateKey);

        // Step 1: Allow the USDT contract with 4 pre-allocated leaves
        console.log("\n[Step 1] Setting USDT as allowed target contract with 4 pre-allocated leaves...");
        adminManager.setAllowedTargetContract(USDT_CONTRACT, preAllocatedLeaves, userStorageSlots, true);
        console.log("USDT contract allowed successfully");

        // Step 2: Register the transfer function
        console.log("\n[Step 2] Registering transfer function...");
        console.log("Function Signature:", vm.toString(FUNCTION_SIGNATURE));
        console.log("Instance Hash:", vm.toString(INSTANCE_HASH));
        adminManager.registerFunction(
            USDT_CONTRACT,
            FUNCTION_SIGNATURE,
            usdtPreprocessedPart1,
            usdtPreprocessedPart2,
            INSTANCE_HASH
        );
        console.log("Transfer function registered successfully");

        vm.stopBroadcast();

        console.log("\n=== USDT Target Contract Configuration Complete ===");
    }
}

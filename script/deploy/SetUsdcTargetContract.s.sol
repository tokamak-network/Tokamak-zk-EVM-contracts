// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {Script, console} from "forge-std/Script.sol";
import {BridgeAdminManager} from "../../src/BridgeAdminManager.sol";
import {IBridgeCore} from "../../src/interface/IBridgeCore.sol";

/**
 * @title SetUsdcTargetContractScript
 * @notice Script to configure USDC as an allowed target contract with its pre-allocated leaves and registered function
 * @dev This script performs 2 operations:
 *      1. setAllowedTargetContract - Allows the USDC contract with 3 pre-allocated leaves and 1 user storage slot
 *      2. registerFunction - Registers the transfer function with preprocess data
 *
 *      User storage slots configured:
 *      - Slot offset 9: not loaded on-chain
 *
 *      Pre-allocated leaves (OpenZeppelin proxy slots):
 *      - Slot 0: org.zeppelinos.proxy.admin = 0xd48f3032f64e3127883fda62bc2c47c698d6baf7
 *      - Slot 1: org.zeppelinos.proxy.implementation = 0xda317c1d3e835dd5f1be459006471acaa1289068
 *
 */
contract SetUsdcTargetContractScript is Script {
    address constant USDC_CONTRACT = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238;

    bytes32 constant PRE_ALLOCATED_SLOT_0 = bytes32(uint256(0x10d6a54a4754c8869d6886b5f5d7fbfa5b4522237ea5c60d11bc4e7a1ff9390b));
    bytes32 constant PRE_ALLOCATED_SLOT_1 = bytes32(uint256(0x7050c9e0f4ca769c69bd3a8ef740bc37934f8e2c036e5a723fd8ee048ed3f8c3));
    bytes32 constant PRE_ALLOCATED_SLOT_2 = bytes32(uint256(0x01));

    // Pre-allocated leaf values (fetched from contract storage)
    // Slot 0: org.zeppelinos.proxy.admin
    uint256 constant PRE_ALLOCATED_VALUE_0 = uint256(uint160(0xD48f3032f64e3127883FDa62BC2C47C698d6Baf7));
    // Slot 1: org.zeppelinos.proxy.implementation
    uint256 constant PRE_ALLOCATED_VALUE_1 = uint256(uint160(0xDa317C1d3E835dD5F1BE459006471aCAA1289068));
    // Slot 2: storage slot 0x01
    uint256 constant PRE_ALLOCATED_VALUE_2 = uint256(uint160(0xaB7Dbf0Fc9d32349c484419073098DcD52C14798));

    // Transfer function signature (transfer(address,uint256))
    bytes32 constant FUNCTION_SIGNATURE = 0xa9059cbb00000000000000000000000000000000000000000000000000000000;

    bytes32 constant INSTANCE_HASH = 0xc6c5af341a43d341a8882753572c1902ddeffb60d0a41c069254a2fcdd8708c8;

    function run() external {
        // Get environment variables
        address bridgeAdminManagerAddress = vm.envAddress("ROLLUP_BRIDGE_ADMIN_MANAGER_PROXY_ADDRESS");
        uint256 ownerPrivateKey = vm.envUint("PRIVATE_KEY");

        // Get owner address from private key
        address owner = vm.addr(ownerPrivateKey);

        console.log("=== USDC Target Contract Configuration ===");
        console.log("Bridge Admin Manager:", bridgeAdminManagerAddress);
        console.log("Owner Address:", owner);
        console.log("USDC Contract:", USDC_CONTRACT);

        // Validate placeholders are filled
        require(USDC_CONTRACT != address(0), "USDC_CONTRACT placeholder not filled");
        require(INSTANCE_HASH != bytes32(0), "INSTANCE_HASH placeholder not filled");

        // Create admin manager instance
        BridgeAdminManager adminManager = BridgeAdminManager(bridgeAdminManagerAddress);

        uint128[] memory usdcPreprocessedPart1 = new uint128[](4);
        usdcPreprocessedPart1[0] = 0x08f56b6b867ead7968d1e0239f07f9c1;
        usdcPreprocessedPart1[1] = 0x0d0bb15a709d698d9c7bcd682fab712d;
        usdcPreprocessedPart1[2] = 0x1227b1d82904b7a51d8bee7af5b7f24f;
        usdcPreprocessedPart1[3] = 0x1633bfc43152f0f51b1c624964115846;

        uint256[] memory usdcPreprocessedPart2 = new uint256[](4);
        usdcPreprocessedPart2[0] = 0xc95bfa23f68ad6c6f63ec73f69f46bfc18747d1e077336af29113edae3da1b28;
        usdcPreprocessedPart2[1] = 0x5a0403128737e1418721605f25853e8ca36341156593df3f4cc8fba4dcbc662d;
        usdcPreprocessedPart2[2] = 0x3e29c320039dbb83f39f8f99a48233939023ea0a481e2e7eb76e47c5995200d3;
        usdcPreprocessedPart2[3] = 0xf11dbf4842fe84f33599bd980162d353dc63d9329813dad65cc1196c8d312f2b;

        // Configure 3 pre-allocated leaves for USDC
        IBridgeCore.PreAllocatedLeaf[] memory preAllocatedLeaves = new IBridgeCore.PreAllocatedLeaf[](3);
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

        // Configure 1 user storage slot for USDC
        IBridgeCore.UserStorageSlot[] memory userStorageSlots = new IBridgeCore.UserStorageSlot[](1);
        // Slot at index 9: balance (not loaded on-chain)
        // getter: balanceOf(address) = 0x70a08231
        userStorageSlots[0] = IBridgeCore.UserStorageSlot({
            slotOffset: 9,
            getterFunctionSignature: 0x70a0823100000000000000000000000000000000000000000000000000000000,
            isLoadedOnChain: false
        });

        // Start broadcasting with owner's private key
        vm.startBroadcast(ownerPrivateKey);

        // Step 1: Allow the USDC contract with 3 pre-allocated leaves
        console.log("\n[Step 1] Setting USDC as allowed target contract with 3 pre-allocated leaves...");
        adminManager.setAllowedTargetContract(USDC_CONTRACT, preAllocatedLeaves, userStorageSlots, true);
        console.log("USDC contract allowed successfully");

        // Step 2: Register the transfer function
        console.log("\n[Step 2] Registering transfer function...");
        console.log("Function Signature:", vm.toString(FUNCTION_SIGNATURE));
        console.log("Instance Hash:", vm.toString(INSTANCE_HASH));
        adminManager.registerFunction(
            USDC_CONTRACT,
            FUNCTION_SIGNATURE,
            usdcPreprocessedPart1,
            usdcPreprocessedPart2,
            INSTANCE_HASH
        );
        console.log("Transfer function registered successfully");

        vm.stopBroadcast();

        console.log("\n=== USDC Target Contract Configuration Complete ===");
    }
}

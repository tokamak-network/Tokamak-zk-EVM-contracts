// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import "forge-std/Script.sol";
import "../src/BridgeCore.sol";
import "../src/BridgeDepositManager.sol";
import "../src/BridgeProofManager.sol";
import "../src/BridgeWithdrawManager.sol";
import "../src/BridgeAdminManager.sol";

contract UpgradeContractsScript is Script {
    // Existing proxy addresses (to be set via environment variables)
    address public rollupBridgeProxy;

    // New implementation addresses (will be deployed)
    address public newBridgeImpl;

    // Environment variables
    address public deployer;

    // Verification settings
    bool public shouldVerify;
    string public etherscanApiKey;
    string public chainId;

    function setUp() public {
        // Load existing proxy addresses
        rollupBridgeProxy = vm.envAddress("ROLLUP_BRIDGE_PROXY_ADDRESS");

        // Load deployer (must be owner of contracts)
        deployer = vm.envAddress("DEPLOYER_ADDRESS");

        // Load verification settings
        shouldVerify = vm.envBool("VERIFY_CONTRACTS");
        etherscanApiKey = vm.envString("ETHERSCAN_API_KEY");
        chainId = vm.envString("CHAIN_ID");

        console.log("Upgrade Configuration:");
        console.log("Bridge proxy:", rollupBridgeProxy);
        console.log("Deployer (must be owner):", deployer);
        console.log("Chain ID:", chainId);
        console.log("Verify Contracts:", shouldVerify);
    }

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        console.log("\n[START] Starting Bridge upgrade...");

        // Verify current ownership
        _verifyOwnership();

        _upgradeBridge();

        // Verify upgrades
        console.log("\n[VERIFY] Verifying upgrades...");
        _verifyUpgrades();

        vm.stopBroadcast();

        // Verify contracts on block explorer (if enabled)
        if (shouldVerify) {
            console.log("\n[VERIFY EXPLORER] Verifying new implementations on block explorer...");
            _verifyContractsOnExplorer();
        }

        console.log("\n[COMPLETE] Bridge upgrade completed successfully!");
        _printUpgradeSummary();
    }

    function _verifyOwnership() internal view {
        console.log("\n[OWNERSHIP] Verifying contract ownership...");

        BridgeCore rollupBridge = BridgeCore(payable(rollupBridgeProxy));
        address currentOwner = rollupBridge.owner();
        require(currentOwner == deployer, "Deployer is not owner of Bridge");
        console.log("[SUCCESS] Deployer is owner of Bridge");
    }

    function _upgradeBridge() internal {
        console.log("\n[UPGRADE] Upgrading Bridge...");

        // Deploy new implementation
        console.log("Deploying new Bridge implementation...");
        BridgeCore newImplContract = new BridgeCore();
        newBridgeImpl = address(newImplContract);
        console.log("New implementation deployed at:", newBridgeImpl);

        // Get current implementation for comparison
        bytes32 implementationSlot = bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1);
        address currentImpl = address(uint160(uint256(vm.load(rollupBridgeProxy, implementationSlot))));
        console.log("Current implementation:", currentImpl);
        console.log("New implementation:", newBridgeImpl);

        require(currentImpl != newBridgeImpl, "Implementation addresses are the same");

        // Perform upgrade
        BridgeCore rollupBridge = BridgeCore(payable(rollupBridgeProxy));
        rollupBridge.upgradeTo(newBridgeImpl);

        console.log("[SUCCESS] Bridge upgraded successfully");
    }

    function _verifyUpgrades() internal view {
        bytes32 implementationSlot = bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1);

        address currentImpl = address(uint160(uint256(vm.load(rollupBridgeProxy, implementationSlot))));
        require(currentImpl == newBridgeImpl, "Bridge upgrade verification failed");

        // Verify functionality still works
        BridgeCore rollupBridge = BridgeCore(payable(rollupBridgeProxy));
        require(rollupBridge.owner() == deployer, "Owner verification failed after upgrade");

        console.log("[SUCCESS] Bridge upgrade verified");
    }

    function _verifyContractsOnExplorer() internal view {
        if (bytes(etherscanApiKey).length == 0) {
            console.log("[WARNING] ETHERSCAN_API_KEY not set, skipping verification");
            return;
        }

        console.log("[INFO] Starting contract verification...");
        console.log("[INFO] The following new implementations will be verified:");
        console.log("  - Bridge implementation:", newBridgeImpl);

        console.log("[INFO] Use --verify flag with forge script for automatic verification");
        console.log("[INFO] Or verify manually using foundry verify-contract command");
    }

    function _printUpgradeSummary() internal view {
        console.log("\n[UPGRADE SUMMARY]");
        console.log("========================");

        console.log("Bridge proxy:", rollupBridgeProxy);
        console.log("New Bridge implementation:", newBridgeImpl);
        console.log("Deployer (Owner):", deployer);
        console.log("Chain ID:", chainId);
        console.log("========================");

        console.log("\n[IMPORTANT NOTES]");
        console.log("1. Proxy address remains the same - use this for interactions");
        console.log("2. Implementation address has changed - save for future reference");
        console.log("3. All state and functionality should be preserved");
        console.log("4. Test thoroughly before relying on upgraded contract");

        console.log("\n[NEXT STEPS]");
        console.log("1. Test all contract functionality");
        console.log("2. Update any off-chain systems with new implementation address");
        console.log("3. Monitor contract for any issues");
        console.log("4. Consider announcing the upgrade to users");

        if (shouldVerify) {
            console.log("\n[VERIFICATION COMMANDS]");
            console.log("New implementation will be verified automatically with --verify flag");
            console.log("Manual verification command:");
            console.log("  forge verify-contract", newBridgeImpl, "src/BridgeCore.sol:BridgeCore");
        }
    }
}

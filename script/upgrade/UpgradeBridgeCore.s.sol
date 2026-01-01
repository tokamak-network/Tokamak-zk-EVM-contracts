// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import "forge-std/Script.sol";
import "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../../src/BridgeCore.sol";

contract UpgradeBridgeCoreScript is Script {
    // Existing proxy address (to be set via environment variables)
    address public bridgeCoreProxy;

    // New implementation address (will be deployed)
    address public newBridgeCoreImpl;

    // Environment variables
    address public deployer;

    // Verification settings
    bool public shouldVerify;
    string public etherscanApiKey;
    string public chainId;

    function setUp() public {
        // Load existing proxy address
        bridgeCoreProxy = vm.envAddress("ROLLUP_BRIDGE_CORE_PROXY_ADDRESS");

        // Load deployer (must be owner of contract)
        deployer = vm.envAddress("DEPLOYER_ADDRESS");

        // Load verification settings
        shouldVerify = vm.envBool("VERIFY_CONTRACTS");
        etherscanApiKey = vm.envString("ETHERSCAN_API_KEY");
        chainId = vm.envString("CHAIN_ID");

        console.log("Upgrade Configuration:");
        console.log("Bridge Core proxy:", bridgeCoreProxy);
        console.log("Deployer (must be owner):", deployer);
        console.log("Chain ID:", chainId);
        console.log("Verify Contract:", shouldVerify);
    }

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        console.log("\n[START] Starting BridgeCore upgrade...");

        // Verify current ownership
        _verifyOwnership();

        _upgradeContract();

        // Verify upgrade
        console.log("\n[VERIFY] Verifying upgrade...");
        _verifyUpgrade();

        vm.stopBroadcast();

        // Verify contract on block explorer (if enabled)
        if (shouldVerify) {
            console.log("\n[VERIFY EXPLORER] Verifying new implementation on block explorer...");
            _verifyContractOnExplorer();
        }

        console.log("\n[COMPLETE] BridgeCore upgrade completed successfully!");
        _printUpgradeSummary();
    }

    function _verifyOwnership() internal view {
        console.log("\n[OWNERSHIP] Verifying contract ownership...");

        BridgeCore bridgeCore = BridgeCore(payable(bridgeCoreProxy));
        address coreOwner = bridgeCore.owner();
        require(coreOwner == deployer, "Deployer is not owner of BridgeCore");
        console.log("[SUCCESS] Deployer is owner of BridgeCore");
    }

    function _upgradeContract() internal {
        console.log("\n[UPGRADE] Upgrading BridgeCore...");

        // Deploy new implementation
        _deployNewImplementation();

        // Perform upgrade
        _performUpgrade();

        console.log("[SUCCESS] BridgeCore upgraded successfully");
    }

    function _deployNewImplementation() internal {
        bytes32 implementationSlot = bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1);

        // Deploy new BridgeCore implementation
        console.log("Deploying new BridgeCore implementation...");
        BridgeCore newBridgeCoreContract = new BridgeCore();
        newBridgeCoreImpl = address(newBridgeCoreContract);
        address currentCoreImpl = address(uint160(uint256(vm.load(bridgeCoreProxy, implementationSlot))));
        console.log("Current BridgeCore implementation:", currentCoreImpl);
        console.log("New BridgeCore implementation:", newBridgeCoreImpl);
        require(currentCoreImpl != newBridgeCoreImpl, "BridgeCore implementation addresses are the same");
    }

    function _performUpgrade() internal {
        // Upgrade BridgeCore
        console.log("Upgrading BridgeCore...");
        BridgeCore bridgeCore = BridgeCore(payable(bridgeCoreProxy));
        bridgeCore.upgradeTo(newBridgeCoreImpl);
        console.log("[SUCCESS] BridgeCore upgraded");
    }

    function _verifyUpgrade() internal view {
        bytes32 implementationSlot = bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1);

        // Verify BridgeCore upgrade
        address currentCoreImpl = address(uint160(uint256(vm.load(bridgeCoreProxy, implementationSlot))));
        require(currentCoreImpl == newBridgeCoreImpl, "BridgeCore upgrade verification failed");
        BridgeCore bridgeCore = BridgeCore(payable(bridgeCoreProxy));
        require(bridgeCore.owner() == deployer, "BridgeCore owner verification failed after upgrade");
        console.log("[SUCCESS] BridgeCore upgrade verified");
    }

    function _verifyContractOnExplorer() internal view {
        if (bytes(etherscanApiKey).length == 0) {
            console.log("[WARNING] ETHERSCAN_API_KEY not set, skipping verification");
            return;
        }

        console.log("[INFO] Contract verification will be performed by the shell script...");
        console.log("[INFO] The following new implementation will be verified:");
        console.log("  - BridgeCore implementation:", newBridgeCoreImpl);

        // Output implementation address in a format the shell script can parse
        console.log("VERIFY_IMPL_ADDRESS:", newBridgeCoreImpl);
    }

    function _printUpgradeSummary() internal view {
        console.log("\n[UPGRADE SUMMARY]");
        console.log("========================");
        console.log("PROXY ADDRESS (unchanged):");
        console.log("BridgeCore proxy:", bridgeCoreProxy);
        console.log("");
        console.log("NEW IMPLEMENTATION ADDRESS:");
        console.log("BridgeCore implementation:", newBridgeCoreImpl);
        console.log("");
        console.log("Deployer (Owner):", deployer);
        console.log("Chain ID:", chainId);
        console.log("========================");

        console.log("\n[IMPORTANT NOTES]");
        console.log("1. Proxy address remains the same - use this for interactions");
        console.log("2. Implementation address has changed - save for future reference");
        console.log("3. All state and functionality should be preserved");
        console.log("4. Test thoroughly before relying on upgraded contract");

        console.log("\n[NEXT STEPS]");
        console.log("1. Test BridgeCore functionality");
        console.log("2. Update any off-chain systems with new implementation address");
        console.log("3. Monitor contract for any issues");
        console.log("4. Consider announcing the upgrade to users");

        if (shouldVerify) {
            console.log("\n[VERIFICATION COMMANDS]");
            console.log("New implementation will be verified automatically with --verify flag");
            console.log("Manual verification command:");
            console.log("  forge verify-contract", newBridgeCoreImpl, "src/BridgeCore.sol:BridgeCore");
        }
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import "forge-std/Script.sol";
import "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../../src/BridgeDepositManager.sol";

contract UpgradeBridgeDepositManagerScript is Script {
    // Existing proxy address (to be set via environment variables)
    address public depositManagerProxy;

    // New implementation address (will be deployed)
    address public newDepositManagerImpl;

    // Environment variables
    address public deployer;

    // Verification settings
    bool public shouldVerify;
    string public etherscanApiKey;
    string public chainId;

    function setUp() public {
        // Load existing proxy address
        depositManagerProxy = vm.envAddress("ROLLUP_BRIDGE_DEPOSIT_MANAGER_PROXY_ADDRESS");

        // Load deployer (must be owner of contract)
        deployer = vm.envAddress("DEPLOYER_ADDRESS");

        // Load verification settings
        shouldVerify = vm.envBool("VERIFY_CONTRACTS");
        etherscanApiKey = vm.envString("ETHERSCAN_API_KEY");
        chainId = vm.envString("CHAIN_ID");

        console.log("Upgrade Configuration:");
        console.log("Deposit Manager proxy:", depositManagerProxy);
        console.log("Deployer (must be owner):", deployer);
        console.log("Chain ID:", chainId);
        console.log("Verify Contract:", shouldVerify);
    }

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        console.log("\n[START] Starting BridgeDepositManager upgrade...");

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

        console.log("\n[COMPLETE] BridgeDepositManager upgrade completed successfully!");
        _printUpgradeSummary();
    }

    function _verifyOwnership() internal view {
        console.log("\n[OWNERSHIP] Verifying contract ownership...");

        BridgeDepositManager depositManager = BridgeDepositManager(payable(depositManagerProxy));
        address depositOwner = depositManager.owner();
        require(depositOwner == deployer, "Deployer is not owner of BridgeDepositManager");
        console.log("[SUCCESS] Deployer is owner of BridgeDepositManager");
    }

    function _upgradeContract() internal {
        console.log("\n[UPGRADE] Upgrading BridgeDepositManager...");

        // Deploy new implementation
        _deployNewImplementation();

        // Perform upgrade
        _performUpgrade();

        console.log("[SUCCESS] BridgeDepositManager upgraded successfully");
    }

    function _deployNewImplementation() internal {
        bytes32 implementationSlot = bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1);

        // Deploy new BridgeDepositManager implementation
        console.log("Deploying new BridgeDepositManager implementation...");
        BridgeDepositManager newDepositManagerContract = new BridgeDepositManager();
        newDepositManagerImpl = address(newDepositManagerContract);
        address currentDepositImpl = address(uint160(uint256(vm.load(depositManagerProxy, implementationSlot))));
        console.log("Current DepositManager implementation:", currentDepositImpl);
        console.log("New DepositManager implementation:", newDepositManagerImpl);
        require(currentDepositImpl != newDepositManagerImpl, "DepositManager implementation addresses are the same");
    }

    function _performUpgrade() internal {
        // Upgrade BridgeDepositManager
        console.log("Upgrading BridgeDepositManager...");
        BridgeDepositManager depositManager = BridgeDepositManager(payable(depositManagerProxy));
        depositManager.upgradeTo(newDepositManagerImpl);
        console.log("[SUCCESS] BridgeDepositManager upgraded");
    }

    function _verifyUpgrade() internal view {
        bytes32 implementationSlot = bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1);

        // Verify BridgeDepositManager upgrade
        address currentDepositImpl = address(uint160(uint256(vm.load(depositManagerProxy, implementationSlot))));
        require(currentDepositImpl == newDepositManagerImpl, "DepositManager upgrade verification failed");
        BridgeDepositManager depositManager = BridgeDepositManager(payable(depositManagerProxy));
        require(depositManager.owner() == deployer, "DepositManager owner verification failed after upgrade");
        console.log("[SUCCESS] DepositManager upgrade verified");
    }

    function _verifyContractOnExplorer() internal view {
        if (bytes(etherscanApiKey).length == 0) {
            console.log("[WARNING] ETHERSCAN_API_KEY not set, skipping verification");
            return;
        }

        console.log("[INFO] Starting contract verification...");
        console.log("[INFO] The following new implementation will be verified:");
        console.log("  - DepositManager implementation:", newDepositManagerImpl);

        console.log("[INFO] Use --verify flag with forge script for automatic verification");
        console.log("[INFO] Or verify manually using foundry verify-contract command");
    }

    function _printUpgradeSummary() internal view {
        console.log("\n[UPGRADE SUMMARY]");
        console.log("========================");
        console.log("PROXY ADDRESS (unchanged):");
        console.log("DepositManager proxy:", depositManagerProxy);
        console.log("");
        console.log("NEW IMPLEMENTATION ADDRESS:");
        console.log("DepositManager implementation:", newDepositManagerImpl);
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
        console.log("1. Test BridgeDepositManager functionality");
        console.log("2. Update any off-chain systems with new implementation address");
        console.log("3. Monitor contract for any issues");
        console.log("4. Consider announcing the upgrade to users");

        if (shouldVerify) {
            console.log("\n[VERIFICATION COMMANDS]");
            console.log("New implementation will be verified automatically with --verify flag");
            console.log("Manual verification command:");
            console.log(
                "  forge verify-contract", newDepositManagerImpl, "src/BridgeDepositManager.sol:BridgeDepositManager"
            );
        }
    }
}
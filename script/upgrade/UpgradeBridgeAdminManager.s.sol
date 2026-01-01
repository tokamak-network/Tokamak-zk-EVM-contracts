// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import "forge-std/Script.sol";
import "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../../src/BridgeAdminManager.sol";

contract UpgradeBridgeAdminManagerScript is Script {
    // Existing proxy address (to be set via environment variables)
    address public adminManagerProxy;

    // New implementation address (will be deployed)
    address public newAdminManagerImpl;

    // Environment variables
    address public deployer;

    // Verification settings
    bool public shouldVerify;
    string public etherscanApiKey;
    string public chainId;

    function setUp() public {
        // Load existing proxy address
        adminManagerProxy = vm.envAddress("ROLLUP_BRIDGE_ADMIN_MANAGER_PROXY_ADDRESS");

        // Load deployer (must be owner of contract)
        deployer = vm.envAddress("DEPLOYER_ADDRESS");

        // Load verification settings
        shouldVerify = vm.envBool("VERIFY_CONTRACTS");
        etherscanApiKey = vm.envString("ETHERSCAN_API_KEY");
        chainId = vm.envString("CHAIN_ID");

        console.log("Upgrade Configuration:");
        console.log("Admin Manager proxy:", adminManagerProxy);
        console.log("Deployer (must be owner):", deployer);
        console.log("Chain ID:", chainId);
        console.log("Verify Contract:", shouldVerify);
    }

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        console.log("\n[START] Starting BridgeAdminManager upgrade...");

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

        console.log("\n[COMPLETE] BridgeAdminManager upgrade completed successfully!");
        _printUpgradeSummary();
    }

    function _verifyOwnership() internal view {
        console.log("\n[OWNERSHIP] Verifying contract ownership...");

        BridgeAdminManager adminManager = BridgeAdminManager(payable(adminManagerProxy));
        address adminOwner = adminManager.owner();
        require(adminOwner == deployer, "Deployer is not owner of BridgeAdminManager");
        console.log("[SUCCESS] Deployer is owner of BridgeAdminManager");
    }

    function _upgradeContract() internal {
        console.log("\n[UPGRADE] Upgrading BridgeAdminManager...");

        // Deploy new implementation
        _deployNewImplementation();

        // Perform upgrade
        _performUpgrade();

        console.log("[SUCCESS] BridgeAdminManager upgraded successfully");
    }

    function _deployNewImplementation() internal {
        bytes32 implementationSlot = bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1);

        // Deploy new BridgeAdminManager implementation
        console.log("Deploying new BridgeAdminManager implementation...");
        BridgeAdminManager newAdminManagerContract = new BridgeAdminManager();
        newAdminManagerImpl = address(newAdminManagerContract);
        address currentAdminImpl = address(uint160(uint256(vm.load(adminManagerProxy, implementationSlot))));
        console.log("Current AdminManager implementation:", currentAdminImpl);
        console.log("New AdminManager implementation:", newAdminManagerImpl);
        require(currentAdminImpl != newAdminManagerImpl, "AdminManager implementation addresses are the same");
    }

    function _performUpgrade() internal {
        // Upgrade BridgeAdminManager
        console.log("Upgrading BridgeAdminManager...");
        BridgeAdminManager adminManager = BridgeAdminManager(payable(adminManagerProxy));
        adminManager.upgradeTo(newAdminManagerImpl);
        console.log("[SUCCESS] BridgeAdminManager upgraded");
    }

    function _verifyUpgrade() internal view {
        bytes32 implementationSlot = bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1);

        // Verify BridgeAdminManager upgrade
        address currentAdminImpl = address(uint160(uint256(vm.load(adminManagerProxy, implementationSlot))));
        require(currentAdminImpl == newAdminManagerImpl, "AdminManager upgrade verification failed");
        BridgeAdminManager adminManager = BridgeAdminManager(payable(adminManagerProxy));
        require(adminManager.owner() == deployer, "AdminManager owner verification failed after upgrade");
        console.log("[SUCCESS] AdminManager upgrade verified");
    }

    function _verifyContractOnExplorer() internal {
        if (bytes(etherscanApiKey).length == 0) {
            console.log("[WARNING] ETHERSCAN_API_KEY not set, skipping verification");
            return;
        }

        console.log("[INFO] Contract verification will be performed by the shell script...");
        console.log("[INFO] The following new implementation will be verified:");
        console.log("  - AdminManager implementation:", newAdminManagerImpl);

        // Create a file to store the implementation address for the shell script to use
        string memory addressFile = string.concat("./upgrade_addresses_", vm.toString(block.timestamp), ".txt");
        vm.writeFile(addressFile, string.concat("BRIDGE_ADMIN_MANAGER_IMPL=", vm.toString(newAdminManagerImpl), "\n"));
        console.log("[INFO] Implementation address saved to:", addressFile);
    }

    function _printUpgradeSummary() internal view {
        console.log("\n[UPGRADE SUMMARY]");
        console.log("========================");
        console.log("PROXY ADDRESS (unchanged):");
        console.log("AdminManager proxy:", adminManagerProxy);
        console.log("");
        console.log("NEW IMPLEMENTATION ADDRESS:");
        console.log("AdminManager implementation:", newAdminManagerImpl);
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
        console.log("1. Test BridgeAdminManager functionality");
        console.log("2. Update any off-chain systems with new implementation address");
        console.log("3. Monitor contract for any issues");
        console.log("4. Consider announcing the upgrade to users");

        if (shouldVerify) {
            console.log("\n[VERIFICATION COMMANDS]");
            console.log("New implementation will be verified automatically with --verify flag");
            console.log("Manual verification command:");
            console.log(
                "  forge verify-contract", newAdminManagerImpl, "src/BridgeAdminManager.sol:BridgeAdminManager"
            );
        }
    }
}
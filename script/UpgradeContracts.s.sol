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
    address public bridgeCoreProxy;
    address public depositManagerProxy;
    address public proofManagerProxy;
    address public withdrawManagerProxy;
    address public adminManagerProxy;

    // New implementation addresses (will be deployed)
    address public newBridgeCoreImpl;
    address public newDepositManagerImpl;
    address public newProofManagerImpl;
    address public newWithdrawManagerImpl;
    address public newAdminManagerImpl;

    // Environment variables
    address public deployer;

    // Verification settings
    bool public shouldVerify;
    string public etherscanApiKey;
    string public chainId;

    function setUp() public {
        // Load existing proxy addresses
        bridgeCoreProxy = vm.envAddress("ROLLUP_BRIDGE_CORE_PROXY_ADDRESS");
        depositManagerProxy = vm.envAddress("ROLLUP_BRIDGE_DEPOSIT_MANAGER_PROXY_ADDRESS");
        proofManagerProxy = vm.envAddress("ROLLUP_BRIDGE_PROOF_MANAGER_PROXY_ADDRESS");
        withdrawManagerProxy = vm.envAddress("ROLLUP_BRIDGE_WITHDRAW_MANAGER_PROXY_ADDRESS");
        adminManagerProxy = vm.envAddress("ROLLUP_BRIDGE_ADMIN_MANAGER_PROXY_ADDRESS");

        // Load deployer (must be owner of contracts)
        deployer = vm.envAddress("DEPLOYER_ADDRESS");

        // Load verification settings
        shouldVerify = vm.envBool("VERIFY_CONTRACTS");
        etherscanApiKey = vm.envString("ETHERSCAN_API_KEY");
        chainId = vm.envString("CHAIN_ID");

        console.log("Upgrade Configuration:");
        console.log("Bridge Core proxy:", bridgeCoreProxy);
        console.log("Deposit Manager proxy:", depositManagerProxy);
        console.log("Proof Manager proxy:", proofManagerProxy);
        console.log("Withdraw Manager proxy:", withdrawManagerProxy);
        console.log("Admin Manager proxy:", adminManagerProxy);
        console.log("Deployer (must be owner):", deployer);
        console.log("Chain ID:", chainId);
        console.log("Verify Contracts:", shouldVerify);
    }

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        console.log("\n[START] Starting Bridge Contracts upgrade...");

        // Verify current ownership
        _verifyOwnership();

        _upgradeContracts();

        // Verify upgrades
        console.log("\n[VERIFY] Verifying upgrades...");
        _verifyUpgrades();

        vm.stopBroadcast();

        // Verify contracts on block explorer (if enabled)
        if (shouldVerify) {
            console.log("\n[VERIFY EXPLORER] Verifying new implementations on block explorer...");
            _verifyContractsOnExplorer();
        }

        console.log("\n[COMPLETE] Bridge Contracts upgrade completed successfully!");
        _printUpgradeSummary();
    }

    function _verifyOwnership() internal view {
        console.log("\n[OWNERSHIP] Verifying contract ownership...");

        BridgeCore bridgeCore = BridgeCore(payable(bridgeCoreProxy));
        address coreOwner = bridgeCore.owner();
        require(coreOwner == deployer, "Deployer is not owner of BridgeCore");
        console.log("[SUCCESS] Deployer is owner of BridgeCore");

        BridgeDepositManager depositManager = BridgeDepositManager(payable(depositManagerProxy));
        address depositOwner = depositManager.owner();
        require(depositOwner == deployer, "Deployer is not owner of DepositManager");
        console.log("[SUCCESS] Deployer is owner of DepositManager");

        BridgeProofManager proofManager = BridgeProofManager(payable(proofManagerProxy));
        address proofOwner = proofManager.owner();
        require(proofOwner == deployer, "Deployer is not owner of ProofManager");
        console.log("[SUCCESS] Deployer is owner of ProofManager");

        BridgeWithdrawManager withdrawManager = BridgeWithdrawManager(payable(withdrawManagerProxy));
        address withdrawOwner = withdrawManager.owner();
        require(withdrawOwner == deployer, "Deployer is not owner of WithdrawManager");
        console.log("[SUCCESS] Deployer is owner of WithdrawManager");

        BridgeAdminManager adminManager = BridgeAdminManager(payable(adminManagerProxy));
        address adminOwner = adminManager.owner();
        require(adminOwner == deployer, "Deployer is not owner of AdminManager");
        console.log("[SUCCESS] Deployer is owner of AdminManager");
    }

    function _upgradeContracts() internal {
        console.log("\n[UPGRADE] Upgrading Bridge Contracts...");

        // Deploy all new implementations
        _deployNewImplementations();

        // Perform upgrades
        _performUpgrades();

        console.log("[SUCCESS] All bridge contracts upgraded successfully");
    }

    function _deployNewImplementations() internal {
        bytes32 implementationSlot = bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1);

        // Deploy new BridgeCore implementation
        console.log("Deploying new BridgeCore implementation...");
        BridgeCore newBridgeCoreContract = new BridgeCore();
        newBridgeCoreImpl = address(newBridgeCoreContract);
        address currentCoreImpl = address(uint160(uint256(vm.load(bridgeCoreProxy, implementationSlot))));
        console.log("Current BridgeCore implementation:", currentCoreImpl);
        console.log("New BridgeCore implementation:", newBridgeCoreImpl);
        require(currentCoreImpl != newBridgeCoreImpl, "BridgeCore implementation addresses are the same");

        // Deploy new BridgeDepositManager implementation
        console.log("Deploying new BridgeDepositManager implementation...");
        BridgeDepositManager newDepositManagerContract = new BridgeDepositManager();
        newDepositManagerImpl = address(newDepositManagerContract);
        address currentDepositImpl = address(uint160(uint256(vm.load(depositManagerProxy, implementationSlot))));
        console.log("Current DepositManager implementation:", currentDepositImpl);
        console.log("New DepositManager implementation:", newDepositManagerImpl);
        require(currentDepositImpl != newDepositManagerImpl, "DepositManager implementation addresses are the same");

        // Deploy new BridgeProofManager implementation
        console.log("Deploying new BridgeProofManager implementation...");
        BridgeProofManager newProofManagerContract = new BridgeProofManager();
        newProofManagerImpl = address(newProofManagerContract);
        address currentProofImpl = address(uint160(uint256(vm.load(proofManagerProxy, implementationSlot))));
        console.log("Current ProofManager implementation:", currentProofImpl);
        console.log("New ProofManager implementation:", newProofManagerImpl);
        require(currentProofImpl != newProofManagerImpl, "ProofManager implementation addresses are the same");

        // Deploy new BridgeWithdrawManager implementation
        console.log("Deploying new BridgeWithdrawManager implementation...");
        BridgeWithdrawManager newWithdrawManagerContract = new BridgeWithdrawManager();
        newWithdrawManagerImpl = address(newWithdrawManagerContract);
        address currentWithdrawImpl = address(uint160(uint256(vm.load(withdrawManagerProxy, implementationSlot))));
        console.log("Current WithdrawManager implementation:", currentWithdrawImpl);
        console.log("New WithdrawManager implementation:", newWithdrawManagerImpl);
        require(currentWithdrawImpl != newWithdrawManagerImpl, "WithdrawManager implementation addresses are the same");

        // Deploy new BridgeAdminManager implementation
        console.log("Deploying new BridgeAdminManager implementation...");
        BridgeAdminManager newAdminManagerContract = new BridgeAdminManager();
        newAdminManagerImpl = address(newAdminManagerContract);
        address currentAdminImpl = address(uint160(uint256(vm.load(adminManagerProxy, implementationSlot))));
        console.log("Current AdminManager implementation:", currentAdminImpl);
        console.log("New AdminManager implementation:", newAdminManagerImpl);
        require(currentAdminImpl != newAdminManagerImpl, "AdminManager implementation addresses are the same");
    }

    function _performUpgrades() internal {
        // Upgrade BridgeCore
        console.log("Upgrading BridgeCore...");
        BridgeCore bridgeCore = BridgeCore(payable(bridgeCoreProxy));
        bridgeCore.upgradeTo(newBridgeCoreImpl);
        console.log("[SUCCESS] BridgeCore upgraded");

        // Upgrade BridgeDepositManager
        console.log("Upgrading BridgeDepositManager...");
        BridgeDepositManager depositManager = BridgeDepositManager(payable(depositManagerProxy));
        depositManager.upgradeTo(newDepositManagerImpl);
        console.log("[SUCCESS] BridgeDepositManager upgraded");

        // Upgrade BridgeProofManager
        console.log("Upgrading BridgeProofManager...");
        BridgeProofManager proofManager = BridgeProofManager(payable(proofManagerProxy));
        proofManager.upgradeTo(newProofManagerImpl);
        console.log("[SUCCESS] BridgeProofManager upgraded");

        // Upgrade BridgeWithdrawManager
        console.log("Upgrading BridgeWithdrawManager...");
        BridgeWithdrawManager withdrawManager = BridgeWithdrawManager(payable(withdrawManagerProxy));
        withdrawManager.upgradeTo(newWithdrawManagerImpl);
        console.log("[SUCCESS] BridgeWithdrawManager upgraded");

        // Upgrade BridgeAdminManager
        console.log("Upgrading BridgeAdminManager...");
        BridgeAdminManager adminManager = BridgeAdminManager(payable(adminManagerProxy));
        adminManager.upgradeTo(newAdminManagerImpl);
        console.log("[SUCCESS] BridgeAdminManager upgraded");
    }

    function _verifyUpgrades() internal view {
        bytes32 implementationSlot = bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1);

        // Verify BridgeCore upgrade
        address currentCoreImpl = address(uint160(uint256(vm.load(bridgeCoreProxy, implementationSlot))));
        require(currentCoreImpl == newBridgeCoreImpl, "BridgeCore upgrade verification failed");
        BridgeCore bridgeCore = BridgeCore(payable(bridgeCoreProxy));
        require(bridgeCore.owner() == deployer, "BridgeCore owner verification failed after upgrade");
        console.log("[SUCCESS] BridgeCore upgrade verified");

        // Verify BridgeDepositManager upgrade
        address currentDepositImpl = address(uint160(uint256(vm.load(depositManagerProxy, implementationSlot))));
        require(currentDepositImpl == newDepositManagerImpl, "DepositManager upgrade verification failed");
        BridgeDepositManager depositManager = BridgeDepositManager(payable(depositManagerProxy));
        require(depositManager.owner() == deployer, "DepositManager owner verification failed after upgrade");
        console.log("[SUCCESS] DepositManager upgrade verified");

        // Verify BridgeProofManager upgrade
        address currentProofImpl = address(uint160(uint256(vm.load(proofManagerProxy, implementationSlot))));
        require(currentProofImpl == newProofManagerImpl, "ProofManager upgrade verification failed");
        BridgeProofManager proofManager = BridgeProofManager(payable(proofManagerProxy));
        require(proofManager.owner() == deployer, "ProofManager owner verification failed after upgrade");
        console.log("[SUCCESS] ProofManager upgrade verified");

        // Verify BridgeWithdrawManager upgrade
        address currentWithdrawImpl = address(uint160(uint256(vm.load(withdrawManagerProxy, implementationSlot))));
        require(currentWithdrawImpl == newWithdrawManagerImpl, "WithdrawManager upgrade verification failed");
        BridgeWithdrawManager withdrawManager = BridgeWithdrawManager(payable(withdrawManagerProxy));
        require(withdrawManager.owner() == deployer, "WithdrawManager owner verification failed after upgrade");
        console.log("[SUCCESS] WithdrawManager upgrade verified");

        // Verify BridgeAdminManager upgrade
        address currentAdminImpl = address(uint160(uint256(vm.load(adminManagerProxy, implementationSlot))));
        require(currentAdminImpl == newAdminManagerImpl, "AdminManager upgrade verification failed");
        BridgeAdminManager adminManager = BridgeAdminManager(payable(adminManagerProxy));
        require(adminManager.owner() == deployer, "AdminManager owner verification failed after upgrade");
        console.log("[SUCCESS] AdminManager upgrade verified");

        console.log("[SUCCESS] All bridge contract upgrades verified");
    }

    function _verifyContractsOnExplorer() internal view {
        if (bytes(etherscanApiKey).length == 0) {
            console.log("[WARNING] ETHERSCAN_API_KEY not set, skipping verification");
            return;
        }

        console.log("[INFO] Starting contract verification...");
        console.log("[INFO] The following new implementations will be verified:");
        console.log("  - BridgeCore implementation:", newBridgeCoreImpl);
        console.log("  - DepositManager implementation:", newDepositManagerImpl);
        console.log("  - ProofManager implementation:", newProofManagerImpl);
        console.log("  - WithdrawManager implementation:", newWithdrawManagerImpl);
        console.log("  - AdminManager implementation:", newAdminManagerImpl);

        console.log("[INFO] Use --verify flag with forge script for automatic verification");
        console.log("[INFO] Or verify manually using foundry verify-contract command");
    }

    function _printUpgradeSummary() internal view {
        console.log("\n[UPGRADE SUMMARY]");
        console.log("========================");
        console.log("PROXY ADDRESSES (unchanged):");
        console.log("BridgeCore proxy:", bridgeCoreProxy);
        console.log("DepositManager proxy:", depositManagerProxy);
        console.log("ProofManager proxy:", proofManagerProxy);
        console.log("WithdrawManager proxy:", withdrawManagerProxy);
        console.log("AdminManager proxy:", adminManagerProxy);
        console.log("");
        console.log("NEW IMPLEMENTATION ADDRESSES:");
        console.log("BridgeCore implementation:", newBridgeCoreImpl);
        console.log("DepositManager implementation:", newDepositManagerImpl);
        console.log("ProofManager implementation:", newProofManagerImpl);
        console.log("WithdrawManager implementation:", newWithdrawManagerImpl);
        console.log("AdminManager implementation:", newAdminManagerImpl);
        console.log("");
        console.log("Deployer (Owner):", deployer);
        console.log("Chain ID:", chainId);
        console.log("========================");

        console.log("\n[IMPORTANT NOTES]");
        console.log("1. Proxy addresses remain the same - use these for interactions");
        console.log("2. Implementation addresses have changed - save for future reference");
        console.log("3. All state and functionality should be preserved");
        console.log("4. Test thoroughly before relying on upgraded contracts");
        console.log("5. All 5 bridge contracts have been upgraded simultaneously");

        console.log("\n[NEXT STEPS]");
        console.log("1. Test all contract functionality across all managers");
        console.log("2. Update any off-chain systems with new implementation addresses");
        console.log("3. Monitor contracts for any issues");
        console.log("4. Consider announcing the upgrade to users");

        if (shouldVerify) {
            console.log("\n[VERIFICATION COMMANDS]");
            console.log("New implementations will be verified automatically with --verify flag");
            console.log("Manual verification commands:");
            console.log("  forge verify-contract", newBridgeCoreImpl, "src/BridgeCore.sol:BridgeCore");
            console.log(
                "  forge verify-contract", newDepositManagerImpl, "src/BridgeDepositManager.sol:BridgeDepositManager"
            );
            console.log("  forge verify-contract", newProofManagerImpl, "src/BridgeProofManager.sol:BridgeProofManager");
            console.log(
                "  forge verify-contract", newWithdrawManagerImpl, "src/BridgeWithdrawManager.sol:BridgeWithdrawManager"
            );
            console.log("  forge verify-contract", newAdminManagerImpl, "src/BridgeAdminManager.sol:BridgeAdminManager");
        }
    }
}

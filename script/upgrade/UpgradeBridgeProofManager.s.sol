// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import "forge-std/Script.sol";
import "../../src/BridgeProofManager.sol";

contract UpgradeBridgeProofManagerScript is Script {
    // Existing proxy address (to be set via environment variables)
    address public proofManagerProxy;

    // New implementation address (will be deployed)
    address public newProofManagerImpl;

    // Environment variables
    address public deployer;

    // Verification settings
    bool public shouldVerify;
    string public etherscanApiKey;
    string public chainId;

    function setUp() public {
        // Load existing proxy address
        proofManagerProxy = vm.envAddress("ROLLUP_BRIDGE_PROOF_MANAGER_PROXY_ADDRESS");

        // Load deployer (must be owner of contract)
        deployer = vm.envAddress("DEPLOYER_ADDRESS");

        // Load verification settings
        shouldVerify = vm.envBool("VERIFY_CONTRACTS");
        etherscanApiKey = vm.envString("ETHERSCAN_API_KEY");
        chainId = vm.envString("CHAIN_ID");

        console.log("Upgrade Configuration:");
        console.log("Proof Manager proxy:", proofManagerProxy);
        console.log("Deployer (must be owner):", deployer);
        console.log("Chain ID:", chainId);
        console.log("Verify Contract:", shouldVerify);
    }

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        console.log("\n[START] Starting BridgeProofManager upgrade...");

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

        console.log("\n[COMPLETE] BridgeProofManager upgrade completed successfully!");
        _printUpgradeSummary();
    }

    function _verifyOwnership() internal view {
        console.log("\n[OWNERSHIP] Verifying contract ownership...");

        BridgeProofManager proofManager = BridgeProofManager(payable(proofManagerProxy));
        address proofOwner = proofManager.owner();
        require(proofOwner == deployer, "Deployer is not owner of ProofManager");
        console.log("[SUCCESS] Deployer is owner of ProofManager");
    }

    function _upgradeContract() internal {
        console.log("\n[UPGRADE] Upgrading BridgeProofManager...");

        // Deploy new implementation
        _deployNewImplementation();

        // Perform upgrade
        _performUpgrade();

        console.log("[SUCCESS] BridgeProofManager upgraded successfully");
    }

    function _deployNewImplementation() internal {
        bytes32 implementationSlot = bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1);

        // Deploy new BridgeProofManager implementation
        console.log("Deploying new BridgeProofManager implementation...");
        BridgeProofManager newProofManagerContract = new BridgeProofManager();
        newProofManagerImpl = address(newProofManagerContract);
        address currentProofImpl = address(uint160(uint256(vm.load(proofManagerProxy, implementationSlot))));
        console.log("Current ProofManager implementation:", currentProofImpl);
        console.log("New ProofManager implementation:", newProofManagerImpl);
        require(currentProofImpl != newProofManagerImpl, "ProofManager implementation addresses are the same");
    }

    function _performUpgrade() internal {
        // Upgrade BridgeProofManager
        console.log("Upgrading BridgeProofManager...");
        BridgeProofManager proofManager = BridgeProofManager(payable(proofManagerProxy));
        proofManager.upgradeTo(newProofManagerImpl);
        console.log("[SUCCESS] BridgeProofManager upgraded");
    }

    function _verifyUpgrade() internal view {
        bytes32 implementationSlot = bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1);

        // Verify BridgeProofManager upgrade
        address currentProofImpl = address(uint160(uint256(vm.load(proofManagerProxy, implementationSlot))));
        require(currentProofImpl == newProofManagerImpl, "ProofManager upgrade verification failed");
        BridgeProofManager proofManager = BridgeProofManager(payable(proofManagerProxy));
        require(proofManager.owner() == deployer, "ProofManager owner verification failed after upgrade");
        console.log("[SUCCESS] ProofManager upgrade verified");
    }

    function _verifyContractOnExplorer() internal {
        if (bytes(etherscanApiKey).length == 0) {
            console.log("[WARNING] ETHERSCAN_API_KEY not set, skipping verification");
            return;
        }

        console.log("[INFO] Contract verification will be performed by the shell script...");
        console.log("[INFO] The following new implementation will be verified:");
        console.log("  - ProofManager implementation:", newProofManagerImpl);

        // Create a file to store the implementation address for the shell script to use
        string memory addressFile = string.concat("./upgrade_addresses_", vm.toString(block.timestamp), ".txt");
        vm.writeFile(addressFile, string.concat("BRIDGE_PROOF_MANAGER_IMPL=", vm.toString(newProofManagerImpl), "\n"));
        console.log("[INFO] Implementation address saved to:", addressFile);
    }

    function _printUpgradeSummary() internal view {
        console.log("\n[UPGRADE SUMMARY]");
        console.log("========================");
        console.log("PROXY ADDRESS (unchanged):");
        console.log("ProofManager proxy:", proofManagerProxy);
        console.log("");
        console.log("NEW IMPLEMENTATION ADDRESS:");
        console.log("ProofManager implementation:", newProofManagerImpl);
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
        console.log("1. Test BridgeProofManager functionality");
        console.log("2. Update any off-chain systems with new implementation address");
        console.log("3. Monitor contract for any issues");
        console.log("4. Consider announcing the upgrade to users");

        if (shouldVerify) {
            console.log("\n[VERIFICATION COMMANDS]");
            console.log("New implementation will be verified automatically with --verify flag");
            console.log("Manual verification command:");
            console.log(
                "  forge verify-contract", newProofManagerImpl, "src/BridgeProofManager.sol:BridgeProofManager"
            );
        }
    }
}
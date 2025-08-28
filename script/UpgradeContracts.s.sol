// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import "../src/merkleTree/MerkleTreeManager4Upgradeable.sol";
import "../src/RollupBridgeUpgradeable.sol";

contract UpgradeContractsScript is Script {
    // Existing proxy addresses (to be set via environment variables)
    address public merkleTreeManagerProxy;
    address public rollupBridgeProxy;
    
    // New implementation addresses (will be deployed)
    address public newMerkleTreeManagerImpl;
    address public newRollupBridgeImpl;
    
    // Environment variables
    address public deployer;
    
    // Upgrade flags
    bool public upgradeMerkleTree;
    bool public upgradeRollupBridge;
    
    // Verification settings
    bool public shouldVerify;
    string public etherscanApiKey;
    string public chainId;

    function setUp() public {
        // Load existing proxy addresses
        merkleTreeManagerProxy = vm.envAddress("MERKLE_TREE_PROXY_ADDRESS");
        rollupBridgeProxy = vm.envAddress("ROLLUP_BRIDGE_PROXY_ADDRESS");
        
        // Load deployer (must be owner of contracts)
        deployer = vm.envAddress("DEPLOYER_ADDRESS");
        
        // Load upgrade flags
        upgradeMerkleTree = vm.envBool("UPGRADE_MERKLE_TREE");
        upgradeRollupBridge = vm.envBool("UPGRADE_ROLLUP_BRIDGE");
        
        // Load verification settings
        shouldVerify = vm.envBool("VERIFY_CONTRACTS");
        etherscanApiKey = vm.envString("ETHERSCAN_API_KEY");
        chainId = vm.envString("CHAIN_ID");

        console.log("Upgrade Configuration:");
        console.log("MerkleTreeManager proxy:", merkleTreeManagerProxy);
        console.log("RollupBridge proxy:", rollupBridgeProxy);
        console.log("Deployer (must be owner):", deployer);
        console.log("Upgrade MerkleTree:", upgradeMerkleTree);
        console.log("Upgrade RollupBridge:", upgradeRollupBridge);
        console.log("Chain ID:", chainId);
        console.log("Verify Contracts:", shouldVerify);
        
        require(upgradeMerkleTree || upgradeRollupBridge, "At least one upgrade flag must be true");
    }

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        console.log("\n[START] Starting contract upgrades...");

        // Verify current ownership
        _verifyOwnership();

        if (upgradeMerkleTree) {
            _upgradeMerkleTreeManager();
        }

        if (upgradeRollupBridge) {
            _upgradeRollupBridge();
        }

        // Verify upgrades
        console.log("\n[VERIFY] Verifying upgrades...");
        _verifyUpgrades();

        vm.stopBroadcast();

        // Verify contracts on block explorer (if enabled)
        if (shouldVerify) {
            console.log("\n[VERIFY EXPLORER] Verifying new implementations on block explorer...");
            _verifyContractsOnExplorer();
        }

        console.log("\n[COMPLETE] Contract upgrades completed successfully!");
        _printUpgradeSummary();
    }

    function _verifyOwnership() internal view {
        console.log("\n[OWNERSHIP] Verifying contract ownership...");
        
        if (upgradeMerkleTree) {
            MerkleTreeManager4Upgradeable merkleTreeManager = MerkleTreeManager4Upgradeable(merkleTreeManagerProxy);
            address currentOwner = merkleTreeManager.owner();
            require(currentOwner == deployer, "Deployer is not owner of MerkleTreeManager4");
            console.log("[SUCCESS] Deployer is owner of MerkleTreeManager4");
        }

        if (upgradeRollupBridge) {
            RollupBridgeUpgradeable rollupBridge = RollupBridgeUpgradeable(payable(rollupBridgeProxy));
            address currentOwner = rollupBridge.owner();
            require(currentOwner == deployer, "Deployer is not owner of RollupBridge");
            console.log("[SUCCESS] Deployer is owner of RollupBridge");
        }
    }

    function _upgradeMerkleTreeManager() internal {
        console.log("\n[UPGRADE] Upgrading MerkleTreeManager4...");
        
        // Deploy new implementation
        console.log("Deploying new MerkleTreeManager4Upgradeable implementation...");
        MerkleTreeManager4Upgradeable newImplContract = new MerkleTreeManager4Upgradeable();
        newMerkleTreeManagerImpl = address(newImplContract);
        console.log("New implementation deployed at:", newMerkleTreeManagerImpl);
        
        // Get current implementation for comparison
        bytes32 implementationSlot = bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1);
        address currentImpl = address(uint160(uint256(vm.load(merkleTreeManagerProxy, implementationSlot))));
        console.log("Current implementation:", currentImpl);
        console.log("New implementation:", newMerkleTreeManagerImpl);
        
        require(currentImpl != newMerkleTreeManagerImpl, "Implementation addresses are the same");
        
        // Perform upgrade
        MerkleTreeManager4Upgradeable merkleTreeManager = MerkleTreeManager4Upgradeable(merkleTreeManagerProxy);
        merkleTreeManager.upgradeTo(newMerkleTreeManagerImpl);
        
        console.log("[SUCCESS] MerkleTreeManager4 upgraded successfully");
    }

    function _upgradeRollupBridge() internal {
        console.log("\n[UPGRADE] Upgrading RollupBridge...");
        
        // Deploy new implementation
        console.log("Deploying new RollupBridgeUpgradeable implementation...");
        RollupBridgeUpgradeable newImplContract = new RollupBridgeUpgradeable();
        newRollupBridgeImpl = address(newImplContract);
        console.log("New implementation deployed at:", newRollupBridgeImpl);
        
        // Get current implementation for comparison
        bytes32 implementationSlot = bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1);
        address currentImpl = address(uint160(uint256(vm.load(rollupBridgeProxy, implementationSlot))));
        console.log("Current implementation:", currentImpl);
        console.log("New implementation:", newRollupBridgeImpl);
        
        require(currentImpl != newRollupBridgeImpl, "Implementation addresses are the same");
        
        // Perform upgrade
        RollupBridgeUpgradeable rollupBridge = RollupBridgeUpgradeable(payable(rollupBridgeProxy));
        rollupBridge.upgradeTo(newRollupBridgeImpl);
        
        console.log("[SUCCESS] RollupBridge upgraded successfully");
    }

    function _verifyUpgrades() internal view {
        bytes32 implementationSlot = bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1);
        
        if (upgradeMerkleTree) {
            address currentImpl = address(uint160(uint256(vm.load(merkleTreeManagerProxy, implementationSlot))));
            require(currentImpl == newMerkleTreeManagerImpl, "MerkleTreeManager4 upgrade verification failed");
            
            // Verify functionality still works
            MerkleTreeManager4Upgradeable merkleTreeManager = MerkleTreeManager4Upgradeable(merkleTreeManagerProxy);
            require(merkleTreeManager.owner() == deployer, "Owner verification failed after upgrade");
            
            console.log("[SUCCESS] MerkleTreeManager4 upgrade verified");
        }

        if (upgradeRollupBridge) {
            address currentImpl = address(uint160(uint256(vm.load(rollupBridgeProxy, implementationSlot))));
            require(currentImpl == newRollupBridgeImpl, "RollupBridge upgrade verification failed");
            
            // Verify functionality still works
            RollupBridgeUpgradeable rollupBridge = RollupBridgeUpgradeable(payable(rollupBridgeProxy));
            require(rollupBridge.owner() == deployer, "Owner verification failed after upgrade");
            
            console.log("[SUCCESS] RollupBridge upgrade verified");
        }
    }

    function _verifyContractsOnExplorer() internal view {
        if (bytes(etherscanApiKey).length == 0) {
            console.log("[WARNING] ETHERSCAN_API_KEY not set, skipping verification");
            return;
        }

        console.log("[INFO] Starting contract verification...");
        
        console.log("[INFO] The following new implementations will be verified:");
        if (upgradeMerkleTree) {
            console.log("  - MerkleTreeManager4Upgradeable implementation:", newMerkleTreeManagerImpl);
        }
        if (upgradeRollupBridge) {
            console.log("  - RollupBridgeUpgradeable implementation:", newRollupBridgeImpl);
        }

        console.log("[INFO] Use --verify flag with forge script for automatic verification");
        console.log("[INFO] Or verify manually using foundry verify-contract command");
    }

    function _printUpgradeSummary() internal view {
        console.log("\n[UPGRADE SUMMARY]");
        console.log("========================");
        
        if (upgradeMerkleTree) {
            console.log("MerkleTreeManager4 proxy:", merkleTreeManagerProxy);
            console.log("New MerkleTreeManager4 implementation:", newMerkleTreeManagerImpl);
        }
        
        if (upgradeRollupBridge) {
            console.log("RollupBridge proxy:", rollupBridgeProxy);
            console.log("New RollupBridge implementation:", newRollupBridgeImpl);
        }
        
        console.log("Deployer (Owner):", deployer);
        console.log("Chain ID:", chainId);
        console.log("========================");

        console.log("\n[IMPORTANT NOTES]");
        console.log("1. Proxy addresses remain the same - use these for interactions");
        console.log("2. Implementation addresses have changed - save for future reference");
        console.log("3. All state and functionality should be preserved");
        console.log("4. Test thoroughly before relying on upgraded contracts");

        console.log("\n[NEXT STEPS]");
        console.log("1. Test all contract functionality");
        console.log("2. Update any off-chain systems with new implementation addresses");
        console.log("3. Monitor contracts for any issues");
        console.log("4. Consider announcing the upgrade to users");

        if (shouldVerify) {
            console.log("\n[VERIFICATION COMMANDS]");
            console.log("New implementations will be verified automatically with --verify flag");
            console.log("Manual verification commands:");
            if (upgradeMerkleTree) {
                console.log(
                    "  forge verify-contract",
                    newMerkleTreeManagerImpl,
                    "src/merkleTree/MerkleTreeManager4Upgradeable.sol:MerkleTreeManager4Upgradeable"
                );
            }
            if (upgradeRollupBridge) {
                console.log(
                    "  forge verify-contract",
                    newRollupBridgeImpl,
                    "src/RollupBridgeUpgradeable.sol:RollupBridgeUpgradeable"
                );
            }
        }
    }

    // Individual upgrade functions for granular control
    function upgradeMerkleTreeOnly() external {
        upgradeMerkleTree = true;
        upgradeRollupBridge = false;
        run();
    }

    function upgradeRollupBridgeOnly() external {
        upgradeMerkleTree = false;
        upgradeRollupBridge = true;
        run();
    }
}
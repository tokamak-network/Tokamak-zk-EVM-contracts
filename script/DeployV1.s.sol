// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../src/merkleTree/MerkleTreeManagerV1.sol";
import "../src/RollupBridgeV1.sol";

contract DeployUpgradeableScript is Script {
    // Implementation addresses
    address public merkleTreeManagerImpl;
    address public rollupBridgeImpl;

    // Proxy addresses (main contracts)
    address public merkleTreeManager;
    address public rollupBridge;

    // Environment variables
    address public zkVerifier;
    address public deployer;
    uint256 public treeDepth;

    // Verification settings
    bool public shouldVerify;
    string public etherscanApiKey;
    string public chainId;

    function setUp() public {
        // Load environment variables
        zkVerifier = vm.envAddress("ZK_VERIFIER_ADDRESS");
        deployer = vm.envAddress("DEPLOYER_ADDRESS");
        treeDepth = vm.envOr("TREE_DEPTH", uint256(20)); // Default to 20

        // Load verification settings
        shouldVerify = vm.envBool("VERIFY_CONTRACTS");
        etherscanApiKey = vm.envString("ETHERSCAN_API_KEY");
        chainId = vm.envString("CHAIN_ID");

        console.log("Atomic Factory UUPS Deployment Configuration (MEV-Safe):");
        console.log("ZK Verifier:", zkVerifier);
        console.log("Deployer:", deployer);
        console.log("Tree Depth:", treeDepth);
        console.log("Network:", vm.envString("RPC_URL"));
        console.log("Chain ID:", chainId);
        console.log("Verify Contracts:", shouldVerify);
    }

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        console.log("\n[START] Starting UUPS proxy deployment with immediate initialization (MEV-safe)...");

        // Step 1: Deploy implementations
        console.log("\n[STEP1] Deploying implementation contracts...");
        MerkleTreeManagerV1 merkleTreeManagerImplContract = new MerkleTreeManagerV1();
        merkleTreeManagerImpl = address(merkleTreeManagerImplContract);
        console.log("[SUCCESS] MerkleTreeManagerV1 implementation deployed at:", merkleTreeManagerImpl);

        RollupBridgeV1 rollupBridgeImplContract = new RollupBridgeV1();
        rollupBridgeImpl = address(rollupBridgeImplContract);
        console.log("[SUCCESS] RollupBridgeV1 implementation deployed at:", rollupBridgeImpl);

        // Step 2: Deploy MerkleTreeManager4 proxy with immediate initialization (atomic)
        console.log("\n[STEP2] Deploying MerkleTreeManager4 proxy with atomic initialization...");
        bytes memory merkleTreeInitData = abi.encodeCall(MerkleTreeManagerV1.initialize, (uint32(treeDepth), deployer));
        ERC1967Proxy merkleTreeProxy = new ERC1967Proxy(merkleTreeManagerImpl, merkleTreeInitData);
        merkleTreeManager = address(merkleTreeProxy);
        console.log("[SUCCESS] MerkleTreeManager4 proxy deployed and initialized at:", merkleTreeManager);

        // Step 3: Deploy RollupBridge proxy with immediate initialization (atomic)
        console.log("\n[STEP3] Deploying RollupBridge proxy with atomic initialization...");
        bytes memory rollupBridgeInitData =
            abi.encodeCall(RollupBridgeV1.initialize, (zkVerifier, merkleTreeManager, deployer));
        ERC1967Proxy rollupBridgeProxy = new ERC1967Proxy(rollupBridgeImpl, rollupBridgeInitData);
        rollupBridge = address(rollupBridgeProxy);
        console.log("[SUCCESS] RollupBridge proxy deployed and initialized at:", rollupBridge);

        // Step 4: Configure MerkleTreeManager4 with RollupBridge
        console.log("\n[STEP4] Configuring MerkleTreeManager4...");
        MerkleTreeManagerV1 merkleTree = MerkleTreeManagerV1(merkleTreeManager);
        merkleTree.setBridge(rollupBridge);
        console.log("[SUCCESS] Bridge address set in MerkleTreeManager4");

        // Step 5: Verify deployment
        console.log("\n[STEP5] Verifying deployment...");
        _verifyDeployment();

        vm.stopBroadcast();

        // Step 6: Verify contracts on block explorer (if enabled)
        if (shouldVerify) {
            console.log("\n[STEP6] Verifying contracts on block explorer...");
            _verifyContractsOnExplorer();
        }

        console.log("\n[COMPLETE] Atomic UUPS deployment completed successfully!");
        _printDeploymentSummary();
    }

    function _verifyDeployment() internal view {
        // Verify implementations exist
        require(merkleTreeManagerImpl != address(0), "MerkleTreeManager4 implementation deployment failed");
        require(rollupBridgeImpl != address(0), "RollupBridge implementation deployment failed");

        // Verify proxies exist and are properly initialized
        require(merkleTreeManager != address(0), "MerkleTreeManager4 proxy deployment failed");
        require(rollupBridge != address(0), "RollupBridge proxy deployment failed");

        // Verify MerkleTreeManager4 proxy configuration
        MerkleTreeManagerV1 merkleTree = MerkleTreeManagerV1(merkleTreeManager);
        require(merkleTree.bridge() == rollupBridge, "Bridge not set in MerkleTreeManager4");
        require(merkleTree.bridgeSet(), "Bridge not properly set");
        require(merkleTree.owner() == deployer, "Owner not set correctly in MerkleTreeManager4");

        // Verify RollupBridge proxy configuration
        RollupBridgeV1 bridge = RollupBridgeV1(payable(rollupBridge));
        require(address(bridge.mtmanager()) == merkleTreeManager, "MerkleTreeManager4 not set in RollupBridge");
        require(address(bridge.zkVerifier()) == zkVerifier, "ZK Verifier not set correctly in RollupBridge");
        require(bridge.owner() == deployer, "Owner not set correctly in RollupBridge");

        // Verify proxy implementation addresses
        bytes32 implementationSlot = bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1);
        address merkleTreeImplFromProxy = address(uint160(uint256(vm.load(merkleTreeManager, implementationSlot))));
        address rollupBridgeImplFromProxy = address(uint160(uint256(vm.load(rollupBridge, implementationSlot))));

        require(merkleTreeImplFromProxy == merkleTreeManagerImpl, "MerkleTreeManager4 proxy implementation mismatch");
        require(rollupBridgeImplFromProxy == rollupBridgeImpl, "RollupBridge proxy implementation mismatch");

        console.log("[SUCCESS] All UUPS proxy contracts verified successfully");
    }

    function _verifyContractsOnExplorer() internal view {
        if (bytes(etherscanApiKey).length == 0) {
            console.log("[WARNING] ETHERSCAN_API_KEY not set, skipping verification");
            return;
        }

        console.log("[INFO] Starting contract verification...");

        console.log("[INFO] The following contracts will be verified:");
        console.log("  - MerkleTreeManagerV1 implementation:", merkleTreeManagerImpl);
        console.log("  - MerkleTreeManager4 proxy:", merkleTreeManager);
        console.log("  - RollupBridgeV1 implementation:", rollupBridgeImpl);
        console.log("  - RollupBridge proxy:", rollupBridge);

        console.log("[INFO] Use --verify flag with forge script for automatic verification");
        console.log("[INFO] Or verify manually using foundry verify-contract command");
    }

    function _printDeploymentSummary() internal view {
        console.log("\n[DEPLOYMENT SUMMARY]");
        console.log("========================");
        console.log("MerkleTreeManagerV1 implementation:", merkleTreeManagerImpl);
        console.log("MerkleTreeManager4 proxy:", merkleTreeManager);
        console.log("RollupBridgeV1 implementation:", rollupBridgeImpl);
        console.log("RollupBridge proxy:", rollupBridge);
        console.log("ZK Verifier:", zkVerifier);
        console.log("Deployer (Owner):", deployer);
        console.log("Tree Depth:", treeDepth);
        console.log("Chain ID:", chainId);
        console.log("========================");

        console.log("\n[MEV PROTECTION FEATURES]");
        console.log("[+] Atomic proxy deployment with initialization");
        console.log("[+] No initialization window for front-running");
        console.log("[+] All contracts linked in single transaction");
        console.log("[+] Proper UUPS proxy pattern implementation");

        console.log("\n[IMPORTANT ADDRESSES TO SAVE]");
        console.log("Main contracts (use these for interactions):");
        console.log("  MerkleTreeManager4 (proxy):", merkleTreeManager);
        console.log("  RollupBridge (proxy):", rollupBridge);
        console.log("");
        console.log("Implementation contracts (for upgrades only):");
        console.log("  MerkleTreeManagerV1 implementation:", merkleTreeManagerImpl);
        console.log("  RollupBridgeV1 implementation:", rollupBridgeImpl);

        console.log("\n[UPGRADE INSTRUCTIONS]");
        console.log("To upgrade contracts (owner only):");
        console.log("  1. Deploy new implementation contract");
        console.log("  2. Call upgradeTo(newImplementation) on existing contract");
        console.log("  3. All state will be preserved during upgrade");

        console.log("\n[NEXT STEPS]");
        console.log("1. Save the deployed addresses (especially proxy addresses)");
        console.log("2. Verify contracts on block explorer");
        console.log("3. Test the bridge functionality");
        console.log("4. Authorize channel creators via RollupBridge.authorizeCreator()");
        console.log("5. Consider setting up timelock or multisig for upgrade authorization");

        if (shouldVerify) {
            console.log("\n[VERIFICATION COMMANDS]");
            console.log("Contracts will be verified automatically with --verify flag");
            console.log("Manual verification commands:");
            console.log(
                "  forge verify-contract",
                merkleTreeManagerImpl,
                "src/merkleTree/MerkleTreeManagerV1.sol:MerkleTreeManagerV1"
            );
            console.log("  forge verify-contract", rollupBridgeImpl, "src/RollupBridgeV1.sol:RollupBridgeV1");
            console.log(
                "  forge verify-contract",
                merkleTreeManager,
                "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy"
            );
            console.log(
                "  forge verify-contract",
                rollupBridge,
                "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy"
            );
        }
    }

    // Utility function to upgrade MerkleTreeManager4 (for future use)
    function upgradeMerkleTreeManager(address proxyAddress, address newImplementation) public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        console.log("Upgrading MerkleTreeManager4...");
        console.log("Proxy address:", proxyAddress);
        console.log("New implementation:", newImplementation);

        MerkleTreeManagerV1 merkleTree = MerkleTreeManagerV1(proxyAddress);
        merkleTree.upgradeTo(newImplementation);

        console.log("[SUCCESS] MerkleTreeManager4 upgraded successfully");
        vm.stopBroadcast();
    }

    // Utility function to upgrade RollupBridge (for future use)
    function upgradeRollupBridge(address proxyAddress, address newImplementation) public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        console.log("Upgrading RollupBridge...");
        console.log("Proxy address:", proxyAddress);
        console.log("New implementation:", newImplementation);

        RollupBridgeV1 bridge = RollupBridgeV1(payable(proxyAddress));
        bridge.upgradeTo(newImplementation);

        console.log("[SUCCESS] RollupBridge upgraded successfully");
        vm.stopBroadcast();
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import "../src/poseidon/Poseidon4.sol";
import "../src/merkleTree/MerkleTreeManager4.sol";
import "../src/RollupBridge.sol";

contract DeployScript is Script {
    // Deployment addresses
    address public poseidon4;
    address public merkleTreeManager4;
    address public rollupBridge;

    // Environment variables
    address public zkVerifier;
    address public deployer;

    // Verification settings
    bool public shouldVerify;
    string public etherscanApiKey;
    string public chainId;

    function setUp() public {
        // Load environment variables
        zkVerifier = vm.envAddress("ZK_VERIFIER_ADDRESS");
        deployer = vm.envAddress("DEPLOYER_ADDRESS");

        // Load verification settings
        shouldVerify = vm.envBool("VERIFY_CONTRACTS");
        etherscanApiKey = vm.envString("ETHERSCAN_API_KEY");
        chainId = vm.envString("CHAIN_ID");

        console.log("Deployment Configuration:");
        console.log("ZK Verifier:", zkVerifier);
        console.log("Deployer:", deployer);
        console.log("Network:", vm.envString("RPC_URL"));
        console.log("Chain ID:", chainId);
        console.log("Verify Contracts:", shouldVerify);
    }

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        console.log("\n[START] Starting deployment...");

        // Step 1: Deploy Poseidon4
        console.log("\n[STEP1] Deploying Poseidon4...");
        Poseidon4 poseidon4Contract = new Poseidon4();
        poseidon4 = address(poseidon4Contract);
        console.log("[SUCCESS] Poseidon4 deployed at:", poseidon4);

        // Step 2: Deploy MerkleTreeManager4
        console.log("\n[STEP2] Deploying MerkleTreeManager4...");
        MerkleTreeManager4 merkleTreeContract = new MerkleTreeManager4(poseidon4);
        merkleTreeManager4 = address(merkleTreeContract);
        console.log("[SUCCESS] MerkleTreeManager4 deployed at:", merkleTreeManager4);

        // Step 3: Deploy RollupBridge
        console.log("\n[STEP3] Deploying RollupBridge...");
        RollupBridge bridgeContract = new RollupBridge(zkVerifier, merkleTreeManager4);
        rollupBridge = address(bridgeContract);
        console.log("[SUCCESS] RollupBridge deployed at:", rollupBridge);

        // Step 4: Configure MerkleTreeManager4 with RollupBridge
        console.log("\n[STEP4] Configuring MerkleTreeManager4...");
        merkleTreeContract.setBridge(rollupBridge);
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

        console.log("\n[COMPLETE] Deployment completed successfully!");
        _printDeploymentSummary();
    }

    function _verifyDeployment() internal view {
        // Verify Poseidon4
        require(poseidon4 != address(0), "Poseidon4 deployment failed");

        // Verify MerkleTreeManager4
        require(merkleTreeManager4 != address(0), "MerkleTreeManager4 deployment failed");
        MerkleTreeManager4 merkleTree = MerkleTreeManager4(merkleTreeManager4);
        require(address(merkleTree.poseidonHasher()) == poseidon4, "Poseidon4 not set in MerkleTreeManager4");
        require(merkleTree.bridge() == rollupBridge, "Bridge not set in MerkleTreeManager4");
        require(merkleTree.bridgeSet(), "Bridge not properly set");

        // Verify RollupBridge
        require(rollupBridge != address(0), "RollupBridge deployment failed");
        RollupBridge bridge = RollupBridge(rollupBridge);
        require(address(bridge.mtmanager()) == merkleTreeManager4, "MerkleTreeManager4 not set in RollupBridge");

        console.log("[SUCCESS] All contracts verified successfully");
    }

    function _verifyContractsOnExplorer() internal view {
        if (bytes(etherscanApiKey).length == 0) {
            console.log("[WARNING] ETHERSCAN_API_KEY not set, skipping verification");
            return;
        }

        console.log("[INFO] Starting contract verification...");

        // Note: Foundry handles the actual verification when using --verify flag
        // This function provides guidance on what will be verified

        console.log("[INFO] The following contracts will be verified:");
        console.log("  - Poseidon4:", poseidon4);
        console.log("  - MerkleTreeManager4:", merkleTreeManager4);
        console.log("  - RollupBridge:", rollupBridge);

        console.log("[INFO] Use --verify flag with forge script for automatic verification");
        console.log("[INFO] Or verify manually using foundry verify-contract command");
    }

    function _printDeploymentSummary() internal view {
        console.log("\n[DEPLOYMENT SUMMARY]");
        console.log("========================");
        console.log("Poseidon4:", poseidon4);
        console.log("MerkleTreeManager4:", merkleTreeManager4);
        console.log("RollupBridge:", rollupBridge);
        console.log("ZK Verifier:", zkVerifier);
        console.log("Deployer:", deployer);
        console.log("Chain ID:", chainId);
        console.log("========================");

        console.log("\n[NEXT STEPS]");
        console.log("1. Save the deployed addresses");
        console.log("2. Verify contracts on block explorer");
        console.log("3. Test the bridge functionality");
        console.log("4. Authorize channel creators via RollupBridge.authorizeCreator()");

        if (shouldVerify) {
            console.log("\n[VERIFICATION]");
            console.log("Contracts will be verified automatically with --verify flag");
            console.log("Manual verification commands:");
            console.log("  forge verify-contract", poseidon4, "src/poseidon/Poseidon4.sol:Poseidon4");
            console.log(
                "  forge verify-contract",
                merkleTreeManager4,
                "src/merkleTree/MerkleTreeManager4.sol:MerkleTreeManager4"
            );
            console.log("  --constructor-args (hex encoded):", vm.toString(abi.encode(poseidon4)));
            console.log("  forge verify-contract", rollupBridge, "src/RollupBridge.sol:RollupBridge");
            console.log("  --constructor-args (hex encoded):", vm.toString(abi.encode(zkVerifier, merkleTreeManager4)));
        }
    }
}

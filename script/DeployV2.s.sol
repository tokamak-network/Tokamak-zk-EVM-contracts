// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../src/RollupBridgeV2.sol";
import "../src/verifier/Verifier.sol";

contract DeployV2Script is Script {
    // Implementation addresses
    address public rollupBridgeV2Impl;
    
    // Proxy addresses (main contracts)
    address public rollupBridgeV2;
    
    // Environment variables
    address public zkVerifier;
    address public deployer;
    
    // Verification settings
    bool public shouldVerify;
    string public etherscanApiKey;
    string public chainId;
    
    function setUp() public {
        // Load environment variables
        deployer = vm.envOr("DEPLOYER_ADDRESS", msg.sender);
        shouldVerify = vm.envOr("VERIFY_CONTRACTS", false);
        etherscanApiKey = vm.envOr("ETHERSCAN_API_KEY", string(""));
        chainId = vm.envOr("CHAIN_ID", string("31337"));
        
        // ZK Verifier can be provided or we deploy a new one
        try vm.envAddress("ZK_VERIFIER_ADDRESS") returns (address verifier) {
            zkVerifier = verifier;
        } catch {
            console.log("No ZK_VERIFIER_ADDRESS provided, will deploy new Verifier");
        }
    }
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        
        deployer = vm.addr(deployerPrivateKey);
        console.log("Deploying with account:", deployer);
        console.log("Account balance:", deployer.balance);
        
        // Deploy ZK Verifier if not provided
        if (zkVerifier == address(0)) {
            console.log("Deploying Verifier...");
            Verifier verifierContract = new Verifier();
            zkVerifier = address(verifierContract);
            console.log("Verifier deployed at:", zkVerifier);
        } else {
            console.log("Using existing Verifier at:", zkVerifier);
        }
        
        // Deploy RollupBridgeV2 implementation
        console.log("Deploying RollupBridgeV2 implementation...");
        RollupBridgeV2 rollupBridgeV2Implementation = new RollupBridgeV2();
        rollupBridgeV2Impl = address(rollupBridgeV2Implementation);
        console.log("RollupBridgeV2 implementation deployed at:", rollupBridgeV2Impl);
        
        // Deploy RollupBridgeV2 proxy
        console.log("Deploying RollupBridgeV2 proxy...");
        bytes memory rollupBridgeInitData = abi.encodeCall(
            RollupBridgeV2.initialize,
            (zkVerifier, address(0), deployer) // No external MerkleTreeManager needed
        );
        
        ERC1967Proxy rollupBridgeV2Proxy = new ERC1967Proxy(
            rollupBridgeV2Impl,
            rollupBridgeInitData
        );
        rollupBridgeV2 = address(rollupBridgeV2Proxy);
        console.log("RollupBridgeV2 proxy deployed at:", rollupBridgeV2);
        
        // Authorize the deployer as a channel creator
        RollupBridgeV2(rollupBridgeV2).authorizeCreator(deployer);
        console.log("Authorized deployer as channel creator");
        
        vm.stopBroadcast();
        
        // Log final addresses
        console.log("\n=== DEPLOYMENT SUMMARY ===");
        console.log("ZK Verifier:", zkVerifier);
        console.log("RollupBridgeV2 Implementation:", rollupBridgeV2Impl);
        console.log("RollupBridgeV2 Proxy:", rollupBridgeV2);
        console.log("Deployer (Owner):", deployer);
        
        // Verify contracts if requested
        if (shouldVerify && bytes(etherscanApiKey).length > 0) {
            verifyContracts();
        }
    }
    
    function verifyContracts() internal {
        console.log("\n=== VERIFYING CONTRACTS ===");
        
        try vm.parseAddress(vm.envString("ZK_VERIFIER_ADDRESS")) {
            console.log("Skipping Verifier verification (pre-existing)");
        } catch {
            // Verify Verifier
            console.log("Verifying Verifier...");
            string[] memory verifierCmd = new string[](6);
            verifierCmd[0] = "forge";
            verifierCmd[1] = "verify-contract";
            verifierCmd[2] = vm.toString(zkVerifier);
            verifierCmd[3] = "src/verifier/Verifier.sol:Verifier";
            verifierCmd[4] = "--etherscan-api-key";
            verifierCmd[5] = etherscanApiKey;
            vm.ffi(verifierCmd);
        }
        
        // Verify RollupBridgeV2 Implementation
        console.log("Verifying RollupBridgeV2 Implementation...");
        string[] memory rollupCmd = new string[](6);
        rollupCmd[0] = "forge";
        rollupCmd[1] = "verify-contract";
        rollupCmd[2] = vm.toString(rollupBridgeV2Impl);
        rollupCmd[3] = "src/RollupBridgeV2.sol:RollupBridgeV2";
        rollupCmd[4] = "--etherscan-api-key";
        rollupCmd[5] = etherscanApiKey;
        vm.ffi(rollupCmd);
        
        console.log("Contract verification complete!");
    }
}
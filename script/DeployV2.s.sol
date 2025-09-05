// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import "forge-std/Script.sol";
import "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../src/RollupBridge.sol";
import "../src/verifier/Verifier.sol";

contract DeployV2Script is Script {
    // Implementation addresses
    address public rollupBridgeImpl;

    // Proxy addresses (main contracts)
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

        // Deploy RollupBridge implementation
        console.log("Deploying RollupBridge implementation...");
        RollupBridge rollupBridgeImplementation = new RollupBridge();
        rollupBridgeImpl = address(rollupBridgeImplementation);
        console.log("RollupBridge implementation deployed at:", rollupBridgeImpl);

        // Deploy RollupBridge proxy
        console.log("Deploying RollupBridge proxy...");
        bytes memory rollupBridgeInitData = abi.encodeCall(
            RollupBridge.initialize,
            (zkVerifier, address(0), deployer) // No external MerkleTreeManager needed
        );

        ERC1967Proxy rollupBridgeProxy = new ERC1967Proxy(rollupBridgeImpl, rollupBridgeInitData);
        rollupBridge = address(rollupBridgeProxy);
        console.log("RollupBridge proxy deployed at:", rollupBridge);

        // Authorize the deployer as a channel creator
        RollupBridge(rollupBridge).authorizeCreator(deployer);
        console.log("Authorized deployer as channel creator");

        vm.stopBroadcast();

        // Log final addresses
        console.log("\n=== DEPLOYMENT SUMMARY ===");
        console.log("ZK Verifier:", zkVerifier);
        console.log("RollupBridge Implementation:", rollupBridgeImpl);
        console.log("RollupBridge Proxy:", rollupBridge);
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

        // Verify RollupBridge Implementation
        console.log("Verifying RollupBridge Implementation...");
        string[] memory rollupCmd = new string[](6);
        rollupCmd[0] = "forge";
        rollupCmd[1] = "verify-contract";
        rollupCmd[2] = vm.toString(rollupBridgeImpl);
        rollupCmd[3] = "src/RollupBridge.sol:RollupBridge";
        rollupCmd[4] = "--etherscan-api-key";
        rollupCmd[5] = etherscanApiKey;
        vm.ffi(rollupCmd);

        console.log("Contract verification complete!");
    }
}

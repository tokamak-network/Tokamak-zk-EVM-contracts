// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import "forge-std/Script.sol";
import "../src/verifier/TokamakVerifier.sol";

contract DeployTokamakVerifierScript is Script {
    address public tokamakVerifier;
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
    }

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        deployer = vm.addr(deployerPrivateKey);
        console.log("Deploying TokamakVerifier with account:", deployer);
        console.log("Account balance:", deployer.balance);

        // Deploy TokamakVerifier
        console.log("Deploying TokamakVerifier...");
        TokamakVerifier verifierContract = new TokamakVerifier();
        tokamakVerifier = address(verifierContract);
        console.log("TokamakVerifier deployed at:", tokamakVerifier);

        vm.stopBroadcast();

        console.log("\n=== DEPLOYMENT COMPLETE ===");
        console.log("TokamakVerifier:", tokamakVerifier);
        console.log("Deployer:", deployer);

        // Verify contract if requested
        if (shouldVerify && bytes(etherscanApiKey).length > 0) {
            console.log("\n=== STARTING CONTRACT VERIFICATION ===");
            console.log("Waiting 30 seconds before verification to allow Etherscan indexing...");
            vm.sleep(30000); // Wait 30 seconds
            verifyContract();
        } else {
            console.log("\n=== SKIPPING CONTRACT VERIFICATION ===");
            if (!shouldVerify) {
                console.log("Reason: VERIFY_CONTRACTS=false");
            }
            if (bytes(etherscanApiKey).length == 0) {
                console.log("Reason: No ETHERSCAN_API_KEY provided");
            }
        }
    }

    function verifyContract() internal {
        console.log("\n=== VERIFYING TOKAMAK VERIFIER ===");
        
        // Ensure contract is deployed before verification
        require(tokamakVerifier != address(0), "TokamakVerifier not deployed");

        console.log("Verifying TokamakVerifier...");
        string[] memory verifierCmd = new string[](6);
        verifierCmd[0] = "forge";
        verifierCmd[1] = "verify-contract";
        verifierCmd[2] = vm.toString(tokamakVerifier);
        verifierCmd[3] = "src/verifier/TokamakVerifier.sol:TokamakVerifier";
        verifierCmd[4] = "--etherscan-api-key";
        verifierCmd[5] = etherscanApiKey;
        _verifyWithRetry(verifierCmd, "TokamakVerifier");

        console.log("TokamakVerifier verification complete!");
    }

    function _verifyWithRetry(string[] memory cmd, string memory contractName) internal {
        uint256 maxRetries = 3;
        uint256 retryDelay = 15000; // 15 seconds

        for (uint256 i = 0; i < maxRetries; i++) {
            try vm.ffi(cmd) {
                console.log(string.concat(contractName, " verified successfully"));
                return;
            } catch {
                if (i < maxRetries - 1) {
                    console.log(string.concat("Verification failed for ", contractName, ", retrying in 15 seconds..."));
                    vm.sleep(retryDelay);
                } else {
                    console.log(
                        string.concat(
                            "Verification failed for ", contractName, " after ", vm.toString(maxRetries), " attempts"
                        )
                    );
                }
            }
        }
    }
}
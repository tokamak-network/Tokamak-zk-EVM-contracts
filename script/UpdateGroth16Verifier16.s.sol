// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import "forge-std/Script.sol";
import "../src/verifier/Groth16Verifier16Leaves.sol";
import "../src/BridgeProofManager.sol";

contract UpdateGroth16Verifier16Script is Script {
    function run() public {
        // Load environment variables
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        // Use the deployed ProofManager proxy address
        address proofManagerAddress = 0xd89A53b0edC82351A300a0779A6f4bA5a310f34E;

        console.log("=== Updating Groth16 16-Leaves Verifier ===");
        console.log("Using ProofManager address:", proofManagerAddress);
        console.log("Deployer address:", vm.addr(privateKey));

        vm.startBroadcast(privateKey);

        // Deploy the new Groth16Verifier16Leaves contract
        console.log("\n1. Deploying new Groth16Verifier16Leaves...");
        Groth16Verifier16Leaves newVerifier16 = new Groth16Verifier16Leaves();
        console.log("New Groth16Verifier16Leaves deployed at:", address(newVerifier16));

        // Get the BridgeProofManager instance
        BridgeProofManager proofManager = BridgeProofManager(proofManagerAddress);

        // Get current verifier addresses to maintain the other verifiers unchanged
        console.log("\n2. Getting current verifier addresses...");
        address currentVerifier16 = address(proofManager.groth16Verifier16());
        address currentVerifier32 = address(proofManager.groth16Verifier32());
        address currentVerifier64 = address(proofManager.groth16Verifier64());
        address currentVerifier128 = address(proofManager.groth16Verifier128());

        console.log("Current 16-leaves verifier:", currentVerifier16);
        console.log("Current 32-leaves verifier:", currentVerifier32);
        console.log("Current 64-leaves verifier:", currentVerifier64);
        console.log("Current 128-leaves verifier:", currentVerifier128);

        // Prepare the new verifiers array (only updating the 16-leaves verifier)
        address[4] memory newVerifiers = [
            address(newVerifier16), // Updated 16-leaves verifier
            currentVerifier32, // Keep existing 32-leaves verifier
            currentVerifier64, // Keep existing 64-leaves verifier
            currentVerifier128 // Keep existing 128-leaves verifier
        ];

        // Update the verifiers
        console.log("\n3. Updating verifiers in ProofManager...");
        proofManager.updateGroth16Verifiers(newVerifiers);
        console.log("Groth16 verifiers updated successfully!");

        // Verify the update
        console.log("\n4. Verifying the update...");
        address updatedVerifier16 = address(proofManager.groth16Verifier16());
        console.log("New 16-leaves verifier address:", updatedVerifier16);
        console.log("Update successful:", updatedVerifier16 == address(newVerifier16));

        vm.stopBroadcast();

        console.log("\n=== Deployment Summary ===");
        console.log("New Groth16Verifier16Leaves:", address(newVerifier16));
        console.log("ProofManager Address:", proofManagerAddress);
        console.log("Transaction completed successfully!");
    }
}

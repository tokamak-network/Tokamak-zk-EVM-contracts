// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/verifier/Groth16Verifier64Leaves.sol";

contract TestGroth16Integration is Script {
    function run() public {
        console.log("Testing Groth16 Integration...");

        // Deploy the real Groth16Verifier
        Groth16Verifier64Leaves verifier = new Groth16Verifier64Leaves();
        console.log("Groth16Verifier deployed at:", address(verifier));

        // Test with mock proof data
        uint256[4] memory pA = [uint256(1), uint256(2), uint256(3), uint256(4)];
        uint256[8] memory pB =
            [uint256(5), uint256(6), uint256(7), uint256(8), uint256(9), uint256(10), uint256(11), uint256(12)];
        uint256[4] memory pC = [uint256(13), uint256(14), uint256(15), uint256(16)];

        // Create test public signals (129 elements)
        uint256[129] memory publicSignals;

        // Fill with test MPT keys and balances
        publicSignals[0] = uint256(uint160(address(0xd69B7AaaE8C1c9F0546AfA4Fd8eD39741cE3f59F))); // MPT key 1
        publicSignals[1] = uint256(uint160(address(0xb18E7CdB6Aa28Cc645227041329896446A1478bd))); // MPT key 2
        publicSignals[2] = uint256(uint160(address(0x9D70617FF571Ac34516C610a51023EE1F28373e8))); // MPT key 3

        publicSignals[64] = 1000000000000000000; // Balance 1: 1 ETH
        publicSignals[65] = 2000000000000000000; // Balance 2: 2 ETH
        publicSignals[66] = 3000000000000000000; // Balance 3: 3 ETH

        // Mock merkle root as last element
        publicSignals[128] = uint256(keccak256("test_merkle_root"));

        console.log("Testing proof verification...");

        try verifier.verifyProof(pA, pB, pC, publicSignals) returns (bool result) {
            console.log("Proof verification result:", result);
            console.log("Note: This will likely be false with mock data, but verifier is working");
        } catch Error(string memory reason) {
            console.log("Verification failed with reason:", reason);
        } catch {
            console.log("Verification failed with unknown error");
        }

        console.log("Groth16 integration test completed");
    }
}

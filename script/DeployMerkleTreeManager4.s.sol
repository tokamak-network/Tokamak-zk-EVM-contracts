// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Script} from "forge-std/Script.sol";
import {MerkleTreeManager4} from "../src/merkleTree/MerkleTreeManager4.sol";
import {Poseidon4Yul} from "@poseidon/Poseidon4Yul.sol";

/**
 * @title DeployMerkleTreeManager4
 * @dev Deployment script for MerkleTreeManager4 contract
 */
contract DeployMerkleTreeManager4 is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy Poseidon4Yul hasher
        Poseidon4Yul poseidonHasher = new Poseidon4Yul();
        console.log("Poseidon4Yul deployed at:", address(poseidonHasher));
        
        // Deploy MerkleTreeManager4 with depth 4 (supports up to 4^4 = 256 leaves)
        MerkleTreeManager4 merkleTree = new MerkleTreeManager4(address(poseidonHasher), 4);
        console.log("MerkleTreeManager4 deployed at:", address(merkleTree));
        
        // Set the bridge address (this should be the actual bridge contract address)
        address bridgeAddress = vm.envAddress("BRIDGE_ADDRESS");
        merkleTree.setBridge(bridgeAddress);
        console.log("Bridge set to:", bridgeAddress);
        
        vm.stopBroadcast();
        
        console.log("Deployment completed successfully!");
        console.log("MerkleTreeManager4:", address(merkleTree));
        console.log("Poseidon4Yul:", address(poseidonHasher));
        console.log("Tree depth: 4 (supports up to 256 leaves)");
        console.log("Children per node: 4 (quaternary tree)");
    }
}

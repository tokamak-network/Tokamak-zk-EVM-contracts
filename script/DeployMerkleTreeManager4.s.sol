// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Script, console} from "forge-std/Script.sol";
import {MerkleTreeManager4} from "../src/merkleTree/MerkleTreeManager4.sol";
import {Poseidon4Yul} from "../lib/poseidon-bls12381-evm/contracts/Poseidon4Yul.sol";

contract DeployMerkleTreeManager4 is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy Poseidon4Yul
        Poseidon4Yul poseidon4Yul = new Poseidon4Yul();
        console.log("Poseidon4Yul deployed at:", address(poseidon4Yul));

        // Deploy MerkleTreeManager4 with depth 16 (maximum for quaternary trees)
        MerkleTreeManager4 merkleTreeManager4 = new MerkleTreeManager4(
            address(poseidon4Yul),
            16
        );
        console.log("MerkleTreeManager4 deployed at:", address(merkleTreeManager4));

        vm.stopBroadcast();
    }
}

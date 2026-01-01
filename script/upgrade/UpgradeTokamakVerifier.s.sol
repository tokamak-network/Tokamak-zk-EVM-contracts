// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import "forge-std/Script.sol";
import "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../../src/verifier/TokamakVerifier.sol";

contract UpgradeTokamakVerifierScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address proxyAddress = vm.envAddress("TOKAMAK_VERIFIER_PROXY_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);

        address deployer = vm.addr(deployerPrivateKey);
        console.log("Upgrading with account:", deployer);
        console.log("Account balance:", deployer.balance);
        console.log("Target proxy address:", proxyAddress);

        // Deploy new TokamakVerifier implementation
        console.log("Deploying new TokamakVerifier implementation...");
        TokamakVerifier newImplementation = new TokamakVerifier();
        address newImplAddress = address(newImplementation);
        console.log("New TokamakVerifier implementation deployed at:", newImplAddress);

        // Get the proxy contract and upgrade it
        TokamakVerifier proxy = TokamakVerifier(proxyAddress);

        // Check current implementation before upgrade
        console.log("Current implementation address:", _getImplementationAddress(proxyAddress));

        // Perform the upgrade
        console.log("Upgrading proxy to new implementation...");
        proxy.upgradeTo(newImplAddress);

        // Verify the upgrade
        address currentImpl = _getImplementationAddress(proxyAddress);
        console.log("New implementation address:", currentImpl);

        require(currentImpl == newImplAddress, "Upgrade failed: implementation address mismatch");
        console.log("Upgrade successful!");

        vm.stopBroadcast();

        console.log("\n=== UPGRADE COMPLETE ===");
        console.log("TokamakVerifier proxy:", proxyAddress);
        console.log("New implementation:", newImplAddress);
        console.log("Deployer:", deployer);
    }

    // Helper function to get implementation address from proxy
    function _getImplementationAddress(address proxy) internal view returns (address) {
        // ERC1967 implementation slot
        bytes32 slot = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        return address(uint160(uint256(vm.load(proxy, slot))));
    }
}
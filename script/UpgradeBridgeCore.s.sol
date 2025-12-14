// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import "forge-std/Script.sol";
import "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../src/BridgeCore.sol";

contract UpgradeBridgeCoreScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address proxyAddress = vm.envAddress("ROLLUP_BRIDGE_CORE_PROXY_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);

        address deployer = vm.addr(deployerPrivateKey);
        console.log("Upgrading with account:", deployer);
        console.log("Account balance:", deployer.balance);
        console.log("Target proxy address:", proxyAddress);

        // Deploy new BridgeCore implementation
        console.log("Deploying new BridgeCore implementation...");
        BridgeCore newImplementation = new BridgeCore();
        address newImplAddress = address(newImplementation);
        console.log("New BridgeCore implementation deployed at:", newImplAddress);

        // Get the proxy contract and upgrade it
        BridgeCore proxy = BridgeCore(proxyAddress);

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
        console.log("BridgeCore proxy:", proxyAddress);
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

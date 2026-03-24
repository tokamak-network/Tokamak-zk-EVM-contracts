// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {BridgeAdminManager} from "../src/BridgeAdminManager.sol";
import {BridgeCore} from "../src/BridgeCore.sol";
import {DAppManager} from "../src/DAppManager.sol";

contract UpgradeBridgeStackScript is Script {
    using stdJson for string;

    struct UpgradeResult {
        address owner;
        address deployer;
        address bridgeAdminManager;
        address bridgeAdminManagerImplementation;
        address dAppManager;
        address dAppManagerImplementation;
        address grothVerifier;
        address tokamakVerifier;
        address bridgeCore;
        address bridgeCoreImplementation;
        address mockAsset;
    }

    function run() external returns (UpgradeResult memory result) {
        uint256 deployerPrivateKey = vm.envUint("BRIDGE_DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        string memory inputPath = _resolvePath(vm.envOr("BRIDGE_INPUT_PATH", string("./deployments/bridge.json")));
        string memory outputPath = _resolvePath(vm.envOr("BRIDGE_OUTPUT_PATH", string("./deployments/bridge.json")));

        string memory existingJson = vm.readFile(inputPath);
        address bridgeAdminManagerProxy = existingJson.readAddress(".bridgeAdminManager");
        address dAppManagerProxy = existingJson.readAddress(".dAppManager");
        address bridgeCoreProxy = existingJson.readAddress(".bridgeCore");

        vm.startBroadcast(deployerPrivateKey);

        BridgeAdminManager bridgeAdminManagerImplementation = new BridgeAdminManager();
        DAppManager dAppManagerImplementation = new DAppManager();
        BridgeCore bridgeCoreImplementation = new BridgeCore();

        BridgeAdminManager adminManagerProxyContract = BridgeAdminManager(bridgeAdminManagerProxy);
        DAppManager dAppManagerProxyContract = DAppManager(dAppManagerProxy);
        BridgeCore bridgeCoreProxyContract = BridgeCore(bridgeCoreProxy);

        adminManagerProxyContract.upgradeTo(address(bridgeAdminManagerImplementation));
        dAppManagerProxyContract.upgradeTo(address(dAppManagerImplementation));
        bridgeCoreProxyContract.upgradeTo(address(bridgeCoreImplementation));

        address owner = bridgeCoreProxyContract.owner();
        address grothVerifier = address(bridgeCoreProxyContract.grothVerifier());
        address tokamakVerifier = address(bridgeCoreProxyContract.tokamakVerifier());

        address mockAsset = address(0);
        if (existingJson.parseRaw(".mockAsset").length != 0) {
            mockAsset = existingJson.readAddress(".mockAsset");
        }

        vm.stopBroadcast();

        result = UpgradeResult({
            owner: owner,
            deployer: deployer,
            bridgeAdminManager: bridgeAdminManagerProxy,
            bridgeAdminManagerImplementation: address(bridgeAdminManagerImplementation),
            dAppManager: dAppManagerProxy,
            dAppManagerImplementation: address(dAppManagerImplementation),
            grothVerifier: grothVerifier,
            tokamakVerifier: tokamakVerifier,
            bridgeCore: bridgeCoreProxy,
            bridgeCoreImplementation: address(bridgeCoreImplementation),
            mockAsset: mockAsset
        });

        _writeDeploymentArtifact(result, inputPath, outputPath);
        _logUpgrade(result);
    }

    function _writeDeploymentArtifact(UpgradeResult memory result, string memory inputPath, string memory outputPath)
        private
    {
        string memory existingJson = vm.readFile(inputPath);
        string memory deploymentJson = "bridgeDeployment";
        vm.serializeAddress(deploymentJson, "owner", result.owner);
        vm.serializeAddress(deploymentJson, "deployer", result.deployer);
        vm.serializeUint(deploymentJson, "merkleTreeLevels", existingJson.readUint(".merkleTreeLevels"));
        if (existingJson.parseRaw(".chainId").length != 0) {
            vm.serializeUint(deploymentJson, "chainId", existingJson.readUint(".chainId"));
        }
        if (existingJson.parseRaw(".abiManifestPath").length != 0) {
            vm.serializeString(deploymentJson, "abiManifestPath", existingJson.readString(".abiManifestPath"));
        }
        vm.serializeString(deploymentJson, "proxyKind", "uups");
        vm.serializeAddress(deploymentJson, "bridgeAdminManager", result.bridgeAdminManager);
        vm.serializeAddress(
            deploymentJson, "bridgeAdminManagerImplementation", result.bridgeAdminManagerImplementation
        );
        vm.serializeAddress(deploymentJson, "dAppManager", result.dAppManager);
        vm.serializeAddress(deploymentJson, "dAppManagerImplementation", result.dAppManagerImplementation);
        vm.serializeAddress(deploymentJson, "grothVerifier", result.grothVerifier);
        vm.serializeAddress(deploymentJson, "tokamakVerifier", result.tokamakVerifier);
        vm.serializeAddress(deploymentJson, "bridgeCore", result.bridgeCore);
        vm.serializeAddress(deploymentJson, "bridgeCoreImplementation", result.bridgeCoreImplementation);
        string memory finalJson = vm.serializeAddress(deploymentJson, "mockAsset", result.mockAsset);
        vm.writeJson(finalJson, outputPath);
    }

    function _logUpgrade(UpgradeResult memory result) private pure {
        console2.log("Bridge deployer:", result.deployer);
        console2.log("Bridge owner:", result.owner);
        console2.log("BridgeAdminManager proxy:", result.bridgeAdminManager);
        console2.log("BridgeAdminManager implementation:", result.bridgeAdminManagerImplementation);
        console2.log("DAppManager proxy:", result.dAppManager);
        console2.log("DAppManager implementation:", result.dAppManagerImplementation);
        console2.log("BridgeCore proxy:", result.bridgeCore);
        console2.log("BridgeCore implementation:", result.bridgeCoreImplementation);
    }

    function _resolvePath(string memory pathValue) private view returns (string memory) {
        bytes memory pathBytes = bytes(pathValue);
        if (pathBytes.length > 0 && pathBytes[0] == "/") {
            return pathValue;
        }
        return string.concat(vm.projectRoot(), "/", pathValue);
    }
}

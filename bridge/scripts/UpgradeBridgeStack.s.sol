// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {BridgeAdminManager} from "../src/BridgeAdminManager.sol";
import {BridgeCore} from "../src/BridgeCore.sol";
import {DAppManager} from "../src/DAppManager.sol";
import {L1TokenVault} from "../src/L1TokenVault.sol";
import {IGrothVerifier} from "../src/interfaces/IGrothVerifier.sol";
import {ITokamakVerifier} from "../src/interfaces/ITokamakVerifier.sol";
import {Groth16Verifier} from "groth16-verifier/src/Groth16Verifier.sol";
import {TokamakVerifier} from "tokamak-zkp/TokamakVerifier.sol";

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
        address bridgeTokenVault;
        address bridgeTokenVaultImplementation;
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
        if (existingJson.parseRaw(".bridgeTokenVault").length == 0) {
            revert("Existing deployment artifact has no shared token-vault proxy. Use redeploy-proxy mode once.");
        }
        address bridgeTokenVaultProxy = existingJson.readAddress(".bridgeTokenVault");

        vm.startBroadcast(deployerPrivateKey);

        BridgeAdminManager bridgeAdminManagerImplementation = new BridgeAdminManager();
        DAppManager dAppManagerImplementation = new DAppManager();
        Groth16Verifier grothVerifierImplementation = new Groth16Verifier();
        TokamakVerifier tokamakVerifierImplementation = new TokamakVerifier();
        BridgeCore bridgeCoreImplementation = new BridgeCore();
        L1TokenVault bridgeTokenVaultImplementation = new L1TokenVault();

        BridgeAdminManager adminManagerProxyContract = BridgeAdminManager(bridgeAdminManagerProxy);
        DAppManager dAppManagerProxyContract = DAppManager(dAppManagerProxy);
        BridgeCore bridgeCoreProxyContract = BridgeCore(bridgeCoreProxy);
        L1TokenVault bridgeTokenVaultProxyContract = L1TokenVault(bridgeTokenVaultProxy);

        adminManagerProxyContract.upgradeTo(address(bridgeAdminManagerImplementation));
        dAppManagerProxyContract.upgradeTo(address(dAppManagerImplementation));
        bridgeCoreProxyContract.upgradeTo(address(bridgeCoreImplementation));
        bridgeTokenVaultProxyContract.upgradeTo(address(bridgeTokenVaultImplementation));
        bridgeCoreProxyContract.setGrothVerifier(IGrothVerifier(address(grothVerifierImplementation)));
        bridgeCoreProxyContract.setTokamakVerifier(ITokamakVerifier(address(tokamakVerifierImplementation)));

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
            bridgeTokenVault: bridgeTokenVaultProxy,
            bridgeTokenVaultImplementation: address(bridgeTokenVaultImplementation),
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
        vm.serializeAddress(deploymentJson, "bridgeAdminManagerImplementation", result.bridgeAdminManagerImplementation);
        vm.serializeAddress(deploymentJson, "dAppManager", result.dAppManager);
        vm.serializeAddress(deploymentJson, "dAppManagerImplementation", result.dAppManagerImplementation);
        vm.serializeAddress(deploymentJson, "grothVerifier", result.grothVerifier);
        vm.serializeAddress(deploymentJson, "tokamakVerifier", result.tokamakVerifier);
        vm.serializeAddress(deploymentJson, "bridgeCore", result.bridgeCore);
        vm.serializeAddress(deploymentJson, "bridgeCoreImplementation", result.bridgeCoreImplementation);
        vm.serializeAddress(deploymentJson, "bridgeTokenVault", result.bridgeTokenVault);
        vm.serializeAddress(deploymentJson, "bridgeTokenVaultImplementation", result.bridgeTokenVaultImplementation);
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
        console2.log("L1TokenVault proxy:", result.bridgeTokenVault);
        console2.log("L1TokenVault implementation:", result.bridgeTokenVaultImplementation);
    }

    function _resolvePath(string memory pathValue) private view returns (string memory) {
        bytes memory pathBytes = bytes(pathValue);
        if (pathBytes.length > 0 && pathBytes[0] == "/") {
            return pathValue;
        }
        return string.concat(vm.projectRoot(), "/", pathValue);
    }
}

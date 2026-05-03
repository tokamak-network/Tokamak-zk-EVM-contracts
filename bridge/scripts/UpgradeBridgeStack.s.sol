// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {BridgeCore} from "../src/BridgeCore.sol";
import {ChannelDeployer} from "../src/ChannelDeployer.sol";
import {DAppManager} from "../src/DAppManager.sol";
import {L1TokenVault} from "../src/L1TokenVault.sol";
import {IGrothVerifier} from "../src/interfaces/IGrothVerifier.sol";
import {ITokamakVerifier} from "../src/interfaces/ITokamakVerifier.sol";
import {Groth16Verifier} from "../src/generated/Groth16Verifier.sol";
import {TokamakVerifier} from "../src/verifiers/TokamakVerifier.sol";

contract UpgradeBridgeStackScript is Script {
    using stdJson for string;

    struct UpgradeResult {
        address owner;
        address deployer;
        address dAppManager;
        address dAppManagerImplementation;
        address grothVerifier;
        address tokamakVerifier;
        address channelDeployer;
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
        string memory grothCompatibleBackendVersion = vm.envString("BRIDGE_GROTH_COMPATIBLE_BACKEND_VERSION");
        string memory tokamakCompatibleBackendVersion = vm.envString("BRIDGE_TOKAMAK_COMPATIBLE_BACKEND_VERSION");

        string memory existingJson = vm.readFile(inputPath);
        address dAppManagerProxy = existingJson.readAddress(".dAppManager");
        address bridgeCoreProxy = existingJson.readAddress(".bridgeCore");
        if (existingJson.parseRaw(".bridgeTokenVault").length == 0) {
            revert("Existing deployment artifact has no shared token-vault proxy. Use redeploy-proxy mode once.");
        }
        address bridgeTokenVaultProxy = existingJson.readAddress(".bridgeTokenVault");

        vm.startBroadcast(deployerPrivateKey);

        DAppManager dAppManagerImplementation = new DAppManager();
        ChannelDeployer channelDeployer = new ChannelDeployer();
        Groth16Verifier grothVerifierImplementation = new Groth16Verifier(grothCompatibleBackendVersion);
        TokamakVerifier tokamakVerifierImplementation = new TokamakVerifier(tokamakCompatibleBackendVersion);
        BridgeCore bridgeCoreImplementation = new BridgeCore();
        L1TokenVault bridgeTokenVaultImplementation = new L1TokenVault();

        DAppManager dAppManagerProxyContract = DAppManager(dAppManagerProxy);
        BridgeCore bridgeCoreProxyContract = BridgeCore(bridgeCoreProxy);
        L1TokenVault bridgeTokenVaultProxyContract = L1TokenVault(bridgeTokenVaultProxy);

        dAppManagerProxyContract.upgradeTo(address(dAppManagerImplementation));
        bridgeCoreProxyContract.upgradeTo(address(bridgeCoreImplementation));
        bridgeTokenVaultProxyContract.upgradeTo(address(bridgeTokenVaultImplementation));
        bridgeCoreProxyContract.setChannelDeployer(channelDeployer);
        bridgeCoreProxyContract.setGrothVerifier(IGrothVerifier(address(grothVerifierImplementation)));
        bridgeCoreProxyContract.setTokamakVerifier(ITokamakVerifier(address(tokamakVerifierImplementation)));
        dAppManagerProxyContract.bindBridgeCore(bridgeCoreProxy);

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
            dAppManager: dAppManagerProxy,
            dAppManagerImplementation: address(dAppManagerImplementation),
            grothVerifier: grothVerifier,
            tokamakVerifier: tokamakVerifier,
            channelDeployer: address(channelDeployer),
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
        vm.serializeAddress(deploymentJson, "dAppManager", result.dAppManager);
        vm.serializeAddress(deploymentJson, "dAppManagerImplementation", result.dAppManagerImplementation);
        vm.serializeAddress(deploymentJson, "grothVerifier", result.grothVerifier);
        vm.serializeString(
            deploymentJson,
            "grothVerifierCompatibleBackendVersion",
            Groth16Verifier(result.grothVerifier).compatibleBackendVersion()
        );
        vm.serializeAddress(deploymentJson, "tokamakVerifier", result.tokamakVerifier);
        vm.serializeString(
            deploymentJson,
            "tokamakVerifierCompatibleBackendVersion",
            TokamakVerifier(result.tokamakVerifier).compatibleBackendVersion()
        );
        vm.serializeAddress(deploymentJson, "channelDeployer", result.channelDeployer);
        vm.serializeAddress(deploymentJson, "bridgeCore", result.bridgeCore);
        vm.serializeAddress(deploymentJson, "bridgeCoreImplementation", result.bridgeCoreImplementation);
        vm.serializeAddress(deploymentJson, "bridgeTokenVault", result.bridgeTokenVault);
        vm.serializeAddress(deploymentJson, "bridgeTokenVaultImplementation", result.bridgeTokenVaultImplementation);
        string memory finalJson = vm.serializeAddress(deploymentJson, "mockAsset", result.mockAsset);
        vm.writeJson(finalJson, outputPath);
    }

    function _logUpgrade(UpgradeResult memory result) private view {
        console2.log("Bridge deployer:", result.deployer);
        console2.log("Bridge owner:", result.owner);
        console2.log("DAppManager proxy:", result.dAppManager);
        console2.log("DAppManager implementation:", result.dAppManagerImplementation);
        console2.log("BridgeCore proxy:", result.bridgeCore);
        console2.log("BridgeCore implementation:", result.bridgeCoreImplementation);
        console2.log("ChannelDeployer:", result.channelDeployer);
        console2.log(
            "Groth16Verifier compatible backend version:",
            Groth16Verifier(result.grothVerifier).compatibleBackendVersion()
        );
        console2.log(
            "TokamakVerifier compatible backend version:",
            TokamakVerifier(result.tokamakVerifier).compatibleBackendVersion()
        );
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

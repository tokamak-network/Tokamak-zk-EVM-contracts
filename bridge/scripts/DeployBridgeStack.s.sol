// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/proxy/ERC1967/ERC1967Proxy.sol";
import {BridgeAdminManager} from "../src/BridgeAdminManager.sol";
import {BridgeCore} from "../src/BridgeCore.sol";
import {ChannelDeployer} from "../src/ChannelDeployer.sol";
import {DAppManager} from "../src/DAppManager.sol";
import {L1TokenVault} from "../src/L1TokenVault.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {IGrothVerifier} from "../src/interfaces/IGrothVerifier.sol";
import {ITokamakVerifier} from "../src/interfaces/ITokamakVerifier.sol";
import {IChannelRegistry} from "../src/interfaces/IChannelRegistry.sol";
import {Groth16Verifier} from "../src/generated/Groth16Verifier.sol";
import {TokamakVerifier} from "../src/verifiers/TokamakVerifier.sol";

contract DeployBridgeStackScript is Script {
    struct DeploymentResult {
        address owner;
        address deployer;
        address bridgeAdminManager;
        address bridgeAdminManagerImplementation;
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

    function run() external returns (DeploymentResult memory result) {
        uint256 deployerPrivateKey = vm.envUint("BRIDGE_DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        address owner = vm.envOr("BRIDGE_OWNER", deployer);
        uint8 merkleTreeLevels = uint8(vm.envUint("BRIDGE_MERKLE_TREE_LEVELS"));
        bool deployMockAsset = vm.envOr("BRIDGE_DEPLOY_MOCK_ASSET", false);
        string memory grothCompatibleBackendVersion = vm.envString("BRIDGE_GROTH_COMPATIBLE_BACKEND_VERSION");
        string memory tokamakCompatibleBackendVersion = vm.envString("BRIDGE_TOKAMAK_COMPATIBLE_BACKEND_VERSION");
        string memory outputPath = _resolvePath(vm.envOr("BRIDGE_OUTPUT_PATH", string("./deployments/bridge.json")));

        vm.startBroadcast(deployerPrivateKey);

        BridgeAdminManager adminManagerImplementation = new BridgeAdminManager();
        DAppManager dAppManagerImplementation = new DAppManager();
        ChannelDeployer channelDeployer = new ChannelDeployer();
        Groth16Verifier grothVerifier = new Groth16Verifier(grothCompatibleBackendVersion);
        TokamakVerifier tokamakVerifier = new TokamakVerifier(tokamakCompatibleBackendVersion);
        BridgeCore bridgeCoreImplementation = new BridgeCore();
        L1TokenVault bridgeTokenVaultImplementation = new L1TokenVault();

        ERC1967Proxy adminManagerProxy = new ERC1967Proxy(
            address(adminManagerImplementation),
            abi.encodeCall(BridgeAdminManager.initialize, (owner, merkleTreeLevels))
        );
        ERC1967Proxy dAppManagerProxy =
            new ERC1967Proxy(address(dAppManagerImplementation), abi.encodeCall(DAppManager.initialize, (deployer)));
        ERC1967Proxy bridgeCoreProxy = new ERC1967Proxy(
            address(bridgeCoreImplementation),
            abi.encodeCall(
                BridgeCore.initialize,
                (
                    deployer,
                    BridgeAdminManager(address(adminManagerProxy)),
                    DAppManager(address(dAppManagerProxy)),
                    channelDeployer,
                    IGrothVerifier(address(grothVerifier)),
                    ITokamakVerifier(address(tokamakVerifier))
                )
            )
        );
        ERC1967Proxy bridgeTokenVaultProxy = new ERC1967Proxy(
            address(bridgeTokenVaultImplementation),
            abi.encodeCall(
                L1TokenVault.initialize,
                (
                    owner,
                    IERC20(BridgeCore(address(bridgeCoreProxy)).canonicalAsset()),
                    IChannelRegistry(address(bridgeCoreProxy))
                )
            )
        );

        BridgeCore(address(bridgeCoreProxy)).bindBridgeTokenVault(address(bridgeTokenVaultProxy));
        DAppManager(address(dAppManagerProxy)).bindBridgeCore(address(bridgeCoreProxy));
        if (owner != deployer) {
            DAppManager(address(dAppManagerProxy)).transferOwnership(owner);
            BridgeCore(address(bridgeCoreProxy)).transferOwnership(owner);
        }

        address mockAsset = address(0);
        if (deployMockAsset) {
            string memory mockAssetName = vm.envOr("BRIDGE_MOCK_ASSET_NAME", string("Bridge Test Asset"));
            string memory mockAssetSymbol = vm.envOr("BRIDGE_MOCK_ASSET_SYMBOL", string("BTA"));
            mockAsset = address(new MockERC20(mockAssetName, mockAssetSymbol));
        }

        vm.stopBroadcast();

        result = DeploymentResult({
            owner: owner,
            deployer: deployer,
            bridgeAdminManager: address(adminManagerProxy),
            bridgeAdminManagerImplementation: address(adminManagerImplementation),
            dAppManager: address(dAppManagerProxy),
            dAppManagerImplementation: address(dAppManagerImplementation),
            grothVerifier: address(grothVerifier),
            tokamakVerifier: address(tokamakVerifier),
            channelDeployer: address(channelDeployer),
            bridgeCore: address(bridgeCoreProxy),
            bridgeCoreImplementation: address(bridgeCoreImplementation),
            bridgeTokenVault: address(bridgeTokenVaultProxy),
            bridgeTokenVaultImplementation: address(bridgeTokenVaultImplementation),
            mockAsset: mockAsset
        });

        _writeDeploymentArtifact(result, merkleTreeLevels, outputPath);
        _logDeployment(result, merkleTreeLevels);
    }

    function _writeDeploymentArtifact(DeploymentResult memory result, uint8 merkleTreeLevels, string memory outputPath)
        private
    {
        string memory deploymentJson = "bridgeDeployment";
        vm.serializeAddress(deploymentJson, "owner", result.owner);
        vm.serializeAddress(deploymentJson, "deployer", result.deployer);
        vm.serializeUint(deploymentJson, "merkleTreeLevels", merkleTreeLevels);
        vm.serializeString(deploymentJson, "proxyKind", "uups");
        vm.serializeAddress(deploymentJson, "bridgeAdminManager", result.bridgeAdminManager);
        vm.serializeAddress(deploymentJson, "bridgeAdminManagerImplementation", result.bridgeAdminManagerImplementation);
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

    function _logDeployment(DeploymentResult memory result, uint8 merkleTreeLevels) private view {
        console2.log("Bridge deployer:", result.deployer);
        console2.log("Bridge owner:", result.owner);
        console2.log("Proxy kind: UUPS");
        console2.log("Merkle tree levels:", merkleTreeLevels);
        console2.log("BridgeAdminManager proxy:", result.bridgeAdminManager);
        console2.log("BridgeAdminManager implementation:", result.bridgeAdminManagerImplementation);
        console2.log("DAppManager proxy:", result.dAppManager);
        console2.log("DAppManager implementation:", result.dAppManagerImplementation);
        console2.log("Groth16Verifier:", result.grothVerifier);
        console2.log(
            "Groth16Verifier compatible backend version:",
            Groth16Verifier(result.grothVerifier).compatibleBackendVersion()
        );
        console2.log("TokamakVerifier:", result.tokamakVerifier);
        console2.log(
            "TokamakVerifier compatible backend version:",
            TokamakVerifier(result.tokamakVerifier).compatibleBackendVersion()
        );
        console2.log("ChannelDeployer:", result.channelDeployer);
        console2.log("BridgeCore proxy:", result.bridgeCore);
        console2.log("BridgeCore implementation:", result.bridgeCoreImplementation);
        console2.log("L1TokenVault proxy:", result.bridgeTokenVault);
        console2.log("L1TokenVault implementation:", result.bridgeTokenVaultImplementation);
        console2.log("Mock asset:", result.mockAsset);
    }

    function _resolvePath(string memory pathValue) private view returns (string memory) {
        bytes memory pathBytes = bytes(pathValue);
        if (pathBytes.length > 0 && pathBytes[0] == "/") {
            return pathValue;
        }
        return string.concat(vm.projectRoot(), "/", pathValue);
    }
}

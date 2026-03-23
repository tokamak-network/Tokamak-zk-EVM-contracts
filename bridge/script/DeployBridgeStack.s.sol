// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {BridgeAdminManager} from "../src/BridgeAdminManager.sol";
import {BridgeCore} from "../src/BridgeCore.sol";
import {DAppManager} from "../src/DAppManager.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {IGrothVerifier} from "../src/interfaces/IGrothVerifier.sol";
import {ITokamakVerifier} from "../src/interfaces/ITokamakVerifier.sol";
import {Groth16Verifier} from "groth16-verifier/src/Groth16Verifier.sol";
import {TokamakVerifier} from "tokamak-zkp/TokamakVerifier.sol";

contract DeployBridgeStackScript is Script {
    struct DeploymentResult {
        address owner;
        address deployer;
        address bridgeAdminManager;
        address dAppManager;
        address grothVerifier;
        address tokamakVerifier;
        address bridgeCore;
        address mockAsset;
    }

    function run() external returns (DeploymentResult memory result) {
        uint256 deployerPrivateKey = vm.envUint("BRIDGE_DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        address owner = vm.envOr("BRIDGE_OWNER", deployer);
        uint8 merkleTreeLevels = uint8(vm.envOr("BRIDGE_MERKLE_TREE_LEVELS", uint256(12)));
        bool deployMockAsset = vm.envOr("BRIDGE_DEPLOY_MOCK_ASSET", false);
        string memory outputPath = vm.envOr("BRIDGE_OUTPUT_PATH", string("./deployments/bridge-latest.json"));

        vm.startBroadcast(deployerPrivateKey);

        BridgeAdminManager adminManager = new BridgeAdminManager(deployer);
        adminManager.setMerkleTreeLevels(merkleTreeLevels);

        DAppManager dAppManager = new DAppManager(deployer);
        Groth16Verifier grothVerifier = new Groth16Verifier();
        TokamakVerifier tokamakVerifier = new TokamakVerifier();
        BridgeCore bridgeCore = new BridgeCore(
            deployer,
            adminManager,
            dAppManager,
            IGrothVerifier(address(grothVerifier)),
            ITokamakVerifier(address(tokamakVerifier))
        );

        address mockAsset = address(0);
        if (deployMockAsset) {
            string memory mockAssetName = vm.envOr("BRIDGE_MOCK_ASSET_NAME", string("Bridge Test Asset"));
            string memory mockAssetSymbol = vm.envOr("BRIDGE_MOCK_ASSET_SYMBOL", string("BTA"));
            mockAsset = address(new MockERC20(mockAssetName, mockAssetSymbol));
        }

        if (owner != deployer) {
            adminManager.transferOwnership(owner);
            dAppManager.transferOwnership(owner);
            bridgeCore.transferOwnership(owner);
        }

        vm.stopBroadcast();

        result = DeploymentResult({
            owner: owner,
            deployer: deployer,
            bridgeAdminManager: address(adminManager),
            dAppManager: address(dAppManager),
            grothVerifier: address(grothVerifier),
            tokamakVerifier: address(tokamakVerifier),
            bridgeCore: address(bridgeCore),
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
        vm.serializeAddress(deploymentJson, "bridgeAdminManager", result.bridgeAdminManager);
        vm.serializeAddress(deploymentJson, "dAppManager", result.dAppManager);
        vm.serializeAddress(deploymentJson, "grothVerifier", result.grothVerifier);
        vm.serializeAddress(deploymentJson, "tokamakVerifier", result.tokamakVerifier);
        vm.serializeAddress(deploymentJson, "bridgeCore", result.bridgeCore);
        string memory finalJson = vm.serializeAddress(deploymentJson, "mockAsset", result.mockAsset);
        vm.writeJson(finalJson, outputPath);
    }

    function _logDeployment(DeploymentResult memory result, uint8 merkleTreeLevels) private pure {
        console2.log("Bridge deployer:", result.deployer);
        console2.log("Bridge owner:", result.owner);
        console2.log("Merkle tree levels:", merkleTreeLevels);
        console2.log("BridgeAdminManager:", result.bridgeAdminManager);
        console2.log("DAppManager:", result.dAppManager);
        console2.log("Groth16Verifier:", result.grothVerifier);
        console2.log("TokamakVerifier:", result.tokamakVerifier);
        console2.log("BridgeCore:", result.bridgeCore);
        console2.log("Mock asset:", result.mockAsset);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import "forge-std/Script.sol";
import "../../src/L2AccountingVault.sol";
import "../../src/PrivateNullifierRegistry.sol";
import "../../src/PrivateNoteRegistry.sol";
import "../../src/PrivateStateController.sol";
import "./PrivateStateDeploymentFactory.sol";

contract DeployPrivateStateScript is Script {
    bytes32 internal constant L2_ACCOUNTING_VAULT_SALT = keccak256("private-state.l2-accounting-vault");
    bytes32 internal constant NOTE_REGISTRY_SALT = keccak256("private-state.note-registry");
    bytes32 internal constant NULLIFIER_REGISTRY_SALT = keccak256("private-state.nullifier-registry");

    address public deployer;
    address public canonicalAsset;
    address public testingBalanceSetter;
    address public deploymentFactory;

    address public l2AccountingVault;
    address public noteRegistry;
    address public nullifierRegistry;
    address public controller;

    function setUp() public {
        canonicalAsset = vm.envAddress("PRIVATE_STATE_CANONICAL_ASSET");
        testingBalanceSetter = vm.envOr("PRIVATE_STATE_TESTING_BALANCE_SETTER", address(0));
    }

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("APPS_DEPLOYER_PRIVATE_KEY");
        deployer = vm.addr(deployerPrivateKey);
        canonicalAsset = vm.envAddress("PRIVATE_STATE_CANONICAL_ASSET");
        testingBalanceSetter = vm.envOr("PRIVATE_STATE_TESTING_BALANCE_SETTER", address(0));

        vm.startBroadcast(deployerPrivateKey);

        PrivateStateDeploymentFactory factory = new PrivateStateDeploymentFactory();
        deploymentFactory = address(factory);

        address predictedController = vm.computeCreateAddress(address(factory), 1);
        address predictedL2AccountingVault = vm.computeCreate2Address(
            L2_ACCOUNTING_VAULT_SALT,
            _l2AccountingVaultInitCodeHash(predictedController, testingBalanceSetter),
            address(factory)
        );
        address predictedNoteRegistry =
            vm.computeCreate2Address(NOTE_REGISTRY_SALT, _noteRegistryInitCodeHash(predictedController), address(factory));
        address predictedNullifierRegistry = vm.computeCreate2Address(
            NULLIFIER_REGISTRY_SALT, _nullifierRegistryInitCodeHash(predictedController), address(factory)
        );

        PrivateStateController controllerContract = factory.deployController(
            predictedNoteRegistry, predictedNullifierRegistry, predictedL2AccountingVault, canonicalAsset
        );
        L2AccountingVault l2AccountingVaultContract =
            factory.deployL2AccountingVault(L2_ACCOUNTING_VAULT_SALT, predictedController, testingBalanceSetter);
        PrivateNoteRegistry noteRegistryContract =
            factory.deployPrivateNoteRegistry(NOTE_REGISTRY_SALT, predictedController);
        PrivateNullifierRegistry nullifierRegistryContract =
            factory.deployPrivateNullifierRegistry(NULLIFIER_REGISTRY_SALT, predictedController);

        vm.stopBroadcast();

        l2AccountingVault = address(l2AccountingVaultContract);
        noteRegistry = address(noteRegistryContract);
        nullifierRegistry = address(nullifierRegistryContract);
        controller = address(controllerContract);

        require(controller == predictedController, "controller prediction mismatch");
        require(l2AccountingVault == predictedL2AccountingVault, "vault prediction mismatch");
        require(noteRegistry == predictedNoteRegistry, "note registry prediction mismatch");
        require(nullifierRegistry == predictedNullifierRegistry, "nullifier registry prediction mismatch");

        console.log("DeployPrivateStateScript complete");
        console.log("deployer", deployer);
        console.log("deploymentFactory", deploymentFactory);
        console.log("owner", deployer);
        console.log("canonicalAsset", canonicalAsset);
        console.log("testingBalanceSetter", testingBalanceSetter);
        console.log("l2AccountingVault", l2AccountingVault);
        console.log("noteRegistry", noteRegistry);
        console.log("nullifierRegistry", nullifierRegistry);
        console.log("controller", controller);
    }

    function _l2AccountingVaultInitCodeHash(address controller_, address testingBalanceSetter_)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(
            abi.encodePacked(type(L2AccountingVault).creationCode, abi.encode(controller_, testingBalanceSetter_))
        );
    }

    function _noteRegistryInitCodeHash(address controller_) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(type(PrivateNoteRegistry).creationCode, abi.encode(controller_)));
    }

    function _nullifierRegistryInitCodeHash(address controller_) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(type(PrivateNullifierRegistry).creationCode, abi.encode(controller_)));
    }
}

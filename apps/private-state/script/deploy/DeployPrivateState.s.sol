// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import "forge-std/Script.sol";
import "../../src/L2AccountingVault.sol";
import "../../src/PrivateStateController.sol";
import "./PrivateStateDeploymentFactory.sol";

contract DeployPrivateStateScript is Script {
    bytes32 internal constant L2_ACCOUNTING_VAULT_SALT = keccak256("private-state.l2-accounting-vault");

    address public deployer;
    address public deploymentFactory;

    address public l2AccountingVault;
    address public controller;

    function setUp() public {}

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("APPS_DEPLOYER_PRIVATE_KEY");
        deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        PrivateStateDeploymentFactory factory = new PrivateStateDeploymentFactory();
        deploymentFactory = address(factory);

        address predictedController = vm.computeCreateAddress(address(factory), 1);
        address predictedL2AccountingVault = vm.computeCreate2Address(
            L2_ACCOUNTING_VAULT_SALT, _l2AccountingVaultInitCodeHash(predictedController), address(factory)
        );

        PrivateStateController controllerContract = factory.deployController(predictedL2AccountingVault);
        L2AccountingVault l2AccountingVaultContract =
            factory.deployL2AccountingVault(L2_ACCOUNTING_VAULT_SALT, predictedController);

        vm.stopBroadcast();

        l2AccountingVault = address(l2AccountingVaultContract);
        controller = address(controllerContract);

        require(controller == predictedController, "controller prediction mismatch");
        require(l2AccountingVault == predictedL2AccountingVault, "vault prediction mismatch");

        console.log("DeployPrivateStateScript complete");
        console.log("deployer", deployer);
        console.log("deploymentFactory", deploymentFactory);
        console.log("owner", deployer);
        console.log("l2AccountingVault", l2AccountingVault);
        console.log("controller", controller);
    }

    function _l2AccountingVaultInitCodeHash(address controller_) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(type(L2AccountingVault).creationCode, abi.encode(controller_)));
    }
}

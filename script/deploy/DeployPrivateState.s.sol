// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import "forge-std/Script.sol";
import "../../apps/private-state/src/L2AccountingVault.sol";
import "../../apps/private-state/src/PrivateNullifierRegistry.sol";
import "../../apps/private-state/src/PrivateNoteRegistry.sol";
import "../../apps/private-state/src/PrivateStateController.sol";

contract DeployPrivateStateScript is Script {
    address public deployer;
    address public finalOwner;
    address public canonicalAsset;

    address public l2AccountingVault;
    address public noteRegistry;
    address public nullifierRegistry;
    address public controller;

    function setUp() public {
        canonicalAsset = vm.envAddress("PRIVATE_STATE_CANONICAL_ASSET");
    }

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        deployer = vm.addr(deployerPrivateKey);
        finalOwner = _loadFinalOwner(deployer);
        canonicalAsset = vm.envAddress("PRIVATE_STATE_CANONICAL_ASSET");

        vm.startBroadcast(deployerPrivateKey);

        L2AccountingVault l2AccountingVaultContract = new L2AccountingVault(deployer);
        PrivateNoteRegistry noteRegistryContract = new PrivateNoteRegistry(deployer);
        PrivateNullifierRegistry nullifierRegistryContract = new PrivateNullifierRegistry(deployer);
        PrivateStateController controllerContract = new PrivateStateController(
            noteRegistryContract, nullifierRegistryContract, l2AccountingVaultContract, canonicalAsset
        );

        l2AccountingVaultContract.bindController(address(controllerContract));
        noteRegistryContract.bindController(address(controllerContract));
        nullifierRegistryContract.bindController(address(controllerContract));

        if (finalOwner != deployer) {
            l2AccountingVaultContract.transferOwnership(finalOwner);
            noteRegistryContract.transferOwnership(finalOwner);
            nullifierRegistryContract.transferOwnership(finalOwner);
        }

        vm.stopBroadcast();

        l2AccountingVault = address(l2AccountingVaultContract);
        noteRegistry = address(noteRegistryContract);
        nullifierRegistry = address(nullifierRegistryContract);
        controller = address(controllerContract);

        console.log("DeployPrivateStateScript complete");
        console.log("deployer", deployer);
        console.log("finalOwner", finalOwner);
        console.log("canonicalAsset", canonicalAsset);
        console.log("l2AccountingVault", l2AccountingVault);
        console.log("noteRegistry", noteRegistry);
        console.log("nullifierRegistry", nullifierRegistry);
        console.log("controller", controller);
    }

    function _loadFinalOwner(address defaultOwner) internal view returns (address owner) {
        try vm.envAddress("PRIVATE_STATE_OWNER") returns (address configuredOwner) {
            owner = configuredOwner;
        } catch {
            owner = defaultOwner;
        }
    }
}

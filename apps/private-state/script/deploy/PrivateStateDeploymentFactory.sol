// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import "../../src/L2AccountingVault.sol";
import "../../src/PrivateNullifierRegistry.sol";
import "../../src/PrivateNoteRegistry.sol";
import "../../src/PrivateStateController.sol";

contract PrivateStateDeploymentFactory {
    function deployController(
        address noteRegistry,
        address nullifierStore,
        address l2AccountingVault,
        address canonicalAsset
    ) external returns (PrivateStateController controller) {
        controller = new PrivateStateController(
            PrivateNoteRegistry(noteRegistry),
            PrivateNullifierRegistry(nullifierStore),
            L2AccountingVault(l2AccountingVault),
            canonicalAsset
        );
    }

    function deployL2AccountingVault(bytes32 salt, address controller) external returns (L2AccountingVault vault) {
        vault = new L2AccountingVault{salt: salt}(controller);
    }

    function deployPrivateNoteRegistry(bytes32 salt, address controller) external returns (PrivateNoteRegistry registry) {
        registry = new PrivateNoteRegistry{salt: salt}(controller);
    }

    function deployPrivateNullifierRegistry(bytes32 salt, address controller)
        external
        returns (PrivateNullifierRegistry registry)
    {
        registry = new PrivateNullifierRegistry{salt: salt}(controller);
    }
}

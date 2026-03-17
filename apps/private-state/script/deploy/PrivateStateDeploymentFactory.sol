// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import "../../src/L2AccountingVault.sol";
import "../../src/PrivateStateController.sol";

contract PrivateStateDeploymentFactory {
    function deployController(address l2AccountingVault) external returns (PrivateStateController controller) {
        controller = new PrivateStateController(L2AccountingVault(l2AccountingVault));
    }

    function deployL2AccountingVault(bytes32 salt, address controller) external returns (L2AccountingVault vault) {
        vault = new L2AccountingVault{salt: salt}(controller);
    }
}

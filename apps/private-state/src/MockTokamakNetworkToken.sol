// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {ERC20} from "@openzeppelin/token/ERC20/ERC20.sol";

/// @title MockTokamakNetworkToken
/// @notice Local-development TON mock for app testing on anvil.
contract MockTokamakNetworkToken is ERC20 {
    constructor(address initialHolder, uint256 initialSupply) ERC20("Tokamak Network Token", "TON") {
        _mint(initialHolder, initialSupply);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

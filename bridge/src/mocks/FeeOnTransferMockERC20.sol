// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ERC20 } from "@openzeppelin/token/ERC20/ERC20.sol";

contract FeeOnTransferMockERC20 is ERC20 {
    uint256 public immutable feeBps;
    address public immutable feeRecipient;

    constructor(string memory name_, string memory symbol_, uint256 feeBps_, address feeRecipient_)
        ERC20(name_, symbol_)
    {
        feeBps = feeBps_;
        feeRecipient = feeRecipient_;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function _update(address from, address to, uint256 value) internal override {
        if (from == address(0) || to == address(0) || feeBps == 0) {
            super._update(from, to, value);
            return;
        }

        uint256 fee = (value * feeBps) / 10_000;
        uint256 netAmount = value - fee;

        super._update(from, feeRecipient, fee);
        super._update(from, to, netAmount);
    }
}

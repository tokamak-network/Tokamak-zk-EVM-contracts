// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

/// @title L2AccountingVault
/// @notice Tracks per-account L2 accounting balances for a bridge-managed custody model.
contract L2AccountingVault {
    uint256 private constant BLS12_381_SCALAR_FIELD_ORDER =
        52435875175126190479447740508185965837690552500527637822603658699938581184512;
    uint256 private constant MAX_LIQUID_BALANCE = BLS12_381_SCALAR_FIELD_ORDER - 1;

    error ZeroAddress();
    error ZeroAmount();
    error UnauthorizedController(address caller);
    error InsufficientLiquidBalance(address account, uint256 available, uint256 required);
    error LiquidBalanceOverflow(address account, uint256 available, uint256 incoming);

    mapping(address account => uint256 amount) public liquidBalances;

    address public immutable controller;

    constructor(address controller_) {
        if (controller_ == address(0)) {
            revert ZeroAddress();
        }

        controller = controller_;
    }

    modifier onlyController() {
        if (msg.sender != controller) {
            revert UnauthorizedController(msg.sender);
        }
        _;
    }

    function creditLiquidBalance(address account, uint256 amount) external onlyController {
        if (account == address(0)) {
            revert ZeroAddress();
        }
        if (amount == 0) {
            revert ZeroAmount();
        }

        uint256 available = liquidBalances[account];
        if (available >= BLS12_381_SCALAR_FIELD_ORDER || amount >= BLS12_381_SCALAR_FIELD_ORDER) {
            revert LiquidBalanceOverflow(account, available, amount);
        }
        if (available > MAX_LIQUID_BALANCE - amount) {
            revert LiquidBalanceOverflow(account, available, amount);
        }

        liquidBalances[account] = available + amount;
    }

    function debitLiquidBalance(address account, uint256 amount) external onlyController {
        if (account == address(0)) {
            revert ZeroAddress();
        }
        if (amount == 0) {
            revert ZeroAmount();
        }

        uint256 available = liquidBalances[account];
        if (available < amount) {
            revert InsufficientLiquidBalance(account, available, amount);
        }

        liquidBalances[account] = available - amount;
    }
}

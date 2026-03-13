// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

/// @title L2AccountingVault
/// @notice Tracks per-account L2 accounting balances for a bridge-managed custody model.
contract L2AccountingVault {
    error ZeroAddress();
    error ZeroAmount();
    error UnauthorizedController(address caller);
    error UnauthorizedTestingBalanceSetter(address caller);
    error InsufficientLiquidBalance(address account, uint256 available, uint256 required);

    event ControllerBound(address indexed controller);
    event TestingBalanceSetterConfigured(address indexed testingBalanceSetter);
    event LiquidBalanceCredited(address indexed account, uint256 amount);
    event LiquidBalanceDebited(address indexed account, uint256 amount);
    event LiquidBalanceSetForTesting(address indexed account, uint256 previousAmount, uint256 newAmount);

    mapping(address account => uint256 amount) public liquidBalances;

    address public immutable controller;
    address public immutable testingBalanceSetter;

    constructor(address controller_, address testingBalanceSetter_) {
        if (controller_ == address(0)) {
            revert ZeroAddress();
        }

        controller = controller_;
        testingBalanceSetter = testingBalanceSetter_;
        emit ControllerBound(controller_);
        emit TestingBalanceSetterConfigured(testingBalanceSetter_);
    }

    modifier onlyController() {
        if (msg.sender != controller) {
            revert UnauthorizedController(msg.sender);
        }
        _;
    }

    modifier onlyTestingBalanceSetter() {
        if (msg.sender != testingBalanceSetter) {
            revert UnauthorizedTestingBalanceSetter(msg.sender);
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

        liquidBalances[account] += amount;
        emit LiquidBalanceCredited(account, amount);
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
        emit LiquidBalanceDebited(account, amount);
    }

    function setLiquidBalanceForTesting(address account, uint256 amount) external onlyTestingBalanceSetter {
        if (account == address(0)) {
            revert ZeroAddress();
        }

        uint256 previousAmount = liquidBalances[account];
        liquidBalances[account] = amount;
        emit LiquidBalanceSetForTesting(account, previousAmount, amount);
    }
}

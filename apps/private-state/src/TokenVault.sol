// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {Ownable} from "@openzeppelin/access/Ownable.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";

/// @title TokenVault
/// @notice Custodies ERC-20 tokens and tracks each account's liquid balance inside the DApp.
contract TokenVault is Ownable {
    using SafeERC20 for IERC20;

    error ZeroAddress();
    error ZeroAmount();
    error UnauthorizedController(address caller);
    error InsufficientLiquidBalance(address account, address token, uint256 available, uint256 required);

    event ControllerUpdated(address indexed controller);
    event Deposited(address indexed payer, address indexed beneficiary, address indexed token, uint256 amount);
    event LiquidBalanceCredited(address indexed account, address indexed token, uint256 amount);
    event LiquidBalanceDebited(address indexed account, address indexed token, uint256 amount);
    event Withdrawn(address indexed account, address indexed receiver, address indexed token, uint256 amount);

    mapping(address account => mapping(address token => uint256 amount)) public liquidBalances;

    address public controller;

    constructor(address initialOwner) Ownable(initialOwner) {}

    modifier onlyController() {
        if (msg.sender != controller) {
            revert UnauthorizedController(msg.sender);
        }
        _;
    }

    function setController(address newController) external onlyOwner {
        if (newController == address(0)) {
            revert ZeroAddress();
        }

        controller = newController;
        emit ControllerUpdated(newController);
    }

    function deposit(address token, address payer, address beneficiary, uint256 amount) external onlyController {
        if (token == address(0) || payer == address(0) || beneficiary == address(0)) {
            revert ZeroAddress();
        }
        if (amount == 0) {
            revert ZeroAmount();
        }

        IERC20(token).safeTransferFrom(payer, address(this), amount);
        liquidBalances[beneficiary][token] += amount;

        emit Deposited(payer, beneficiary, token, amount);
    }

    function creditLiquidBalance(address account, address token, uint256 amount) external onlyController {
        if (account == address(0) || token == address(0)) {
            revert ZeroAddress();
        }
        if (amount == 0) {
            revert ZeroAmount();
        }

        liquidBalances[account][token] += amount;
        emit LiquidBalanceCredited(account, token, amount);
    }

    function debitLiquidBalance(address account, address token, uint256 amount) external onlyController {
        if (account == address(0) || token == address(0)) {
            revert ZeroAddress();
        }
        if (amount == 0) {
            revert ZeroAmount();
        }

        uint256 available = liquidBalances[account][token];
        if (available < amount) {
            revert InsufficientLiquidBalance(account, token, available, amount);
        }

        liquidBalances[account][token] = available - amount;
        emit LiquidBalanceDebited(account, token, amount);
    }

    function withdraw(address token, address account, address receiver, uint256 amount) external onlyController {
        if (token == address(0) || account == address(0) || receiver == address(0)) {
            revert ZeroAddress();
        }
        if (amount == 0) {
            revert ZeroAmount();
        }

        uint256 available = liquidBalances[account][token];
        if (available < amount) {
            revert InsufficientLiquidBalance(account, token, available, amount);
        }

        liquidBalances[account][token] = available - amount;
        IERC20(token).safeTransfer(receiver, amount);

        emit Withdrawn(account, receiver, token, amount);
    }
}

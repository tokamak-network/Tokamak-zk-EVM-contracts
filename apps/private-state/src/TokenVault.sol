// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {Ownable} from "@openzeppelin/access/Ownable.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";

/// @title TokenVault
/// @notice Custodies the Tokamak Network Token and tracks each account's liquid balance inside the DApp.
contract TokenVault is Ownable {
    using SafeERC20 for IERC20;

    error ZeroAddress();
    error ZeroAmount();
    error ControllerAlreadyBound();
    error UnauthorizedController(address caller);
    error InsufficientLiquidBalance(address account, uint256 available, uint256 required);

    event ControllerBound(address indexed controller);
    event Deposited(address indexed payer, address indexed beneficiary, uint256 amount);
    event LiquidBalanceCredited(address indexed account, uint256 amount);
    event LiquidBalanceDebited(address indexed account, uint256 amount);
    event Withdrawn(address indexed account, address indexed receiver, uint256 amount);

    IERC20 public immutable tokamakNetworkToken;

    mapping(address account => uint256 amount) public liquidBalances;

    address public controller;

    constructor(address initialOwner, address tokamakNetworkToken_) Ownable(initialOwner) {
        if (tokamakNetworkToken_ == address(0)) {
            revert ZeroAddress();
        }

        tokamakNetworkToken = IERC20(tokamakNetworkToken_);
    }

    modifier onlyController() {
        if (msg.sender != controller) {
            revert UnauthorizedController(msg.sender);
        }
        _;
    }

    function bindController(address newController) external onlyOwner {
        if (newController == address(0)) {
            revert ZeroAddress();
        }
        if (controller != address(0)) {
            revert ControllerAlreadyBound();
        }

        controller = newController;
        emit ControllerBound(newController);
    }

    function deposit(address payer, address beneficiary, uint256 amount) external onlyController {
        if (payer == address(0) || beneficiary == address(0)) {
            revert ZeroAddress();
        }
        if (amount == 0) {
            revert ZeroAmount();
        }

        tokamakNetworkToken.safeTransferFrom(payer, address(this), amount);
        liquidBalances[beneficiary] += amount;

        emit Deposited(payer, beneficiary, amount);
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

    function withdraw(address account, address receiver, uint256 amount) external onlyController {
        if (account == address(0) || receiver == address(0)) {
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
        tokamakNetworkToken.safeTransfer(receiver, amount);

        emit Withdrawn(account, receiver, amount);
    }
}

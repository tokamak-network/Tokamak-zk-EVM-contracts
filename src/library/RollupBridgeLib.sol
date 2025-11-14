// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import "lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/IERC20Upgradeable.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";

/**
 * @title RollupBridgeLib
 * @notice Library for RollupBridge utility functions to reduce contract size
 * @dev Extracted from RollupBridge to comply with EIP-170 contract size limits
 */
library RollupBridgeLib {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    // ========== FUNCTIONS ==========

    /**
     * @notice Derives an Ethereum-style address from the uncompressed public key (x||y)
     * @param pkx The x coordinate of the public key
     * @param pky The y coordinate of the public key
     * @return The derived Ethereum address
     */
    function deriveAddressFromPubkey(uint256 pkx, uint256 pky) internal pure returns (address) {
        bytes32 h = keccak256(abi.encodePacked(pkx, pky));
        return address(uint160(uint256(h)));
    }

    /**
     * @notice Internal function to handle token deposits with fee-on-transfer support
     * @param _from The address depositing tokens
     * @param _token The token contract
     * @param _amount The amount to deposit
     * @return The actual amount deposited (after any fees)
     */
    function depositToken(address _from, IERC20Upgradeable _token, uint256 _amount) internal returns (uint256) {
        // Check that user has sufficient balance
        uint256 userBalance = _token.balanceOf(_from);
        require(
            userBalance >= _amount,
            string(abi.encodePacked("Insufficient token balance: ", toString(userBalance), " < ", toString(_amount)))
        );

        // Check that user has approved sufficient allowance
        uint256 userAllowance = _token.allowance(_from, address(this));
        require(
            userAllowance >= _amount,
            string(
                abi.encodePacked("Insufficient token allowance: ", toString(userAllowance), " < ", toString(_amount))
            )
        );

        uint256 balanceBefore = _token.balanceOf(address(this));

        // Use SafeERC20's safeTransferFrom - this will handle USDT's void return properly
        _token.safeTransferFrom(_from, address(this), _amount);

        uint256 balanceAfter = _token.balanceOf(address(this));

        // Handle fee-on-transfer tokens like USDT (though fees are currently disabled)
        uint256 actualAmount = balanceAfter - balanceBefore;
        require(actualAmount > 0, "No tokens transferred");

        return actualAmount;
    }

    /**
     * @notice Converts uint256 to string
     * @param value The value to convert
     * @return The string representation
     */
    function toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }
}

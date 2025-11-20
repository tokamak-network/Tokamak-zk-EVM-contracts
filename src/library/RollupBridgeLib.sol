// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import "lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/IERC20Upgradeable.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "../interface/IGroth16Verifier16Leaves.sol";
import "../interface/IGroth16Verifier32Leaves.sol";
import "../interface/IGroth16Verifier64Leaves.sol";
import "../interface/IGroth16Verifier128Leaves.sol";

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

    /**
     * @notice Determines the required tree size based on number of participants and tokens
     * @param participantCount Number of participants
     * @param tokenCount Number of tokens
     * @return The required tree size (16, 32, 64, or 128)
     */
    function determineTreeSize(uint256 participantCount, uint256 tokenCount) internal pure returns (uint256) {
        uint256 totalLeaves = participantCount * tokenCount;

        if (totalLeaves <= 16) {
            return 16;
        } else if (totalLeaves <= 32) {
            return 32;
        } else if (totalLeaves <= 64) {
            return 64;
        } else if (totalLeaves <= 128) {
            return 128;
        } else {
            revert("Too many participant-token combinations");
        }
    }

    /**
     * @notice Verifies Groth16 proof using the appropriate verifier based on tree size
     * @param treeSize The required tree size (16, 32, 64, or 128)
     * @param verifier16 The 16-leaf verifier contract
     * @param verifier32 The 32-leaf verifier contract
     * @param verifier64 The 64-leaf verifier contract
     * @param verifier128 The 128-leaf verifier contract
     * @param pA The A component of the proof
     * @param pB The B component of the proof
     * @param pC The C component of the proof
     * @param publicSignals The public signals for verification
     * @return True if the proof is valid
     */
    function verifyGroth16Proof(
        uint256 treeSize,
        IGroth16Verifier16Leaves verifier16,
        IGroth16Verifier32Leaves verifier32,
        IGroth16Verifier64Leaves verifier64,
        IGroth16Verifier128Leaves verifier128,
        uint256[4] calldata pA,
        uint256[8] calldata pB,
        uint256[4] calldata pC,
        uint256[] memory publicSignals
    ) internal view returns (bool) {
        if (treeSize == 16) {
            require(publicSignals.length == 33, "Invalid public signals length for 16 leaves");
            uint256[33] memory signals16;
            for (uint256 i = 0; i < 33; i++) {
                signals16[i] = publicSignals[i];
            }
            return verifier16.verifyProof(pA, pB, pC, signals16);
        } else if (treeSize == 32) {
            require(publicSignals.length == 65, "Invalid public signals length for 32 leaves");
            uint256[65] memory signals32;
            for (uint256 i = 0; i < 65; i++) {
                signals32[i] = publicSignals[i];
            }
            return verifier32.verifyProof(pA, pB, pC, signals32);
        } else if (treeSize == 64) {
            require(publicSignals.length == 129, "Invalid public signals length for 64 leaves");
            uint256[129] memory signals64;
            for (uint256 i = 0; i < 129; i++) {
                signals64[i] = publicSignals[i];
            }
            return verifier64.verifyProof(pA, pB, pC, signals64);
        } else if (treeSize == 128) {
            require(publicSignals.length == 257, "Invalid public signals length for 128 leaves");
            uint256[257] memory signals128;
            for (uint256 i = 0; i < 257; i++) {
                signals128[i] = publicSignals[i];
            }
            return verifier128.verifyProof(pA, pB, pC, signals128);
        } else {
            revert("Invalid tree size");
        }
    }
}

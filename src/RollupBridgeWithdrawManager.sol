// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import "lib/openzeppelin-contracts-upgradeable/contracts/security/ReentrancyGuardUpgradeable.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/IERC20Upgradeable.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "./interface/IRollupBridgeCore.sol";

contract RollupBridgeWithdrawManager is ReentrancyGuardUpgradeable, OwnableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    uint256 public constant PROOF_SUBMISSION_DEADLINE = 7 days;
    uint256 public constant NATIVE_TOKEN_TRANSFER_GAS_LIMIT = 1_000_000;
    address public constant ETH_TOKEN_ADDRESS = address(1);

    IRollupBridgeCore public rollupBridge;

    event ChannelClosed(uint256 indexed channelId);
    event ChannelFinalized(uint256 indexed channelId);
    event EmergencyWithdrawalsEnabled(uint256 indexed channelId);
    event Withdrawn(uint256 indexed channelId, address indexed user, address token, uint256 amount);
    event LeaderBondSlashed(uint256 indexed channelId, address indexed leader, uint256 bondAmount, string reason);
    event LeaderBondReclaimed(uint256 indexed channelId, address indexed leader, uint256 bondAmount);
    event TreasuryAddressUpdated(address indexed oldTreasury, address indexed newTreasury);
    event SlashedBondsWithdrawn(address indexed treasury, uint256 amount);

    modifier onlyBridge() {
        require(msg.sender == address(rollupBridge), "Only bridge can call");
        _;
    }

    function initialize(address _rollupBridge, address _owner) public initializer {
        __ReentrancyGuard_init();
        __Ownable_init_unchained();
        _transferOwnership(_owner);

        require(_rollupBridge != address(0), "Invalid bridge address");
        rollupBridge = IRollupBridgeCore(_rollupBridge);
    }

    function closeAndFinalizeChannel(uint256 channelId) external {
        require(msg.sender == rollupBridge.getChannelLeader(channelId) || msg.sender == owner(), "unauthorized caller");
        require(
            rollupBridge.getChannelState(channelId) == IRollupBridgeCore.ChannelState.Closing, "Not in closing state"
        );
        require(rollupBridge.isSignatureVerified(channelId), "signature not verified");

        rollupBridge.setChannelState(channelId, IRollupBridgeCore.ChannelState.Closed);
        rollupBridge.setChannelCloseTimestamp(channelId, block.timestamp);

        emit ChannelClosed(channelId);
        emit ChannelFinalized(channelId);
    }

    function emergencyCloseExpiredChannel(uint256 channelId) external {
        require(msg.sender == owner(), "unauthorized caller");
        require(
            rollupBridge.getChannelState(channelId) == IRollupBridgeCore.ChannelState.Open
                || rollupBridge.getChannelState(channelId) == IRollupBridgeCore.ChannelState.Active,
            "Channel must be in Open or Active state"
        );

        (uint256 openTimestamp, uint256 timeout) = rollupBridge.getChannelTimeout(channelId);
        require(
            block.timestamp >= openTimestamp + timeout + PROOF_SUBMISSION_DEADLINE,
            "Proof submission deadline not reached"
        );

        (uint256 leaderBond, bool leaderBondSlashed) = rollupBridge.getLeaderBond(channelId);
        if (!leaderBondSlashed && leaderBond > 0) {
            rollupBridge.slashLeaderBond(channelId, "Failed to submit proof before timeout");
        }

        rollupBridge.enableEmergencyWithdrawals(channelId);
        rollupBridge.setChannelState(channelId, IRollupBridgeCore.ChannelState.Closed);
        rollupBridge.setChannelCloseTimestamp(channelId, block.timestamp);

        emit ChannelClosed(channelId);
    }

    function handleProofTimeout(uint256 channelId) external {
        require(rollupBridge.isChannelParticipant(channelId, msg.sender), "Not a participant");
        require(
            rollupBridge.getChannelState(channelId) == IRollupBridgeCore.ChannelState.Open
                || rollupBridge.getChannelState(channelId) == IRollupBridgeCore.ChannelState.Active,
            "Invalid state"
        );

        (uint256 openTimestamp, uint256 timeout) = rollupBridge.getChannelTimeout(channelId);
        require(
            block.timestamp >= openTimestamp + timeout + PROOF_SUBMISSION_DEADLINE,
            "Proof submission deadline not reached"
        );

        rollupBridge.slashLeaderBond(channelId, "Failed to submit proof on time");
        rollupBridge.enableEmergencyWithdrawals(channelId);
    }

    function withdraw(uint256 channelId) external nonReentrant {
        require(rollupBridge.getChannelState(channelId) == IRollupBridgeCore.ChannelState.Closed, "Not closed");
        require(!rollupBridge.hasUserWithdrawn(channelId, msg.sender), "Already withdrawn");
        require(rollupBridge.isChannelParticipant(channelId, msg.sender), "Not a participant");

        address[] memory allowedTokens = rollupBridge.getChannelAllowedTokens(channelId);
        bool hasWithdrawableAmount = false;

        // Mark user as withdrawn first to prevent reentrancy
        rollupBridge.markUserWithdrawn(channelId, msg.sender);

        // Withdraw all tokens for the user
        for (uint256 i = 0; i < allowedTokens.length; i++) {
            address token = allowedTokens[i];
            uint256 withdrawAmount = rollupBridge.getWithdrawableAmount(channelId, msg.sender, token);
            
            if (withdrawAmount > 0) {
                hasWithdrawableAmount = true;
                rollupBridge.clearWithdrawableAmount(channelId, msg.sender, token);

                if (token == ETH_TOKEN_ADDRESS) {
                    (bool success,) = msg.sender.call{value: withdrawAmount}("");
                    require(success, "ETH transfer failed");
                } else {
                    IERC20Upgradeable(token).safeTransfer(msg.sender, withdrawAmount);
                }

                emit Withdrawn(channelId, msg.sender, token, withdrawAmount);
            }
        }

        require(hasWithdrawableAmount, "No withdrawable amount");
    }

    function reclaimLeaderBond(uint256 channelId) external nonReentrant {
        require(msg.sender == rollupBridge.getChannelLeader(channelId), "Not the leader");
        require(rollupBridge.getChannelState(channelId) == IRollupBridgeCore.ChannelState.Closed, "Channel not closed");

        (uint256 leaderBond, bool leaderBondSlashed) = rollupBridge.getLeaderBond(channelId);
        require(!leaderBondSlashed, "Bond was slashed");
        require(leaderBond > 0, "No bond to reclaim");

        uint256 bondAmount = rollupBridge.reclaimLeaderBondInternal(channelId);

        (bool success,) = msg.sender.call{value: bondAmount}("");
        require(success, "Bond transfer failed");

        emit LeaderBondReclaimed(channelId, msg.sender, bondAmount);
    }

    function setTreasuryAddress(address _treasury) external onlyOwner {
        require(_treasury != address(0), "Treasury cannot be zero address");

        address oldTreasury = rollupBridge.getTreasuryAddress();
        // This would need to be implemented in the core bridge contract
        // rollupBridge.setTreasuryAddress(_treasury);

        emit TreasuryAddressUpdated(oldTreasury, _treasury);
    }

    function withdrawSlashedBonds() external onlyOwner nonReentrant {
        address treasury = rollupBridge.getTreasuryAddress();
        require(treasury != address(0), "Treasury address not set");

        uint256 totalSlashedBonds = rollupBridge.getTotalSlashedBonds();
        require(totalSlashedBonds > 0, "No slashed bonds to withdraw");

        // This would need to be coordinated with the core bridge contract
        // to actually transfer the funds and reset the slashed bonds counter

        (bool success,) = treasury.call{value: totalSlashedBonds}("");
        require(success, "Slashed bond transfer failed");

        emit SlashedBondsWithdrawn(treasury, totalSlashedBonds);
    }

    function updateRollupBridge(address _newBridge) external onlyOwner {
        require(_newBridge != address(0), "Invalid bridge address");
        rollupBridge = IRollupBridgeCore(_newBridge);
    }

    receive() external payable {}

    uint256[46] private __gap;
}

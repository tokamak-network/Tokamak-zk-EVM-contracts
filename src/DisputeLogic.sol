// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import "lib/openzeppelin-contracts-upgradeable/contracts/security/ReentrancyGuardUpgradeable.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "./interface/IRollupBridge.sol";

/**
 * @title DisputeLogic
 * @author Tokamak Ooo project
 * @notice Dispute resolution and slashing logic for RollupBridge
 * @dev This contract implements:
 *      - Slashing mechanisms for malicious behavior
 *      - L2 address collision prevention
 *      - Dispute resolution for proof failures
 *      - Emergency withdrawal mechanisms
 */
abstract contract DisputeLogic is Initializable, ReentrancyGuardUpgradeable, OwnableUpgradeable {
    // ========== CONSTANTS ==========
    uint256 public constant DISPUTE_TIMEOUT = 14 days;

    // ========== ENUMS ==========
    enum DisputeStatus {
        Raised,
        Resolved,
        Rejected
    }

    // ========== STRUCTS ==========
    struct Dispute {
        uint256 channelId;
        address accuser;
        address accused;
        DisputeStatus status;
        uint256 timestamp;
        uint256 slashAmount;
        bytes evidence;
        string description;
        bool resolved;
    }

    // ========== STORAGE ==========

    /// @custom:storage-location erc7201:tokamak.storage.DisputeLogic
    struct DisputeLogicStorage {
        // Dispute tracking
        mapping(uint256 => Dispute) disputes;
        mapping(uint256 => uint256[]) channelDisputes; // channelId => dispute IDs
        uint256 nextDisputeId;
        // L2 address collision prevention
        mapping(uint256 => mapping(address => bool)) usedL2Addresses; // channelId => l2Address => used
        mapping(address => mapping(uint256 => address)) l2ToL1Mapping; // l2Address => channelId => l1Address
        // Emergency state tracking
        mapping(uint256 => bool) emergencyMode; // channelId => emergency mode enabled
        mapping(uint256 => mapping(address => uint256)) emergencyWithdrawable; // channelId => participant => amount
    }

    // keccak256(abi.encode(uint256(keccak256("tokamak.storage.DisputeLogic")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant DisputeLogicStorageLocation =
        0x2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2c3d4e5f6a7b8c9d0e1f2a00;

    function _getDisputeLogicStorage() internal pure returns (DisputeLogicStorage storage $) {
        assembly {
            $.slot := DisputeLogicStorageLocation
        }
    }

    // ========== EVENTS ==========
    event DisputeRaised(uint256 indexed disputeId, uint256 indexed channelId, address indexed accuser, address accused);

    event DisputeResolved(
        uint256 indexed disputeId, uint256 indexed channelId, address indexed accused, bool slashed, uint256 slashAmount
    );

    event EmergencyModeEnabled(uint256 indexed channelId, string reason);

    event L2AddressCollisionPrevented(uint256 indexed channelId, address l2Address, address attemptedUser);

    // ========== ABSTRACT FUNCTIONS ==========
    // These must be implemented by the inheriting contract
    function _getChannelParticipants(uint256 channelId) internal view virtual returns (address[] memory);
    function _getParticipantDeposit(uint256 channelId, address participant) internal view virtual returns (uint256);
    function _isParticipant(uint256 channelId, address participant) internal view virtual returns (bool);
    function _getChannelState(uint256 channelId) internal view virtual returns (IRollupBridge.ChannelState);
    function _getChannelCloseTimestamp(uint256 channelId) internal view virtual returns (uint256);
    function _getChallengePeriod() internal view virtual returns (uint256);
    function _getChannelLeader(uint256 channelId) internal view virtual returns (address);
    function _hasWithdrawn(uint256 channelId, address participant) internal view virtual returns (bool);

    // ========== L2 ADDRESS COLLISION PREVENTION ==========

    /**
     * @notice Validates and registers L2 addresses to prevent collisions
     * @param channelId The channel ID
     * @param l1Address The L1 address of the participant
     * @param l2Address The proposed L2 address
     * @return success True if validation passed and address was registered
     */
    function validateAndRegisterL2Address(uint256 channelId, address l1Address, address l2Address)
        internal
        returns (bool success)
    {
        DisputeLogicStorage storage $ = _getDisputeLogicStorage();

        require(l2Address != address(0), "Invalid L2 address");

        // Check if L2 address is already used in this channel
        if ($.usedL2Addresses[channelId][l2Address]) {
            emit L2AddressCollisionPrevented(channelId, l2Address, l1Address);
            return false;
        }

        // Register the L2 address
        $.usedL2Addresses[channelId][l2Address] = true;
        $.l2ToL1Mapping[l2Address][channelId] = l1Address;

        return true;
    }

    // ========== DISPUTE MANAGEMENT ==========

    /**
     * @notice Raises a dispute against the channel leader
     * @param channelId The channel where the dispute occurred
     * @param evidence Additional evidence (encoded)
     * @param description Human-readable description
     * @return disputeId The ID of the created dispute
     */
    function raiseDispute(uint256 channelId, bytes calldata evidence, string calldata description)
        public
        returns (uint256 disputeId)
    {
        // Get the channel leader - disputes are always against the leader
        address leader = _getChannelLeader(channelId);

        // Only participants can raise disputes (leader cannot dispute themselves)
        require(_isParticipant(channelId, msg.sender), "Not a participant");
        require(leader != msg.sender, "Leader cannot dispute themselves");

        // Ensure disputes can only be raised during the dispute period
        IRollupBridge.ChannelState state = _getChannelState(channelId);
        require(state == IRollupBridge.ChannelState.Dispute, "Channel must be in dispute period to raise disputes");

        uint256 closeTimestamp = _getChannelCloseTimestamp(channelId);
        uint256 challengePeriod = _getChallengePeriod();
        require(block.timestamp <= closeTimestamp + challengePeriod, "Challenge period has expired");

        return _raiseDispute(channelId, msg.sender, leader, evidence, description);
    }

    function _raiseDispute(
        uint256 channelId,
        address accuser,
        address accused,
        bytes memory evidence,
        string memory description
    ) internal returns (uint256 disputeId) {
        DisputeLogicStorage storage $ = _getDisputeLogicStorage();

        disputeId = $.nextDisputeId++;

        $.disputes[disputeId] = Dispute({
            channelId: channelId,
            accuser: accuser,
            accused: accused,
            status: DisputeStatus.Raised,
            timestamp: block.timestamp,
            slashAmount: 0,
            evidence: evidence,
            description: description,
            resolved: false
        });

        $.channelDisputes[channelId].push(disputeId);

        emit DisputeRaised(disputeId, channelId, accuser, accused);

        return disputeId;
    }

    /**
     * @notice Resolves a dispute (owner only for manual resolution)
     * @param disputeId The dispute to resolve
     * @param shouldSlash Whether the accused should be slashed
     */
    function resolveDispute(uint256 disputeId, bool shouldSlash) external onlyOwner {
        _resolveDispute(disputeId, shouldSlash);
    }

    function _resolveDispute(uint256 disputeId, bool shouldSlash) internal {
        DisputeLogicStorage storage $ = _getDisputeLogicStorage();
        Dispute storage dispute = $.disputes[disputeId];

        require(dispute.status == DisputeStatus.Raised, "Dispute already resolved");
        require(!dispute.resolved, "Dispute already processed");

        dispute.status = shouldSlash ? DisputeStatus.Resolved : DisputeStatus.Rejected;
        dispute.resolved = true;

        // If dispute is resolved against leader (shouldSlash = true), enable emergency mode
        if (shouldSlash && dispute.accused == _getChannelLeader(dispute.channelId)) {
            _enableEmergencyModeInternal(dispute.channelId, "Leader misconduct proven via dispute resolution");
        }

        emit DisputeResolved(disputeId, dispute.channelId, dispute.accused, shouldSlash, 0);
    }

    // ========== EMERGENCY MECHANISMS ==========

    /**
     * @notice Enables emergency mode for a channel
     * @param channelId The channel ID
     * @param reason The reason for emergency mode
     */
    function enableEmergencyMode(uint256 channelId, string calldata reason) external onlyOwner {
        DisputeLogicStorage storage $ = _getDisputeLogicStorage();

        $.emergencyMode[channelId] = true;

        // Set emergency withdrawable amounts based on current deposits
        address[] memory participants = _getChannelParticipants(channelId);
        for (uint256 i = 0; i < participants.length; i++) {
            address participant = participants[i];
            uint256 deposit = _getParticipantDeposit(channelId, participant);
            $.emergencyWithdrawable[channelId][participant] = deposit;
        }

        emit EmergencyModeEnabled(channelId, reason);
    }

    /**
     * @notice Internal function to enable emergency mode (used by dispute resolution)
     * @param channelId The channel ID
     * @param reason The reason for emergency mode
     */
    function _enableEmergencyModeInternal(uint256 channelId, string memory reason) internal {
        DisputeLogicStorage storage $ = _getDisputeLogicStorage();

        // Only enable if not already enabled
        if ($.emergencyMode[channelId]) {
            return;
        }

        $.emergencyMode[channelId] = true;

        // Set emergency withdrawable amounts based on current deposits
        address[] memory participants = _getChannelParticipants(channelId);
        for (uint256 i = 0; i < participants.length; i++) {
            address participant = participants[i];
            uint256 deposit = _getParticipantDeposit(channelId, participant);
            $.emergencyWithdrawable[channelId][participant] = deposit;
        }

        emit EmergencyModeEnabled(channelId, reason);
    }

    /**
     * @notice Allows emergency withdrawal when emergency mode is enabled
     * @param channelId The channel ID
     */
    function emergencyWithdraw(uint256 channelId) external nonReentrant {
        DisputeLogicStorage storage $ = _getDisputeLogicStorage();

        require($.emergencyMode[channelId], "Emergency mode not enabled");
        require(_isParticipant(channelId, msg.sender), "Not a participant");
        require(!_hasWithdrawn(channelId, msg.sender), "Already withdrawn via normal flow");

        uint256 withdrawable = $.emergencyWithdrawable[channelId][msg.sender];
        require(withdrawable > 0, "Nothing to withdraw");

        $.emergencyWithdrawable[channelId][msg.sender] = 0;

        // Transfer logic would be implemented in the inheriting contract
        // This function should be overridden to handle actual transfers
        _executeEmergencyTransfer(channelId, msg.sender, withdrawable);
    }

    /**
     * @notice Executes emergency transfer (to be implemented by inheriting contract)
     * @param channelId The channel ID
     * @param participant The participant receiving the transfer
     * @param amount The amount to transfer
     */
    function _executeEmergencyTransfer(uint256 channelId, address participant, uint256 amount) internal virtual;

    // ========== VIEW FUNCTIONS ==========

    function getDispute(uint256 disputeId) external view returns (Dispute memory) {
        DisputeLogicStorage storage $ = _getDisputeLogicStorage();
        return $.disputes[disputeId];
    }

    function getChannelDisputes(uint256 channelId) external view returns (uint256[] memory) {
        DisputeLogicStorage storage $ = _getDisputeLogicStorage();
        return $.channelDisputes[channelId];
    }

    function isL2AddressUsed(uint256 channelId, address l2Address) external view returns (bool) {
        DisputeLogicStorage storage $ = _getDisputeLogicStorage();
        return $.usedL2Addresses[channelId][l2Address];
    }

    function isEmergencyModeEnabled(uint256 channelId) external view returns (bool) {
        DisputeLogicStorage storage $ = _getDisputeLogicStorage();
        return $.emergencyMode[channelId];
    }

    function getEmergencyWithdrawable(uint256 channelId, address participant) external view returns (uint256) {
        DisputeLogicStorage storage $ = _getDisputeLogicStorage();
        return $.emergencyWithdrawable[channelId][participant];
    }

    function getDisputeTimeout() external pure returns (uint256) {
        return DISPUTE_TIMEOUT;
    }

    /**
     * @notice Checks if there are any unresolved or resolved disputes against the channel leader
     * @param channelId The channel ID to check
     * @return hasActiveDisputes True if there are pending or resolved disputes against the leader
     */
    function hasResolvedDisputesAgainstLeader(uint256 channelId) external view returns (bool hasActiveDisputes) {
        DisputeLogicStorage storage $ = _getDisputeLogicStorage();
        address leader = _getChannelLeader(channelId);

        uint256[] memory disputeIds = $.channelDisputes[channelId];
        for (uint256 i = 0; i < disputeIds.length; i++) {
            Dispute storage dispute = $.disputes[disputeIds[i]];
            if (dispute.accused == leader) {
                // Check if dispute has timed out (automatically rejected)
                bool isExpired = block.timestamp > dispute.timestamp + DISPUTE_TIMEOUT;

                // Block bond reclaim if dispute is pending (and not expired) or resolved against leader
                if (!isExpired && (dispute.status == DisputeStatus.Raised)) {
                    return true; // Pending dispute that hasn't expired
                } else if (dispute.status == DisputeStatus.Resolved && dispute.resolved) {
                    return true; // Dispute resolved against leader
                }
                // Expired disputes (isExpired && status == Raised) are treated as rejected
            }
        }
        return false;
    }

    uint256[44] private __gap;
}

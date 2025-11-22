// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import "lib/openzeppelin-contracts-upgradeable/contracts/utils/cryptography/ECDSAUpgradeable.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/security/ReentrancyGuardUpgradeable.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";

contract RollupBridgeCore is ReentrancyGuardUpgradeable, OwnableUpgradeable, UUPSUpgradeable {
    using ECDSAUpgradeable for bytes32;

    enum ChannelState {
        None,
        Initialized,
        Open,
        Active,
        Closing,
        Closed
    }

    struct ChannelParams {
        address[] allowedTokens;
        address[] participants;
        uint256 timeout;
        uint256 pkx;
        uint256 pky;
    }

    struct TargetContract {
        address contractAddress;
        bytes1 storageSlot;
    }

    struct RegisteredFunction {
        bytes32 functionSignature;
        uint128[] preprocessedPart1;
        uint256[] preprocessedPart2;
    }

    struct Channel {
        uint256 id;
        address[] allowedTokens;
        mapping(address => bool) isTokenAllowed;
        mapping(address => mapping(address => uint256)) tokenDeposits;
        mapping(address => uint256) tokenTotalDeposits;
        bytes32 initialStateRoot;
        address[] participants;
        mapping(address => mapping(address => uint256)) l2MptKeys;
        mapping(address => bool) isParticipant;
        ChannelState state;
        uint256 openTimestamp;
        uint256 closeTimestamp;
        uint256 timeout;
        address leader;
        uint256 leaderBond;
        bool leaderBondSlashed;
        mapping(address => bool) hasWithdrawn;
        mapping(address => mapping(address => uint256)) withdrawAmount;
        uint256 pkx;
        uint256 pky;
        address signerAddr;
        bool sigVerified;
        uint256 requiredTreeSize;
    }

    uint256 public constant MIN_PARTICIPANTS = 3;
    uint256 public constant MAX_PARTICIPANTS = 128;
    uint256 public constant LEADER_BOND_REQUIRED = 0.001 ether;
    address public constant ETH_TOKEN_ADDRESS = address(1);

    /// @custom:storage-location erc7201:tokamak.storage.RollupBridgeCore
    struct RollupBridgeCoreStorage {
        mapping(uint256 => Channel) channels;
        mapping(address => bool) isChannelLeader;
        mapping(address => TargetContract) allowedTargetContracts;
        mapping(address => bool) isTargetContractAllowed;
        mapping(bytes32 => RegisteredFunction) registeredFunctions;
        uint256 nextChannelId;
        address treasury;
        uint256 totalSlashedBonds;
        address depositManager;
        address proofManager;
        address withdrawManager;
        address adminManager;
    }

    bytes32 private constant RollupBridgeCoreStorageLocation =
        0x1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e4f5a6b7c8d9e0f1a00;

    event ChannelOpened(uint256 indexed channelId, address[] allowedTokens);

    modifier onlyManager() {
        RollupBridgeCoreStorage storage $ = _getRollupBridgeCoreStorage();
        require(
            msg.sender == $.depositManager || msg.sender == $.proofManager || msg.sender == $.withdrawManager
                || msg.sender == $.adminManager,
            "Only managers can call"
        );
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _depositManager,
        address _proofManager,
        address _withdrawManager,
        address _adminManager,
        address _owner
    ) public initializer {
        __ReentrancyGuard_init();
        __Ownable_init_unchained();
        _transferOwnership(_owner);
        __UUPSUpgradeable_init();

        RollupBridgeCoreStorage storage $ = _getRollupBridgeCoreStorage();
        $.depositManager = _depositManager;
        $.proofManager = _proofManager;
        $.withdrawManager = _withdrawManager;
        $.adminManager = _adminManager;
    }

    function openChannel(ChannelParams calldata params) external payable returns (uint256 channelId) {
        RollupBridgeCoreStorage storage $ = _getRollupBridgeCoreStorage();

        require(msg.value == LEADER_BOND_REQUIRED, "Leader bond required");
        require(!$.isChannelLeader[msg.sender], "Channel limit reached");
        require(params.allowedTokens.length > 0, "Must specify at least one token");
        require(params.allowedTokens.length <= 4, "Maximum 4 tokens allowed");
        require(params.timeout >= 1 hours && params.timeout <= 365 days, "Invalid timeout");

        uint256 requiredTreeSize = determineTreeSize(params.participants.length, params.allowedTokens.length);

        require(
            params.participants.length >= MIN_PARTICIPANTS && params.participants.length <= MAX_PARTICIPANTS,
            "Invalid participant count"
        );

        for (uint256 i = 0; i < params.allowedTokens.length;) {
            address token = params.allowedTokens[i];
            require(token == ETH_TOKEN_ADDRESS || $.isTargetContractAllowed[token], "Token not allowed");

            for (uint256 j = i + 1; j < params.allowedTokens.length;) {
                require(params.allowedTokens[j] != token, "Duplicate token");
                unchecked {
                    ++j;
                }
            }
            unchecked {
                ++i;
            }
        }

        unchecked {
            channelId = $.nextChannelId++;
        }

        $.isChannelLeader[msg.sender] = true;
        Channel storage channel = $.channels[channelId];

        channel.id = channelId;
        channel.leader = msg.sender;
        channel.leaderBond = msg.value;
        channel.leaderBondSlashed = false;
        channel.openTimestamp = block.timestamp;
        channel.timeout = params.timeout;
        channel.state = ChannelState.Initialized;
        channel.requiredTreeSize = requiredTreeSize;

        uint256 tokensLength = params.allowedTokens.length;
        for (uint256 i = 0; i < tokensLength;) {
            channel.allowedTokens.push(params.allowedTokens[i]);
            channel.isTokenAllowed[params.allowedTokens[i]] = true;
            unchecked {
                ++i;
            }
        }

        uint256 participantsLength = params.participants.length;
        for (uint256 i = 0; i < participantsLength;) {
            address participant = params.participants[i];
            require(!channel.isParticipant[participant], "Duplicate participant");

            channel.participants.push(participant);
            channel.isParticipant[participant] = true;
            unchecked {
                ++i;
            }
        }

        channel.pkx = params.pkx;
        channel.pky = params.pky;
        address signerAddr = deriveAddressFromPubkey(params.pkx, params.pky);
        channel.signerAddr = signerAddr;

        emit ChannelOpened(channelId, params.allowedTokens);
    }

    // Manager interface functions
    function getChannelState(uint256 channelId) external view returns (ChannelState) {
        RollupBridgeCoreStorage storage $ = _getRollupBridgeCoreStorage();
        return $.channels[channelId].state;
    }

    function isChannelParticipant(uint256 channelId, address participant) external view returns (bool) {
        RollupBridgeCoreStorage storage $ = _getRollupBridgeCoreStorage();
        return $.channels[channelId].isParticipant[participant];
    }

    function isTokenAllowedInChannel(uint256 channelId, address token) external view returns (bool) {
        RollupBridgeCoreStorage storage $ = _getRollupBridgeCoreStorage();
        return $.channels[channelId].isTokenAllowed[token];
    }

    function getChannelLeader(uint256 channelId) external view returns (address) {
        RollupBridgeCoreStorage storage $ = _getRollupBridgeCoreStorage();
        return $.channels[channelId].leader;
    }

    function getChannelParticipants(uint256 channelId) external view returns (address[] memory) {
        RollupBridgeCoreStorage storage $ = _getRollupBridgeCoreStorage();
        return $.channels[channelId].participants;
    }

    function getChannelAllowedTokens(uint256 channelId) external view returns (address[] memory) {
        RollupBridgeCoreStorage storage $ = _getRollupBridgeCoreStorage();
        return $.channels[channelId].allowedTokens;
    }

    function getChannelTreeSize(uint256 channelId) external view returns (uint256) {
        RollupBridgeCoreStorage storage $ = _getRollupBridgeCoreStorage();
        return $.channels[channelId].requiredTreeSize;
    }

    function getParticipantTokenDeposit(uint256 channelId, address participant, address token)
        external
        view
        returns (uint256)
    {
        RollupBridgeCoreStorage storage $ = _getRollupBridgeCoreStorage();
        return $.channels[channelId].tokenDeposits[token][participant];
    }

    function getL2MptKey(uint256 channelId, address participant, address token) external view returns (uint256) {
        RollupBridgeCoreStorage storage $ = _getRollupBridgeCoreStorage();
        return $.channels[channelId].l2MptKeys[participant][token];
    }

    function getChannelTotalDeposits(uint256 channelId, address token) external view returns (uint256) {
        RollupBridgeCoreStorage storage $ = _getRollupBridgeCoreStorage();
        return $.channels[channelId].tokenTotalDeposits[token];
    }

    function getChannelPublicKey(uint256 channelId) external view returns (uint256 pkx, uint256 pky) {
        RollupBridgeCoreStorage storage $ = _getRollupBridgeCoreStorage();
        Channel storage channel = $.channels[channelId];
        return (channel.pkx, channel.pky);
    }

    function getChannelSignerAddr(uint256 channelId) external view returns (address) {
        RollupBridgeCoreStorage storage $ = _getRollupBridgeCoreStorage();
        return $.channels[channelId].signerAddr;
    }

    function getRegisteredFunction(bytes32 functionSignature) external view returns (RegisteredFunction memory) {
        RollupBridgeCoreStorage storage $ = _getRollupBridgeCoreStorage();
        return $.registeredFunctions[functionSignature];
    }

    function isAllowedTargetContract(address targetContract) external view returns (bool) {
        RollupBridgeCoreStorage storage $ = _getRollupBridgeCoreStorage();
        return $.isTargetContractAllowed[targetContract];
    }

    function getTargetContractData(address targetContract) external view returns (TargetContract memory) {
        RollupBridgeCoreStorage storage $ = _getRollupBridgeCoreStorage();
        require($.isTargetContractAllowed[targetContract], "Target contract not allowed");
        return $.allowedTargetContracts[targetContract];
    }

    // Manager setter functions
    function updateChannelTokenDeposits(uint256 channelId, address token, address participant, uint256 amount)
        external
        onlyManager
    {
        RollupBridgeCoreStorage storage $ = _getRollupBridgeCoreStorage();
        $.channels[channelId].tokenDeposits[token][participant] += amount;
    }

    function updateChannelTotalDeposits(uint256 channelId, address token, uint256 amount) external onlyManager {
        RollupBridgeCoreStorage storage $ = _getRollupBridgeCoreStorage();
        $.channels[channelId].tokenTotalDeposits[token] += amount;
    }

    function setChannelL2MptKey(uint256 channelId, address participant, address token, uint256 mptKey)
        external
        onlyManager
    {
        RollupBridgeCoreStorage storage $ = _getRollupBridgeCoreStorage();
        $.channels[channelId].l2MptKeys[participant][token] = mptKey;
    }

    function setChannelInitialStateRoot(uint256 channelId, bytes32 stateRoot) external onlyManager {
        RollupBridgeCoreStorage storage $ = _getRollupBridgeCoreStorage();
        $.channels[channelId].initialStateRoot = stateRoot;
    }

    function setChannelState(uint256 channelId, ChannelState state) external onlyManager {
        RollupBridgeCoreStorage storage $ = _getRollupBridgeCoreStorage();
        $.channels[channelId].state = state;
        if (state == ChannelState.Closed) {
            $.isChannelLeader[$.channels[channelId].leader] = false;
        }
    }

    function setChannelWithdrawAmounts(
        uint256 channelId,
        address[] memory participants,
        address[] memory tokens,
        uint256[][] memory amounts
    ) external onlyManager {
        RollupBridgeCoreStorage storage $ = _getRollupBridgeCoreStorage();
        Channel storage channel = $.channels[channelId];

        for (uint256 participantIdx = 0; participantIdx < participants.length; participantIdx++) {
            address participant = participants[participantIdx];
            for (uint256 tokenIdx = 0; tokenIdx < tokens.length; tokenIdx++) {
                address token = tokens[tokenIdx];
                uint256 finalBalance = amounts[participantIdx][tokenIdx];
                channel.withdrawAmount[token][participant] = finalBalance;
            }
        }
    }

    function setChannelSignatureVerified(uint256 channelId, bool verified) external onlyManager {
        RollupBridgeCoreStorage storage $ = _getRollupBridgeCoreStorage();
        $.channels[channelId].sigVerified = verified;
    }

    function setAllowedTargetContract(address targetContract, bytes1 storageSlot, bool allowed) external onlyManager {
        RollupBridgeCoreStorage storage $ = _getRollupBridgeCoreStorage();

        if (allowed) {
            $.allowedTargetContracts[targetContract] =
                TargetContract({contractAddress: targetContract, storageSlot: storageSlot});
        } else {
            delete $.allowedTargetContracts[targetContract];
        }

        $.isTargetContractAllowed[targetContract] = allowed;
    }

    function registerFunction(
        bytes32 functionSignature,
        uint128[] memory preprocessedPart1,
        uint256[] memory preprocessedPart2
    ) external onlyManager {
        RollupBridgeCoreStorage storage $ = _getRollupBridgeCoreStorage();

        $.registeredFunctions[functionSignature] = RegisteredFunction({
            functionSignature: functionSignature,
            preprocessedPart1: preprocessedPart1,
            preprocessedPart2: preprocessedPart2
        });
    }

    function unregisterFunction(bytes32 functionSignature) external onlyManager {
        RollupBridgeCoreStorage storage $ = _getRollupBridgeCoreStorage();
        delete $.registeredFunctions[functionSignature];
    }

    function setTreasuryAddress(address treasury) external onlyManager {
        RollupBridgeCoreStorage storage $ = _getRollupBridgeCoreStorage();
        $.treasury = treasury;
    }

    // Additional view functions
    function nextChannelId() external view returns (uint256) {
        RollupBridgeCoreStorage storage $ = _getRollupBridgeCoreStorage();
        return $.nextChannelId;
    }

    function getTreasuryAddress() external view returns (address) {
        RollupBridgeCoreStorage storage $ = _getRollupBridgeCoreStorage();
        return $.treasury;
    }

    function getTotalSlashedBonds() external view returns (uint256) {
        RollupBridgeCoreStorage storage $ = _getRollupBridgeCoreStorage();
        return $.totalSlashedBonds;
    }

    function getChannelInfo(uint256 channelId)
        external
        view
        returns (address[] memory allowedTokens, ChannelState state, uint256 participantCount, bytes32 initialRoot)
    {
        RollupBridgeCoreStorage storage $ = _getRollupBridgeCoreStorage();
        Channel storage channel = $.channels[channelId];
        return (channel.allowedTokens, channel.state, channel.participants.length, channel.initialStateRoot);
    }

    function isSignatureVerified(uint256 channelId) external view returns (bool) {
        RollupBridgeCoreStorage storage $ = _getRollupBridgeCoreStorage();
        return $.channels[channelId].sigVerified;
    }

    function getWithdrawableAmount(uint256 channelId, address participant, address token)
        external
        view
        returns (uint256)
    {
        RollupBridgeCoreStorage storage $ = _getRollupBridgeCoreStorage();
        return $.channels[channelId].withdrawAmount[token][participant];
    }

    function hasUserWithdrawn(uint256 channelId, address participant) external view returns (bool) {
        RollupBridgeCoreStorage storage $ = _getRollupBridgeCoreStorage();
        return $.channels[channelId].hasWithdrawn[participant];
    }

    function markUserWithdrawn(uint256 channelId, address participant) external onlyManager {
        RollupBridgeCoreStorage storage $ = _getRollupBridgeCoreStorage();
        $.channels[channelId].hasWithdrawn[participant] = true;
    }

    function clearWithdrawableAmount(uint256 channelId, address participant, address token) external onlyManager {
        RollupBridgeCoreStorage storage $ = _getRollupBridgeCoreStorage();
        $.channels[channelId].withdrawAmount[token][participant] = 0;
    }

    function setChannelCloseTimestamp(uint256 channelId, uint256 timestamp) external onlyManager {
        RollupBridgeCoreStorage storage $ = _getRollupBridgeCoreStorage();
        $.channels[channelId].closeTimestamp = timestamp;
    }

    function _getRollupBridgeCoreStorage() internal pure returns (RollupBridgeCoreStorage storage $) {
        assembly {
            $.slot := RollupBridgeCoreStorageLocation
        }
    }

    function updateManagerAddresses(
        address _depositManager,
        address _proofManager,
        address _withdrawManager,
        address _adminManager
    ) external onlyOwner {
        RollupBridgeCoreStorage storage $ = _getRollupBridgeCoreStorage();
        if (_depositManager != address(0)) $.depositManager = _depositManager;
        if (_proofManager != address(0)) $.proofManager = _proofManager;
        if (_withdrawManager != address(0)) $.withdrawManager = _withdrawManager;
        if (_adminManager != address(0)) $.adminManager = _adminManager;
    }

    // === DASHBOARD FUNCTIONS ===

    /**
     * @notice Get the total number of channels created
     * @return Total number of channels
     */
    function getTotalChannels() external view returns (uint256) {
        RollupBridgeCoreStorage storage $ = _getRollupBridgeCoreStorage();
        return $.nextChannelId;
    }

    /**
     * @notice Get comprehensive channel statistics
     * @return openChannels Number of open channels
     * @return activeChannels Number of active channels  
     * @return closingChannels Number of closing channels
     * @return closedChannels Number of closed channels
     */
    function getChannelStats() external view returns (
        uint256 openChannels,
        uint256 activeChannels, 
        uint256 closingChannels,
        uint256 closedChannels
    ) {
        RollupBridgeCoreStorage storage $ = _getRollupBridgeCoreStorage();
        
        for (uint256 i = 0; i < $.nextChannelId; i++) {
            Channel storage channel = $.channels[i];
            if (channel.id > 0) { // Channel exists
                ChannelState state = channel.state;
                if (state == ChannelState.Open) openChannels++;
                else if (state == ChannelState.Active) activeChannels++;
                else if (state == ChannelState.Closing) closingChannels++;
                else if (state == ChannelState.Closed) closedChannels++;
            }
        }
    }

    /**
     * @notice Get a user's total balance across all channels and tokens
     * @param user The user address
     * @return tokens Array of token addresses the user has deposited
     * @return balances Array of corresponding balances
     */
    function getUserTotalBalance(address user) external view returns (
        address[] memory tokens,
        uint256[] memory balances
    ) {
        RollupBridgeCoreStorage storage $ = _getRollupBridgeCoreStorage();
        
        // First pass: collect unique tokens
        address[] memory allTokens = new address[](1000); // Max estimate
        uint256 tokenCount = 0;
        
        for (uint256 i = 0; i < $.nextChannelId; i++) {
            Channel storage channel = $.channels[i];
            if (channel.id > 0 && channel.isParticipant[user]) {
                for (uint256 j = 0; j < channel.allowedTokens.length; j++) {
                    address token = channel.allowedTokens[j];
                    bool isNewToken = true;
                    for (uint256 k = 0; k < tokenCount; k++) {
                        if (allTokens[k] == token) {
                            isNewToken = false;
                            break;
                        }
                    }
                    if (isNewToken) {
                        allTokens[tokenCount] = token;
                        tokenCount++;
                    }
                }
            }
        }
        
        // Second pass: calculate balances
        tokens = new address[](tokenCount);
        balances = new uint256[](tokenCount);
        
        for (uint256 i = 0; i < tokenCount; i++) {
            tokens[i] = allTokens[i];
            for (uint256 j = 0; j < $.nextChannelId; j++) {
                Channel storage channel = $.channels[j];
                if (channel.id > 0 && channel.isParticipant[user]) {
                    balances[i] += channel.tokenDeposits[user][tokens[i]];
                }
            }
        }
    }

    /**
     * @notice Get channel states for multiple channels at once
     * @param channelIds Array of channel IDs to query
     * @return states Array of corresponding channel states
     */
    function batchGetChannelStates(uint256[] calldata channelIds) 
        external 
        view 
        returns (ChannelState[] memory states) 
    {
        states = new ChannelState[](channelIds.length);
        RollupBridgeCoreStorage storage $ = _getRollupBridgeCoreStorage();
        
        for (uint256 i = 0; i < channelIds.length; i++) {
            states[i] = $.channels[channelIds[i]].state;
        }
    }

    // === MEDIUM PRIORITY UX FUNCTIONS ===

    /**
     * @notice Get user analytics including total deposits, channels participated, and activity
     * @param user The user address
     * @return totalChannelsJoined Number of channels the user has joined
     * @return activeChannelsCount Number of active channels the user is in
     * @return totalTokenTypes Number of different token types the user has deposited
     * @return channelsAsLeader Number of channels where user is the leader
     */
    function getUserAnalytics(address user) external view returns (
        uint256 totalChannelsJoined,
        uint256 activeChannelsCount,
        uint256 totalTokenTypes,
        uint256 channelsAsLeader
    ) {
        RollupBridgeCoreStorage storage $ = _getRollupBridgeCoreStorage();
        
        // Track unique tokens
        address[] memory userTokens = new address[](1000);
        uint256 tokenCount = 0;
        
        for (uint256 i = 0; i < $.nextChannelId; i++) {
            Channel storage channel = $.channels[i];
            if (channel.id > 0 && channel.isParticipant[user]) {
                totalChannelsJoined++;
                
                if (channel.state == ChannelState.Active) {
                    activeChannelsCount++;
                }
                
                if (channel.leader == user) {
                    channelsAsLeader++;
                }
                
                // Count unique tokens
                for (uint256 j = 0; j < channel.allowedTokens.length; j++) {
                    address token = channel.allowedTokens[j];
                    if (channel.tokenDeposits[user][token] > 0) {
                        bool isNewToken = true;
                        for (uint256 k = 0; k < tokenCount; k++) {
                            if (userTokens[k] == token) {
                                isNewToken = false;
                                break;
                            }
                        }
                        if (isNewToken) {
                            userTokens[tokenCount] = token;
                            tokenCount++;
                        }
                    }
                }
            }
        }
        
        totalTokenTypes = tokenCount;
    }

    /**
     * @notice Get channel participation history for a user
     * @param user The user address
     * @return channelIds Array of channel IDs the user has participated in
     * @return states Array of corresponding channel states
     * @return joinTimestamps Array of when the user joined each channel
     * @return isLeaderFlags Array indicating if user was leader in each channel
     */
    function getChannelHistory(address user) external view returns (
        uint256[] memory channelIds,
        ChannelState[] memory states,
        uint256[] memory joinTimestamps,
        bool[] memory isLeaderFlags
    ) {
        RollupBridgeCoreStorage storage $ = _getRollupBridgeCoreStorage();
        
        // First pass: count user's channels
        uint256 userChannelCount = 0;
        for (uint256 i = 0; i < $.nextChannelId; i++) {
            if ($.channels[i].id > 0 && $.channels[i].isParticipant[user]) {
                userChannelCount++;
            }
        }
        
        // Second pass: collect data
        channelIds = new uint256[](userChannelCount);
        states = new ChannelState[](userChannelCount);
        joinTimestamps = new uint256[](userChannelCount);
        isLeaderFlags = new bool[](userChannelCount);
        
        uint256 index = 0;
        for (uint256 i = 0; i < $.nextChannelId; i++) {
            Channel storage channel = $.channels[i];
            if (channel.id > 0 && channel.isParticipant[user]) {
                channelIds[index] = channel.id;
                states[index] = channel.state;
                joinTimestamps[index] = channel.openTimestamp;
                isLeaderFlags[index] = (channel.leader == user);
                index++;
            }
        }
    }

    /**
     * @notice Check if a user can make a deposit
     * @param user The user address
     * @param channelId The channel ID
     * @param token The token address
     * @param amount The amount to deposit
     * @return canDeposit Whether the user can deposit
     * @return reason Reason if cannot deposit
     */
    function canUserDeposit(address user, uint256 channelId, address token, uint256 amount) 
        external 
        view 
        returns (bool canDeposit, string memory reason) 
    {
        RollupBridgeCoreStorage storage $ = _getRollupBridgeCoreStorage();
        Channel storage channel = $.channels[channelId];
        
        if (channel.id == 0) {
            return (false, "Channel does not exist");
        }
        
        if (!channel.isParticipant[user]) {
            return (false, "User is not a participant in this channel");
        }
        
        if (!channel.isTokenAllowed[token]) {
            return (false, "Token is not allowed in this channel");
        }
        
        if (channel.state != ChannelState.Open && channel.state != ChannelState.Active) {
            return (false, "Channel is not open for deposits");
        }
        
        if (amount == 0) {
            return (false, "Deposit amount must be greater than 0");
        }
        
        return (true, "");
    }

    /**
     * @notice Check if a user can withdraw from a channel
     * @param user The user address
     * @param channelId The channel ID
     * @return canWithdraw Whether the user can withdraw
     * @return reason Reason if cannot withdraw
     */
    function canUserWithdraw(address user, uint256 channelId) 
        external 
        view 
        returns (bool canWithdraw, string memory reason) 
    {
        RollupBridgeCoreStorage storage $ = _getRollupBridgeCoreStorage();
        Channel storage channel = $.channels[channelId];
        
        if (channel.id == 0) {
            return (false, "Channel does not exist");
        }
        
        if (!channel.isParticipant[user]) {
            return (false, "User is not a participant in this channel");
        }
        
        if (channel.state != ChannelState.Closed) {
            return (false, "Channel is not closed");
        }
        
        if (channel.hasWithdrawn[user]) {
            return (false, "User has already withdrawn from this channel");
        }
        
        return (true, "");
    }

    // === LOW PRIORITY ADVANCED FUNCTIONS ===

    /**
     * @notice Get comprehensive system analytics
     * @return totalChannelsCreated Total channels ever created
     * @return totalValueLocked Total value locked across all channels and tokens
     * @return totalUniqueUsers Number of unique users who have participated
     * @return averageChannelSize Average number of participants per channel
     * @return totalSlashedAmount Total amount that has been slashed
     */
    function getSystemAnalytics() external view returns (
        uint256 totalChannelsCreated,
        uint256 totalValueLocked,
        uint256 totalUniqueUsers,
        uint256 averageChannelSize,
        uint256 totalSlashedAmount
    ) {
        RollupBridgeCoreStorage storage $ = _getRollupBridgeCoreStorage();
        
        totalChannelsCreated = $.nextChannelId;
        totalSlashedAmount = $.totalSlashedBonds;
        
        // Track unique users and calculate TVL
        address[] memory allUsers = new address[](10000); // Max estimate
        uint256 userCount = 0;
        uint256 totalParticipants = 0;
        uint256 channelCount = 0;
        
        for (uint256 i = 0; i < $.nextChannelId; i++) {
            Channel storage channel = $.channels[i];
            if (channel.id > 0) {
                channelCount++;
                totalParticipants += channel.participants.length;
                
                // Count unique users
                for (uint256 j = 0; j < channel.participants.length; j++) {
                    address user = channel.participants[j];
                    bool isNewUser = true;
                    for (uint256 k = 0; k < userCount; k++) {
                        if (allUsers[k] == user) {
                            isNewUser = false;
                            break;
                        }
                    }
                    if (isNewUser) {
                        allUsers[userCount] = user;
                        userCount++;
                    }
                }
                
                // Calculate TVL for this channel
                for (uint256 j = 0; j < channel.allowedTokens.length; j++) {
                    address token = channel.allowedTokens[j];
                    totalValueLocked += channel.tokenTotalDeposits[token];
                }
            }
        }
        
        totalUniqueUsers = userCount;
        averageChannelSize = channelCount > 0 ? totalParticipants / channelCount : 0;
    }

    /**
     * @notice Get live metrics for a specific channel
     * @param channelId The channel ID
     * @return activeParticipants Number of participants who have made deposits
     * @return totalDeposits Total number of deposits made to this channel
     * @return averageDepositSize Average deposit size across all tokens (in wei equivalent)
     * @return timeActive How long the channel has been active (in seconds)
     * @return lastActivityTime Timestamp of last deposit activity
     */
    function getChannelLiveMetrics(uint256 channelId) external view returns (
        uint256 activeParticipants,
        uint256 totalDeposits,
        uint256 averageDepositSize,
        uint256 timeActive,
        uint256 lastActivityTime
    ) {
        RollupBridgeCoreStorage storage $ = _getRollupBridgeCoreStorage();
        Channel storage channel = $.channels[channelId];
        
        if (channel.id == 0) {
            return (0, 0, 0, 0, 0);
        }
        
        uint256 totalDepositValue = 0;
        uint256 depositCount = 0;
        
        // Count active participants and calculate metrics
        for (uint256 i = 0; i < channel.participants.length; i++) {
            address participant = channel.participants[i];
            bool hasDeposits = false;
            
            for (uint256 j = 0; j < channel.allowedTokens.length; j++) {
                address token = channel.allowedTokens[j];
                uint256 deposit = channel.tokenDeposits[participant][token];
                if (deposit > 0) {
                    hasDeposits = true;
                    totalDepositValue += deposit;
                    depositCount++;
                }
            }
            
            if (hasDeposits) {
                activeParticipants++;
            }
        }
        
        totalDeposits = depositCount;
        averageDepositSize = depositCount > 0 ? totalDepositValue / depositCount : 0;
        timeActive = channel.state == ChannelState.Closed ? 
            channel.closeTimestamp - channel.openTimestamp :
            block.timestamp - channel.openTimestamp;
        lastActivityTime = channel.openTimestamp; // Use openTimestamp as activity time
    }

    /**
     * @notice Search channels by participant address
     * @param participant The participant address to search for
     * @param state Optional state filter (use ChannelState.None for no filter)
     * @param limit Maximum number of results to return
     * @param offset Offset for pagination
     * @return channelIds Array of matching channel IDs
     * @return totalMatches Total number of matches (for pagination)
     */
    function searchChannelsByParticipant(
        address participant,
        ChannelState state,
        uint256 limit,
        uint256 offset
    ) external view returns (
        uint256[] memory channelIds,
        uint256 totalMatches
    ) {
        RollupBridgeCoreStorage storage $ = _getRollupBridgeCoreStorage();
        
        // First pass: count matches
        for (uint256 i = 0; i < $.nextChannelId; i++) {
            Channel storage channel = $.channels[i];
            if (channel.id > 0 && channel.isParticipant[participant]) {
                if (state == ChannelState.None || channel.state == state) {
                    totalMatches++;
                }
            }
        }
        
        // Second pass: collect results with pagination
        uint256 resultSize = totalMatches > limit ? limit : totalMatches;
        channelIds = new uint256[](resultSize);
        
        uint256 currentMatch = 0;
        uint256 resultIndex = 0;
        
        for (uint256 i = 0; i < $.nextChannelId && resultIndex < resultSize; i++) {
            Channel storage channel = $.channels[i];
            if (channel.id > 0 && channel.isParticipant[participant]) {
                if (state == ChannelState.None || channel.state == state) {
                    if (currentMatch >= offset) {
                        channelIds[resultIndex] = channel.id;
                        resultIndex++;
                    }
                    currentMatch++;
                }
            }
        }
    }

    /**
     * @notice Search channels by token address
     * @param token The token address to search for
     * @param minTotalDeposits Minimum total deposits required
     * @param limit Maximum number of results to return
     * @param offset Offset for pagination
     * @return channelIds Array of matching channel IDs
     * @return totalDeposits Array of total deposits for each channel
     * @return totalMatches Total number of matches (for pagination)
     */
    function searchChannelsByToken(
        address token,
        uint256 minTotalDeposits,
        uint256 limit,
        uint256 offset
    ) external view returns (
        uint256[] memory channelIds,
        uint256[] memory totalDeposits,
        uint256 totalMatches
    ) {
        RollupBridgeCoreStorage storage $ = _getRollupBridgeCoreStorage();
        
        // First pass: count matches
        for (uint256 i = 0; i < $.nextChannelId; i++) {
            Channel storage channel = $.channels[i];
            if (channel.id > 0 && channel.isTokenAllowed[token]) {
                if (channel.tokenTotalDeposits[token] >= minTotalDeposits) {
                    totalMatches++;
                }
            }
        }
        
        // Second pass: collect results with pagination
        uint256 resultSize = totalMatches > limit ? limit : totalMatches;
        channelIds = new uint256[](resultSize);
        totalDeposits = new uint256[](resultSize);
        
        uint256 currentMatch = 0;
        uint256 resultIndex = 0;
        
        for (uint256 i = 0; i < $.nextChannelId && resultIndex < resultSize; i++) {
            Channel storage channel = $.channels[i];
            if (channel.id > 0 && channel.isTokenAllowed[token]) {
                if (channel.tokenTotalDeposits[token] >= minTotalDeposits) {
                    if (currentMatch >= offset) {
                        channelIds[resultIndex] = channel.id;
                        totalDeposits[resultIndex] = channel.tokenTotalDeposits[token];
                        resultIndex++;
                    }
                    currentMatch++;
                }
            }
        }
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function deriveAddressFromPubkey(uint256 pkx, uint256 pky) internal pure returns (address) {
        bytes32 h = keccak256(abi.encodePacked(pkx, pky));
        return address(uint160(uint256(h)));
    }

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
     * @notice Returns the address of the current implementation contract
     * @dev Uses EIP-1967 standard storage slot for implementation address
     * @return implementation The address of the implementation contract
     */
    function getImplementation() external view returns (address implementation) {
        bytes32 slot = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        assembly {
            implementation := sload(slot)
        }
    }

    uint256[42] private __gap;
}

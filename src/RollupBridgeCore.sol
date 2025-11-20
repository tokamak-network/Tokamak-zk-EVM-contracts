// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import "lib/openzeppelin-contracts-upgradeable/contracts/utils/cryptography/ECDSAUpgradeable.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/security/ReentrancyGuardUpgradeable.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "./library/RollupBridgeLib.sol";

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

        uint256 requiredTreeSize =
            RollupBridgeLib.determineTreeSize(params.participants.length, params.allowedTokens.length);

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
        address signerAddr = RollupBridgeLib.deriveAddressFromPubkey(params.pkx, params.pky);
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
        returns (
            address[] memory allowedTokens,
            ChannelState state,
            uint256 participantCount,
            bytes32 initialRoot
        )
    {
        RollupBridgeCoreStorage storage $ = _getRollupBridgeCoreStorage();
        Channel storage channel = $.channels[channelId];
        return (
            channel.allowedTokens,
            channel.state,
            channel.participants.length,
            channel.initialStateRoot
        );
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

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    uint256[42] private __gap;
}

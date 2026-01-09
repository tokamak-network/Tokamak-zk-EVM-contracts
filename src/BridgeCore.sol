// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import "lib/openzeppelin-contracts-upgradeable/contracts/utils/cryptography/ECDSAUpgradeable.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/security/ReentrancyGuardUpgradeable.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";

contract BridgeCore is ReentrancyGuardUpgradeable, OwnableUpgradeable, UUPSUpgradeable {
    using ECDSAUpgradeable for bytes32;

    enum ChannelState {
        None,
        Initialized,
        Open,
        Closing
    }

    struct ChannelParams {
        bytes32 channelId;
        address targetContract;
        address[] whitelisted;
        bool enableFrostSignature;
    }

    struct TargetContract {
        // contractAddress removed - redundant with mapping key
        PreAllocatedLeaf[] storageSlot;
        RegisteredFunction[] registeredFunctions;
    }

    struct PreAllocatedLeaf {
        uint256 value;
        bytes32 key;
        bool isActive;
    }

    struct RegisteredFunction {
        bytes32 functionSignature;
        bytes32 instancesHash;
        uint128[] preprocessedPart1;
        uint256[] preprocessedPart2;
    }

    // User-specific data consolidated
    struct UserChannelData {
        uint256 deposit;
        uint256 l2MptKey;
        bool isParticipant;
    }

    struct Channel {
        // Slot 1
        bytes32 id;
        // Slot 2: pack addresses and small values (20 + 20 + 1 + 1 + 1 + 13 bytes = 56 bytes)
        address targetContract; // 20 bytes
        address leader; // 20 bytes
        ChannelState state; // 1 byte
        bool sigVerified; // 1 byte
        bool frostSignatureEnabled; // 1 byte
        // 13 bytes available for future use

        // Slot 3: signer and counts (20 + 8 + 4 bytes = 32 bytes)
        address signerAddr; // 20 bytes
        uint64 requiredTreeSize; // 8 bytes (enough for tree size)
        uint32 preAllocatedLeavesCount; // 4 bytes (max 4.2B leaves)
        // Slot 4-5: timestamps (each 128 bits is enough until year 10^38)
        uint128 openTimestamp; // 16 bytes
        uint128 closeTimestamp; // 16 bytes
        uint128 _reserved; // 16 bytes for future use
        // Slots 6-7: state roots
        bytes32 initialStateRoot;
        bytes32 finalStateRoot;
        // Slot 8: block info
        bytes32 blockInfosHash;
        // Slots 9-10: public key
        uint256 pkx;
        uint256 pky;
        // Slot 11: total deposits
        uint256 totalDeposits;
        // Dynamic storage (mappings and arrays)
        // address[] whitelisted;
        mapping(address => bool) isWhiteListed;
        address[] participants;
        mapping(address => UserChannelData) userData;
    }

    uint256 public constant MIN_PARTICIPANTS = 1;
    uint256 public constant MAX_PARTICIPANTS = 128;

    /// @custom:storage-location erc7201:tokamak.storage.BridgeCore
    struct BridgeCoreStorage {
        mapping(bytes32 => Channel) channels;
        mapping(address => bool) isChannelLeader;
        mapping(address => TargetContract) allowedTargetContracts;
        address depositManager;
        address proofManager;
        address withdrawManager;
        address adminManager;
        mapping(address => mapping(bytes32 => PreAllocatedLeaf)) preAllocatedLeaves;
        mapping(address => bytes32[]) targetContractPreAllocatedKeys;
        mapping(address => mapping(bytes32 => mapping(address => uint256))) withdrawAmount;
    }

    bytes32 private constant BridgeCoreStorageLocation =
        0x1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e4f5a6b7c8d9e0f1a00;

    event ChannelOpened(bytes32 indexed channelId, address targetContract);
    event ChannelPublicKeySet(bytes32 indexed channelId, uint256 pkx, uint256 pky, address signerAddr);
    event PreAllocatedLeafSet(address indexed targetContract, bytes32 indexed mptKey, uint256 value);
    event PreAllocatedLeafRemoved(address indexed targetContract, bytes32 indexed mptKey);
    event ChannelDeleted(bytes32 indexed channelId, uint256 cleanupTime);

    modifier onlyManager() {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
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

        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        $.depositManager = _depositManager;
        $.proofManager = _proofManager;
        $.withdrawManager = _withdrawManager;
        $.adminManager = _adminManager;
    }

    // ========== EXTERNAL FUNCTIONS ==========

    function openChannel(ChannelParams calldata params) external returns (bytes32 channelId) {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();

        require(params.channelId != bytes32(0), "Channel ID cannot be zero");
        require(params.targetContract != address(0), "Target contract cannot be zero address");
        require(_isTargetContractAllowed(params.targetContract), "Target contract not allowed");
        require($.channels[params.channelId].leader == address(0), "Channel ID already exists");

        channelId = params.channelId;

        // Get number of active pre-allocated leaves for this target contract
        uint256 preAllocatedCount = _getActivePreAllocatedCount(params.targetContract);

        // Calculate maximum allowed participants considering pre-allocated leaves
        uint256 maxAllowedParticipants = MAX_PARTICIPANTS - preAllocatedCount;

        require(
            params.whitelisted.length >= MIN_PARTICIPANTS && params.whitelisted.length <= maxAllowedParticipants,
            "Invalid whitelisted count considering pre-allocated leaves"
        );

        uint256 requiredTreeSize = determineTreeSize(params.whitelisted.length + preAllocatedCount, 1);

        $.isChannelLeader[msg.sender] = true;
        Channel storage channel = $.channels[channelId];

        channel.id = channelId;
        channel.targetContract = params.targetContract;
        channel.leader = msg.sender;
        channel.openTimestamp = uint128(block.timestamp);
        channel.state = ChannelState.Initialized;
        channel.requiredTreeSize = uint64(requiredTreeSize);
        channel.preAllocatedLeavesCount = uint32(preAllocatedCount);
        channel.frostSignatureEnabled = params.enableFrostSignature;

        uint256 whitelistedLength = params.whitelisted.length;
        for (uint256 i = 0; i < whitelistedLength;) {
            address whitelistedUser = params.whitelisted[i];
            
            channel.isWhiteListed[whitelistedUser] = true;
            unchecked {
                ++i;
            }
        }

        emit ChannelOpened(channelId, params.targetContract);
    }

    function setChannelPublicKey(bytes32 channelId, uint256 pkx, uint256 pky) external {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        Channel storage channel = $.channels[channelId];

        require(channel.leader != address(0), "Channel does not exist");
        require(msg.sender == channel.leader, "Only channel leader can set public key");
        require(channel.frostSignatureEnabled, "frost is disabled");

        require(channel.state == ChannelState.Initialized, "Can only set public key for initialized channel");
        require(channel.pkx == 0 && channel.pky == 0, "Public key already set");

        channel.pkx = pkx;
        channel.pky = pky;
        address signerAddr = deriveAddressFromPubkey(pkx, pky);
        channel.signerAddr = signerAddr;

        emit ChannelPublicKeySet(channelId, pkx, pky, signerAddr);
    }

    // Manager setter functions
    function updateChannelUserDeposits(bytes32 channelId, address participant, uint256 amount) external onlyManager {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        $.channels[channelId].userData[participant].deposit += amount;
    }

    function updateChannelTotalDeposits(bytes32 channelId, uint256 amount) external onlyManager {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        $.channels[channelId].totalDeposits += amount;
    }

    function setChannelL2MptKey(bytes32 channelId, address participant, uint256 mptKey) external onlyManager {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        Channel storage channel = $.channels[channelId];

        // Check if the mptKey is already used by another participant
        for (uint256 i = 0; i < channel.participants.length; i++) {
            address existingParticipant = channel.participants[i];
            if (
                existingParticipant != participant && channel.userData[existingParticipant].l2MptKey == mptKey
                    && mptKey != 0
            ) {
                revert("L2MPTKey already in use by another participant");
            }
        }

        channel.userData[participant].l2MptKey = mptKey;
    }

    function setChannelInitialStateRoot(bytes32 channelId, bytes32 stateRoot) external onlyManager {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        $.channels[channelId].initialStateRoot = stateRoot;
    }

    function setChannelFinalStateRoot(bytes32 channelId, bytes32 stateRoot) external onlyManager {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        $.channels[channelId].finalStateRoot = stateRoot;
    }

    function setChannelState(bytes32 channelId, ChannelState state) external onlyManager {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        $.channels[channelId].state = state;
    }

    function setChannelWithdrawAmounts(bytes32 channelId, address[] memory participants, uint256[] memory amounts)
        external
        onlyManager
    {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        
        // Get target contract before channel cleanup
        address targetContract = $.channels[channelId].targetContract;

        for (uint256 participantIdx = 0; participantIdx < participants.length; participantIdx++) {
            address participant = participants[participantIdx];
            uint256 finalBalance = amounts[participantIdx];
            $.withdrawAmount[participant][channelId][targetContract] = finalBalance;
        }
    }

    function setChannelSignatureVerified(bytes32 channelId, bool verified) external onlyManager {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        $.channels[channelId].sigVerified = verified;
    }

    function setAllowedTargetContract(address targetContract, PreAllocatedLeaf[] memory storageSlots, bool allowed)
        external
        onlyManager
    {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();

        if (allowed) {
            // Clear existing storage slots
            delete $.allowedTargetContracts[targetContract].storageSlot;

            // Add new storage slots
            for (uint256 i = 0; i < storageSlots.length; i++) {
                $.allowedTargetContracts[targetContract].storageSlot.push(storageSlots[i]);
            }

            // If no storage slots provided and no functions registered, add a dummy entry
            // to mark the contract as allowed
            if (storageSlots.length == 0 && $.allowedTargetContracts[targetContract].registeredFunctions.length == 0) {
                // Push a dummy inactive leaf to mark as allowed
                $.allowedTargetContracts[targetContract].storageSlot.push(
                    PreAllocatedLeaf({value: 0, key: bytes32(0), isActive: false})
                );
            }
        } else {
            delete $.allowedTargetContracts[targetContract];
        }
    }

    function registerFunction(
        address targetContract,
        bytes32 functionSignature,
        uint128[] memory preprocessedPart1,
        uint256[] memory preprocessedPart2,
        bytes32 instancesHash
    ) external onlyManager {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();

        require(_isTargetContractAllowed(targetContract), "Target contract not allowed");

        // Also add to target contract's registered functions
        TargetContract storage target = $.allowedTargetContracts[targetContract];

        // Check if function already exists for this target
        bool functionExists = false;
        for (uint256 i = 0; i < target.registeredFunctions.length; i++) {
            if (target.registeredFunctions[i].functionSignature == functionSignature) {
                // Update existing function
                target.registeredFunctions[i] = RegisteredFunction({
                    functionSignature: functionSignature,
                    instancesHash: instancesHash,
                    preprocessedPart1: preprocessedPart1,
                    preprocessedPart2: preprocessedPart2
                });
                functionExists = true;
                break;
            }
        }

        // If function doesn't exist, add it
        if (!functionExists) {
            target.registeredFunctions.push(
                RegisteredFunction({
                    functionSignature: functionSignature,
                    instancesHash: instancesHash,
                    preprocessedPart1: preprocessedPart1,
                    preprocessedPart2: preprocessedPart2
                })
            );
        }
    }

    function unregisterFunction(address targetContract, bytes32 functionSignature) external onlyManager {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();

        require(_isTargetContractAllowed(targetContract), "Target contract not allowed");

        // Remove from target contract's registered functions
        TargetContract storage target = $.allowedTargetContracts[targetContract];
        uint256 functionsLength = target.registeredFunctions.length;

        for (uint256 i = 0; i < functionsLength; i++) {
            if (target.registeredFunctions[i].functionSignature == functionSignature) {
                // Move the last element to this position and pop
                if (i != functionsLength - 1) {
                    target.registeredFunctions[i] = target.registeredFunctions[functionsLength - 1];
                }
                target.registeredFunctions.pop();
                break;
            }
        }
    }

    function clearWithdrawableAmount(bytes32 channelId, address participant, address targetContract) external onlyManager {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        $.withdrawAmount[participant][channelId][targetContract] = 0;
    }

    function setChannelCloseTimestamp(bytes32 channelId, uint256 timestamp) external onlyManager {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        $.channels[channelId].closeTimestamp = uint128(timestamp);
    }

    function setChannelBlockInfosHash(bytes32 channelId, bytes32 blockInfosHash) external onlyManager {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        $.channels[channelId].blockInfosHash = blockInfosHash;
    }

    function addParticipantOnDeposit(bytes32 channelId, address user) external onlyManager {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        Channel storage channel = $.channels[channelId];

        // require(channel.userData[user].isParticipant, "User not whitelisted");
        require(channel.isWhiteListed[user], "User not whitelisted");

        // Check if user is already in participants array
        for (uint256 i = 0; i < channel.participants.length; i++) {
            if (channel.participants[i] == user) {
                return; // User already in participants
            }
        }

        // Add user to participants array
        channel.participants.push(user);
    }

    function cleanupChannel(bytes32 channelId) external onlyManager {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        Channel storage channel = $.channels[channelId];

        require(channel.leader != address(0), "Channel does not exist");

        // Remove channel leader flag and delete channel
        $.isChannelLeader[channel.leader] = false;
        delete $.channels[channelId];

        emit ChannelDeleted(channelId, block.timestamp);
    }



    // ========== PRE-ALLOCATED LEAVES MANAGEMENT ==========

    /**
     * @notice Set a pre-allocated leaf value for a target contract
     * @dev Only managers can call this function
     * @param targetContract The target contract address
     * @param key The MPT key for the pre-allocated leaf
     * @param value The value for the pre-allocated leaf
     */
    function setPreAllocatedLeaf(address targetContract, bytes32 key, uint256 value) external onlyManager {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();

        require(_isTargetContractAllowed(targetContract), "Target contract not allowed");
        require(key != bytes32(0), "MPT key cannot be zero");

        PreAllocatedLeaf storage leaf = $.preAllocatedLeaves[targetContract][key];

        // If this is a new pre-allocated leaf, add it to the keys array
        if (!leaf.isActive) {
            $.targetContractPreAllocatedKeys[targetContract].push(key);
        }

        leaf.key = key;
        leaf.value = value;
        leaf.isActive = true;

        emit PreAllocatedLeafSet(targetContract, key, value);
    }

    /**
     * @notice Remove a pre-allocated leaf for a target contract
     * @dev Only managers can call this function
     * @param targetContract The target contract address
     * @param key The MPT key to remove
     */
    function removePreAllocatedLeaf(address targetContract, bytes32 key) external onlyManager {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();

        PreAllocatedLeaf storage leaf = $.preAllocatedLeaves[targetContract][key];
        require(leaf.isActive, "Pre-allocated leaf does not exist");

        // Remove from the keys array
        bytes32[] storage keys = $.targetContractPreAllocatedKeys[targetContract];
        for (uint256 i = 0; i < keys.length; i++) {
            if (keys[i] == key) {
                keys[i] = keys[keys.length - 1];
                keys.pop();
                break;
            }
        }

        // Remove the leaf
        delete $.preAllocatedLeaves[targetContract][key];

        emit PreAllocatedLeafRemoved(targetContract, key);
    }

    /**
     * @notice Get a pre-allocated leaf value
     * @param targetContract The target contract address
     * @param key The MPT key
     * @return value The value of the pre-allocated leaf
     * @return exists Whether the leaf exists
     */
    function getPreAllocatedLeaf(address targetContract, bytes32 key)
        external
        view
        returns (uint256 value, bool exists)
    {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        PreAllocatedLeaf storage leaf = $.preAllocatedLeaves[targetContract][key];
        return (leaf.value, leaf.isActive);
    }

    /**
     * @notice Get all pre-allocated leaves for a target contract
     * @param targetContract The target contract address
     * @return keys Array of pre-allocated keys
     */
    function getPreAllocatedKeys(address targetContract) external view returns (bytes32[] memory keys) {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        return $.targetContractPreAllocatedKeys[targetContract];
    }

    /**
     * @notice Get the number of pre-allocated leaves for a target contract
     * @param targetContract The target contract address
     * @return count Number of pre-allocated leaves
     */
    function getPreAllocatedLeavesCount(address targetContract) external view returns (uint256 count) {
        return _getActivePreAllocatedCount(targetContract);
    }

    /**
     * @notice Get maximum allowed participants for a target contract considering pre-allocated leaves
     * @param targetContract The target contract address
     * @return maxParticipants Maximum number of participants allowed
     */
    function getMaxAllowedParticipants(address targetContract) external view returns (uint256 maxParticipants) {
        uint256 preAllocatedCount = _getActivePreAllocatedCount(targetContract);
        return MAX_PARTICIPANTS - preAllocatedCount;
    }

    /**
     * @notice Get the number of pre-allocated leaves for a specific channel
     * @param channelId The channel ID
     * @return count Number of pre-allocated leaves in the channel
     */
    function getChannelPreAllocatedLeavesCount(bytes32 channelId) external view returns (uint256 count) {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        return $.channels[channelId].preAllocatedLeavesCount;
    }

    // ========== INTERNAL FUNCTIONS ==========

    function _getBridgeCoreStorage() internal pure returns (BridgeCoreStorage storage $) {
        assembly {
            $.slot := BridgeCoreStorageLocation
        }
    }

    function _isTargetContractAllowed(address targetContract) internal view returns (bool) {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        TargetContract storage target = $.allowedTargetContracts[targetContract];
        // A target contract is allowed if it has storage slots or registered functions
        // (including dummy inactive entries used just to mark as allowed)
        return target.storageSlot.length > 0 || target.registeredFunctions.length > 0;
    }

    function _getActivePreAllocatedCount(address targetContract) internal view returns (uint256) {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        uint256 count = 0;
        bytes32[] memory keys = $.targetContractPreAllocatedKeys[targetContract];
        for (uint256 i = 0; i < keys.length; i++) {
            if ($.preAllocatedLeaves[targetContract][keys[i]].isActive) {
                count++;
            }
        }
        return count;
    }


    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function deriveAddressFromPubkey(uint256 pkx, uint256 pky) internal pure returns (address) {
        bytes32 h = keccak256(abi.encodePacked(pkx, pky));
        return address(uint160(uint256(h)));
    }

    function determineTreeSize(uint256 participantCount, uint256 contractCount) internal pure returns (uint256) {
        uint256 totalLeaves = participantCount * contractCount;

        if (totalLeaves <= 16) {
            return 16;
        } else if (totalLeaves <= 32) {
            return 32;
        } else if (totalLeaves <= 64) {
            return 64;
        } else if (totalLeaves <= 128) {
            return 128;
        } else {
            revert("Too many participant-contract combinations");
        }
    }

    // ========== OWNER FUNCTIONS ==========

    function updateManagerAddresses(
        address _depositManager,
        address _proofManager,
        address _withdrawManager,
        address _adminManager
    ) external onlyOwner {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        if (_depositManager != address(0)) $.depositManager = _depositManager;
        if (_proofManager != address(0)) $.proofManager = _proofManager;
        if (_withdrawManager != address(0)) $.withdrawManager = _withdrawManager;
        if (_adminManager != address(0)) $.adminManager = _adminManager;
    }

    // ========== GETTER FUNCTIONS ==========

    function depositManager() external view returns (address) {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        return $.depositManager;
    }

    function withdrawManager() external view returns (address) {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        return $.withdrawManager;
    }

    function getChannelState(bytes32 channelId) external view returns (ChannelState) {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        return $.channels[channelId].state;
    }

    function isChannelParticipant(bytes32 channelId, address participant) external view returns (bool) {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        return $.channels[channelId].userData[participant].isParticipant;
    }

    function getChannelTargetContract(bytes32 channelId) external view returns (address) {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        return $.channels[channelId].targetContract;
    }

    function getChannelLeader(bytes32 channelId) external view returns (address) {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        return $.channels[channelId].leader;
    }

    function getChannelParticipants(bytes32 channelId) external view returns (address[] memory) {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        return $.channels[channelId].participants;
    }

    function isChannelWhitelisted(bytes32 channelId, address addr) external view returns (bool) {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        return $.channels[channelId].isWhiteListed[addr];
    }

    function getChannelTreeSize(bytes32 channelId) external view returns (uint256) {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        return $.channels[channelId].requiredTreeSize;
    }

    function getParticipantDeposit(bytes32 channelId, address participant) external view returns (uint256) {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        return $.channels[channelId].userData[participant].deposit;
    }

    function getL2MptKey(bytes32 channelId, address participant) external view returns (uint256) {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        return $.channels[channelId].userData[participant].l2MptKey;
    }

    function getChannelTotalDeposits(bytes32 channelId) external view returns (uint256) {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        return $.channels[channelId].totalDeposits;
    }

    function getChannelPublicKey(bytes32 channelId) external view returns (uint256 pkx, uint256 pky) {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        Channel storage channel = $.channels[channelId];
        return (channel.pkx, channel.pky);
    }

    function isChannelPublicKeySet(bytes32 channelId) external view returns (bool) {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        Channel storage channel = $.channels[channelId];
        return channel.pkx != 0 && channel.pky != 0;
    }

    function getChannelSignerAddr(bytes32 channelId) external view returns (address) {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        return $.channels[channelId].signerAddr;
    }

    function getChannelFinalStateRoot(bytes32 channelId) external view returns (bytes32) {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        return $.channels[channelId].finalStateRoot;
    }

    function getChannelInitialStateRoot(bytes32 channelId) external view returns (bytes32) {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        return $.channels[channelId].initialStateRoot;
    }

    function isAllowedTargetContract(address targetContract) external view returns (bool) {
        return _isTargetContractAllowed(targetContract);
    }

    function getTargetContractData(address targetContract) external view returns (TargetContract memory) {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        require(_isTargetContractAllowed(targetContract), "Target contract not allowed");
        return $.allowedTargetContracts[targetContract];
    }

    function getChannelInfo(bytes32 channelId)
        external
        view
        returns (address targetContract, ChannelState state, uint256 participantCount, bytes32 initialRoot)
    {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        Channel storage channel = $.channels[channelId];
        return (channel.targetContract, channel.state, channel.participants.length, channel.initialStateRoot);
    }

    function isSignatureVerified(bytes32 channelId) external view returns (bool) {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        return $.channels[channelId].sigVerified;
    }

    function getWithdrawableAmount(bytes32 channelId, address participant, address targetContract) external view returns (uint256) {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        return $.withdrawAmount[participant][channelId][targetContract];
    }

    function hasUserWithdrawn(bytes32 channelId, address participant, address targetContract) external view returns (bool) {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        return $.withdrawAmount[participant][channelId][targetContract] == 0;
    }

    function getChannelBlockInfosHash(bytes32 channelId) external view returns (bytes32) {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        return $.channels[channelId].blockInfosHash;
    }

    function isMarkedChannelLeader(address addr) external view returns (bool) {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        return $.isChannelLeader[addr];
    }

    function isFrostSignatureEnabled(bytes32 channelId) external view returns (bool) {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        return $.channels[channelId].frostSignatureEnabled;
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

    
    /**
     * @notice Generate a channel ID hash from leader address and salt
     * @dev This is a pure function that can be called off-chain to generate channel IDs
     * @param leader The channel leader address
     * @param salt Any salt value to ensure uniqueness
     * @return channelId The generated channel ID
     */
    function generateChannelId(address leader, bytes32 salt) external pure returns (bytes32 channelId) {
        return keccak256(abi.encodePacked(leader, salt));
    }

    uint256[42] private __gap;
}

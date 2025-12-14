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
        Closing,
        Closed
    }

    struct ChannelParams {
        address targetContract;
        address[] participants;
        uint256 timeout;
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
        uint256 withdrawAmount;
        bool hasWithdrawn;
        bool isParticipant;
    }

    struct Channel {
        // Slot 1
        uint256 id;
        // Slot 2: pack addresses and small values (20 + 20 + 1 + 1 + 14 bytes = 56 bytes)
        address targetContract; // 20 bytes
        address leader; // 20 bytes
        ChannelState state; // 1 byte
        bool sigVerified; // 1 byte
        // 14 bytes available for future use

        // Slot 3: signer and counts (20 + 8 + 4 bytes = 32 bytes)
        address signerAddr; // 20 bytes
        uint64 requiredTreeSize; // 8 bytes (enough for tree size)
        uint32 preAllocatedLeavesCount; // 4 bytes (max 4.2B leaves)
        // Slot 4-5: timestamps (each 128 bits is enough until year 10^38)
        uint128 openTimestamp; // 16 bytes
        uint128 timeout; // 16 bytes
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
        address[] participants;
        mapping(address => UserChannelData) userData;
    }

    uint256 public constant MIN_PARTICIPANTS = 1;
    uint256 public constant MAX_PARTICIPANTS = 128;

    /// @custom:storage-location erc7201:tokamak.storage.BridgeCore
    struct BridgeCoreStorage {
        mapping(uint256 => Channel) channels;
        mapping(address => bool) isChannelLeader;
        mapping(address => TargetContract) allowedTargetContracts;
        // isTargetContractAllowed removed - check if allowedTargetContracts[addr].storageSlot.length > 0 or registeredFunctions.length > 0
        mapping(bytes32 => RegisteredFunction) registeredFunctions; // Keep for backward compatibility during migration
        uint256 nextChannelId;
        address depositManager;
        address proofManager;
        address withdrawManager;
        address adminManager;
        mapping(address => mapping(bytes32 => PreAllocatedLeaf)) preAllocatedLeaves;
        mapping(address => bytes32[]) targetContractPreAllocatedKeys;
    }

    bytes32 private constant BridgeCoreStorageLocation =
        0x1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e4f5a6b7c8d9e0f1a00;

    event ChannelOpened(uint256 indexed channelId, address targetContract);
    event ChannelPublicKeySet(uint256 indexed channelId, uint256 pkx, uint256 pky, address signerAddr);
    event PreAllocatedLeafSet(address indexed targetContract, bytes32 indexed mptKey, uint256 value);
    event PreAllocatedLeafRemoved(address indexed targetContract, bytes32 indexed mptKey);

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

    function openChannel(ChannelParams calldata params) external returns (uint256 channelId) {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();

        //disabled for testing
        //require(!$.isChannelLeader[msg.sender], "Channel limit reached");
        require(params.targetContract != address(0), "Target contract cannot be zero address");
        require(_isTargetContractAllowed(params.targetContract), "Target contract not allowed");
        require(params.timeout >= 1 hours && params.timeout <= 365 days, "Invalid timeout");

        // Get number of active pre-allocated leaves for this target contract
        uint256 preAllocatedCount = _getActivePreAllocatedCount(params.targetContract);

        // Calculate maximum allowed participants considering pre-allocated leaves
        uint256 maxAllowedParticipants = MAX_PARTICIPANTS - preAllocatedCount;

        require(
            params.participants.length >= MIN_PARTICIPANTS && params.participants.length <= maxAllowedParticipants,
            "Invalid participant count considering pre-allocated leaves"
        );

        uint256 requiredTreeSize = determineTreeSize(params.participants.length + preAllocatedCount, 1);

        unchecked {
            channelId = $.nextChannelId++;
        }

        $.isChannelLeader[msg.sender] = true;
        Channel storage channel = $.channels[channelId];

        channel.id = channelId;
        channel.targetContract = params.targetContract;
        channel.leader = msg.sender;
        channel.openTimestamp = uint128(block.timestamp);
        channel.timeout = uint128(params.timeout);
        channel.state = ChannelState.Initialized;
        channel.requiredTreeSize = uint64(requiredTreeSize);
        channel.preAllocatedLeavesCount = uint32(preAllocatedCount);

        uint256 participantsLength = params.participants.length;
        for (uint256 i = 0; i < participantsLength;) {
            address participant = params.participants[i];
            require(!channel.userData[participant].isParticipant, "Duplicate participant");

            channel.participants.push(participant);
            channel.userData[participant].isParticipant = true;
            unchecked {
                ++i;
            }
        }

        emit ChannelOpened(channelId, params.targetContract);
    }

    function setChannelPublicKey(uint256 channelId, uint256 pkx, uint256 pky) external {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        Channel storage channel = $.channels[channelId];

        require(channel.leader != address(0), "Channel does not exist");
        require(msg.sender == channel.leader, "Only channel leader can set public key");
        require(channel.state == ChannelState.Initialized, "Can only set public key for initialized channel");
        require(channel.pkx == 0 && channel.pky == 0, "Public key already set");

        channel.pkx = pkx;
        channel.pky = pky;
        address signerAddr = deriveAddressFromPubkey(pkx, pky);
        channel.signerAddr = signerAddr;

        emit ChannelPublicKeySet(channelId, pkx, pky, signerAddr);
    }

    // Manager setter functions
    function updateChannelUserDeposits(uint256 channelId, address participant, uint256 amount) external onlyManager {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        $.channels[channelId].userData[participant].deposit += amount;
    }

    function updateChannelTotalDeposits(uint256 channelId, uint256 amount) external onlyManager {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        $.channels[channelId].totalDeposits += amount;
    }

    function setChannelL2MptKey(uint256 channelId, address participant, uint256 mptKey) external onlyManager {
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

    function setChannelInitialStateRoot(uint256 channelId, bytes32 stateRoot) external onlyManager {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        $.channels[channelId].initialStateRoot = stateRoot;
    }

    function setChannelFinalStateRoot(uint256 channelId, bytes32 stateRoot) external onlyManager {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        $.channels[channelId].finalStateRoot = stateRoot;
    }

    function setChannelState(uint256 channelId, ChannelState state) external onlyManager {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        $.channels[channelId].state = state;
        if (state == ChannelState.Closed) {
            $.isChannelLeader[$.channels[channelId].leader] = false;
        }
    }

    function setChannelWithdrawAmounts(uint256 channelId, address[] memory participants, uint256[] memory amounts)
        external
        onlyManager
    {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        Channel storage channel = $.channels[channelId];

        for (uint256 participantIdx = 0; participantIdx < participants.length; participantIdx++) {
            address participant = participants[participantIdx];
            uint256 finalBalance = amounts[participantIdx];
            channel.userData[participant].withdrawAmount = finalBalance;
        }
    }

    function setChannelSignatureVerified(uint256 channelId, bool verified) external onlyManager {
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

        // Store in global registry for backward compatibility
        $.registeredFunctions[functionSignature] = RegisteredFunction({
            functionSignature: functionSignature,
            instancesHash: instancesHash,
            preprocessedPart1: preprocessedPart1,
            preprocessedPart2: preprocessedPart2
        });

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

        // Delete from global registry
        delete $.registeredFunctions[functionSignature];

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

    function markUserWithdrawn(uint256 channelId, address participant) external onlyManager {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        $.channels[channelId].userData[participant].hasWithdrawn = true;
    }

    function clearWithdrawableAmount(uint256 channelId, address participant) external onlyManager {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        $.channels[channelId].userData[participant].withdrawAmount = 0;
    }

    function setChannelCloseTimestamp(uint256 channelId, uint256 timestamp) external onlyManager {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        $.channels[channelId].closeTimestamp = uint128(timestamp);
    }

    function setChannelBlockInfosHash(uint256 channelId, bytes32 blockInfosHash) external onlyManager {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        $.channels[channelId].blockInfosHash = blockInfosHash;
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
    function getChannelPreAllocatedLeavesCount(uint256 channelId) external view returns (uint256 count) {
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

    function _isTargetContractValid(Channel storage channel, address targetContract) private view returns (bool) {
        return channel.targetContract == targetContract;
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

    function getChannelState(uint256 channelId) external view returns (ChannelState) {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        return $.channels[channelId].state;
    }

    function isChannelParticipant(uint256 channelId, address participant) external view returns (bool) {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        return $.channels[channelId].userData[participant].isParticipant;
    }

    function getChannelTargetContract(uint256 channelId) external view returns (address) {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        return $.channels[channelId].targetContract;
    }

    function getChannelLeader(uint256 channelId) external view returns (address) {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        return $.channels[channelId].leader;
    }

    function getChannelParticipants(uint256 channelId) external view returns (address[] memory) {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        return $.channels[channelId].participants;
    }

    function getChannelTreeSize(uint256 channelId) external view returns (uint256) {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        return $.channels[channelId].requiredTreeSize;
    }

    function getParticipantDeposit(uint256 channelId, address participant) external view returns (uint256) {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        return $.channels[channelId].userData[participant].deposit;
    }

    function getL2MptKey(uint256 channelId, address participant) external view returns (uint256) {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        return $.channels[channelId].userData[participant].l2MptKey;
    }

    function getChannelTotalDeposits(uint256 channelId) external view returns (uint256) {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        return $.channels[channelId].totalDeposits;
    }

    function getChannelPublicKey(uint256 channelId) external view returns (uint256 pkx, uint256 pky) {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        Channel storage channel = $.channels[channelId];
        return (channel.pkx, channel.pky);
    }

    function isChannelPublicKeySet(uint256 channelId) external view returns (bool) {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        Channel storage channel = $.channels[channelId];
        return channel.pkx != 0 && channel.pky != 0;
    }

    function getChannelSignerAddr(uint256 channelId) external view returns (address) {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        return $.channels[channelId].signerAddr;
    }

    function getChannelFinalStateRoot(uint256 channelId) external view returns (bytes32) {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        return $.channels[channelId].finalStateRoot;
    }

    function getChannelInitialStateRoot(uint256 channelId) external view returns (bytes32) {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        return $.channels[channelId].initialStateRoot;
    }

    function getChannelTimeout(uint256 channelId) external view returns (uint256 openTimestamp, uint256 timeout) {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        Channel storage channel = $.channels[channelId];
        return (channel.openTimestamp, channel.timeout);
    }

    function getRegisteredFunction(bytes32 functionSignature) external view returns (RegisteredFunction memory) {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        return $.registeredFunctions[functionSignature];
    }

    function isAllowedTargetContract(address targetContract) external view returns (bool) {
        return _isTargetContractAllowed(targetContract);
    }

    function getTargetContractData(address targetContract) external view returns (TargetContract memory) {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        require(_isTargetContractAllowed(targetContract), "Target contract not allowed");
        return $.allowedTargetContracts[targetContract];
    }

    /**
     * @notice Get registered functions for a specific target contract
     * @param targetContract The target contract address
     * @return Array of registered functions
     */
    function getTargetContractFunctions(address targetContract) external view returns (RegisteredFunction[] memory) {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        require(_isTargetContractAllowed(targetContract), "Target contract not allowed");
        return $.allowedTargetContracts[targetContract].registeredFunctions;
    }

    function nextChannelId() external view returns (uint256) {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        return $.nextChannelId;
    }

    function getChannelInfo(uint256 channelId)
        external
        view
        returns (address targetContract, ChannelState state, uint256 participantCount, bytes32 initialRoot)
    {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        Channel storage channel = $.channels[channelId];
        return (channel.targetContract, channel.state, channel.participants.length, channel.initialStateRoot);
    }

    function isSignatureVerified(uint256 channelId) external view returns (bool) {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        return $.channels[channelId].sigVerified;
    }

    function getWithdrawableAmount(uint256 channelId, address participant) external view returns (uint256) {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        return $.channels[channelId].userData[participant].withdrawAmount;
    }

    function hasUserWithdrawn(uint256 channelId, address participant) external view returns (bool) {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        return $.channels[channelId].userData[participant].hasWithdrawn;
    }

    function getChannelBlockInfosHash(uint256 channelId) external view returns (bytes32) {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        return $.channels[channelId].blockInfosHash;
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

    // === DASHBOARD FUNCTIONS ===

    /**
     * @notice Get the total number of channels created
     * @return Total number of channels
     */
    function getTotalChannels() external view returns (uint256) {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        return $.nextChannelId;
    }

    /**
     * @notice Get comprehensive channel statistics
     * @return openChannels Number of open channels
     * @return activeChannels Number of active channels (same as open)
     * @return closingChannels Number of closing channels
     * @return closedChannels Number of closed channels
     */
    function getChannelStats()
        external
        view
        returns (uint256 openChannels, uint256 activeChannels, uint256 closingChannels, uint256 closedChannels)
    {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();

        for (uint256 i = 0; i < $.nextChannelId; i++) {
            Channel storage channel = $.channels[i];
            if (channel.id > 0) {
                // Channel exists
                ChannelState state = channel.state;
                if (state == ChannelState.Open) {
                    openChannels++;
                    activeChannels++;
                } else if (state == ChannelState.Closing) {
                    closingChannels++;
                } else if (state == ChannelState.Closed) {
                    closedChannels++;
                }
            }
        }
    }

    /**
     * @notice Get a user's total balance across all channels and target contracts
     * @param user The user address
     * @return targetContracts Array of target contract addresses the user has deposited to
     * @return balances Array of corresponding balances
     */
    function getUserTotalBalance(address user)
        external
        view
        returns (address[] memory targetContracts, uint256[] memory balances)
    {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();

        // First pass: collect unique target contracts
        address[] memory allTargetContracts = new address[](1000); // Max estimate
        uint256 contractCount = 0;

        for (uint256 i = 0; i < $.nextChannelId; i++) {
            Channel storage channel = $.channels[i];
            if (channel.id > 0 && channel.userData[user].isParticipant) {
                address targetContract = channel.targetContract;
                bool isNewContract = true;
                for (uint256 k = 0; k < contractCount; k++) {
                    if (allTargetContracts[k] == targetContract) {
                        isNewContract = false;
                        break;
                    }
                }
                if (isNewContract) {
                    allTargetContracts[contractCount] = targetContract;
                    contractCount++;
                }
            }
        }

        // Second pass: calculate balances
        targetContracts = new address[](contractCount);
        balances = new uint256[](contractCount);

        for (uint256 i = 0; i < contractCount; i++) {
            targetContracts[i] = allTargetContracts[i];
            for (uint256 j = 0; j < $.nextChannelId; j++) {
                Channel storage channel = $.channels[j];
                if (
                    channel.id > 0 && channel.userData[user].isParticipant
                        && channel.targetContract == targetContracts[i]
                ) {
                    balances[i] += channel.userData[user].deposit;
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
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();

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
     * @return totalContractTypes Number of different target contract types the user has deposited to
     * @return channelsAsLeader Number of channels where user is the leader
     */
    function getUserAnalytics(address user)
        external
        view
        returns (
            uint256 totalChannelsJoined,
            uint256 activeChannelsCount,
            uint256 totalContractTypes,
            uint256 channelsAsLeader
        )
    {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();

        // Track unique target contracts
        address[] memory userContracts = new address[](1000);
        uint256 contractCount = 0;

        for (uint256 i = 0; i < $.nextChannelId; i++) {
            Channel storage channel = $.channels[i];
            if (channel.id > 0 && channel.userData[user].isParticipant) {
                totalChannelsJoined++;

                if (channel.state == ChannelState.Open) {
                    activeChannelsCount++;
                }

                if (channel.leader == user) {
                    channelsAsLeader++;
                }

                // Count unique target contracts where user has deposits
                if (channel.userData[user].deposit > 0) {
                    address targetContract = channel.targetContract;
                    bool isNewContract = true;
                    for (uint256 k = 0; k < contractCount; k++) {
                        if (userContracts[k] == targetContract) {
                            isNewContract = false;
                            break;
                        }
                    }
                    if (isNewContract) {
                        userContracts[contractCount] = targetContract;
                        contractCount++;
                    }
                }
            }
        }

        totalContractTypes = contractCount;
    }

    /**
     * @notice Get channel participation history for a user
     * @param user The user address
     * @return channelIds Array of channel IDs the user has participated in
     * @return states Array of corresponding channel states
     * @return joinTimestamps Array of when the user joined each channel
     * @return isLeaderFlags Array indicating if user was leader in each channel
     */
    function getChannelHistory(address user)
        external
        view
        returns (
            uint256[] memory channelIds,
            ChannelState[] memory states,
            uint256[] memory joinTimestamps,
            bool[] memory isLeaderFlags
        )
    {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();

        // First pass: count user's channels
        uint256 userChannelCount = 0;
        for (uint256 i = 0; i < $.nextChannelId; i++) {
            if ($.channels[i].id > 0 && $.channels[i].userData[user].isParticipant) {
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
            if (channel.id > 0 && channel.userData[user].isParticipant) {
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
     * @param amount The amount to deposit
     * @return canDeposit Whether the user can deposit
     * @return reason Reason if cannot deposit
     */
    function canUserDeposit(address user, uint256 channelId, uint256 amount)
        external
        view
        returns (bool canDeposit, string memory reason)
    {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        Channel storage channel = $.channels[channelId];

        if (channel.id == 0) {
            return (false, "Channel does not exist");
        }

        if (!channel.userData[user].isParticipant) {
            return (false, "User is not a participant in this channel");
        }

        if (channel.state != ChannelState.Open) {
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
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        Channel storage channel = $.channels[channelId];

        if (channel.id == 0) {
            return (false, "Channel does not exist");
        }

        if (!channel.userData[user].isParticipant) {
            return (false, "User is not a participant in this channel");
        }

        if (channel.state != ChannelState.Closed) {
            return (false, "Channel is not closed");
        }

        if (channel.userData[user].hasWithdrawn) {
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
     */
    function getSystemAnalytics()
        external
        view
        returns (
            uint256 totalChannelsCreated,
            uint256 totalValueLocked,
            uint256 totalUniqueUsers,
            uint256 averageChannelSize
        )
    {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();

        totalChannelsCreated = $.nextChannelId;

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
                totalValueLocked += channel.totalDeposits;
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
    function getChannelLiveMetrics(uint256 channelId)
        external
        view
        returns (
            uint256 activeParticipants,
            uint256 totalDeposits,
            uint256 averageDepositSize,
            uint256 timeActive,
            uint256 lastActivityTime
        )
    {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();
        Channel storage channel = $.channels[channelId];

        if (channel.id == 0) {
            return (0, 0, 0, 0, 0);
        }

        uint256 totalDepositValue = 0;
        uint256 depositCount = 0;

        // Count active participants and calculate metrics
        for (uint256 i = 0; i < channel.participants.length; i++) {
            address participant = channel.participants[i];
            uint256 deposit = channel.userData[participant].deposit;

            if (deposit > 0) {
                activeParticipants++;
                totalDepositValue += deposit;
                depositCount++;
            }
        }

        totalDeposits = depositCount;
        averageDepositSize = depositCount > 0 ? totalDepositValue / depositCount : 0;
        timeActive = channel.state == ChannelState.Closed
            ? channel.closeTimestamp - channel.openTimestamp
            : block.timestamp - channel.openTimestamp;
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
    function searchChannelsByParticipant(address participant, ChannelState state, uint256 limit, uint256 offset)
        external
        view
        returns (uint256[] memory channelIds, uint256 totalMatches)
    {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();

        // First pass: count matches
        for (uint256 i = 0; i < $.nextChannelId; i++) {
            Channel storage channel = $.channels[i];
            if (channel.id > 0 && channel.userData[participant].isParticipant) {
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
            if (channel.id > 0 && channel.userData[participant].isParticipant) {
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
     * @notice Search channels by target contract address
     * @param targetContract The target contract address to search for
     * @param minTotalDeposits Minimum total deposits required
     * @param limit Maximum number of results to return
     * @param offset Offset for pagination
     * @return channelIds Array of matching channel IDs
     * @return totalDeposits Array of total deposits for each channel
     * @return totalMatches Total number of matches (for pagination)
     */
    function searchChannelsByTargetContract(
        address targetContract,
        uint256 minTotalDeposits,
        uint256 limit,
        uint256 offset
    ) external view returns (uint256[] memory channelIds, uint256[] memory totalDeposits, uint256 totalMatches) {
        BridgeCoreStorage storage $ = _getBridgeCoreStorage();

        // First pass: count matches
        for (uint256 i = 0; i < $.nextChannelId; i++) {
            Channel storage channel = $.channels[i];
            if (channel.id > 0 && channel.targetContract == targetContract) {
                if (channel.totalDeposits >= minTotalDeposits) {
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
            if (channel.id > 0 && channel.targetContract == targetContract) {
                if (channel.totalDeposits >= minTotalDeposits) {
                    if (currentMatch >= offset) {
                        channelIds[resultIndex] = channel.id;
                        totalDeposits[resultIndex] = channel.totalDeposits;
                        resultIndex++;
                    }
                    currentMatch++;
                }
            }
        }
    }

    uint256[42] private __gap;
}

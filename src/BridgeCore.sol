// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import "@openzeppelin-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin-upgradeable/security/ReentrancyGuardUpgradeable.sol";

contract BridgeCore is Initializable, OwnableUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable {
    enum ChannelState {
        None,
        Initialized,
        Open,
        Closing
    }

    struct PreAllocatedLeaf {
        uint256 value;
        bytes32 key;
        bool isActive;
    }

    struct UserStorageSlot {
        uint8 slotOffset;
        bytes32 getterFunctionSignature;
        bool isLoadedOnChain;
    }

    struct RegisteredFunction {
        bytes32 functionSignature;
        bytes32 instancesHash;
        uint128[] preprocessedPart1;
        uint256[] preprocessedPart2;
    }

    struct TargetContract {
        PreAllocatedLeaf[] preAllocatedLeaves;
        RegisteredFunction[] registeredFunctions;
        UserStorageSlot[] userStorageSlots;
    }

    struct ChannelParams {
        bytes32 channelId;
        address targetContract;
        address[] whitelisted;
        bool enableFrostSignature;
    }

    uint256 public constant CHANNEL_TIMEOUT = 7 days;
    uint16 public constant nTokamakPublicInputs = 64;
    uint8 public constant nMerkleTreeLevels = 7;

    struct FunctionCfg {
        bytes32 instancesHash;
        bytes32 preprocessHash;
        bool exists;
    }

    struct Channel {
        bool exists;
        bytes32 id;
        address leader;
        address targetContract;
        ChannelState state;
        bool sigVerified;
        bool frostSignatureEnabled;
        uint64 requiredTreeSize;
        uint128 openTimestamp;
        uint128 closeTimestamp;
        bytes32 initialStateRoot;
        bytes32 finalStateRoot;
        bytes32 blockInfosHash;
        uint256 pkx;
        uint256 pky;
        address signerAddr;
        address[] participants;
        mapping(address => bool) isWhitelisted;
        mapping(address => bool) isParticipant;
        bytes32[] appFunctionSignatures;
        mapping(bytes32 => bool) hasAppFunctionSignature;
        address[] appStorageAddrs;
        mapping(address => bool) hasAppStorageAddr;
        mapping(address => mapping(address => uint256)) userStorageKey;
        mapping(address => mapping(address => bool)) hasUserStorageKey;
        mapping(address => mapping(uint256 => address)) storageKeyOwner;
        mapping(address => mapping(uint256 => bool)) hasStorageKeyOwner;
        mapping(address => mapping(uint256 => uint256)) validatedStorageValue;
        mapping(address => mapping(uint256 => bool)) hasValidatedStorageValue;
    }

    mapping(bytes32 => Channel) private _channels;

    mapping(address => TargetContract) private _targetContracts;
    mapping(address => bool) private _isAllowedTargetContract;
    mapping(address => bytes32[]) private _storagePreAllocKeys;
    mapping(address => mapping(bytes32 => bool)) private _storagePreAllocKeyExists;
    mapping(address => mapping(bytes32 => uint256)) private _storagePreAllocValue;
    mapping(address => mapping(bytes32 => bool)) private _storagePreAllocActive;
    mapping(address => uint8[]) private _storageUserSlots;
    mapping(address => mapping(uint8 => bool)) private _storageUserSlotExists;
    mapping(address => bytes32[]) private _storageFunctions;
    mapping(address => mapping(bytes32 => bool)) private _storageFunctionExists;

    mapping(bytes32 => address[]) private _functionStorages;
    mapping(bytes32 => mapping(address => bool)) private _functionStorageExists;
    mapping(bytes32 => FunctionCfg) private _functionCfg;

    mapping(bytes32 => mapping(address => mapping(uint16 => bytes32))) private _verifiedStateRoot;
    mapping(bytes32 => uint16[]) private _verifiedStateIndices;
    mapping(bytes32 => mapping(uint16 => bool)) private _verifiedStateIndexExists;

    mapping(bytes32 => mapping(uint8 => mapping(address => mapping(uint16 => bytes32)))) private _proposedStateRoot;
    mapping(bytes32 => uint8[]) private _proposedForkIds;
    mapping(bytes32 => mapping(uint8 => bool)) private _proposedForkExists;
    mapping(bytes32 => mapping(uint8 => uint16[])) private _proposedStateIndices;
    mapping(bytes32 => mapping(uint8 => mapping(uint16 => bool))) private _proposedStateIndexExists;

    address private _depositManager;
    address private _proofManager;
    address private _withdrawManager;
    address private _adminManager;

    event ChannelOpened(bytes32 indexed channelId, address indexed leader, address indexed targetContract);
    event ChannelPublicKeySet(bytes32 indexed channelId, uint256 pkx, uint256 pky, address signerAddr);
    event TargetContractAllowed(address indexed targetContract, bool allowed);
    event FunctionRegistered(bytes32 indexed functionSignature, address indexed storageAddr);
    event FunctionUnregistered(bytes32 indexed functionSignature, address indexed storageAddr);
    event SingleLeafUpdated(bytes32 indexed channelId, address indexed appStorageAddr, uint16 indexed stateIndex);
    event ProposedStateRootsVerified(bytes32 indexed channelId, uint8 indexed forkId, uint16 indexed stateIndex);

    modifier onlyManagerOrOwner() {
        require(
            msg.sender == owner() || msg.sender == _depositManager || msg.sender == _proofManager
                || msg.sender == _withdrawManager || msg.sender == _adminManager,
            "Only manager or owner"
        );
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address depositManager_,
        address proofManager_,
        address withdrawManager_,
        address adminManager_,
        address owner_
    ) external initializer {
        __Ownable_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

        _transferOwnership(owner_);
        _depositManager = depositManager_;
        _proofManager = proofManager_;
        _withdrawManager = withdrawManager_;
        _adminManager = adminManager_;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function updateManagerAddresses(
        address depositManager_,
        address proofManager_,
        address withdrawManager_,
        address adminManager_
    ) external onlyOwner {
        if (depositManager_ != address(0)) _depositManager = depositManager_;
        if (proofManager_ != address(0)) _proofManager = proofManager_;
        if (withdrawManager_ != address(0)) _withdrawManager = withdrawManager_;
        if (adminManager_ != address(0)) _adminManager = adminManager_;
    }

    function openChannel(ChannelParams calldata params) external returns (bytes32 channelId) {
        require(params.channelId != bytes32(0), "Channel ID cannot be zero");
        require(params.targetContract != address(0), "Invalid target contract");
        require(_isAllowedTargetContract[params.targetContract], "Target contract not allowed");
        require(!_channels[params.channelId].exists, "Channel ID already exists");

        channelId = params.channelId;
        Channel storage c = _channels[channelId];
        c.exists = true;
        c.id = channelId;
        c.leader = msg.sender;
        c.targetContract = params.targetContract;
        c.state = ChannelState.Initialized;
        c.frostSignatureEnabled = params.enableFrostSignature;
        c.requiredTreeSize = uint64(1 << nMerkleTreeLevels);
        c.openTimestamp = uint128(block.timestamp);

        _addWhitelistedUser(c, msg.sender);
        for (uint256 i = 0; i < params.whitelisted.length; i++) {
            _addWhitelistedUser(c, params.whitelisted[i]);
        }

        bytes32[] storage fns = _storageFunctions[params.targetContract];
        for (uint256 i = 0; i < fns.length; i++) {
            bytes32 fSig = fns[i];
            if (!c.hasAppFunctionSignature[fSig]) {
                c.hasAppFunctionSignature[fSig] = true;
                c.appFunctionSignatures.push(fSig);
            }

            address[] storage storages = _functionStorages[fSig];
            for (uint256 j = 0; j < storages.length; j++) {
                address s = storages[j];
                if (!c.hasAppStorageAddr[s]) {
                    c.hasAppStorageAddr[s] = true;
                    c.appStorageAddrs.push(s);
                }
            }
        }

        if (!c.hasAppStorageAddr[params.targetContract]) {
            c.hasAppStorageAddr[params.targetContract] = true;
            c.appStorageAddrs.push(params.targetContract);
        }

        emit ChannelOpened(channelId, msg.sender, params.targetContract);
    }

    function setChannelPublicKey(bytes32 channelId, uint256 pkx, uint256 pky) external {
        Channel storage c = _requireChannel(channelId);
        require(msg.sender == c.leader, "Only channel leader");
        require(c.frostSignatureEnabled, "Frost disabled");
        require(c.pkx == 0 && c.pky == 0, "Public key already set");

        c.pkx = pkx;
        c.pky = pky;
        c.signerAddr = _deriveAddressFromPubkey(pkx, pky);

        emit ChannelPublicKeySet(channelId, pkx, pky, c.signerAddr);
    }

    function setAllowedTargetContract(
        address targetContract,
        PreAllocatedLeaf[] memory leaves,
        UserStorageSlot[] memory userStorageSlots,
        bool allowed
    ) external onlyManagerOrOwner {
        require(targetContract != address(0), "Invalid target contract");

        _clearTargetContract(targetContract);

        if (!allowed) {
            _isAllowedTargetContract[targetContract] = false;
            emit TargetContractAllowed(targetContract, false);
            return;
        }

        _isAllowedTargetContract[targetContract] = true;

        for (uint256 i = 0; i < leaves.length; i++) {
            PreAllocatedLeaf memory leaf = leaves[i];
            _targetContracts[targetContract].preAllocatedLeaves.push(leaf);
            if (leaf.isActive && !_storagePreAllocKeyExists[targetContract][leaf.key]) {
                _storagePreAllocKeyExists[targetContract][leaf.key] = true;
                _storagePreAllocKeys[targetContract].push(leaf.key);
            }
            _storagePreAllocValue[targetContract][leaf.key] = leaf.value;
            _storagePreAllocActive[targetContract][leaf.key] = leaf.isActive;
        }

        for (uint256 i = 0; i < userStorageSlots.length; i++) {
            UserStorageSlot memory slot = userStorageSlots[i];
            _targetContracts[targetContract].userStorageSlots.push(slot);
            if (!_storageUserSlotExists[targetContract][slot.slotOffset]) {
                _storageUserSlotExists[targetContract][slot.slotOffset] = true;
                _storageUserSlots[targetContract].push(slot.slotOffset);
            }
        }

        emit TargetContractAllowed(targetContract, true);
    }

    function registerFunction(
        address targetContract,
        bytes32 functionSignature,
        uint128[] memory preprocessedPart1,
        uint256[] memory preprocessedPart2,
        bytes32 instancesHash
    ) external onlyManagerOrOwner {
        require(targetContract != address(0), "Invalid target contract");
        require(functionSignature != bytes32(0), "Invalid function signature");
        require(_isAllowedTargetContract[targetContract], "Target contract not allowed");

        bytes32 preprocessHash = keccak256(abi.encode(preprocessedPart1, preprocessedPart2));

        FunctionCfg storage cfg = _functionCfg[functionSignature];
        if (cfg.exists) {
            require(cfg.instancesHash == instancesHash, "Function config conflict");
            require(cfg.preprocessHash == preprocessHash, "Function config conflict");
        } else {
            cfg.exists = true;
            cfg.instancesHash = instancesHash;
            cfg.preprocessHash = preprocessHash;
        }

        bool replaced = false;
        RegisteredFunction[] storage fns = _targetContracts[targetContract].registeredFunctions;
        for (uint256 i = 0; i < fns.length; i++) {
            if (fns[i].functionSignature == functionSignature) {
                fns[i] = RegisteredFunction({
                    functionSignature: functionSignature,
                    instancesHash: instancesHash,
                    preprocessedPart1: preprocessedPart1,
                    preprocessedPart2: preprocessedPart2
                });
                replaced = true;
                break;
            }
        }

        if (!replaced) {
            fns.push(
                RegisteredFunction({
                    functionSignature: functionSignature,
                    instancesHash: instancesHash,
                    preprocessedPart1: preprocessedPart1,
                    preprocessedPart2: preprocessedPart2
                })
            );
        }

        if (!_functionStorageExists[functionSignature][targetContract]) {
            _functionStorageExists[functionSignature][targetContract] = true;
            _functionStorages[functionSignature].push(targetContract);
        }

        if (!_storageFunctionExists[targetContract][functionSignature]) {
            _storageFunctionExists[targetContract][functionSignature] = true;
            _storageFunctions[targetContract].push(functionSignature);
        }

        emit FunctionRegistered(functionSignature, targetContract);
    }

    function unregisterFunction(address targetContract, bytes32 functionSignature) external onlyManagerOrOwner {
        require(targetContract != address(0), "Invalid target contract");
        require(functionSignature != bytes32(0), "Invalid function signature");

        RegisteredFunction[] storage fns = _targetContracts[targetContract].registeredFunctions;
        for (uint256 i = 0; i < fns.length; i++) {
            if (fns[i].functionSignature == functionSignature) {
                fns[i] = fns[fns.length - 1];
                fns.pop();
                break;
            }
        }

        _removeFunctionStorageRelation(functionSignature, targetContract);

        if (_storageFunctionExists[targetContract][functionSignature]) {
            _storageFunctionExists[targetContract][functionSignature] = false;
            bytes32[] storage byStorage = _storageFunctions[targetContract];
            for (uint256 i = 0; i < byStorage.length; i++) {
                if (byStorage[i] == functionSignature) {
                    byStorage[i] = byStorage[byStorage.length - 1];
                    byStorage.pop();
                    break;
                }
            }
        }

        emit FunctionUnregistered(functionSignature, targetContract);
    }

    function updateChannelUserDeposits(bytes32 channelId, address participant, uint8 slotIndex, uint256 amount)
        external
        onlyManagerOrOwner
    {
        Channel storage c = _requireChannel(channelId);
        require(c.isParticipant[participant], "Participant not in channel");
        require(c.appStorageAddrs.length > 0, "No app storage");

        address appStorageAddr = c.appStorageAddrs[slotIndex % c.appStorageAddrs.length];
        require(c.hasUserStorageKey[participant][appStorageAddr], "User storage key missing");
        uint256 storageKey = c.userStorageKey[participant][appStorageAddr];

        c.validatedStorageValue[appStorageAddr][storageKey] += amount;
        c.hasValidatedStorageValue[appStorageAddr][storageKey] = true;
    }

    function setChannelL2MptKeys(bytes32 channelId, address participant, uint256[] calldata mptKeys)
        external
        onlyManagerOrOwner
    {
        Channel storage c = _requireChannel(channelId);
        require(c.isParticipant[participant], "Participant not in channel");
        require(mptKeys.length == c.appStorageAddrs.length, "MPT keys count mismatch");

        for (uint256 i = 0; i < mptKeys.length; i++) {
            _setChannelUserStorageKey(c, participant, c.appStorageAddrs[i], mptKeys[i]);
        }
    }

    function setChannelUserStorageKey(bytes32 channelId, address participant, address appStorageAddr, uint256 key)
        external
        onlyManagerOrOwner
    {
        Channel storage c = _requireChannel(channelId);
        require(c.isParticipant[participant], "Participant not in channel");
        _setChannelUserStorageKey(c, participant, appStorageAddr, key);
    }

    function setChannelValidatedStorageValue(bytes32 channelId, address appStorageAddr, uint256 storageKey, uint256 value)
        external
        onlyManagerOrOwner
    {
        Channel storage c = _requireChannel(channelId);
        require(c.hasAppStorageAddr[appStorageAddr], "Invalid app storage");
        require(c.hasStorageKeyOwner[appStorageAddr][storageKey], "Storage key not found");

        c.validatedStorageValue[appStorageAddr][storageKey] = value;
        c.hasValidatedStorageValue[appStorageAddr][storageKey] = true;
    }

    function increaseChannelValidatedStorageValue(
        bytes32 channelId,
        address appStorageAddr,
        uint256 storageKey,
        uint256 amount
    ) external onlyManagerOrOwner {
        Channel storage c = _requireChannel(channelId);
        require(c.hasAppStorageAddr[appStorageAddr], "Invalid app storage");
        require(c.hasStorageKeyOwner[appStorageAddr][storageKey], "Storage key not found");

        c.validatedStorageValue[appStorageAddr][storageKey] += amount;
        c.hasValidatedStorageValue[appStorageAddr][storageKey] = true;
    }

    function setChannelValidatedUserStorage(
        bytes32 channelId,
        address[] memory participants,
        uint256[][] memory slotValues
    ) external onlyManagerOrOwner {
        Channel storage c = _requireChannel(channelId);
        require(participants.length == slotValues.length, "Input length mismatch");

        for (uint256 i = 0; i < participants.length; i++) {
            address user = participants[i];
            require(c.isParticipant[user], "Participant not in channel");
            require(slotValues[i].length == c.appStorageAddrs.length, "Slot values count mismatch");

            for (uint256 j = 0; j < c.appStorageAddrs.length; j++) {
                address appStorageAddr = c.appStorageAddrs[j];
                require(c.hasUserStorageKey[user][appStorageAddr], "User storage key missing");
                uint256 key = c.userStorageKey[user][appStorageAddr];
                c.validatedStorageValue[appStorageAddr][key] = slotValues[i][j];
                c.hasValidatedStorageValue[appStorageAddr][key] = true;
            }
        }
    }

    function clearValidatedUserStorage(bytes32 channelId, address participant, address targetContract)
        external
        onlyManagerOrOwner
    {
        Channel storage c = _requireChannel(channelId);
        require(c.isParticipant[participant], "Participant not in channel");

        if (targetContract != address(0)) {
            if (c.hasUserStorageKey[participant][targetContract]) {
                uint256 key = c.userStorageKey[participant][targetContract];
                c.validatedStorageValue[targetContract][key] = 0;
                c.hasValidatedStorageValue[targetContract][key] = true;
            }
            return;
        }

        for (uint256 i = 0; i < c.appStorageAddrs.length; i++) {
            address appStorageAddr = c.appStorageAddrs[i];
            if (c.hasUserStorageKey[participant][appStorageAddr]) {
                uint256 key = c.userStorageKey[participant][appStorageAddr];
                c.validatedStorageValue[appStorageAddr][key] = 0;
                c.hasValidatedStorageValue[appStorageAddr][key] = true;
            }
        }
    }

    function setChannelInitialStateRoot(bytes32 channelId, bytes32 stateRoot) external onlyManagerOrOwner {
        Channel storage c = _requireChannel(channelId);
        c.initialStateRoot = stateRoot;
        c.finalStateRoot = stateRoot;

        for (uint256 i = 0; i < c.appStorageAddrs.length; i++) {
            address appStorageAddr = c.appStorageAddrs[i];
            _setVerifiedStateRoot(channelId, appStorageAddr, 0, stateRoot);
            _setProposedStateRoot(channelId, 0, appStorageAddr, 0, stateRoot);
        }
    }

    function setChannelFinalStateRoot(bytes32 channelId, bytes32 stateRoot) external onlyManagerOrOwner {
        Channel storage c = _requireChannel(channelId);
        uint16 nextIndex = _nextStateIndex(channelId);

        for (uint256 i = 0; i < c.appStorageAddrs.length; i++) {
            address appStorageAddr = c.appStorageAddrs[i];
            _setVerifiedStateRoot(channelId, appStorageAddr, nextIndex, stateRoot);
            _setProposedStateRoot(channelId, 0, appStorageAddr, nextIndex, stateRoot);
        }

        if (nextIndex == 0) {
            c.initialStateRoot = stateRoot;
        }
        c.finalStateRoot = stateRoot;
    }

    function updateSingleStateLeaf(
        bytes32 channelId,
        address appStorageAddr,
        uint256 userChannelStorageKey,
        uint256 updatedStorageValue,
        bytes32 updatedRoot,
        uint256[16] calldata,
        uint256[5] calldata
    ) external onlyManagerOrOwner returns (bool) {
        Channel storage c = _requireChannel(channelId);
        require(c.hasAppStorageAddr[appStorageAddr], "Invalid app storage");
        require(c.hasStorageKeyOwner[appStorageAddr][userChannelStorageKey], "Storage key not found");

        c.validatedStorageValue[appStorageAddr][userChannelStorageKey] = updatedStorageValue;
        c.hasValidatedStorageValue[appStorageAddr][userChannelStorageKey] = true;

        uint16 nextIndex = _nextStateIndex(channelId);
        for (uint256 i = 0; i < c.appStorageAddrs.length; i++) {
            address storageAddr = c.appStorageAddrs[i];
            bytes32 root = storageAddr == appStorageAddr
                ? updatedRoot
                : _deriveSiblingRoot(channelId, storageAddr, nextIndex, updatedRoot);

            _setVerifiedStateRoot(channelId, storageAddr, nextIndex, root);
            _setProposedStateRoot(channelId, 0, storageAddr, nextIndex, root);
        }

        if (nextIndex == 0) {
            c.initialStateRoot = updatedRoot;
        }
        c.finalStateRoot = updatedRoot;

        emit SingleLeafUpdated(channelId, appStorageAddr, nextIndex);
        return true;
    }

    function verifyProposedStateRoots(
        bytes32 channelId,
        uint8 forkId,
        uint16 proposedStateIndex,
        address[] calldata appStorageAddrs,
        uint256[][] calldata storageKeys,
        uint256[][] calldata updatedStorageValues,
        bytes32[] calldata updatedRoots,
        uint256[42] calldata,
        uint256[4] calldata,
        uint256[] calldata publicInputTokamak
    ) external onlyManagerOrOwner returns (bool) {
        Channel storage c = _requireChannel(channelId);

        require(publicInputTokamak.length == nTokamakPublicInputs, "Invalid tokamak public input length");
        require(appStorageAddrs.length == c.appStorageAddrs.length, "App storage count mismatch");
        require(storageKeys.length == appStorageAddrs.length, "Storage keys count mismatch");
        require(updatedStorageValues.length == appStorageAddrs.length, "Storage values count mismatch");
        require(updatedRoots.length == appStorageAddrs.length, "Roots count mismatch");

        bool[] memory seen = new bool[](c.appStorageAddrs.length);
        uint256 expectedLeaves = 1 << nMerkleTreeLevels;

        for (uint256 i = 0; i < appStorageAddrs.length; i++) {
            address appStorageAddr = appStorageAddrs[i];
            uint256 channelStorageIdx = type(uint256).max;
            for (uint256 j = 0; j < c.appStorageAddrs.length; j++) {
                if (c.appStorageAddrs[j] == appStorageAddr) {
                    channelStorageIdx = j;
                    break;
                }
            }
            require(channelStorageIdx != type(uint256).max, "Invalid app storage");
            require(!seen[channelStorageIdx], "Duplicate app storage");
            seen[channelStorageIdx] = true;

            require(storageKeys[i].length == expectedLeaves, "Invalid storage key vector size");
            require(updatedStorageValues[i].length == expectedLeaves, "Invalid storage value vector size");

            for (uint256 j = 0; j < storageKeys[i].length; j++) {
                uint256 key = storageKeys[i][j];
                if (c.hasStorageKeyOwner[appStorageAddr][key]) {
                    c.validatedStorageValue[appStorageAddr][key] = updatedStorageValues[i][j];
                    c.hasValidatedStorageValue[appStorageAddr][key] = true;
                }
            }

            _setProposedStateRoot(channelId, forkId, appStorageAddr, proposedStateIndex, updatedRoots[i]);
        }

        for (uint256 i = 0; i < seen.length; i++) {
            require(seen[i], "Missing app storage");
        }

        emit ProposedStateRootsVerified(channelId, forkId, proposedStateIndex);
        return true;
    }

    function setChannelState(bytes32 channelId, ChannelState state) external onlyManagerOrOwner {
        Channel storage c = _requireChannel(channelId);
        c.state = state;
    }

    function setChannelCloseTimestamp(bytes32 channelId, uint256 timestamp) external onlyManagerOrOwner {
        Channel storage c = _requireChannel(channelId);
        c.closeTimestamp = uint128(timestamp);
    }

    function setChannelSignatureVerified(bytes32 channelId, bool verified) external onlyManagerOrOwner {
        Channel storage c = _requireChannel(channelId);
        c.sigVerified = verified;
    }

    function setChannelBlockInfosHash(bytes32 channelId, bytes32 blockInfosHash) external onlyManagerOrOwner {
        Channel storage c = _requireChannel(channelId);
        c.blockInfosHash = blockInfosHash;
    }

    function addParticipantOnDeposit(bytes32 channelId, address user) external onlyManagerOrOwner {
        Channel storage c = _requireChannel(channelId);
        require(c.isWhitelisted[user], "User not whitelisted");

        if (c.isParticipant[user]) {
            return;
        }

        c.isParticipant[user] = true;
        c.participants.push(user);
    }

    function cleanupChannel(bytes32 channelId) external onlyManagerOrOwner {
        Channel storage c = _requireChannel(channelId);

        for (uint256 i = 0; i < c.participants.length; i++) {
            address user = c.participants[i];
            c.isParticipant[user] = false;
            c.isWhitelisted[user] = false;

            for (uint256 j = 0; j < c.appStorageAddrs.length; j++) {
                address appStorageAddr = c.appStorageAddrs[j];
                if (c.hasUserStorageKey[user][appStorageAddr]) {
                    uint256 key = c.userStorageKey[user][appStorageAddr];
                    c.hasUserStorageKey[user][appStorageAddr] = false;
                    c.userStorageKey[user][appStorageAddr] = 0;
                    c.hasStorageKeyOwner[appStorageAddr][key] = false;
                    c.storageKeyOwner[appStorageAddr][key] = address(0);
                    c.validatedStorageValue[appStorageAddr][key] = 0;
                    c.hasValidatedStorageValue[appStorageAddr][key] = false;
                }
            }
        }

        _clearChannelStateRelations(channelId);
        delete _channels[channelId];
    }

    function setPreAllocatedLeaf(address targetContract, bytes32 mptKey, uint256 value) external onlyManagerOrOwner {
        require(_isAllowedTargetContract[targetContract], "Target contract not allowed");

        if (!_storagePreAllocKeyExists[targetContract][mptKey]) {
            _storagePreAllocKeyExists[targetContract][mptKey] = true;
            _storagePreAllocKeys[targetContract].push(mptKey);
            _targetContracts[targetContract].preAllocatedLeaves.push(
                PreAllocatedLeaf({value: value, key: mptKey, isActive: true})
            );
        } else {
            PreAllocatedLeaf[] storage leaves = _targetContracts[targetContract].preAllocatedLeaves;
            for (uint256 i = 0; i < leaves.length; i++) {
                if (leaves[i].key == mptKey) {
                    leaves[i].value = value;
                    leaves[i].isActive = true;
                    break;
                }
            }
        }

        _storagePreAllocValue[targetContract][mptKey] = value;
        _storagePreAllocActive[targetContract][mptKey] = true;
    }

    function removePreAllocatedLeaf(address targetContract, bytes32 mptKey) external onlyManagerOrOwner {
        require(_storagePreAllocKeyExists[targetContract][mptKey], "Pre-allocated leaf not found");

        _storagePreAllocKeyExists[targetContract][mptKey] = false;
        _storagePreAllocActive[targetContract][mptKey] = false;
        _storagePreAllocValue[targetContract][mptKey] = 0;

        bytes32[] storage keys = _storagePreAllocKeys[targetContract];
        for (uint256 i = 0; i < keys.length; i++) {
            if (keys[i] == mptKey) {
                keys[i] = keys[keys.length - 1];
                keys.pop();
                break;
            }
        }

        PreAllocatedLeaf[] storage leaves = _targetContracts[targetContract].preAllocatedLeaves;
        for (uint256 i = 0; i < leaves.length; i++) {
            if (leaves[i].key == mptKey) {
                leaves[i] = leaves[leaves.length - 1];
                leaves.pop();
                break;
            }
        }
    }

    function depositManager() external view returns (address) {
        return _depositManager;
    }

    function withdrawManager() external view returns (address) {
        return _withdrawManager;
    }

    function getChannelState(bytes32 channelId) external view returns (ChannelState) {
        return _channels[channelId].state;
    }

    function getChannelTargetContract(bytes32 channelId) external view returns (address) {
        return _channels[channelId].targetContract;
    }

    function getChannelLeader(bytes32 channelId) external view returns (address) {
        return _channels[channelId].leader;
    }

    function getChannelParticipants(bytes32 channelId) external view returns (address[] memory) {
        return _channels[channelId].participants;
    }

    function getChannelUsers(bytes32 channelId) external view returns (address[] memory) {
        return _channels[channelId].participants;
    }

    function isChannelWhitelisted(bytes32 channelId, address addr) external view returns (bool) {
        return _channels[channelId].isWhitelisted[addr];
    }

    function getChannelTreeSize(bytes32 channelId) external view returns (uint256) {
        return _channels[channelId].requiredTreeSize;
    }

    function getChannelMerkleTreeLevels(bytes32 channelId) public view returns (uint8) {
        Channel storage c = _channels[channelId];
        if (!c.exists || c.requiredTreeSize == 0) {
            return nMerkleTreeLevels;
        }

        uint256 treeSize = c.requiredTreeSize;
        uint8 levels;
        while (treeSize > 1) {
            levels++;
            treeSize >>= 1;
        }
        return levels;
    }

    function getL2MptKey(bytes32 channelId, address participant, uint8 slotIndex) external view returns (uint256) {
        Channel storage c = _channels[channelId];
        if (c.appStorageAddrs.length == 0) {
            return 0;
        }
        address appStorageAddr = c.appStorageAddrs[slotIndex % c.appStorageAddrs.length];
        return c.userStorageKey[participant][appStorageAddr];
    }

    function getChannelPublicKey(bytes32 channelId) external view returns (uint256 pkx, uint256 pky) {
        Channel storage c = _channels[channelId];
        return (c.pkx, c.pky);
    }

    function isChannelPublicKeySet(bytes32 channelId) external view returns (bool) {
        Channel storage c = _channels[channelId];
        return c.pkx != 0 && c.pky != 0;
    }

    function getChannelSignerAddr(bytes32 channelId) external view returns (address) {
        return _channels[channelId].signerAddr;
    }

    function getChannelFinalStateRoot(bytes32 channelId) external view returns (bytes32) {
        return _channels[channelId].finalStateRoot;
    }

    function getChannelInitialStateRoot(bytes32 channelId) external view returns (bytes32) {
        return _channels[channelId].initialStateRoot;
    }

    function isAllowedTargetContract(address targetContract) external view returns (bool) {
        return _isAllowedTargetContract[targetContract];
    }

    function getTargetContractData(address targetContract) external view returns (TargetContract memory) {
        require(_isAllowedTargetContract[targetContract], "Target contract not allowed");
        return _targetContracts[targetContract];
    }

    function getChannelInfo(bytes32 channelId)
        external
        view
        returns (address targetContract, ChannelState state, uint256 participantCount, bytes32 initialRoot)
    {
        Channel storage c = _channels[channelId];
        return (c.targetContract, c.state, c.participants.length, c.initialStateRoot);
    }

    function getValidatedUserSlotValue(bytes32 channelId, address participant, uint8 slotIndex)
        external
        view
        returns (uint256)
    {
        Channel storage c = _channels[channelId];
        if (c.appStorageAddrs.length == 0) {
            return 0;
        }

        address appStorageAddr = c.appStorageAddrs[slotIndex % c.appStorageAddrs.length];
        if (!c.hasUserStorageKey[participant][appStorageAddr]) {
            return 0;
        }

        uint256 key = c.userStorageKey[participant][appStorageAddr];
        return c.validatedStorageValue[appStorageAddr][key];
    }

    function getValidatedUserTargetContract(bytes32 channelId, address) external view returns (address) {
        Channel storage c = _channels[channelId];
        if (c.appStorageAddrs.length == 0) {
            return address(0);
        }
        return c.appStorageAddrs[0];
    }

    function hasUserWithdrawn(bytes32 channelId, address participant, address targetContract)
        external
        view
        returns (bool)
    {
        Channel storage c = _channels[channelId];
        if (!c.hasUserStorageKey[participant][targetContract]) {
            return true;
        }

        uint256 key = c.userStorageKey[participant][targetContract];
        return c.validatedStorageValue[targetContract][key] == 0;
    }

    function getBalanceSlotIndex(address targetContract) public view returns (uint8) {
        UserStorageSlot[] storage slots = _targetContracts[targetContract].userStorageSlots;
        for (uint8 i = 0; i < slots.length; i++) {
            if (!slots[i].isLoadedOnChain) {
                return i;
            }
        }
        return 0;
    }

    function getBalanceSlotOffset(address targetContract) external view returns (uint8) {
        UserStorageSlot[] storage slots = _targetContracts[targetContract].userStorageSlots;
        for (uint8 i = 0; i < slots.length; i++) {
            if (!slots[i].isLoadedOnChain) {
                return slots[i].slotOffset;
            }
        }
        return 0;
    }

    function isSignatureVerified(bytes32 channelId) external view returns (bool) {
        return _channels[channelId].sigVerified;
    }

    function getChannelBlockInfosHash(bytes32 channelId) external view returns (bytes32) {
        return _channels[channelId].blockInfosHash;
    }

    function isFrostSignatureEnabled(bytes32 channelId) external view returns (bool) {
        return _channels[channelId].frostSignatureEnabled;
    }

    function isChannelTimedOut(bytes32 channelId) external view returns (bool) {
        Channel storage c = _requireChannelView(channelId);
        return block.timestamp > uint256(c.openTimestamp) + CHANNEL_TIMEOUT;
    }

    function isMarkedChannelLeader(address addr, bytes32 channelId) external view returns (bool) {
        return _channels[channelId].leader == addr;
    }

    function getFcnStorages(bytes32 functionSignature) external view returns (address[] memory) {
        return _functionStorages[functionSignature];
    }

    function getPreAllocKeys(address storageAddr) external view returns (bytes32[] memory) {
        return _storagePreAllocKeys[storageAddr];
    }

    function getUserSlots(address storageAddr) external view returns (uint8[] memory) {
        return _storageUserSlots[storageAddr];
    }

    function getFcnCfg(bytes32 functionSignature) public view returns (bytes32 instancesHash, bytes32 preprocessHash) {
        FunctionCfg storage cfg = _functionCfg[functionSignature];
        require(cfg.exists, "Function config not found");
        return (cfg.instancesHash, cfg.preprocessHash);
    }

    function getAppFcnStorages(bytes32 channelId, bytes32 functionSignature) public view returns (address[] memory) {
        Channel storage c = _channels[channelId];
        if (!c.hasAppFunctionSignature[functionSignature]) {
            return new address[](0);
        }

        address[] storage storages = _functionStorages[functionSignature];
        uint256 count;
        for (uint256 i = 0; i < storages.length; i++) {
            if (c.hasAppStorageAddr[storages[i]]) {
                count++;
            }
        }

        address[] memory result = new address[](count);
        uint256 idx;
        for (uint256 i = 0; i < storages.length; i++) {
            if (c.hasAppStorageAddr[storages[i]]) {
                result[idx] = storages[i];
                idx++;
            }
        }
        return result;
    }

    function getAppPreAllocKeys(bytes32 channelId, address appStorageAddr) public view returns (bytes32[] memory) {
        Channel storage c = _channels[channelId];
        if (!c.hasAppStorageAddr[appStorageAddr]) {
            return new bytes32[](0);
        }
        return _storagePreAllocKeys[appStorageAddr];
    }

    function getAppUserSlots(bytes32 channelId, address appStorageAddr) public view returns (uint8[] memory) {
        Channel storage c = _channels[channelId];
        if (!c.hasAppStorageAddr[appStorageAddr]) {
            return new uint8[](0);
        }
        return _storageUserSlots[appStorageAddr];
    }

    function getAppFcnCfg(bytes32 channelId, bytes32 functionSignature)
        public
        view
        returns (bytes32 instancesHash, bytes32 preprocessHash)
    {
        Channel storage c = _channels[channelId];
        require(c.hasAppFunctionSignature[functionSignature], "Function not in channel");
        return getFcnCfg(functionSignature);
    }

    function getAppUserStorageKey(bytes32 channelId, address user, address appStorageAddr)
        public
        view
        returns (uint256)
    {
        Channel storage c = _channels[channelId];
        require(c.hasAppStorageAddr[appStorageAddr], "Invalid app storage");
        require(c.isParticipant[user], "User not in channel");
        require(c.hasUserStorageKey[user][appStorageAddr], "User storage key not found");
        return c.userStorageKey[user][appStorageAddr];
    }

    function getAppValidatedStorageValue(bytes32 channelId, address appStorageAddr, uint256 appUserStorageKey)
        public
        view
        returns (uint256)
    {
        Channel storage c = _channels[channelId];
        require(c.hasAppStorageAddr[appStorageAddr], "Invalid app storage");
        require(c.hasStorageKeyOwner[appStorageAddr][appUserStorageKey], "Storage key not found");
        return c.validatedStorageValue[appStorageAddr][appUserStorageKey];
    }

    function getAppPreAllocValue(bytes32 channelId, address appStorageAddr, bytes32 preAllocKey)
        public
        view
        returns (uint256)
    {
        Channel storage c = _channels[channelId];
        require(c.hasAppStorageAddr[appStorageAddr], "Invalid app storage");
        require(_storagePreAllocActive[appStorageAddr][preAllocKey], "Pre-allocated leaf not found");
        return _storagePreAllocValue[appStorageAddr][preAllocKey];
    }

    function getVerifiedStateRoot(bytes32 channelId, address appStorageAddr, uint16 stateIndex)
        public
        view
        returns (bytes32)
    {
        Channel storage c = _channels[channelId];
        require(c.hasAppStorageAddr[appStorageAddr], "Invalid app storage");
        return _verifiedStateRoot[channelId][appStorageAddr][stateIndex];
    }

    function getProposedStateRoot(bytes32 channelId, uint8 forkId, address appStorageAddr, uint16 stateIndex)
        public
        view
        returns (bytes32)
    {
        Channel storage c = _channels[channelId];
        require(c.hasAppStorageAddr[appStorageAddr], "Invalid app storage");
        return _proposedStateRoot[channelId][forkId][appStorageAddr][stateIndex];
    }

    function getProposedStateFork(bytes32 channelId, uint8 forkId)
        public
        view
        returns (uint16[] memory stateIndices, bytes32[] memory roots)
    {
        Channel storage c = _channels[channelId];
        uint16[] storage storedIndices = _proposedStateIndices[channelId][forkId];

        stateIndices = new uint16[](storedIndices.length);
        roots = new bytes32[](storedIndices.length);

        address primaryStorage = c.appStorageAddrs.length == 0 ? c.targetContract : c.appStorageAddrs[0];

        for (uint256 i = 0; i < storedIndices.length; i++) {
            uint16 t = storedIndices[i];
            stateIndices[i] = t;
            roots[i] = _proposedStateRoot[channelId][forkId][primaryStorage][t];
        }
    }

    function getChannelFcnStorages(bytes32 channelId, bytes32 functionSignature)
        external
        view
        returns (address[] memory)
    {
        return getAppFcnStorages(channelId, functionSignature);
    }

    function getChannelPreAllocKeys(bytes32 channelId, address appStorageAddr) external view returns (bytes32[] memory) {
        return getAppPreAllocKeys(channelId, appStorageAddr);
    }

    function getChannelUserSlots(bytes32 channelId, address appStorageAddr) external view returns (uint8[] memory) {
        return getAppUserSlots(channelId, appStorageAddr);
    }

    function getChannelFcnCfg(bytes32 channelId, bytes32 functionSignature)
        external
        view
        returns (bytes32 instancesHash, bytes32 preprocessHash)
    {
        return getAppFcnCfg(channelId, functionSignature);
    }

    function getChannelUserStorageKey(bytes32 channelId, address user, address appStorageAddr)
        external
        view
        returns (uint256)
    {
        return getAppUserStorageKey(channelId, user, appStorageAddr);
    }

    function getChannelValidatedStorageValue(bytes32 channelId, address appStorageAddr, uint256 appUserStorageKey)
        external
        view
        returns (uint256)
    {
        return getAppValidatedStorageValue(channelId, appStorageAddr, appUserStorageKey);
    }

    function getChannelPreAllocValue(bytes32 channelId, address appStorageAddr, bytes32 preAllocKey)
        external
        view
        returns (uint256)
    {
        return getAppPreAllocValue(channelId, appStorageAddr, preAllocKey);
    }

    function getChannelVerifiedStateRoot(bytes32 channelId, address appStorageAddr, uint16 stateIndex)
        external
        view
        returns (bytes32)
    {
        return getVerifiedStateRoot(channelId, appStorageAddr, stateIndex);
    }

    function getChannelProposedStateRoot(bytes32 channelId, uint8 forkId, address appStorageAddr, uint16 stateIndex)
        external
        view
        returns (bytes32)
    {
        return getProposedStateRoot(channelId, forkId, appStorageAddr, stateIndex);
    }

    function getChannelProposedStateFork(bytes32 channelId, uint8 forkId)
        external
        view
        returns (uint16[] memory stateIndices, bytes32[] memory roots)
    {
        return getProposedStateFork(channelId, forkId);
    }

    function getPreAllocatedLeaf(address targetContract, bytes32 mptKey)
        external
        view
        returns (uint256 value, bool exists)
    {
        return (_storagePreAllocValue[targetContract][mptKey], _storagePreAllocActive[targetContract][mptKey]);
    }

    function getPreAllocatedKeys(address targetContract) external view returns (bytes32[] memory keys) {
        return _storagePreAllocKeys[targetContract];
    }

    function getPreAllocatedLeavesCount(address targetContract) public view returns (uint256 count) {
        return _storagePreAllocKeys[targetContract].length;
    }

    function getChannelPreAllocatedLeavesCount(bytes32 channelId) external view returns (uint256 count) {
        Channel storage c = _channels[channelId];
        return _storagePreAllocKeys[c.targetContract].length;
    }

    function getImplementation() external view returns (address implementation) {
        bytes32 slot = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        assembly {
            implementation := sload(slot)
        }
    }

    function generateChannelId(address leader, bytes32 salt) external pure returns (bytes32 channelId) {
        return keccak256(abi.encodePacked(leader, salt));
    }

    function _requireChannel(bytes32 channelId) internal view returns (Channel storage c) {
        c = _channels[channelId];
        require(c.exists, "Channel does not exist");
    }

    function _requireChannelView(bytes32 channelId) internal view returns (Channel storage c) {
        c = _channels[channelId];
        require(c.exists, "Channel does not exist");
    }

    function _addWhitelistedUser(Channel storage c, address user) internal {
        if (user == address(0) || c.isWhitelisted[user]) {
            return;
        }
        c.isWhitelisted[user] = true;
        if (!c.isParticipant[user]) {
            c.isParticipant[user] = true;
            c.participants.push(user);
        }
    }

    function _setChannelUserStorageKey(Channel storage c, address participant, address appStorageAddr, uint256 key)
        internal
    {
        require(c.hasAppStorageAddr[appStorageAddr], "Invalid app storage");

        for (uint256 storageIdx = 0; storageIdx < c.appStorageAddrs.length; storageIdx++) {
            bytes32[] storage preKeys = _storagePreAllocKeys[c.appStorageAddrs[storageIdx]];
            for (uint256 i = 0; i < preKeys.length; i++) {
                require(key != uint256(preKeys[i]), "Storage key collides with pre-alloc key");
            }
        }

        if (c.hasUserStorageKey[participant][appStorageAddr]) {
            uint256 prevKey = c.userStorageKey[participant][appStorageAddr];
            if (prevKey == key) {
                return;
            }
            c.hasStorageKeyOwner[appStorageAddr][prevKey] = false;
            c.storageKeyOwner[appStorageAddr][prevKey] = address(0);
        }

        if (c.hasStorageKeyOwner[appStorageAddr][key]) {
            require(c.storageKeyOwner[appStorageAddr][key] == participant, "Duplicate storage key");
        }

        c.hasUserStorageKey[participant][appStorageAddr] = true;
        c.userStorageKey[participant][appStorageAddr] = key;
        c.hasStorageKeyOwner[appStorageAddr][key] = true;
        c.storageKeyOwner[appStorageAddr][key] = participant;

        if (!c.hasValidatedStorageValue[appStorageAddr][key]) {
            c.hasValidatedStorageValue[appStorageAddr][key] = true;
            c.validatedStorageValue[appStorageAddr][key] = 0;
        }
    }

    function _clearTargetContract(address targetContract) internal {
        RegisteredFunction[] storage fns = _targetContracts[targetContract].registeredFunctions;
        while (fns.length > 0) {
            bytes32 functionSignature = fns[fns.length - 1].functionSignature;
            fns.pop();
            _removeFunctionStorageRelation(functionSignature, targetContract);
            if (_storageFunctionExists[targetContract][functionSignature]) {
                _storageFunctionExists[targetContract][functionSignature] = false;
            }
        }
        delete _storageFunctions[targetContract];

        bytes32[] storage keys = _storagePreAllocKeys[targetContract];
        for (uint256 i = 0; i < keys.length; i++) {
            bytes32 key = keys[i];
            _storagePreAllocKeyExists[targetContract][key] = false;
            _storagePreAllocValue[targetContract][key] = 0;
            _storagePreAllocActive[targetContract][key] = false;
        }
        delete _storagePreAllocKeys[targetContract];

        uint8[] storage slots = _storageUserSlots[targetContract];
        for (uint256 i = 0; i < slots.length; i++) {
            _storageUserSlotExists[targetContract][slots[i]] = false;
        }
        delete _storageUserSlots[targetContract];

        delete _targetContracts[targetContract];
    }

    function _removeFunctionStorageRelation(bytes32 functionSignature, address targetContract) internal {
        if (!_functionStorageExists[functionSignature][targetContract]) {
            return;
        }

        _functionStorageExists[functionSignature][targetContract] = false;
        address[] storage storages = _functionStorages[functionSignature];
        for (uint256 i = 0; i < storages.length; i++) {
            if (storages[i] == targetContract) {
                storages[i] = storages[storages.length - 1];
                storages.pop();
                break;
            }
        }

        if (storages.length == 0) {
            delete _functionCfg[functionSignature];
        }
    }

    function _setVerifiedStateRoot(bytes32 channelId, address appStorageAddr, uint16 stateIndex, bytes32 root)
        internal
    {
        if (!_verifiedStateIndexExists[channelId][stateIndex]) {
            _verifiedStateIndexExists[channelId][stateIndex] = true;
            _verifiedStateIndices[channelId].push(stateIndex);
        }
        _verifiedStateRoot[channelId][appStorageAddr][stateIndex] = root;
    }

    function _setProposedStateRoot(bytes32 channelId, uint8 forkId, address appStorageAddr, uint16 stateIndex, bytes32 root)
        internal
    {
        if (!_proposedForkExists[channelId][forkId]) {
            _proposedForkExists[channelId][forkId] = true;
            _proposedForkIds[channelId].push(forkId);
        }

        if (!_proposedStateIndexExists[channelId][forkId][stateIndex]) {
            _proposedStateIndexExists[channelId][forkId][stateIndex] = true;
            _proposedStateIndices[channelId][forkId].push(stateIndex);
        }

        _proposedStateRoot[channelId][forkId][appStorageAddr][stateIndex] = root;
    }

    function _nextStateIndex(bytes32 channelId) internal view returns (uint16) {
        uint16[] storage indices = _verifiedStateIndices[channelId];
        if (indices.length == 0) {
            return 0;
        }
        return indices[indices.length - 1] + 1;
    }

    function _deriveSiblingRoot(bytes32 channelId, address appStorageAddr, uint16 nextIndex, bytes32 seed)
        internal
        view
        returns (bytes32)
    {
        if (nextIndex == 0) {
            return keccak256(abi.encodePacked(channelId, appStorageAddr, nextIndex, seed));
        }

        bytes32 prev = _verifiedStateRoot[channelId][appStorageAddr][nextIndex - 1];
        return keccak256(abi.encodePacked(prev, appStorageAddr, nextIndex, seed));
    }

    function _clearChannelStateRelations(bytes32 channelId) internal {
        Channel storage c = _channels[channelId];

        uint16[] storage verifiedIndices = _verifiedStateIndices[channelId];
        for (uint256 i = 0; i < verifiedIndices.length; i++) {
            uint16 t = verifiedIndices[i];
            _verifiedStateIndexExists[channelId][t] = false;
            for (uint256 j = 0; j < c.appStorageAddrs.length; j++) {
                _verifiedStateRoot[channelId][c.appStorageAddrs[j]][t] = bytes32(0);
            }
        }
        delete _verifiedStateIndices[channelId];

        uint8[] storage forks = _proposedForkIds[channelId];
        for (uint256 i = 0; i < forks.length; i++) {
            uint8 forkId = forks[i];
            _proposedForkExists[channelId][forkId] = false;
            uint16[] storage indices = _proposedStateIndices[channelId][forkId];
            for (uint256 j = 0; j < indices.length; j++) {
                uint16 t = indices[j];
                _proposedStateIndexExists[channelId][forkId][t] = false;
                for (uint256 k = 0; k < c.appStorageAddrs.length; k++) {
                    _proposedStateRoot[channelId][forkId][c.appStorageAddrs[k]][t] = bytes32(0);
                }
            }
            delete _proposedStateIndices[channelId][forkId];
        }
        delete _proposedForkIds[channelId];
    }

    function _deriveAddressFromPubkey(uint256 pkx, uint256 pky) internal pure returns (address) {
        bytes32 h = keccak256(abi.encodePacked(pkx, pky));
        return address(uint160(uint256(h)));
    }

    uint256[43] private __gap;
}

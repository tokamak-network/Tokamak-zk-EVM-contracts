// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

interface IBridgeManagerMinimal {
    function nTokamakPublicInputs() external view returns (uint16);
    function nMerkleTreeLevels() external view returns (uint8);
    function hasFcnCfg(bytes4 fcnSig) external view returns (bool);
    function getFcnStorages(bytes4 fcnSig) external view returns (address[] memory);
    function getPreAllocKeys(address storageAddr) external view returns (bytes32[] memory);
    function getUserSlots(address storageAddr) external view returns (uint8[] memory);
    function getFcnCfg(bytes4 fcnSig) external view returns (bytes32 instancesHash, bytes32 preprocessHash);
}

contract BridgeChannel {
    address public immutable core;
    IBridgeManagerMinimal public immutable bridgeManager;

    uint256 public stateIndex;

    bytes4[] private _appFcnSigs;
    address[] private _appStorageAddrs;
    address[] private _users;

    mapping(bytes4 => bool) private _isAppFcnSig;
    mapping(address => bool) private _isAppStorage;
    mapping(address => bool) private _isUser;

    mapping(bytes4 => address[]) private _appFcnStorages;
    mapping(address => bytes32[]) private _appPreAllocKeys;
    mapping(address => uint8[]) private _appUserSlots;

    mapping(bytes4 => bytes32) private _instancesHashByFcn;
    mapping(bytes4 => bytes32) private _preprocessHashByFcn;

    mapping(address => mapping(address => bytes32)) private _appUserStorageKey;
    mapping(address => mapping(address => bool)) private _hasAppUserStorageKey;

    mapping(address => mapping(bytes32 => address)) private _keyOwnerByStorage;
    mapping(address => mapping(bytes32 => uint256)) private _appValidatedStorageValue;
    mapping(address => mapping(bytes32 => bool)) private _hasAppValidatedStorageValue;

    mapping(address => mapping(bytes32 => uint256)) private _appPreAllocValue;
    mapping(address => mapping(bytes32 => bool)) private _hasAppPreAllocValue;

    mapping(address => mapping(uint256 => bytes32)) private _verifiedStateRoot;

    modifier onlyCore() {
        require(msg.sender == core, "Only core");
        _;
    }

    modifier onlyChannelUser(address user) {
        require(_isUser[user], "User not in channel");
        _;
    }

    constructor(
        address managerAddress,
        bytes4[] memory appFcnSigs,
        address[] memory users,
        address coreAddress
    ) {
        require(managerAddress != address(0), "Invalid manager");
        require(coreAddress != address(0), "Invalid core");
        require(appFcnSigs.length > 0, "No function signatures");
        require(users.length > 0, "No users");

        bridgeManager = IBridgeManagerMinimal(managerAddress);
        core = coreAddress;

        _initializeUsers(users);
        _initializeFunctionProjection(appFcnSigs);
        _initializeStorageProjection();
        _initializeStateRoots();
    }

    function getUsers() external view returns (address[] memory) {
        return _users;
    }

    function isUser(address user) external view returns (bool) {
        return _isUser[user];
    }

    function getAppFcnStorages(bytes4 fcnSig) external view returns (address[] memory) {
        require(_isAppFcnSig[fcnSig], "Function not in channel");
        return _appFcnStorages[fcnSig];
    }

    function getAppPreAllocKeys(address storageAddr) external view returns (bytes32[] memory) {
        _requireAppStorage(storageAddr);
        return _appPreAllocKeys[storageAddr];
    }

    function getAppUserSlots(address storageAddr) external view returns (uint8[] memory) {
        _requireAppStorage(storageAddr);
        return _appUserSlots[storageAddr];
    }

    function getAppFcnCfg(bytes4 fcnSig) external view returns (bytes32 instancesHash, bytes32 preprocessHash) {
        require(_isAppFcnSig[fcnSig], "Function not in channel");
        return (_instancesHashByFcn[fcnSig], _preprocessHashByFcn[fcnSig]);
    }

    function getAppUserStorageKey(address user, address storageAddr)
        external
        view
        onlyChannelUser(user)
        returns (bytes32)
    {
        _requireAppStorage(storageAddr);
        require(_hasAppUserStorageKey[user][storageAddr], "User storage key not set");
        return _appUserStorageKey[user][storageAddr];
    }

    function getAppValidatedStorageValue(address storageAddr, bytes32 appUserStorageKey)
        external
        view
        returns (uint256)
    {
        _requireAppStorage(storageAddr);
        require(_hasAppValidatedStorageValue[storageAddr][appUserStorageKey], "Validated value not set");
        return _appValidatedStorageValue[storageAddr][appUserStorageKey];
    }

    function getAppPreAllocValue(address storageAddr, bytes32 preAllocKey) external view returns (uint256) {
        _requireAppStorage(storageAddr);
        require(_hasAppPreAllocValue[storageAddr][preAllocKey], "Pre-allocated key not found");
        return _appPreAllocValue[storageAddr][preAllocKey];
    }

    function getVerifiedStateRoot(address storageAddr, uint256 stateIdx) external view returns (bytes32) {
        _requireAppStorage(storageAddr);
        require(stateIdx <= stateIndex, "Invalid state index");
        return _verifiedStateRoot[storageAddr][stateIdx];
    }

    function getStorageKeyOwner(address storageAddr, bytes32 appUserStorageKey) external view returns (address) {
        _requireAppStorage(storageAddr);
        return _keyOwnerByStorage[storageAddr][appUserStorageKey];
    }

    function setAppUserStorageKey(address user, address storageAddr, bytes32 appUserStorageKey)
        external
        onlyCore
        onlyChannelUser(user)
    {
        _requireAppStorage(storageAddr);

        address existingOwner = _keyOwnerByStorage[storageAddr][appUserStorageKey];
        require(existingOwner == address(0) || existingOwner == user, "Key owned by another user");

        if (_hasAppUserStorageKey[user][storageAddr]) {
            bytes32 previousKey = _appUserStorageKey[user][storageAddr];
            if (previousKey != appUserStorageKey && _keyOwnerByStorage[storageAddr][previousKey] == user) {
                delete _keyOwnerByStorage[storageAddr][previousKey];
            }
        }

        _appUserStorageKey[user][storageAddr] = appUserStorageKey;
        _hasAppUserStorageKey[user][storageAddr] = true;
        _keyOwnerByStorage[storageAddr][appUserStorageKey] = user;
    }

    function setAppPreAllocValue(address storageAddr, bytes32 preAllocKey, uint256 value) external onlyCore {
        _requireAppStorage(storageAddr);
        require(_hasAppPreAllocValue[storageAddr][preAllocKey], "Pre-allocated key not found");
        _appPreAllocValue[storageAddr][preAllocKey] = value;
    }

    function updateSingleStorage(
        address appStorageAddr,
        bytes32 appUserStorageKey,
        uint256 updatedStorageValue,
        bytes32 updatedRoot,
        uint256[16] calldata proofGroth16,
        uint256[5] calldata publicInputGroth16
    ) external onlyCore returns (bool) {
        _requireAppStorage(appStorageAddr);
        require(_keyOwnerByStorage[appStorageAddr][appUserStorageKey] != address(0), "Unknown app user storage key");
        require(updatedRoot != _verifiedStateRoot[appStorageAddr][stateIndex], "Root must change");

        proofGroth16;
        publicInputGroth16;

        _appValidatedStorageValue[appStorageAddr][appUserStorageKey] = updatedStorageValue;
        _hasAppValidatedStorageValue[appStorageAddr][appUserStorageKey] = true;

        uint256 nextIndex = stateIndex + 1;
        _copyRootsToNextState(nextIndex);
        _verifiedStateRoot[appStorageAddr][nextIndex] = updatedRoot;
        stateIndex = nextIndex;

        return true;
    }

    function updateAllStorages(
        address[] calldata appStorageAddrs,
        bytes32[] calldata appUserStorageKeys,
        uint256[][] calldata updatedStorageValues,
        bytes32[] calldata updatedRoots,
        uint256[42] calldata proofTokamak,
        uint256[4] calldata preprocessTokamak,
        uint256[] calldata publicInputTokamak
    ) external onlyCore returns (bool) {
        require(appStorageAddrs.length == _appStorageAddrs.length, "Storage length mismatch");
        require(appUserStorageKeys.length == appStorageAddrs.length, "Key length mismatch");
        require(updatedStorageValues.length == appStorageAddrs.length, "Value length mismatch");
        require(updatedRoots.length == appStorageAddrs.length, "Root length mismatch");
        require(publicInputTokamak.length == bridgeManager.nTokamakPublicInputs(), "Tokamak public input length mismatch");

        proofTokamak;
        preprocessTokamak;
        publicInputTokamak;

        uint256 nextIndex = stateIndex + 1;
        _copyRootsToNextState(nextIndex);

        bool anyRootChanged = false;

        for (uint256 i = 0; i < appStorageAddrs.length; i++) {
            address storageAddr = appStorageAddrs[i];
            require(storageAddr == _appStorageAddrs[i], "Storage order mismatch");
            require(_keyOwnerByStorage[storageAddr][appUserStorageKeys[i]] != address(0), "Unknown app user storage key");

            if (updatedStorageValues[i].length > 0) {
                _appValidatedStorageValue[storageAddr][appUserStorageKeys[i]] = updatedStorageValues[i][0];
                _hasAppValidatedStorageValue[storageAddr][appUserStorageKeys[i]] = true;
            }

            if (updatedRoots[i] != _verifiedStateRoot[storageAddr][stateIndex]) {
                anyRootChanged = true;
            }
            _verifiedStateRoot[storageAddr][nextIndex] = updatedRoots[i];
        }

        require(anyRootChanged, "No root update");
        stateIndex = nextIndex;

        return true;
    }

    function _initializeUsers(address[] memory users) internal {
        for (uint256 i = 0; i < users.length; i++) {
            address user = users[i];
            require(user != address(0), "Invalid user");
            require(!_isUser[user], "Duplicate user");

            _isUser[user] = true;
            _users.push(user);
        }
    }

    function _initializeFunctionProjection(bytes4[] memory appFcnSigs) internal {
        for (uint256 i = 0; i < appFcnSigs.length; i++) {
            bytes4 fcnSig = appFcnSigs[i];
            require(fcnSig != bytes4(0), "Invalid function signature");
            require(!_isAppFcnSig[fcnSig], "Duplicate function signature");
            require(bridgeManager.hasFcnCfg(fcnSig), "Function config missing");

            _isAppFcnSig[fcnSig] = true;
            _appFcnSigs.push(fcnSig);

            (bytes32 instancesHash, bytes32 preprocessHash) = bridgeManager.getFcnCfg(fcnSig);
            _instancesHashByFcn[fcnSig] = instancesHash;
            _preprocessHashByFcn[fcnSig] = preprocessHash;

            address[] memory storages = bridgeManager.getFcnStorages(fcnSig);
            require(storages.length > 0, "Function storage relation missing");

            for (uint256 j = 0; j < storages.length; j++) {
                address storageAddr = storages[j];
                require(storageAddr != address(0), "Invalid storage address");

                _appFcnStorages[fcnSig].push(storageAddr);
                if (!_isAppStorage[storageAddr]) {
                    _isAppStorage[storageAddr] = true;
                    _appStorageAddrs.push(storageAddr);
                }
            }
        }
    }

    function _initializeStorageProjection() internal {
        for (uint256 i = 0; i < _appStorageAddrs.length; i++) {
            address storageAddr = _appStorageAddrs[i];

            bytes32[] memory preAllocKeys = bridgeManager.getPreAllocKeys(storageAddr);
            for (uint256 j = 0; j < preAllocKeys.length; j++) {
                bytes32 key = preAllocKeys[j];
                _appPreAllocKeys[storageAddr].push(key);
                _appPreAllocValue[storageAddr][key] = 0;
                _hasAppPreAllocValue[storageAddr][key] = true;
            }

            uint8[] memory userSlots = bridgeManager.getUserSlots(storageAddr);
            for (uint256 j = 0; j < userSlots.length; j++) {
                _appUserSlots[storageAddr].push(userSlots[j]);
            }
        }
    }

    function _initializeStateRoots() internal {
        stateIndex = 0;
        for (uint256 i = 0; i < _appStorageAddrs.length; i++) {
            _verifiedStateRoot[_appStorageAddrs[i]][0] = bytes32(0);
        }
    }

    function _copyRootsToNextState(uint256 nextIndex) internal {
        for (uint256 i = 0; i < _appStorageAddrs.length; i++) {
            address storageAddr = _appStorageAddrs[i];
            _verifiedStateRoot[storageAddr][nextIndex] = _verifiedStateRoot[storageAddr][stateIndex];
        }
    }

    function _requireAppStorage(address storageAddr) internal view {
        require(_isAppStorage[storageAddr], "Storage not in channel");
    }
}

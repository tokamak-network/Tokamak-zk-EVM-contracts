// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import "./BridgeAccessControl.sol";
import "./BridgeChannel.sol";
import "./BridgeManager.sol";

contract BridgeCore is BridgeOwnable {
    BridgeManager public immutable bridgeManager;

    mapping(bytes32 => address) private _channelAddress;
    bytes32[] private _channelIds;

    event ChannelCreated(bytes32 indexed channelId, address channelAddress);

    constructor(address managerAddress, address initialOwner) BridgeOwnable(initialOwner) {
        require(managerAddress != address(0), "Invalid manager");
        bridgeManager = BridgeManager(managerAddress);
    }

    function createChannel(bytes32 channelId, bytes4[] calldata appFcnSigs, address[] calldata users)
        external
        onlyOwner
        returns (address channelAddress)
    {
        require(channelId != bytes32(0), "Invalid channel id");
        require(_channelAddress[channelId] == address(0), "Channel already exists");

        BridgeChannel channel = new BridgeChannel(address(bridgeManager), appFcnSigs, users, address(this));
        channelAddress = address(channel);

        _channelAddress[channelId] = channelAddress;
        _channelIds.push(channelId);

        emit ChannelCreated(channelId, channelAddress);
    }

    function getChannelAddress(bytes32 channelId) external view returns (address) {
        return _requireChannel(channelId);
    }

    function getChannelIds() external view returns (bytes32[] memory) {
        return _channelIds;
    }

    function getChannelUsers(bytes32 channelId) external view returns (address[] memory) {
        return BridgeChannel(_requireChannel(channelId)).getUsers();
    }

    function getChannelFcnStorages(bytes32 channelId, bytes4 fcnSig) external view returns (address[] memory) {
        return BridgeChannel(_requireChannel(channelId)).getAppFcnStorages(fcnSig);
    }

    function getChannelPreAllocKeys(bytes32 channelId, address storageAddr) external view returns (bytes32[] memory) {
        return BridgeChannel(_requireChannel(channelId)).getAppPreAllocKeys(storageAddr);
    }

    function getChannelUserSlots(bytes32 channelId, address storageAddr) external view returns (uint8[] memory) {
        return BridgeChannel(_requireChannel(channelId)).getAppUserSlots(storageAddr);
    }

    function getChannelFcnCfg(bytes32 channelId, bytes4 fcnSig)
        external
        view
        returns (bytes32 instancesHash, bytes32 preprocessHash)
    {
        return BridgeChannel(_requireChannel(channelId)).getAppFcnCfg(fcnSig);
    }

    function getChannelUserStorageKey(bytes32 channelId, address user, address storageAddr)
        external
        view
        returns (bytes32)
    {
        return BridgeChannel(_requireChannel(channelId)).getAppUserStorageKey(user, storageAddr);
    }

    function getChannelValidatedStorageValue(bytes32 channelId, address storageAddr, bytes32 appUserStorageKey)
        external
        view
        returns (uint256)
    {
        BridgeChannel channel = BridgeChannel(_requireChannel(channelId));
        address keyOwner = channel.getStorageKeyOwner(storageAddr, appUserStorageKey);
        require(keyOwner != address(0) && channel.isUser(keyOwner), "Missing membership witness");
        return channel.getAppValidatedStorageValue(storageAddr, appUserStorageKey);
    }

    function getChannelPreAllocValue(bytes32 channelId, address storageAddr, bytes32 preAllocKey)
        external
        view
        returns (uint256)
    {
        return BridgeChannel(_requireChannel(channelId)).getAppPreAllocValue(storageAddr, preAllocKey);
    }

    function getChannelVerifiedStateRoot(bytes32 channelId, address storageAddr, uint256 stateIdx)
        external
        view
        returns (bytes32)
    {
        return BridgeChannel(_requireChannel(channelId)).getVerifiedStateRoot(storageAddr, stateIdx);
    }

    function setChannelUserStorageKey(bytes32 channelId, address user, address storageAddr, bytes32 appUserStorageKey)
        external
        onlyOwner
    {
        BridgeChannel(_requireChannel(channelId)).setAppUserStorageKey(user, storageAddr, appUserStorageKey);
    }

    function setChannelPreAllocValue(bytes32 channelId, address storageAddr, bytes32 preAllocKey, uint256 value)
        external
        onlyOwner
    {
        BridgeChannel(_requireChannel(channelId)).setAppPreAllocValue(storageAddr, preAllocKey, value);
    }

    function updateSingleStorage(
        bytes32 channelId,
        address appStorageAddr,
        bytes32 appUserStorageKey,
        uint256 updatedStorageValue,
        bytes32 updatedRoot,
        uint256[16] calldata proofGroth16,
        uint256[5] calldata publicInputGroth16
    ) external onlyOwner returns (bool) {
        return BridgeChannel(_requireChannel(channelId)).updateSingleStorage(
            appStorageAddr, appUserStorageKey, updatedStorageValue, updatedRoot, proofGroth16, publicInputGroth16
        );
    }

    function updateAllStorages(
        bytes32 channelId,
        address[] calldata appStorageAddrs,
        bytes32[] calldata appUserStorageKeys,
        uint256[][] calldata updatedStorageValues,
        bytes32[] calldata updatedRoots,
        uint256[42] calldata proofTokamak,
        uint256[4] calldata preprocessTokamak,
        uint256[] calldata publicInputTokamak
    ) external onlyOwner returns (bool) {
        return BridgeChannel(_requireChannel(channelId)).updateAllStorages(
            appStorageAddrs,
            appUserStorageKeys,
            updatedStorageValues,
            updatedRoots,
            proofTokamak,
            preprocessTokamak,
            publicInputTokamak
        );
    }

    function _requireChannel(bytes32 channelId) internal view returns (address channelAddress) {
        channelAddress = _channelAddress[channelId];
        require(channelAddress != address(0), "Channel not found");
    }
}

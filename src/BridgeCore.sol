// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Owned} from "./Owned.sol";
import {BridgeAdminManager} from "./BridgeAdminManager.sol";
import {Channel} from "./Channel.sol";

contract BridgeCore is Owned {
    error InvalidAdminManager();
    error ChannelAlreadyExists();
    error UnknownChannel();

    BridgeAdminManager public immutable adminManager;

    uint256[] private _channelIds;
    mapping(uint256 => bool) private _channelSeen;
    mapping(uint256 => address) private _channelById;

    event ChannelCreated(uint256 indexed channelId, address indexed channelAddress);

    constructor(address initialOwner, BridgeAdminManager adminManager_) Owned(initialOwner) {
        if (address(adminManager_) == address(0)) revert InvalidAdminManager();
        adminManager = adminManager_;
    }

    function createChannel(uint256 channelId, bytes4[] calldata appFunctionSigs) external onlyOwner returns (address) {
        if (_channelSeen[channelId]) revert ChannelAlreadyExists();

        Channel channel = new Channel(owner, adminManager, appFunctionSigs);
        _channelSeen[channelId] = true;
        _channelById[channelId] = address(channel);
        _channelIds.push(channelId);

        emit ChannelCreated(channelId, address(channel));
        return address(channel);
    }

    function getChannelIds() external view returns (uint256[] memory) {
        return _channelIds;
    }

    function getChannel(uint256 channelId) external view returns (address) {
        return _requireChannel(channelId);
    }

    function getChannelUsers(uint256 channelId) external view returns (uint256[] memory) {
        return Channel(_requireChannel(channelId)).getUsers();
    }

    function getChannelFcnStorages(uint256 channelId, bytes4 functionSig) external view returns (uint160[] memory) {
        return Channel(_requireChannel(channelId)).getAppFcnStorages(functionSig);
    }

    function getChannelPreAllocKeys(uint256 channelId, uint160 storageAddr) external view returns (bytes32[] memory) {
        return Channel(_requireChannel(channelId)).getAppPreAllocKeys(storageAddr);
    }

    function getChannelUserSlots(uint256 channelId, uint160 storageAddr) external view returns (uint8[] memory) {
        return Channel(_requireChannel(channelId)).getAppUserSlots(storageAddr);
    }

    function getChannelFcnCfg(
        uint256 channelId,
        bytes4 functionSig
    ) external view returns (bytes32 instanceHash, bytes32 preprocessHash) {
        return Channel(_requireChannel(channelId)).getAppFcnCfg(functionSig);
    }

    function getChannelUserStorageKey(uint256 channelId, uint256 userAddr, uint160 storageAddr) external view returns (bytes32) {
        return Channel(_requireChannel(channelId)).getAppUserStorageKey(userAddr, storageAddr);
    }

    function getChannelValidatedStorageValue(
        uint256 channelId,
        uint160 storageAddr,
        bytes32 userChannelStorageKey
    ) external view returns (bytes32) {
        return Channel(_requireChannel(channelId)).getAppValidatedStorageValue(storageAddr, userChannelStorageKey);
    }

    function getChannelPreAllocValue(uint256 channelId, uint160 storageAddr, bytes32 preAllocKey) external view returns (bytes32) {
        return Channel(_requireChannel(channelId)).getAppPreAllocValue(storageAddr, preAllocKey);
    }

    function getChannelVerifiedStateRoot(uint256 channelId, uint160 storageAddr, uint16 stateIndex) external view returns (bytes32) {
        return Channel(_requireChannel(channelId)).getVerifiedStateRoot(storageAddr, stateIndex);
    }

    function getChannelProposedStateRoot(
        uint256 channelId,
        uint8 forkId,
        uint160 storageAddr,
        uint16 stateIndex
    ) external view returns (bytes32) {
        return Channel(_requireChannel(channelId)).getProposedStateRoot(forkId, storageAddr, stateIndex);
    }

    function getChannelProposedStateFork(
        uint256 channelId,
        uint8 forkId
    ) external view returns (uint16[] memory stateIndices, uint160[] memory appStorageAddrs, bytes32[] memory roots) {
        return Channel(_requireChannel(channelId)).getProposedStateFork(forkId);
    }

    function _requireChannel(uint256 channelId) internal view returns (address channelAddress) {
        channelAddress = _channelById[channelId];
        if (channelAddress == address(0)) revert UnknownChannel();
    }
}

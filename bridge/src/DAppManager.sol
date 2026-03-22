// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/access/Ownable.sol";
import {BridgeStructs} from "./BridgeStructs.sol";
import {BridgeAdminManager} from "./BridgeAdminManager.sol";

contract DAppManager is Ownable {
    error UnknownDApp(uint256 dappId);
    error DuplicateDApp(uint256 dappId);
    error UnsupportedFunctionSignature(bytes4 functionSig);
    error UnsupportedChannelFunction(uint256 dappId, address entryContract, bytes4 functionSig);

    struct DAppInfo {
        bool exists;
        bytes32 labelHash;
    }

    BridgeAdminManager public immutable adminManager;

    mapping(uint256 => DAppInfo) private _dapps;
    mapping(uint256 => mapping(bytes32 => bool)) private _supportedFunctions;
    mapping(uint256 => BridgeStructs.FunctionReference[]) private _registeredFunctions;

    event DAppRegistered(uint256 indexed dappId, bytes32 labelHash);
    event DAppFunctionsRegistered(uint256 indexed dappId, uint256 count);

    constructor(address initialOwner, BridgeAdminManager adminManager_) Ownable(initialOwner) {
        adminManager = adminManager_;
    }

    function registerDApp(uint256 dappId, bytes32 labelHash) external onlyOwner {
        if (_dapps[dappId].exists) {
            revert DuplicateDApp(dappId);
        }
        _dapps[dappId] = DAppInfo({exists: true, labelHash: labelHash});
        emit DAppRegistered(dappId, labelHash);
    }

    function registerDAppFunctions(uint256 dappId, BridgeStructs.FunctionReference[] calldata refs)
        external
        onlyOwner
    {
        if (!_dapps[dappId].exists) {
            revert UnknownDApp(dappId);
        }

        for (uint256 i = 0; i < refs.length; i++) {
            if (!adminManager.hasFunction(refs[i].functionSig)) {
                revert UnsupportedFunctionSignature(refs[i].functionSig);
            }

            bytes32 functionKey = computeFunctionKey(refs[i].entryContract, refs[i].functionSig);
            if (!_supportedFunctions[dappId][functionKey]) {
                _supportedFunctions[dappId][functionKey] = true;
                _registeredFunctions[dappId].push(refs[i]);
            }
        }

        emit DAppFunctionsRegistered(dappId, refs.length);
    }

    function isSupportedFunction(uint256 dappId, address entryContract, bytes4 functionSig)
        external
        view
        returns (bool)
    {
        return _supportedFunctions[dappId][computeFunctionKey(entryContract, functionSig)];
    }

    function getFunctionMetadata(uint256 dappId, address entryContract, bytes4 functionSig)
        external
        view
        returns (BridgeStructs.FunctionConfig memory)
    {
        if (!_supportedFunctions[dappId][computeFunctionKey(entryContract, functionSig)]) {
            revert UnsupportedChannelFunction(dappId, entryContract, functionSig);
        }
        return adminManager.getFunctionConfig(functionSig);
    }

    function getDAppInfo(uint256 dappId) external view returns (DAppInfo memory) {
        if (!_dapps[dappId].exists) {
            revert UnknownDApp(dappId);
        }
        return _dapps[dappId];
    }

    function getRegisteredFunctions(uint256 dappId)
        external
        view
        returns (BridgeStructs.FunctionReference[] memory out)
    {
        if (!_dapps[dappId].exists) {
            revert UnknownDApp(dappId);
        }

        BridgeStructs.FunctionReference[] storage refs = _registeredFunctions[dappId];
        out = new BridgeStructs.FunctionReference[](refs.length);
        for (uint256 i = 0; i < refs.length; i++) {
            out[i] = refs[i];
        }
    }

    function computeFunctionKey(address entryContract, bytes4 functionSig)
        public
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(entryContract, functionSig));
    }
}


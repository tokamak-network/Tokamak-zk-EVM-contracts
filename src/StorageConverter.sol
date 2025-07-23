// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {MerkleTree} from "./library/MerkleTree.sol";

contract StorageConverter {
    struct ConversionConfig {
        address targetContract;
        bytes32[] relevantSlots;
        uint256 treeDepth;
        bool useSparseTree;
    }

    mapping(bytes32 => ConversionConfig) public computationConfigs;

    function registerComputation(
        bytes32 computationType,
        address targetContract,
        bytes32[] calldata slots,
        uint256 depth
    ) external {
        computationConfigs[computationType] = ConversionConfig({
            targetContract: targetContract,
            relevantSlots: slots,
            treeDepth: depth,
            useSparseTree: true
        });
    }

    function convertStorageToZKTree(address targetContract, address[] calldata accounts, uint256[] calldata values)
        external
        pure
        returns (bytes32)
    {
        require(accounts.length == values.length, "Length mismatch");

        bytes32[] memory leaves = new bytes32[](accounts.length);

        for (uint256 i = 0; i < accounts.length; i++) {
            leaves[i] = keccak256(abi.encodePacked(accounts[i], values[i]));
        }

        return MerkleTree.computeRoot(leaves);
    }
}

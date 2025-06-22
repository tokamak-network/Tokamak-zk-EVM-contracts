// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

interface IStateTransitionVerifier {
    
    struct StateUpdate{
        bytes32 channelId;
        bytes32 oldStateRoot;
        bytes32 newStateRoot;
        uint128[] proofPart1;
        uint256[] proofPart2;
        uint256[] publicInputs;
        bytes[] participantSignatures;  // Multi-sig requirement
        address[] signers;  // Who signed
    }
    
    error Invalid__Verifier();
    error Invalid__OldStateRoot(bytes32);
    error Invalid__SnarkProof();

    function verifyAndCommitStateUpdate(StateUpdate calldata update) external returns(bool);
    function updateVerifier(address _verifier) external; 
}
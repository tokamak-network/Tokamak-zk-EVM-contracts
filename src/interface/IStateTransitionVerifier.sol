// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

interface IStateTransitionVerifier {
    struct StateUpdate {
        bytes32 channelId;
        bytes32 oldStateRoot;
        bytes32 newStateRoot;
        uint128[] proofPart1;
        uint256[] proofPart2;
        uint256[] publicInputs;
        bytes[] participantSignatures; // Multi-sig requirement
        address[] signers; // Who signed
        uint256 nonce;
    }

    // Events
    event StateUpdated(bytes32 indexed channelId, bytes32 oldStateRoot, bytes32 newStateRoot, uint256 nonce);

    event VerifierUpdated(address indexed oldVerifier, address indexed newVerifier);

    // custom errors
    error Invalid__Verifier();
    error Invalid__ChannelRegistry();
    error Invalid__OldStateRoot(bytes32 provided, bytes32 expected);
    error Invalid__SnarkProof();
    error Invalid__SignatureCount(uint256 provided, uint256 required);
    error Invalid__Signature(address signer, uint256 index);
    error Invalid__Signer(address signer);
    error Invalid__DuplicateSigner(address signer);
    error Invalid__Nonce(uint256 provided, uint256 expected);
    error Invalid__ArrayLengthMismatch();
    error Invalid__ChannelNotActive();
    error Invalid__Caller();

    function verifyAndCommitStateUpdate(StateUpdate calldata update) external returns (bool);
    function updateVerifier(address _verifier) external;
}

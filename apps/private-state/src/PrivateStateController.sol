// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {L2AccountingVault} from "./L2AccountingVault.sol";
import {PrivateNullifierRegistry} from "./PrivateNullifierRegistry.sol";
import {PrivateNoteRegistry} from "./PrivateNoteRegistry.sol";

/// @title PrivateStateController
/// @notice User-facing application logic for the non-private zk-note DApp.
contract PrivateStateController {
    error EmptyArray();
    error ZeroAddress();
    error ZeroAmount();
    error UnknownCommitment(bytes32 commitment);
    error InputOutputValueMismatch(uint256 inputValue, uint256 outputValue);
    error UnauthorizedNoteOwner(address caller, address expectedOwner);

    struct Note {
        address owner;
        uint256 value;
        bytes32 salt;
    }

    bytes32 private constant NOTE_COMMITMENT_DOMAIN = keccak256("PRIVATE_STATE_NOTE_COMMITMENT");
    bytes32 private constant NULLIFIER_DOMAIN = keccak256("PRIVATE_STATE_NULLIFIER");

    event MockBridgeDepositApplied(address indexed account, uint256 amount);
    event NoteMinted(
        address indexed liquidBalanceOwner, bytes32 indexed commitment, address indexed noteOwner, uint256 amount
    );
    event NotesRedeemed(address indexed operator, address indexed receiver, uint256 inputCount);
    event MockBridgeWithdrawalApplied(address indexed account, uint256 amount);

    PrivateNullifierRegistry public immutable nullifierStore;
    PrivateNoteRegistry public immutable noteRegistry;
    L2AccountingVault public immutable l2AccountingVault;
    address public immutable canonicalAsset;

    constructor(
        PrivateNoteRegistry noteRegistry_,
        PrivateNullifierRegistry nullifierStore_,
        L2AccountingVault l2AccountingVault_,
        address canonicalAsset_
    ) {
        if (
            address(noteRegistry_) == address(0) || address(nullifierStore_) == address(0)
                || address(l2AccountingVault_) == address(0) || canonicalAsset_ == address(0)
        ) {
            revert ZeroAddress();
        }

        nullifierStore = nullifierStore_;
        noteRegistry = noteRegistry_;
        l2AccountingVault = l2AccountingVault_;
        canonicalAsset = canonicalAsset_;
    }

    function mockBridgeDeposit(uint256 amount) external {
        l2AccountingVault.creditLiquidBalance(msg.sender, amount);
        emit MockBridgeDepositApplied(msg.sender, amount);
    }

    function mockBridgeWithdraw(uint256 amount) external {
        l2AccountingVault.debitLiquidBalance(msg.sender, amount);
        emit MockBridgeWithdrawalApplied(msg.sender, amount);
    }

    function mintNotes1(Note[1] calldata outputs) external returns (bytes32[1] memory commitments) {
        Note calldata output0 = outputs[0];
        _validateNoteFields(output0.value, output0.owner);

        l2AccountingVault.debitLiquidBalance(msg.sender, output0.value);
        commitments[0] = _computeNoteCommitmentUnchecked(output0.value, output0.owner, output0.salt);
        noteRegistry.registerCommitment(commitments[0]);
        emit NoteMinted(msg.sender, commitments[0], output0.owner, output0.value);
    }

    function mintNotes2(Note[2] calldata outputs) external returns (bytes32[2] memory commitments) {
        Note calldata output0 = outputs[0];
        Note calldata output1 = outputs[1];
        _validateNoteFields(output0.value, output0.owner);
        _validateNoteFields(output1.value, output1.owner);

        uint256 totalValue = output0.value + output1.value;
        l2AccountingVault.debitLiquidBalance(msg.sender, totalValue);

        commitments[0] = _computeNoteCommitmentUnchecked(output0.value, output0.owner, output0.salt);
        noteRegistry.registerCommitment(commitments[0]);
        emit NoteMinted(msg.sender, commitments[0], output0.owner, output0.value);

        commitments[1] = _computeNoteCommitmentUnchecked(output1.value, output1.owner, output1.salt);
        noteRegistry.registerCommitment(commitments[1]);
        emit NoteMinted(msg.sender, commitments[1], output1.owner, output1.value);
    }

    function mintNotes3(Note[3] calldata outputs) external returns (bytes32[3] memory commitments) {
        Note calldata output0 = outputs[0];
        Note calldata output1 = outputs[1];
        Note calldata output2 = outputs[2];
        _validateNoteFields(output0.value, output0.owner);
        _validateNoteFields(output1.value, output1.owner);
        _validateNoteFields(output2.value, output2.owner);

        uint256 totalValue = output0.value + output1.value + output2.value;
        l2AccountingVault.debitLiquidBalance(msg.sender, totalValue);

        commitments[0] = _computeNoteCommitmentUnchecked(output0.value, output0.owner, output0.salt);
        noteRegistry.registerCommitment(commitments[0]);
        emit NoteMinted(msg.sender, commitments[0], output0.owner, output0.value);

        commitments[1] = _computeNoteCommitmentUnchecked(output1.value, output1.owner, output1.salt);
        noteRegistry.registerCommitment(commitments[1]);
        emit NoteMinted(msg.sender, commitments[1], output1.owner, output1.value);

        commitments[2] = _computeNoteCommitmentUnchecked(output2.value, output2.owner, output2.salt);
        noteRegistry.registerCommitment(commitments[2]);
        emit NoteMinted(msg.sender, commitments[2], output2.owner, output2.value);
    }

    function transferNotes1(Note[1] calldata inputNotes, Note[3] calldata outputs)
        external
        returns (bytes32[1] memory nullifiers, bytes32[3] memory outputCommitments)
    {
        Note calldata output0 = outputs[0];
        Note calldata output1 = outputs[1];
        Note calldata output2 = outputs[2];
        _validateNoteFields(output0.value, output0.owner);
        _validateNoteFields(output1.value, output1.owner);
        _validateNoteFields(output2.value, output2.owner);
        uint256 totalOutputValue = output0.value + output1.value + output2.value;

        Note calldata note = inputNotes[0];
        _validateNoteFields(note.value, note.owner);

        bytes32 sharedPayloadHash = _computeSharedNotePayloadHash(note.value, note.owner, note.salt);
        bytes32 commitment = _computeNoteCommitmentFromSharedHash(sharedPayloadHash);
        if (!noteRegistry.commitmentExists(commitment)) {
            revert UnknownCommitment(commitment);
        }

        _requireNoteOwner(note.owner);
        if (note.value != totalOutputValue) {
            revert InputOutputValueMismatch(note.value, totalOutputValue);
        }

        nullifiers[0] = _computeNullifierFromSharedHash(sharedPayloadHash);
        nullifierStore.useNullifier(nullifiers[0], commitment, msg.sender);

        bytes32 output0Commitment = _computeNoteCommitmentUnchecked(output0.value, output0.owner, output0.salt);
        outputCommitments[0] = output0Commitment;
        noteRegistry.registerCommitment(output0Commitment);

        bytes32 output1Commitment = _computeNoteCommitmentUnchecked(output1.value, output1.owner, output1.salt);
        outputCommitments[1] = output1Commitment;
        noteRegistry.registerCommitment(output1Commitment);

        bytes32 output2Commitment = _computeNoteCommitmentUnchecked(output2.value, output2.owner, output2.salt);
        outputCommitments[2] = output2Commitment;
        noteRegistry.registerCommitment(output2Commitment);
    }

    function transferNotes4(Note[4] calldata inputNotes, Note[3] calldata outputs)
        external
        returns (bytes32[4] memory nullifiers, bytes32[3] memory outputCommitments)
    {
        uint256 totalOutputValue = _validateTransferOutputs(outputs);
        bytes32[4] memory commitments;
        uint256 totalInputValue;

        for (uint256 i = 0; i < 4; ++i) {
            Note calldata note = inputNotes[i];
            _validateNoteFields(note.value, note.owner);

            bytes32 sharedPayloadHash = _computeSharedNotePayloadHash(note.value, note.owner, note.salt);
            bytes32 commitment = _computeNoteCommitmentFromSharedHash(sharedPayloadHash);
            if (!noteRegistry.commitmentExists(commitment)) {
                revert UnknownCommitment(commitment);
            }

            _requireNoteOwner(note.owner);
            commitments[i] = commitment;
            nullifiers[i] = _computeNullifierFromSharedHash(sharedPayloadHash);
            totalInputValue += note.value;
        }

        if (totalInputValue != totalOutputValue) {
            revert InputOutputValueMismatch(totalInputValue, totalOutputValue);
        }

        for (uint256 i = 0; i < 4; ++i) {
            nullifierStore.useNullifier(nullifiers[i], commitments[i], msg.sender);
        }

        _registerTransferOutputs(outputs, outputCommitments);
    }

    function transferNotes6(Note[6] calldata inputNotes, Note[3] calldata outputs)
        external
        returns (bytes32[6] memory nullifiers, bytes32[3] memory outputCommitments)
    {
        uint256 totalOutputValue = _validateTransferOutputs(outputs);
        bytes32[6] memory commitments;
        uint256 totalInputValue;

        for (uint256 i = 0; i < 6; ++i) {
            Note calldata note = inputNotes[i];
            _validateNoteFields(note.value, note.owner);

            bytes32 sharedPayloadHash = _computeSharedNotePayloadHash(note.value, note.owner, note.salt);
            bytes32 commitment = _computeNoteCommitmentFromSharedHash(sharedPayloadHash);
            if (!noteRegistry.commitmentExists(commitment)) {
                revert UnknownCommitment(commitment);
            }

            _requireNoteOwner(note.owner);
            commitments[i] = commitment;
            nullifiers[i] = _computeNullifierFromSharedHash(sharedPayloadHash);
            totalInputValue += note.value;
        }

        if (totalInputValue != totalOutputValue) {
            revert InputOutputValueMismatch(totalInputValue, totalOutputValue);
        }

        for (uint256 i = 0; i < 6; ++i) {
            nullifierStore.useNullifier(nullifiers[i], commitments[i], msg.sender);
        }

        _registerTransferOutputs(outputs, outputCommitments);
    }

    function transferNotes8(Note[8] calldata inputNotes, Note[3] calldata outputs)
        external
        returns (bytes32[8] memory nullifiers, bytes32[3] memory outputCommitments)
    {
        uint256 totalOutputValue = _validateTransferOutputs(outputs);
        bytes32[8] memory commitments;
        uint256 totalInputValue;

        for (uint256 i = 0; i < 8; ++i) {
            Note calldata note = inputNotes[i];
            _validateNoteFields(note.value, note.owner);

            bytes32 sharedPayloadHash = _computeSharedNotePayloadHash(note.value, note.owner, note.salt);
            bytes32 commitment = _computeNoteCommitmentFromSharedHash(sharedPayloadHash);
            if (!noteRegistry.commitmentExists(commitment)) {
                revert UnknownCommitment(commitment);
            }

            _requireNoteOwner(note.owner);
            commitments[i] = commitment;
            nullifiers[i] = _computeNullifierFromSharedHash(sharedPayloadHash);
            totalInputValue += note.value;
        }

        if (totalInputValue != totalOutputValue) {
            revert InputOutputValueMismatch(totalInputValue, totalOutputValue);
        }

        for (uint256 i = 0; i < 8; ++i) {
            nullifierStore.useNullifier(nullifiers[i], commitments[i], msg.sender);
        }

        _registerTransferOutputs(outputs, outputCommitments);
    }

    function redeemNotes4(Note[4] calldata inputNotes, address receiver)
        external
        returns (bytes32[4] memory nullifiers)
    {
        if (receiver == address(0)) {
            revert ZeroAddress();
        }

        bytes32[4] memory inputCommitments;
        for (uint256 i = 0; i < 4; ++i) {
            Note calldata note = inputNotes[i];
            _validateNoteFields(note.value, note.owner);

            bytes32 sharedPayloadHash = _computeSharedNotePayloadHash(note.value, note.owner, note.salt);
            bytes32 commitment = _computeNoteCommitmentFromSharedHash(sharedPayloadHash);
            if (!noteRegistry.commitmentExists(commitment)) {
                revert UnknownCommitment(commitment);
            }

            _requireNoteOwner(note.owner);
            inputCommitments[i] = commitment;
            nullifiers[i] = _computeNullifierFromSharedHash(sharedPayloadHash);
        }

        for (uint256 i = 0; i < 4; ++i) {
            nullifierStore.useNullifier(nullifiers[i], inputCommitments[i], msg.sender);
            l2AccountingVault.creditLiquidBalance(receiver, inputNotes[i].value);
        }

        emit NotesRedeemed(msg.sender, receiver, 4);
    }

    function redeemNotes6(Note[6] calldata inputNotes, address receiver)
        external
        returns (bytes32[6] memory nullifiers)
    {
        if (receiver == address(0)) {
            revert ZeroAddress();
        }

        bytes32[6] memory inputCommitments;
        for (uint256 i = 0; i < 6; ++i) {
            Note calldata note = inputNotes[i];
            _validateNoteFields(note.value, note.owner);

            bytes32 sharedPayloadHash = _computeSharedNotePayloadHash(note.value, note.owner, note.salt);
            bytes32 commitment = _computeNoteCommitmentFromSharedHash(sharedPayloadHash);
            if (!noteRegistry.commitmentExists(commitment)) {
                revert UnknownCommitment(commitment);
            }

            _requireNoteOwner(note.owner);
            inputCommitments[i] = commitment;
            nullifiers[i] = _computeNullifierFromSharedHash(sharedPayloadHash);
        }

        for (uint256 i = 0; i < 6; ++i) {
            nullifierStore.useNullifier(nullifiers[i], inputCommitments[i], msg.sender);
            l2AccountingVault.creditLiquidBalance(receiver, inputNotes[i].value);
        }

        emit NotesRedeemed(msg.sender, receiver, 6);
    }

    function redeemNotes8(Note[8] calldata inputNotes, address receiver)
        external
        returns (bytes32[8] memory nullifiers)
    {
        if (receiver == address(0)) {
            revert ZeroAddress();
        }

        bytes32[8] memory inputCommitments;
        for (uint256 i = 0; i < 8; ++i) {
            Note calldata note = inputNotes[i];
            _validateNoteFields(note.value, note.owner);

            bytes32 sharedPayloadHash = _computeSharedNotePayloadHash(note.value, note.owner, note.salt);
            bytes32 commitment = _computeNoteCommitmentFromSharedHash(sharedPayloadHash);
            if (!noteRegistry.commitmentExists(commitment)) {
                revert UnknownCommitment(commitment);
            }

            _requireNoteOwner(note.owner);
            inputCommitments[i] = commitment;
            nullifiers[i] = _computeNullifierFromSharedHash(sharedPayloadHash);
        }

        for (uint256 i = 0; i < 8; ++i) {
            nullifierStore.useNullifier(nullifiers[i], inputCommitments[i], msg.sender);
            l2AccountingVault.creditLiquidBalance(receiver, inputNotes[i].value);
        }

        emit NotesRedeemed(msg.sender, receiver, 8);
    }

    function computeNoteCommitment(uint256 value, address owner, bytes32 salt) public view returns (bytes32) {
        _validateNoteFields(value, owner);
        return _computeNoteCommitmentFromSharedHash(_computeSharedNotePayloadHash(value, owner, salt));
    }

    function computeNullifier(uint256 value, address owner, bytes32 salt) public view returns (bytes32) {
        _validateNoteFields(value, owner);
        return _computeNullifierFromSharedHash(_computeSharedNotePayloadHash(value, owner, salt));
    }

    function _validateNoteFields(uint256 value, address owner) internal pure {
        if (owner == address(0)) {
            revert ZeroAddress();
        }
        if (value == 0) {
            revert ZeroAmount();
        }
    }

    function _requireNoteOwner(address owner) internal view {
        if (msg.sender != owner) {
            revert UnauthorizedNoteOwner(msg.sender, owner);
        }
    }

    function _computeNoteCommitmentUnchecked(uint256 value, address owner, bytes32 salt) internal view returns (bytes32) {
        return _computeNoteCommitmentFromSharedHash(_computeSharedNotePayloadHash(value, owner, salt));
    }

    function _computeNullifierUnchecked(uint256 value, address owner, bytes32 salt) internal view returns (bytes32) {
        return _computeNullifierFromSharedHash(_computeSharedNotePayloadHash(value, owner, salt));
    }

    function _computeSharedNotePayloadHash(uint256 value, address owner, bytes32 salt) internal view returns (bytes32) {
        return keccak256(abi.encode(block.chainid, canonicalAsset, value, owner, salt));
    }

    function _computeNoteCommitmentFromSharedHash(bytes32 sharedPayloadHash) internal pure returns (bytes32) {
        return keccak256(abi.encode(NOTE_COMMITMENT_DOMAIN, sharedPayloadHash));
    }

    function _computeNullifierFromSharedHash(bytes32 sharedPayloadHash) internal pure returns (bytes32) {
        return keccak256(abi.encode(NULLIFIER_DOMAIN, sharedPayloadHash));
    }

    function _validateTransferOutputs(Note[3] calldata outputs) internal pure returns (uint256 totalOutputValue) {
        for (uint256 i = 0; i < 3; ++i) {
            _validateNoteFields(outputs[i].value, outputs[i].owner);
            totalOutputValue += outputs[i].value;
        }
    }

    function _registerTransferOutputs(Note[3] calldata outputs, bytes32[3] memory outputCommitments) internal {
        for (uint256 i = 0; i < 3; ++i) {
            bytes32 commitment = _computeNoteCommitmentUnchecked(outputs[i].value, outputs[i].owner, outputs[i].salt);
            outputCommitments[i] = commitment;
            noteRegistry.registerCommitment(commitment);
        }
    }

}

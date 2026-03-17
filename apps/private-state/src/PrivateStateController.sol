// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {L2AccountingVault} from "./L2AccountingVault.sol";

/// @title PrivateStateController
/// @notice User-facing application logic for the non-private zk-note DApp.
contract PrivateStateController {
    error EmptyArray();
    error ZeroCommitment();
    error ZeroNullifier();
    error ZeroAddress();
    error ZeroAmount();
    error CommitmentAlreadyExists(bytes32 commitment);
    error NullifierAlreadyUsed(bytes32 nullifier);
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

    mapping(bytes32 commitment => bool exists) public commitmentExists;
    mapping(bytes32 nullifier => bool used) public nullifierUsed;
    L2AccountingVault public immutable l2AccountingVault;

    constructor(L2AccountingVault l2AccountingVault_) {
        if (address(l2AccountingVault_) == address(0)) {
            revert ZeroAddress();
        }

        l2AccountingVault = l2AccountingVault_;
    }

    function mintNotes1(Note[1] calldata outputs) external returns (bytes32[1] memory commitments) {
        uint256 output0Value;
        (output0Value, commitments[0]) = _prepareOutputNote(outputs[0]);

        l2AccountingVault.debitLiquidBalance(msg.sender, output0Value);
        _registerCommitment(commitments[0]);
    }

    function mintNotes2(Note[2] calldata outputs) external returns (bytes32[2] memory commitments) {
        uint256 output0Value;
        (output0Value, commitments[0]) = _prepareOutputNote(outputs[0]);
        uint256 output1Value;
        (output1Value, commitments[1]) = _prepareOutputNote(outputs[1]);

        uint256 totalValue = output0Value + output1Value;
        l2AccountingVault.debitLiquidBalance(msg.sender, totalValue);
        _registerCommitment(commitments[0]);
        _registerCommitment(commitments[1]);
    }

    function mintNotes3(Note[3] calldata outputs) external returns (bytes32[3] memory commitments) {
        uint256 output0Value;
        (output0Value, commitments[0]) = _prepareOutputNote(outputs[0]);
        uint256 output1Value;
        (output1Value, commitments[1]) = _prepareOutputNote(outputs[1]);
        uint256 output2Value;
        (output2Value, commitments[2]) = _prepareOutputNote(outputs[2]);

        uint256 totalValue = output0Value + output1Value + output2Value;
        l2AccountingVault.debitLiquidBalance(msg.sender, totalValue);
        _registerCommitment(commitments[0]);
        _registerCommitment(commitments[1]);
        _registerCommitment(commitments[2]);
    }

    function mintNotes4(Note[4] calldata outputs) external returns (bytes32[4] memory commitments) {
        uint256 output0Value;
        (output0Value, commitments[0]) = _prepareOutputNote(outputs[0]);
        uint256 output1Value;
        (output1Value, commitments[1]) = _prepareOutputNote(outputs[1]);
        uint256 output2Value;
        (output2Value, commitments[2]) = _prepareOutputNote(outputs[2]);
        uint256 output3Value;
        (output3Value, commitments[3]) = _prepareOutputNote(outputs[3]);

        uint256 totalValue = output0Value + output1Value + output2Value + output3Value;
        l2AccountingVault.debitLiquidBalance(msg.sender, totalValue);
        _registerCommitment(commitments[0]);
        _registerCommitment(commitments[1]);
        _registerCommitment(commitments[2]);
        _registerCommitment(commitments[3]);
    }

    function mintNotes5(Note[5] calldata outputs) external returns (bytes32[5] memory commitments) {
        uint256 output0Value;
        (output0Value, commitments[0]) = _prepareOutputNote(outputs[0]);
        uint256 output1Value;
        (output1Value, commitments[1]) = _prepareOutputNote(outputs[1]);
        uint256 output2Value;
        (output2Value, commitments[2]) = _prepareOutputNote(outputs[2]);
        uint256 output3Value;
        (output3Value, commitments[3]) = _prepareOutputNote(outputs[3]);
        uint256 output4Value;
        (output4Value, commitments[4]) = _prepareOutputNote(outputs[4]);

        uint256 totalValue = output0Value + output1Value + output2Value + output3Value + output4Value;
        l2AccountingVault.debitLiquidBalance(msg.sender, totalValue);
        _registerCommitment(commitments[0]);
        _registerCommitment(commitments[1]);
        _registerCommitment(commitments[2]);
        _registerCommitment(commitments[3]);
        _registerCommitment(commitments[4]);
    }

    function mintNotes6(Note[6] calldata outputs) external returns (bytes32[6] memory commitments) {
        uint256 output0Value;
        (output0Value, commitments[0]) = _prepareOutputNote(outputs[0]);
        uint256 output1Value;
        (output1Value, commitments[1]) = _prepareOutputNote(outputs[1]);
        uint256 output2Value;
        (output2Value, commitments[2]) = _prepareOutputNote(outputs[2]);
        uint256 output3Value;
        (output3Value, commitments[3]) = _prepareOutputNote(outputs[3]);
        uint256 output4Value;
        (output4Value, commitments[4]) = _prepareOutputNote(outputs[4]);
        uint256 output5Value;
        (output5Value, commitments[5]) = _prepareOutputNote(outputs[5]);

        uint256 totalValue = output0Value + output1Value + output2Value + output3Value + output4Value + output5Value;
        l2AccountingVault.debitLiquidBalance(msg.sender, totalValue);
        _registerCommitment(commitments[0]);
        _registerCommitment(commitments[1]);
        _registerCommitment(commitments[2]);
        _registerCommitment(commitments[3]);
        _registerCommitment(commitments[4]);
        _registerCommitment(commitments[5]);
    }

    function transferNotes1To1(Note[1] calldata inputNotes, Note[1] calldata outputs)
        external
        returns (bytes32[1] memory nullifiers, bytes32[1] memory outputCommitments)
    {
        (address output0Owner, uint256 output0Value, bytes32 output0Salt) = _loadValidatedNote(outputs[0]);

        uint256 noteValue;
        (noteValue, nullifiers[0]) = _prepareSpendableNote(inputNotes[0]);
        if (noteValue != output0Value) {
            revert InputOutputValueMismatch(noteValue, output0Value);
        }

        _useNullifier(nullifiers[0]);

        bytes32 output0Commitment = _computeNoteCommitmentUnchecked(output0Value, output0Owner, output0Salt);
        outputCommitments[0] = output0Commitment;
        _registerCommitment(output0Commitment);
    }

    function transferNotes1To2(Note[1] calldata inputNotes, Note[2] calldata outputs)
        external
        returns (bytes32[1] memory nullifiers, bytes32[2] memory outputCommitments)
    {
        (address output0Owner, uint256 output0Value, bytes32 output0Salt) = _loadValidatedNote(outputs[0]);
        (address output1Owner, uint256 output1Value, bytes32 output1Salt) = _loadValidatedNote(outputs[1]);
        uint256 totalOutputValue = output0Value + output1Value;

        uint256 noteValue;
        (noteValue, nullifiers[0]) = _prepareSpendableNote(inputNotes[0]);
        if (noteValue != totalOutputValue) {
            revert InputOutputValueMismatch(noteValue, totalOutputValue);
        }

        _useNullifier(nullifiers[0]);

        bytes32 output0Commitment = _computeNoteCommitmentUnchecked(output0Value, output0Owner, output0Salt);
        outputCommitments[0] = output0Commitment;
        _registerCommitment(output0Commitment);

        bytes32 output1Commitment = _computeNoteCommitmentUnchecked(output1Value, output1Owner, output1Salt);
        outputCommitments[1] = output1Commitment;
        _registerCommitment(output1Commitment);
    }

    function transferNotes1To3(Note[1] calldata inputNotes, Note[3] calldata outputs)
        external
        returns (bytes32[1] memory nullifiers, bytes32[3] memory outputCommitments)
    {
        uint256 output0Value;
        uint256 output1Value;
        uint256 output2Value;
        (output0Value, outputCommitments[0]) = _prepareOutputNote(outputs[0]);
        (output1Value, outputCommitments[1]) = _prepareOutputNote(outputs[1]);
        (output2Value, outputCommitments[2]) = _prepareOutputNote(outputs[2]);
        uint256 totalOutputValue = output0Value + output1Value + output2Value;

        uint256 noteValue;
        (noteValue, nullifiers[0]) = _prepareSpendableNote(inputNotes[0]);
        if (noteValue != totalOutputValue) {
            revert InputOutputValueMismatch(noteValue, totalOutputValue);
        }

        _useNullifier(nullifiers[0]);
        _registerCommitment(outputCommitments[0]);
        _registerCommitment(outputCommitments[1]);
        _registerCommitment(outputCommitments[2]);
    }

    function transferNotes2To1(Note[2] calldata inputNotes, Note[1] calldata outputs)
        external
        returns (bytes32[2] memory nullifiers, bytes32[1] memory outputCommitments)
    {
        uint256 totalOutputValue;
        (totalOutputValue, outputCommitments[0]) = _prepareOutputNote(outputs[0]);

        uint256 totalInputValue;
        {
            uint256 noteValue;
            (noteValue, nullifiers[0]) = _prepareSpendableNote(inputNotes[0]);
            totalInputValue = noteValue;
        }
        {
            uint256 noteValue;
            (noteValue, nullifiers[1]) = _prepareSpendableNote(inputNotes[1]);
            totalInputValue += noteValue;
        }

        if (totalInputValue != totalOutputValue) {
            revert InputOutputValueMismatch(totalInputValue, totalOutputValue);
        }

        _useNullifier(nullifiers[0]);
        _useNullifier(nullifiers[1]);
        _registerCommitment(outputCommitments[0]);
    }

    function transferNotes2To2(Note[2] calldata inputNotes, Note[2] calldata outputs)
        external
        returns (bytes32[2] memory nullifiers, bytes32[2] memory outputCommitments)
    {
        uint256 output0Value;
        uint256 output1Value;
        (output0Value, outputCommitments[0]) = _prepareOutputNote(outputs[0]);
        (output1Value, outputCommitments[1]) = _prepareOutputNote(outputs[1]);
        uint256 totalOutputValue = output0Value + output1Value;

        uint256 totalInputValue;
        {
            uint256 noteValue;
            (noteValue, nullifiers[0]) = _prepareSpendableNote(inputNotes[0]);
            totalInputValue = noteValue;
        }
        {
            uint256 noteValue;
            (noteValue, nullifiers[1]) = _prepareSpendableNote(inputNotes[1]);
            totalInputValue += noteValue;
        }

        if (totalInputValue != totalOutputValue) {
            revert InputOutputValueMismatch(totalInputValue, totalOutputValue);
        }

        _useNullifier(nullifiers[0]);
        _useNullifier(nullifiers[1]);
        _registerCommitment(outputCommitments[0]);
        _registerCommitment(outputCommitments[1]);
    }

    function transferNotes3To1(Note[3] calldata inputNotes, Note[1] calldata outputs)
        external
        returns (bytes32[3] memory nullifiers, bytes32[1] memory outputCommitments)
    {
        uint256 totalOutputValue;
        (totalOutputValue, outputCommitments[0]) = _prepareOutputNote(outputs[0]);

        uint256 totalInputValue;
        {
            uint256 noteValue;
            (noteValue, nullifiers[0]) = _prepareSpendableNote(inputNotes[0]);
            totalInputValue = noteValue;
        }
        {
            uint256 noteValue;
            (noteValue, nullifiers[1]) = _prepareSpendableNote(inputNotes[1]);
            totalInputValue += noteValue;
        }
        {
            uint256 noteValue;
            (noteValue, nullifiers[2]) = _prepareSpendableNote(inputNotes[2]);
            totalInputValue += noteValue;
        }

        if (totalInputValue != totalOutputValue) {
            revert InputOutputValueMismatch(totalInputValue, totalOutputValue);
        }

        _useNullifier(nullifiers[0]);
        _useNullifier(nullifiers[1]);
        _useNullifier(nullifiers[2]);
        _registerCommitment(outputCommitments[0]);
    }

    function transferNotes3To2(Note[3] calldata inputNotes, Note[2] calldata outputs)
        external
        returns (bytes32[3] memory nullifiers, bytes32[2] memory outputCommitments)
    {
        uint256 output0Value;
        uint256 output1Value;
        (output0Value, outputCommitments[0]) = _prepareOutputNote(outputs[0]);
        (output1Value, outputCommitments[1]) = _prepareOutputNote(outputs[1]);
        uint256 totalOutputValue = output0Value + output1Value;

        uint256 note0Value;
        (note0Value, nullifiers[0]) = _prepareSpendableNote(inputNotes[0]);

        uint256 note1Value;
        (note1Value, nullifiers[1]) = _prepareSpendableNote(inputNotes[1]);

        uint256 note2Value;
        (note2Value, nullifiers[2]) = _prepareSpendableNote(inputNotes[2]);

        uint256 totalInputValue = note0Value + note1Value + note2Value;
        if (totalInputValue != totalOutputValue) {
            revert InputOutputValueMismatch(totalInputValue, totalOutputValue);
        }

        _useNullifier(nullifiers[0]);
        _useNullifier(nullifiers[1]);
        _useNullifier(nullifiers[2]);
        _registerCommitment(outputCommitments[0]);
        _registerCommitment(outputCommitments[1]);
    }

    function transferNotes4To1(Note[4] calldata inputNotes, Note[1] calldata outputs)
        external
        returns (bytes32[4] memory nullifiers, bytes32[1] memory outputCommitments)
    {
        uint256 totalOutputValue;
        (totalOutputValue, outputCommitments[0]) = _prepareOutputNote(outputs[0]);

        uint256 totalInputValue;
        {
            uint256 noteValue;
            (noteValue, nullifiers[0]) = _prepareSpendableNote(inputNotes[0]);
            totalInputValue = noteValue;
        }
        {
            uint256 noteValue;
            (noteValue, nullifiers[1]) = _prepareSpendableNote(inputNotes[1]);
            totalInputValue += noteValue;
        }
        {
            uint256 noteValue;
            (noteValue, nullifiers[2]) = _prepareSpendableNote(inputNotes[2]);
            totalInputValue += noteValue;
        }
        {
            uint256 noteValue;
            (noteValue, nullifiers[3]) = _prepareSpendableNote(inputNotes[3]);
            totalInputValue += noteValue;
        }

        if (totalInputValue != totalOutputValue) {
            revert InputOutputValueMismatch(totalInputValue, totalOutputValue);
        }

        _useNullifier(nullifiers[0]);
        _useNullifier(nullifiers[1]);
        _useNullifier(nullifiers[2]);
        _useNullifier(nullifiers[3]);
        _registerCommitment(outputCommitments[0]);
    }


    function redeemNotes1(Note[1] calldata inputNotes, address receiver)
        external
        returns (bytes32[1] memory nullifiers)
    {
        assembly {
            if iszero(receiver) {
                mstore(0x00, 0xd92e233d)
                revert(0x1c, 0x04)
            }
        }
        {
            uint256 noteValue;
            bytes32 nullifier;
            (noteValue, nullifier) = _prepareSpendableNote(inputNotes[0]);
            nullifiers[0] = nullifier;
            _useNullifier(nullifier);
            l2AccountingVault.creditLiquidBalance(receiver, noteValue);
        }

    }

    function redeemNotes2(Note[2] calldata inputNotes, address receiver)
        external
        returns (bytes32[2] memory nullifiers)
    {
        assembly {
            if iszero(receiver) {
                mstore(0x00, 0xd92e233d)
                revert(0x1c, 0x04)
            }
        }
        {
            uint256 noteValue;
            bytes32 nullifier;
            (noteValue, nullifier) = _prepareSpendableNote(inputNotes[0]);
            nullifiers[0] = nullifier;
            _useNullifier(nullifier);
            uint256 totalRedeemValue = noteValue;

            (noteValue, nullifier) = _prepareSpendableNote(inputNotes[1]);
            nullifiers[1] = nullifier;
            _useNullifier(nullifier);
            totalRedeemValue += noteValue;

            l2AccountingVault.creditLiquidBalance(receiver, totalRedeemValue);
        }
    }

    function redeemNotes3(Note[3] calldata inputNotes, address receiver)
        external
        returns (bytes32[3] memory nullifiers)
    {
        assembly {
            if iszero(receiver) {
                mstore(0x00, 0xd92e233d)
                revert(0x1c, 0x04)
            }
        }
        {
            uint256 noteValue;
            bytes32 nullifier;
            (noteValue, nullifier) = _prepareSpendableNote(inputNotes[0]);
            nullifiers[0] = nullifier;
            _useNullifier(nullifier);
            uint256 totalRedeemValue = noteValue;

            (noteValue, nullifier) = _prepareSpendableNote(inputNotes[1]);
            nullifiers[1] = nullifier;
            _useNullifier(nullifier);
            totalRedeemValue += noteValue;

            (noteValue, nullifier) = _prepareSpendableNote(inputNotes[2]);
            nullifiers[2] = nullifier;
            _useNullifier(nullifier);
            totalRedeemValue += noteValue;

            l2AccountingVault.creditLiquidBalance(receiver, totalRedeemValue);
        }
    }

    function redeemNotes4(Note[4] calldata inputNotes, address receiver)
        external
        returns (bytes32[4] memory nullifiers)
    {
        assembly {
            if iszero(receiver) {
                mstore(0x00, 0xd92e233d)
                revert(0x1c, 0x04)
            }
        }
        {
            uint256 noteValue;
            bytes32 nullifier;
            (noteValue, nullifier) = _prepareSpendableNote(inputNotes[0]);
            nullifiers[0] = nullifier;
            _useNullifier(nullifier);
            uint256 totalRedeemValue = noteValue;

            (noteValue, nullifier) = _prepareSpendableNote(inputNotes[1]);
            nullifiers[1] = nullifier;
            _useNullifier(nullifier);
            totalRedeemValue += noteValue;

            (noteValue, nullifier) = _prepareSpendableNote(inputNotes[2]);
            nullifiers[2] = nullifier;
            _useNullifier(nullifier);
            totalRedeemValue += noteValue;

            (noteValue, nullifier) = _prepareSpendableNote(inputNotes[3]);
            nullifiers[3] = nullifier;
            _useNullifier(nullifier);
            totalRedeemValue += noteValue;

            l2AccountingVault.creditLiquidBalance(receiver, totalRedeemValue);
        }
    }

    function computeNoteCommitment(uint256 value, address owner, bytes32 salt) public pure returns (bytes32) {
        _validateNoteFields(value, owner);
        return _computeNoteCommitmentUnchecked(value, owner, salt);
    }

    function computeNullifier(uint256 value, address owner, bytes32 salt) public pure returns (bytes32) {
        _validateNoteFields(value, owner);
        return _computeNullifierUnchecked(value, owner, salt);
    }

    function _validateNoteFields(uint256 value, address owner) internal pure {
        assembly {
            if iszero(owner) {
                mstore(0x00, 0xd92e233d)
                revert(0x1c, 0x04)
            }
            if iszero(value) {
                mstore(0x00, 0x1f2a2005)
                revert(0x1c, 0x04)
            }
        }
    }

    function _requireNoteOwner(address owner) internal view {
        if (msg.sender != owner) {
            revert UnauthorizedNoteOwner(msg.sender, owner);
        }
    }

    function _computeNoteCommitmentUnchecked(uint256 value, address owner, bytes32 salt) internal pure returns (bytes32) {
        return keccak256(abi.encode(NOTE_COMMITMENT_DOMAIN, owner, value, salt));
    }

    function _computeNullifierUnchecked(uint256 value, address owner, bytes32 salt) internal pure returns (bytes32) {
        return keccak256(abi.encode(NULLIFIER_DOMAIN, owner, value, salt));
    }

    function _prepareOutputNote(Note calldata outputNote)
        internal
        pure
        returns (uint256 outputValue, bytes32 outputCommitment)
    {
        (address outputOwner, uint256 value, bytes32 outputSalt) = _loadValidatedNote(outputNote);
        outputValue = value;
        outputCommitment = _computeNoteCommitmentUnchecked(value, outputOwner, outputSalt);
    }

    function _prepareSpendableNote(Note calldata inputNote)
        internal
        view
        returns (uint256 noteValue, bytes32 nullifier)
    {
        (address noteOwner, uint256 value, bytes32 noteSalt) = _loadValidatedNote(inputNote);
        bytes32 commitment = _computeNoteCommitmentUnchecked(value, noteOwner, noteSalt);
        if (!commitmentExists[commitment]) {
            revert UnknownCommitment(commitment);
        }
        _requireNoteOwner(noteOwner);
        noteValue = value;
        nullifier = _computeNullifierUnchecked(value, noteOwner, noteSalt);
    }

    function _registerCommitment(bytes32 commitment) internal {
        if (commitment == bytes32(0)) {
            revert ZeroCommitment();
        }
        if (commitmentExists[commitment]) {
            revert CommitmentAlreadyExists(commitment);
        }
        commitmentExists[commitment] = true;
    }

    function _useNullifier(bytes32 nullifier) internal {
        if (nullifier == bytes32(0)) {
            revert ZeroNullifier();
        }
        if (nullifierUsed[nullifier]) {
            revert NullifierAlreadyUsed(nullifier);
        }
        nullifierUsed[nullifier] = true;
    }

    function _loadValidatedNote(Note calldata note)
        internal
        pure
        returns (address owner, uint256 value, bytes32 salt)
    {
        assembly {
            let noteOffset := note
            owner := and(calldataload(noteOffset), 0xffffffffffffffffffffffffffffffffffffffff)
            value := calldataload(add(noteOffset, 0x20))
            salt := calldataload(add(noteOffset, 0x40))
        }
        _validateNoteFields(value, owner);
    }

}

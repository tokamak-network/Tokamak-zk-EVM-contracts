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

    event MockBridgeDepositApplied(address indexed account, uint256 amount);
    event NoteMinted(
        address indexed liquidBalanceOwner, bytes32 indexed commitment, address indexed noteOwner, uint256 amount
    );
    event NotesRedeemed(address indexed operator, address indexed receiver, uint256 inputCount);
    event MockBridgeWithdrawalApplied(address indexed account, uint256 amount);

    mapping(bytes32 commitment => bool exists) public commitmentExists;
    mapping(bytes32 nullifier => bool used) public nullifierUsed;
    L2AccountingVault public immutable l2AccountingVault;
    address public immutable canonicalAsset;

    constructor(L2AccountingVault l2AccountingVault_, address canonicalAsset_) {
        if (address(l2AccountingVault_) == address(0) || canonicalAsset_ == address(0)) {
            revert ZeroAddress();
        }

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
        (address output0Owner, uint256 output0Value, bytes32 output0Salt) = _loadValidatedNote(outputs[0]);

        l2AccountingVault.debitLiquidBalance(msg.sender, output0Value);
        commitments[0] = _computeNoteCommitmentUnchecked(output0Value, output0Owner, output0Salt);
        _registerCommitment(commitments[0]);
        emit NoteMinted(msg.sender, commitments[0], output0Owner, output0Value);
    }

    function mintNotes2(Note[2] calldata outputs) external returns (bytes32[2] memory commitments) {
        (address output0Owner, uint256 output0Value, bytes32 output0Salt) = _loadValidatedNote(outputs[0]);
        (address output1Owner, uint256 output1Value, bytes32 output1Salt) = _loadValidatedNote(outputs[1]);

        uint256 totalValue = output0Value + output1Value;
        l2AccountingVault.debitLiquidBalance(msg.sender, totalValue);

        commitments[0] = _computeNoteCommitmentUnchecked(output0Value, output0Owner, output0Salt);
        _registerCommitment(commitments[0]);
        emit NoteMinted(msg.sender, commitments[0], output0Owner, output0Value);

        commitments[1] = _computeNoteCommitmentUnchecked(output1Value, output1Owner, output1Salt);
        _registerCommitment(commitments[1]);
        emit NoteMinted(msg.sender, commitments[1], output1Owner, output1Value);
    }

    function mintNotes3(Note[3] calldata outputs) external returns (bytes32[3] memory commitments) {
        (address output0Owner, uint256 output0Value, bytes32 output0Salt) = _loadValidatedNote(outputs[0]);
        (address output1Owner, uint256 output1Value, bytes32 output1Salt) = _loadValidatedNote(outputs[1]);
        (address output2Owner, uint256 output2Value, bytes32 output2Salt) = _loadValidatedNote(outputs[2]);

        uint256 totalValue = output0Value + output1Value + output2Value;
        l2AccountingVault.debitLiquidBalance(msg.sender, totalValue);

        commitments[0] = _computeNoteCommitmentUnchecked(output0Value, output0Owner, output0Salt);
        _registerCommitment(commitments[0]);
        emit NoteMinted(msg.sender, commitments[0], output0Owner, output0Value);

        commitments[1] = _computeNoteCommitmentUnchecked(output1Value, output1Owner, output1Salt);
        _registerCommitment(commitments[1]);
        emit NoteMinted(msg.sender, commitments[1], output1Owner, output1Value);

        commitments[2] = _computeNoteCommitmentUnchecked(output2Value, output2Owner, output2Salt);
        _registerCommitment(commitments[2]);
        emit NoteMinted(msg.sender, commitments[2], output2Owner, output2Value);
    }

    function transferNotes1To1(Note[1] calldata inputNotes, Note[1] calldata outputs)
        external
        returns (bytes32[1] memory nullifiers, bytes32[1] memory outputCommitments)
    {
        (address output0Owner, uint256 output0Value, bytes32 output0Salt) = _loadValidatedNote(outputs[0]);

        (address noteOwner, uint256 noteValue, bytes32 noteSalt) = _loadValidatedNote(inputNotes[0]);

        bytes32 commitment = _computeNoteCommitmentUnchecked(noteValue, noteOwner, noteSalt);
        if (!commitmentExists[commitment]) {
            revert UnknownCommitment(commitment);
        }

        _requireNoteOwner(noteOwner);
        if (noteValue != output0Value) {
            revert InputOutputValueMismatch(noteValue, output0Value);
        }

        nullifiers[0] = _computeNullifierUnchecked(noteValue, noteOwner, noteSalt);
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

        (address noteOwner, uint256 noteValue, bytes32 noteSalt) = _loadValidatedNote(inputNotes[0]);

        bytes32 commitment = _computeNoteCommitmentUnchecked(noteValue, noteOwner, noteSalt);
        if (!commitmentExists[commitment]) {
            revert UnknownCommitment(commitment);
        }

        _requireNoteOwner(noteOwner);
        if (noteValue != totalOutputValue) {
            revert InputOutputValueMismatch(noteValue, totalOutputValue);
        }

        nullifiers[0] = _computeNullifierUnchecked(noteValue, noteOwner, noteSalt);
        _useNullifier(nullifiers[0]);

        bytes32 output0Commitment = _computeNoteCommitmentUnchecked(output0Value, output0Owner, output0Salt);
        outputCommitments[0] = output0Commitment;
        _registerCommitment(output0Commitment);

        bytes32 output1Commitment = _computeNoteCommitmentUnchecked(output1Value, output1Owner, output1Salt);
        outputCommitments[1] = output1Commitment;
        _registerCommitment(output1Commitment);
    }

    function transferNotes2To1(Note[2] calldata inputNotes, Note[1] calldata outputs)
        external
        returns (bytes32[2] memory nullifiers, bytes32[1] memory outputCommitments)
    {
        uint256 totalOutputValue = _validateTransferOutputs(outputs);
        uint256 totalInputValue;

        for (uint256 i = 0; i < 2; ++i) {
            (address noteOwner, uint256 noteValue, bytes32 noteSalt) = _loadValidatedNote(inputNotes[i]);

            bytes32 commitment = _computeNoteCommitmentUnchecked(noteValue, noteOwner, noteSalt);
            if (!commitmentExists[commitment]) {
                revert UnknownCommitment(commitment);
            }

            _requireNoteOwner(noteOwner);
            nullifiers[i] = _computeNullifierUnchecked(noteValue, noteOwner, noteSalt);
            totalInputValue += noteValue;
        }

        if (totalInputValue != totalOutputValue) {
            revert InputOutputValueMismatch(totalInputValue, totalOutputValue);
        }

        for (uint256 i = 0; i < 2; ++i) {
            _useNullifier(nullifiers[i]);
        }

        _registerTransferOutputs(outputs, outputCommitments);
    }

    function transferNotes2To2(Note[2] calldata inputNotes, Note[2] calldata outputs)
        external
        returns (bytes32[2] memory nullifiers, bytes32[2] memory outputCommitments)
    {
        uint256 totalOutputValue = _validateTransferOutputs(outputs);
        uint256 totalInputValue;

        for (uint256 i = 0; i < 2; ++i) {
            (address noteOwner, uint256 noteValue, bytes32 noteSalt) = _loadValidatedNote(inputNotes[i]);

            bytes32 commitment = _computeNoteCommitmentUnchecked(noteValue, noteOwner, noteSalt);
            if (!commitmentExists[commitment]) {
                revert UnknownCommitment(commitment);
            }

            _requireNoteOwner(noteOwner);
            nullifiers[i] = _computeNullifierUnchecked(noteValue, noteOwner, noteSalt);
            totalInputValue += noteValue;
        }

        if (totalInputValue != totalOutputValue) {
            revert InputOutputValueMismatch(totalInputValue, totalOutputValue);
        }

        for (uint256 i = 0; i < 2; ++i) {
            _useNullifier(nullifiers[i]);
        }

        _registerTransferOutputs(outputs, outputCommitments);
    }

    function transferNotes3To1(Note[3] calldata inputNotes, Note[1] calldata outputs)
        external
        returns (bytes32[3] memory nullifiers, bytes32[1] memory outputCommitments)
    {
        uint256 totalOutputValue = _validateTransferOutputs(outputs);
        uint256 totalInputValue;

        for (uint256 i = 0; i < 3; ++i) {
            (address noteOwner, uint256 noteValue, bytes32 noteSalt) = _loadValidatedNote(inputNotes[i]);

            bytes32 commitment = _computeNoteCommitmentUnchecked(noteValue, noteOwner, noteSalt);
            if (!commitmentExists[commitment]) {
                revert UnknownCommitment(commitment);
            }

            _requireNoteOwner(noteOwner);
            nullifiers[i] = _computeNullifierUnchecked(noteValue, noteOwner, noteSalt);
            totalInputValue += noteValue;
        }

        if (totalInputValue != totalOutputValue) {
            revert InputOutputValueMismatch(totalInputValue, totalOutputValue);
        }

        for (uint256 i = 0; i < 3; ++i) {
            _useNullifier(nullifiers[i]);
        }

        _registerTransferOutputs(outputs, outputCommitments);
    }

    function transferNotes3To2(Note[3] calldata inputNotes, Note[2] calldata outputs)
        external
        returns (bytes32[3] memory nullifiers, bytes32[2] memory outputCommitments)
    {
        (address output0Owner, uint256 output0Value, bytes32 output0Salt) = _loadValidatedNote(outputs[0]);
        (address output1Owner, uint256 output1Value, bytes32 output1Salt) = _loadValidatedNote(outputs[1]);
        uint256 totalOutputValue = output0Value + output1Value;

        (address note0Owner, uint256 note0Value, bytes32 note0Salt) = _loadValidatedNote(inputNotes[0]);
        bytes32 commitment0 = _computeNoteCommitmentUnchecked(note0Value, note0Owner, note0Salt);
        if (!commitmentExists[commitment0]) {
            revert UnknownCommitment(commitment0);
        }
        _requireNoteOwner(note0Owner);
        nullifiers[0] = _computeNullifierUnchecked(note0Value, note0Owner, note0Salt);
        _useNullifier(nullifiers[0]);

        (address note1Owner, uint256 note1Value, bytes32 note1Salt) = _loadValidatedNote(inputNotes[1]);
        bytes32 commitment1 = _computeNoteCommitmentUnchecked(note1Value, note1Owner, note1Salt);
        if (!commitmentExists[commitment1]) {
            revert UnknownCommitment(commitment1);
        }
        _requireNoteOwner(note1Owner);
        nullifiers[1] = _computeNullifierUnchecked(note1Value, note1Owner, note1Salt);
        _useNullifier(nullifiers[1]);

        (address note2Owner, uint256 note2Value, bytes32 note2Salt) = _loadValidatedNote(inputNotes[2]);
        bytes32 commitment2 = _computeNoteCommitmentUnchecked(note2Value, note2Owner, note2Salt);
        if (!commitmentExists[commitment2]) {
            revert UnknownCommitment(commitment2);
        }
        _requireNoteOwner(note2Owner);
        nullifiers[2] = _computeNullifierUnchecked(note2Value, note2Owner, note2Salt);
        _useNullifier(nullifiers[2]);

        uint256 totalInputValue = note0Value + note1Value + note2Value;
        if (totalInputValue != totalOutputValue) {
            revert InputOutputValueMismatch(totalInputValue, totalOutputValue);
        }

        bytes32 output0Commitment = _computeNoteCommitmentUnchecked(output0Value, output0Owner, output0Salt);
        outputCommitments[0] = output0Commitment;
        _registerCommitment(output0Commitment);

        bytes32 output1Commitment = _computeNoteCommitmentUnchecked(output1Value, output1Owner, output1Salt);
        outputCommitments[1] = output1Commitment;
        _registerCommitment(output1Commitment);
    }

    function transferNotes4To1(Note[4] calldata inputNotes, Note[1] calldata outputs)
        external
        returns (bytes32[4] memory nullifiers, bytes32[1] memory outputCommitments)
    {
        uint256 totalOutputValue = _validateTransferOutputs(outputs);
        uint256 totalInputValue;

        for (uint256 i = 0; i < 4; ++i) {
            (address noteOwner, uint256 noteValue, bytes32 noteSalt) = _loadValidatedNote(inputNotes[i]);

            bytes32 commitment = _computeNoteCommitmentUnchecked(noteValue, noteOwner, noteSalt);
            if (!commitmentExists[commitment]) {
                revert UnknownCommitment(commitment);
            }

            _requireNoteOwner(noteOwner);
            nullifiers[i] = _computeNullifierUnchecked(noteValue, noteOwner, noteSalt);
            totalInputValue += noteValue;
        }

        if (totalInputValue != totalOutputValue) {
            revert InputOutputValueMismatch(totalInputValue, totalOutputValue);
        }

        for (uint256 i = 0; i < 4; ++i) {
            _useNullifier(nullifiers[i]);
        }

        _registerTransferOutputs(outputs, outputCommitments);
    }

    function transferNotes4To2(Note[4] calldata inputNotes, Note[2] calldata outputs)
        external
        returns (bytes32[4] memory nullifiers, bytes32[2] memory outputCommitments)
    {
        uint256 totalOutputValue = _validateTransferOutputs(outputs);
        uint256 totalInputValue;

        for (uint256 i = 0; i < 4; ++i) {
            (address noteOwner, uint256 noteValue, bytes32 noteSalt) = _loadValidatedNote(inputNotes[i]);

            bytes32 commitment = _computeNoteCommitmentUnchecked(noteValue, noteOwner, noteSalt);
            if (!commitmentExists[commitment]) {
                revert UnknownCommitment(commitment);
            }

            _requireNoteOwner(noteOwner);
            nullifiers[i] = _computeNullifierUnchecked(noteValue, noteOwner, noteSalt);
            totalInputValue += noteValue;
        }

        if (totalInputValue != totalOutputValue) {
            revert InputOutputValueMismatch(totalInputValue, totalOutputValue);
        }

        for (uint256 i = 0; i < 4; ++i) {
            _useNullifier(nullifiers[i]);
        }

        _registerTransferOutputs(outputs, outputCommitments);
    }

    function transferNotes5To1(Note[5] calldata inputNotes, Note[1] calldata outputs)
        external
        returns (bytes32[5] memory nullifiers, bytes32[1] memory outputCommitments)
    {
        uint256 totalOutputValue = _validateTransferOutputs(outputs);
        uint256 totalInputValue;

        for (uint256 i = 0; i < 5; ++i) {
            (address noteOwner, uint256 noteValue, bytes32 noteSalt) = _loadValidatedNote(inputNotes[i]);

            bytes32 commitment = _computeNoteCommitmentUnchecked(noteValue, noteOwner, noteSalt);
            if (!commitmentExists[commitment]) {
                revert UnknownCommitment(commitment);
            }

            _requireNoteOwner(noteOwner);
            nullifiers[i] = _computeNullifierUnchecked(noteValue, noteOwner, noteSalt);
            totalInputValue += noteValue;
        }

        if (totalInputValue != totalOutputValue) {
            revert InputOutputValueMismatch(totalInputValue, totalOutputValue);
        }

        for (uint256 i = 0; i < 5; ++i) {
            _useNullifier(nullifiers[i]);
        }

        _registerTransferOutputs(outputs, outputCommitments);
    }

    function transferNotes5To2(Note[5] calldata inputNotes, Note[2] calldata outputs)
        external
        returns (bytes32[5] memory nullifiers, bytes32[2] memory outputCommitments)
    {
        uint256 totalOutputValue = _validateTransferOutputs(outputs);
        uint256 totalInputValue;

        for (uint256 i = 0; i < 5; ++i) {
            (address noteOwner, uint256 noteValue, bytes32 noteSalt) = _loadValidatedNote(inputNotes[i]);

            bytes32 commitment = _computeNoteCommitmentUnchecked(noteValue, noteOwner, noteSalt);
            if (!commitmentExists[commitment]) {
                revert UnknownCommitment(commitment);
            }

            _requireNoteOwner(noteOwner);
            nullifiers[i] = _computeNullifierUnchecked(noteValue, noteOwner, noteSalt);
            totalInputValue += noteValue;
        }

        if (totalInputValue != totalOutputValue) {
            revert InputOutputValueMismatch(totalInputValue, totalOutputValue);
        }

        for (uint256 i = 0; i < 5; ++i) {
            _useNullifier(nullifiers[i]);
        }

        _registerTransferOutputs(outputs, outputCommitments);
    }

    function transferNotes6To1(Note[6] calldata inputNotes, Note[1] calldata outputs)
        external
        returns (bytes32[6] memory nullifiers, bytes32[1] memory outputCommitments)
    {
        uint256 totalOutputValue = _validateTransferOutputs(outputs);
        uint256 totalInputValue;

        for (uint256 i = 0; i < 6; ++i) {
            (address noteOwner, uint256 noteValue, bytes32 noteSalt) = _loadValidatedNote(inputNotes[i]);

            bytes32 commitment = _computeNoteCommitmentUnchecked(noteValue, noteOwner, noteSalt);
            if (!commitmentExists[commitment]) {
                revert UnknownCommitment(commitment);
            }

            _requireNoteOwner(noteOwner);
            nullifiers[i] = _computeNullifierUnchecked(noteValue, noteOwner, noteSalt);
            totalInputValue += noteValue;
        }

        if (totalInputValue != totalOutputValue) {
            revert InputOutputValueMismatch(totalInputValue, totalOutputValue);
        }

        for (uint256 i = 0; i < 6; ++i) {
            _useNullifier(nullifiers[i]);
        }

        _registerTransferOutputs(outputs, outputCommitments);
    }

    function transferNotes6To2(Note[6] calldata inputNotes, Note[2] calldata outputs)
        external
        returns (bytes32[6] memory nullifiers, bytes32[2] memory outputCommitments)
    {
        uint256 totalOutputValue = _validateTransferOutputs(outputs);
        uint256 totalInputValue;

        for (uint256 i = 0; i < 6; ++i) {
            (address noteOwner, uint256 noteValue, bytes32 noteSalt) = _loadValidatedNote(inputNotes[i]);

            bytes32 commitment = _computeNoteCommitmentUnchecked(noteValue, noteOwner, noteSalt);
            if (!commitmentExists[commitment]) {
                revert UnknownCommitment(commitment);
            }

            _requireNoteOwner(noteOwner);
            nullifiers[i] = _computeNullifierUnchecked(noteValue, noteOwner, noteSalt);
            totalInputValue += noteValue;
        }

        if (totalInputValue != totalOutputValue) {
            revert InputOutputValueMismatch(totalInputValue, totalOutputValue);
        }

        for (uint256 i = 0; i < 6; ++i) {
            _useNullifier(nullifiers[i]);
        }

        _registerTransferOutputs(outputs, outputCommitments);
    }

    function transferNotes7To1(Note[7] calldata inputNotes, Note[1] calldata outputs)
        external
        returns (bytes32[7] memory nullifiers, bytes32[1] memory outputCommitments)
    {
        uint256 totalOutputValue = _validateTransferOutputs(outputs);
        uint256 totalInputValue;

        for (uint256 i = 0; i < 7; ++i) {
            (address noteOwner, uint256 noteValue, bytes32 noteSalt) = _loadValidatedNote(inputNotes[i]);

            bytes32 commitment = _computeNoteCommitmentUnchecked(noteValue, noteOwner, noteSalt);
            if (!commitmentExists[commitment]) {
                revert UnknownCommitment(commitment);
            }

            _requireNoteOwner(noteOwner);
            nullifiers[i] = _computeNullifierUnchecked(noteValue, noteOwner, noteSalt);
            totalInputValue += noteValue;
        }

        if (totalInputValue != totalOutputValue) {
            revert InputOutputValueMismatch(totalInputValue, totalOutputValue);
        }

        for (uint256 i = 0; i < 7; ++i) {
            _useNullifier(nullifiers[i]);
        }

        _registerTransferOutputs(outputs, outputCommitments);
    }

    function transferNotes7To2(Note[7] calldata inputNotes, Note[2] calldata outputs)
        external
        returns (bytes32[7] memory nullifiers, bytes32[2] memory outputCommitments)
    {
        uint256 totalOutputValue = _validateTransferOutputs(outputs);
        uint256 totalInputValue;

        for (uint256 i = 0; i < 7; ++i) {
            (address noteOwner, uint256 noteValue, bytes32 noteSalt) = _loadValidatedNote(inputNotes[i]);

            bytes32 commitment = _computeNoteCommitmentUnchecked(noteValue, noteOwner, noteSalt);
            if (!commitmentExists[commitment]) {
                revert UnknownCommitment(commitment);
            }

            _requireNoteOwner(noteOwner);
            nullifiers[i] = _computeNullifierUnchecked(noteValue, noteOwner, noteSalt);
            totalInputValue += noteValue;
        }

        if (totalInputValue != totalOutputValue) {
            revert InputOutputValueMismatch(totalInputValue, totalOutputValue);
        }

        for (uint256 i = 0; i < 7; ++i) {
            _useNullifier(nullifiers[i]);
        }

        _registerTransferOutputs(outputs, outputCommitments);
    }

    function transferNotes8To1(Note[8] calldata inputNotes, Note[1] calldata outputs)
        external
        returns (bytes32[8] memory nullifiers, bytes32[1] memory outputCommitments)
    {
        uint256 totalOutputValue = _validateTransferOutputs(outputs);
        uint256 totalInputValue;

        for (uint256 i = 0; i < 8; ++i) {
            (address noteOwner, uint256 noteValue, bytes32 noteSalt) = _loadValidatedNote(inputNotes[i]);

            bytes32 commitment = _computeNoteCommitmentUnchecked(noteValue, noteOwner, noteSalt);
            if (!commitmentExists[commitment]) {
                revert UnknownCommitment(commitment);
            }

            _requireNoteOwner(noteOwner);
            nullifiers[i] = _computeNullifierUnchecked(noteValue, noteOwner, noteSalt);
            totalInputValue += noteValue;
        }

        if (totalInputValue != totalOutputValue) {
            revert InputOutputValueMismatch(totalInputValue, totalOutputValue);
        }

        for (uint256 i = 0; i < 8; ++i) {
            _useNullifier(nullifiers[i]);
        }

        _registerTransferOutputs(outputs, outputCommitments);
    }

    function transferNotes8To2(Note[8] calldata inputNotes, Note[2] calldata outputs)
        external
        returns (bytes32[8] memory nullifiers, bytes32[2] memory outputCommitments)
    {
        uint256 totalOutputValue = _validateTransferOutputs(outputs);
        uint256 totalInputValue;

        for (uint256 i = 0; i < 8; ++i) {
            (address noteOwner, uint256 noteValue, bytes32 noteSalt) = _loadValidatedNote(inputNotes[i]);

            bytes32 commitment = _computeNoteCommitmentUnchecked(noteValue, noteOwner, noteSalt);
            if (!commitmentExists[commitment]) {
                revert UnknownCommitment(commitment);
            }

            _requireNoteOwner(noteOwner);
            nullifiers[i] = _computeNullifierUnchecked(noteValue, noteOwner, noteSalt);
            totalInputValue += noteValue;
        }

        if (totalInputValue != totalOutputValue) {
            revert InputOutputValueMismatch(totalInputValue, totalOutputValue);
        }

        for (uint256 i = 0; i < 8; ++i) {
            _useNullifier(nullifiers[i]);
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
        for (uint256 i = 0; i < 4; ++i) {
            (address noteOwner, uint256 noteValue, bytes32 noteSalt) = _loadValidatedNote(inputNotes[i]);

            bytes32 commitment = _computeNoteCommitmentUnchecked(noteValue, noteOwner, noteSalt);
            if (!commitmentExists[commitment]) {
                revert UnknownCommitment(commitment);
            }

            _requireNoteOwner(noteOwner);
            nullifiers[i] = _computeNullifierUnchecked(noteValue, noteOwner, noteSalt);
        }

        for (uint256 i = 0; i < 4; ++i) {
            _useNullifier(nullifiers[i]);
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
        for (uint256 i = 0; i < 6; ++i) {
            (address noteOwner, uint256 noteValue, bytes32 noteSalt) = _loadValidatedNote(inputNotes[i]);

            bytes32 commitment = _computeNoteCommitmentUnchecked(noteValue, noteOwner, noteSalt);
            if (!commitmentExists[commitment]) {
                revert UnknownCommitment(commitment);
            }

            _requireNoteOwner(noteOwner);
            nullifiers[i] = _computeNullifierUnchecked(noteValue, noteOwner, noteSalt);
        }

        for (uint256 i = 0; i < 6; ++i) {
            _useNullifier(nullifiers[i]);
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
        for (uint256 i = 0; i < 8; ++i) {
            (address noteOwner, uint256 noteValue, bytes32 noteSalt) = _loadValidatedNote(inputNotes[i]);

            bytes32 commitment = _computeNoteCommitmentUnchecked(noteValue, noteOwner, noteSalt);
            if (!commitmentExists[commitment]) {
                revert UnknownCommitment(commitment);
            }

            _requireNoteOwner(noteOwner);
            nullifiers[i] = _computeNullifierUnchecked(noteValue, noteOwner, noteSalt);
        }

        for (uint256 i = 0; i < 8; ++i) {
            _useNullifier(nullifiers[i]);
            l2AccountingVault.creditLiquidBalance(receiver, inputNotes[i].value);
        }

        emit NotesRedeemed(msg.sender, receiver, 8);
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

    function _validateTransferOutputs(Note[1] calldata outputs) internal pure returns (uint256 totalOutputValue) {
        (, totalOutputValue,) = _loadValidatedNote(outputs[0]);
    }

    function _validateTransferOutputs(Note[2] calldata outputs) internal pure returns (uint256 totalOutputValue) {
        for (uint256 i = 0; i < 2; ++i) {
            (, uint256 outputValue,) = _loadValidatedNote(outputs[i]);
            totalOutputValue += outputValue;
        }
    }

    function _registerTransferOutputs(Note[1] calldata outputs, bytes32[1] memory outputCommitments) internal {
        (address outputOwner, uint256 outputValue, bytes32 outputSalt) = _loadValidatedNote(outputs[0]);
        bytes32 commitment = _computeNoteCommitmentUnchecked(outputValue, outputOwner, outputSalt);
        outputCommitments[0] = commitment;
        _registerCommitment(commitment);
    }

    function _registerTransferOutputs(Note[2] calldata outputs, bytes32[2] memory outputCommitments) internal {
        for (uint256 i = 0; i < 2; ++i) {
            (address outputOwner, uint256 outputValue, bytes32 outputSalt) = _loadValidatedNote(outputs[i]);
            bytes32 commitment = _computeNoteCommitmentUnchecked(outputValue, outputOwner, outputSalt);
            outputCommitments[i] = commitment;
            _registerCommitment(commitment);
        }
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

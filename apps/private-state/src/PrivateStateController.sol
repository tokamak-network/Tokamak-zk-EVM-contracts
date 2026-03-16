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

    function transferNotes2To1(Note[2] calldata inputNotes, Note[1] calldata outputs)
        external
        returns (bytes32[2] memory nullifiers, bytes32[1] memory outputCommitments)
    {
        uint256 totalOutputValue;
        (totalOutputValue, outputCommitments[0]) = _prepareTransferOutput(outputs[0]);

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
        (output0Value, outputCommitments[0]) = _prepareTransferOutput(outputs[0]);
        (output1Value, outputCommitments[1]) = _prepareTransferOutput(outputs[1]);
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
        (totalOutputValue, outputCommitments[0]) = _prepareTransferOutput(outputs[0]);

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
        (address output0Owner, uint256 output0Value, bytes32 output0Salt) = _loadValidatedNote(outputs[0]);
        (address output1Owner, uint256 output1Value, bytes32 output1Salt) = _loadValidatedNote(outputs[1]);
        uint256 totalOutputValue = output0Value + output1Value;

        uint256 note0Value;
        (note0Value, nullifiers[0]) = _prepareSpendableNote(inputNotes[0]);
        _useNullifier(nullifiers[0]);

        uint256 note1Value;
        (note1Value, nullifiers[1]) = _prepareSpendableNote(inputNotes[1]);
        _useNullifier(nullifiers[1]);

        uint256 note2Value;
        (note2Value, nullifiers[2]) = _prepareSpendableNote(inputNotes[2]);
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
        uint256 totalOutputValue;
        (totalOutputValue, outputCommitments[0]) = _prepareTransferOutput(outputs[0]);

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
            l2AccountingVault.creditLiquidBalance(receiver, noteValue);
        }
        {
            uint256 noteValue;
            bytes32 nullifier;
            (noteValue, nullifier) = _prepareSpendableNote(inputNotes[1]);
            nullifiers[1] = nullifier;
            _useNullifier(nullifier);
            l2AccountingVault.creditLiquidBalance(receiver, noteValue);
        }
        {
            uint256 noteValue;
            bytes32 nullifier;
            (noteValue, nullifier) = _prepareSpendableNote(inputNotes[2]);
            nullifiers[2] = nullifier;
            _useNullifier(nullifier);
            l2AccountingVault.creditLiquidBalance(receiver, noteValue);
        }
        {
            uint256 noteValue;
            bytes32 nullifier;
            (noteValue, nullifier) = _prepareSpendableNote(inputNotes[3]);
            nullifiers[3] = nullifier;
            _useNullifier(nullifier);
            l2AccountingVault.creditLiquidBalance(receiver, noteValue);
        }

        emit NotesRedeemed(msg.sender, receiver, 4);
    }

    function redeemNotes6(Note[6] calldata inputNotes, address receiver)
        external
        returns (bytes32[6] memory nullifiers)
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
        {
            uint256 noteValue;
            bytes32 nullifier;
            (noteValue, nullifier) = _prepareSpendableNote(inputNotes[1]);
            nullifiers[1] = nullifier;
            _useNullifier(nullifier);
            l2AccountingVault.creditLiquidBalance(receiver, noteValue);
        }
        {
            uint256 noteValue;
            bytes32 nullifier;
            (noteValue, nullifier) = _prepareSpendableNote(inputNotes[2]);
            nullifiers[2] = nullifier;
            _useNullifier(nullifier);
            l2AccountingVault.creditLiquidBalance(receiver, noteValue);
        }
        {
            uint256 noteValue;
            bytes32 nullifier;
            (noteValue, nullifier) = _prepareSpendableNote(inputNotes[3]);
            nullifiers[3] = nullifier;
            _useNullifier(nullifier);
            l2AccountingVault.creditLiquidBalance(receiver, noteValue);
        }
        {
            uint256 noteValue;
            bytes32 nullifier;
            (noteValue, nullifier) = _prepareSpendableNote(inputNotes[4]);
            nullifiers[4] = nullifier;
            _useNullifier(nullifier);
            l2AccountingVault.creditLiquidBalance(receiver, noteValue);
        }
        {
            uint256 noteValue;
            bytes32 nullifier;
            (noteValue, nullifier) = _prepareSpendableNote(inputNotes[5]);
            nullifiers[5] = nullifier;
            _useNullifier(nullifier);
            l2AccountingVault.creditLiquidBalance(receiver, noteValue);
        }

        emit NotesRedeemed(msg.sender, receiver, 6);
    }

    function redeemNotes8(Note[8] calldata inputNotes, address receiver)
        external
        returns (bytes32[8] memory nullifiers)
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
        {
            uint256 noteValue;
            bytes32 nullifier;
            (noteValue, nullifier) = _prepareSpendableNote(inputNotes[1]);
            nullifiers[1] = nullifier;
            _useNullifier(nullifier);
            l2AccountingVault.creditLiquidBalance(receiver, noteValue);
        }
        {
            uint256 noteValue;
            bytes32 nullifier;
            (noteValue, nullifier) = _prepareSpendableNote(inputNotes[2]);
            nullifiers[2] = nullifier;
            _useNullifier(nullifier);
            l2AccountingVault.creditLiquidBalance(receiver, noteValue);
        }
        {
            uint256 noteValue;
            bytes32 nullifier;
            (noteValue, nullifier) = _prepareSpendableNote(inputNotes[3]);
            nullifiers[3] = nullifier;
            _useNullifier(nullifier);
            l2AccountingVault.creditLiquidBalance(receiver, noteValue);
        }
        {
            uint256 noteValue;
            bytes32 nullifier;
            (noteValue, nullifier) = _prepareSpendableNote(inputNotes[4]);
            nullifiers[4] = nullifier;
            _useNullifier(nullifier);
            l2AccountingVault.creditLiquidBalance(receiver, noteValue);
        }
        {
            uint256 noteValue;
            bytes32 nullifier;
            (noteValue, nullifier) = _prepareSpendableNote(inputNotes[5]);
            nullifiers[5] = nullifier;
            _useNullifier(nullifier);
            l2AccountingVault.creditLiquidBalance(receiver, noteValue);
        }
        {
            uint256 noteValue;
            bytes32 nullifier;
            (noteValue, nullifier) = _prepareSpendableNote(inputNotes[6]);
            nullifiers[6] = nullifier;
            _useNullifier(nullifier);
            l2AccountingVault.creditLiquidBalance(receiver, noteValue);
        }
        {
            uint256 noteValue;
            bytes32 nullifier;
            (noteValue, nullifier) = _prepareSpendableNote(inputNotes[7]);
            nullifiers[7] = nullifier;
            _useNullifier(nullifier);
            l2AccountingVault.creditLiquidBalance(receiver, noteValue);
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

    function _prepareTransferOutput(Note calldata outputNote)
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

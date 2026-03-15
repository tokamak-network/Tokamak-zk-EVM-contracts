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
        _validateNoteFields(outputs[0].value, outputs[0].owner);

        l2AccountingVault.debitLiquidBalance(msg.sender, outputs[0].value);
        commitments[0] = _mintOutputNote(msg.sender, outputs[0]);
    }

    function mintNotes2(Note[2] calldata outputs) external returns (bytes32[2] memory commitments) {
        _validateNoteFields(outputs[0].value, outputs[0].owner);
        _validateNoteFields(outputs[1].value, outputs[1].owner);

        uint256 totalValue = outputs[0].value + outputs[1].value;
        l2AccountingVault.debitLiquidBalance(msg.sender, totalValue);

        commitments[0] = _mintOutputNote(msg.sender, outputs[0]);
        commitments[1] = _mintOutputNote(msg.sender, outputs[1]);
    }

    function mintNotes3(Note[3] calldata outputs) external returns (bytes32[3] memory commitments) {
        _validateNoteFields(outputs[0].value, outputs[0].owner);
        _validateNoteFields(outputs[1].value, outputs[1].owner);
        _validateNoteFields(outputs[2].value, outputs[2].owner);

        uint256 totalValue = outputs[0].value + outputs[1].value + outputs[2].value;
        l2AccountingVault.debitLiquidBalance(msg.sender, totalValue);

        commitments[0] = _mintOutputNote(msg.sender, outputs[0]);
        commitments[1] = _mintOutputNote(msg.sender, outputs[1]);
        commitments[2] = _mintOutputNote(msg.sender, outputs[2]);
    }

    function transferNotes1(Note[1] calldata inputNotes, Note[3] calldata outputs)
        external
        returns (bytes32[1] memory nullifiers, bytes32[3] memory outputCommitments)
    {
        uint256 totalOutputValue = _validateTransferOutputs(outputs);
        Note calldata note = inputNotes[0];
        _validateNoteFields(note.value, note.owner);

        bytes32 commitment = _computeNoteCommitmentUnchecked(note.value, note.owner, note.salt);
        if (!noteRegistry.commitmentExists(commitment)) {
            revert UnknownCommitment(commitment);
        }

        _requireNoteOwner(note.owner);
        if (note.value != totalOutputValue) {
            revert InputOutputValueMismatch(note.value, totalOutputValue);
        }

        nullifiers[0] = _computeNullifierUnchecked(note.value, note.owner, note.salt);
        nullifierStore.useNullifier(nullifiers[0], commitment, msg.sender);
        _registerTransferOutputs(outputs, outputCommitments);
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

            bytes32 commitment = _computeNoteCommitmentUnchecked(note.value, note.owner, note.salt);
            if (!noteRegistry.commitmentExists(commitment)) {
                revert UnknownCommitment(commitment);
            }

            _requireNoteOwner(note.owner);
            commitments[i] = commitment;
            nullifiers[i] = _computeNullifierUnchecked(note.value, note.owner, note.salt);
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

            bytes32 commitment = _computeNoteCommitmentUnchecked(note.value, note.owner, note.salt);
            if (!noteRegistry.commitmentExists(commitment)) {
                revert UnknownCommitment(commitment);
            }

            _requireNoteOwner(note.owner);
            commitments[i] = commitment;
            nullifiers[i] = _computeNullifierUnchecked(note.value, note.owner, note.salt);
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

            bytes32 commitment = _computeNoteCommitmentUnchecked(note.value, note.owner, note.salt);
            if (!noteRegistry.commitmentExists(commitment)) {
                revert UnknownCommitment(commitment);
            }

            _requireNoteOwner(note.owner);
            commitments[i] = commitment;
            nullifiers[i] = _computeNullifierUnchecked(note.value, note.owner, note.salt);
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
        Note[] memory dynamicInputs = _copyNotes4(inputNotes);
        bytes32[] memory dynamicNullifiers = _redeemFixedNotes(dynamicInputs, receiver);
        for (uint256 i = 0; i < 4; ++i) {
            nullifiers[i] = dynamicNullifiers[i];
        }
    }

    function redeemNotes6(Note[6] calldata inputNotes, address receiver)
        external
        returns (bytes32[6] memory nullifiers)
    {
        Note[] memory dynamicInputs = _copyNotes6(inputNotes);
        bytes32[] memory dynamicNullifiers = _redeemFixedNotes(dynamicInputs, receiver);
        for (uint256 i = 0; i < 6; ++i) {
            nullifiers[i] = dynamicNullifiers[i];
        }
    }

    function redeemNotes8(Note[8] calldata inputNotes, address receiver)
        external
        returns (bytes32[8] memory nullifiers)
    {
        Note[] memory dynamicInputs = _copyNotes8(inputNotes);
        bytes32[] memory dynamicNullifiers = _redeemFixedNotes(dynamicInputs, receiver);
        for (uint256 i = 0; i < 8; ++i) {
            nullifiers[i] = dynamicNullifiers[i];
        }
    }

    function computeNoteCommitment(uint256 value, address owner, bytes32 salt) public view returns (bytes32) {
        _validateNoteFields(value, owner);
        return _computeNoteCommitmentUnchecked(value, owner, salt);
    }

    function computeNullifier(uint256 value, address owner, bytes32 salt) public view returns (bytes32) {
        _validateNoteFields(value, owner);
        return _computeNullifierUnchecked(value, owner, salt);
    }

    function _mintOutputNote(address liquidBalanceOwner, Note calldata output) internal returns (bytes32 commitment) {
        commitment = computeNoteCommitment(output.value, output.owner, output.salt);
        noteRegistry.registerCommitment(commitment);
        emit NoteMinted(liquidBalanceOwner, commitment, output.owner, output.value);
    }

    function _redeemFixedNotes(Note[] memory inputNotes, address receiver)
        internal
        returns (bytes32[] memory nullifiers)
    {
        if (receiver == address(0)) {
            revert ZeroAddress();
        }

        bytes32[] memory inputCommitments = new bytes32[](inputNotes.length);
        nullifiers = new bytes32[](inputNotes.length);
        for (uint256 i = 0; i < inputNotes.length; ++i) {
            Note memory note = inputNotes[i];
            _validateNoteFields(note.value, note.owner);

            bytes32 commitment = _computeNoteCommitmentUnchecked(note.value, note.owner, note.salt);
            if (!noteRegistry.commitmentExists(commitment)) {
                revert UnknownCommitment(commitment);
            }

            _requireNoteOwner(note.owner);
            inputCommitments[i] = commitment;
            nullifiers[i] = _computeNullifierUnchecked(note.value, note.owner, note.salt);
        }

        for (uint256 i = 0; i < inputNotes.length; ++i) {
            nullifierStore.useNullifier(nullifiers[i], inputCommitments[i], msg.sender);
            l2AccountingVault.creditLiquidBalance(receiver, inputNotes[i].value);
        }

        emit NotesRedeemed(msg.sender, receiver, inputNotes.length);
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
        return keccak256(abi.encode(block.chainid, address(noteRegistry), canonicalAsset, value, owner, salt));
    }

    function _computeNullifierUnchecked(uint256 value, address owner, bytes32 salt) internal view returns (bytes32) {
        return keccak256(abi.encode(block.chainid, address(nullifierStore), canonicalAsset, value, owner, salt));
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

    function _copyNotes4(Note[4] calldata inputNotes) internal pure returns (Note[] memory copied) {
        copied = new Note[](4);
        for (uint256 i = 0; i < 4; ++i) {
            copied[i] = inputNotes[i];
        }
    }

    function _copyNotes6(Note[6] calldata inputNotes) internal pure returns (Note[] memory copied) {
        copied = new Note[](6);
        for (uint256 i = 0; i < 6; ++i) {
            copied[i] = inputNotes[i];
        }
    }

    function _copyNotes8(Note[8] calldata inputNotes) internal pure returns (Note[] memory copied) {
        copied = new Note[](8);
        for (uint256 i = 0; i < 8; ++i) {
            copied[i] = inputNotes[i];
        }
    }

}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import "forge-std/Test.sol";
import {L2AccountingVault} from "../../apps/private-state/src/L2AccountingVault.sol";
import {PrivateStateController} from "../../apps/private-state/src/PrivateStateController.sol";
import {PrivateStateDeploymentFactory} from "../../apps/private-state/scripts/deploy/PrivateStateDeploymentFactory.sol";

contract PrivateStateControllerTest is Test {
    uint256 private constant BLS12_381_SCALAR_FIELD_ORDER =
        52435875175126190479447740508185965837690552500527637822603658699938581184512;
    uint256 private constant MAX_LIQUID_BALANCE = BLS12_381_SCALAR_FIELD_ORDER - 1;

    address private alice = makeAddr("alice");
    address private bob = makeAddr("bob");
    address private mallory = makeAddr("mallory");
    bytes32 private constant L2_ACCOUNTING_VAULT_SALT = keccak256("private-state.l2-accounting-vault");

    L2AccountingVault private l2AccountingVault;
    PrivateStateController private controller;
    PrivateStateDeploymentFactory private deploymentFactory;

    bytes32 private constant NOTE_VALUE_ENCRYPTED_TOPIC = keccak256("NoteValueEncrypted(bytes32[3])");
    bytes32 private constant STORAGE_KEY_OBSERVED_TOPIC = keccak256("StorageKeyObserved(bytes32)");
    bytes32 private constant LIQUID_BALANCE_STORAGE_WRITE_OBSERVED_TOPIC =
        keccak256("LiquidBalanceStorageWriteObserved(address,bytes32)");
    uint256 private constant COMMITMENT_EXISTS_SLOT = 0;
    uint256 private constant NULLIFIER_USED_SLOT = 1;

    function setUp() public {
        deploymentFactory = new PrivateStateDeploymentFactory();

        address predictedController = vm.computeCreateAddress(address(deploymentFactory), 1);
        address predictedL2AccountingVault = vm.computeCreate2Address(
            L2_ACCOUNTING_VAULT_SALT, _l2AccountingVaultInitCodeHash(predictedController), address(deploymentFactory)
        );

        controller = deploymentFactory.deployController(predictedL2AccountingVault);
        l2AccountingVault = deploymentFactory.deployL2AccountingVault(L2_ACCOUNTING_VAULT_SALT, predictedController);

        assertEq(address(controller), predictedController);
        assertEq(address(l2AccountingVault), predictedL2AccountingVault);
    }

    function testTransferNotes4To1RedeemAndDrainLiquidBalance() public {
        _seedLiquidBalance(alice, 100 ether);

        assertEq(l2AccountingVault.liquidBalances(alice), 100 ether);

        PrivateStateController.Note memory note0 = _mintNote(alice, 10 ether, bytes32("alice-4-0"));
        PrivateStateController.Note memory note1 = _mintNote(alice, 15 ether, bytes32("alice-4-1"));
        PrivateStateController.Note memory note2 = _mintNote(alice, 20 ether, bytes32("alice-4-2"));
        PrivateStateController.Note memory note3 = _mintNote(alice, 15 ether, bytes32("alice-4-3"));

        assertEq(l2AccountingVault.liquidBalances(alice), 40 ether);

        PrivateStateController.Note[4] memory inputNotes = _notes4(note0, note1, note2, note3);
        PrivateStateController.TransferOutput[1] memory outputs =
            _transferOutputArray1(_transferOutput(bob, 60 ether, "bob-4-0"));

        vm.prank(alice);
        (bytes32[4] memory nullifiers, bytes32[1] memory outputCommitments) =
            controller.transferNotes4To1(outputs, inputNotes);

        for (uint256 i = 0; i < 4; ++i) {
            assertTrue(controller.nullifierUsed(nullifiers[i]));
        }
        assertTrue(controller.commitmentExists(outputCommitments[0]));

        _seedLiquidBalance(bob, 30 ether);

        vm.startPrank(bob);
        controller.mintNotes1(_mintOutputArray1(_mintOutput(_note(bob, 30 ether, bytes32("bob-4-dummy-1")))));
        controller.redeemNotes2(
            _notes2(_noteFromTransferOutput(outputs[0]), _note(bob, 30 ether, bytes32("bob-4-dummy-1"))), bob
        );
        vm.stopPrank();

        assertEq(l2AccountingVault.liquidBalances(bob), 90 ether);

        _debitLiquidBalance(bob, 90 ether);

        assertEq(l2AccountingVault.liquidBalances(bob), 0);
    }

    function testTransferNoteFamiliesOwnerCanTransferDirectly() public {
        _seedLiquidBalance(alice, 800 ether);

        PrivateStateController.Note[1] memory inputNotes1To1 = _noteArray1(_mintNote(alice, 10 ether, bytes32("alice-1to1-0")));
        PrivateStateController.TransferOutput[1] memory outputs1To1 =
            _transferOutputArray1(_transferOutput(bob, 10 ether, "bob-1to1-0"));
        vm.prank(alice);
        (, bytes32[1] memory outputCommitments1To1) = controller.transferNotes1To1(outputs1To1, inputNotes1To1);
        _assertCommitmentsExist(outputCommitments1To1);

        PrivateStateController.Note[1] memory inputNotes1To2 = _noteArray1(_mintNote(alice, 20 ether, bytes32("alice-1to2-0")));
        PrivateStateController.TransferOutput[2] memory outputs1To2 = _transferOutputs2(
            _transferOutput(bob, 10 ether, "bob-1to2-0"),
            _transferOutput(alice, 10 ether, "alice-1to2-change-0")
        );
        vm.prank(alice);
        (, bytes32[2] memory outputCommitments1To2) = controller.transferNotes1To2(outputs1To2, inputNotes1To2);
        _assertCommitmentsExist(outputCommitments1To2);

        PrivateStateController.Note[1] memory inputNotes1To3 = _noteArray1(_mintNote(alice, 30 ether, bytes32("alice-1to3-0")));
        PrivateStateController.TransferOutput[3] memory outputs1To3 = _transferOutputs3(
            _transferOutput(bob, 10 ether, "bob-1to3-0"),
            _transferOutput(alice, 10 ether, "alice-1to3-change-0"),
            _transferOutput(alice, 10 ether, "alice-1to3-change-1")
        );
        vm.prank(alice);
        (, bytes32[3] memory outputCommitments1To3) = controller.transferNotes1To3(outputs1To3, inputNotes1To3);
        _assertCommitmentsExist(outputCommitments1To3);

        PrivateStateController.Note[2] memory inputNotes2To1 = _noteArray2(
            _mintNote(alice, 10 ether, bytes32("alice-2to1-0")), _mintNote(alice, 10 ether, bytes32("alice-2to1-1"))
        );
        PrivateStateController.TransferOutput[1] memory outputs2To1 =
            _transferOutputArray1(_transferOutput(bob, 20 ether, "bob-2to1-0"));
        vm.prank(alice);
        (, bytes32[1] memory outputCommitments2To1) = controller.transferNotes2To1(outputs2To1, inputNotes2To1);
        _assertCommitmentsExist(outputCommitments2To1);

        PrivateStateController.Note[2] memory inputNotes2To2 = _noteArray2(
            _mintNote(alice, 10 ether, bytes32("alice-2to2-0")), _mintNote(alice, 10 ether, bytes32("alice-2to2-1"))
        );
        PrivateStateController.TransferOutput[2] memory outputs2To2 = _transferOutputs2(
            _transferOutput(bob, 10 ether, "bob-2to2-0"),
            _transferOutput(alice, 10 ether, "alice-2to2-change-0")
        );
        vm.prank(alice);
        (, bytes32[2] memory outputCommitments2To2) = controller.transferNotes2To2(outputs2To2, inputNotes2To2);
        _assertCommitmentsExist(outputCommitments2To2);

        PrivateStateController.Note[3] memory inputNotes3To1 = _notes3(
            _mintNote(alice, 10 ether, bytes32("alice-3to1-0")),
            _mintNote(alice, 10 ether, bytes32("alice-3to1-1")),
            _mintNote(alice, 10 ether, bytes32("alice-3to1-2"))
        );
        PrivateStateController.TransferOutput[1] memory outputs3To1 =
            _transferOutputArray1(_transferOutput(bob, 30 ether, "bob-3to1-0"));
        vm.prank(alice);
        (, bytes32[1] memory outputCommitments3To1) = controller.transferNotes3To1(outputs3To1, inputNotes3To1);
        _assertCommitmentsExist(outputCommitments3To1);

        PrivateStateController.Note[3] memory inputNotes3To2 = _notes3(
            _mintNote(alice, 10 ether, bytes32("alice-3to2-0")),
            _mintNote(alice, 10 ether, bytes32("alice-3to2-1")),
            _mintNote(alice, 10 ether, bytes32("alice-3to2-2"))
        );
        PrivateStateController.TransferOutput[2] memory outputs3To2 = _transferOutputs2(
            _transferOutput(bob, 10 ether, "bob-3to2-0"),
            _transferOutput(alice, 20 ether, "alice-3to2-change-0")
        );
        vm.prank(alice);
        (, bytes32[2] memory outputCommitments3To2) = controller.transferNotes3To2(outputs3To2, inputNotes3To2);
        _assertCommitmentsExist(outputCommitments3To2);

        PrivateStateController.Note[4] memory inputNotes4To1 = _notes4(
            _mintNote(alice, 10 ether, bytes32("alice-4to1-0")),
            _mintNote(alice, 10 ether, bytes32("alice-4to1-1")),
            _mintNote(alice, 10 ether, bytes32("alice-4to1-2")),
            _mintNote(alice, 10 ether, bytes32("alice-4to1-3"))
        );
        PrivateStateController.TransferOutput[1] memory outputs4To1 =
            _transferOutputArray1(_transferOutput(bob, 40 ether, "bob-4to1-0"));
        vm.prank(alice);
        (, bytes32[1] memory outputCommitments4To1) = controller.transferNotes4To1(outputs4To1, inputNotes4To1);
        _assertCommitmentsExist(outputCommitments4To1);

    }

    function testTransferNotes4To1CannotTransferAnotherOwnersNotes() public {
        _seedLiquidBalance(alice, 40 ether);

        PrivateStateController.Note[4] memory inputNotes = _notes4(
            _mintNote(alice, 10 ether, bytes32("alice-4b-0")),
            _mintNote(alice, 10 ether, bytes32("alice-4b-1")),
            _mintNote(alice, 10 ether, bytes32("alice-4b-2")),
            _mintNote(alice, 10 ether, bytes32("alice-4b-3"))
        );
        PrivateStateController.TransferOutput[1] memory outputs =
            _transferOutputArray1(_transferOutput(bob, 40 ether, "bob-4b-0"));

        vm.expectRevert(abi.encodeWithSelector(PrivateStateController.UnauthorizedNoteOwner.selector, mallory, alice));
        vm.prank(mallory);
        controller.transferNotes4To1(outputs, inputNotes);
    }

    function testTransferNotes4To1CannotReplaySpentNotes() public {
        _seedLiquidBalance(alice, 40 ether);

        PrivateStateController.Note memory note0 = _mintNote(alice, 10 ether, bytes32("alice-4c-0"));
        PrivateStateController.Note memory note1 = _mintNote(alice, 10 ether, bytes32("alice-4c-1"));
        PrivateStateController.Note memory note2 = _mintNote(alice, 10 ether, bytes32("alice-4c-2"));
        PrivateStateController.Note memory note3 = _mintNote(alice, 10 ether, bytes32("alice-4c-3"));

        PrivateStateController.Note[4] memory inputNotes = _notes4(note0, note1, note2, note3);
        PrivateStateController.TransferOutput[1] memory outputs =
            _transferOutputArray1(_transferOutput(alice, 40 ether, "alice-4c-out-0"));

        vm.prank(alice);
        controller.transferNotes4To1(outputs, inputNotes);

        vm.expectRevert(
            abi.encodeWithSelector(PrivateStateController.NullifierAlreadyUsed.selector, _nullifierOf(note0))
        );
        vm.prank(alice);
        controller.transferNotes4To1(outputs, inputNotes);
    }

    function testTransferNotes4To1RejectsValueMismatch() public {
        _seedLiquidBalance(alice, 40 ether);

        PrivateStateController.Note[4] memory inputNotes = _notes4(
            _mintNote(alice, 10 ether, bytes32("alice-4d-0")),
            _mintNote(alice, 10 ether, bytes32("alice-4d-1")),
            _mintNote(alice, 10 ether, bytes32("alice-4d-2")),
            _mintNote(alice, 10 ether, bytes32("alice-4d-3"))
        );
        PrivateStateController.TransferOutput[1] memory outputs =
            _transferOutputArray1(_transferOutput(bob, 41 ether, "bob-4d-0"));

        vm.expectRevert(
            abi.encodeWithSelector(PrivateStateController.InputOutputValueMismatch.selector, 40 ether, 41 ether)
        );
        vm.prank(alice);
        controller.transferNotes4To1(outputs, inputNotes);
    }

    function testTransferNotes4To1UnknownCommitmentCannotBeSpent() public {
        PrivateStateController.Note[4] memory inputNotes = _notes4(
            _note(alice, 5 ether, bytes32("unknown-4-0")),
            _note(alice, 5 ether, bytes32("unknown-4-1")),
            _note(alice, 5 ether, bytes32("unknown-4-2")),
            _note(alice, 5 ether, bytes32("unknown-4-3"))
        );
        PrivateStateController.TransferOutput[1] memory outputs =
            _transferOutputArray1(_transferOutput(bob, 20 ether, "unknown-out-0"));
        bytes32 unknownCommitment = _commitmentOf(inputNotes[0]);

        vm.expectRevert(abi.encodeWithSelector(PrivateStateController.UnknownCommitment.selector, unknownCommitment));
        vm.prank(alice);
        controller.transferNotes4To1(outputs, inputNotes);
    }

    function testTransferNotes1To2EmitsCiphertextLogPerOutput() public {
        _seedLiquidBalance(alice, 20 ether);

        PrivateStateController.Note[1] memory inputNotes = _noteArray1(_mintNote(alice, 20 ether, bytes32("alice-event-1to2-0")));
        PrivateStateController.TransferOutput[2] memory outputs = _transferOutputs2(
            _transferOutput(bob, 7 ether, "bob-event-1to2-0"),
            _transferOutput(alice, 13 ether, "alice-event-1to2-change-0")
        );

        vm.recordLogs();
        vm.prank(alice);
        controller.transferNotes1To2(outputs, inputNotes);

        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 2);
        assertEq(entries[0].topics.length, 1);
        assertEq(entries[1].topics.length, 1);
        assertEq(entries[0].topics[0], NOTE_VALUE_ENCRYPTED_TOPIC);
        assertEq(entries[1].topics[0], NOTE_VALUE_ENCRYPTED_TOPIC);

        bytes32[3] memory event0 = abi.decode(entries[0].data, (bytes32[3]));
        bytes32[3] memory event1 = abi.decode(entries[1].data, (bytes32[3]));

        _assertEncryptedNoteValueEq(event0, outputs[0].encryptedNoteValue);
        _assertEncryptedNoteValueEq(event1, outputs[1].encryptedNoteValue);
    }

    function testRedeemNotes1OwnerCanRedeemDirectly() public {
        _seedLiquidBalance(alice, 10 ether);

        PrivateStateController.Note[1] memory inputNotes =
            _noteArray1(_mintNote(alice, 10 ether, bytes32("alice-redeem-1a")));

        vm.prank(alice);
        bytes32[1] memory nullifiers = controller.redeemNotes1(inputNotes, bob);

        assertEq(l2AccountingVault.liquidBalances(bob), 10 ether);
        assertTrue(controller.nullifierUsed(nullifiers[0]));
    }

    function testRedeemNotes2OwnerCanRedeemDirectly() public {
        _seedLiquidBalance(alice, 20 ether);

        PrivateStateController.Note[2] memory inputNotes = _noteArray2(
            _mintNote(alice, 10 ether, bytes32("alice-redeem-2a")),
            _mintNote(alice, 10 ether, bytes32("alice-redeem-2b"))
        );

        vm.prank(alice);
        bytes32[2] memory nullifiers = controller.redeemNotes2(inputNotes, bob);

        assertEq(l2AccountingVault.liquidBalances(bob), 20 ether);
        assertTrue(controller.nullifierUsed(nullifiers[0]));
        assertTrue(controller.nullifierUsed(nullifiers[1]));
    }

    function testRedeemNotes3OwnerCanRedeemDirectly() public {
        _seedLiquidBalance(alice, 30 ether);

        PrivateStateController.Note[3] memory inputNotes = _notes3(
            _mintNote(alice, 10 ether, bytes32("alice-redeem-3a")),
            _mintNote(alice, 10 ether, bytes32("alice-redeem-3b")),
            _mintNote(alice, 10 ether, bytes32("alice-redeem-3c"))
        );

        vm.prank(alice);
        bytes32[3] memory nullifiers = controller.redeemNotes3(inputNotes, bob);

        assertEq(l2AccountingVault.liquidBalances(bob), 30 ether);
        for (uint256 i = 0; i < 3; ++i) {
            assertTrue(controller.nullifierUsed(nullifiers[i]));
        }
    }

    function testRedeemNotes4OwnerCanRedeemDirectly() public {
        _seedLiquidBalance(alice, 40 ether);

        PrivateStateController.Note[4] memory inputNotes = _notes4(
            _mintNote(alice, 10 ether, bytes32("alice-redeem-4a")),
            _mintNote(alice, 10 ether, bytes32("alice-redeem-4b")),
            _mintNote(alice, 10 ether, bytes32("alice-redeem-4c")),
            _mintNote(alice, 10 ether, bytes32("alice-redeem-4d"))
        );

        vm.prank(alice);
        bytes32[4] memory nullifiers = controller.redeemNotes4(inputNotes, bob);

        assertEq(l2AccountingVault.liquidBalances(bob), 40 ether);
        for (uint256 i = 0; i < 4; ++i) {
            assertTrue(controller.nullifierUsed(nullifiers[i]));
        }
    }

    function testMintNotes2EmitsVaultWriteEventWithUpdatedBalance() public {
        _seedLiquidBalance(alice, 30 ether);

        PrivateStateController.MintOutput[2] memory outputs = _mintOutputs2(
            _note(alice, 10 ether, bytes32("alice-mint-event-2-0")),
            _note(bob, 20 ether, bytes32("alice-mint-event-2-1"))
        );

        vm.recordLogs();
        vm.prank(alice);
        controller.mintNotes2(outputs);

        _assertSingleLiquidBalanceStorageWriteObserved(vm.getRecordedLogs(), alice, 0);
    }

    function testMintNotes1EmitsCommitmentStorageKeyObserved() public {
        _seedLiquidBalance(alice, 10 ether);
        PrivateStateController.Note memory note = _note(alice, 10 ether, bytes32("alice-commitment-storage-key"));
        bytes32 expectedStorageKey = keccak256(abi.encode(_commitmentOf(note), COMMITMENT_EXISTS_SLOT));

        vm.recordLogs();
        vm.prank(alice);
        controller.mintNotes1(_mintOutputArray1(_mintOutput(note)));

        _assertSingleControllerStorageKeyObserved(vm.getRecordedLogs(), expectedStorageKey);
    }

    function testRedeemNotes2EmitsVaultWriteEventWithUpdatedBalance() public {
        _seedLiquidBalance(alice, 20 ether);

        PrivateStateController.Note[2] memory inputNotes = _noteArray2(
            _mintNote(alice, 10 ether, bytes32("alice-redeem-event-2a")),
            _mintNote(alice, 10 ether, bytes32("alice-redeem-event-2b"))
        );

        vm.recordLogs();
        vm.prank(alice);
        controller.redeemNotes2(inputNotes, bob);

        _assertSingleLiquidBalanceStorageWriteObserved(vm.getRecordedLogs(), bob, 20 ether);
    }

    function testRedeemNotes1EmitsNullifierStorageKeyObserved() public {
        _seedLiquidBalance(alice, 10 ether);
        PrivateStateController.Note memory note = _mintNote(alice, 10 ether, bytes32("alice-nullifier-storage-key"));
        bytes32 expectedStorageKey = keccak256(abi.encode(_nullifierOf(note), NULLIFIER_USED_SLOT));

        vm.recordLogs();
        vm.prank(alice);
        controller.redeemNotes1(_noteArray1(note), bob);

        _assertSingleControllerStorageKeyObserved(vm.getRecordedLogs(), expectedStorageKey);
    }

    function testRedeemNotes3CannotRedeemAnotherOwnersNotes() public {
        _seedLiquidBalance(alice, 30 ether);

        PrivateStateController.Note[3] memory inputNotes = _notes3(
            _mintNote(alice, 10 ether, bytes32("alice-redeem-unauthorized-0")),
            _mintNote(alice, 10 ether, bytes32("alice-redeem-unauthorized-1")),
            _mintNote(alice, 10 ether, bytes32("alice-redeem-unauthorized-2"))
        );

        vm.expectRevert(abi.encodeWithSelector(PrivateStateController.UnauthorizedNoteOwner.selector, mallory, alice));
        vm.prank(mallory);
        controller.redeemNotes3(inputNotes, mallory);
    }

    function testMintNotes1CreatesCommitment() public {
        _seedLiquidBalance(alice, 18 ether);

        PrivateStateController.MintOutput[1] memory outputs =
            _mintOutputArray1(_mintOutput(_note(alice, 18 ether, bytes32("alice-mint-event"))));

        vm.prank(alice);
        bytes32[1] memory commitments = controller.mintNotes1(outputs);

        assertEq(l2AccountingVault.liquidBalances(alice), 0);
        assertTrue(controller.commitmentExists(commitments[0]));
    }

    function testMintNotes2CreatesTwoCommitments() public {
        _seedLiquidBalance(alice, 30 ether);

        PrivateStateController.MintOutput[2] memory outputs = _mintOutputs2(
            _note(alice, 10 ether, bytes32("alice-mint-2-0")), _note(bob, 20 ether, bytes32("alice-mint-2-1"))
        );

        vm.prank(alice);
        bytes32[2] memory commitments = controller.mintNotes2(outputs);

        assertEq(l2AccountingVault.liquidBalances(alice), 0);
        assertTrue(controller.commitmentExists(commitments[0]));
        assertTrue(controller.commitmentExists(commitments[1]));
    }

    function testMintNotes3CreatesThreeCommitments() public {
        _seedLiquidBalance(alice, 45 ether);

        PrivateStateController.MintOutput[3] memory outputs = _mintOutputs3(
            _note(alice, 10 ether, bytes32("alice-mint-3-0")),
            _note(bob, 15 ether, bytes32("alice-mint-3-1")),
            _note(alice, 20 ether, bytes32("alice-mint-3-2"))
        );

        vm.prank(alice);
        bytes32[3] memory commitments = controller.mintNotes3(outputs);

        assertEq(l2AccountingVault.liquidBalances(alice), 0);
        for (uint256 i = 0; i < 3; ++i) {
            assertTrue(controller.commitmentExists(commitments[i]));
        }
    }

    function testMintNotes4CreatesFourCommitments() public {
        _seedLiquidBalance(alice, 70 ether);

        PrivateStateController.MintOutput[4] memory outputs = _mintOutputs4(
            _note(alice, 10 ether, bytes32("alice-mint-4-0")),
            _note(bob, 15 ether, bytes32("alice-mint-4-1")),
            _note(alice, 20 ether, bytes32("alice-mint-4-2")),
            _note(bob, 25 ether, bytes32("alice-mint-4-3"))
        );

        vm.prank(alice);
        bytes32[4] memory commitments = controller.mintNotes4(outputs);

        assertEq(l2AccountingVault.liquidBalances(alice), 0);
        for (uint256 i = 0; i < 4; ++i) {
            assertTrue(controller.commitmentExists(commitments[i]));
        }
    }

    function testMintNotes5CreatesFiveCommitments() public {
        _seedLiquidBalance(alice, 100 ether);

        PrivateStateController.MintOutput[5] memory outputs = _mintOutputs5(
            _note(alice, 10 ether, bytes32("alice-mint-5-0")),
            _note(bob, 15 ether, bytes32("alice-mint-5-1")),
            _note(alice, 20 ether, bytes32("alice-mint-5-2")),
            _note(bob, 25 ether, bytes32("alice-mint-5-3")),
            _note(alice, 30 ether, bytes32("alice-mint-5-4"))
        );

        vm.prank(alice);
        bytes32[5] memory commitments = controller.mintNotes5(outputs);

        assertEq(l2AccountingVault.liquidBalances(alice), 0);
        for (uint256 i = 0; i < 5; ++i) {
            assertTrue(controller.commitmentExists(commitments[i]));
        }
    }

    function testMintNotes6CreatesSixCommitments() public {
        _seedLiquidBalance(alice, 135 ether);

        PrivateStateController.MintOutput[6] memory outputs = _mintOutputs6(
            _note(alice, 10 ether, bytes32("alice-mint-6-0")),
            _note(bob, 15 ether, bytes32("alice-mint-6-1")),
            _note(alice, 20 ether, bytes32("alice-mint-6-2")),
            _note(bob, 25 ether, bytes32("alice-mint-6-3")),
            _note(alice, 30 ether, bytes32("alice-mint-6-4")),
            _note(bob, 35 ether, bytes32("alice-mint-6-5"))
        );

        vm.prank(alice);
        bytes32[6] memory commitments = controller.mintNotes6(outputs);

        assertEq(l2AccountingVault.liquidBalances(alice), 0);
        for (uint256 i = 0; i < 6; ++i) {
            assertTrue(controller.commitmentExists(commitments[i]));
        }
    }

    function testCannotDebitLiquidBalanceBeyondAvailableAmount() public {
        _seedLiquidBalance(alice, 10 ether);

        vm.expectRevert(
            abi.encodeWithSelector(L2AccountingVault.InsufficientLiquidBalance.selector, alice, 10 ether, 11 ether)
        );
        _debitLiquidBalance(alice, 11 ether);
    }

    function testControllerCannotCreditLiquidBalancePastBlsScalarField() public {
        vm.prank(address(controller));
        l2AccountingVault.creditLiquidBalance(alice, MAX_LIQUID_BALANCE);

        vm.expectRevert(
            abi.encodeWithSelector(
                L2AccountingVault.LiquidBalanceOverflow.selector, alice, MAX_LIQUID_BALANCE, 1
            )
        );
        vm.prank(address(controller));
        l2AccountingVault.creditLiquidBalance(alice, 1);
    }

    function testControllerCreditCannotOverflowBlsScalarField() public {
        vm.prank(address(controller));
        l2AccountingVault.creditLiquidBalance(alice, MAX_LIQUID_BALANCE);

        vm.expectRevert(
            abi.encodeWithSelector(
                L2AccountingVault.LiquidBalanceOverflow.selector, alice, MAX_LIQUID_BALANCE, 1
            )
        );
        _seedLiquidBalance(alice, 1);
    }

    function testStoresUseImmutablePredictedController() public view {
        assertEq(l2AccountingVault.controller(), address(controller));
    }

    function _mintNote(address noteOwner, uint256 value, bytes32 salt)
        internal
        returns (PrivateStateController.Note memory note)
    {
        note = _note(noteOwner, value, salt);
        vm.prank(noteOwner);
        controller.mintNotes1(_mintOutputArray1(_mintOutput(note)));
    }

    function _seedLiquidBalance(address account, uint256 amount) internal {
        vm.prank(address(controller));
        l2AccountingVault.creditLiquidBalance(account, amount);
    }

    function _debitLiquidBalance(address account, uint256 amount) internal {
        vm.prank(address(controller));
        l2AccountingVault.debitLiquidBalance(account, amount);
    }

    function _assertSingleLiquidBalanceStorageWriteObserved(Vm.Log[] memory logs, address account, uint256 value)
        internal
        view
    {
        uint256 matchCount;
        for (uint256 i = 0; i < logs.length; ++i) {
            if (
                logs[i].emitter != address(l2AccountingVault)
                    || logs[i].topics.length != 1
                    || logs[i].topics[0] != LIQUID_BALANCE_STORAGE_WRITE_OBSERVED_TOPIC
            ) {
                continue;
            }

            matchCount += 1;
            (address writtenAddress, bytes32 writtenValue) = abi.decode(logs[i].data, (address, bytes32));
            assertEq(writtenAddress, account);
            assertEq(writtenValue, bytes32(value));
        }

        assertEq(matchCount, 1);
    }

    function _assertSingleControllerStorageKeyObserved(Vm.Log[] memory logs, bytes32 expectedStorageKey) internal view {
        uint256 matchCount;
        for (uint256 i = 0; i < logs.length; ++i) {
            if (
                logs[i].emitter != address(controller)
                    || logs[i].topics.length != 1
                    || logs[i].topics[0] != STORAGE_KEY_OBSERVED_TOPIC
            ) {
                continue;
            }

            matchCount += 1;
            bytes32 storageKey = abi.decode(logs[i].data, (bytes32));
            assertEq(storageKey, expectedStorageKey);
        }

        assertEq(matchCount, 1);
    }

    function _note(address owner_, uint256 value_, bytes32 salt_)
        internal
        pure
        returns (PrivateStateController.Note memory)
    {
        return PrivateStateController.Note({owner: owner_, value: value_, salt: salt_});
    }

    function _mintOutput(PrivateStateController.Note memory note)
        internal
        pure
        returns (PrivateStateController.MintOutput memory)
    {
        return PrivateStateController.MintOutput({
            value: note.value,
            encryptedNoteValue: _mintEncryptedNoteValue(note.salt)
        });
    }

    function _transferOutput(address owner_, uint256 value_, string memory label)
        internal
        pure
        returns (PrivateStateController.TransferOutput memory)
    {
        return PrivateStateController.TransferOutput({
            owner: owner_,
            value: value_,
            encryptedNoteValue: _encryptedNoteValue(label)
        });
    }

    function _notes4(
        PrivateStateController.Note memory note0,
        PrivateStateController.Note memory note1,
        PrivateStateController.Note memory note2,
        PrivateStateController.Note memory note3
    ) internal pure returns (PrivateStateController.Note[4] memory notes) {
        notes[0] = note0;
        notes[1] = note1;
        notes[2] = note2;
        notes[3] = note3;
    }

    function _notes6(
        PrivateStateController.Note memory note0,
        PrivateStateController.Note memory note1,
        PrivateStateController.Note memory note2,
        PrivateStateController.Note memory note3,
        PrivateStateController.Note memory note4,
        PrivateStateController.Note memory note5
    ) internal pure returns (PrivateStateController.Note[6] memory notes) {
        notes[0] = note0;
        notes[1] = note1;
        notes[2] = note2;
        notes[3] = note3;
        notes[4] = note4;
        notes[5] = note5;
    }

    function _notes5(
        PrivateStateController.Note memory note0,
        PrivateStateController.Note memory note1,
        PrivateStateController.Note memory note2,
        PrivateStateController.Note memory note3,
        PrivateStateController.Note memory note4
    ) internal pure returns (PrivateStateController.Note[5] memory notes) {
        notes[0] = note0;
        notes[1] = note1;
        notes[2] = note2;
        notes[3] = note3;
        notes[4] = note4;
    }

    function _notes8(
        PrivateStateController.Note memory note0,
        PrivateStateController.Note memory note1,
        PrivateStateController.Note memory note2,
        PrivateStateController.Note memory note3,
        PrivateStateController.Note memory note4,
        PrivateStateController.Note memory note5,
        PrivateStateController.Note memory note6,
        PrivateStateController.Note memory note7
    ) internal pure returns (PrivateStateController.Note[8] memory notes) {
        notes[0] = note0;
        notes[1] = note1;
        notes[2] = note2;
        notes[3] = note3;
        notes[4] = note4;
        notes[5] = note5;
        notes[6] = note6;
        notes[7] = note7;
    }

    function _notes2(PrivateStateController.Note memory note0, PrivateStateController.Note memory note1)
        internal
        pure
        returns (PrivateStateController.Note[2] memory notes)
    {
        notes[0] = note0;
        notes[1] = note1;
    }

    function _transferOutputArray1(PrivateStateController.TransferOutput memory output0)
        internal
        pure
        returns (PrivateStateController.TransferOutput[1] memory outputs)
    {
        outputs[0] = output0;
    }

    function _mintOutputArray1(PrivateStateController.MintOutput memory output0)
        internal
        pure
        returns (PrivateStateController.MintOutput[1] memory outputs)
    {
        outputs[0] = output0;
    }

    function _mintOutputs2(PrivateStateController.Note memory note0, PrivateStateController.Note memory note1)
        internal
        pure
        returns (PrivateStateController.MintOutput[2] memory outputs)
    {
        outputs[0] = _mintOutput(note0);
        outputs[1] = _mintOutput(note1);
    }

    function _mintOutputs3(
        PrivateStateController.Note memory note0,
        PrivateStateController.Note memory note1,
        PrivateStateController.Note memory note2
    ) internal pure returns (PrivateStateController.MintOutput[3] memory outputs) {
        outputs[0] = _mintOutput(note0);
        outputs[1] = _mintOutput(note1);
        outputs[2] = _mintOutput(note2);
    }

    function _mintOutputs4(
        PrivateStateController.Note memory note0,
        PrivateStateController.Note memory note1,
        PrivateStateController.Note memory note2,
        PrivateStateController.Note memory note3
    ) internal pure returns (PrivateStateController.MintOutput[4] memory outputs) {
        outputs[0] = _mintOutput(note0);
        outputs[1] = _mintOutput(note1);
        outputs[2] = _mintOutput(note2);
        outputs[3] = _mintOutput(note3);
    }

    function _mintOutputs5(
        PrivateStateController.Note memory note0,
        PrivateStateController.Note memory note1,
        PrivateStateController.Note memory note2,
        PrivateStateController.Note memory note3,
        PrivateStateController.Note memory note4
    ) internal pure returns (PrivateStateController.MintOutput[5] memory outputs) {
        outputs[0] = _mintOutput(note0);
        outputs[1] = _mintOutput(note1);
        outputs[2] = _mintOutput(note2);
        outputs[3] = _mintOutput(note3);
        outputs[4] = _mintOutput(note4);
    }

    function _mintOutputs6(
        PrivateStateController.Note memory note0,
        PrivateStateController.Note memory note1,
        PrivateStateController.Note memory note2,
        PrivateStateController.Note memory note3,
        PrivateStateController.Note memory note4,
        PrivateStateController.Note memory note5
    ) internal pure returns (PrivateStateController.MintOutput[6] memory outputs) {
        outputs[0] = _mintOutput(note0);
        outputs[1] = _mintOutput(note1);
        outputs[2] = _mintOutput(note2);
        outputs[3] = _mintOutput(note3);
        outputs[4] = _mintOutput(note4);
        outputs[5] = _mintOutput(note5);
    }

    function _transferOutputs2(
        PrivateStateController.TransferOutput memory output0,
        PrivateStateController.TransferOutput memory output1
    ) internal pure returns (PrivateStateController.TransferOutput[2] memory outputs) {
        outputs[0] = output0;
        outputs[1] = output1;
    }

    function _transferOutputs3(
        PrivateStateController.TransferOutput memory output0,
        PrivateStateController.TransferOutput memory output1,
        PrivateStateController.TransferOutput memory output2
    ) internal pure returns (PrivateStateController.TransferOutput[3] memory outputs) {
        outputs[0] = output0;
        outputs[1] = output1;
        outputs[2] = output2;
    }

    function _notes3(
        PrivateStateController.Note memory note0,
        PrivateStateController.Note memory note1,
        PrivateStateController.Note memory note2
    ) internal pure returns (PrivateStateController.Note[3] memory notes) {
        notes[0] = note0;
        notes[1] = note1;
        notes[2] = note2;
    }

    function _noteArray1(PrivateStateController.Note memory note0)
        internal
        pure
        returns (PrivateStateController.Note[1] memory notes)
    {
        notes[0] = note0;
    }

    function _noteArray2(PrivateStateController.Note memory note0, PrivateStateController.Note memory note1)
        internal
        pure
        returns (PrivateStateController.Note[2] memory notes)
    {
        notes[0] = note0;
        notes[1] = note1;
    }

    function _assertCommitmentsExist(bytes32[1] memory commitments) internal view {
        assertTrue(controller.commitmentExists(commitments[0]));
    }

    function _assertCommitmentsExist(bytes32[2] memory commitments) internal view {
        assertTrue(controller.commitmentExists(commitments[0]));
        assertTrue(controller.commitmentExists(commitments[1]));
    }

    function _assertCommitmentsExist(bytes32[3] memory commitments) internal view {
        assertTrue(controller.commitmentExists(commitments[0]));
        assertTrue(controller.commitmentExists(commitments[1]));
        assertTrue(controller.commitmentExists(commitments[2]));
    }

    function _commitmentOf(PrivateStateController.Note memory note) internal view returns (bytes32) {
        return controller.computeNoteCommitment(note.value, note.owner, note.salt);
    }

    function _nullifierOf(PrivateStateController.Note memory note) internal view returns (bytes32) {
        return controller.computeNullifier(note.value, note.owner, note.salt);
    }

    function _noteFromTransferOutput(PrivateStateController.TransferOutput memory output)
        internal
        pure
        returns (PrivateStateController.Note memory)
    {
        return PrivateStateController.Note({
            owner: output.owner,
            value: output.value,
            salt: keccak256(abi.encode(output.encryptedNoteValue))
        });
    }

    function _encryptedNoteValue(string memory label) internal pure returns (bytes32[3] memory encryptedNoteValue) {
        encryptedNoteValue[0] = keccak256(abi.encodePacked(label, ":ephemeralPubKeyX"));
        encryptedNoteValue[1] = keccak256(abi.encodePacked(label, ":packedMeta"));
        encryptedNoteValue[2] = keccak256(abi.encodePacked(label, ":ciphertextValue"));
    }

    function _mintEncryptedNoteValue(bytes32 salt) internal pure returns (bytes32[3] memory encryptedNoteValue) {
        encryptedNoteValue[0] = keccak256(abi.encodePacked("mint:ephemeralPubKeyX:", salt));
        encryptedNoteValue[1] = keccak256(abi.encodePacked("mint:packedMeta:", salt));
        encryptedNoteValue[2] = keccak256(abi.encodePacked("mint:ciphertextValue:", salt));
    }

    function _assertEncryptedNoteValueEq(bytes32[3] memory left, bytes32[3] memory right) internal pure {
        assertEq(left[0], right[0]);
        assertEq(left[1], right[1]);
        assertEq(left[2], right[2]);
    }

    function _l2AccountingVaultInitCodeHash(address controller_) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(type(L2AccountingVault).creationCode, abi.encode(controller_)));
    }
}

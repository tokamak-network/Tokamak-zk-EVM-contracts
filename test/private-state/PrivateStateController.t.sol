// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import "forge-std/Test.sol";
import {L2AccountingVault} from "../../apps/private-state/src/L2AccountingVault.sol";
import {PrivateStateController} from "../../apps/private-state/src/PrivateStateController.sol";
import {PrivateStateDeploymentFactory} from "../../apps/private-state/script/deploy/PrivateStateDeploymentFactory.sol";

contract PrivateStateControllerTest is Test {
    address private alice = makeAddr("alice");
    address private bob = makeAddr("bob");
    address private mallory = makeAddr("mallory");
    address private canonicalAsset = makeAddr("canonical-asset");

    bytes32 private constant L2_ACCOUNTING_VAULT_SALT = keccak256("private-state.l2-accounting-vault");

    L2AccountingVault private l2AccountingVault;
    PrivateStateController private controller;
    PrivateStateDeploymentFactory private deploymentFactory;

    function setUp() public {
        deploymentFactory = new PrivateStateDeploymentFactory();

        address predictedController = vm.computeCreateAddress(address(deploymentFactory), 1);
        address predictedL2AccountingVault = vm.computeCreate2Address(
            L2_ACCOUNTING_VAULT_SALT, _l2AccountingVaultInitCodeHash(predictedController), address(deploymentFactory)
        );

        controller = deploymentFactory.deployController(predictedL2AccountingVault, canonicalAsset);
        l2AccountingVault = deploymentFactory.deployL2AccountingVault(L2_ACCOUNTING_VAULT_SALT, predictedController);

        assertEq(address(controller), predictedController);
        assertEq(address(l2AccountingVault), predictedL2AccountingVault);
    }

    function testTransferNotes4To1MockBridgeDepositRedeemAndMockBridgeWithdraw() public {
        vm.prank(alice);
        controller.mockBridgeDeposit(100 ether);

        assertEq(l2AccountingVault.liquidBalances(alice), 100 ether);

        PrivateStateController.Note memory note0 = _mintNote(alice, 10 ether, bytes32("alice-4-0"));
        PrivateStateController.Note memory note1 = _mintNote(alice, 15 ether, bytes32("alice-4-1"));
        PrivateStateController.Note memory note2 = _mintNote(alice, 20 ether, bytes32("alice-4-2"));
        PrivateStateController.Note memory note3 = _mintNote(alice, 15 ether, bytes32("alice-4-3"));

        assertEq(l2AccountingVault.liquidBalances(alice), 40 ether);

        PrivateStateController.Note[4] memory inputNotes = _notes4(note0, note1, note2, note3);
        PrivateStateController.Note[1] memory outputs = _noteArray1(_note(bob, 60 ether, bytes32("bob-4-0")));

        vm.prank(alice);
        (bytes32[4] memory nullifiers, bytes32[1] memory outputCommitments) =
            controller.transferNotes4To1(inputNotes, outputs);

        for (uint256 i = 0; i < 4; ++i) {
            assertTrue(controller.nullifierUsed(nullifiers[i]));
        }
        assertTrue(controller.commitmentExists(outputCommitments[0]));

        vm.prank(bob);
        controller.mockBridgeDeposit(30 ether);

        vm.startPrank(bob);
        controller.mintNotes1(_noteArray1(_note(bob, 10 ether, bytes32("bob-4-dummy-1"))));
        controller.mintNotes1(_noteArray1(_note(bob, 10 ether, bytes32("bob-4-dummy-2"))));
        controller.mintNotes1(_noteArray1(_note(bob, 10 ether, bytes32("bob-4-dummy-3"))));
        controller.redeemNotes4(
            _notes4(
                _note(bob, 60 ether, bytes32("bob-4-0")),
                _note(bob, 10 ether, bytes32("bob-4-dummy-1")),
                _note(bob, 10 ether, bytes32("bob-4-dummy-2")),
                _note(bob, 10 ether, bytes32("bob-4-dummy-3"))
            ),
            bob
        );
        vm.stopPrank();

        assertEq(l2AccountingVault.liquidBalances(bob), 90 ether);

        vm.prank(bob);
        controller.mockBridgeWithdraw(90 ether);

        assertEq(l2AccountingVault.liquidBalances(bob), 0);
    }

    function testTransferNoteFamiliesOwnerCanTransferDirectly() public {
        vm.prank(alice);
        controller.mockBridgeDeposit(800 ether);

        PrivateStateController.Note[1] memory inputNotes1To1 = _noteArray1(_mintNote(alice, 10 ether, bytes32("alice-1to1-0")));
        PrivateStateController.Note[1] memory outputs1To1 = _noteArray1(_note(bob, 10 ether, bytes32("bob-1to1-0")));
        vm.prank(alice);
        (, bytes32[1] memory outputCommitments1To1) = controller.transferNotes1To1(inputNotes1To1, outputs1To1);
        _assertCommitmentsExist(outputCommitments1To1);

        PrivateStateController.Note[1] memory inputNotes1To2 = _noteArray1(_mintNote(alice, 20 ether, bytes32("alice-1to2-0")));
        PrivateStateController.Note[2] memory outputs1To2 = _notes2(
            _note(bob, 10 ether, bytes32("bob-1to2-0")),
            _note(alice, 10 ether, bytes32("alice-1to2-change-0"))
        );
        vm.prank(alice);
        (, bytes32[2] memory outputCommitments1To2) = controller.transferNotes1To2(inputNotes1To2, outputs1To2);
        _assertCommitmentsExist(outputCommitments1To2);

        PrivateStateController.Note[2] memory inputNotes2To1 = _noteArray2(
            _mintNote(alice, 10 ether, bytes32("alice-2to1-0")), _mintNote(alice, 10 ether, bytes32("alice-2to1-1"))
        );
        PrivateStateController.Note[1] memory outputs2To1 = _noteArray1(_note(bob, 20 ether, bytes32("bob-2to1-0")));
        vm.prank(alice);
        (, bytes32[1] memory outputCommitments2To1) = controller.transferNotes2To1(inputNotes2To1, outputs2To1);
        _assertCommitmentsExist(outputCommitments2To1);

        PrivateStateController.Note[2] memory inputNotes2To2 = _noteArray2(
            _mintNote(alice, 10 ether, bytes32("alice-2to2-0")), _mintNote(alice, 10 ether, bytes32("alice-2to2-1"))
        );
        PrivateStateController.Note[2] memory outputs2To2 = _notes2(
            _note(bob, 10 ether, bytes32("bob-2to2-0")),
            _note(alice, 10 ether, bytes32("alice-2to2-change-0"))
        );
        vm.prank(alice);
        (, bytes32[2] memory outputCommitments2To2) = controller.transferNotes2To2(inputNotes2To2, outputs2To2);
        _assertCommitmentsExist(outputCommitments2To2);

        PrivateStateController.Note[3] memory inputNotes3To1 = _notes3(
            _mintNote(alice, 10 ether, bytes32("alice-3to1-0")),
            _mintNote(alice, 10 ether, bytes32("alice-3to1-1")),
            _mintNote(alice, 10 ether, bytes32("alice-3to1-2"))
        );
        PrivateStateController.Note[1] memory outputs3To1 = _noteArray1(_note(bob, 30 ether, bytes32("bob-3to1-0")));
        vm.prank(alice);
        (, bytes32[1] memory outputCommitments3To1) = controller.transferNotes3To1(inputNotes3To1, outputs3To1);
        _assertCommitmentsExist(outputCommitments3To1);

        PrivateStateController.Note[3] memory inputNotes3To2 = _notes3(
            _mintNote(alice, 10 ether, bytes32("alice-3to2-0")),
            _mintNote(alice, 10 ether, bytes32("alice-3to2-1")),
            _mintNote(alice, 10 ether, bytes32("alice-3to2-2"))
        );
        PrivateStateController.Note[2] memory outputs3To2 = _notes2(
            _note(bob, 10 ether, bytes32("bob-3to2-0")),
            _note(alice, 20 ether, bytes32("alice-3to2-change-0"))
        );
        vm.prank(alice);
        (, bytes32[2] memory outputCommitments3To2) = controller.transferNotes3To2(inputNotes3To2, outputs3To2);
        _assertCommitmentsExist(outputCommitments3To2);

        PrivateStateController.Note[4] memory inputNotes4To1 = _notes4(
            _mintNote(alice, 10 ether, bytes32("alice-4to1-0")),
            _mintNote(alice, 10 ether, bytes32("alice-4to1-1")),
            _mintNote(alice, 10 ether, bytes32("alice-4to1-2")),
            _mintNote(alice, 10 ether, bytes32("alice-4to1-3"))
        );
        PrivateStateController.Note[1] memory outputs4To1 = _noteArray1(_note(bob, 40 ether, bytes32("bob-4to1-0")));
        vm.prank(alice);
        (, bytes32[1] memory outputCommitments4To1) = controller.transferNotes4To1(inputNotes4To1, outputs4To1);
        _assertCommitmentsExist(outputCommitments4To1);

    }

    function testTransferNotes4To1CannotTransferAnotherOwnersNotes() public {
        vm.prank(alice);
        controller.mockBridgeDeposit(40 ether);

        PrivateStateController.Note[4] memory inputNotes = _notes4(
            _mintNote(alice, 10 ether, bytes32("alice-4b-0")),
            _mintNote(alice, 10 ether, bytes32("alice-4b-1")),
            _mintNote(alice, 10 ether, bytes32("alice-4b-2")),
            _mintNote(alice, 10 ether, bytes32("alice-4b-3"))
        );
        PrivateStateController.Note[1] memory outputs = _noteArray1(_note(bob, 40 ether, bytes32("bob-4b-0")));

        vm.expectRevert(abi.encodeWithSelector(PrivateStateController.UnauthorizedNoteOwner.selector, mallory, alice));
        vm.prank(mallory);
        controller.transferNotes4To1(inputNotes, outputs);
    }

    function testTransferNotes4To1CannotReplaySpentNotes() public {
        vm.prank(alice);
        controller.mockBridgeDeposit(40 ether);

        PrivateStateController.Note memory note0 = _mintNote(alice, 10 ether, bytes32("alice-4c-0"));
        PrivateStateController.Note memory note1 = _mintNote(alice, 10 ether, bytes32("alice-4c-1"));
        PrivateStateController.Note memory note2 = _mintNote(alice, 10 ether, bytes32("alice-4c-2"));
        PrivateStateController.Note memory note3 = _mintNote(alice, 10 ether, bytes32("alice-4c-3"));

        PrivateStateController.Note[4] memory inputNotes = _notes4(note0, note1, note2, note3);
        PrivateStateController.Note[1] memory outputs = _noteArray1(_note(alice, 40 ether, bytes32("alice-4c-out-0")));

        vm.prank(alice);
        controller.transferNotes4To1(inputNotes, outputs);

        vm.expectRevert(
            abi.encodeWithSelector(PrivateStateController.NullifierAlreadyUsed.selector, _nullifierOf(note0))
        );
        vm.prank(alice);
        controller.transferNotes4To1(inputNotes, outputs);
    }

    function testTransferNotes4To1RejectsValueMismatch() public {
        vm.prank(alice);
        controller.mockBridgeDeposit(40 ether);

        PrivateStateController.Note[4] memory inputNotes = _notes4(
            _mintNote(alice, 10 ether, bytes32("alice-4d-0")),
            _mintNote(alice, 10 ether, bytes32("alice-4d-1")),
            _mintNote(alice, 10 ether, bytes32("alice-4d-2")),
            _mintNote(alice, 10 ether, bytes32("alice-4d-3"))
        );
        PrivateStateController.Note[1] memory outputs = _noteArray1(_note(bob, 41 ether, bytes32("bob-4d-0")));

        vm.expectRevert(
            abi.encodeWithSelector(PrivateStateController.InputOutputValueMismatch.selector, 40 ether, 41 ether)
        );
        vm.prank(alice);
        controller.transferNotes4To1(inputNotes, outputs);
    }

    function testTransferNotes4To1UnknownCommitmentCannotBeSpent() public {
        PrivateStateController.Note[4] memory inputNotes = _notes4(
            _note(alice, 5 ether, bytes32("unknown-4-0")),
            _note(alice, 5 ether, bytes32("unknown-4-1")),
            _note(alice, 5 ether, bytes32("unknown-4-2")),
            _note(alice, 5 ether, bytes32("unknown-4-3"))
        );
        PrivateStateController.Note[1] memory outputs = _noteArray1(_note(bob, 20 ether, bytes32("unknown-out-0")));
        bytes32 unknownCommitment = _commitmentOf(inputNotes[0]);

        vm.expectRevert(abi.encodeWithSelector(PrivateStateController.UnknownCommitment.selector, unknownCommitment));
        vm.prank(alice);
        controller.transferNotes4To1(inputNotes, outputs);
    }

    function testRedeemNotes4OwnerCanRedeemDirectly() public {
        vm.prank(alice);
        controller.mockBridgeDeposit(40 ether);

        PrivateStateController.Note[4] memory inputNotes = _notes4(
            _mintNote(alice, 10 ether, bytes32("alice-redeem-0")),
            _mintNote(alice, 10 ether, bytes32("alice-redeem-1")),
            _mintNote(alice, 10 ether, bytes32("alice-redeem-2")),
            _mintNote(alice, 10 ether, bytes32("alice-redeem-3"))
        );

        vm.prank(alice);
        bytes32[4] memory nullifiers = controller.redeemNotes4(inputNotes, bob);

        assertEq(l2AccountingVault.liquidBalances(bob), 40 ether);
        for (uint256 i = 0; i < 4; ++i) {
            assertTrue(controller.nullifierUsed(nullifiers[i]));
        }
    }

    function testRedeemNotes3OwnerCanRedeemDirectly() public {
        vm.prank(alice);
        controller.mockBridgeDeposit(30 ether);

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

    function testRedeemNotes4CannotRedeemAnotherOwnersNotes() public {
        vm.prank(alice);
        controller.mockBridgeDeposit(40 ether);

        PrivateStateController.Note[4] memory inputNotes = _notes4(
            _mintNote(alice, 10 ether, bytes32("alice-redeem-4")),
            _mintNote(alice, 10 ether, bytes32("alice-redeem-5")),
            _mintNote(alice, 10 ether, bytes32("alice-redeem-6")),
            _mintNote(alice, 10 ether, bytes32("alice-redeem-7"))
        );

        vm.expectRevert(abi.encodeWithSelector(PrivateStateController.UnauthorizedNoteOwner.selector, mallory, alice));
        vm.prank(mallory);
        controller.redeemNotes4(inputNotes, mallory);
    }

    function testRedeemNotes6OwnerCanRedeemDirectly() public {
        vm.prank(alice);
        controller.mockBridgeDeposit(60 ether);

        PrivateStateController.Note[6] memory inputNotes = _notes6(
            _mintNote(alice, 10 ether, bytes32("alice-redeem-6a")),
            _mintNote(alice, 10 ether, bytes32("alice-redeem-6b")),
            _mintNote(alice, 10 ether, bytes32("alice-redeem-6c")),
            _mintNote(alice, 10 ether, bytes32("alice-redeem-6d")),
            _mintNote(alice, 10 ether, bytes32("alice-redeem-6e")),
            _mintNote(alice, 10 ether, bytes32("alice-redeem-6f"))
        );

        vm.prank(alice);
        controller.redeemNotes6(inputNotes, bob);

        assertEq(l2AccountingVault.liquidBalances(bob), 60 ether);
    }

    function testRedeemNotes8OwnerCanRedeemDirectly() public {
        vm.prank(alice);
        controller.mockBridgeDeposit(80 ether);

        PrivateStateController.Note[8] memory inputNotes = _notes8(
            _mintNote(alice, 10 ether, bytes32("alice-redeem-8a")),
            _mintNote(alice, 10 ether, bytes32("alice-redeem-8b")),
            _mintNote(alice, 10 ether, bytes32("alice-redeem-8c")),
            _mintNote(alice, 10 ether, bytes32("alice-redeem-8d")),
            _mintNote(alice, 10 ether, bytes32("alice-redeem-8e")),
            _mintNote(alice, 10 ether, bytes32("alice-redeem-8f")),
            _mintNote(alice, 10 ether, bytes32("alice-redeem-8g")),
            _mintNote(alice, 10 ether, bytes32("alice-redeem-8h"))
        );

        vm.prank(alice);
        controller.redeemNotes8(inputNotes, bob);

        assertEq(l2AccountingVault.liquidBalances(bob), 80 ether);
    }

    function testMintNotes1CreatesCommitment() public {
        vm.prank(alice);
        controller.mockBridgeDeposit(18 ether);

        PrivateStateController.Note[1] memory outputs = _noteArray1(_note(alice, 18 ether, bytes32("alice-mint-event")));

        vm.prank(alice);
        bytes32[1] memory commitments = controller.mintNotes1(outputs);

        assertEq(l2AccountingVault.liquidBalances(alice), 0);
        assertTrue(controller.commitmentExists(commitments[0]));
    }

    function testMintNotes2CreatesTwoCommitments() public {
        vm.prank(alice);
        controller.mockBridgeDeposit(30 ether);

        PrivateStateController.Note[2] memory outputs = _noteArray2(
            _note(alice, 10 ether, bytes32("alice-mint-2-0")), _note(bob, 20 ether, bytes32("alice-mint-2-1"))
        );

        vm.prank(alice);
        bytes32[2] memory commitments = controller.mintNotes2(outputs);

        assertEq(l2AccountingVault.liquidBalances(alice), 0);
        assertTrue(controller.commitmentExists(commitments[0]));
        assertTrue(controller.commitmentExists(commitments[1]));
    }

    function testMintNotes3CreatesThreeCommitments() public {
        vm.prank(alice);
        controller.mockBridgeDeposit(45 ether);

        PrivateStateController.Note[3] memory outputs = _notes3(
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
        vm.prank(alice);
        controller.mockBridgeDeposit(70 ether);

        PrivateStateController.Note[4] memory outputs = _notes4(
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

    function testCannotMockBridgeWithdrawMoreThanLiquidBalance() public {
        vm.prank(alice);
        controller.mockBridgeDeposit(10 ether);

        vm.expectRevert(
            abi.encodeWithSelector(L2AccountingVault.InsufficientLiquidBalance.selector, alice, 10 ether, 11 ether)
        );
        vm.prank(alice);
        controller.mockBridgeWithdraw(11 ether);
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
        controller.mintNotes1(_noteArray1(note));
    }

    function _note(address owner_, uint256 value_, bytes32 salt_)
        internal
        pure
        returns (PrivateStateController.Note memory)
    {
        return PrivateStateController.Note({owner: owner_, value: value_, salt: salt_});
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

    function _commitmentOf(PrivateStateController.Note memory note) internal view returns (bytes32) {
        return controller.computeNoteCommitment(note.value, note.owner, note.salt);
    }

    function _nullifierOf(PrivateStateController.Note memory note) internal view returns (bytes32) {
        return controller.computeNullifier(note.value, note.owner, note.salt);
    }

    function _l2AccountingVaultInitCodeHash(address controller_) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(type(L2AccountingVault).creationCode, abi.encode(controller_)));
    }
}

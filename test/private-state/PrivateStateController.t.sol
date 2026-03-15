// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import "forge-std/Test.sol";
import {L2AccountingVault} from "../../apps/private-state/src/L2AccountingVault.sol";
import {PrivateNullifierRegistry} from "../../apps/private-state/src/PrivateNullifierRegistry.sol";
import {PrivateNoteRegistry} from "../../apps/private-state/src/PrivateNoteRegistry.sol";
import {PrivateStateController} from "../../apps/private-state/src/PrivateStateController.sol";
import {PrivateStateDeploymentFactory} from "../../apps/private-state/script/deploy/PrivateStateDeploymentFactory.sol";

contract PrivateStateControllerTest is Test {
    address private alice = makeAddr("alice");
    address private bob = makeAddr("bob");
    address private mallory = makeAddr("mallory");
    address private canonicalAsset = makeAddr("canonical-asset");

    bytes32 private constant L2_ACCOUNTING_VAULT_SALT = keccak256("private-state.l2-accounting-vault");
    bytes32 private constant NOTE_REGISTRY_SALT = keccak256("private-state.note-registry");
    bytes32 private constant NULLIFIER_REGISTRY_SALT = keccak256("private-state.nullifier-registry");

    L2AccountingVault private l2AccountingVault;
    PrivateNullifierRegistry private nullifierStore;
    PrivateNoteRegistry private noteRegistry;
    PrivateStateController private controller;
    PrivateStateDeploymentFactory private deploymentFactory;

    function setUp() public {
        deploymentFactory = new PrivateStateDeploymentFactory();

        address predictedController = vm.computeCreateAddress(address(deploymentFactory), 1);
        address predictedL2AccountingVault = vm.computeCreate2Address(
            L2_ACCOUNTING_VAULT_SALT, _l2AccountingVaultInitCodeHash(predictedController), address(deploymentFactory)
        );
        address predictedNoteRegistry =
            vm.computeCreate2Address(NOTE_REGISTRY_SALT, _noteRegistryInitCodeHash(predictedController), address(deploymentFactory));
        address predictedNullifierRegistry = vm.computeCreate2Address(
            NULLIFIER_REGISTRY_SALT, _nullifierRegistryInitCodeHash(predictedController), address(deploymentFactory)
        );

        controller = deploymentFactory.deployController(
            predictedNoteRegistry, predictedNullifierRegistry, predictedL2AccountingVault, canonicalAsset
        );
        l2AccountingVault = deploymentFactory.deployL2AccountingVault(L2_ACCOUNTING_VAULT_SALT, predictedController);
        noteRegistry = deploymentFactory.deployPrivateNoteRegistry(NOTE_REGISTRY_SALT, predictedController);
        nullifierStore =
            deploymentFactory.deployPrivateNullifierRegistry(NULLIFIER_REGISTRY_SALT, predictedController);

        assertEq(address(controller), predictedController);
        assertEq(address(l2AccountingVault), predictedL2AccountingVault);
        assertEq(address(noteRegistry), predictedNoteRegistry);
        assertEq(address(nullifierStore), predictedNullifierRegistry);
    }

    function testTransferNotes4MockBridgeDepositRedeemAndMockBridgeWithdraw() public {
        vm.prank(alice);
        controller.mockBridgeDeposit(100 ether);

        assertEq(l2AccountingVault.liquidBalances(alice), 100 ether);

        PrivateStateController.Note memory note0 = _mintNote(alice, 10 ether, bytes32("alice-4-0"));
        PrivateStateController.Note memory note1 = _mintNote(alice, 15 ether, bytes32("alice-4-1"));
        PrivateStateController.Note memory note2 = _mintNote(alice, 20 ether, bytes32("alice-4-2"));
        PrivateStateController.Note memory note3 = _mintNote(alice, 15 ether, bytes32("alice-4-3"));

        assertEq(l2AccountingVault.liquidBalances(alice), 40 ether);

        PrivateStateController.Note[4] memory inputNotes = _notes4(note0, note1, note2, note3);
        PrivateStateController.Note[3] memory outputs = _notes3(
            _note(bob, 35 ether, bytes32("bob-4-0")),
            _note(alice, 15 ether, bytes32("alice-4-change-0")),
            _note(alice, 10 ether, bytes32("alice-4-change-1"))
        );

        vm.prank(alice);
        (bytes32[4] memory nullifiers, bytes32[3] memory outputCommitments) =
            controller.transferNotes4(inputNotes, outputs);

        for (uint256 i = 0; i < 4; ++i) {
            assertTrue(nullifierStore.nullifierUsed(nullifiers[i]));
        }
        for (uint256 i = 0; i < 3; ++i) {
            assertTrue(noteRegistry.commitmentExists(outputCommitments[i]));
        }

        PrivateStateController.Note[4] memory bobNotes = _notes4(
            _note(bob, 35 ether, bytes32("bob-4-0")),
            _note(bob, 10 ether, bytes32("bob-4-dummy-1")),
            _note(bob, 10 ether, bytes32("bob-4-dummy-2")),
            _note(bob, 10 ether, bytes32("bob-4-dummy-3"))
        );

        vm.prank(bob);
        controller.mockBridgeDeposit(30 ether);

        vm.startPrank(bob);
        controller.mintNotes1(_noteArray1(_note(bob, 10 ether, bytes32("bob-4-dummy-1"))));
        controller.mintNotes1(_noteArray1(_note(bob, 10 ether, bytes32("bob-4-dummy-2"))));
        controller.mintNotes1(_noteArray1(_note(bob, 10 ether, bytes32("bob-4-dummy-3"))));
        controller.redeemNotes4(bobNotes, bob);
        vm.stopPrank();

        assertEq(l2AccountingVault.liquidBalances(bob), 65 ether);

        vm.prank(bob);
        controller.mockBridgeWithdraw(65 ether);

        assertEq(l2AccountingVault.liquidBalances(bob), 0);
    }

    function testTransferNotes1OwnerCanTransferDirectly() public {
        vm.prank(alice);
        controller.mockBridgeDeposit(30 ether);

        PrivateStateController.Note[1] memory inputNotes = _noteArray1(_mintNote(alice, 30 ether, bytes32("alice-1-0")));
        PrivateStateController.Note[3] memory outputs = _notes3(
            _note(bob, 10 ether, bytes32("bob-1-0")),
            _note(alice, 10 ether, bytes32("alice-1-change-0")),
            _note(alice, 10 ether, bytes32("alice-1-change-1"))
        );

        vm.prank(alice);
        (bytes32[1] memory nullifiers, bytes32[3] memory outputCommitments) =
            controller.transferNotes1(inputNotes, outputs);

        assertTrue(nullifierStore.nullifierUsed(nullifiers[0]));
        for (uint256 i = 0; i < 3; ++i) {
            assertTrue(noteRegistry.commitmentExists(outputCommitments[i]));
        }
    }

    function testTransferNotes4CannotTransferAnotherOwnersNotes() public {
        vm.prank(alice);
        controller.mockBridgeDeposit(40 ether);

        PrivateStateController.Note[4] memory inputNotes = _notes4(
            _mintNote(alice, 10 ether, bytes32("alice-4b-0")),
            _mintNote(alice, 10 ether, bytes32("alice-4b-1")),
            _mintNote(alice, 10 ether, bytes32("alice-4b-2")),
            _mintNote(alice, 10 ether, bytes32("alice-4b-3"))
        );
        PrivateStateController.Note[3] memory outputs = _notes3(
            _note(bob, 20 ether, bytes32("bob-4b-0")),
            _note(alice, 10 ether, bytes32("alice-4b-change-0")),
            _note(alice, 10 ether, bytes32("alice-4b-change-1"))
        );

        vm.expectRevert(abi.encodeWithSelector(PrivateStateController.UnauthorizedNoteOwner.selector, mallory, alice));
        vm.prank(mallory);
        controller.transferNotes4(inputNotes, outputs);
    }

    function testTransferNotes4CannotReplaySpentNotes() public {
        vm.prank(alice);
        controller.mockBridgeDeposit(40 ether);

        PrivateStateController.Note memory note0 = _mintNote(alice, 10 ether, bytes32("alice-4c-0"));
        PrivateStateController.Note memory note1 = _mintNote(alice, 10 ether, bytes32("alice-4c-1"));
        PrivateStateController.Note memory note2 = _mintNote(alice, 10 ether, bytes32("alice-4c-2"));
        PrivateStateController.Note memory note3 = _mintNote(alice, 10 ether, bytes32("alice-4c-3"));

        PrivateStateController.Note[4] memory inputNotes = _notes4(note0, note1, note2, note3);
        PrivateStateController.Note[3] memory outputs = _notes3(
            _note(alice, 15 ether, bytes32("alice-4c-out-0")),
            _note(alice, 15 ether, bytes32("alice-4c-out-1")),
            _note(alice, 10 ether, bytes32("alice-4c-out-2"))
        );

        vm.prank(alice);
        controller.transferNotes4(inputNotes, outputs);

        vm.expectRevert(
            abi.encodeWithSelector(PrivateNullifierRegistry.NullifierAlreadyUsed.selector, _nullifierOf(note0))
        );
        vm.prank(alice);
        controller.transferNotes4(inputNotes, outputs);
    }

    function testTransferNotes4RejectsValueMismatch() public {
        vm.prank(alice);
        controller.mockBridgeDeposit(40 ether);

        PrivateStateController.Note[4] memory inputNotes = _notes4(
            _mintNote(alice, 10 ether, bytes32("alice-4d-0")),
            _mintNote(alice, 10 ether, bytes32("alice-4d-1")),
            _mintNote(alice, 10 ether, bytes32("alice-4d-2")),
            _mintNote(alice, 10 ether, bytes32("alice-4d-3"))
        );
        PrivateStateController.Note[3] memory outputs = _notes3(
            _note(bob, 20 ether, bytes32("bob-4d-0")),
            _note(alice, 10 ether, bytes32("alice-4d-change-0")),
            _note(alice, 11 ether, bytes32("alice-4d-change-1"))
        );

        vm.expectRevert(
            abi.encodeWithSelector(PrivateStateController.InputOutputValueMismatch.selector, 40 ether, 41 ether)
        );
        vm.prank(alice);
        controller.transferNotes4(inputNotes, outputs);
    }

    function testTransferNotes6OwnerCanTransferDirectly() public {
        vm.prank(alice);
        controller.mockBridgeDeposit(60 ether);

        PrivateStateController.Note[6] memory inputNotes = _notes6(
            _mintNote(alice, 10 ether, bytes32("alice-6-0")),
            _mintNote(alice, 10 ether, bytes32("alice-6-1")),
            _mintNote(alice, 10 ether, bytes32("alice-6-2")),
            _mintNote(alice, 10 ether, bytes32("alice-6-3")),
            _mintNote(alice, 10 ether, bytes32("alice-6-4")),
            _mintNote(alice, 10 ether, bytes32("alice-6-5"))
        );
        PrivateStateController.Note[3] memory outputs = _notes3(
            _note(bob, 30 ether, bytes32("bob-6-0")),
            _note(alice, 20 ether, bytes32("alice-6-change-0")),
            _note(alice, 10 ether, bytes32("alice-6-change-1"))
        );

        vm.prank(alice);
        (, bytes32[3] memory outputCommitments) = controller.transferNotes6(inputNotes, outputs);

        for (uint256 i = 0; i < 3; ++i) {
            assertTrue(noteRegistry.commitmentExists(outputCommitments[i]));
        }
    }

    function testTransferNotes8OwnerCanTransferDirectly() public {
        vm.prank(alice);
        controller.mockBridgeDeposit(80 ether);

        PrivateStateController.Note[8] memory inputNotes = _notes8(
            _mintNote(alice, 10 ether, bytes32("alice-8-0")),
            _mintNote(alice, 10 ether, bytes32("alice-8-1")),
            _mintNote(alice, 10 ether, bytes32("alice-8-2")),
            _mintNote(alice, 10 ether, bytes32("alice-8-3")),
            _mintNote(alice, 10 ether, bytes32("alice-8-4")),
            _mintNote(alice, 10 ether, bytes32("alice-8-5")),
            _mintNote(alice, 10 ether, bytes32("alice-8-6")),
            _mintNote(alice, 10 ether, bytes32("alice-8-7"))
        );
        PrivateStateController.Note[3] memory outputs = _notes3(
            _note(bob, 40 ether, bytes32("bob-8-0")),
            _note(alice, 20 ether, bytes32("alice-8-change-0")),
            _note(alice, 20 ether, bytes32("alice-8-change-1"))
        );

        vm.prank(alice);
        (, bytes32[3] memory outputCommitments) = controller.transferNotes8(inputNotes, outputs);

        for (uint256 i = 0; i < 3; ++i) {
            assertTrue(noteRegistry.commitmentExists(outputCommitments[i]));
        }
    }

    function testTransferNotes4UnknownCommitmentCannotBeSpent() public {
        PrivateStateController.Note[4] memory inputNotes = _notes4(
            _note(alice, 5 ether, bytes32("unknown-4-0")),
            _note(alice, 5 ether, bytes32("unknown-4-1")),
            _note(alice, 5 ether, bytes32("unknown-4-2")),
            _note(alice, 5 ether, bytes32("unknown-4-3"))
        );
        PrivateStateController.Note[3] memory outputs = _notes3(
            _note(bob, 10 ether, bytes32("unknown-out-0")),
            _note(alice, 5 ether, bytes32("unknown-out-1")),
            _note(alice, 5 ether, bytes32("unknown-out-2"))
        );
        bytes32 unknownCommitment = _commitmentOf(inputNotes[0]);

        vm.expectRevert(abi.encodeWithSelector(PrivateStateController.UnknownCommitment.selector, unknownCommitment));
        vm.prank(alice);
        controller.transferNotes4(inputNotes, outputs);
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
            assertTrue(nullifierStore.nullifierUsed(nullifiers[i]));
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
        assertTrue(noteRegistry.commitmentExists(commitments[0]));
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
        assertTrue(noteRegistry.commitmentExists(commitments[0]));
        assertTrue(noteRegistry.commitmentExists(commitments[1]));
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
            assertTrue(noteRegistry.commitmentExists(commitments[i]));
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
        assertEq(noteRegistry.controller(), address(controller));
        assertEq(nullifierStore.controller(), address(controller));
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

    function _commitmentOf(PrivateStateController.Note memory note) internal view returns (bytes32) {
        return controller.computeNoteCommitment(note.value, note.owner, note.salt);
    }

    function _nullifierOf(PrivateStateController.Note memory note) internal view returns (bytes32) {
        return controller.computeNullifier(note.value, note.owner, note.salt);
    }

    function _l2AccountingVaultInitCodeHash(address controller_) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(type(L2AccountingVault).creationCode, abi.encode(controller_)));
    }

    function _noteRegistryInitCodeHash(address controller_) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(type(PrivateNoteRegistry).creationCode, abi.encode(controller_)));
    }

    function _nullifierRegistryInitCodeHash(address controller_) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(type(PrivateNullifierRegistry).creationCode, abi.encode(controller_)));
    }
}

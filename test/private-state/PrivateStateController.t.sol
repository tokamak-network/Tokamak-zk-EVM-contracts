// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/token/ERC20/ERC20.sol";
import {PrivateNullifierRegistry} from "../../apps/private-state/src/PrivateNullifierRegistry.sol";
import {PrivateNoteRegistry} from "../../apps/private-state/src/PrivateNoteRegistry.sol";
import {PrivateStateController} from "../../apps/private-state/src/PrivateStateController.sol";
import {TokenVault} from "../../apps/private-state/src/TokenVault.sol";

contract MockToken is ERC20 {
    constructor() ERC20("Tokamak Network Token", "TON") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract PrivateStateControllerTest is Test {
    address private owner = makeAddr("owner");
    address private alice = makeAddr("alice");
    address private bob = makeAddr("bob");
    address private mallory = makeAddr("mallory");

    MockToken private token;
    TokenVault private tokenVault;
    PrivateNullifierRegistry private nullifierStore;
    PrivateNoteRegistry private noteRegistry;
    PrivateStateController private controller;

    event EncryptedNotePublished(bytes32 indexed commitment, address indexed noteOwner, bytes encryptedPayload);

    function setUp() public {
        token = new MockToken();
        tokenVault = new TokenVault(owner, address(token));
        nullifierStore = new PrivateNullifierRegistry(owner);
        noteRegistry = new PrivateNoteRegistry(owner);
        controller = new PrivateStateController(noteRegistry, nullifierStore, tokenVault);

        vm.startPrank(owner);
        tokenVault.bindController(address(controller));
        nullifierStore.bindController(address(controller));
        noteRegistry.bindController(address(controller));
        vm.stopPrank();

        token.mint(alice, 1_000 ether);
        token.mint(bob, 1_000 ether);

        vm.prank(alice);
        token.approve(address(tokenVault), type(uint256).max);

        vm.prank(bob);
        token.approve(address(tokenVault), type(uint256).max);
    }

    function testTransferNotes4DepositRedeemAndWithdraw() public {
        vm.prank(alice);
        controller.depositToken(100 ether);

        assertEq(tokenVault.liquidBalances(alice), 100 ether);
        assertEq(token.balanceOf(address(tokenVault)), 100 ether);

        PrivateStateController.InputNote memory note0 =
            _mintNote(alice, 10 ether, bytes32("alice-4-0"), "enc:alice-4-0");
        PrivateStateController.InputNote memory note1 =
            _mintNote(alice, 15 ether, bytes32("alice-4-1"), "enc:alice-4-1");
        PrivateStateController.InputNote memory note2 =
            _mintNote(alice, 20 ether, bytes32("alice-4-2"), "enc:alice-4-2");
        PrivateStateController.InputNote memory note3 =
            _mintNote(alice, 15 ether, bytes32("alice-4-3"), "enc:alice-4-3");

        assertEq(tokenVault.liquidBalances(alice), 40 ether);

        PrivateStateController.InputNote[4] memory inputNotes = _inputNotes4(note0, note1, note2, note3);
        PrivateStateController.OutputNote[3] memory outputs = _outputNotes3(
            _outputNote(bob, 35 ether, bytes32("bob-4-0")),
            _outputNote(alice, 15 ether, bytes32("alice-4-change-0")),
            _outputNote(alice, 10 ether, bytes32("alice-4-change-1"))
        );
        bytes[3] memory encryptedOutputPayloads =
            _payloads3(bytes("enc:bob-4-0"), bytes("enc:alice-4-change-0"), bytes("enc:alice-4-change-1"));

        vm.prank(alice);
        (bytes32[4] memory nullifiers, bytes32[3] memory outputCommitments) =
            controller.transferNotes4(inputNotes, outputs, encryptedOutputPayloads);

        for (uint256 i = 0; i < 4; ++i) {
            assertTrue(nullifierStore.nullifierUsed(nullifiers[i]));
        }
        for (uint256 i = 0; i < 3; ++i) {
            assertTrue(noteRegistry.commitmentExists(outputCommitments[i]));
        }

        PrivateStateController.InputNote[4] memory bobNotes = _inputNotes4(
            _inputNote(35 ether, bob, bytes32("bob-4-0")),
            _inputNote(10 ether, bob, bytes32("bob-4-dummy-1")),
            _inputNote(10 ether, bob, bytes32("bob-4-dummy-2")),
            _inputNote(10 ether, bob, bytes32("bob-4-dummy-3"))
        );

        vm.prank(bob);
        controller.depositToken(30 ether);

        vm.prank(bob);
        controller.mintNotes1(
            _outputNotes1(_outputNote(bob, 10 ether, bytes32("bob-4-dummy-1"))), _payloads1(bytes("enc:bob-4-dummy-1"))
        );
        vm.prank(bob);
        controller.mintNotes1(
            _outputNotes1(_outputNote(bob, 10 ether, bytes32("bob-4-dummy-2"))), _payloads1(bytes("enc:bob-4-dummy-2"))
        );
        vm.prank(bob);
        controller.mintNotes1(
            _outputNotes1(_outputNote(bob, 10 ether, bytes32("bob-4-dummy-3"))), _payloads1(bytes("enc:bob-4-dummy-3"))
        );

        vm.prank(bob);
        controller.redeemNotes4(bobNotes, bob);

        assertEq(tokenVault.liquidBalances(bob), 65 ether);

        uint256 bobBalanceBefore = token.balanceOf(bob);

        vm.prank(bob);
        controller.withdrawToken(65 ether, bob);

        assertEq(tokenVault.liquidBalances(bob), 0);
        assertEq(token.balanceOf(bob), bobBalanceBefore + 65 ether);
        assertEq(token.balanceOf(address(tokenVault)), 65 ether);
    }

    function testTransferNotes4CannotTransferAnotherOwnersNotes() public {
        vm.prank(alice);
        controller.depositToken(40 ether);

        PrivateStateController.InputNote[4] memory inputNotes = _inputNotes4(
            _mintNote(alice, 10 ether, bytes32("alice-4b-0"), "enc:alice-4b-0"),
            _mintNote(alice, 10 ether, bytes32("alice-4b-1"), "enc:alice-4b-1"),
            _mintNote(alice, 10 ether, bytes32("alice-4b-2"), "enc:alice-4b-2"),
            _mintNote(alice, 10 ether, bytes32("alice-4b-3"), "enc:alice-4b-3")
        );
        PrivateStateController.OutputNote[3] memory outputs = _outputNotes3(
            _outputNote(bob, 20 ether, bytes32("bob-4b-0")),
            _outputNote(alice, 10 ether, bytes32("alice-4b-change-0")),
            _outputNote(alice, 10 ether, bytes32("alice-4b-change-1"))
        );
        bytes[3] memory encryptedOutputPayloads =
            _payloads3(bytes("enc:bob-4b-0"), bytes("enc:alice-4b-change-0"), bytes("enc:alice-4b-change-1"));

        vm.expectRevert(abi.encodeWithSelector(PrivateStateController.UnauthorizedNoteOwner.selector, mallory, alice));
        vm.prank(mallory);
        controller.transferNotes4(inputNotes, outputs, encryptedOutputPayloads);
    }

    function testTransferNotes4CannotReplaySpentNotes() public {
        vm.prank(alice);
        controller.depositToken(40 ether);

        PrivateStateController.InputNote memory note0 =
            _mintNote(alice, 10 ether, bytes32("alice-4c-0"), "enc:alice-4c-0");
        PrivateStateController.InputNote memory note1 =
            _mintNote(alice, 10 ether, bytes32("alice-4c-1"), "enc:alice-4c-1");
        PrivateStateController.InputNote memory note2 =
            _mintNote(alice, 10 ether, bytes32("alice-4c-2"), "enc:alice-4c-2");
        PrivateStateController.InputNote memory note3 =
            _mintNote(alice, 10 ether, bytes32("alice-4c-3"), "enc:alice-4c-3");

        PrivateStateController.InputNote[4] memory inputNotes = _inputNotes4(note0, note1, note2, note3);
        PrivateStateController.OutputNote[3] memory outputs = _outputNotes3(
            _outputNote(alice, 15 ether, bytes32("alice-4c-out-0")),
            _outputNote(alice, 15 ether, bytes32("alice-4c-out-1")),
            _outputNote(alice, 10 ether, bytes32("alice-4c-out-2"))
        );
        bytes[3] memory encryptedOutputPayloads =
            _payloads3(bytes("enc:alice-4c-out-0"), bytes("enc:alice-4c-out-1"), bytes("enc:alice-4c-out-2"));

        vm.prank(alice);
        controller.transferNotes4(inputNotes, outputs, encryptedOutputPayloads);

        vm.expectRevert(
            abi.encodeWithSelector(PrivateNullifierRegistry.NullifierAlreadyUsed.selector, _nullifierOf(note0))
        );
        vm.prank(alice);
        controller.transferNotes4(inputNotes, outputs, encryptedOutputPayloads);
    }

    function testTransferNotes4RejectsValueMismatch() public {
        vm.prank(alice);
        controller.depositToken(40 ether);

        PrivateStateController.InputNote[4] memory inputNotes = _inputNotes4(
            _mintNote(alice, 10 ether, bytes32("alice-4d-0"), "enc:alice-4d-0"),
            _mintNote(alice, 10 ether, bytes32("alice-4d-1"), "enc:alice-4d-1"),
            _mintNote(alice, 10 ether, bytes32("alice-4d-2"), "enc:alice-4d-2"),
            _mintNote(alice, 10 ether, bytes32("alice-4d-3"), "enc:alice-4d-3")
        );
        PrivateStateController.OutputNote[3] memory outputs = _outputNotes3(
            _outputNote(bob, 20 ether, bytes32("bob-4d-0")),
            _outputNote(alice, 10 ether, bytes32("alice-4d-change-0")),
            _outputNote(alice, 11 ether, bytes32("alice-4d-change-1"))
        );
        bytes[3] memory encryptedOutputPayloads =
            _payloads3(bytes("enc:bob-4d-0"), bytes("enc:alice-4d-change-0"), bytes("enc:alice-4d-change-1"));

        vm.expectRevert(
            abi.encodeWithSelector(PrivateStateController.InputOutputValueMismatch.selector, 40 ether, 41 ether)
        );
        vm.prank(alice);
        controller.transferNotes4(inputNotes, outputs, encryptedOutputPayloads);
    }

    function testTransferNotes6OwnerCanTransferDirectly() public {
        vm.prank(alice);
        controller.depositToken(60 ether);

        PrivateStateController.InputNote[6] memory inputNotes = _inputNotes6(
            _mintNote(alice, 10 ether, bytes32("alice-6-0"), "enc:alice-6-0"),
            _mintNote(alice, 10 ether, bytes32("alice-6-1"), "enc:alice-6-1"),
            _mintNote(alice, 10 ether, bytes32("alice-6-2"), "enc:alice-6-2"),
            _mintNote(alice, 10 ether, bytes32("alice-6-3"), "enc:alice-6-3"),
            _mintNote(alice, 10 ether, bytes32("alice-6-4"), "enc:alice-6-4"),
            _mintNote(alice, 10 ether, bytes32("alice-6-5"), "enc:alice-6-5")
        );
        PrivateStateController.OutputNote[3] memory outputs = _outputNotes3(
            _outputNote(bob, 30 ether, bytes32("bob-6-0")),
            _outputNote(alice, 20 ether, bytes32("alice-6-change-0")),
            _outputNote(alice, 10 ether, bytes32("alice-6-change-1"))
        );
        bytes[3] memory encryptedOutputPayloads =
            _payloads3(bytes("enc:bob-6-0"), bytes("enc:alice-6-change-0"), bytes("enc:alice-6-change-1"));

        vm.prank(alice);
        (, bytes32[3] memory outputCommitments) =
            controller.transferNotes6(inputNotes, outputs, encryptedOutputPayloads);

        for (uint256 i = 0; i < 3; ++i) {
            assertTrue(noteRegistry.commitmentExists(outputCommitments[i]));
        }
    }

    function testTransferNotes8OwnerCanTransferDirectly() public {
        vm.prank(alice);
        controller.depositToken(80 ether);

        PrivateStateController.InputNote[8] memory inputNotes = _inputNotes8(
            _mintNote(alice, 10 ether, bytes32("alice-8-0"), "enc:alice-8-0"),
            _mintNote(alice, 10 ether, bytes32("alice-8-1"), "enc:alice-8-1"),
            _mintNote(alice, 10 ether, bytes32("alice-8-2"), "enc:alice-8-2"),
            _mintNote(alice, 10 ether, bytes32("alice-8-3"), "enc:alice-8-3"),
            _mintNote(alice, 10 ether, bytes32("alice-8-4"), "enc:alice-8-4"),
            _mintNote(alice, 10 ether, bytes32("alice-8-5"), "enc:alice-8-5"),
            _mintNote(alice, 10 ether, bytes32("alice-8-6"), "enc:alice-8-6"),
            _mintNote(alice, 10 ether, bytes32("alice-8-7"), "enc:alice-8-7")
        );
        PrivateStateController.OutputNote[3] memory outputs = _outputNotes3(
            _outputNote(bob, 40 ether, bytes32("bob-8-0")),
            _outputNote(alice, 20 ether, bytes32("alice-8-change-0")),
            _outputNote(alice, 20 ether, bytes32("alice-8-change-1"))
        );
        bytes[3] memory encryptedOutputPayloads =
            _payloads3(bytes("enc:bob-8-0"), bytes("enc:alice-8-change-0"), bytes("enc:alice-8-change-1"));

        vm.prank(alice);
        (, bytes32[3] memory outputCommitments) =
            controller.transferNotes8(inputNotes, outputs, encryptedOutputPayloads);

        for (uint256 i = 0; i < 3; ++i) {
            assertTrue(noteRegistry.commitmentExists(outputCommitments[i]));
        }
    }

    function testTransferNotes4UnknownCommitmentCannotBeSpent() public {
        PrivateStateController.InputNote[4] memory inputNotes = _inputNotes4(
            _inputNote(5 ether, alice, bytes32("unknown-4-0")),
            _inputNote(5 ether, alice, bytes32("unknown-4-1")),
            _inputNote(5 ether, alice, bytes32("unknown-4-2")),
            _inputNote(5 ether, alice, bytes32("unknown-4-3"))
        );
        PrivateStateController.OutputNote[3] memory outputs = _outputNotes3(
            _outputNote(bob, 10 ether, bytes32("unknown-out-0")),
            _outputNote(alice, 5 ether, bytes32("unknown-out-1")),
            _outputNote(alice, 5 ether, bytes32("unknown-out-2"))
        );
        bytes[3] memory encryptedOutputPayloads =
            _payloads3(bytes("enc:unknown-out-0"), bytes("enc:unknown-out-1"), bytes("enc:unknown-out-2"));

        bytes32 unknownCommitment = _commitmentOf(inputNotes[0]);

        vm.expectRevert(abi.encodeWithSelector(PrivateStateController.UnknownCommitment.selector, unknownCommitment));
        vm.prank(alice);
        controller.transferNotes4(inputNotes, outputs, encryptedOutputPayloads);
    }

    function testRedeemNotes4OwnerCanRedeemDirectly() public {
        vm.prank(alice);
        controller.depositToken(40 ether);

        PrivateStateController.InputNote[4] memory inputNotes = _inputNotes4(
            _mintNote(alice, 10 ether, bytes32("alice-redeem-0"), "enc:alice-redeem-0"),
            _mintNote(alice, 10 ether, bytes32("alice-redeem-1"), "enc:alice-redeem-1"),
            _mintNote(alice, 10 ether, bytes32("alice-redeem-2"), "enc:alice-redeem-2"),
            _mintNote(alice, 10 ether, bytes32("alice-redeem-3"), "enc:alice-redeem-3")
        );

        vm.prank(alice);
        bytes32[4] memory nullifiers = controller.redeemNotes4(inputNotes, bob);

        assertEq(tokenVault.liquidBalances(bob), 40 ether);
        for (uint256 i = 0; i < 4; ++i) {
            assertTrue(nullifierStore.nullifierUsed(nullifiers[i]));
        }
    }

    function testRedeemNotes4CannotRedeemAnotherOwnersNotes() public {
        vm.prank(alice);
        controller.depositToken(40 ether);

        PrivateStateController.InputNote[4] memory inputNotes = _inputNotes4(
            _mintNote(alice, 10 ether, bytes32("alice-redeem-4"), "enc:alice-redeem-4"),
            _mintNote(alice, 10 ether, bytes32("alice-redeem-5"), "enc:alice-redeem-5"),
            _mintNote(alice, 10 ether, bytes32("alice-redeem-6"), "enc:alice-redeem-6"),
            _mintNote(alice, 10 ether, bytes32("alice-redeem-7"), "enc:alice-redeem-7")
        );

        vm.expectRevert(abi.encodeWithSelector(PrivateStateController.UnauthorizedNoteOwner.selector, mallory, alice));
        vm.prank(mallory);
        controller.redeemNotes4(inputNotes, mallory);
    }

    function testRedeemNotes6OwnerCanRedeemDirectly() public {
        vm.prank(alice);
        controller.depositToken(60 ether);

        PrivateStateController.InputNote[6] memory inputNotes = _inputNotes6(
            _mintNote(alice, 10 ether, bytes32("alice-redeem-6a"), "enc:alice-redeem-6a"),
            _mintNote(alice, 10 ether, bytes32("alice-redeem-6b"), "enc:alice-redeem-6b"),
            _mintNote(alice, 10 ether, bytes32("alice-redeem-6c"), "enc:alice-redeem-6c"),
            _mintNote(alice, 10 ether, bytes32("alice-redeem-6d"), "enc:alice-redeem-6d"),
            _mintNote(alice, 10 ether, bytes32("alice-redeem-6e"), "enc:alice-redeem-6e"),
            _mintNote(alice, 10 ether, bytes32("alice-redeem-6f"), "enc:alice-redeem-6f")
        );

        vm.prank(alice);
        controller.redeemNotes6(inputNotes, bob);

        assertEq(tokenVault.liquidBalances(bob), 60 ether);
    }

    function testRedeemNotes8OwnerCanRedeemDirectly() public {
        vm.prank(alice);
        controller.depositToken(80 ether);

        PrivateStateController.InputNote[8] memory inputNotes = _inputNotes8(
            _mintNote(alice, 10 ether, bytes32("alice-redeem-8a"), "enc:alice-redeem-8a"),
            _mintNote(alice, 10 ether, bytes32("alice-redeem-8b"), "enc:alice-redeem-8b"),
            _mintNote(alice, 10 ether, bytes32("alice-redeem-8c"), "enc:alice-redeem-8c"),
            _mintNote(alice, 10 ether, bytes32("alice-redeem-8d"), "enc:alice-redeem-8d"),
            _mintNote(alice, 10 ether, bytes32("alice-redeem-8e"), "enc:alice-redeem-8e"),
            _mintNote(alice, 10 ether, bytes32("alice-redeem-8f"), "enc:alice-redeem-8f"),
            _mintNote(alice, 10 ether, bytes32("alice-redeem-8g"), "enc:alice-redeem-8g"),
            _mintNote(alice, 10 ether, bytes32("alice-redeem-8h"), "enc:alice-redeem-8h")
        );

        vm.prank(alice);
        controller.redeemNotes8(inputNotes, bob);

        assertEq(tokenVault.liquidBalances(bob), 80 ether);
    }

    function testMintNotes1EmitsEncryptedPayload() public {
        PrivateStateController.InputNote memory aliceNote = _inputNote(18 ether, alice, bytes32("alice-mint-event"));
        bytes memory encryptedPayload = bytes("enc:alice-mint-event");
        bytes32 expectedCommitment = _commitmentOf(aliceNote);

        vm.prank(alice);
        controller.depositToken(18 ether);

        vm.expectEmit(true, true, false, true);
        emit EncryptedNotePublished(expectedCommitment, alice, encryptedPayload);

        vm.prank(alice);
        controller.mintNotes1(
            _outputNotes1(_outputNote(aliceNote.owner, aliceNote.value, aliceNote.salt)), _payloads1(encryptedPayload)
        );
    }

    function testMintNotes2CreatesTwoCommitments() public {
        vm.prank(alice);
        controller.depositToken(30 ether);

        PrivateStateController.OutputNote[2] memory outputs = _outputNotes2(
            _outputNote(alice, 10 ether, bytes32("alice-mint-2-0")),
            _outputNote(bob, 20 ether, bytes32("alice-mint-2-1"))
        );
        bytes[2] memory encryptedPayloads = _payloads2(bytes("enc:alice-mint-2-0"), bytes("enc:alice-mint-2-1"));

        vm.prank(alice);
        bytes32[2] memory commitments = controller.mintNotes2(outputs, encryptedPayloads);

        assertEq(tokenVault.liquidBalances(alice), 0);
        assertTrue(noteRegistry.commitmentExists(commitments[0]));
        assertTrue(noteRegistry.commitmentExists(commitments[1]));
    }

    function testMintNotes3CreatesThreeCommitments() public {
        vm.prank(alice);
        controller.depositToken(45 ether);

        PrivateStateController.OutputNote[3] memory outputs = _outputNotes3(
            _outputNote(alice, 10 ether, bytes32("alice-mint-3-0")),
            _outputNote(bob, 15 ether, bytes32("alice-mint-3-1")),
            _outputNote(alice, 20 ether, bytes32("alice-mint-3-2"))
        );
        bytes[3] memory encryptedPayloads =
            _payloads3(bytes("enc:alice-mint-3-0"), bytes("enc:alice-mint-3-1"), bytes("enc:alice-mint-3-2"));

        vm.prank(alice);
        bytes32[3] memory commitments = controller.mintNotes3(outputs, encryptedPayloads);

        assertEq(tokenVault.liquidBalances(alice), 0);
        for (uint256 i = 0; i < 3; ++i) {
            assertTrue(noteRegistry.commitmentExists(commitments[i]));
        }
    }

    function testCannotWithdrawMoreThanLiquidBalance() public {
        vm.prank(alice);
        controller.depositToken(10 ether);

        vm.expectRevert(
            abi.encodeWithSelector(TokenVault.InsufficientLiquidBalance.selector, alice, 10 ether, 11 ether)
        );
        vm.prank(alice);
        controller.withdrawToken(11 ether, alice);
    }

    function testStoreControllerCannotBeRebound() public {
        vm.expectRevert(TokenVault.ControllerAlreadyBound.selector);
        vm.prank(owner);
        tokenVault.bindController(mallory);

        vm.expectRevert(PrivateNoteRegistry.ControllerAlreadyBound.selector);
        vm.prank(owner);
        noteRegistry.bindController(mallory);

        vm.expectRevert(PrivateNullifierRegistry.ControllerAlreadyBound.selector);
        vm.prank(owner);
        nullifierStore.bindController(mallory);
    }

    function _mintNote(address noteOwner, uint256 value, bytes32 salt, bytes memory encryptedPayload)
        internal
        returns (PrivateStateController.InputNote memory note)
    {
        note = _inputNote(value, noteOwner, salt);
        vm.prank(noteOwner);
        controller.mintNotes1(_outputNotes1(_outputNote(noteOwner, value, salt)), _payloads1(encryptedPayload));
    }

    function _inputNote(uint256 value_, address owner_, bytes32 salt_)
        internal
        pure
        returns (PrivateStateController.InputNote memory)
    {
        return PrivateStateController.InputNote({value: value_, owner: owner_, salt: salt_});
    }

    function _outputNote(address owner_, uint256 value_, bytes32 salt_)
        internal
        pure
        returns (PrivateStateController.OutputNote memory)
    {
        return PrivateStateController.OutputNote({owner: owner_, value: value_, salt: salt_});
    }

    function _inputNotes4(
        PrivateStateController.InputNote memory note0,
        PrivateStateController.InputNote memory note1,
        PrivateStateController.InputNote memory note2,
        PrivateStateController.InputNote memory note3
    ) internal pure returns (PrivateStateController.InputNote[4] memory notes) {
        notes[0] = note0;
        notes[1] = note1;
        notes[2] = note2;
        notes[3] = note3;
    }

    function _inputNotes6(
        PrivateStateController.InputNote memory note0,
        PrivateStateController.InputNote memory note1,
        PrivateStateController.InputNote memory note2,
        PrivateStateController.InputNote memory note3,
        PrivateStateController.InputNote memory note4,
        PrivateStateController.InputNote memory note5
    ) internal pure returns (PrivateStateController.InputNote[6] memory notes) {
        notes[0] = note0;
        notes[1] = note1;
        notes[2] = note2;
        notes[3] = note3;
        notes[4] = note4;
        notes[5] = note5;
    }

    function _inputNotes8(
        PrivateStateController.InputNote memory note0,
        PrivateStateController.InputNote memory note1,
        PrivateStateController.InputNote memory note2,
        PrivateStateController.InputNote memory note3,
        PrivateStateController.InputNote memory note4,
        PrivateStateController.InputNote memory note5,
        PrivateStateController.InputNote memory note6,
        PrivateStateController.InputNote memory note7
    ) internal pure returns (PrivateStateController.InputNote[8] memory notes) {
        notes[0] = note0;
        notes[1] = note1;
        notes[2] = note2;
        notes[3] = note3;
        notes[4] = note4;
        notes[5] = note5;
        notes[6] = note6;
        notes[7] = note7;
    }

    function _outputNotes3(
        PrivateStateController.OutputNote memory note0,
        PrivateStateController.OutputNote memory note1,
        PrivateStateController.OutputNote memory note2
    ) internal pure returns (PrivateStateController.OutputNote[3] memory notes) {
        notes[0] = note0;
        notes[1] = note1;
        notes[2] = note2;
    }

    function _outputNotes1(PrivateStateController.OutputNote memory note0)
        internal
        pure
        returns (PrivateStateController.OutputNote[1] memory notes)
    {
        notes[0] = note0;
    }

    function _outputNotes2(
        PrivateStateController.OutputNote memory note0,
        PrivateStateController.OutputNote memory note1
    ) internal pure returns (PrivateStateController.OutputNote[2] memory notes) {
        notes[0] = note0;
        notes[1] = note1;
    }

    function _payloads1(bytes memory payload0) internal pure returns (bytes[1] memory payloads) {
        payloads[0] = payload0;
    }

    function _payloads2(bytes memory payload0, bytes memory payload1) internal pure returns (bytes[2] memory payloads) {
        payloads[0] = payload0;
        payloads[1] = payload1;
    }

    function _payloads3(bytes memory payload0, bytes memory payload1, bytes memory payload2)
        internal
        pure
        returns (bytes[3] memory payloads)
    {
        payloads[0] = payload0;
        payloads[1] = payload1;
        payloads[2] = payload2;
    }

    function _commitmentOf(PrivateStateController.InputNote memory note) internal view returns (bytes32) {
        return controller.computeNoteCommitment(note.value, note.owner, note.salt);
    }

    function _nullifierOf(PrivateStateController.InputNote memory note) internal view returns (bytes32) {
        return controller.computeNullifier(note.value, note.owner, note.salt);
    }
}

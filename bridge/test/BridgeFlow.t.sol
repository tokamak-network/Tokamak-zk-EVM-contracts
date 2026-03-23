// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {BridgeStructs} from "../src/BridgeStructs.sol";
import {BridgeAdminManager} from "../src/BridgeAdminManager.sol";
import {DAppManager} from "../src/DAppManager.sol";
import {BridgeCore} from "../src/BridgeCore.sol";
import {ChannelManager} from "../src/ChannelManager.sol";
import {L1TokenVault} from "../src/L1TokenVault.sol";
import {IGrothVerifier} from "../src/interfaces/IGrothVerifier.sol";
import {ITokamakVerifier} from "../src/interfaces/ITokamakVerifier.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {FeeOnTransferMockERC20} from "../src/mocks/FeeOnTransferMockERC20.sol";
import {DepositGrothProofFixture, WithdrawGrothProofFixture} from "./GrothProofFixtures.sol";
import {Groth16Verifier} from "groth16-verifier/src/Groth16Verifier.sol";
import {TokamakVerifier} from "tokamak-zkp/TokamakVerifier.sol";

contract BridgeFlowTest is Test {
    using stdJson for string;

    bytes4 internal constant APP_SIG = bytes4(keccak256("trade(uint256)"));
    bytes4 internal constant APP_SIG_2 = bytes4(keccak256("rebalance(uint256)"));
    uint256 internal constant BLS12_381_SCALAR_FIELD_MODULUS =
        0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001;
    bytes32 internal constant INITIAL_ZERO_ROOT =
        bytes32(uint256(5829984778942235508054786484586420582947187778500268001993713384889194068958));
    string internal constant TOKAMAK_FIXTURE_PATH = "test/fixtures/tokamak-proof-fixture.json";
    string internal constant REAL_TOKAMAK_PROOF_PATH =
        "../tokamak-zkp/test/fixtures/mintNotes1-proof/resource/prove/output/proof.json";
    string internal constant REAL_TOKAMAK_PREPROCESS_PATH =
        "../tokamak-zkp/test/fixtures/mintNotes1-proof/resource/preprocess/output/preprocess.json";
    string internal constant REAL_TOKAMAK_INSTANCE_PATH =
        "../tokamak-zkp/test/fixtures/mintNotes1-proof/resource/synthesizer/output/instance.json";
    address internal constant REAL_TOKAMAK_APP_STORAGE = 0x8b64A4D3DF1771d7dFC93b374f545563B680b420;

    BridgeAdminManager internal adminManager;
    DAppManager internal dAppManager;
    BridgeCore internal bridgeCore;
    Groth16Verifier internal grothVerifier;
    TokamakVerifier internal tokamakVerifier;
    MockERC20 internal asset;

    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);
    address internal leader = address(0x1EAD);
    address internal appContract = address(0xCAFE);
    address internal appContract2 = address(0xD00D);

    uint256 internal channelId = 1;
    uint256 internal secondChannelId = 2;

    ChannelManager internal channelManager;
    L1TokenVault internal tokenVault;

    function setUp() public {
        BridgeStructs.TokamakProofPayload memory tokamakFixture = _loadTokamakProofPayload();

        adminManager = new BridgeAdminManager(address(this));
        adminManager.setMerkleTreeLevels(12);

        tokamakVerifier = new TokamakVerifier();

        address vaultStorageAddr = address(0xF00D);
        address appStorageAddr = address(0x1234);
        address secondaryVaultStorageAddr = address(0xF00E);
        dAppManager = new DAppManager(address(this));
        dAppManager.registerDApp(
            1,
            keccak256("private-app"),
            _defaultStorageLayouts(vaultStorageAddr, appStorageAddr),
            _defaultDAppFunctions(
                vaultStorageAddr,
                appStorageAddr,
                _computePointEncodingHash(tokamakFixture.functionPreprocessPart1, tokamakFixture.functionPreprocessPart2)
            )
        );
        dAppManager.registerDApp(
            2,
            keccak256("alt-private-app"),
            _singleVaultStorageLayout(secondaryVaultStorageAddr),
            _singleVaultDAppFunction(secondaryVaultStorageAddr)
        );

        grothVerifier = new Groth16Verifier();
        bridgeCore = new BridgeCore(
            address(this),
            adminManager,
            dAppManager,
            IGrothVerifier(address(grothVerifier)),
            ITokamakVerifier(address(tokamakVerifier))
        );

        asset = new MockERC20("Mock Asset", "MA");
        asset.mint(alice, 1_000 ether);
        asset.mint(bob, 1_000 ether);

        (address manager, address vault) = bridgeCore.createChannel(
            channelId,
            1,
            leader,
            asset,
            keccak256(abi.encode(tokamakFixture.aPubBlock))
        );

        channelManager = ChannelManager(manager);
        tokenVault = L1TokenVault(vault);

        vm.prank(alice);
        asset.approve(address(tokenVault), type(uint256).max);
        vm.prank(bob);
        asset.approve(address(tokenVault), type(uint256).max);
    }

    function testRegisterAndFundStoresDerivedLeafIndex() public {
        bytes32 key = bytes32(uint256(5));

        vm.prank(alice);
        tokenVault.registerAndFund(key, 100 ether);

        L1TokenVault.VaultRegistration memory registration = tokenVault.getRegistration(alice);
        assertTrue(registration.exists);
        assertEq(registration.l2TokenVaultKey, key);
        assertEq(registration.leafIndex, 5);
        assertEq(registration.availableBalance, 100 ether);
        assertEq(asset.balanceOf(address(tokenVault)), 100 ether);
    }

    function testRejectsUnsupportedMerkleTreeLevels() public {
        vm.expectRevert(
            abi.encodeWithSelector(BridgeAdminManager.UnsupportedMerkleTreeLevels.selector, uint8(13), uint8(12))
        );
        adminManager.setMerkleTreeLevels(13);
    }

    function testChannelStoresManagedStorageAddressVector() public view {
        address[] memory managedStorageAddresses = channelManager.getManagedStorageAddresses();
        assertEq(managedStorageAddresses.length, 2);
        assertEq(managedStorageAddresses[0], address(0xF00D));
        assertEq(managedStorageAddresses[1], address(0x1234));

        bytes32[] memory currentRoots = channelManager.getCurrentRootVector();
        assertEq(currentRoots.length, managedStorageAddresses.length);
        assertEq(currentRoots[0], INITIAL_ZERO_ROOT);
        assertEq(currentRoots[1], INITIAL_ZERO_ROOT);
    }

    function testRejectsPerChannelLeafCollision() public {
        vm.prank(alice);
        tokenVault.registerAndFund(bytes32(uint256(1)), 10 ether);

        vm.expectRevert(abi.encodeWithSelector(BridgeCore.ChannelLeafIndexCollision.selector, channelId, 1));
        vm.prank(bob);
        tokenVault.registerAndFund(bytes32(uint256(4097)), 10 ether);
    }

    function testRejectsGlobalKeyReuseAcrossChannels() public {
        bytes32 reusedKey = bytes32(uint256(8));

        vm.prank(alice);
        tokenVault.registerAndFund(reusedKey, 10 ether);

        (, address secondVaultAddress) = bridgeCore.createChannel(
            secondChannelId,
            1,
            leader,
            asset,
            keccak256(abi.encode(_loadTokamakProofPayload().aPubBlock))
        );

        L1TokenVault secondVault = L1TokenVault(secondVaultAddress);
        vm.prank(bob);
        asset.approve(address(secondVault), type(uint256).max);

        vm.expectRevert(abi.encodeWithSelector(BridgeCore.GlobalVaultKeyAlreadyRegistered.selector, reusedKey));
        vm.prank(bob);
        secondVault.registerAndFund(reusedKey, 10 ether);
    }

    function testRejectsDAppRegistrationWithMultipleTokenVaultStorages() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                DAppManager.MultipleTokenVaultStorageAddresses.selector, 3, address(0xF00D), address(0xF00E)
            )
        );
        dAppManager.registerDApp(
            3,
            keccak256("invalid-private-app"),
            _threeStorageLayouts(address(0xF00D), address(0x1234), address(0xF00E)),
            _conflictingDAppFunctions(address(0xF00D), address(0xF00E))
        );
    }

    function testRejectsDAppRegistrationWithoutPreprocessHash() public {
        BridgeStructs.DAppFunctionMetadata[] memory functions = new BridgeStructs.DAppFunctionMetadata[](1);
        functions[0] = BridgeStructs.DAppFunctionMetadata({
            entryContract: appContract,
            functionSig: APP_SIG,
            storageAddrs: _addressArray(address(0xF00D), address(0x1234)),
            preprocessInputHash: bytes32(0)
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                DAppManager.MissingPreprocessInputHash.selector,
                uint256(3),
                appContract,
                APP_SIG
            )
        );
        dAppManager.registerDApp(
            3,
            keccak256("missing-preprocess-hash"),
            _defaultStorageLayouts(address(0xF00D), address(0x1234)),
            functions
        );
    }

    function testRejectsChannelCreationWithoutAPubBlockHash() public {
        vm.expectRevert(BridgeCore.MissingAPubBlockHash.selector);
        bridgeCore.createChannel(channelId + 100, 1, leader, asset, bytes32(0));
    }

    function testRejectsChannelCreationWithTooManyManagedStorages() public {
        BridgeStructs.StorageMetadata[] memory storages = new BridgeStructs.StorageMetadata[](12);
        for (uint256 i = 0; i < storages.length; i++) {
            storages[i] = BridgeStructs.StorageMetadata({
                storageAddr: address(uint160(0x1000 + i)),
                preAllocatedKeys: new bytes32[](0),
                userStorageSlots: new uint8[](0),
                isTokenVaultStorage: i == 0
            });
        }

        BridgeStructs.DAppFunctionMetadata[] memory functions = new BridgeStructs.DAppFunctionMetadata[](1);
        address[] memory storageAddrs = new address[](storages.length);
        for (uint256 i = 0; i < storages.length; i++) {
            storageAddrs[i] = storages[i].storageAddr;
        }
        functions[0] = BridgeStructs.DAppFunctionMetadata({
            entryContract: appContract,
            functionSig: APP_SIG,
            storageAddrs: storageAddrs,
            preprocessInputHash: bytes32("PREPROCESS_INPUT")
        });

        dAppManager.registerDApp(3, keccak256("oversized-dapp"), storages, functions);

        vm.expectRevert(
            abi.encodeWithSelector(BridgeCore.TooManyManagedStorages.selector, uint256(12), uint256(11))
        );
        bridgeCore.createChannel(channelId + 101, 3, leader, asset, keccak256("block"));
    }

    function testGrothDepositUpdatesVaultStateAndRootVector() public {
        bytes32 key = bytes32(uint256(111));
        vm.prank(alice);
        tokenVault.registerAndFund(key, 100 ether);

        uint256[5] memory pubSignals = _depositPublicSignals();
        BridgeStructs.GrothUpdate memory update = BridgeStructs.GrothUpdate({
            currentRoot: bytes32(pubSignals[0]),
            updatedRoot: bytes32(pubSignals[1]),
            currentUserKey: key,
            currentUserValue: pubSignals[3],
            updatedUserKey: key,
            updatedUserValue: pubSignals[4]
        });

        vm.prank(alice);
        tokenVault.deposit(_depositProof(), update);

        L1TokenVault.VaultRegistration memory registration = tokenVault.getRegistration(alice);
        assertEq(registration.availableBalance, 100 ether - 10);

        bytes32[] memory currentRoots = channelManager.getCurrentRootVector();
        assertEq(currentRoots[0], bytes32(pubSignals[1]));
        assertEq(
            channelManager.getLatestTokenVaultLeaf(registration.leafIndex),
            tokenVault.encodeTokenVaultLeaf(bytes32(0), 10)
        );
    }

    function testGrothWithdrawAndClaimToWallet() public {
        bytes32 key = bytes32(uint256(111));
        vm.prank(alice);
        tokenVault.registerAndFund(key, 100 ether);

        uint256[5] memory depositSignals = _depositPublicSignals();
        BridgeStructs.GrothUpdate memory depositUpdate = BridgeStructs.GrothUpdate({
            currentRoot: bytes32(depositSignals[0]),
            updatedRoot: bytes32(depositSignals[1]),
            currentUserKey: key,
            currentUserValue: depositSignals[3],
            updatedUserKey: key,
            updatedUserValue: depositSignals[4]
        });
        vm.prank(alice);
        tokenVault.deposit(_depositProof(), depositUpdate);

        uint256[5] memory withdrawSignals = _withdrawPublicSignals();
        BridgeStructs.GrothUpdate memory withdrawUpdate = BridgeStructs.GrothUpdate({
            currentRoot: bytes32(withdrawSignals[0]),
            updatedRoot: bytes32(withdrawSignals[1]),
            currentUserKey: key,
            currentUserValue: withdrawSignals[3],
            updatedUserKey: key,
            updatedUserValue: withdrawSignals[4]
        });
        vm.prank(alice);
        tokenVault.withdraw(_withdrawProof(), withdrawUpdate);

        L1TokenVault.VaultRegistration memory registration = tokenVault.getRegistration(alice);
        assertEq(registration.availableBalance, 100 ether - 4);

        uint256 aliceBalanceBefore = asset.balanceOf(alice);
        vm.prank(alice);
        tokenVault.claimToWallet(50 ether);
        assertEq(asset.balanceOf(alice), aliceBalanceBefore + 50 ether);
    }

    function testRejectsFeeOnTransferAssetDuringRegistration() public {
        FeeOnTransferMockERC20 feeAsset = new FeeOnTransferMockERC20("Fee Asset", "FEE", 100, address(0xFEE));
        feeAsset.mint(alice, 100 ether);

        (address manager, address vault) =
            bridgeCore.createChannel(channelId + 102, 1, leader, feeAsset, keccak256(abi.encode(_loadTokamakProofPayload().aPubBlock)));

        manager;
        L1TokenVault feeVault = L1TokenVault(vault);
        vm.prank(alice);
        feeAsset.approve(address(feeVault), type(uint256).max);

        vm.expectRevert(
            abi.encodeWithSelector(L1TokenVault.UnsupportedAssetTransferBehavior.selector, 100 ether, 99 ether)
        );
        vm.prank(alice);
        feeVault.registerAndFund(bytes32(uint256(7)), 100 ether);
    }

    function testDepositRejectsL2ValueAtScalarFieldModulus() public {
        bytes32 key = bytes32(uint256(111));
        vm.prank(alice);
        tokenVault.registerAndFund(key, 100 ether);

        BridgeStructs.GrothUpdate memory update = BridgeStructs.GrothUpdate({
            currentRoot: bytes32(_depositPublicSignals()[0]),
            updatedRoot: bytes32(_depositPublicSignals()[1]),
            currentUserKey: key,
            currentUserValue: 0,
            updatedUserKey: key,
            updatedUserValue: BLS12_381_SCALAR_FIELD_MODULUS
        });

        vm.expectRevert(
            abi.encodeWithSelector(L1TokenVault.L2ValueOutOfRange.selector, BLS12_381_SCALAR_FIELD_MODULUS)
        );
        vm.prank(alice);
        tokenVault.deposit(_depositProof(), update);
    }

    function testWithdrawRejectsCurrentL2ValueAtScalarFieldModulus() public {
        bytes32 key = bytes32(uint256(111));
        vm.prank(alice);
        tokenVault.registerAndFund(key, 100 ether);

        BridgeStructs.GrothUpdate memory update = BridgeStructs.GrothUpdate({
            currentRoot: bytes32(_withdrawPublicSignals()[0]),
            updatedRoot: bytes32(_withdrawPublicSignals()[1]),
            currentUserKey: key,
            currentUserValue: BLS12_381_SCALAR_FIELD_MODULUS,
            updatedUserKey: key,
            updatedUserValue: 0
        });

        vm.expectRevert(
            abi.encodeWithSelector(L1TokenVault.L2ValueOutOfRange.selector, BLS12_381_SCALAR_FIELD_MODULUS)
        );
        vm.prank(alice);
        tokenVault.withdraw(_withdrawProof(), update);
    }

    function testTokamakVerificationRejectsUnsupportedFunction() public {
        BridgeStructs.TokamakProofPayload memory proofPayload = _blankTokamakProofPayload();
        proofPayload.aPubUser[22] = uint160(address(0xBEEF));
        proofPayload.aPubUser[24] = uint32(APP_SIG);
        _writeSplitWord(proofPayload.aPubUser, 26, uint256(INITIAL_ZERO_ROOT));
        _writeSplitWord(proofPayload.aPubUser, 28, uint256(INITIAL_ZERO_ROOT));

        BridgeStructs.TokamakTransactionInstance memory instance = BridgeStructs.TokamakTransactionInstance({
            currentRootVector: _rootVector(INITIAL_ZERO_ROOT, INITIAL_ZERO_ROOT),
            updatedRootVector: _rootVector(bytes32(0), bytes32(0)),
            entryContract: address(0xBEEF),
            functionSig: APP_SIG
        });

        vm.expectRevert(
            abi.encodeWithSelector(ChannelManager.UnsupportedChannelFunction.selector, address(0xBEEF), APP_SIG)
        );
        channelManager.submitTokamakProof(abi.encode(proofPayload), instance);
    }

    function testTokamakVerificationRejectsEntryContractMismatchAgainstAPubUser() public {
        BridgeStructs.TokamakProofPayload memory proofPayload = _loadTokamakProofPayload();
        BridgeStructs.TokamakTransactionInstance memory instance = BridgeStructs.TokamakTransactionInstance({
            currentRootVector: _currentRootsFromAPubUser(proofPayload.aPubUser),
            updatedRootVector: _updatedRootsFromAPubUser(proofPayload.aPubUser),
            entryContract: address(0xBEEF),
            functionSig: _functionSigFromAPubUser(proofPayload.aPubUser)
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                ChannelManager.EntryContractPublicInputMismatch.selector,
                address(0xBEEF),
                _entryContractFromAPubUser(proofPayload.aPubUser)
            )
        );
        channelManager.submitTokamakProof(abi.encode(proofPayload), instance);
    }

    function testTokamakVerificationRejectsUpdatedRootMismatchAgainstAPubUser() public {
        BridgeStructs.TokamakProofPayload memory proofPayload = _loadTokamakProofPayload();
        bytes32[] memory updatedRoots = _updatedRootsFromAPubUser(proofPayload.aPubUser);
        updatedRoots[0] = bytes32(uint256(updatedRoots[0]) + 1);

        BridgeStructs.TokamakTransactionInstance memory instance = BridgeStructs.TokamakTransactionInstance({
            currentRootVector: _currentRootsFromAPubUser(proofPayload.aPubUser),
            updatedRootVector: updatedRoots,
            entryContract: _entryContractFromAPubUser(proofPayload.aPubUser),
            functionSig: _functionSigFromAPubUser(proofPayload.aPubUser)
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                ChannelManager.UpdatedRootVectorPublicInputMismatch.selector,
                uint256(0),
                updatedRoots[0],
                _updatedRootsFromAPubUser(proofPayload.aPubUser)[0]
            )
        );
        channelManager.submitTokamakProof(abi.encode(proofPayload), instance);
    }

    function testChannelUsesRealTokamakVerifier() public view {
        assertEq(address(bridgeCore.tokamakVerifier()), address(tokamakVerifier));
    }

    function testTokamakVerificationRejectsProofForUnexpectedCurrentState() public {
        BridgeStructs.TokamakProofPayload memory proofPayload = _loadTokamakProofPayload();
        BridgeStructs.TokamakTransactionInstance memory instance = BridgeStructs.TokamakTransactionInstance({
            currentRootVector: _currentRootsFromAPubUser(proofPayload.aPubUser),
            updatedRootVector: _updatedRootsFromAPubUser(proofPayload.aPubUser),
            entryContract: _entryContractFromAPubUser(proofPayload.aPubUser),
            functionSig: _functionSigFromAPubUser(proofPayload.aPubUser)
        });

        vm.expectRevert(ChannelManager.UnexpectedCurrentRootVector.selector);
        channelManager.submitTokamakProof(abi.encode(proofPayload), instance);
    }

    function testTokamakVerificationAcceptsRealProofBundleAfterSeedingVerifiedPreState() public {
        BridgeStructs.TokamakProofPayload memory proofPayload = _loadRealTokamakProofPayload();
        address entryContract = _entryContractFromAPubUser(proofPayload.aPubUser);
        bytes4 functionSig = _functionSigFromAPubUser(proofPayload.aPubUser);

        BridgeAdminManager localAdminManager = new BridgeAdminManager(address(this));
        localAdminManager.setMerkleTreeLevels(12);

        DAppManager localDAppManager = new DAppManager(address(this));
        localDAppManager.registerDApp(
            99,
            keccak256("real-proof-private-state"),
            _realTokamakStorageLayouts(entryContract, REAL_TOKAMAK_APP_STORAGE),
            _realTokamakFunctions(
                entryContract,
                functionSig,
                REAL_TOKAMAK_APP_STORAGE,
                _computePointEncodingHash(proofPayload.functionPreprocessPart1, proofPayload.functionPreprocessPart2)
            )
        );

        Groth16Verifier localGrothVerifier = new Groth16Verifier();
        BridgeCore localBridgeCore = new BridgeCore(
            address(this),
            localAdminManager,
            localDAppManager,
            IGrothVerifier(address(localGrothVerifier)),
            ITokamakVerifier(address(tokamakVerifier))
        );
        MockERC20 localAsset = new MockERC20("Bridge Positive Path Asset", "BPPA");

        (address manager,) =
            localBridgeCore.createChannel(99, 99, leader, localAsset, keccak256(abi.encode(proofPayload.aPubBlock)));

        ChannelManager localChannelManager = ChannelManager(manager);
        bytes32[] memory currentRoots = _currentRootsFromAPubUser(proofPayload.aPubUser);
        bytes32[] memory updatedRoots = _updatedRootsFromAPubUser(proofPayload.aPubUser);

        // The extracted proof bundle starts from an already-updated channel state rather than the bridge's zero root.
        _seedChannelCurrentRoots(localChannelManager, currentRoots);

        BridgeStructs.TokamakTransactionInstance memory instance = BridgeStructs.TokamakTransactionInstance({
            currentRootVector: currentRoots,
            updatedRootVector: updatedRoots,
            entryContract: entryContract,
            functionSig: functionSig
        });

        bool accepted = localChannelManager.submitTokamakProof(abi.encode(proofPayload), instance);
        assertTrue(accepted);

        bytes32[] memory resultingRoots = localChannelManager.getCurrentRootVector();
        assertEq(resultingRoots.length, updatedRoots.length);
        for (uint256 i = 0; i < updatedRoots.length; i++) {
            assertEq(resultingRoots[i], updatedRoots[i]);
        }
    }

    function _loadTokamakProofPayload()
        internal
        returns (BridgeStructs.TokamakProofPayload memory payload)
    {
        string memory json = vm.readFile(TOKAMAK_FIXTURE_PATH);

        payload.proofPart1 = _toUint128Array(json.readUintArray(".proofPart1"));
        payload.proofPart2 = json.readUintArray(".proofPart2");
        payload.functionPreprocessPart1 = _toUint128Array(json.readUintArray(".functionPreprocessPart1"));
        payload.functionPreprocessPart2 = json.readUintArray(".functionPreprocessPart2");
        uint256[] memory publicInputs = json.readUintArray(".publicInputs");
        payload.aPubUser = _slice(publicInputs, 0, 50);
        payload.aPubBlock = _slice(publicInputs, 50, 78);
    }

    function _loadRealTokamakProofPayload()
        internal
        returns (BridgeStructs.TokamakProofPayload memory payload)
    {
        string memory proofJson = vm.readFile(REAL_TOKAMAK_PROOF_PATH);
        string memory preprocessJson = vm.readFile(REAL_TOKAMAK_PREPROCESS_PATH);
        string memory instanceJson = vm.readFile(REAL_TOKAMAK_INSTANCE_PATH);

        payload.proofPart1 = _toUint128Array(proofJson.readUintArray(".proof_entries_part1"));
        payload.proofPart2 = proofJson.readUintArray(".proof_entries_part2");
        payload.functionPreprocessPart1 =
            _toUint128Array(preprocessJson.readUintArray(".preprocess_entries_part1"));
        payload.functionPreprocessPart2 = preprocessJson.readUintArray(".preprocess_entries_part2");
        payload.aPubUser = instanceJson.readUintArray(".a_pub_user");
        payload.aPubBlock = instanceJson.readUintArray(".a_pub_block");
    }

    function _rootVector(bytes32 left, bytes32 right) internal pure returns (bytes32[] memory roots) {
        roots = new bytes32[](2);
        roots[0] = left;
        roots[1] = right;
    }

    function _updatedRootsFromAPubUser(uint256[] memory aPubUser) internal pure returns (bytes32[] memory roots) {
        roots = new bytes32[](2);
        roots[0] = _decodeBytes32FromSplitWords(aPubUser, 0);
        roots[1] = _decodeBytes32FromSplitWords(aPubUser, 2);
    }

    function _currentRootsFromAPubUser(uint256[] memory aPubUser) internal pure returns (bytes32[] memory roots) {
        roots = new bytes32[](2);
        roots[0] = _decodeBytes32FromSplitWords(aPubUser, 26);
        roots[1] = _decodeBytes32FromSplitWords(aPubUser, 28);
    }

    function _entryContractFromAPubUser(uint256[] memory aPubUser) internal pure returns (address) {
        return address(uint160(_decodeUint256FromSplitWords(aPubUser, 22)));
    }

    function _functionSigFromAPubUser(uint256[] memory aPubUser) internal pure returns (bytes4) {
        return bytes4(uint32(_decodeUint256FromSplitWords(aPubUser, 24)));
    }

    function _defaultStorageLayouts(address tokenVaultStorage, address appStorage)
        internal
        pure
        returns (BridgeStructs.StorageMetadata[] memory storageLayouts)
    {
        storageLayouts = new BridgeStructs.StorageMetadata[](2);
        storageLayouts[0] = BridgeStructs.StorageMetadata({
            storageAddr: tokenVaultStorage,
            preAllocatedKeys: _bytes32Array(bytes32(uint256(0))),
            userStorageSlots: _uint8Array(0),
            isTokenVaultStorage: true
        });
        storageLayouts[1] = BridgeStructs.StorageMetadata({
            storageAddr: appStorage,
            preAllocatedKeys: _bytes32Array(bytes32(uint256(1))),
            userStorageSlots: _uint8Array(0),
            isTokenVaultStorage: false
        });
    }

    function _realTokamakStorageLayouts(address entryContract, address appStorage)
        internal
        pure
        returns (BridgeStructs.StorageMetadata[] memory storageLayouts)
    {
        storageLayouts = new BridgeStructs.StorageMetadata[](2);
        storageLayouts[0] = BridgeStructs.StorageMetadata({
            storageAddr: entryContract,
            preAllocatedKeys: new bytes32[](0),
            userStorageSlots: new uint8[](0),
            isTokenVaultStorage: false
        });
        storageLayouts[1] = BridgeStructs.StorageMetadata({
            storageAddr: appStorage,
            preAllocatedKeys: new bytes32[](0),
            userStorageSlots: new uint8[](0),
            isTokenVaultStorage: true
        });
    }

    function _singleVaultStorageLayout(address tokenVaultStorage)
        internal
        pure
        returns (BridgeStructs.StorageMetadata[] memory storageLayouts)
    {
        storageLayouts = new BridgeStructs.StorageMetadata[](1);
        storageLayouts[0] = BridgeStructs.StorageMetadata({
            storageAddr: tokenVaultStorage,
            preAllocatedKeys: _bytes32Array(bytes32(uint256(2))),
            userStorageSlots: _uint8Array(0),
            isTokenVaultStorage: true
        });
    }

    function _threeStorageLayouts(address firstVaultStorage, address appStorage, address secondVaultStorage)
        internal
        pure
        returns (BridgeStructs.StorageMetadata[] memory storageLayouts)
    {
        storageLayouts = new BridgeStructs.StorageMetadata[](3);
        storageLayouts[0] = BridgeStructs.StorageMetadata({
            storageAddr: firstVaultStorage,
            preAllocatedKeys: _bytes32Array(bytes32(uint256(0))),
            userStorageSlots: _uint8Array(0),
            isTokenVaultStorage: true
        });
        storageLayouts[1] = BridgeStructs.StorageMetadata({
            storageAddr: appStorage,
            preAllocatedKeys: _bytes32Array(bytes32(uint256(1))),
            userStorageSlots: _uint8Array(0),
            isTokenVaultStorage: false
        });
        storageLayouts[2] = BridgeStructs.StorageMetadata({
            storageAddr: secondVaultStorage,
            preAllocatedKeys: _bytes32Array(bytes32(uint256(2))),
            userStorageSlots: _uint8Array(0),
            isTokenVaultStorage: true
        });
    }

    function _defaultDAppFunctions(
        address tokenVaultStorage,
        address appStorage,
        bytes32 preprocessInputHash
    )
        internal
        view
        returns (BridgeStructs.DAppFunctionMetadata[] memory functions)
    {
        functions = new BridgeStructs.DAppFunctionMetadata[](1);
        functions[0] = BridgeStructs.DAppFunctionMetadata({
            entryContract: appContract,
            functionSig: APP_SIG,
            storageAddrs: _addressArray(tokenVaultStorage, appStorage),
            preprocessInputHash: preprocessInputHash
        });
    }

    function _singleVaultDAppFunction(address tokenVaultStorage)
        internal
        view
        returns (BridgeStructs.DAppFunctionMetadata[] memory functions)
    {
        functions = new BridgeStructs.DAppFunctionMetadata[](1);
        functions[0] = BridgeStructs.DAppFunctionMetadata({
            entryContract: appContract2,
            functionSig: APP_SIG_2,
            storageAddrs: _singleAddressArray(tokenVaultStorage),
            preprocessInputHash: bytes32("PREPROCESS_INPUT_2")
        });
    }

    function _realTokamakFunctions(
        address entryContract,
        bytes4 functionSig,
        address appStorage,
        bytes32 preprocessInputHash
    )
        internal
        pure
        returns (BridgeStructs.DAppFunctionMetadata[] memory functions)
    {
        functions = new BridgeStructs.DAppFunctionMetadata[](1);
        functions[0] = BridgeStructs.DAppFunctionMetadata({
            entryContract: entryContract,
            functionSig: functionSig,
            storageAddrs: _addressArray(entryContract, appStorage),
            preprocessInputHash: preprocessInputHash
        });
    }

    function _conflictingDAppFunctions(address firstVaultStorage, address secondVaultStorage)
        internal
        view
        returns (BridgeStructs.DAppFunctionMetadata[] memory functions)
    {
        functions = new BridgeStructs.DAppFunctionMetadata[](2);
        functions[0] = BridgeStructs.DAppFunctionMetadata({
            entryContract: appContract,
            functionSig: APP_SIG,
            storageAddrs: _addressArray(firstVaultStorage, address(0x1234)),
            preprocessInputHash: bytes32("PREPROCESS_INPUT")
        });
        functions[1] = BridgeStructs.DAppFunctionMetadata({
            entryContract: appContract2,
            functionSig: APP_SIG_2,
            storageAddrs: _singleAddressArray(secondVaultStorage),
            preprocessInputHash: bytes32("PREPROCESS_INPUT_2")
        });
    }

    function _addressArray(address first, address second)
        internal
        pure
        returns (address[] memory addrs)
    {
        addrs = new address[](2);
        addrs[0] = first;
        addrs[1] = second;
    }

    function _singleAddressArray(address value) internal pure returns (address[] memory addrs) {
        addrs = new address[](1);
        addrs[0] = value;
    }

    function _blankTokamakProofPayload()
        internal
        pure
        returns (BridgeStructs.TokamakProofPayload memory payload)
    {
        payload.proofPart1 = new uint128[](0);
        payload.proofPart2 = new uint256[](0);
        payload.functionPreprocessPart1 = new uint128[](0);
        payload.functionPreprocessPart2 = new uint256[](0);
        payload.aPubUser = new uint256[](50);
        payload.aPubBlock = new uint256[](78);
    }

    function _decodeBytes32FromSplitWords(uint256[] memory words, uint256 offset) internal pure returns (bytes32) {
        return bytes32(_decodeUint256FromSplitWords(words, offset));
    }

    function _decodeUint256FromSplitWords(uint256[] memory words, uint256 offset) internal pure returns (uint256) {
        return words[offset] | (words[offset + 1] << 128);
    }

    function _writeSplitWord(uint256[] memory words, uint256 offset, uint256 value) internal pure {
        words[offset] = uint128(value);
        words[offset + 1] = uint128(value >> 128);
    }

    function _depositProof() private pure returns (BridgeStructs.GrothProof memory proof) {
        proof = BridgeStructs.GrothProof({
            pA: DepositGrothProofFixture.pA(),
            pB: DepositGrothProofFixture.pB(),
            pC: DepositGrothProofFixture.pC()
        });
    }

    function _withdrawProof() private pure returns (BridgeStructs.GrothProof memory proof) {
        proof = BridgeStructs.GrothProof({
            pA: WithdrawGrothProofFixture.pA(),
            pB: WithdrawGrothProofFixture.pB(),
            pC: WithdrawGrothProofFixture.pC()
        });
    }

    function _depositPublicSignals() private pure returns (uint256[5] memory values) {
        values = [
            uint256(5829984778942235508054786484586420582947187778500268001993713384889194068958),
            uint256(12649971214846735256928973055327082315338775527920953067671803034981096374020),
            uint256(111),
            uint256(0),
            uint256(10)
        ];
    }

    function _withdrawPublicSignals() private pure returns (uint256[5] memory values) {
        values = [
            uint256(12649971214846735256928973055327082315338775527920953067671803034981096374020),
            uint256(6561881689766049952519769904166055391395720462224322729436837786896958711256),
            uint256(111),
            uint256(10),
            uint256(4)
        ];
    }

    function _bytes32Array(bytes32 value) internal pure returns (bytes32[] memory out) {
        out = new bytes32[](1);
        out[0] = value;
    }

    function _uint8Array(uint8 value) internal pure returns (uint8[] memory out) {
        out = new uint8[](1);
        out[0] = value;
    }

    function _toUint128Array(uint256[] memory values) internal pure returns (uint128[] memory out) {
        out = new uint128[](values.length);
        for (uint256 i = 0; i < values.length; i++) {
            out[i] = uint128(values[i]);
        }
    }

    function _slice(uint256[] memory values, uint256 start, uint256 length)
        internal
        pure
        returns (uint256[] memory out)
    {
        out = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            out[i] = values[start + i];
        }
    }

    function _computePointEncodingHash(uint128[] memory part1, uint256[] memory part2)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(part1, part2));
    }

    function _seedChannelCurrentRoots(ChannelManager targetChannelManager, bytes32[] memory currentRoots) internal {
        vm.store(address(targetChannelManager), bytes32(uint256(1)), bytes32(currentRoots.length));
        bytes32 dataBaseSlot = keccak256(abi.encode(uint256(1)));
        for (uint256 i = 0; i < currentRoots.length; i++) {
            vm.store(address(targetChannelManager), bytes32(uint256(dataBaseSlot) + i), currentRoots[i]);
        }
    }
}

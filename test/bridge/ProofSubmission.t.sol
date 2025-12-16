// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import "forge-std/Test.sol";
import "../../src/BridgeCore.sol";
import "../../src/BridgeProofManager.sol";
import "../../src/BridgeDepositManager.sol";
import "../../src/BridgeWithdrawManager.sol";
import "../../src/BridgeAdminManager.sol";
import "../../src/interface/ITokamakVerifier.sol";
import "../../src/interface/IZecFrost.sol";
import "../../src/interface/IGroth16Verifier16Leaves.sol";
import {ZecFrost} from "../../src/library/ZecFrost.sol";
import {TokamakVerifier} from "../../src/verifier/TokamakVerifier.sol";
import {Groth16Verifier16Leaves} from "../../src/verifier/Groth16Verifier16Leaves.sol";
import {Groth16Verifier32Leaves} from "../../src/verifier/Groth16Verifier32Leaves.sol";
import {Groth16Verifier64Leaves} from "../../src/verifier/Groth16Verifier64Leaves.sol";
import {Groth16Verifier128Leaves} from "../../src/verifier/Groth16Verifier128Leaves.sol";
import "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/token/ERC20/ERC20.sol";

contract MockTokamakVerifier is ITokamakVerifier {
    bool public shouldVerify = true;

    function setShouldVerify(bool _should) external {
        shouldVerify = _should;
    }

    function verify(
        uint128[] calldata,
        uint256[] calldata,
        uint128[] calldata,
        uint256[] calldata,
        uint256[] calldata,
        uint256
    ) external view override returns (bool) {
        return shouldVerify;
    }
}

contract MockZecFrost is IZecFrost {
    address public mockSigner;

    // Mapping of signature vectors to their recovered addresses
    mapping(bytes32 => address) private signatureVectorToSigner;

    constructor() {
        mockSigner = address(this);

        // Vector 1 signature (valid) - recovers to user1 (0xd96b35D012879d89cfBA6fE215F1015863a6f6d0)
        bytes32 vector1Key = keccak256(
            abi.encodePacked(
                uint256(0x1fb4c0436e9054ae0b237cde3d7a478ce82405b43fdbb5bf1d63c9f8d912dd5d),
                uint256(0x3a7784df441925a8859b9f3baf8d570d488493506437db3ccf230a4b43b27c1e),
                uint256(0xc7fdcb364dd8577e47dd479185ca659adbfcd1b8675e5cbb36e5f93ca4e15b25)
            )
        );
        signatureVectorToSigner[vector1Key] = 0xd96b35D012879d89cfBA6fE215F1015863a6f6d0;

        // Vector 2 signature (invalid) - recovers to user2 (0x012C2171f631e27C4bA9f7f8262af2a48956939A)
        bytes32 vector2Key = keccak256(
            abi.encodePacked(
                uint256(0xc303bb5de5a5962d9af9b45f5e0bdc919de2aac9153b8c353960f50aa3cb950c),
                uint256(0x6df25261f523a8ea346f49dad49b3b36786e653a129cff327a0fea5839e712a2),
                uint256(0x27c26d628367261edb63b64eefc48a192a8130e9cd608b75820775684af010b0)
            )
        );
        signatureVectorToSigner[vector2Key] = 0x012C2171f631e27C4bA9f7f8262af2a48956939A;
    }

    function verify(bytes32, uint256, uint256, uint256, uint256, uint256) external view override returns (address) {
        // Simply return the mock signer for all signatures
        return mockSigner;
    }

    function setMockSigner(address _signer) external {
        mockSigner = _signer;
    }
}

contract MockGroth16Verifier is IGroth16Verifier16Leaves {
    bool public shouldVerify = true;

    function setShouldVerify(bool _should) external {
        shouldVerify = _should;
    }

    function verifyProof(uint256[4] calldata, uint256[8] calldata, uint256[4] calldata, uint256[33] calldata)
        external
        view
        override
        returns (bool)
    {
        return shouldVerify;
    }
}

contract MockGroth16Verifier32 is IGroth16Verifier32Leaves {
    bool public shouldVerify = true;

    function setShouldVerify(bool _should) external {
        shouldVerify = _should;
    }

    function verifyProof(uint256[4] calldata, uint256[8] calldata, uint256[4] calldata, uint256[65] calldata)
        external
        view
        override
        returns (bool)
    {
        return shouldVerify;
    }
}

contract MockGroth16Verifier64 is IGroth16Verifier64Leaves {
    bool public shouldVerify = true;

    function setShouldVerify(bool _should) external {
        shouldVerify = _should;
    }

    function verifyProof(uint256[4] calldata, uint256[8] calldata, uint256[4] calldata, uint256[129] calldata)
        external
        view
        override
        returns (bool)
    {
        return shouldVerify;
    }
}

contract MockGroth16Verifier128 is IGroth16Verifier128Leaves {
    bool public shouldVerify = true;

    function setShouldVerify(bool _should) external {
        shouldVerify = _should;
    }

    function verifyProof(uint256[4] calldata, uint256[8] calldata, uint256[4] calldata, uint256[257] calldata)
        external
        view
        override
        returns (bool)
    {
        return shouldVerify;
    }
}

contract MockERC20 is ERC20 {
    constructor() ERC20("Mock Token", "MOCK") {
        _mint(msg.sender, 1000000 * 10 ** 18);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract ProofSubmissionTest is Test {
    uint256 public constant INITIAL_BALANCE = 1000 ether;
    uint256 public constant INITIAL_TOKEN_BALANCE = 1000 * 10 ** 18;

    BridgeCore public bridge;
    BridgeProofManager public proofManager;
    BridgeDepositManager public depositManager;
    BridgeWithdrawManager public withdrawManager;
    BridgeAdminManager public adminManager;
    TokamakVerifier public tokamakVerifier;
    MockZecFrost public mockZecFrost;
    MockGroth16Verifier public groth16Verifier16;
    MockGroth16Verifier32 public groth16Verifier32;
    MockGroth16Verifier64 public groth16Verifier64;
    MockGroth16Verifier128 public groth16Verifier128;
    MockERC20 public token;

    address public owner = address(1);
    address public user1 = 0xF9Fa94D45C49e879E46Ea783fc133F41709f3bc7;
    address public user2 = 0x322acfaA747F3CE5b5899611034FB4433f0Edf34;
    address public user3 = 0x31Fbd690BF62cd8C60A93F3aD8E96A6085Dc5647;

    uint256 public User1l2MPTKey = 0x5846aca7f69c5df6171620f9fe93a0b0071057dbeaea943382e36283d98d3164;
    uint256 public User2l2MPTKey = 0x30cb74383499705597743f7ebc89ac8514034e4525cc903fb79eb32ace584be7;
    uint256 public User3l2MPTKey = 0x2cba90f17ac312557f5d3eb10891ce57e40bf513a8ae0dbbf153ef6fafd5d9eb;

    uint256 public user1DepositValue = 1000000000000000000;
    uint256 public user2DepositValue = 1000000000000000000;
    uint256 public user3DepositValue = 1000000000000000000;

    // Storage arrays for proof data (similar to Verifier.t.sol)
    uint128[] public proofPart1;
    uint256[] public proofPart2;
    uint256[] public publicInputs;

    function setUp() public {
        // Deploy contracts
        vm.startPrank(owner);

        tokamakVerifier = new TokamakVerifier();
        mockZecFrost = new MockZecFrost();
        groth16Verifier16 = new MockGroth16Verifier();
        groth16Verifier32 = new MockGroth16Verifier32();
        groth16Verifier64 = new MockGroth16Verifier64();
        groth16Verifier128 = new MockGroth16Verifier128();
        token = new MockERC20();

        // Deploy manager implementations
        BridgeDepositManager depositManagerImpl = new BridgeDepositManager();
        BridgeWithdrawManager withdrawManagerImpl = new BridgeWithdrawManager();
        BridgeAdminManager adminManagerImpl = new BridgeAdminManager();
        BridgeProofManager proofManagerImpl = new BridgeProofManager();

        // Deploy core contract with proxy first
        BridgeCore implementation = new BridgeCore();
        bytes memory bridgeInitData = abi.encodeCall(
            BridgeCore.initialize,
            (address(0), address(0), address(0), address(0), owner) // Temporary addresses
        );
        ERC1967Proxy bridgeProxy = new ERC1967Proxy(address(implementation), bridgeInitData);
        bridge = BridgeCore(address(bridgeProxy));

        // Deploy manager proxies with bridge address
        bytes memory depositInitData = abi.encodeCall(BridgeDepositManager.initialize, (address(bridge), owner));
        ERC1967Proxy depositProxy = new ERC1967Proxy(address(depositManagerImpl), depositInitData);
        depositManager = BridgeDepositManager(address(depositProxy));

        bytes memory withdrawInitData = abi.encodeCall(BridgeWithdrawManager.initialize, (address(bridge), owner));
        ERC1967Proxy withdrawProxy = new ERC1967Proxy(address(withdrawManagerImpl), withdrawInitData);
        withdrawManager = BridgeWithdrawManager(payable(address(withdrawProxy)));

        bytes memory adminInitData = abi.encodeCall(BridgeAdminManager.initialize, (address(bridge), owner));
        ERC1967Proxy adminProxy = new ERC1967Proxy(address(adminManagerImpl), adminInitData);
        adminManager = BridgeAdminManager(address(adminProxy));

        address[4] memory groth16Verifiers = [
            address(groth16Verifier16),
            address(groth16Verifier32),
            address(groth16Verifier64),
            address(groth16Verifier128)
        ];
        bytes memory proofInitData = abi.encodeCall(
            BridgeProofManager.initialize,
            (address(bridge), address(tokamakVerifier), address(mockZecFrost), groth16Verifiers, owner)
        );
        ERC1967Proxy proofProxy = new ERC1967Proxy(address(proofManagerImpl), proofInitData);
        proofManager = BridgeProofManager(address(proofProxy));

        // Update bridge with manager addresses
        bridge.updateManagerAddresses(
            address(depositManager), address(proofManager), address(withdrawManager), address(adminManager)
        );

        // Configure mock ZecFrost - we'll set the actual expected signer later in tests

        // Fund test accounts
        vm.deal(user1, INITIAL_BALANCE);
        vm.deal(user2, INITIAL_BALANCE);
        vm.deal(user3, INITIAL_BALANCE);

        token.mint(user1, INITIAL_TOKEN_BALANCE);
        token.mint(user2, INITIAL_TOKEN_BALANCE);
        token.mint(user3, INITIAL_TOKEN_BALANCE);

        // correct preprocess for ton transfer function
        uint128[] memory preprocessedPart1 = new uint128[](4);
        preprocessedPart1[0] = 0x06ff9cd406006fe268f46632127797b4;
        preprocessedPart1[1] = 0x102596c7f24bd535978293a0410c5c9f;
        preprocessedPart1[2] = 0x12a9229904b6f245ca7db3fcba70c6a1;
        preprocessedPart1[3] = 0x13957ffacab24d44d4340517764334d6;
        uint256[] memory preprocessedPart2 = new uint256[](4);
        preprocessedPart2[0] = 0xc02e6272910efe491543bfa526c1d4cbc4088d53f830e87216f31379b37fbe8b;
        preprocessedPart2[1] = 0x3dec5512f9b8522a03f0a0e2b7b820cf58c0b59896392281ea3a0b1a531116c5;
        preprocessedPart2[2] = 0xd500a0746c560be56a2a2bf0e8ffcb0a48d95154c1744c32a989b2b8ab7cc6d7;
        preprocessedPart2[3] = 0x3309be45c3359e078db5f1473f69bfdb4aec50caf827812f1c670c8ca9de396c;

        IBridgeCore.PreAllocatedLeaf[] memory emptySlots = new IBridgeCore.PreAllocatedLeaf[](0);
        adminManager.setAllowedTargetContract(address(token), emptySlots, true);

        // Set pre-allocated leaf with key 0x07 and value 18 (for decimals)
        adminManager.setPreAllocatedLeaf(address(token), bytes32(uint256(0x07)), 18);

        // Use the correct function instance hash computed from channel5_proof1.json data (starting at index 64)
        bytes32 functionInstanceHash = 0xd157cb883adb9cb0e27d9dc419e2a4be817d856281b994583b5bae64be94d35a;

        // Register transfer function using the selector from the proof (0xa9059cbb)
        // This matches index 18 in a_pub_user and index 45 in a_pub_function
        // IMPORTANT: bytes4 to bytes32 conversion pads on the right, not left
        bytes32 transferSig = bytes32(bytes4(uint32(0xa9059cbb)));
        adminManager.registerFunction(
            address(token), transferSig, preprocessedPart1, preprocessedPart2, functionInstanceHash
        );

        vm.stopPrank();
    }

    // Helper function to compute function instance hash from a_pub_function array
    function computeFunctionInstanceHash() internal returns (bytes32) {
        // Save the current state of publicInputs
        uint256[] memory savedPublicInputs = new uint256[](publicInputs.length);
        for (uint256 i = 0; i < publicInputs.length; i++) {
            savedPublicInputs[i] = publicInputs[i];
        }

        // Load the public inputs to get the exact same data structure as the proof
        loadPublicInputs();

        // Extract function instance data exactly like _extractFunctionInstanceHashFromProof does (using index 64)
        uint256 functionDataLength = publicInputs.length - 64; // Should be 448 elements (512-64)
        uint256[] memory extractedFunctionData = new uint256[](functionDataLength);

        for (uint256 i = 0; i < functionDataLength; i++) {
            extractedFunctionData[i] = publicInputs[64 + i];
        }

        // Hash the function instance data
        bytes32 hash = keccak256(abi.encodePacked(extractedFunctionData));

        // Restore the original state of publicInputs
        delete publicInputs;
        for (uint256 i = 0; i < savedPublicInputs.length; i++) {
            publicInputs.push(savedPublicInputs[i]);
        }

        return hash;
    }

    // Helper function to set up a channel with 3 participants and deposits
    function setupChannelWithDeposits() internal returns (uint256 channelId) {
        // Open channel with user1 as leader
        vm.startPrank(user1);

        address[] memory participants = new address[](3);
        participants[0] = user1;
        participants[1] = user2;
        participants[2] = user3;

        BridgeCore.ChannelParams memory params =
            BridgeCore.ChannelParams({targetContract: address(token), participants: participants, timeout: 7 days});

        channelId = bridge.openChannel(params);

        // Set channel public key (required before deposits)
        uint256 pkx = 0x1234567890123456789012345678901234567890123456789012345678901234;
        uint256 pky = 0x9876543210987654321098765432109876543210987654321098765432109876;
        bridge.setChannelPublicKey(channelId, pkx, pky);

        // User1 deposits
        token.approve(address(depositManager), user1DepositValue);
        depositManager.depositToken(channelId, user1DepositValue, bytes32(User1l2MPTKey));
        vm.stopPrank();

        // User2 deposits
        vm.startPrank(user2);
        token.approve(address(depositManager), user2DepositValue);
        depositManager.depositToken(channelId, user2DepositValue, bytes32(User2l2MPTKey));
        vm.stopPrank();

        // User3 deposits
        vm.startPrank(user3);
        token.approve(address(depositManager), user3DepositValue);
        depositManager.depositToken(channelId, user3DepositValue, bytes32(User3l2MPTKey));
        vm.stopPrank();

        // Initialize channel state (as leader)
        vm.startPrank(user1);

        // Create initialization proof
        BridgeProofManager.ChannelInitializationProof memory initProof;

        // Set mock proof values for groth16 proof
        initProof.pA[0] = 1;
        initProof.pA[1] = 2;
        initProof.pA[2] = 3;
        initProof.pA[3] = 4;

        for (uint256 i = 0; i < 8; i++) {
            initProof.pB[i] = i + 1;
        }

        for (uint256 i = 0; i < 4; i++) {
            initProof.pC[i] = i + 1;
        }

        // Set initial state root to match the input state root from the proof (indices 8 & 9)
        // upper (index 9) << 128 | lower (index 8) = 0x5876a74c8e49224c5997659e57ca9a5b << 128 | 0x769375dc5a3b94bcf40f75827be355f8
        initProof.merkleRoot = 0x5876a74c8e49224c5997659e57ca9a5b769375dc5a3b94bcf40f75827be355f8;

        // Initialize channel state
        proofManager.initializeChannelState(channelId, initProof);
        console.logBytes32(bridge.getChannelInitialStateRoot(channelId));

        vm.stopPrank();

        return channelId;
    }

    function testcheckInstanceHash() public {
        bytes32 functionInstanceHash = computeFunctionInstanceHash();
        bytes32 transferSig = bytes32(bytes4(uint32(0xa9059cbb)));
        console.logBytes32(functionInstanceHash);
        console.logBytes32(transferSig);
    }

    // Test function to verify the helper works correctly
    function testSetupChannelWithDeposits() public {
        uint256 channelId = setupChannelWithDeposits();

        // Verify channel is set up correctly
        assertEq(uint8(bridge.getChannelState(channelId)), uint8(IBridgeCore.ChannelState.Open));
        assertEq(bridge.getChannelLeader(channelId), user1);

        // Verify participants
        address[] memory participants = bridge.getChannelParticipants(channelId);
        assertEq(participants.length, 3);
        assertEq(participants[0], user1);
        assertEq(participants[1], user2);
        assertEq(participants[2], user3);

        // Verify deposits
        assertEq(bridge.getParticipantDeposit(channelId, user1), user1DepositValue);
        assertEq(bridge.getParticipantDeposit(channelId, user2), user2DepositValue);
        assertEq(bridge.getParticipantDeposit(channelId, user3), user3DepositValue);

        // Verify L2 MPT keys
        assertEq(bridge.getL2MptKey(channelId, user1), User1l2MPTKey);
        assertEq(bridge.getL2MptKey(channelId, user2), User2l2MPTKey);
        assertEq(bridge.getL2MptKey(channelId, user3), User3l2MPTKey);

        // Verify pre-allocated leaf was set
        (uint256 value, bool exists) = adminManager.getPreAllocatedLeaf(address(token), bytes32(uint256(0x07)));
        assertTrue(exists, "Pre-allocated leaf should exist");
        assertEq(value, 18, "Pre-allocated leaf value should be 18");
    }

    // Test submitProofAndSignature with real proof data
    function testSubmitProofAndSignatureRealProof() public {
        // First, we need to use the real TokamakVerifier
        vm.startPrank(owner);
        TokamakVerifier realVerifier = new TokamakVerifier();
        proofManager.updateVerifier(address(realVerifier));
        vm.stopPrank();

        // Set up channel with deposits
        uint256 channelId = setupChannelWithDeposits();

        // Fast forward time to pass timeout (7 days + 1 second)
        vm.warp(block.timestamp + 7 days + 1);

        // Prepare the proof data from proof.json
        BridgeProofManager.ProofData[] memory proofs = new BridgeProofManager.ProofData[](1);

        // Clear and load proof entries part 1 (38 entries) from channel5_proof1.json
        delete proofPart1;
        proofPart1.push(28422251986255464038882119639303519153);
        proofPart1.push(1753724496264877589946835404549887395);
        proofPart1.push(8076450072917113079046931827613270738);
        proofPart1.push(23217316740904571737253040259366061810);
        proofPart1.push(22885999424868575700160922385686724032);
        proofPart1.push(93879424416525294481595904174894480);
        proofPart1.push(2096509218002469110550869714391616604);
        proofPart1.push(4634960899920833962889976994719644543);
        proofPart1.push(2948813556897622506729487580172948377);
        proofPart1.push(27445058105774310990851977383151029920);
        proofPart1.push(21854107068554191789416729584656202973);
        proofPart1.push(12830176743274527250517631283882084608);
        proofPart1.push(17807212929027213677787552111554764578);
        proofPart1.push(25405316417957334366712100249006505720);
        proofPart1.push(6667220718400803798283655428675532817);
        proofPart1.push(34236275876778095724748870038078704586);
        proofPart1.push(15783222771514149636757072493996462499);
        proofPart1.push(17058997455240377501360023503771671504);
        proofPart1.push(5966930523150431175538415014757083195);
        proofPart1.push(20296915344985653667419829380159442810);
        proofPart1.push(6383575590908513845142025362619146495);
        proofPart1.push(18240325468827225061786328405729717828);
        proofPart1.push(28833353362716129246483967816372270438);
        proofPart1.push(7444346854010968038273794957779084658);
        proofPart1.push(18235277753191285985348075042679465586);
        proofPart1.push(27451232359699606742128632371992638212);
        proofPart1.push(7016794823052071611875745274086286043);
        proofPart1.push(26526764007997390605505011806584807878);
        proofPart1.push(11754987646778852116913220606768586078);
        proofPart1.push(7536612760187471213093135958211846304);
        proofPart1.push(15657867429228531313630168874379766829);
        proofPart1.push(12358543324386123947794332926089404770);
        proofPart1.push(11754987646778852116913220606768586078);
        proofPart1.push(7536612760187471213093135958211846304);
        proofPart1.push(24673386736626038467411216280500924546);
        proofPart1.push(22379167169490362791453575996222631807);
        proofPart1.push(28721445888175510467033619778250895025);
        proofPart1.push(9950425763827526932307372522106597639);

        // Clear and load proof entries part 2 (42 entries) from channel5_proof1.json
        delete proofPart2;
        proofPart2.push(86467851479664118601524714048119929761619795900781837938309879488654108375914);
        proofPart2.push(115607231606982772217078754850458307628518892525637720020155241698142940359080);
        proofPart2.push(77133546075141356092847813147499035635566809824198408072180529562000792648832);
        proofPart2.push(67779503058932948410085776069500804132378436149632005674409342354774356985360);
        proofPart2.push(112284387134164105525752953361906341688369029664554983291366844726597826269612);
        proofPart2.push(57563495358218802649924636385449150791967079875665052776941222602891938619942);
        proofPart2.push(113805585267867565255615580276757421218458730695021317942000158057398168269441);
        proofPart2.push(94705294669599045899771834920651137983376020621484215261514217202660737156303);
        proofPart2.push(21277886786939099602838689124564564870938597259046178730051508027901390356611);
        proofPart2.push(109466905400407161932530629753957679365748050991126062777001761261921899265469);
        proofPart2.push(82014094317749521417785302275948104504920978749047927533033685964149531000837);
        proofPart2.push(80071330664885219589502356272625871423518694157441561983196227411830332142311);
        proofPart2.push(78655819006586586412292592545432160664569408111019791173108573360880504536358);
        proofPart2.push(16428268176438145553746073015359786371809726114070136436616099491748561612493);
        proofPart2.push(114133563149771374084847462985477452080363386616643759644186720767191903050896);
        proofPart2.push(57597585773294897041339808766356146849248448382281665754437787677901458154988);
        proofPart2.push(23645114387103043765982647131264747328181771320307599416676133956972480883634);
        proofPart2.push(73070421120922194016643197770044833986259152042885069819118509366223976173070);
        proofPart2.push(112579761717107370550652060725586355346984844337444823863769842271563139689931);
        proofPart2.push(104758306371045723058960200039371285569210942777164891221866628341306843732538);
        proofPart2.push(93714905895521779071905382153021235958410096243708840726995919964940545739406);
        proofPart2.push(30185069765781370081099961604870921182775165744370592756991520159106153458903);
        proofPart2.push(49266313869916838113594408720902200973699682654624023075101062689302972680437);
        proofPart2.push(24947781581188844875179909771254268990651110284783028487547403191477825869777);
        proofPart2.push(19055164500538535022860359837774319422023555737035088234082669610525440160404);
        proofPart2.push(27475779270268144747826258562239100126287757048698768410420697715352691386438);
        proofPart2.push(40902479023892589856872366233145964033854456865168312168637644689158601689784);
        proofPart2.push(70112190909172725190677740967366313706008919265779877528849608707278646716072);
        proofPart2.push(5428618245534049313679002304263472795260407879454976351716968888043024279171);
        proofPart2.push(65616936704165537387955398321706573468753022122529888759347866395710333715091);
        proofPart2.push(95082411397873784016246325697397701229404440650201031555061619662862885354444);
        proofPart2.push(35229381242728937963583838411228334702650253106071351227998642639439035583348);
        proofPart2.push(5428618245534049313679002304263472795260407879454976351716968888043024279171);
        proofPart2.push(65616936704165537387955398321706573468753022122529888759347866395710333715091);
        proofPart2.push(76647022441435571075335663933364310802087038454777642944203669155298080376675);
        proofPart2.push(101964110396868189150847809285909259841706623591239092476324291628901796579348);
        proofPart2.push(99560530314461643784367097728760376045870100910175650989811024373594908505905);
        proofPart2.push(76849188236098109939901605536532349895904226807381372005693777505364630306088);
        proofPart2.push(25929311852885330983164205382870403572284970578026804702550712639782026099509);
        proofPart2.push(17547443043525918646060393392276855175921075981782159228288222266843184283962);
        proofPart2.push(9099032483345218225342001954915398363591500667278812985455214490273755518478);
        proofPart2.push(49171792617045835045090095646075531140472805487395239516857597273092318937078);

        // Load public inputs from instance.json (all 512 values)
        loadPublicInputs();

        // The actual state roots in the proof according to instance_description.json:
        // Index 8: "Initial Merkle tree root hash (lower 16 bytes)"
        // Index 9: "Initial Merkle tree root hash (upper 16 bytes)"
        // Index 10: "Resulting Merkle tree root hash (lower 16 bytes)"
        // Index 11: "Resulting Merkle tree root hash (upper 16 bytes)"
        bytes32 outputStateRoot = bytes32((publicInputs[11] << 128) | publicInputs[10]);

        // Convert storage arrays to memory arrays for proper passing
        uint128[] memory proofPart1Memory = new uint128[](proofPart1.length);
        for (uint256 i = 0; i < proofPart1.length; i++) {
            proofPart1Memory[i] = proofPart1[i];
        }

        uint256[] memory proofPart2Memory = new uint256[](proofPart2.length);
        for (uint256 i = 0; i < proofPart2.length; i++) {
            proofPart2Memory[i] = proofPart2[i];
        }

        uint256[] memory publicInputsMemory = new uint256[](publicInputs.length);
        for (uint256 i = 0; i < publicInputs.length; i++) {
            publicInputsMemory[i] = publicInputs[i];
        }

        proofs[0] = BridgeProofManager.ProofData({
            proofPart1: proofPart1Memory,
            proofPart2: proofPart2Memory,
            publicInputs: publicInputsMemory,
            smax: 256
        });

        // Create signature with correct commitment
        bytes32 commitmentHash = keccak256(abi.encodePacked(channelId, outputStateRoot));

        // Configure MockZecFrost to return the channel's signer address
        // The signer address is derived from the public key set in setupChannelWithDeposits
        vm.startPrank(owner);
        // Get the actual signer address from the bridge
        address expectedSigner = bridge.getChannelSignerAddr(channelId);
        mockZecFrost.setMockSigner(expectedSigner);
        vm.stopPrank();

        BridgeProofManager.Signature memory signature = BridgeProofManager.Signature({
            message: commitmentHash,
            rx: 0x1fb4c0436e9054ae0b237cde3d7a478ce82405b43fdbb5bf1d63c9f8d912dd5d,
            ry: 0x3a7784df441925a8859b9f3baf8d570d488493506437db3ccf230a4b43b27c1e,
            z: 0xc7fdcb364dd8577e47dd479185ca659adbfcd1b8675e5cbb36e5f93ca4e15b25
        });

        // Submit proof and signature
        vm.startPrank(user1);
        proofManager.submitProofAndSignature(channelId, proofs, signature);
        vm.stopPrank();

        // Verify that the channel state was updated
        assertEq(uint8(bridge.getChannelState(channelId)), uint8(IBridgeCore.ChannelState.Closing));
        assertTrue(bridge.isSignatureVerified(channelId));
    }

    // Helper function to load public inputs from channel5_proof1.json
    function loadPublicInputs() internal {
        delete publicInputs;

        // a_pub_user (indices 0-41) from channel5_proof1.json
        for(uint256 i = 0; i < 42; i++) {
            if(i == 8) publicInputs.push(0x769375dc5a3b94bcf40f75827be355f8);
            else if(i == 9) publicInputs.push(0x5876a74c8e49224c5997659e57ca9a5b);
            else if(i == 10) publicInputs.push(0x7c4a3489a695f09d962204ae3cb42fd0);
            else if(i == 11) publicInputs.push(0x0bfee9c26c3cd9549157ef90c7a648e7);
            else if(i == 12) publicInputs.push(0xa1de99584b859abf3ecc0a3d8ae22c4d);
            else if(i == 13) publicInputs.push(0x0c2d7a50c82d20362117a77c54dffbad);
            else if(i == 14) publicInputs.push(0x85b8f5c0457dbc3b7c8a280373c40044);
            else if(i == 15) publicInputs.push(0xa30fe402);
            else if(i == 16) publicInputs.push(0xa9059cbb);
            else publicInputs.push(0x00);
        }

        // a_pub_block (indices 42-63) from channel5_proof1.json
        for(uint256 i = 0; i < 22; i++) {
            if(i == 0) publicInputs.push(0x4a13a0977f4d7101ebc24b87bb23f0d5);
            else if(i == 1) publicInputs.push(0x13cb6ae3);
            else if(i == 2) publicInputs.push(0x6941286c);
            else if(i == 4) publicInputs.push(0x965505);
            else if(i == 6) publicInputs.push(0xaaa74863900cd1aa397b147b5e3a97df);
            else if(i == 7) publicInputs.push(0x3158a0204e0c6977c846dec8dcb483ab);
            else if(i == 8) publicInputs.push(0x03938700);
            else if(i == 10) publicInputs.push(0xaa36a7);
            else if(i == 16) publicInputs.push(0x27ed7bb87b32e2c18b4d69b3d3d60f34);
            else if(i == 17) publicInputs.push(0xba60a2b5465adc32b9b6d1f442c9f9c2);
            else publicInputs.push(0x00);
        }

        // a_pub_function (indices 64-511) from channel5_proof1.json  
        // First add the actual meaningful values
        publicInputs.push(0x01);
        publicInputs.push(0xffffffffffffffffffffffffffffffff);
        publicInputs.push(0xffffffff);
        publicInputs.push(0xe72f6afd7d1f72623e6b071492d1122b);
        publicInputs.push(0x11dafe5d23e1218086a365b99fbf3d3b);
        publicInputs.push(0x3e26ba5cc220fed7cc3f870e59d292aa);
        publicInputs.push(0x1d523cf1ddab1a1793132e78c866c0c3);
        publicInputs.push(0x00);
        publicInputs.push(0x00);
        publicInputs.push(0x01);
        publicInputs.push(0x00);
        publicInputs.push(0x80);
        publicInputs.push(0x00);
        publicInputs.push(0x00);
        publicInputs.push(0x00);
        publicInputs.push(0x200000);
        publicInputs.push(0x04);
        publicInputs.push(0x00);
        publicInputs.push(0x44);
        publicInputs.push(0x00);
        publicInputs.push(0x010000);
        publicInputs.push(0xe0);
        publicInputs.push(0x00);
        publicInputs.push(0x08000000);
        publicInputs.push(0x20);
        publicInputs.push(0x00);
        publicInputs.push(0x10000000);
        publicInputs.push(0xe0);
        publicInputs.push(0x00);
        publicInputs.push(0x10000000);
        publicInputs.push(0x70a08231);
        publicInputs.push(0x00);
        publicInputs.push(0x020000);
        publicInputs.push(0x98650275);
        publicInputs.push(0x00);
        publicInputs.push(0x020000);
        publicInputs.push(0xaa271e1a);
        publicInputs.push(0x00);
        publicInputs.push(0x020000);
        publicInputs.push(0x98650275);
        publicInputs.push(0x00);
        publicInputs.push(0x100000);
        publicInputs.push(0xa457c2d7);
        publicInputs.push(0x00);
        publicInputs.push(0x100000);
        publicInputs.push(0xa9059cbb);
        publicInputs.push(0x00);
        publicInputs.push(0x100000);
        publicInputs.push(0x04);
        publicInputs.push(0x00);
        publicInputs.push(0x44);
        publicInputs.push(0x00);
        publicInputs.push(0x08);
        publicInputs.push(0x40);
        publicInputs.push(0x00);
        publicInputs.push(0x010000);
        publicInputs.push(0x200000);
        publicInputs.push(0x02);
        publicInputs.push(0xffffffffffffffffffffffffffffffff);
        publicInputs.push(0xffffffff);
        publicInputs.push(0x20);
        publicInputs.push(0x00);
        publicInputs.push(0x02);
        publicInputs.push(0x20);
        publicInputs.push(0x00);
        publicInputs.push(0x02);
        publicInputs.push(0x00);
        publicInputs.push(0x00);
        publicInputs.push(0xffffffffffffffffffffffffffffffff);
        publicInputs.push(0xffffffff);
        publicInputs.push(0xffffffffffffffffffffffffffffffff);
        publicInputs.push(0xffffffff);
        publicInputs.push(0x100000);
        publicInputs.push(0x200000);
        publicInputs.push(0x00);
        publicInputs.push(0x00);
        publicInputs.push(0xffffffffffffffffffffffffffffffff);
        publicInputs.push(0xffffffff);
        publicInputs.push(0xffffffffffffffffffffffffffffffff);
        publicInputs.push(0xffffffff);
        publicInputs.push(0x100000);
        publicInputs.push(0x200000);
        publicInputs.push(0x60);
        publicInputs.push(0x00);
        publicInputs.push(0x02);
        publicInputs.push(0x20);
        publicInputs.push(0x00);
        publicInputs.push(0x02);
        publicInputs.push(0x00);
        publicInputs.push(0x00);
        publicInputs.push(0xffffffffffffffffffffffffffffffff);
        publicInputs.push(0xffffffff);
        publicInputs.push(0xffffffffffffffffffffffffffffffff);
        publicInputs.push(0xffffffff);
        publicInputs.push(0x20);
        publicInputs.push(0x00);
        publicInputs.push(0x02);
        publicInputs.push(0x20);
        publicInputs.push(0x00);
        publicInputs.push(0x02);
        publicInputs.push(0x1da9);
        publicInputs.push(0x00);
        publicInputs.push(0xffffffff);
        publicInputs.push(0x00);
        publicInputs.push(0x020000);
        publicInputs.push(0x200000);
        publicInputs.push(0x08);
        publicInputs.push(0x00);
        publicInputs.push(0x00);
        publicInputs.push(0xffffffffffffffffffffffffffffffff);
        publicInputs.push(0xffffffff);
        publicInputs.push(0xffffffffffffffffffffffffffffffff);
        publicInputs.push(0xffffffff);
        publicInputs.push(0x20);
        publicInputs.push(0x00);
        publicInputs.push(0x02);
        publicInputs.push(0x20);
        publicInputs.push(0x00);
        publicInputs.push(0x02);
        publicInputs.push(0x00);
        publicInputs.push(0x00);
        publicInputs.push(0xffffffffffffffffffffffffffffffff);
        publicInputs.push(0xffffffff);
        publicInputs.push(0xffffffffffffffffffffffffffffffff);
        publicInputs.push(0xffffffff);
        publicInputs.push(0x20);
        publicInputs.push(0x00);
        publicInputs.push(0x02);
        publicInputs.push(0x20);
        publicInputs.push(0x00);
        publicInputs.push(0x02);
        publicInputs.push(0x1acc);
        publicInputs.push(0x00);
        publicInputs.push(0xffffffff);
        publicInputs.push(0x00);
        publicInputs.push(0x02);
        publicInputs.push(0x010000);
        publicInputs.push(0x200000);
        publicInputs.push(0x00);
        publicInputs.push(0x00);
        publicInputs.push(0xffffffffffffffffffffffffffffffff);
        publicInputs.push(0xffffffff);
        publicInputs.push(0xffffffffffffffffffffffffffffffff);
        publicInputs.push(0xffffffff);
        publicInputs.push(0x20);
        publicInputs.push(0x00);
        publicInputs.push(0x02);
        publicInputs.push(0x20);
        publicInputs.push(0x00);
        publicInputs.push(0x02);
        publicInputs.push(0xffffffffffffffffffffffffffffffff);
        publicInputs.push(0xffffffff);
        publicInputs.push(0xffffffffffffffffffffffffffffffff);
        publicInputs.push(0xffffffff);
        publicInputs.push(0x20);
        publicInputs.push(0x00);
        publicInputs.push(0x02);
        publicInputs.push(0x08);
        publicInputs.push(0x07);
        publicInputs.push(0x00);
        publicInputs.push(0x15);
        publicInputs.push(0x00);
        publicInputs.push(0x0100);
        publicInputs.push(0x00);
        publicInputs.push(0x01);
        publicInputs.push(0x00);
        publicInputs.push(0x10);
        publicInputs.push(0xff);
        publicInputs.push(0x00);
        publicInputs.push(0x200000);
        publicInputs.push(0x200000);
        publicInputs.push(0x01);
        publicInputs.push(0x00);
        publicInputs.push(0x200000);
        publicInputs.push(0x200000);
        publicInputs.push(0x200000);
        publicInputs.push(0x200000);
        publicInputs.push(0x20);
        publicInputs.push(0x00);
        publicInputs.push(0x02);
        publicInputs.push(0x08);
        // Fill remaining elements up to 512 with zeros  
        while (publicInputs.length < 512) {
            publicInputs.push(0x00);
        }
    }

    function loadFunctionInstance() internal pure returns (uint256[] memory) {
        uint256[] memory functionInstances = new uint256[](446);

        functionInstances[0] = 0x01;
        functionInstances[1] = 0xffffffffffffffffffffffffffffffff;
        functionInstances[2] = 0xffffffff;
        functionInstances[3] = 0xe72f6afd7d1f72623e6b071492d1122b;
        functionInstances[4] = 0x11dafe5d23e1218086a365b99fbf3d3b;
        functionInstances[5] = 0x3e26ba5cc220fed7cc3f870e59d292aa;
        functionInstances[6] = 0x1d523cf1ddab1a1793132e78c866c0c3;
        functionInstances[7] = 0x00;
        functionInstances[8] = 0x00;
        functionInstances[9] = 0x01;
        functionInstances[10] = 0x00;
        functionInstances[11] = 0x80;
        functionInstances[12] = 0x00;
        functionInstances[13] = 0x00;
        functionInstances[14] = 0x00;
        functionInstances[15] = 0x200000;
        functionInstances[16] = 0x04;
        functionInstances[17] = 0x00;
        functionInstances[18] = 0x44;
        functionInstances[19] = 0x00;
        functionInstances[20] = 0x010000;
        functionInstances[21] = 0xe0;
        functionInstances[22] = 0x00;
        functionInstances[23] = 0x08000000;
        functionInstances[24] = 0x20;
        functionInstances[25] = 0x00;
        functionInstances[26] = 0x10000000;
        functionInstances[27] = 0xe0;
        functionInstances[28] = 0x00;
        functionInstances[29] = 0x10000000;
        functionInstances[30] = 0x70a08231;
        functionInstances[31] = 0x00;
        functionInstances[32] = 0x020000;
        functionInstances[33] = 0x98650275;
        functionInstances[34] = 0x00;
        functionInstances[35] = 0x020000;
        functionInstances[36] = 0xaa271e1a;
        functionInstances[37] = 0x00;
        functionInstances[38] = 0x020000;
        functionInstances[39] = 0x98650275;
        functionInstances[40] = 0x00;
        functionInstances[41] = 0x100000;
        functionInstances[42] = 0xa457c2d7;
        functionInstances[43] = 0x00;
        functionInstances[44] = 0x100000;
        functionInstances[45] = 0xa9059cbb;
        functionInstances[46] = 0x00;
        functionInstances[47] = 0x100000;
        functionInstances[48] = 0x04;
        functionInstances[49] = 0x00;
        functionInstances[50] = 0x44;
        functionInstances[51] = 0x00;
        functionInstances[52] = 0x08;
        functionInstances[53] = 0x40;
        functionInstances[54] = 0x00;
        functionInstances[55] = 0x010000;
        functionInstances[56] = 0x200000;
        functionInstances[57] = 0x02;
        functionInstances[58] = 0xffffffffffffffffffffffffffffffff;
        functionInstances[59] = 0xffffffff;
        functionInstances[60] = 0x20;
        functionInstances[61] = 0x00;
        functionInstances[62] = 0x02;
        functionInstances[63] = 0x20;
        functionInstances[64] = 0x00;
        functionInstances[65] = 0x02;
        functionInstances[66] = 0x00;
        functionInstances[67] = 0x00;
        functionInstances[68] = 0xffffffffffffffffffffffffffffffff;
        functionInstances[69] = 0xffffffff;
        functionInstances[70] = 0xffffffffffffffffffffffffffffffff;
        functionInstances[71] = 0xffffffff;
        functionInstances[72] = 0x100000;
        functionInstances[73] = 0x200000;
        functionInstances[74] = 0x00;
        functionInstances[75] = 0x00;
        functionInstances[76] = 0xffffffffffffffffffffffffffffffff;
        functionInstances[77] = 0xffffffff;
        functionInstances[78] = 0xffffffffffffffffffffffffffffffff;
        functionInstances[79] = 0xffffffff;
        functionInstances[80] = 0x100000;
        functionInstances[81] = 0x200000;
        functionInstances[82] = 0x60;
        functionInstances[83] = 0x00;
        functionInstances[84] = 0x02;
        functionInstances[85] = 0x20;
        functionInstances[86] = 0x00;
        functionInstances[87] = 0x02;
        functionInstances[88] = 0x00;
        functionInstances[89] = 0x00;
        functionInstances[90] = 0xffffffffffffffffffffffffffffffff;
        functionInstances[91] = 0xffffffff;
        functionInstances[92] = 0xffffffffffffffffffffffffffffffff;
        functionInstances[93] = 0xffffffff;
        functionInstances[94] = 0x20;
        functionInstances[95] = 0x00;
        functionInstances[96] = 0x02;
        functionInstances[97] = 0x20;
        functionInstances[98] = 0x00;
        functionInstances[99] = 0x02;
        functionInstances[100] = 0x1da9;
        functionInstances[101] = 0x00;
        functionInstances[102] = 0xffffffff;
        functionInstances[103] = 0x00;
        functionInstances[104] = 0x020000;
        functionInstances[105] = 0x200000;
        functionInstances[106] = 0x08;
        functionInstances[107] = 0x00;
        functionInstances[108] = 0x00;
        functionInstances[109] = 0xffffffffffffffffffffffffffffffff;
        functionInstances[110] = 0xffffffff;
        functionInstances[111] = 0xffffffffffffffffffffffffffffffff;
        functionInstances[112] = 0xffffffff;
        functionInstances[113] = 0x20;
        functionInstances[114] = 0x00;
        functionInstances[115] = 0x02;
        functionInstances[116] = 0x20;
        functionInstances[117] = 0x00;
        functionInstances[118] = 0x02;
        functionInstances[119] = 0x00;
        functionInstances[120] = 0x00;
        functionInstances[121] = 0xffffffffffffffffffffffffffffffff;
        functionInstances[122] = 0xffffffff;
        functionInstances[123] = 0xffffffffffffffffffffffffffffffff;
        functionInstances[124] = 0xffffffff;
        functionInstances[125] = 0x20;
        functionInstances[126] = 0x00;
        functionInstances[127] = 0x02;
        functionInstances[128] = 0x20;
        functionInstances[129] = 0x00;
        functionInstances[130] = 0x02;
        functionInstances[131] = 0x1acc;
        functionInstances[132] = 0x00;
        functionInstances[133] = 0xffffffff;
        functionInstances[134] = 0x00;
        functionInstances[135] = 0x02;
        functionInstances[136] = 0x010000;
        functionInstances[137] = 0x200000;
        functionInstances[138] = 0x00;
        functionInstances[139] = 0x00;
        functionInstances[140] = 0xffffffffffffffffffffffffffffffff;
        functionInstances[141] = 0xffffffff;
        functionInstances[142] = 0xffffffffffffffffffffffffffffffff;
        functionInstances[143] = 0xffffffff;
        functionInstances[144] = 0x20;
        functionInstances[145] = 0x00;
        functionInstances[146] = 0x02;
        functionInstances[147] = 0x20;
        functionInstances[148] = 0x00;
        functionInstances[149] = 0x02;
        functionInstances[150] = 0xffffffffffffffffffffffffffffffff;
        functionInstances[151] = 0xffffffff;
        functionInstances[152] = 0xffffffffffffffffffffffffffffffff;
        functionInstances[153] = 0xffffffff;
        functionInstances[154] = 0x20;
        functionInstances[155] = 0x00;
        functionInstances[156] = 0x02;
        functionInstances[157] = 0x08;
        functionInstances[158] = 0x07;
        functionInstances[159] = 0x00;
        functionInstances[160] = 0x15;
        functionInstances[161] = 0x00;
        functionInstances[162] = 0x0100;
        functionInstances[163] = 0x00;
        functionInstances[164] = 0x01;
        functionInstances[165] = 0x00;
        functionInstances[166] = 0x10;
        functionInstances[167] = 0xff;
        functionInstances[168] = 0x00;
        functionInstances[169] = 0x200000;
        functionInstances[170] = 0x200000;
        functionInstances[171] = 0x01;
        functionInstances[172] = 0x00;
        functionInstances[173] = 0x200000;
        functionInstances[174] = 0x200000;
        functionInstances[175] = 0x200000;
        functionInstances[176] = 0x200000;
        functionInstances[177] = 0x20;
        functionInstances[178] = 0x00;
        functionInstances[179] = 0x02;
        functionInstances[180] = 0x08;
        functionInstances[181] = 0x00;

        return functionInstances;
    }
}

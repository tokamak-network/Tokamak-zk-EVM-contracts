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
        preprocessedPart1[0] = 0x1136c7a73653af0cbdc9fda441a80391;
        preprocessedPart1[1] = 0x007c86367643476dcdb0e9bcf1617f1c;
        preprocessedPart1[2] = 0x18c9e2822155742dd5fbd050aa293be5;
        preprocessedPart1[3] = 0x00b248168d62853defda478a7a46e0a0;
        uint256[] memory preprocessedPart2 = new uint256[](4);
        preprocessedPart2[0] = 0xc4383bb8c86977fc45c94bc42353e37b39907e30b52054990083a85cf5256c22;
        preprocessedPart2[1] = 0x8fc97f11906d661f0b434c3c49d0ec8b3cac2928f6ff6fac5815686d175d2e87;
        preprocessedPart2[2] = 0xf84798df0fcfbd79e070d2303170d78e438e4b32975a4ebf6e1ff32863f2cc3e;
        preprocessedPart2[3] = 0xc6b05d5e144de6e3b25f09093b9ba94c194452d8decf3af3390cfa46df134c0e;

        IBridgeCore.PreAllocatedLeaf[] memory emptySlots = new IBridgeCore.PreAllocatedLeaf[](0);
        adminManager.setAllowedTargetContract(address(token), emptySlots, true);

        // Set pre-allocated leaf with key 0x07 and value 18 (for decimals)
        adminManager.setPreAllocatedLeaf(address(token), bytes32(uint256(0x07)), 18);

        // Compute the function instance hash from the proof's a_pub_function data
        bytes32 functionInstanceHash = computeFunctionInstanceHash();

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

        // Extract function instance data exactly like _extractFunctionInstanceHashFromProof does
        uint256 functionDataLength = publicInputs.length - 66; // Should be 446 elements (512-66)
        uint256[] memory extractedFunctionData = new uint256[](functionDataLength);

        for (uint256 i = 0; i < functionDataLength; i++) {
            extractedFunctionData[i] = publicInputs[66 + i];
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
        // part1 << 128 | part2 = 0x697f6a98de69bdc71426efe52f459cfc << 128 | 0x7380218991c8a0feb79bb9715fd26e2a
        initProof.merkleRoot = 0x697f6a98de69bdc71426efe52f459cfc7380218991c8a0feb79bb9715fd26e2a;

        // Initialize channel state
        proofManager.initializeChannelState(channelId, initProof);

        vm.stopPrank();

        return channelId;
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

        // Clear and load proof entries part 1 (38 entries) - using dynamic storage arrays
        delete proofPart1;
        proofPart1.push(0x15815614b1d3cfda780a76f38debd7a8);
        proofPart1.push(0x15b853b4b6eda1d03dc7425ff8de2ab8);
        proofPart1.push(0x1579e2d3f28e91954ea7f08662b1cf3c);
        proofPart1.push(0x1193fdc21cf50013a57a04b95a980e70);
        proofPart1.push(0x0ef6fa45a824d55e6ab0242e79346af4);
        proofPart1.push(0x0579570790721e06f618e9b435e99fcc);
        proofPart1.push(0x0712c6c5aaa97978302ea53ed788bb9f);
        proofPart1.push(0x0fd202428e1846b62b08551224fc44fa);
        proofPart1.push(0x192da2abb37a61d57edd3cb783519fff);
        proofPart1.push(0x037fecce4bb5d2c935aea5d5dce3eb69);
        proofPart1.push(0x188d99fd3fa3fb713313356e80d011a5);
        proofPart1.push(0x00a815a29deb9b4c2b7f59fad3d0aa70);
        proofPart1.push(0x0dd23c7c26c943439e5793ec06d24027);
        proofPart1.push(0x13af2ab494a3a28b5a9329fcc15e3358);
        proofPart1.push(0x16d79ba31faebbd9be3c5d6ec33405b6);
        proofPart1.push(0x041cb373ead122e1a5755f5e7e11b52a);
        proofPart1.push(0x144bd4c7d0d646d7a50710a2408d10f1);
        proofPart1.push(0x14035301f93670a1083c4bf0410ed855);
        proofPart1.push(0x1106f645a82f2e3098a2d184d5ecce06);
        proofPart1.push(0x12a69c3983176f94b3af657430db1c47);
        proofPart1.push(0x10247238a26ae53c84ad57577454ed6b);
        proofPart1.push(0x1552e5c50974761247a91ad853b5831f);
        proofPart1.push(0x0ed5ac16f53d550faa94b3f89e7c3068);
        proofPart1.push(0x0de8107eff76583c9db6296e542e6f72);
        proofPart1.push(0x059d13674332bae80788f4aad61a36bb);
        proofPart1.push(0x11928ff2162df1dee7bd651f1f06b247);
        proofPart1.push(0x17a05db254eda53ead06061a27b8051a);
        proofPart1.push(0x09cb514bf0ba929adabafa7898023cf3);
        proofPart1.push(0x13eb334743fa8f040a1d288c03872162);
        proofPart1.push(0x1882f3c85de4b5e36314f849a9a35d6c);
        proofPart1.push(0x085686e98ae7c7a0d4ad61f7e1fc2207);
        proofPart1.push(0x0445f9424f1f95b4d831006e7a13f0f0);
        proofPart1.push(0x13eb334743fa8f040a1d288c03872162);
        proofPart1.push(0x1882f3c85de4b5e36314f849a9a35d6c);
        proofPart1.push(0x1674357a821eb6fbd29b19d2bc46bf11);
        proofPart1.push(0x090838093c14b593a824dfe2f491af72);
        proofPart1.push(0x0bf54da2ebdc1f4d8cf126c88c579e2a);
        proofPart1.push(0x04fef23658e5ec9ac987a183ba44f153);

        // Clear and load proof entries part 2 (42 entries) - using dynamic storage arrays
        delete proofPart2;
        proofPart2.push(0x218a2513b9f5d2f07da97b9c001c29cfd1def3795cdc67c7a55aae80d6fa1739);
        proofPart2.push(0x870afac1b023aeb155cd0407035ede2b91c0411f25f3e814419af37045549bf2);
        proofPart2.push(0xb803b959f341ba8d0df34277acf806a22987ee4405bfdb8a6075abab622d8938);
        proofPart2.push(0x4cf5ef5575cc65795c91a41bedd329a870d531132d4c01c0daacfa21ae9d0c9b);
        proofPart2.push(0x5cff38c52fa19d052a230f004a5767cd06f0ee607f235dee61c279901e1eb334);
        proofPart2.push(0x903044616e6a82670d4f0e7da1c2acce49b2f2fdb4bec4d892a6c61a605dabe7);
        proofPart2.push(0x238c8319cab91bf944028e56fdc53fac686912eddb2681bb31da98de1a45046f);
        proofPart2.push(0x72751b0b8849f28e90a043496f8e3c721a9a2c11dc37dfb4b8eb2e51617b838f);
        proofPart2.push(0x1786cc8744ba3c625faf3e425d6efb7fb7a8843f3e7bf849c5bb91aeda51039b);
        proofPart2.push(0xb44c14a62ea7274bfaaeef7f9d177295533ca16b8424c570f40d336f750899c5);
        proofPart2.push(0x0b7e53ae849ff813c770b7fa067c015db95084df6ccfc2d08d7ed344106e9446);
        proofPart2.push(0x903f8c62ade1fe442f896656ccd601dea9f6b884de44ca50179e95b69d7e9278);
        proofPart2.push(0x1a576bce68d74c7f45d2099e21c03ba18b785d4443ca24664a4358b5b4492b07);
        proofPart2.push(0x706a7e78137f8ab4bb6fab55cb7829e4dcd332e07db3233827d57b974ba772c7);
        proofPart2.push(0x08608535f35ba479cbdf98ec4117f1d6d0d5bbbc7120d15975db81ef47084bb1);
        proofPart2.push(0x7a41b65ce8cea584d8903d0e7d311b291df68e8b5cbb2f03aec78b1f632859f3);
        proofPart2.push(0xb51ec8eabaef042a70a4993bae881b2352090b550a0b778918cfa65affcafeb4);
        proofPart2.push(0xab74f4e1b4bb1455e8f57881cc861f7dab291441b019bf6b2b42edff13ab4ff8);
        proofPart2.push(0xd8717ef8b4c49967258125a65a627ffb1039a70986016de2326013298fdad205);
        proofPart2.push(0xb910ebe08c152b86b2cc202f10b89f09bb995327673800c6ff6960cee9fe0fa6);
        proofPart2.push(0x51a0b49263eb04d442553649aa8ba2bff8bf08395e94a40aaf2d6cdf4de5e200);
        proofPart2.push(0x2deddc72de9bd7c8539eb2dbffc05c6d0c6d3dc082211da6b9d2cf6261c5b95c);
        proofPart2.push(0xe90764e8c3c608909905317d1db45264d115e53ff1f5560812e9ad9a712a1aef);
        proofPart2.push(0xf3f16f05a8ac974202fca819ad30654566669e877c575b752e6f2844e8bf811d);
        proofPart2.push(0x7074d02532f74b37b3bf2e2e80e6efd74a59d9c2be7014205f8b0a68da5cf660);
        proofPart2.push(0xb5cb826a1ede3b7eaf370442e4c37560272964a6cacf8d5b7f16a37c376289c9);
        proofPart2.push(0x895f9fab7c3b6d2d2f4c8abab824bce78ebb829d678c9c7893938b1be37797da);
        proofPart2.push(0xe2b5b0dc5b4927868448b343b342c3cbdcc5ed11ec5ca34cafd05d8e1a7d30e5);
        proofPart2.push(0x24a58a466697866ac22e9279dab43ac2b643e6752eedf664396ece2bb61e3e99);
        proofPart2.push(0x4906165f727bdc79f02b6a0b717bacff91e4d980566e205199160e1b84237097);
        proofPart2.push(0x1ae0176fd63ecfa263c5f019842cee0fb2b00c92cdfae64746dd78fc0dd8f58d);
        proofPart2.push(0xf2f32da4b9ea674a98015718df38ef40fd8d4187f23a738ec8fd70902be929d2);
        proofPart2.push(0x24a58a466697866ac22e9279dab43ac2b643e6752eedf664396ece2bb61e3e99);
        proofPart2.push(0x4906165f727bdc79f02b6a0b717bacff91e4d980566e205199160e1b84237097);
        proofPart2.push(0x6ec7a66b4c594cc793e83b44f4da30ad8dd9184f02414a35da49deacc2aeae29);
        proofPart2.push(0x61a58def048a6f157c8c269ce1ff0f622a851eac19fab9060f6cb2e33599eac2);
        proofPart2.push(0x55cc89b9e9e4a9a7c389845c00289a0b8471efb1d4a0bb58c39accb4dc0794a8);
        proofPart2.push(0x2919e53d947ef94f43e16675e04a66b6746bbea448cd8ef68b1c477fa86fc4e9);
        proofPart2.push(0x17fbc25ff5a04b607706778a88332341049268460ee170d1cf06cd64634ee20a);
        proofPart2.push(0x6ead56bfcbba4c416108882629c6c61b940ea05f76cce26606537b96506e15e6);
        proofPart2.push(0x447fff7ec6e9996301a21dbae35881d00d3fc12c7226ba85ff28245be34db010);
        proofPart2.push(0x32fe3527e7bac897c0083e5362f707898d66b4ac5c52bd5004afbe7d713bf6c9);

        // Load public inputs from instance.json (all 512 values)
        loadPublicInputs();

        // The actual state roots in the proof according to instance_description.json:
        // Index 8: "Initial Merkle tree root hash (lower 16 bytes)"
        // Index 9: "Initial Merkle tree root hash (upper 16 bytes)"
        // Index 10: "Resulting Merkle tree root hash (lower 16 bytes)"
        // Index 11: "Resulting Merkle tree root hash (upper 16 bytes)"
        bytes32 outputStateRoot = bytes32((publicInputs[10] << 128) | publicInputs[11]);

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

    // Helper function to load public inputs from instance.json
    function loadPublicInputs() internal {
        delete publicInputs;

        // a_pub_user (indices 0-41)
        publicInputs.push(0x00);
        publicInputs.push(0x00);
        publicInputs.push(0x00);
        publicInputs.push(0x00);
        publicInputs.push(0x00);
        publicInputs.push(0x00);
        publicInputs.push(0x00);
        publicInputs.push(0x00);
        publicInputs.push(0x697f6a98de69bdc71426efe52f459cfc);
        publicInputs.push(0x7380218991c8a0feb79bb9715fd26e2a);
        publicInputs.push(0x85e43e3f03778631a09942dd08cf2e8d);
        publicInputs.push(0x4f3d75526b4d4b109e87539730a792e4);
        publicInputs.push(0xe21d7692eebc6214c1585134fda4b0d6);
        publicInputs.push(0x0c8ba5023657fe4b7d7c4edb122894ba);
        publicInputs.push(0x85b8f5c0457dbc3b7c8a280373c40044);
        publicInputs.push(0xa30fe402);
        publicInputs.push(0xa9059cbb);
        publicInputs.push(0x00);
        publicInputs.push(0x00);
        publicInputs.push(0x00);
        publicInputs.push(0x00);
        publicInputs.push(0x00);
        publicInputs.push(0x00);
        publicInputs.push(0x00);
        publicInputs.push(0x00);
        publicInputs.push(0x00);
        publicInputs.push(0x00);
        publicInputs.push(0x00);
        publicInputs.push(0x00);
        publicInputs.push(0x00);
        publicInputs.push(0x00);
        publicInputs.push(0x00);
        publicInputs.push(0x00);
        publicInputs.push(0x00);
        publicInputs.push(0x00);
        publicInputs.push(0x00);
        publicInputs.push(0x00);
        publicInputs.push(0x00);
        publicInputs.push(0x00);
        publicInputs.push(0x00);

        // a_pub_block (indices 42-65)
        publicInputs.push(0x29dec4629dfb4170647c4ed4efc392cd);
        publicInputs.push(0xf24a01ae);
        publicInputs.push(0x6939333c);
        publicInputs.push(0x00);
        publicInputs.push(0x95abdc);
        publicInputs.push(0x00);
        publicInputs.push(0x19959c1873750220732ca5148bab3254);
        publicInputs.push(0xa0c5ba1cddaf068fc86d068a534eb367);
        publicInputs.push(0x039386c7);
        publicInputs.push(0x00);
        publicInputs.push(0xaa36a7);
        publicInputs.push(0x00);
        publicInputs.push(0x00);
        publicInputs.push(0x00);
        publicInputs.push(0x00);
        publicInputs.push(0x00);
        publicInputs.push(0xb29b7b4ce683591d957141ca7e4bbc9d);
        publicInputs.push(0x151ac8176283d1313ff21b9d60ad82ce);
        // Rest are zeros (60-65)
        publicInputs.push(0x00);
        publicInputs.push(0x00);
        publicInputs.push(0x00);
        publicInputs.push(0x00);
        publicInputs.push(0x00);
        publicInputs.push(0x00);

        // a_pub_function (indices 66-517) - All the function instance data
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
        // Rest are all zeros (247-511)
        for (uint256 i = 247; i < 512; i++) {
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

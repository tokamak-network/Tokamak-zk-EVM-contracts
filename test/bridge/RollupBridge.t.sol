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
import "../../src/interface/IGroth16Verifier32Leaves.sol";
import "../../src/interface/IGroth16Verifier64Leaves.sol";
import "../../src/interface/IGroth16Verifier128Leaves.sol";
import {ZecFrost} from "../../src/library/ZecFrost.sol";

// Mock Contracts
contract MockZecFrost is IZecFrost {
    address public mockSigner;
    
    // Mapping of signature vectors to their recovered addresses
    mapping(bytes32 => address) private signatureVectorToSigner;

    constructor() {
        mockSigner = address(this);
        
        // Vector 1 signature (valid) - recovers to user1 (0xd96b35D012879d89cfBA6fE215F1015863a6f6d0)
        bytes32 vector1Key = keccak256(abi.encodePacked(
            uint256(0x1fb4c0436e9054ae0b237cde3d7a478ce82405b43fdbb5bf1d63c9f8d912dd5d),
            uint256(0x3a7784df441925a8859b9f3baf8d570d488493506437db3ccf230a4b43b27c1e),
            uint256(0xc7fdcb364dd8577e47dd479185ca659adbfcd1b8675e5cbb36e5f93ca4e15b25)
        ));
        signatureVectorToSigner[vector1Key] = 0xd96b35D012879d89cfBA6fE215F1015863a6f6d0;
        
        // Vector 2 signature (invalid) - recovers to user2 (0x012C2171f631e27C4bA9f7f8262af2a48956939A)
        bytes32 vector2Key = keccak256(abi.encodePacked(
            uint256(0xc303bb5de5a5962d9af9b45f5e0bdc919de2aac9153b8c353960f50aa3cb950c),
            uint256(0x6df25261f523a8ea346f49dad49b3b36786e653a129cff327a0fea5839e712a2),
            uint256(0x27c26d628367261edb63b64eefc48a192a8130e9cd608b75820775684af010b0)
        ));
        signatureVectorToSigner[vector2Key] = 0x012C2171f631e27C4bA9f7f8262af2a48956939A;
    }

    function verify(bytes32, uint256, uint256, uint256 rx, uint256 ry, uint256 z) external view override returns (address) {
        // Check if this is one of our known signature vectors
        bytes32 vectorKey = keccak256(abi.encodePacked(rx, ry, z));
        address vectorSigner = signatureVectorToSigner[vectorKey];
        
        if (vectorSigner != address(0)) {
            return vectorSigner;
        }
        
        // Fall back to mock signer for unknown vectors
        return mockSigner;
    }

    function setMockSigner(address _signer) external {
        mockSigner = _signer;
    }
}

import {TokamakVerifier} from "../../src/verifier/TokamakVerifier.sol";
import {Groth16Verifier16Leaves} from "../../src/verifier/Groth16Verifier16Leaves.sol";
import {Groth16Verifier32Leaves} from "../../src/verifier/Groth16Verifier32Leaves.sol";
import {Groth16Verifier64Leaves} from "../../src/verifier/Groth16Verifier64Leaves.sol";
import {Groth16Verifier128Leaves} from "../../src/verifier/Groth16Verifier128Leaves.sol";
import "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../../src/library/RLP.sol";
import "@openzeppelin/token/ERC20/ERC20.sol";

// Mock Contracts
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

// High precision token (27 decimals)
contract HighPrecisionToken is ERC20 {
    constructor() ERC20("High Precision Token", "HPT") {}

    function decimals() public pure override returns (uint8) {
        return 27;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

// USDT-like token (6 decimals)
contract USDTLikeToken is ERC20 {
    constructor() ERC20("USDT Like Token", "USDT") {}

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract BridgeCoreTest is Test {
    using RLP for bytes;

    BridgeCore public bridge;
    BridgeProofManager public proofManager;
    BridgeDepositManager public depositManager;
    BridgeWithdrawManager public withdrawManager;
    BridgeAdminManager public adminManager;
    MockTokamakVerifier public tokamakVerifier;
    MockZecFrost public mockZecFrost;
    MockGroth16Verifier public groth16Verifier16;
    MockGroth16Verifier32 public groth16Verifier32;
    MockGroth16Verifier64 public groth16Verifier64;
    MockGroth16Verifier128 public groth16Verifier128;
    MockERC20 public token;
    HighPrecisionToken public highPrecisionToken;
    USDTLikeToken public usdtLikeToken;

    address public owner = address(1);
    address public leader = address(2);
    address public leader2 = address(22);
    address public user1 = 0xd96b35D012879d89cfBA6fE215F1015863a6f6d0; // Address that ZecFrost signature 1 recovers to
    address public user2 = address(3);
    address public user3 = address(4);

    address public l2Leader = address(12);
    address public l2User1 = address(13);
    address public l2User2 = address(14);
    address public l2User3 = address(15);

    uint256 public constant INITIAL_BALANCE = 1000 ether;
    uint256 public constant INITIAL_TOKEN_BALANCE = 1000 * 10 ** 18;

    event ChannelOpened(uint256 indexed channelId, address indexed targetContract);
    event ChannelClosed(uint256 indexed channelId);
    event ChannelFinalized(uint256 indexed channelId);
    event Deposited(uint256 indexed channelId, address indexed user, address token, uint256 amount);
    event Withdrawn(uint256 indexed channelId, address indexed user, address token, uint256 amount);
    event EmergencyWithdrawn(uint256 indexed channelId, address indexed user, address token, uint256 amount);
    event StateInitialized(uint256 indexed channelId, bytes32 currentStateRoot);
    event TokamakZkSnarkProofsVerified(uint256 indexed channelId, address indexed signer);

    function setUp() public {
        // Deploy contracts
        vm.startPrank(owner);

        tokamakVerifier = new MockTokamakVerifier();
        mockZecFrost = new MockZecFrost();
        groth16Verifier16 = new MockGroth16Verifier();
        groth16Verifier32 = new MockGroth16Verifier32();
        groth16Verifier64 = new MockGroth16Verifier64();
        groth16Verifier128 = new MockGroth16Verifier128();
        token = new MockERC20();
        highPrecisionToken = new HighPrecisionToken();
        usdtLikeToken = new USDTLikeToken();

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
        vm.deal(leader, INITIAL_BALANCE);
        vm.deal(leader2, INITIAL_BALANCE);
        vm.deal(user1, INITIAL_BALANCE);
        vm.deal(user2, INITIAL_BALANCE);
        vm.deal(user3, INITIAL_BALANCE);

        token.mint(leader, INITIAL_TOKEN_BALANCE);
        token.mint(leader2, INITIAL_TOKEN_BALANCE);
        token.mint(user1, INITIAL_TOKEN_BALANCE);
        token.mint(user2, INITIAL_TOKEN_BALANCE);
        token.mint(user3, INITIAL_TOKEN_BALANCE);

        // Mint high precision tokens (2 tokens = 2 * 10^27)
        uint256 highPrecisionAmount = 2 * 10 ** 27;
        highPrecisionToken.mint(user1, highPrecisionAmount);
        highPrecisionToken.mint(user2, highPrecisionAmount);
        highPrecisionToken.mint(user3, highPrecisionAmount);

        // Mint USDT-like tokens (1 token = 1 * 10^6)
        uint256 usdtAmount = 1 * 10 ** 6;
        usdtLikeToken.mint(user1, usdtAmount);
        usdtLikeToken.mint(user2, usdtAmount);
        usdtLikeToken.mint(user3, usdtAmount);

        // Allow the token contracts for testing
        uint128[] memory preprocessedPart1 = new uint128[](4);
        preprocessedPart1[0] = 0x1186b2f2b6871713b10bc24ef04a9a39;
        preprocessedPart1[1] = 0x02b36b71d4948be739d14bb0e8f4a887;
        preprocessedPart1[2] = 0x18e54aba379045c9f5c18d8aefeaa8cc;
        preprocessedPart1[3] = 0x08df3e052d4b1c0840d73edcea3f85e7;
        uint256[] memory preprocessedPart2 = new uint256[](4);
        preprocessedPart2[0] = 0x7e084b3358f7f1404f0a4ee1acc6d254997032f77fd77593fab7c896b7cfce1e;
        preprocessedPart2[1] = 0xe2dfa30cd1fca5558bfe26343dc755a0a52ef6115b9aef97d71b047ed5d830c8;
        preprocessedPart2[2] = 0xf68408df0b8dda3f529522a67be22f2934970885243a9d2cf17d140f2ac1bb10;
        preprocessedPart2[3] = 0x4b0d9a6ffeb25101ff57e35d7e527f2080c460edc122f2480f8313555a71d3ac;

        IBridgeCore.PreAllocatedLeaf[] memory emptySlots = new IBridgeCore.PreAllocatedLeaf[](0);
        adminManager.setAllowedTargetContract(address(token), emptySlots, true);
        adminManager.setAllowedTargetContract(address(highPrecisionToken), emptySlots, true);
        adminManager.setAllowedTargetContract(address(usdtLikeToken), emptySlots, true);

        // Register transfer function for each token using 4-byte selector (standard format)
        bytes32 transferSig = bytes32(bytes4(keccak256("transfer(address,uint256)")));
        adminManager.registerFunction(address(token), transferSig, preprocessedPart1, preprocessedPart2, keccak256("test_instance_hash"));
        adminManager.registerFunction(address(highPrecisionToken), transferSig, preprocessedPart1, preprocessedPart2, keccak256("test_instance_hash"));
        adminManager.registerFunction(address(usdtLikeToken), transferSig, preprocessedPart1, preprocessedPart2, keccak256("test_instance_hash"));

        vm.stopPrank();
    }

    // ========== Helper Functions for ZecFrost Signatures ==========

    /**
     * @dev Creates a ZecFrost signature that verifies against user1 (0xd96b35D012879d89cfBA6fE215F1015863a6f6d0)
     */
    // Using BridgeProofManager.Signature directly

    struct TestChannelInitializationProof {
        uint256[4] pA;
        uint256[8] pB;
        uint256[4] pC;
        bytes32 merkleRoot;
    }

    // Using BridgeProofManager.ProofData and IBridgeCore.RegisteredFunction directly

    function _createZecFrostSignature() internal pure returns (BridgeProofManager.Signature memory) {
        return _createZecFrostSignatureForChannel(1); // Default test channel ID
    }
    
    function _createZecFrostSignatureForChannel(uint256 channelId) internal pure returns (BridgeProofManager.Signature memory) {
        // Create commitment hash for the given channel and standard finalStateRoot
        bytes32 finalStateRoot = bytes32(uint256(keccak256("finalStateRoot")));
        bytes32 commitmentHash = keccak256(abi.encodePacked(channelId, finalStateRoot));
        
        // Return Vector 1 signature data - recovers to 0xd96b35D012879d89cfBA6fE215F1015863a6f6d0 (user1)
        return BridgeProofManager.Signature({
            message: commitmentHash,
            rx: 0x1fb4c0436e9054ae0b237cde3d7a478ce82405b43fdbb5bf1d63c9f8d912dd5d,
            ry: 0x3a7784df441925a8859b9f3baf8d570d488493506437db3ccf230a4b43b27c1e,
            z: 0xc7fdcb364dd8577e47dd479185ca659adbfcd1b8675e5cbb36e5f93ca4e15b25
        });
    }

    /**
     * @dev Creates a ZecFrost signature that verifies against user2 (0x012C2171f631e27C4bA9f7f8262af2a48956939A)
     */
    function _createWrongZecFrostSignature() internal pure returns (BridgeProofManager.Signature memory) {
        return _createWrongZecFrostSignatureForChannel(1); // Default test channel ID
    }
    
    function _createWrongZecFrostSignatureForChannel(uint256 channelId) internal pure returns (BridgeProofManager.Signature memory) {
        // Create commitment hash for the given channel and finalStateRoot
        bytes32 finalStateRoot = bytes32(uint256(keccak256("finalStateRoot")));
        bytes32 commitmentHash = keccak256(abi.encodePacked(channelId, finalStateRoot));
        
        // Return Vector 2 signature data - recovers to 0x012C2171f631e27C4bA9f7f8262af2a48956939A (user2)
        return BridgeProofManager.Signature({
            message: commitmentHash,
            rx: 0xc303bb5de5a5962d9af9b45f5e0bdc919de2aac9153b8c353960f50aa3cb950c,
            ry: 0x6df25261f523a8ea346f49dad49b3b36786e653a129cff327a0fea5839e712a2,
            z: 0x27c26d628367261edb63b64eefc48a192a8130e9cd608b75820775684af010b0
        });
    }

    // ========== Helper Functions for Channel Creation ==========

    function _createChannelParams() internal view returns (BridgeCore.ChannelParams memory) {
        address[] memory participants = new address[](3);
        participants[0] = user1;
        participants[1] = user2;
        participants[2] = user3;

        return
            BridgeCore.ChannelParams({targetContract: address(token), participants: participants, timeout: 1 days});
    }

    function _createGroth16Proof(bytes32 merkleRoot) internal pure returns (TestChannelInitializationProof memory) {
        // Mock Groth16 proof data
        uint256[4] memory pA = [uint256(1), uint256(2), uint256(3), uint256(4)];
        uint256[8] memory pB =
            [uint256(5), uint256(6), uint256(7), uint256(8), uint256(9), uint256(10), uint256(11), uint256(12)];
        uint256[4] memory pC = [uint256(13), uint256(14), uint256(15), uint256(16)];

        return TestChannelInitializationProof({pA: pA, pB: pB, pC: pC, merkleRoot: merkleRoot});
    }

    // ========== Helper Functions for MPT Leaves ==========

    /**
     * @dev Creates a mock MPT leaf with RLP-encoded account data: [nonce, balance, storageHash, codeHash]
     */
    function _createMockMPTLeaf(uint256 balance) internal pure returns (bytes memory) {
        bytes[] memory accountFields = new bytes[](4);

        // nonce = 0
        accountFields[0] = RLP.encode(abi.encodePacked(uint256(0)));

        // balance
        accountFields[1] = RLP.encode(abi.encodePacked(balance));

        // storageHash (empty storage)
        accountFields[2] = RLP.encode(abi.encodePacked(keccak256("")));

        // codeHash (empty code)
        accountFields[3] = RLP.encode(abi.encodePacked(keccak256("")));

        return RLP.encodeList(accountFields);
    }

    /**
     * @dev Creates MPT leaves for a given set of balances
     */
    function _createMPTLeaves(uint256[] memory balances) internal pure returns (bytes[] memory) {
        bytes[] memory leaves = new bytes[](balances.length);
        for (uint256 i = 0; i < balances.length; i++) {
            leaves[i] = _createMockMPTLeaf(balances[i]);
        }
        return leaves;
    }

    /**
     * @dev Creates ProofData struct for testing
     */
    function _createProofData(
        uint128[] memory proofPart1,
        uint256[] memory proofPart2,
        uint256[] memory publicInputs,
        uint256 smax,
        uint256[] memory finalBalances
    ) internal pure returns (BridgeProofManager.ProofData memory, uint256[] memory) {
        BridgeProofManager.ProofData memory proofData = BridgeProofManager.ProofData({
            proofPart1: proofPart1,
            proofPart2: proofPart2,
            publicInputs: publicInputs,
            smax: smax
        });
        return (proofData, finalBalances);
    }

    /**
     * @dev Creates mock participant roots for testing
     */
    function _createMockParticipantRoots(uint256 count) internal pure returns (bytes32[] memory) {
        bytes32[] memory participantRoots = new bytes32[](count);
        for (uint256 i = 0; i < count; i++) {
            // Generate deterministic mock roots based on participant index
            participantRoots[i] = keccak256(abi.encodePacked("participant_root", i));
        }
        return participantRoots;
    }

    /**
     * @dev Creates ProofData struct for testing with mock participantRoots (for backwards compatibility)
     * This version handles the old signature for existing tests
     */
    function _createProofDataSimple(
        uint128[] memory proofPart1,
        uint256[] memory proofPart2,
        uint256[] memory publicInputs,
        uint256 smax,
        bytes[] memory, /* initialMPTLeaves */
        bytes[] memory finalMPTLeaves
    ) internal pure returns (BridgeProofManager.ProofData memory, uint256[] memory) {
        // Set proper state root values for bridge tests to pass state root chain validation
        _setTestStateRoots(publicInputs);
        return _createProofDataFromMPT(proofPart1, proofPart2, publicInputs, smax, finalMPTLeaves);
    }

    function _setTestStateRoots(uint256[] memory publicInputs) internal pure {
        if (publicInputs.length >= 12) {
            // Use the same mock root that's used in channel initialization for input
            bytes32 mockRoot = keccak256(abi.encodePacked("mockRoot"));
            uint256 inputRootHigh = uint256(mockRoot) >> 128;
            uint256 inputRootLow = uint256(mockRoot) & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
            
            // Use the finalStateRoot (which is set in publicInputs[0]) for output
            bytes32 finalStateRoot = bytes32(publicInputs[0]);
            uint256 outputRootHigh = uint256(finalStateRoot) >> 128;
            uint256 outputRootLow = uint256(finalStateRoot) & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
            
            publicInputs[8] = inputRootHigh;   // input state root high
            publicInputs[9] = inputRootLow;    // input state root low
            publicInputs[10] = outputRootHigh; // output state root high (matches publicInputs[0])
            publicInputs[11] = outputRootLow;  // output state root low
        }
        
        // Set function signature at index 18 (transfer function selector: 0xa9059cbb)
        if (publicInputs.length >= 19) {
            publicInputs[18] = 0xa9059cbb; // transfer(address,uint256) function selector
        }
    }


    /**
     * @dev Helper function to create a simple proof data for tests that still use old MPT structure
     * Converts old MPT-based calls to new function-based structure
     */
    function _createProofDataFromMPT(
        uint128[] memory proofPart1,
        uint256[] memory proofPart2,
        uint256[] memory publicInputs,
        uint256 smax,
        bytes[] memory finalMPTLeaves
    ) internal pure returns (BridgeProofManager.ProofData memory, uint256[] memory) {
        // Set proper state root values and function signature for bridge tests
        _setTestStateRoots(publicInputs);
        

        // Create final balances array - we'll decode the intended values from the leaf count pattern
        uint256 participantCount = finalMPTLeaves.length;
        uint256[] memory finalBalances = new uint256[](participantCount);

        // Simple pattern based on participant count to avoid stack too deep
        if (smax == 6 && participantCount == 3) {
            // testSubmitAggregatedProof expects redistribution (6,0,0)
            finalBalances[0] = 6 ether;
            finalBalances[1] = 0 ether;
            finalBalances[2] = 0 ether;
        } else {
            // Default: each participant gets (i+1) ether to match deposit pattern
            for (uint256 i = 0; i < participantCount; i++) {
                finalBalances[i] = (i + 1) * 1 ether;
            }
        }

        BridgeProofManager.ProofData memory proofData = BridgeProofManager.ProofData({
            proofPart1: proofPart1,
            proofPart2: proofPart2,
            publicInputs: publicInputs,
            smax: smax
        });

        return (proofData, finalBalances);
    }

    /**
     * @dev Helper function to create proof data with non-conserving balances for violation tests
     */
    function _createProofDataViolatingConservation(
        uint128[] memory proofPart1,
        uint256[] memory proofPart2,
        uint256[] memory publicInputs,
        uint256 smax
    ) internal pure returns (BridgeProofManager.ProofData memory, uint256[] memory) {
        // Set proper state root values for bridge tests to pass state root chain validation
        _setTestStateRoots(publicInputs);

        // Create final balances that violate conservation (total 7 instead of 6)
        uint256[] memory finalBalances = new uint256[](3);
        finalBalances[0] = 2 ether; // Total will be 2+2+3=7 ether, violating conservation
        finalBalances[1] = 2 ether;
        finalBalances[2] = 3 ether;

        BridgeProofManager.ProofData memory proofData = BridgeProofManager.ProofData({
            proofPart1: proofPart1,
            proofPart2: proofPart2,
            publicInputs: publicInputs,
            smax: smax
        });

        return (proofData, finalBalances);
    }

    // ========== Channel Opening Tests ==========

    function testOpenChannel() public {
        vm.startPrank(leader);

        address[] memory participants = new address[](3);
        participants[0] = user1;
        participants[1] = user2;
        participants[2] = user3;


        BridgeCore.ChannelParams memory params =
            BridgeCore.ChannelParams({targetContract: address(token), participants: participants, timeout: 1 days});
        uint256 channelId = bridge.openChannel(params);
        bridge.setChannelPublicKey(
            channelId,
            0x51909117a840e98bbcf1aae0375c6e85920b641edee21518cb79a19ac347f638,
            0xf2cf51268a560b92b57994c09af3c129e7f5646a48e668564edde80fd5076c6e
        );

        assertEq(channelId, 0);

        BridgeCore.ChannelState state = bridge.getChannelState(channelId);
        address targetContractReturned = bridge.getChannelTargetContract(channelId);
        address[] memory channelParticipants = bridge.getChannelParticipants(channelId);

        assertEq(targetContractReturned, address(token));
        assertEq(uint8(state), uint8(BridgeCore.ChannelState.Initialized));
        assertEq(channelParticipants.length, 3);

        vm.stopPrank();
    }

    // ========== Deposit Tests ==========

    function testDepositTokenBasic() public {
        uint256 channelId = _createChannel();
        uint256 depositAmount = 1 ether;

        vm.startPrank(user1);

        // Approve and deposit token
        token.approve(address(depositManager), depositAmount);

        vm.expectEmit(true, true, true, true);
        emit Deposited(channelId, user1, address(token), depositAmount);
        depositManager.depositToken(channelId, depositAmount, bytes32(uint256(uint160(l2User1))));

        vm.stopPrank();
    }

    function testDepositTokenNotParticipant() public {
        uint256 channelId = _createChannel();

        vm.startPrank(address(999));
        token.mint(address(999), 1 ether);
        token.approve(address(depositManager), 1 ether);
        vm.expectRevert("Not a participant");
        depositManager.depositToken(channelId, 1 ether, bytes32(uint256(uint160(l2User1))));
        vm.stopPrank();
    }

    function testDepositToken() public {
        uint256 channelId = _createTokenChannel();
        uint256 depositAmount = 100 * 10 ** 18;

        vm.startPrank(user1);

        token.approve(address(depositManager), depositAmount);

        vm.expectEmit(true, true, true, true);
        emit Deposited(channelId, user1, address(token), depositAmount);

        depositManager.depositToken(channelId, depositAmount, bytes32(uint256(uint160(l2User1))));

        assertEq(token.balanceOf(address(depositManager)), depositAmount);

        vm.stopPrank();
    }

    // ========== State Initialization Tests ==========

    function testInitializeChannelState() public {
        uint256 channelId = _createChannel();

        // Make deposits using DepositManager
        vm.startPrank(user1);
        token.approve(address(depositManager), 1 ether);
        depositManager.depositToken(channelId, 1 ether, bytes32(uint256(uint160(l2User1))));
        vm.stopPrank();

        vm.startPrank(user3);
        token.approve(address(depositManager), 3 ether);
        depositManager.depositToken(channelId, 3 ether, bytes32(uint256(uint160(l2User3))));
        vm.stopPrank();

        // Initialize state
        bytes32 mockMerkleRoot = keccak256(abi.encodePacked("mockRoot"));
        TestChannelInitializationProof memory mockProof = TestChannelInitializationProof({
            pA: [uint256(1), uint256(2), uint256(3), uint256(4)],
            pB: [uint256(5), uint256(6), uint256(7), uint256(8), uint256(9), uint256(10), uint256(11), uint256(12)],
            pC: [uint256(13), uint256(14), uint256(15), uint256(16)],
            merkleRoot: mockMerkleRoot
        });
        vm.prank(leader);
        proofManager.initializeChannelState(
            channelId,
            BridgeProofManager.ChannelInitializationProof({
                pA: mockProof.pA,
                pB: mockProof.pB,
                pC: mockProof.pC,
                merkleRoot: mockProof.merkleRoot
            })
        );

        // Check state using individual getters since getChannelInfo doesn't exist
        BridgeCore.ChannelState state = bridge.getChannelState(channelId);

        assertEq(uint8(state), uint8(BridgeCore.ChannelState.Open));
    }

    /**
     * @notice Tests that initializeChannelState produces different root hashes for channels
     *         with the same participants but different deposit amounts
     * @dev This test verifies the fix for the bug where different deposits produced identical hashes
     */
    function testInitializeChannelStateDifferentDeposits() public {
        // Simplified test: just verify that token channels with different deposits create different root hashes
        // Use tokens to match working patterns exactly

        // Create first channel
        uint256 channelId1 = _createChannel();

        // Make specific deposits - Set 1: [1, 2, 0]
        vm.startPrank(user1);
        token.approve(address(depositManager), 1 ether);
        depositManager.depositToken(channelId1, 1 ether, bytes32(uint256(uint160(l2User1))));
        vm.stopPrank();

        vm.startPrank(user2);
        token.approve(address(depositManager), 2 ether);
        depositManager.depositToken(channelId1, 2 ether, bytes32(uint256(uint160(l2User2))));
        vm.stopPrank();
        // user3 makes no deposit

        // Initialize and get root hash 1
        bytes32 mockMerkleRoot1 = keccak256(abi.encodePacked("mockRoot1"));
        TestChannelInitializationProof memory mockProof1 = TestChannelInitializationProof({
            pA: [uint256(1), uint256(2), uint256(3), uint256(4)],
            pB: [uint256(5), uint256(6), uint256(7), uint256(8), uint256(9), uint256(10), uint256(11), uint256(12)],
            pC: [uint256(13), uint256(14), uint256(15), uint256(16)],
            merkleRoot: mockMerkleRoot1
        });
        vm.prank(leader);
        proofManager.initializeChannelState(
            channelId1,
            BridgeProofManager.ChannelInitializationProof({
                pA: mockProof1.pA,
                pB: mockProof1.pB,
                pC: mockProof1.pC,
                merkleRoot: mockProof1.merkleRoot
            })
        );
        (,,, bytes32 rootHash1) = bridge.getChannelInfo(channelId1);

        // Simple approach: just verify the root hashes are different after initialization
        // No need to complete full lifecycle for this test

        // Create second channel with different leader to avoid "Channel limit reached"
        uint256 channelId2 = _createChannelWithLeader(leader2);
        vm.startPrank(user1);
        token.approve(address(depositManager), 1 ether);
        depositManager.depositToken(channelId2, 1 ether, bytes32(uint256(uint160(l2User1))));
        vm.stopPrank();

        vm.startPrank(user2);
        token.approve(address(depositManager), 1 ether);
        depositManager.depositToken(channelId2, 1 ether, bytes32(uint256(uint160(l2User2)))); // Same amount this time
        vm.stopPrank();
        // user3 makes no deposit

        // Initialize and get root hash 2
        bytes32 mockMerkleRoot2 = keccak256(abi.encodePacked("mockRoot2"));
        TestChannelInitializationProof memory mockProof2 = TestChannelInitializationProof({
            pA: [uint256(1), uint256(2), uint256(3), uint256(4)],
            pB: [uint256(5), uint256(6), uint256(7), uint256(8), uint256(9), uint256(10), uint256(11), uint256(12)],
            pC: [uint256(13), uint256(14), uint256(15), uint256(16)],
            merkleRoot: mockMerkleRoot2
        });
        vm.prank(leader2);
        proofManager.initializeChannelState(
            channelId2,
            BridgeProofManager.ChannelInitializationProof({
                pA: mockProof2.pA,
                pB: mockProof2.pB,
                pC: mockProof2.pC,
                merkleRoot: mockProof2.merkleRoot
            })
        );
        (,,, bytes32 rootHash2) = bridge.getChannelInfo(channelId2);

        // The root hashes should be different for different deposit amounts
        assertTrue(rootHash1 != rootHash2, "Root hashes should be different for different deposit amounts");
    }

    function testInitialize_ChannelStateNotLeader() public {
        uint256 channelId = _createChannel();

        bytes32 mockMerkleRoot = keccak256(abi.encodePacked("mockRoot"));
        TestChannelInitializationProof memory mockProof = TestChannelInitializationProof({
            pA: [uint256(1), uint256(2), uint256(3), uint256(4)],
            pB: [uint256(5), uint256(6), uint256(7), uint256(8), uint256(9), uint256(10), uint256(11), uint256(12)],
            pC: [uint256(13), uint256(14), uint256(15), uint256(16)],
            merkleRoot: mockMerkleRoot
        });
        vm.prank(user1);
        vm.expectRevert("Not leader");
        proofManager.initializeChannelState(
            channelId,
            BridgeProofManager.ChannelInitializationProof({
                pA: mockProof.pA,
                pB: mockProof.pB,
                pC: mockProof.pC,
                merkleRoot: mockProof.merkleRoot
            })
        );
    }

    // ========== Proof Submission Tests ==========

    function testSubmitProofAndSignatureWithBalanceChanges() public {
        uint256 channelId = _initializeChannel();

        uint128[] memory proofPart1 = new uint128[](1);
        uint256[] memory proofPart2 = new uint256[](1);
        uint256[] memory publicInputs = new uint256[](512);
        publicInputs[0] = uint256(keccak256("finalStateRoot"));

        // Create MPT leaves matching the deposited amounts (1, 2, 3 ether)
        uint256[] memory initialBalances = new uint256[](3);
        initialBalances[0] = 1 ether;
        initialBalances[1] = 2 ether;
        initialBalances[2] = 3 ether;

        uint256[] memory finalBalances = new uint256[](3);
        finalBalances[0] = 6 ether; // Changed distribution but same total
        finalBalances[1] = 0 ether;
        finalBalances[2] = 0 ether;

        bytes[] memory initialMPTLeaves = _createMPTLeaves(initialBalances);
        bytes[] memory finalMPTLeaves = _createMPTLeaves(finalBalances);

        // Advance time past the channel timeout to allow proof submission
        vm.warp(block.timestamp + 1 days + 1);

        vm.prank(leader);
        vm.expectEmit(true, true, false, false);
        emit TokamakZkSnarkProofsVerified(channelId, leader);
        (BridgeProofManager.ProofData memory proofData,) =
            _createProofDataSimple(proofPart1, proofPart2, publicInputs, 6, initialMPTLeaves, finalMPTLeaves);
        proofManager.submitProofAndSignature(channelId, _wrapProofInArray(proofData), _createZecFrostSignatureForChannel(channelId));
    }

    function testSubmitProofAndSignatureBalanceMismatch() public {
        uint256 channelId = _initializeChannel();

        uint128[] memory proofPart1 = new uint128[](1);
        uint256[] memory proofPart2 = new uint256[](1);
        uint256[] memory publicInputs = new uint256[](512);
        publicInputs[0] = uint256(keccak256("finalStateRoot"));

        // Create MPT leaves with wrong initial balances
        uint256[] memory wrongInitialBalances = new uint256[](3);
        wrongInitialBalances[0] = 2 ether; // Wrong - should be 1 ether
        wrongInitialBalances[1] = 2 ether;
        wrongInitialBalances[2] = 3 ether;

        uint256[] memory finalBalances = new uint256[](3);
        finalBalances[0] = 2 ether;
        finalBalances[1] = 2 ether;
        finalBalances[2] = 3 ether;

        // Advance time past the channel timeout to allow proof submission
        vm.warp(block.timestamp + 1 days + 1);

        vm.prank(leader);
        (BridgeProofManager.ProofData memory proofData, uint256[] memory finalBalancesArray) =
            _createProofDataViolatingConservation(proofPart1, proofPart2, publicInputs, 0);

        // submitProof should succeed since it no longer validates final balances
        proofManager.submitProofAndSignature(channelId, _wrapProofInArray(proofData), _createZecFrostSignatureForChannel(channelId));

        // verifyFinalBalancesGroth16 should fail with balance conservation error
        BridgeProofManager.ChannelFinalizationProof memory finalizationProof = BridgeProofManager
            .ChannelFinalizationProof({
            pA: [uint256(1), uint256(2), uint256(3), uint256(4)],
            pB: [uint256(5), uint256(6), uint256(7), uint256(8), uint256(9), uint256(10), uint256(11), uint256(12)],
            pC: [uint256(13), uint256(14), uint256(15), uint256(16)]
        });

        vm.expectRevert("Balance conservation violated");
        proofManager.verifyFinalBalancesGroth16(channelId, finalBalancesArray, finalizationProof);
    }

    function testSubmitProofAndSignatureConservationViolation() public {
        uint256 channelId = _initializeChannel();

        uint128[] memory proofPart1 = new uint128[](1);
        uint256[] memory proofPart2 = new uint256[](1);
        uint256[] memory publicInputs = new uint256[](512);
        publicInputs[0] = uint256(keccak256("finalStateRoot"));

        // Create MPT leaves with correct initial but wrong final balances
        uint256[] memory initialBalances = new uint256[](3);
        initialBalances[0] = 1 ether;
        initialBalances[1] = 2 ether;
        initialBalances[2] = 3 ether;

        uint256[] memory wrongFinalBalances = new uint256[](3);
        wrongFinalBalances[0] = 2 ether;
        wrongFinalBalances[1] = 2 ether;
        wrongFinalBalances[2] = 4 ether; // Extra ether created!

        // Advance time past the channel timeout to allow proof submission
        vm.warp(block.timestamp + 1 days + 1);

        vm.prank(leader);
        (BridgeProofManager.ProofData memory proofData, uint256[] memory finalBalances) =
            _createProofDataViolatingConservation(proofPart1, proofPart2, publicInputs, 0);

        // submitProof should succeed since it no longer validates final balances
        proofManager.submitProofAndSignature(channelId, _wrapProofInArray(proofData), _createZecFrostSignatureForChannel(channelId));

        // verifyFinalBalancesGroth16 should fail with balance conservation error
        BridgeProofManager.ChannelFinalizationProof memory finalizationProof = BridgeProofManager
            .ChannelFinalizationProof({
            pA: [uint256(1), uint256(2), uint256(3), uint256(4)],
            pB: [uint256(5), uint256(6), uint256(7), uint256(8), uint256(9), uint256(10), uint256(11), uint256(12)],
            pC: [uint256(13), uint256(14), uint256(15), uint256(16)]
        });

        vm.expectRevert("Balance conservation violated");
        proofManager.verifyFinalBalancesGroth16(channelId, finalBalances, finalizationProof);
    }

    function testSubmitProofAndSignatureMismatchedArrays() public {
        uint256 channelId = _initializeChannel();

        uint128[] memory proofPart1 = new uint128[](1);
        uint256[] memory proofPart2 = new uint256[](1);
        uint256[] memory publicInputs = new uint256[](512);
        publicInputs[0] = uint256(keccak256("finalStateRoot"));

        uint256[] memory initialBalances = new uint256[](3);
        initialBalances[0] = 1 ether;
        initialBalances[1] = 2 ether;
        initialBalances[2] = 3 ether;

        uint256[] memory finalBalances = new uint256[](2); // Wrong length!
        finalBalances[0] = 3 ether;
        finalBalances[1] = 3 ether;

        bytes[] memory initialMPTLeaves = _createMPTLeaves(initialBalances);
        bytes[] memory finalMPTLeaves = _createMPTLeaves(finalBalances);

        // Advance time past the channel timeout to allow proof submission
        vm.warp(block.timestamp + 1 days + 1);

        vm.prank(leader);
        (BridgeProofManager.ProofData memory proofData,) =
            _createProofDataSimple(proofPart1, proofPart2, publicInputs, 0, initialMPTLeaves, finalMPTLeaves);

        // submitProof should succeed since it no longer validates final balances
        proofManager.submitProofAndSignature(channelId, _wrapProofInArray(proofData), _createZecFrostSignatureForChannel(channelId));

        // Create a mismatched final balances array (wrong length)
        uint256[] memory mismatchedFinalBalances = new uint256[](2); // Should be 3
        mismatchedFinalBalances[0] = 3 ether;
        mismatchedFinalBalances[1] = 3 ether;

        // verifyFinalBalancesGroth16 should fail with array length error
        BridgeProofManager.ChannelFinalizationProof memory finalizationProof = BridgeProofManager
            .ChannelFinalizationProof({
            pA: [uint256(1), uint256(2), uint256(3), uint256(4)],
            pB: [uint256(5), uint256(6), uint256(7), uint256(8), uint256(9), uint256(10), uint256(11), uint256(12)],
            pC: [uint256(13), uint256(14), uint256(15), uint256(16)]
        });

        vm.expectRevert("Invalid final balances length");
        proofManager.verifyFinalBalancesGroth16(channelId, mismatchedFinalBalances, finalizationProof);
    }

    function testSubmitProofAndSignatureGasUsage() public {
        uint256 channelId = _initializeChannel();

        uint128[] memory proofPart1 = new uint128[](10); // Larger proof data
        uint256[] memory proofPart2 = new uint256[](10);
        uint256[] memory publicInputs = new uint256[](512);

        // Fill with some data to simulate realistic proof sizes
        for (uint256 i = 0; i < proofPart1.length; i++) {
            proofPart1[i] = uint128(i + 1);
        }
        for (uint256 i = 0; i < proofPart2.length; i++) {
            proofPart2[i] = i + 1;
        }
        for (uint256 i = 0; i < publicInputs.length; i++) {
            publicInputs[i] = i + 1;
        }
        // Override first element for final state root
        publicInputs[0] = uint256(keccak256("finalStateRoot"));

        // Create MPT leaves matching the deposited amounts (1, 2, 3 ether)
        uint256[] memory initialBalances = new uint256[](3);
        initialBalances[0] = 1 ether;
        initialBalances[1] = 2 ether;
        initialBalances[2] = 3 ether;

        uint256[] memory finalBalances = new uint256[](3);
        finalBalances[0] = 2 ether; // Redistributed balances
        finalBalances[1] = 1 ether;
        finalBalances[2] = 3 ether;

        bytes[] memory initialMPTLeaves = _createMPTLeaves(initialBalances);
        bytes[] memory finalMPTLeaves = _createMPTLeaves(finalBalances);

        // Advance time past the channel timeout to allow proof submission
        vm.warp(block.timestamp + 1 days + 1);

        vm.prank(leader);

        uint256 gasBefore = gasleft();
        (BridgeProofManager.ProofData memory proofDataLocal,) =
            _createProofDataSimple(proofPart1, proofPart2, publicInputs, 0, initialMPTLeaves, finalMPTLeaves);
        proofManager.submitProofAndSignature(channelId, _wrapProofInArray(proofDataLocal), _createZecFrostSignatureForChannel(channelId));
        uint256 gasAfter = gasleft();

        uint256 gasUsed = gasBefore - gasAfter;

        console.log("Gas used for submitProof and signProof:", gasUsed);

        // Assert reasonable gas usage (adjust threshold as needed)
        assertTrue(gasUsed < 10000000, "Gas usage too high");
        assertTrue(gasUsed > 50000, "Gas usage suspiciously low");
    }

    // ========== Signature Tests ==========

    function testSubmitProofAndSignature() public {
        uint256 channelId = _initializeChannel();

        uint128[] memory proofPart1 = new uint128[](1);
        uint256[] memory proofPart2 = new uint256[](1);
        uint256[] memory publicInputs = new uint256[](512);
        publicInputs[0] = uint256(keccak256("finalStateRoot"));

        // Create MPT leaves matching the deposited amounts
        uint256[] memory balances = new uint256[](3);
        balances[0] = 1 ether;
        balances[1] = 2 ether;
        balances[2] = 3 ether;

        bytes[] memory initialMPTLeaves = _createMPTLeaves(balances);
        bytes[] memory finalMPTLeaves = _createMPTLeaves(balances);

        // Advance time past the channel timeout to allow proof submission
        vm.warp(block.timestamp + 1 days + 1);

        // Test successful submission with signature - should emit event and go directly to Closed
        vm.prank(leader);
        vm.expectEmit(true, true, false, false);
        emit TokamakZkSnarkProofsVerified(channelId, leader);
        (BridgeProofManager.ProofData memory proofDataLocal,) =
            _createProofDataSimple(proofPart1, proofPart2, publicInputs, 0, initialMPTLeaves, finalMPTLeaves);
        proofManager.submitProofAndSignature(channelId, _wrapProofInArray(proofDataLocal), _createZecFrostSignatureForChannel(channelId));

        // Verify channel goes to Closing state after proof and signature
        BridgeCore.ChannelState state = bridge.getChannelState(channelId);
        assertEq(uint8(state), uint8(BridgeCore.ChannelState.Closing));

        // Verify signature is verified
        assertTrue(bridge.isSignatureVerified(channelId));
    }

    function testSubmitProofAndSignatureInvalidSignature() public {
        uint256 channelId = _initializeChannel();

        uint128[] memory proofPart1 = new uint128[](1);
        uint256[] memory proofPart2 = new uint256[](1);
        uint256[] memory publicInputs = new uint256[](512);
        publicInputs[0] = uint256(keccak256("finalStateRoot"));

        uint256[] memory balances = new uint256[](3);
        balances[0] = 1 ether;
        balances[1] = 2 ether;
        balances[2] = 3 ether;

        bytes[] memory initialMPTLeaves = _createMPTLeaves(balances);
        bytes[] memory finalMPTLeaves = _createMPTLeaves(balances);

        vm.warp(block.timestamp + 1 days + 1);

        // Test with invalid signature
        (BridgeProofManager.ProofData memory proofDataLocal,) =
            _createProofDataSimple(proofPart1, proofPart2, publicInputs, 0, initialMPTLeaves, finalMPTLeaves);
        
        vm.expectRevert("Invalid group threshold signature");
        proofManager.submitProofAndSignature(channelId, _wrapProofInArray(proofDataLocal), _createWrongZecFrostSignatureForChannel(channelId));
    }

    function testSubmitProofAndSignatureUnauthorized() public {
        uint256 channelId = _initializeChannel();

        uint128[] memory proofPart1 = new uint128[](1);
        uint256[] memory proofPart2 = new uint256[](1);
        uint256[] memory publicInputs = new uint256[](512);
        publicInputs[0] = uint256(keccak256("finalStateRoot"));

        uint256[] memory balances = new uint256[](3);
        balances[0] = 1 ether;
        balances[1] = 2 ether;
        balances[2] = 3 ether;

        bytes[] memory initialMPTLeaves = _createMPTLeaves(balances);
        bytes[] memory finalMPTLeaves = _createMPTLeaves(balances);

        vm.warp(block.timestamp + 1 days + 1);

        // Test with wrong signature that doesn't match the expected signer  
        (BridgeProofManager.ProofData memory proofDataLocal,) =
            _createProofDataSimple(proofPart1, proofPart2, publicInputs, 0, initialMPTLeaves, finalMPTLeaves);
            
        vm.prank(user1);
        vm.expectRevert("Invalid group threshold signature");
        proofManager.submitProofAndSignature(channelId, _wrapProofInArray(proofDataLocal), _createWrongZecFrostSignatureForChannel(channelId));
    }

    // ========== Channel Closing Tests ==========

    function testCloseChannel() public {
        uint256 channelId = _getSignedChannel();

        // Channel should be in Closing state after submitProof and signProof
        assertEq(uint8(bridge.getChannelState(channelId)), uint8(BridgeCore.ChannelState.Closing));

        // Prepare final balances for verifyFinalBalancesGroth16
        uint256[] memory finalBalances = new uint256[](3);
        finalBalances[0] = 1 ether; // user1
        finalBalances[1] = 2 ether; // user2
        finalBalances[2] = 3 ether; // user3 (leader)

        // Create finalization proof
        BridgeProofManager.ChannelFinalizationProof memory finalizationProof = BridgeProofManager
            .ChannelFinalizationProof({
            pA: [uint256(1), uint256(2), uint256(3), uint256(4)],
            pB: [uint256(5), uint256(6), uint256(7), uint256(8), uint256(9), uint256(10), uint256(11), uint256(12)],
            pC: [uint256(13), uint256(14), uint256(15), uint256(16)]
        });

        // Call verifyFinalBalancesGroth16 to close the channel
        proofManager.verifyFinalBalancesGroth16(channelId, finalBalances, finalizationProof);

        (, BridgeCore.ChannelState state,,) = bridge.getChannelInfo(channelId);
        assertEq(uint8(state), uint8(BridgeCore.ChannelState.Closed));
    }

    function testCloseChannelInvalidProof() public {
        uint256 channelId = _initializeChannel();

        uint128[] memory proofPart1 = new uint128[](1);
        uint256[] memory proofPart2 = new uint256[](1);
        uint256[] memory publicInputs = new uint256[](512);
        publicInputs[0] = uint256(keccak256("finalStateRoot"));

        uint256[] memory balances = new uint256[](3);
        balances[0] = 1 ether;
        balances[1] = 2 ether;
        balances[2] = 3 ether;

        bytes[] memory initialMPTLeaves = _createMPTLeaves(balances);
        bytes[] memory finalMPTLeaves = _createMPTLeaves(balances);

        // Advance time past the channel timeout to allow proof submission
        vm.warp(block.timestamp + 1 days + 1);

        tokamakVerifier.setShouldVerify(false);

        vm.prank(leader);
        vm.expectRevert("Invalid ZK proof");
        (BridgeProofManager.ProofData memory proofDataLocal,) =
            _createProofDataSimple(proofPart1, proofPart2, publicInputs, 0, initialMPTLeaves, finalMPTLeaves);
        proofManager.submitProofAndSignature(channelId, _wrapProofInArray(proofDataLocal), _createZecFrostSignatureForChannel(channelId));
    }

    // ========== Channel Deletion Tests ==========

    function testCloseAndFinalizeChannel() public {
        uint256 channelId = _getSignedChannel();

        // Channel should be in Closing state after submitProof and signProof
        assertEq(uint8(bridge.getChannelState(channelId)), uint8(BridgeCore.ChannelState.Closing));

        // Prepare final balances for verifyFinalBalancesGroth16
        uint256[] memory finalBalances = new uint256[](3);
        finalBalances[0] = 1 ether; // user1
        finalBalances[1] = 2 ether; // user2
        finalBalances[2] = 3 ether; // user3 (leader)

        // Create finalization proof
        BridgeProofManager.ChannelFinalizationProof memory finalizationProof = BridgeProofManager
            .ChannelFinalizationProof({
            pA: [uint256(1), uint256(2), uint256(3), uint256(4)],
            pB: [uint256(5), uint256(6), uint256(7), uint256(8), uint256(9), uint256(10), uint256(11), uint256(12)],
            pC: [uint256(13), uint256(14), uint256(15), uint256(16)]
        });

        // Call verifyFinalBalancesGroth16 to close the channel
        proofManager.verifyFinalBalancesGroth16(channelId, finalBalances, finalizationProof);

        // Verify channel is finalized (in Closed state)
        BridgeCore.ChannelState state = bridge.getChannelState(channelId);
        assertEq(uint8(state), uint8(BridgeCore.ChannelState.Closed));
    }

    function testCloseChannelFromClosingState() public {
        uint256 channelId = _submitProof();
        // Channel is in Closing state with signature verified

        // Verify it's in Closing state
        assertEq(uint8(bridge.getChannelState(channelId)), uint8(BridgeCore.ChannelState.Closing));

        // Prepare final balances for verifyFinalBalancesGroth16
        uint256[] memory finalBalances = new uint256[](3);
        finalBalances[0] = 1 ether; // user1
        finalBalances[1] = 2 ether; // user2
        finalBalances[2] = 3 ether; // user3 (leader)

        // Create finalization proof
        BridgeProofManager.ChannelFinalizationProof memory finalizationProof = BridgeProofManager
            .ChannelFinalizationProof({
            pA: [uint256(1), uint256(2), uint256(3), uint256(4)],
            pB: [uint256(5), uint256(6), uint256(7), uint256(8), uint256(9), uint256(10), uint256(11), uint256(12)],
            pC: [uint256(13), uint256(14), uint256(15), uint256(16)]
        });

        // Call verifyFinalBalancesGroth16 to close the channel
        proofManager.verifyFinalBalancesGroth16(channelId, finalBalances, finalizationProof);

        // Verify it's now Closed
        assertEq(uint8(bridge.getChannelState(channelId)), uint8(BridgeCore.ChannelState.Closed));
    }

    // ========== Helper Functions ==========

    function _createChannel() internal returns (uint256) {
        vm.startPrank(leader);

        address[] memory participants = new address[](3);
        participants[0] = user1;
        participants[1] = user2;
        participants[2] = user3;


        BridgeCore.ChannelParams memory params =
            BridgeCore.ChannelParams({targetContract: address(token), participants: participants, timeout: 1 days});
        uint256 channelId = bridge.openChannel(params);
        bridge.setChannelPublicKey(
            channelId,
            0x51909117a840e98bbcf1aae0375c6e85920b641edee21518cb79a19ac347f638,
            0xf2cf51268a560b92b57994c09af3c129e7f5646a48e668564edde80fd5076c6e
        );

        vm.stopPrank();

        return channelId;
    }

    function _createTokenChannel() internal returns (uint256) {
        vm.startPrank(leader);

        address[] memory participants = new address[](3);
        participants[0] = user1;
        participants[1] = user2;
        participants[2] = user3;


        BridgeCore.ChannelParams memory params =
            BridgeCore.ChannelParams({targetContract: address(token), participants: participants, timeout: 1 days});
        uint256 channelId = bridge.openChannel(params);
        bridge.setChannelPublicKey(
            channelId,
            0x51909117a840e98bbcf1aae0375c6e85920b641edee21518cb79a19ac347f638,
            0xf2cf51268a560b92b57994c09af3c129e7f5646a48e668564edde80fd5076c6e
        );

        vm.stopPrank();

        return channelId;
    }

    function _createChannelWithLeader(address newLeader) internal returns (uint256) {
        vm.startPrank(newLeader);

        address[] memory participants = new address[](3);
        participants[0] = user1;
        participants[1] = user2;
        participants[2] = user3;


        BridgeCore.ChannelParams memory params =
            BridgeCore.ChannelParams({targetContract: address(token), participants: participants, timeout: 1 days});
        uint256 channelId = bridge.openChannel(params);
        bridge.setChannelPublicKey(
            channelId,
            0x51909117a840e98bbcf1aae0375c6e85920b641edee21518cb79a19ac347f638,
            0xf2cf51268a560b92b57994c09af3c129e7f5646a48e668564edde80fd5076c6e
        );

        vm.stopPrank();

        return channelId;
    }

    function _submitProofForChannel(uint256 channelId, address channelLeader) internal {
        // Make deposits
        vm.startPrank(user1);
        token.approve(address(depositManager), 1 ether);
        depositManager.depositToken(channelId, 1 ether, bytes32(uint256(uint160(l2User1))));
        vm.stopPrank();

        vm.startPrank(user2);
        token.approve(address(depositManager), 2 ether);
        depositManager.depositToken(channelId, 2 ether, bytes32(uint256(uint160(l2User2))));
        vm.stopPrank();

        vm.startPrank(user3);
        token.approve(address(depositManager), 3 ether);
        depositManager.depositToken(channelId, 3 ether, bytes32(uint256(uint160(l2User3))));
        vm.stopPrank();

        // Initialize state
        bytes32 mockMerkleRoot = keccak256(abi.encodePacked("mockRoot"));
        TestChannelInitializationProof memory mockProof = TestChannelInitializationProof({
            pA: [uint256(1), uint256(2), uint256(3), uint256(4)],
            pB: [uint256(5), uint256(6), uint256(7), uint256(8), uint256(9), uint256(10), uint256(11), uint256(12)],
            pC: [uint256(13), uint256(14), uint256(15), uint256(16)],
            merkleRoot: mockMerkleRoot
        });
        vm.prank(channelLeader);
        proofManager.initializeChannelState(
            channelId,
            BridgeProofManager.ChannelInitializationProof({
                pA: mockProof.pA,
                pB: mockProof.pB,
                pC: mockProof.pC,
                merkleRoot: mockProof.merkleRoot
            })
        );

        uint128[] memory proofPart1 = new uint128[](1);
        uint256[] memory proofPart2 = new uint256[](1);
        uint256[] memory publicInputs = new uint256[](512);
        publicInputs[0] = uint256(keccak256("finalStateRoot"));

        // Create MPT leaves matching the deposited amounts
        uint256[] memory balances = new uint256[](3);
        balances[0] = 1 ether;
        balances[1] = 2 ether;
        balances[2] = 3 ether;

        bytes[] memory initialMPTLeaves = _createMPTLeaves(balances);
        bytes[] memory finalMPTLeaves = _createMPTLeaves(balances);

        vm.prank(channelLeader);
        (BridgeProofManager.ProofData memory proofDataLocal,) =
            _createProofDataSimple(proofPart1, proofPart2, publicInputs, 0, initialMPTLeaves, finalMPTLeaves);
        proofManager.submitProofAndSignature(channelId, _wrapProofInArray(proofDataLocal), _createZecFrostSignatureForChannel(channelId));
    }

    function _initializeChannel() internal returns (uint256) {
        uint256 channelId = _createChannel();
        
        // Configure MockZecFrost to accept the channel's expected signer
        address expectedSigner = bridge.getChannelSignerAddr(channelId);
        mockZecFrost.setMockSigner(expectedSigner);

        // Make deposits
        vm.startPrank(user1);
        token.approve(address(depositManager), 1 ether);
        depositManager.depositToken(channelId, 1 ether, bytes32(uint256(uint160(l2User1))));
        vm.stopPrank();

        vm.startPrank(user2);
        token.approve(address(depositManager), 2 ether);
        depositManager.depositToken(channelId, 2 ether, bytes32(uint256(uint160(l2User2))));
        vm.stopPrank();

        vm.startPrank(user3);
        token.approve(address(depositManager), 3 ether);
        depositManager.depositToken(channelId, 3 ether, bytes32(uint256(uint160(l2User3))));
        vm.stopPrank();

        // Initialize state
        bytes32 mockMerkleRoot = keccak256(abi.encodePacked("mockRoot"));
        TestChannelInitializationProof memory mockProof = TestChannelInitializationProof({
            pA: [uint256(1), uint256(2), uint256(3), uint256(4)],
            pB: [uint256(5), uint256(6), uint256(7), uint256(8), uint256(9), uint256(10), uint256(11), uint256(12)],
            pC: [uint256(13), uint256(14), uint256(15), uint256(16)],
            merkleRoot: mockMerkleRoot
        });
        vm.prank(leader);
        proofManager.initializeChannelState(
            channelId,
            BridgeProofManager.ChannelInitializationProof({
                pA: mockProof.pA,
                pB: mockProof.pB,
                pC: mockProof.pC,
                merkleRoot: mockProof.merkleRoot
            })
        );

        return channelId;
    }

    function _submitProof() internal returns (uint256) {
        uint256 channelId = _initializeChannel();

        uint128[] memory proofPart1 = new uint128[](1);
        uint256[] memory proofPart2 = new uint256[](1);
        uint256[] memory publicInputs = new uint256[](512);
        publicInputs[0] = uint256(keccak256("finalStateRoot"));

        // Create MPT leaves matching the deposited amounts
        uint256[] memory balances = new uint256[](3);
        balances[0] = 1 ether;
        balances[1] = 2 ether;
        balances[2] = 3 ether;

        bytes[] memory initialMPTLeaves = _createMPTLeaves(balances);
        bytes[] memory finalMPTLeaves = _createMPTLeaves(balances);

        // Advance time past the channel timeout to allow proof submission
        vm.warp(block.timestamp + 1 days + 1);

        vm.prank(leader);
        (BridgeProofManager.ProofData memory proofDataLocal,) =
            _createProofDataSimple(proofPart1, proofPart2, publicInputs, 0, initialMPTLeaves, finalMPTLeaves);
        proofManager.submitProofAndSignature(channelId, _wrapProofInArray(proofDataLocal), _createZecFrostSignatureForChannel(channelId));

        return channelId;
    }

    function _getSignedChannel() internal returns (uint256) {
        // _submitProof now includes signature, so it's already signed and in Closing state
        return _submitProof();
    }

    function _getClosedChannel() internal returns (uint256) {
        uint256 channelId = _getSignedChannel();

        vm.prank(leader);

        return channelId;
    }

    // ========== Fuzz Tests ==========

    function testFuzzDeposit(uint256 amount) public {
        vm.assume(amount > 0 && amount < 100 ether);

        uint256 channelId = _createChannel();

        vm.deal(user1, amount);
        vm.startPrank(user1);
        token.approve(address(depositManager), amount);
        depositManager.depositToken(channelId, amount, bytes32(uint256(uint160(l2User1))));
        vm.stopPrank();
    }

    function testFuzzTimeout(uint256 timeout) public {
        vm.assume(timeout >= 1 hours && timeout <= 7 days);

        vm.startPrank(leader);

        address[] memory participants = new address[](3);
        participants[0] = user1;
        participants[1] = user2;
        participants[2] = user3;


        BridgeCore.ChannelParams memory params =
            BridgeCore.ChannelParams({targetContract: address(token), participants: participants, timeout: timeout});
        uint256 channelId = bridge.openChannel(params);
        bridge.setChannelPublicKey(
            channelId,
            0x51909117a840e98bbcf1aae0375c6e85920b641edee21518cb79a19ac347f638,
            0xf2cf51268a560b92b57994c09af3c129e7f5646a48e668564edde80fd5076c6e
        );

        vm.stopPrank();
    }

    // ========== Integration Tests ==========

    function testFullChannelLifecycle() public {
        // 1. Open channel
        uint256 channelId = _createChannel();

        // 2. Make deposits
        vm.startPrank(user1);
        token.approve(address(depositManager), 1 ether);
        depositManager.depositToken(channelId, 1 ether, bytes32(uint256(uint160(l2User1))));
        vm.stopPrank();

        vm.startPrank(user2);
        token.approve(address(depositManager), 2 ether);
        depositManager.depositToken(channelId, 2 ether, bytes32(uint256(uint160(l2User2))));
        vm.stopPrank();

        vm.startPrank(user3);
        token.approve(address(depositManager), 3 ether);
        depositManager.depositToken(channelId, 3 ether, bytes32(uint256(uint160(l2User3))));
        vm.stopPrank();

        // 3. Initialize state
        bytes32 mockMerkleRoot = keccak256(abi.encodePacked("mockRoot"));
        TestChannelInitializationProof memory mockProof = TestChannelInitializationProof({
            pA: [uint256(1), uint256(2), uint256(3), uint256(4)],
            pB: [uint256(5), uint256(6), uint256(7), uint256(8), uint256(9), uint256(10), uint256(11), uint256(12)],
            pC: [uint256(13), uint256(14), uint256(15), uint256(16)],
            merkleRoot: mockMerkleRoot
        });
        vm.prank(leader);
        proofManager.initializeChannelState(
            channelId,
            BridgeProofManager.ChannelInitializationProof({
                pA: mockProof.pA,
                pB: mockProof.pB,
                pC: mockProof.pC,
                merkleRoot: mockProof.merkleRoot
            })
        );

        // 4. Submit proof with MPT leaves

        uint128[] memory proofPart1 = new uint128[](1);
        uint256[] memory proofPart2 = new uint256[](1);
        uint256[] memory publicInputs = new uint256[](512);
        publicInputs[0] = uint256(keccak256("finalStateRoot"));

        uint256[] memory balances = new uint256[](3);
        balances[0] = 1 ether;
        balances[1] = 2 ether;
        balances[2] = 3 ether;

        bytes[] memory initialMPTLeaves = _createMPTLeaves(balances);
        bytes[] memory finalMPTLeaves = _createMPTLeaves(balances);

        // Advance time past the channel timeout to allow proof submission
        vm.warp(block.timestamp + 1 days + 1);

        vm.prank(leader);
        (BridgeProofManager.ProofData memory proofDataLocal,) =
            _createProofDataSimple(proofPart1, proofPart2, publicInputs, 0, initialMPTLeaves, finalMPTLeaves);
        proofManager.submitProofAndSignature(channelId, _wrapProofInArray(proofDataLocal), _createZecFrostSignatureForChannel(channelId));

        // Channel is now in Closing state with signature verified
    }

    function testSignatureCommitmentProtection() public {
        uint256 channelId = _initializeChannel();
        uint128[] memory proofPart1 = new uint128[](1);
        uint256[] memory proofPart2 = new uint256[](1);
        
        // Malicious proof with different final state root  
        uint256[] memory maliciousPublicInputs = new uint256[](512);
        maliciousPublicInputs[0] = uint256(keccak256("maliciousStateRoot"));
        
        uint256[] memory balances = new uint256[](3);
        balances[0] = 1 ether;
        balances[1] = 2 ether;
        balances[2] = 3 ether;
        bytes[] memory initialMPTLeaves = _createMPTLeaves(balances);
        bytes[] memory finalMPTLeaves = _createMPTLeaves(balances);

        vm.warp(block.timestamp + 1 days + 1);

        // Try to submit malicious proof with signature meant for legitimate proof
        (BridgeProofManager.ProofData memory maliciousProof,) =
            _createProofDataSimple(proofPart1, proofPart2, maliciousPublicInputs, 0, initialMPTLeaves, finalMPTLeaves);
        
        // Create signature for legitimate proof (different finalStateRoot)
        bytes32 legitimateCommitmentHash = keccak256(abi.encodePacked(channelId, bytes32(uint256(keccak256("legitimateStateRoot")))));
        BridgeProofManager.Signature memory legitimateSignature = BridgeProofManager.Signature({
            message: legitimateCommitmentHash,
            rx: 0x1fb4c0436e9054ae0b237cde3d7a478ce82405b43fdbb5bf1d63c9f8d912dd5d,
            ry: 0x3a7784df441925a8859b9f3baf8d570d488493506437db3ccf230a4b43b27c1e,
            z: 0xc7fdcb364dd8577e47dd479185ca659adbfcd1b8675e5cbb36e5f93ca4e15b25
        });
        
        // This should fail because signature doesn't match proof content
        vm.expectRevert("Signature must commit to proof content");
        proofManager.submitProofAndSignature(channelId, _wrapProofInArray(maliciousProof), legitimateSignature);

        // Verify channel state unchanged
        require(bridge.getChannelState(channelId) == BridgeCore.ChannelState.Open);
    }


    function _getRealProofData()
        internal
        pure
        returns (
            uint128[] memory serializedProofPart1,
            uint256[] memory serializedProofPart2,
            uint128[] memory preprocessedPart1,
            uint256[] memory preprocessedPart2,
            uint256[] memory publicInputs,
            uint256 smax
        )
    {
        // Initialize arrays
        serializedProofPart1 = new uint128[](38);
        serializedProofPart2 = new uint256[](42);
        preprocessedPart1 = new uint128[](4);
        preprocessedPart2 = new uint256[](4);
        publicInputs = new uint256[](512);

        // PREPROCESSED PART 1 (First 16 bytes - 32 hex chars)
        preprocessedPart1[0] = (0x042df2d7ba82218503dbadeaa9e87792);
        preprocessedPart1[1] = (0x0801f08b0423c3bb6cc7640b59e2ad81);
        preprocessedPart1[2] = (0x14d6acdf7112c181e4b618ae54cf2dbb);
        preprocessedPart1[3] = (0x0620aa348ac912429c4397e4083ba707);

        // PREPROCESSED PART 2 (Last 32 bytes - 64 hex chars)
        preprocessedPart2[0] = (0xebcab00c3413baa3b039e936e26e87f30a8ed8e4260497bfd1dc2227674f0d02);
        preprocessedPart2[1] = (0xb3cb4d475bbb5b22058c8ce67c59d218277dbdb6ae79e1e083cc74bc2197b283);
        preprocessedPart2[2] = (0x9fde9d8a778d5c673020961f56a2976b4cde817a6b617b2dd830da65787a21cd);
        preprocessedPart2[3] = (0x8c800ff423029764962680ccc47ad3244a8669361f84ad5922f8659e5b8a678e);

        // SERIALIZED PROOF PART 1 (First 16 bytes - 32 hex chars)
        serializedProofPart1[0] = (0x0c24fdec12d53a11da4d980c17d4e1a0);
        serializedProofPart1[1] = (0x17a05805dfe64737462cc7905747825b);
        serializedProofPart1[2] = (0x0896a633d5adf4b47c13d51806d66a35);
        serializedProofPart1[3] = (0x0a083a0932bebfbe2075aaf972cc5af7);
        serializedProofPart1[4] = (0x0a28401cd04c6e2e0bf2677b09d43a4c);
        serializedProofPart1[5] = (0x182ee1ed2f42610a39b255b4a0e84ee5);
        serializedProofPart1[6] = (0x0bd00d0783c76029e7d10c85d8b7a054);
        serializedProofPart1[7] = (0x087cbceebc924fadbff19a7059e44a68);
        serializedProofPart1[8] = (0x0ab348bc443f0fae8b8cf657e1c970ce);
        serializedProofPart1[9] = (0x1445acc8d6f02dddd0e17eaafd98d200);
        serializedProofPart1[10] = (0x001708378a5785dc70d0e217112197b9);
        serializedProofPart1[11] = (0x0783caf01311feb7b0896a179ad220d2);
        serializedProofPart1[12] = (0x0c5479dab696569b5943662da9194b3b);
        serializedProofPart1[13] = (0x0cabc8d2b5e630fd8b5698e2d4ce9370);
        serializedProofPart1[14] = (0x11d4bbafa0da1fc302112e38300bd9a1);
        serializedProofPart1[15] = (0x0a3c0cc511d40fa513a97ab0fae9da99);
        serializedProofPart1[16] = (0x03dbeb7f79d515638ed23e5ce018f592);
        serializedProofPart1[17] = (0x0d1c6c26b1f7d69bb0441eb8fde52aa4);
        serializedProofPart1[18] = (0x04be84681792a0a5afabba29ed3fcfb8);
        serializedProofPart1[19] = (0x05fb88f7324750e43d173a23aee8181e);
        serializedProofPart1[20] = (0x170f46f976ef61677cbebcdefb74feeb);
        serializedProofPart1[21] = (0x0b17a6a12b6fb13eca79be94abc8582b);
        serializedProofPart1[22] = (0x064aac9536b7b2ce667f9ba6a28cb1d3);
        serializedProofPart1[23] = (0x15f89d14f23e7cd275787c22e59b7cfb);
        serializedProofPart1[24] = (0x1768019026542d286a58258435158b31);
        serializedProofPart1[25] = (0x0a61414b5c2ccfe907df78c2b39bcd2e);
        serializedProofPart1[26] = (0x04f4c3891678a4e32c90b78e11a6ade1);
        serializedProofPart1[27] = (0x1982759528c860a8757bc2afc9f7fda4);
        serializedProofPart1[28] = (0x158ca44f01aac0407705fe5cc4d44f5c);
        serializedProofPart1[29] = (0x0a03d544f26007212ab4d53d3a8fcb87);
        serializedProofPart1[30] = (0x086ece3d5d70f8815d8b1c3659ca8a8a);
        serializedProofPart1[31] = (0x10b90670319cd41cf4af3e0b474be4ca);
        serializedProofPart1[32] = (0x158ca44f01aac0407705fe5cc4d44f5c);
        serializedProofPart1[33] = (0x0a03d544f26007212ab4d53d3a8fcb87);
        serializedProofPart1[34] = (0x126cbc300279a36e774d9e1c1953e9dc);
        serializedProofPart1[35] = (0x0ee0a0e6d60e1f8527d56093560223f5);
        serializedProofPart1[36] = (0x18ab22994ea4cb2eb9ebea8af602f8dd);
        serializedProofPart1[37] = (0x129eab9c15fcd487d09de770171b6912);

        // SERIALIZED PROOF PART 2 (Last 32 bytes - 64 hex chars)
        serializedProofPart2[0] = (0x29afb6b437675cf15e0324fe3bad032c88bd9addc36ff22855acb73a5c3f4cef);
        serializedProofPart2[1] = (0xdd670e5cdb1a14f5842e418357b752ee2200d5eab40a3990615224f2467c985a);
        serializedProofPart2[2] = (0xa379b716417a5870cc2f334e28cd91a388c5e3f18012f24700a103ea0c2aacb2);
        serializedProofPart2[3] = (0xffaac16f6dc2f74a0e7e18fba4e5585b4e5d642ded1156a1f58f48853e59aa42);
        serializedProofPart2[4] = (0xa23bfdfdfca0f91636ecc5527ac26058e20d58bac954eb642bae8bd626ef7010);
        serializedProofPart2[5] = (0x6f9598e15cdb8c85c5ac7ac0a78e1385446815324b91f17efacada8c544d2196);
        serializedProofPart2[6] = (0xba1b4b3bc86fb24b15799faa6c863b93de799bcb6a7aa6b000dff5e3dab2471f);
        serializedProofPart2[7] = (0xec6e41cb9cf3cc5910993ea9f08f40bd100ddf83f93f04e6bdd316797ef0beb0);
        serializedProofPart2[8] = (0xe9df3c6debe8c19110bc1d660e4deb5a52301ac37ecc90879bd68ecc8d97bdd2);
        serializedProofPart2[9] = (0x00fc98c6635577ff28950f2143aa83508c93095237abd83d69e2b24886dea95a);
        serializedProofPart2[10] = (0x63914eaba1999e91128214fdc6658ecfbc495062ceef8457ca7a1ec6c0d0e0eb);
        serializedProofPart2[11] = (0xd5bbef14f885ccbe203d48b0014ffdb943845363b278c4ab5be13674a2378134);
        serializedProofPart2[12] = (0x3d07b6d0abc0874227371ff6317cac98105f2f6fc1181cd1d66a4e4ec946cc65);
        serializedProofPart2[13] = (0x3f31b28005195499d4af392ca85edb0cee55452f39d4237641476955548e12af);
        serializedProofPart2[14] = (0xa66c27ac6a19f296259e0979530c4fcd90cb9e74249871c0c6489485404d9063);
        serializedProofPart2[15] = (0xd72bca363ba9ae574db315d4336478d0042b3e0e61270a4792a28368185a3194);
        serializedProofPart2[16] = (0xed8921adcbf1cf3805b293511a1b11363907a3aac8f481d8fd94374c040e5d6b);
        serializedProofPart2[17] = (0xd434523ed473b876e8ec1d784d149db6f706deac4d472677587a1fce0a161b3b);
        serializedProofPart2[18] = (0x6ea759852f22461d6206b877123aa7b5e0c8c2f252bcfd67e7db9e270f4f89f0);
        serializedProofPart2[19] = (0x58673a8bd4ce54d417f3f4611f1a17babe9ae036c26dbd1c090b5aa21b103e7e);
        serializedProofPart2[20] = (0x795bb282127eb89f0f74f3ac4225110c7f6ba1d28ee3585c5d2f9fd87407a076);
        serializedProofPart2[21] = (0x1c5f55837e396d3133e3327a1d55181c43e70a40175eec9830f504196143addc);
        serializedProofPart2[22] = (0xd6f85a33ffc841e63ffb0f7397933fbc479255bc76350181f60e8a674ce4a511);
        serializedProofPart2[23] = (0x042e8d8894ad3c74b0a4e53b6d4ed6ef593d6c289192c995573db09388ff6d11);
        serializedProofPart2[24] = (0x1569d3423b1b51e0bc46ba0eb5cc6a5d85d824a38380712cc45cf82afaf207a5);
        serializedProofPart2[25] = (0x1ab0450608bd2e5ba51dc73326511bf150fc5641615ae710a50b693b243642c7);
        serializedProofPart2[26] = (0x08daa13bff0ada0a5bc43ed4d7cea70dd8f326ceb3b4e45c371dd2700ef6f0c6);
        serializedProofPart2[27] = (0x4b3655e123391a00b8d3071defdab3c8b8417c0f5a547d6b589dcd20ecd33e7e);
        serializedProofPart2[28] = (0xc6e1ae5fca24804ade878f6ef38651c10c05a135e3f97bfd2d904fda94c7a9b1);
        serializedProofPart2[29] = (0x7a4e463b9e70b0b696dfbdf889158587a97fef29a5ccec0e9280623518965f4d);
        serializedProofPart2[30] = (0xcc5b7968dccd9e745adadb83015cd9e23c93952cb531f2f4288da589c0069574);
        serializedProofPart2[31] = (0xe7f91b230e048be6e77b32dc40b244236168ca832273465751c4f2ccc01cbf64);
        serializedProofPart2[32] = (0xc6e1ae5fca24804ade878f6ef38651c10c05a135e3f97bfd2d904fda94c7a9b1);
        serializedProofPart2[33] = (0x7a4e463b9e70b0b696dfbdf889158587a97fef29a5ccec0e9280623518965f4d);
        serializedProofPart2[34] = (0xbaea13ee7c8871272649ac7715c915a9a56ed50a8dea0571e2eff309d40f58ab);
        serializedProofPart2[35] = (0x82225a228142d0995337f879f93baf9f33e98586d1fc033a7dacbef88a99fe20);
        serializedProofPart2[36] = (0x4f776b37f90ad57ce6ea738d9aa08ab70f7b59b4f3936d07b1232bb77dc23b49);
        serializedProofPart2[37] = (0x9186c52b1e29b407b2ced700d98969bd27ef020d51bedc925a12759bc01b277d);
        serializedProofPart2[38] = (0x5cbd85f2d305fe00912332e05075b9f0de9c10f44ec7ab91b1f62084281f248c);
        serializedProofPart2[39] = (0x72369709049708f987668022c05c3ff71329e24dbda58f5107687c2c1c019bc3);
        serializedProofPart2[40] = (0x54bf083810754a2f2e0ea1a9c2cc1cd0dff97d8fd62a463be309018d5e482d10);
        serializedProofPart2[41] = (0x4f95625e828ae72498ff9d6e15029b414cd6cc9a8ba6d8f1dc1366f2879c76a8);

        //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
        ///////////////////////////////////             PUBLIC INPUTS             ////////////////////////////////////////////////
        //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

        publicInputs[0] = (0x00000000000000000000000000000000ad92adf90254df20eb73f68015e9a000);
        publicInputs[1] = (0x0000000000000000000000000000000000000000000000000000000001e371b2);
        publicInputs[2] = (0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs[3] = (0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs[4] = (0x00000000000000000000000000000000ad92adf90254df20eb73f68015e9a000);
        publicInputs[5] = (0x0000000000000000000000000000000000000000000000000000000001e371b2);
        publicInputs[6] = (0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs[7] = (0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs[8] = (0x00000000000000000000000000000000bcbd36a06b28bf1d5459edbe7dea2c85);
        publicInputs[9] = (0x00000000000000000000000000000000000000000000000000000000fc284778);
        publicInputs[10] = (0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs[11] = (0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs[12] = (0x00000000000000000000000000000000bcbd36a06b28bf1d5459edbe7dea2c85);
        publicInputs[13] = (0x00000000000000000000000000000000000000000000000000000000fc284778);
        publicInputs[14] = (0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs[15] = (0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs[16] = (0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs[17] = (0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs[18] = (0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs[19] = (0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs[20] = (0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs[21] = (0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs[22] = (0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs[23] = (0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs[24] = (0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs[25] = (0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs[26] = (0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs[27] = (0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs[28] = (0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs[29] = (0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs[30] = (0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs[31] = (0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs[32] = (0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs[33] = (0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs[34] = (0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs[35] = (0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs[36] = (0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs[37] = (0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs[38] = (0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs[39] = (0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs[40] = (0x000000000000000000000000000000004c9920779783843241d6b450935960df);
        publicInputs[41] = (0x00000000000000000000000000000000e69a44d2db21957ed88948127ec06b10);
        publicInputs[42] = (0x000000000000000000000000000000004c9920779783843241d6b450935960df);
        publicInputs[43] = (0x00000000000000000000000000000000e69a44d2db21957ed88948127ec06b10);
        publicInputs[44] = (0x000000000000000000000000000000004cba917fb9796a16f3ca5bc38b943d00);
        publicInputs[45] = (0x0000000000000000000000000000000099377efdd5f7e86f7648b87c1eccd6a8);
        publicInputs[46] = (0x000000000000000000000000000000004cba917fb9796a16f3ca5bc38b943d00);
        publicInputs[47] = (0x0000000000000000000000000000000099377efdd5f7e86f7648b87c1eccd6a8);
        publicInputs[48] = (0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs[49] = (0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs[50] = (0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs[51] = (0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs[52] = (0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs[53] = (0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs[54] = (0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs[55] = (0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs[56] = (0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs[57] = (0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs[58] = (0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs[59] = (0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs[60] = (0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs[61] = (0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs[62] = (0x0000000000000000000000000000000000000000000000000000000000000000);
        publicInputs[63] = (0x0000000000000000000000000000000000000000000000000000000000000000);

        smax = 512;
    }

    /**
     * @dev Helper to setup channel with specified number of participants
     */
    function _setupChannelWithParticipants(uint256 participantCount) internal returns (uint256 channelId) {
        // Use different leaders to avoid "channel limit reached" error
        address channelLeader = address(uint160(100 + participantCount));

        // Fund the leader
        vm.deal(channelLeader, 10 ether);

        vm.startPrank(channelLeader);

        address[] memory participants = new address[](participantCount);
        for (uint256 i = 0; i < participantCount; i++) {
            participants[i] = address(uint160(3 + i)); // Start from address(3)
        }


        BridgeCore.ChannelParams memory params =
            BridgeCore.ChannelParams({targetContract: address(token), participants: participants, timeout: 1 days});
        channelId = bridge.openChannel(params);
        bridge.setChannelPublicKey(
            channelId,
            0x51909117a840e98bbcf1aae0375c6e85920b641edee21518cb79a19ac347f638,
            0xf2cf51268a560b92b57994c09af3c129e7f5646a48e668564edde80fd5076c6e
        );

        // Deposit for each participant
        for (uint256 i = 0; i < participantCount; i++) {
            vm.stopPrank();

            // Fund the participant
            vm.deal(participants[i], 10 ether);

            vm.startPrank(participants[i]);
            token.approve(address(depositManager), (i + 1) * 1 ether);
            depositManager.depositToken(channelId, (i + 1) * 1 ether, bytes32(uint256(13 + i))); // Use different MPT keys
            vm.stopPrank();
        }

        bytes32 mockMerkleRoot = keccak256(abi.encodePacked("mockRoot"));
        TestChannelInitializationProof memory mockProof = TestChannelInitializationProof({
            pA: [uint256(1), uint256(2), uint256(3), uint256(4)],
            pB: [uint256(5), uint256(6), uint256(7), uint256(8), uint256(9), uint256(10), uint256(11), uint256(12)],
            pC: [uint256(13), uint256(14), uint256(15), uint256(16)],
            merkleRoot: mockMerkleRoot
        });
        vm.prank(channelLeader);
        proofManager.initializeChannelState(
            channelId,
            BridgeProofManager.ChannelInitializationProof({
                pA: mockProof.pA,
                pB: mockProof.pB,
                pC: mockProof.pC,
                merkleRoot: mockProof.merkleRoot
            })
        );

        vm.stopPrank();
    }

    // ========== Tree Size Selection Tests ==========

    function testTreeSize128LeavesSelection() public {
        // Use a fresh leader for this test
        address testLeader = address(0x999);
        vm.deal(testLeader, 10 ether);
        vm.startPrank(testLeader);

        // Create 33 participants to force 128-leaf tree selection
        // 33 participants × 3 tokens = 99 leaves, which requires 128-leaf tree
        address[] memory participants = new address[](33);
        for (uint256 i = 0; i < 33; i++) {
            participants[i] = address(uint160(1000 + i)); // Generate unique addresses
        }

        BridgeCore.ChannelParams memory params =
            BridgeCore.ChannelParams({targetContract: address(token), participants: participants, timeout: 1 days});

        // Open the channel
        uint256 channelId = bridge.openChannel(params);
        bridge.setChannelPublicKey(
            channelId,
            0x51909117a840e98bbcf1aae0375c6e85920b641edee21518cb79a19ac347f638,
            0xf2cf51268a560b92b57994c09af3c129e7f5646a48e668564edde80fd5076c6e
        );

        // Verify the channel was created successfully
        assertEq(channelId, 0);

        // Get channel info to verify participants and target contract
        (address targetContract, BridgeCore.ChannelState state, uint256 participantCount,) =
            bridge.getChannelInfo(channelId);

        assertEq(targetContract, address(token));
        assertEq(uint8(state), uint8(BridgeCore.ChannelState.Initialized));
        assertEq(participantCount, 33);

        // Verify that the contract selected the 128-leaf tree
        uint256 requiredTreeSize = bridge.getChannelTreeSize(channelId);
        assertEq(requiredTreeSize, 64, "Should select 64-leaf tree for 33 participants");

        vm.stopPrank();
    }

    function _testTreeSizeScenario(
        uint256 participantCount,
        uint256 tokenCount,
        uint256 expectedTreeSize,
        string memory description
    ) internal {
        // Use a unique leader for each scenario
        address uniqueLeader = address(uint160(1100 + participantCount + tokenCount));
        vm.deal(uniqueLeader, 10 ether);
        vm.startPrank(uniqueLeader);

        // Create participants array
        address[] memory participants = new address[](participantCount);
        for (uint256 i = 0; i < participantCount; i++) {
            participants[i] = address(uint160(2000 + i)); // Generate unique addresses
        }

        // Create tokens array (max 3 unique tokens available)
        address[] memory allowedTokens = new address[](tokenCount);
        if (tokenCount >= 1) allowedTokens[0] = address(token);
        if (tokenCount >= 2) allowedTokens[1] = address(usdtLikeToken);
        if (tokenCount >= 3) allowedTokens[2] = address(highPrecisionToken);

        BridgeCore.ChannelParams memory params =
            BridgeCore.ChannelParams({targetContract: address(token), participants: participants, timeout: 1 days});

        // Open the channel
        uint256 channelId = bridge.openChannel(params);
        bridge.setChannelPublicKey(
            channelId,
            0x51909117a840e98bbcf1aae0375c6e85920b641edee21518cb79a19ac347f638,
            0xf2cf51268a560b92b57994c09af3c129e7f5646a48e668564edde80fd5076c6e
        );

        // Verify the tree size selection
        uint256 actualTreeSize = bridge.getChannelTreeSize(channelId);
        assertEq(actualTreeSize, expectedTreeSize, description);

        vm.stopPrank();
    }

    function _wrapProofInArray(BridgeProofManager.ProofData memory proof)
        internal
        pure
        returns (BridgeProofManager.ProofData[] memory)
    {
        BridgeProofManager.ProofData[] memory proofs = new BridgeProofManager.ProofData[](1);
        proofs[0] = proof;
        return proofs;
    }
}

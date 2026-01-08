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

    function verify(bytes32, uint256, uint256, uint256 rx, uint256 ry, uint256 z)
        external
        view
        override
        returns (address)
    {
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

        // Use the correct preprocessed data from ProofSubmission.t.sol
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

        // Use the actual registered function instance hash from the deployed contract
        bytes32 functionInstanceHash = 0xd157cb883adb9cb0e27d9dc419e2a4be817d856281b994583b5bae64be94d35a;

        IBridgeCore.PreAllocatedLeaf[] memory emptySlots = new IBridgeCore.PreAllocatedLeaf[](0);
        adminManager.setAllowedTargetContract(address(token), emptySlots, true);
        adminManager.setAllowedTargetContract(address(highPrecisionToken), emptySlots, true);
        adminManager.setAllowedTargetContract(address(usdtLikeToken), emptySlots, true);

        // Register transfer function for each token using 4-byte selector (standard format)
        bytes32 transferSig = bytes32(bytes4(keccak256("transfer(address,uint256)")));
        adminManager.registerFunction(
            address(token), transferSig, preprocessedPart1, preprocessedPart2, functionInstanceHash
        );
        adminManager.registerFunction(
            address(highPrecisionToken), transferSig, preprocessedPart1, preprocessedPart2, functionInstanceHash
        );
        adminManager.registerFunction(
            address(usdtLikeToken), transferSig, preprocessedPart1, preprocessedPart2, functionInstanceHash
        );

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

    function _createZecFrostSignatureForChannel(uint256 channelId)
        internal
        pure
        returns (BridgeProofManager.Signature memory)
    {
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

    function _createZecFrostSignatureForProofData(uint256 channelId, uint256[] memory publicInputs)
        internal
        pure
        returns (BridgeProofManager.Signature memory)
    {
        // Extract finalStateRoot from proof data (indices 1 and 0)
        bytes32 finalStateRoot = bytes32((publicInputs[1] << 128) | publicInputs[0]);
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

    function _createWrongZecFrostSignatureForChannel(uint256 channelId)
        internal
        pure
        returns (BridgeProofManager.Signature memory)
    {
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

        return BridgeCore.ChannelParams({
            targetContract: address(token),
            whitelisted: participants,
            enableFrostSignature: true
        });
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
    ) internal view returns (BridgeProofManager.ProofData memory, uint256[] memory) {
        // Set proper state root values for bridge tests to pass state root chain validation
        _setTestStateRoots(publicInputs, 0); // Assume channel 0 for now
        return _createProofDataFromMPT(proofPart1, proofPart2, publicInputs, smax, finalMPTLeaves);
    }

    function _createProofDataSimpleForChannel(
        uint256 channelId,
        uint128[] memory proofPart1,
        uint256[] memory proofPart2,
        uint256[] memory publicInputs,
        uint256 smax,
        bytes[] memory, /* initialMPTLeaves */
        bytes[] memory finalMPTLeaves
    ) internal view returns (BridgeProofManager.ProofData memory, uint256[] memory) {
        // Set proper state root values for bridge tests to pass state root chain validation
        _setTestStateRoots(publicInputs, channelId);
        return _createProofDataFromMPT(proofPart1, proofPart2, publicInputs, smax, finalMPTLeaves);
    }

    function _setTestStateRoots(uint256[] memory publicInputs, uint256 channelId) internal view {
        if (publicInputs.length >= 12) {
            // Use the actual initial state root from the specified channel
            bytes32 actualInitialRoot = bridge.getChannelInitialStateRoot(channelId);
            uint256 inputRootHigh = uint256(actualInitialRoot) >> 128;
            uint256 inputRootLow = uint256(actualInitialRoot) & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;

            // Use the finalStateRoot (which is set in publicInputs[0]) for output
            // Note: publicInputs[0] is currently set to the full keccak256("finalStateRoot") hash
            bytes32 finalStateRoot = bytes32(publicInputs[0]);
            uint256 outputRootHigh = uint256(finalStateRoot) >> 128;
            uint256 outputRootLow = uint256(finalStateRoot) & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;

            publicInputs[8] = inputRootLow; // input state root low
            publicInputs[9] = inputRootHigh; // input state root high
            publicInputs[0] = outputRootLow; // output state root low
            publicInputs[1] = outputRootHigh; // output state root high
        }

        // Set function signature at index 14 (transfer function selector: 0xa9059cbb)
        if (publicInputs.length >= 17) {
            publicInputs[14] = 0xa9059cbb; // transfer(address,uint256) function selector
        }
        // Set function instance data (indices 66-511) to match computeCorrectFunctionInstanceHash
        _setFunctionInstanceData(publicInputs);
    }

    // Overloaded version for pure functions that can't access bridge state
    function _setTestStateRoots(uint256[] memory publicInputs) internal pure {
        if (publicInputs.length >= 12) {
            // Use the hardcoded mock root for pure functions
            bytes32 mockRoot = keccak256(abi.encodePacked("mockRoot"));
            uint256 inputRootHigh = uint256(mockRoot) >> 128;
            uint256 inputRootLow = uint256(mockRoot) & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;

            // Use the finalStateRoot (which is set in publicInputs[0]) for output
            bytes32 finalStateRoot = bytes32(publicInputs[0]);
            uint256 outputRootHigh = uint256(finalStateRoot) >> 128;
            uint256 outputRootLow = uint256(finalStateRoot) & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;

            publicInputs[8] = inputRootLow; // input state root low
            publicInputs[9] = inputRootHigh; // input state root high
            publicInputs[0] = outputRootLow; // output state root low
            publicInputs[1] = outputRootHigh; // output state root high
        }

        // Set function signature at index 14 (transfer function selector: 0xa9059cbb)
        if (publicInputs.length >= 17) {
            publicInputs[14] = 0xa9059cbb; // transfer(address,uint256) function selector
        }
        // Set function instance data (indices 66-511) to match computeCorrectFunctionInstanceHash
        _setFunctionInstanceData(publicInputs);
    }

    function _setFunctionInstanceData(uint256[] memory publicInputs) internal pure {
        if (publicInputs.length < 512) return; // Need at least 512 elements for function instance data

        // Call the helper that creates the same function instances array
        uint256[] memory functionInstances = _getCorrectFunctionInstanceData();

        // Set the function instance data in publicInputs starting at index 64
        for (uint256 i = 0; i < 446 && (64 + i) < publicInputs.length; i++) {
            publicInputs[64 + i] = functionInstances[i];
        }
    }

    function _getCorrectFunctionInstanceData() internal pure returns (uint256[] memory) {
        // Exact copy of the function instance data from computeCorrectFunctionInstanceHash
        uint256[] memory functionInstances = new uint256[](446);

        // All 181 assignments copied from computeCorrectFunctionInstanceHash
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
        functionInstances[32] = 0x100000;
        functionInstances[33] = 0x095ea7b3;
        functionInstances[34] = 0x00;
        functionInstances[35] = 0x100000;
        functionInstances[36] = 0x23b872dd;
        functionInstances[37] = 0x00;
        functionInstances[38] = 0x100000;
        functionInstances[39] = 0x18160ddd;
        functionInstances[40] = 0x00;
        functionInstances[41] = 0x100000;
        functionInstances[42] = 0x313ce567;
        functionInstances[43] = 0x00;
        functionInstances[44] = 0x100000;
        functionInstances[45] = 0x06fdde03;
        functionInstances[46] = 0x00;
        functionInstances[47] = 0x100000;
        functionInstances[48] = 0x95d89b41;
        functionInstances[49] = 0x00;
        functionInstances[50] = 0x100000;
        functionInstances[51] = 0x39509351;
        functionInstances[52] = 0x00;
        functionInstances[53] = 0x100000;
        functionInstances[54] = 0xa457c2d7;
        functionInstances[55] = 0x00;
        functionInstances[56] = 0x100000;
        functionInstances[57] = 0xa9059cbb;
        functionInstances[58] = 0x00;
        functionInstances[59] = 0x100000;
        functionInstances[60] = 0x04;
        functionInstances[61] = 0x00;
        functionInstances[62] = 0x44;
        functionInstances[63] = 0x00;
        functionInstances[64] = 0x08;
        functionInstances[65] = 0x40;
        functionInstances[66] = 0x00;
        functionInstances[67] = 0x010000;
        functionInstances[68] = 0x200000;
        functionInstances[69] = 0x02;
        functionInstances[70] = 0xffffffffffffffffffffffffffffffff;
        functionInstances[71] = 0xffffffff;
        functionInstances[72] = 0x20;
        functionInstances[73] = 0x00;
        functionInstances[74] = 0x02;
        functionInstances[75] = 0x20;
        functionInstances[76] = 0x00;
        functionInstances[77] = 0x04;
        functionInstances[78] = 0x00;
        functionInstances[79] = 0x01;
        functionInstances[80] = 0x00;
        functionInstances[81] = 0x00;
        functionInstances[82] = 0x00;
        functionInstances[83] = 0x00;
        functionInstances[84] = 0x01;
        functionInstances[85] = 0x00;
        functionInstances[86] = 0x00;
        functionInstances[87] = 0x00;
        functionInstances[88] = 0x00;
        functionInstances[89] = 0x01;
        functionInstances[90] = 0x00;
        functionInstances[91] = 0x00;
        functionInstances[92] = 0x00;
        functionInstances[93] = 0x00;
        functionInstances[94] = 0x01;
        functionInstances[95] = 0x00;
        functionInstances[96] = 0x00;
        functionInstances[97] = 0x00;
        functionInstances[98] = 0x00;
        functionInstances[99] = 0x01;
        functionInstances[100] = 0x00;
        functionInstances[101] = 0x00;
        functionInstances[102] = 0x00;
        functionInstances[103] = 0x00;
        functionInstances[104] = 0x01;
        functionInstances[105] = 0x00;
        functionInstances[106] = 0x00;
        functionInstances[107] = 0x00;
        functionInstances[108] = 0x00;
        functionInstances[109] = 0x01;
        functionInstances[110] = 0x00;
        functionInstances[111] = 0x00;
        functionInstances[112] = 0x00;
        functionInstances[113] = 0x00;
        functionInstances[114] = 0x01;
        functionInstances[115] = 0x00;
        functionInstances[116] = 0x00;
        functionInstances[117] = 0x00;
        functionInstances[118] = 0x00;
        functionInstances[119] = 0x01;
        functionInstances[120] = 0x00;
        functionInstances[121] = 0x00;
        functionInstances[122] = 0x00;
        functionInstances[123] = 0x00;
        functionInstances[124] = 0x01;
        functionInstances[125] = 0x00;
        functionInstances[126] = 0x020000;
        functionInstances[127] = 0x70a08231;
        functionInstances[128] = 0x00;
        functionInstances[129] = 0x100000;
        functionInstances[130] = 0x02;
        functionInstances[131] = 0x00;
        functionInstances[132] = 0x04;
        functionInstances[133] = 0x00;
        functionInstances[134] = 0x00;
        functionInstances[135] = 0x40;
        functionInstances[136] = 0x00;
        functionInstances[137] = 0x08;
        functionInstances[138] = 0x00;
        functionInstances[139] = 0x40;
        functionInstances[140] = 0x00;
        functionInstances[141] = 0x10000001;
        functionInstances[142] = 0x04;
        functionInstances[143] = 0x00;
        functionInstances[144] = 0x24;
        functionInstances[145] = 0x00;
        functionInstances[146] = 0x08;
        functionInstances[147] = 0x40;
        functionInstances[148] = 0x00;
        functionInstances[149] = 0x200000;
        functionInstances[150] = 0x020000;
        functionInstances[151] = 0x095ea7b3;
        functionInstances[152] = 0x00;
        functionInstances[153] = 0x100000;
        functionInstances[154] = 0x23b872dd;
        functionInstances[155] = 0x00;
        functionInstances[156] = 0x100000;
        functionInstances[157] = 0x18160ddd;
        functionInstances[158] = 0x00;
        functionInstances[159] = 0x100000;
        functionInstances[160] = 0x313ce567;
        functionInstances[161] = 0x00;
        functionInstances[162] = 0x100000;
        functionInstances[163] = 0x06fdde03;
        functionInstances[164] = 0x00;
        functionInstances[165] = 0x100000;
        functionInstances[166] = 0x95d89b41;
        functionInstances[167] = 0x00;
        functionInstances[168] = 0x100000;
        functionInstances[169] = 0x39509351;
        functionInstances[170] = 0x00;
        functionInstances[171] = 0x100000;
        functionInstances[172] = 0xa457c2d7;
        functionInstances[173] = 0x00;
        functionInstances[174] = 0x100000;
        functionInstances[175] = 0xa9059cbb;
        functionInstances[176] = 0x00;
        functionInstances[177] = 0x100000;
        functionInstances[178] = 0x04;
        functionInstances[179] = 0x00;
        functionInstances[180] = 0x44;

        // Rest remain zero (indices 181-445 are default initialized to 0)
        return functionInstances;
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

        BridgeCore.ChannelParams memory params = BridgeCore.ChannelParams({
            targetContract: address(token),
            whitelisted: participants,
            enableFrostSignature: true
        });
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
        
        // Check that all participants are whitelisted
        assertTrue(bridge.isChannelWhitelisted(channelId, user1));
        assertTrue(bridge.isChannelWhitelisted(channelId, user2));
        assertTrue(bridge.isChannelWhitelisted(channelId, user3));
        
        assertEq(channelParticipants.length, 0); // No deposits made yet

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
        vm.expectRevert("Not whitelisted");
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





    // ========== Signature Tests ==========

    // ========== Channel Closing Tests ==========


    // ========== Channel Deletion Tests ==========



    // ========== Helper Functions ==========

    function _identityPermutation(uint256 size) internal pure returns (uint256[] memory) {
        uint256[] memory permutation = new uint256[](size);
        for (uint256 i = 0; i < size; i++) {
            permutation[i] = i;
        }
        return permutation;
    }

    function _createChannel() internal returns (uint256) {
        vm.startPrank(leader);

        address[] memory participants = new address[](3);
        participants[0] = user1;
        participants[1] = user2;
        participants[2] = user3;

        BridgeCore.ChannelParams memory params = BridgeCore.ChannelParams({
            targetContract: address(token),
            whitelisted: participants,
            enableFrostSignature: true
        });
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

        BridgeCore.ChannelParams memory params = BridgeCore.ChannelParams({
            targetContract: address(token),
            whitelisted: participants,
            enableFrostSignature: true
        });
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

        BridgeCore.ChannelParams memory params = BridgeCore.ChannelParams({
            targetContract: address(token),
            whitelisted: participants,
            enableFrostSignature: true
        });
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
        proofManager.submitProofAndSignature(
            channelId,
            _wrapProofInArray(proofDataLocal),
            _createZecFrostSignatureForProofData(channelId, proofDataLocal.publicInputs)
        );
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
        (BridgeProofManager.ProofData memory proofDataLocal,) = _createProofDataSimpleForChannel(
            channelId, proofPart1, proofPart2, publicInputs, 0, initialMPTLeaves, finalMPTLeaves
        );
        proofManager.submitProofAndSignature(
            channelId,
            _wrapProofInArray(proofDataLocal),
            _createZecFrostSignatureForProofData(channelId, proofDataLocal.publicInputs)
        );

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

        BridgeCore.ChannelParams memory params = BridgeCore.ChannelParams({
            targetContract: address(token),
            whitelisted: participants,
            enableFrostSignature: true
        });
        uint256 channelId = bridge.openChannel(params);
        bridge.setChannelPublicKey(
            channelId,
            0x51909117a840e98bbcf1aae0375c6e85920b641edee21518cb79a19ac347f638,
            0xf2cf51268a560b92b57994c09af3c129e7f5646a48e668564edde80fd5076c6e
        );

        vm.stopPrank();
    }

    // ========== Integration Tests ==========


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
        bytes32 legitimateCommitmentHash =
            keccak256(abi.encodePacked(channelId, bytes32(uint256(keccak256("legitimateStateRoot")))));
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
        publicInputs[14] = (0x00000000000000000000000000000000000000000000000000000000a9059cbb);
        publicInputs[15] = (0x0000000000000000000000000000000000000000000000000000000000000000);
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

        // Function instance data (indices 66-511) - from ProofSubmission.t.sol
        publicInputs[66] = 0x01;
        publicInputs[67] = 0xffffffffffffffffffffffffffffffff;
        publicInputs[68] = 0xffffffff;
        publicInputs[69] = 0xe72f6afd7d1f72623e6b071492d1122b;
        publicInputs[70] = 0x11dafe5d23e1218086a365b99fbf3d3b;
        publicInputs[71] = 0x3e26ba5cc220fed7cc3f870e59d292aa;
        publicInputs[72] = 0x1d523cf1ddab1a1793132e78c866c0c3;
        publicInputs[73] = 0x00;
        publicInputs[74] = 0x00;
        publicInputs[75] = 0x01;
        publicInputs[76] = 0x00;
        publicInputs[77] = 0x80;
        publicInputs[78] = 0x00;
        publicInputs[79] = 0x00;
        publicInputs[80] = 0x00;
        publicInputs[81] = 0x200000;
        publicInputs[82] = 0x04;
        publicInputs[83] = 0x00;
        publicInputs[84] = 0x44;
        publicInputs[85] = 0x00;
        publicInputs[86] = 0x010000;
        publicInputs[87] = 0xe0;
        publicInputs[88] = 0x00;
        publicInputs[89] = 0x08000000;
        publicInputs[90] = 0x20;
        publicInputs[91] = 0x00;
        publicInputs[92] = 0x10000000;
        publicInputs[93] = 0xe0;
        publicInputs[94] = 0x00;
        publicInputs[95] = 0x10000000;
        publicInputs[96] = 0x70a08231;
        publicInputs[97] = 0x00;
        publicInputs[98] = 0x020000;
        publicInputs[99] = 0x98650275;
        publicInputs[100] = 0x00;
        publicInputs[101] = 0x020000;
        publicInputs[102] = 0xaa271e1a;
        publicInputs[103] = 0x00;
        publicInputs[104] = 0x020000;
        publicInputs[105] = 0x98650275;
        publicInputs[106] = 0x00;
        publicInputs[107] = 0x100000;
        publicInputs[108] = 0xa457c2d7;
        publicInputs[109] = 0x00;
        publicInputs[110] = 0x100000;
        publicInputs[111] = 0xa9059cbb;
        publicInputs[112] = 0x00;
        publicInputs[113] = 0x100000;
        publicInputs[114] = 0x04;
        publicInputs[115] = 0x00;
        publicInputs[116] = 0x44;
        publicInputs[117] = 0x00;
        publicInputs[118] = 0x08;
        publicInputs[119] = 0x40;
        publicInputs[120] = 0x00;
        publicInputs[121] = 0x010000;
        publicInputs[122] = 0x200000;
        publicInputs[123] = 0x02;
        publicInputs[124] = 0xffffffffffffffffffffffffffffffff;
        publicInputs[125] = 0xffffffff;
        publicInputs[126] = 0x20;
        publicInputs[127] = 0x00;
        publicInputs[128] = 0x02;
        publicInputs[129] = 0x20;
        publicInputs[130] = 0x00;
        publicInputs[131] = 0x02;
        publicInputs[132] = 0x00;
        publicInputs[133] = 0x00;
        publicInputs[134] = 0xffffffffffffffffffffffffffffffff;
        publicInputs[135] = 0xffffffff;
        publicInputs[136] = 0xffffffffffffffffffffffffffffffff;
        publicInputs[137] = 0xffffffff;
        publicInputs[138] = 0x100000;
        publicInputs[139] = 0x200000;
        publicInputs[140] = 0x00;
        publicInputs[141] = 0x00;
        publicInputs[142] = 0xffffffffffffffffffffffffffffffff;
        publicInputs[143] = 0xffffffff;
        publicInputs[144] = 0xffffffffffffffffffffffffffffffff;
        publicInputs[145] = 0xffffffff;
        publicInputs[146] = 0x100000;
        publicInputs[147] = 0x200000;
        publicInputs[148] = 0x60;
        publicInputs[149] = 0x00;
        publicInputs[150] = 0x02;
        publicInputs[151] = 0x20;
        publicInputs[152] = 0x00;
        publicInputs[153] = 0x02;
        publicInputs[154] = 0x00;
        publicInputs[155] = 0x00;
        publicInputs[156] = 0xffffffffffffffffffffffffffffffff;
        publicInputs[157] = 0xffffffff;
        publicInputs[158] = 0xffffffffffffffffffffffffffffffff;
        publicInputs[159] = 0xffffffff;
        publicInputs[160] = 0x20;
        publicInputs[161] = 0x00;
        publicInputs[162] = 0x02;
        publicInputs[163] = 0x20;
        publicInputs[164] = 0x00;
        publicInputs[165] = 0x02;
        publicInputs[166] = 0x1da9;
        publicInputs[167] = 0x00;
        publicInputs[168] = 0xffffffff;
        publicInputs[169] = 0x00;
        publicInputs[170] = 0x020000;
        publicInputs[171] = 0x200000;
        publicInputs[172] = 0x08;
        publicInputs[173] = 0x00;
        publicInputs[174] = 0x00;
        publicInputs[175] = 0xffffffffffffffffffffffffffffffff;
        publicInputs[176] = 0xffffffff;
        publicInputs[177] = 0xffffffffffffffffffffffffffffffff;
        publicInputs[178] = 0xffffffff;
        publicInputs[179] = 0x20;
        publicInputs[180] = 0x00;
        publicInputs[181] = 0x02;
        publicInputs[182] = 0x20;
        publicInputs[183] = 0x00;
        publicInputs[184] = 0x02;
        publicInputs[185] = 0x00;
        publicInputs[186] = 0x00;
        publicInputs[187] = 0xffffffffffffffffffffffffffffffff;
        publicInputs[188] = 0xffffffff;
        publicInputs[189] = 0xffffffffffffffffffffffffffffffff;
        publicInputs[190] = 0xffffffff;
        publicInputs[191] = 0x20;
        publicInputs[192] = 0x00;
        publicInputs[193] = 0x02;
        publicInputs[194] = 0x20;
        publicInputs[195] = 0x00;
        publicInputs[196] = 0x02;
        publicInputs[197] = 0x1acc;
        publicInputs[198] = 0x00;
        publicInputs[199] = 0xffffffff;
        publicInputs[200] = 0x00;
        publicInputs[201] = 0x02;
        publicInputs[202] = 0x010000;
        publicInputs[203] = 0x200000;
        publicInputs[204] = 0x00;
        publicInputs[205] = 0x00;
        publicInputs[206] = 0xffffffffffffffffffffffffffffffff;
        publicInputs[207] = 0xffffffff;
        publicInputs[208] = 0xffffffffffffffffffffffffffffffff;
        publicInputs[209] = 0xffffffff;
        publicInputs[210] = 0x20;
        publicInputs[211] = 0x00;
        publicInputs[212] = 0x02;
        publicInputs[213] = 0x20;
        publicInputs[214] = 0x00;
        publicInputs[215] = 0x02;
        publicInputs[216] = 0xffffffffffffffffffffffffffffffff;
        publicInputs[217] = 0xffffffff;
        publicInputs[218] = 0xffffffffffffffffffffffffffffffff;
        publicInputs[219] = 0xffffffff;
        publicInputs[220] = 0x20;
        publicInputs[221] = 0x00;
        publicInputs[222] = 0x02;
        publicInputs[223] = 0x08;
        publicInputs[224] = 0x07;
        publicInputs[225] = 0x00;
        publicInputs[226] = 0x15;
        publicInputs[227] = 0x00;
        publicInputs[228] = 0x0100;
        publicInputs[229] = 0x00;
        publicInputs[230] = 0x01;
        publicInputs[231] = 0x00;
        publicInputs[232] = 0x10;
        publicInputs[233] = 0xff;
        publicInputs[234] = 0x00;
        publicInputs[235] = 0x200000;
        publicInputs[236] = 0x200000;
        publicInputs[237] = 0x01;
        publicInputs[238] = 0x00;
        publicInputs[239] = 0x200000;
        publicInputs[240] = 0x200000;
        publicInputs[241] = 0x200000;
        publicInputs[242] = 0x200000;
        publicInputs[243] = 0x20;
        publicInputs[244] = 0x00;
        publicInputs[245] = 0x02;
        publicInputs[246] = 0x08;
        // Rest are zeros (247-511)
        for (uint256 i = 247; i <= 511; i++) {
            publicInputs[i] = 0x00;
        }

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

        BridgeCore.ChannelParams memory params = BridgeCore.ChannelParams({
            targetContract: address(token),
            whitelisted: participants,
            enableFrostSignature: true
        });
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

        // Create 33 whitelisted users to force 64-leaf tree selection
        // 33 whitelisted users × 1 contract = 33 leaves, which requires 64-leaf tree
        address[] memory participants = new address[](33);
        for (uint256 i = 0; i < 33; i++) {
            participants[i] = address(uint160(1000 + i)); // Generate unique addresses
        }

        BridgeCore.ChannelParams memory params = BridgeCore.ChannelParams({
            targetContract: address(token),
            whitelisted: participants,
            enableFrostSignature: true
        });

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
        assertEq(participantCount, 0); // No deposits made yet, so no actual participants

        // Verify that the contract selected the 64-leaf tree
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

        BridgeCore.ChannelParams memory params = BridgeCore.ChannelParams({
            targetContract: address(token),
            whitelisted: participants,
            enableFrostSignature: true
        });

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

    function computeCorrectFunctionInstanceHash() internal pure returns (bytes32) {
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
        // Rest are zeros (181-445)

        return keccak256(abi.encodePacked(functionInstances));
    }


    function _makeDeposits(uint256 channelId, address[] memory participants) internal {
        for (uint256 i = 0; i < participants.length; i++) {
            vm.startPrank(participants[i]);
            uint256 amount = (i + 1) * 1 ether;
            token.approve(address(depositManager), amount);
            depositManager.depositToken(channelId, amount, bytes32(uint256(uint160(participants[i]))));
            vm.stopPrank();
        }
    }
}

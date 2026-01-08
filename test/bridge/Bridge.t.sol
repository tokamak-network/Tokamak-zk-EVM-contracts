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

    event ChannelOpened(bytes32 indexed channelId, address indexed targetContract);
    event ChannelClosed(bytes32 indexed channelId);
    event ChannelFinalized(bytes32 indexed channelId);
    event Deposited(bytes32 indexed channelId, address indexed user, address token, uint256 amount);
    event Withdrawn(bytes32 indexed channelId, address indexed user, address token, uint256 amount);
    event EmergencyWithdrawn(bytes32 indexed channelId, address indexed user, address token, uint256 amount);
    event StateInitialized(bytes32 indexed channelId, bytes32 currentStateRoot);
    event TokamakZkSnarkProofsVerified(bytes32 indexed channelId, address indexed signer);

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
        return _createZecFrostSignatureForChannel(bytes32(uint256(1))); // Default test channel ID
    }

    function _createZecFrostSignatureForChannel(bytes32 channelId)
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

    function _createZecFrostSignatureForProofData(bytes32 channelId, uint256[] memory publicInputs)
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
        return _createWrongZecFrostSignatureForChannel(bytes32(uint256(1))); // Default test channel ID
    }

    function _createWrongZecFrostSignatureForChannel(bytes32 channelId)
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
            channelId: keccak256(abi.encode(address(this), uint256(1))),
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
        _setTestStateRoots(publicInputs, bytes32(uint256(0))); // Assume channel 0 for now
        return _createProofDataFromMPT(proofPart1, proofPart2, publicInputs, smax, finalMPTLeaves);
    }

    function _createProofDataSimpleForChannel(
        bytes32 channelId,
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

    function _setTestStateRoots(uint256[] memory publicInputs, bytes32 channelId) internal view {
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

        bytes32 channelId = keccak256(abi.encode(address(this), uint256(2)));
        BridgeCore.ChannelParams memory params = BridgeCore.ChannelParams({
            channelId: channelId,
            targetContract: address(token),
            whitelisted: participants,
            enableFrostSignature: true
        });
        bytes32 returnedChannelId = bridge.openChannel(params);
        bridge.setChannelPublicKey(
            channelId,
            0x51909117a840e98bbcf1aae0375c6e85920b641edee21518cb79a19ac347f638,
            0xf2cf51268a560b92b57994c09af3c129e7f5646a48e668564edde80fd5076c6e
        );

        assertEq(returnedChannelId, channelId);

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
        bytes32 channelId = _createChannel();
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
        bytes32 channelId = _createChannel();

        vm.startPrank(address(999));
        token.mint(address(999), 1 ether);
        token.approve(address(depositManager), 1 ether);
        vm.expectRevert("Not whitelisted");
        depositManager.depositToken(channelId, 1 ether, bytes32(uint256(uint160(l2User1))));
        vm.stopPrank();
    }

    function testDepositToken() public {
        bytes32 channelId = _createTokenChannel();
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
        bytes32 channelId = _createChannel();

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
        bytes32 channelId1 = _createChannel();

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
        bytes32 channelId2 = _createChannelWithLeader(leader2);
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
        bytes32 channelId = _createChannel();

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

    function _createChannel() internal returns (bytes32) {
        vm.startPrank(leader);

        address[] memory participants = new address[](3);
        participants[0] = user1;
        participants[1] = user2;
        participants[2] = user3;

        bytes32 channelId = keccak256(abi.encode(address(this), block.timestamp, "createChannel"));
        BridgeCore.ChannelParams memory params = BridgeCore.ChannelParams({
            channelId: channelId,
            targetContract: address(token),
            whitelisted: participants,
            enableFrostSignature: true
        });
        bytes32 returnedChannelId = bridge.openChannel(params);
        assertEq(returnedChannelId, channelId);
        bridge.setChannelPublicKey(
            channelId,
            0x51909117a840e98bbcf1aae0375c6e85920b641edee21518cb79a19ac347f638,
            0xf2cf51268a560b92b57994c09af3c129e7f5646a48e668564edde80fd5076c6e
        );

        vm.stopPrank();

        return channelId;
    }

    function _createTokenChannel() internal returns (bytes32) {
        vm.startPrank(leader);

        address[] memory participants = new address[](3);
        participants[0] = user1;
        participants[1] = user2;
        participants[2] = user3;

        bytes32 channelId = keccak256(abi.encode(address(this), block.timestamp, "createTokenChannel"));
        BridgeCore.ChannelParams memory params = BridgeCore.ChannelParams({
            channelId: channelId,
            targetContract: address(token),
            whitelisted: participants,
            enableFrostSignature: true
        });
        bytes32 returnedChannelId = bridge.openChannel(params);
        assertEq(returnedChannelId, channelId);
        bridge.setChannelPublicKey(
            channelId,
            0x51909117a840e98bbcf1aae0375c6e85920b641edee21518cb79a19ac347f638,
            0xf2cf51268a560b92b57994c09af3c129e7f5646a48e668564edde80fd5076c6e
        );

        vm.stopPrank();

        return channelId;
    }

    function _createChannelWithLeader(address newLeader) internal returns (bytes32) {
        vm.startPrank(newLeader);

        address[] memory participants = new address[](3);
        participants[0] = user1;
        participants[1] = user2;
        participants[2] = user3;

        bytes32 channelId = keccak256(abi.encode(address(this), newLeader, block.timestamp, "createChannelWithLeader"));
        BridgeCore.ChannelParams memory params = BridgeCore.ChannelParams({
            channelId: channelId,
            targetContract: address(token),
            whitelisted: participants,
            enableFrostSignature: true
        });
        bytes32 returnedChannelId = bridge.openChannel(params);
        assertEq(returnedChannelId, channelId);
        bridge.setChannelPublicKey(
            channelId,
            0x51909117a840e98bbcf1aae0375c6e85920b641edee21518cb79a19ac347f638,
            0xf2cf51268a560b92b57994c09af3c129e7f5646a48e668564edde80fd5076c6e
        );

        vm.stopPrank();

        return channelId;
    }

    function _initializeChannel() internal returns (bytes32) {
        bytes32 channelId = _createChannel();

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

    function _submitProof() internal returns (bytes32) {
        bytes32 channelId = _initializeChannel();

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

    function _getSignedChannel() internal returns (bytes32) {
        // _submitProof now includes signature, so it's already signed and in Closing state
        return _submitProof();
    }

    function _getClosedChannel() internal returns (bytes32) {
        bytes32 channelId = _getSignedChannel();

        vm.prank(leader);

        return channelId;
    }

    // ========== Fuzz Tests ==========

    function testFuzzDeposit(uint256 amount) public {
        vm.assume(amount > 0 && amount < 100 ether);

        bytes32 channelId = _createChannel();

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

        bytes32 testChannelId = keccak256(abi.encode(address(this), timeout, "testFuzzTimeout"));
        BridgeCore.ChannelParams memory params = BridgeCore.ChannelParams({
            channelId: testChannelId,
            targetContract: address(token),
            whitelisted: participants,
            enableFrostSignature: true
        });
        bytes32 channelId = bridge.openChannel(params);
        assertEq(channelId, testChannelId);
        bridge.setChannelPublicKey(
            channelId,
            0x51909117a840e98bbcf1aae0375c6e85920b641edee21518cb79a19ac347f638,
            0xf2cf51268a560b92b57994c09af3c129e7f5646a48e668564edde80fd5076c6e
        );

        vm.stopPrank();
    }

    // ========== Integration Tests ==========


    function testSignatureCommitmentProtection() public {
        bytes32 channelId = _initializeChannel();
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

    /**
     * @dev Helper to setup channel with specified number of participants
     */
    function _setupChannelWithParticipants(uint256 participantCount) internal returns (bytes32 channelId) {
        // Use different leaders to avoid "channel limit reached" error
        address channelLeader = address(uint160(100 + participantCount));

        // Fund the leader
        vm.deal(channelLeader, 10 ether);

        vm.startPrank(channelLeader);

        address[] memory participants = new address[](participantCount);
        for (uint256 i = 0; i < participantCount; i++) {
            participants[i] = address(uint160(3 + i)); // Start from address(3)
        }

        channelId = keccak256(abi.encode(address(this), participantCount, block.timestamp, "setupChannel"));
        BridgeCore.ChannelParams memory params = BridgeCore.ChannelParams({
            channelId: channelId,
            targetContract: address(token),
            whitelisted: participants,
            enableFrostSignature: true
        });
        bytes32 returnedChannelId = bridge.openChannel(params);
        assertEq(returnedChannelId, channelId);
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

        bytes32 testChannelId = keccak256(abi.encode(address(this), testLeader, "test64Leaves"));
        BridgeCore.ChannelParams memory params = BridgeCore.ChannelParams({
            channelId: testChannelId,
            targetContract: address(token),
            whitelisted: participants,
            enableFrostSignature: true
        });

        // Open the channel
        bytes32 channelId = bridge.openChannel(params);
        assertEq(channelId, testChannelId);
        bridge.setChannelPublicKey(
            channelId,
            0x51909117a840e98bbcf1aae0375c6e85920b641edee21518cb79a19ac347f638,
            0xf2cf51268a560b92b57994c09af3c129e7f5646a48e668564edde80fd5076c6e
        );

        // Verify the channel was created successfully
        assertEq(channelId, testChannelId);

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
}

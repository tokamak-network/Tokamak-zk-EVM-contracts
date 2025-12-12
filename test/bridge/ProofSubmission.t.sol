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
    MockTokamakVerifier public tokamakVerifier;
    MockZecFrost public mockZecFrost;
    MockGroth16Verifier public groth16Verifier16;
    MockGroth16Verifier32 public groth16Verifier32;
    MockGroth16Verifier64 public groth16Verifier64;
    MockGroth16Verifier128 public groth16Verifier128;
    MockERC20 public token;

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

        // Register transfer function using 4-byte selector (standard format)
        bytes32 transferSig = bytes32(bytes4(keccak256("transfer(address,uint256)")));
        adminManager.registerFunction(address(token), transferSig, preprocessedPart1, preprocessedPart2, keccak256("test_instance_hash"));

        vm.stopPrank();
    }
}


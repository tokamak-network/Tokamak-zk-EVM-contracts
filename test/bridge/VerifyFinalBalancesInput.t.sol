// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import "forge-std/Test.sol";
import "../../src/BridgeProofManager.sol";
import "../../src/interface/IBridgeCore.sol";
import "../../src/interface/IGroth16Verifier16Leaves.sol";
import "../../src/interface/IGroth16Verifier32Leaves.sol";
import "../../src/interface/IGroth16Verifier64Leaves.sol";
import "../../src/interface/IGroth16Verifier128Leaves.sol";
import "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract MockGroth16Verifier16 is IGroth16Verifier16Leaves {
    function verifyProof(uint256[4] calldata, uint256[8] calldata, uint256[4] calldata, uint256[33] calldata)
        external
        pure
        override
        returns (bool)
    {
        return true;
    }
}

contract MockGroth16Verifier32 is IGroth16Verifier32Leaves {
    function verifyProof(uint256[4] calldata, uint256[8] calldata, uint256[4] calldata, uint256[65] calldata)
        external
        pure
        override
        returns (bool)
    {
        return true;
    }
}

contract MockGroth16Verifier64 is IGroth16Verifier64Leaves {
    function verifyProof(uint256[4] calldata, uint256[8] calldata, uint256[4] calldata, uint256[129] calldata)
        external
        pure
        override
        returns (bool)
    {
        return true;
    }
}

contract MockGroth16Verifier128 is IGroth16Verifier128Leaves {
    function verifyProof(uint256[4] calldata, uint256[8] calldata, uint256[4] calldata, uint256[257] calldata)
        external
        pure
        override
        returns (bool)
    {
        return true;
    }
}

contract MockBridgeCore {
    IBridgeCore.ChannelState public state;
    bool public frostEnabled;
    bool public signatureVerified;
    address[] public participants;
    uint256 public totalDeposits;
    bytes32 public finalStateRoot;
    uint256 public treeSize;
    address public targetContract;
    mapping(address => uint256) public l2MptKeys;

    function setConfig(
        IBridgeCore.ChannelState _state,
        bool _frostEnabled,
        bool _signatureVerified,
        address[] calldata _participants,
        uint256 _totalDeposits,
        bytes32 _finalStateRoot,
        uint256 _treeSize,
        address _targetContract
    ) external {
        state = _state;
        frostEnabled = _frostEnabled;
        signatureVerified = _signatureVerified;
        totalDeposits = _totalDeposits;
        finalStateRoot = _finalStateRoot;
        treeSize = _treeSize;
        targetContract = _targetContract;

        delete participants;
        for (uint256 i = 0; i < _participants.length; i++) {
            participants.push(_participants[i]);
        }
    }

    function setL2MptKey(address participant, uint256 key) external {
        l2MptKeys[participant] = key;
    }

    function getChannelState(bytes32) external view returns (IBridgeCore.ChannelState) {
        return state;
    }

    function isFrostSignatureEnabled(bytes32) external view returns (bool) {
        return frostEnabled;
    }

    function isSignatureVerified(bytes32) external view returns (bool) {
        return signatureVerified;
    }

    function getChannelParticipants(bytes32) external view returns (address[] memory) {
        return participants;
    }

    function getChannelTotalDeposits(bytes32) external view returns (uint256) {
        return totalDeposits;
    }

    function getChannelFinalStateRoot(bytes32) external view returns (bytes32) {
        return finalStateRoot;
    }

    function getChannelTreeSize(bytes32) external view returns (uint256) {
        return treeSize;
    }

    function getChannelTargetContract(bytes32) external view returns (address) {
        return targetContract;
    }

    function getPreAllocatedLeavesCount(address) external pure returns (uint256) {
        return 0;
    }

    function getPreAllocatedKeys(address) external pure returns (bytes32[] memory keys) {
        return new bytes32[](0);
    }

    function getPreAllocatedLeaf(address, bytes32) external pure returns (uint256 value, bool exists) {
        return (0, false);
    }

    function getL2MptKey(bytes32, address participant) external view returns (uint256) {
        return l2MptKeys[participant];
    }

    function setChannelWithdrawAmounts(bytes32, address[] memory, uint256[] memory) external {}

    function setChannelCloseTimestamp(bytes32, uint256) external {}

    function setChannelState(bytes32, IBridgeCore.ChannelState newState) external {
        state = newState;
    }
}

contract VerifyFinalBalancesInputTest is Test {
    BridgeProofManager private proofManager;
    MockBridgeCore private bridge;

    function setUp() public {
        bridge = new MockBridgeCore();
        MockGroth16Verifier16 verifier16 = new MockGroth16Verifier16();
        MockGroth16Verifier32 verifier32 = new MockGroth16Verifier32();
        MockGroth16Verifier64 verifier64 = new MockGroth16Verifier64();
        MockGroth16Verifier128 verifier128 = new MockGroth16Verifier128();

        BridgeProofManager implementation = new BridgeProofManager();
        address[4] memory groth16Verifiers =
            [address(verifier16), address(verifier32), address(verifier64), address(verifier128)];
        bytes memory initData = abi.encodeCall(
            BridgeProofManager.initialize, (address(bridge), address(0), address(0), groth16Verifiers, address(this))
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        proofManager = BridgeProofManager(address(proxy));

        address[] memory participants = new address[](6);
        participants[0] = address(0x1);
        participants[1] = address(0x2);
        participants[2] = address(0x3);
        participants[3] = address(0x4);
        participants[4] = address(0x5);
        participants[5] = address(0x6);

        bridge.setConfig(
            IBridgeCore.ChannelState.Closing,
            false,
            false,
            participants,
            90_000000000000000000,
            bytes32(uint256(0x1234)),
            16,
            address(0xBEEF)
        );
    }

    function testVerifyFinalBalancesGroth16WithProvidedInputs() public {
        bytes32 channelId = bytes32(uint256(42));

        uint256[] memory finalBalances = new uint256[](6);
        finalBalances[0] = 8_000000000000000000;
        finalBalances[1] = 21_000000000000000000;
        finalBalances[2] = 9_000000000000000000;
        finalBalances[3] = 18_000000000000000000;
        finalBalances[4] = 4_000000000000000000;
        finalBalances[5] = 30_000000000000000000;

        uint256[] memory permutation = new uint256[](6);
        permutation[0] = 3;
        permutation[1] = 1;
        permutation[2] = 2;
        permutation[3] = 5;
        permutation[4] = 4;
        permutation[5] = 0;

        BridgeProofManager.ChannelFinalizationProof memory proof = BridgeProofManager.ChannelFinalizationProof({
            pA: [
                uint256(25546506726576549862703313676415253466),
                uint256(65946752761513164061266583987877524705193624113638805923614457567397607972749),
                uint256(24675421685932766870833412730604877816),
                uint256(58772741817313822323502079494608416713920431158614398725016740819096558635401)
            ],
            pB: [
                uint256(31347278282182569007908832442228656946),
                uint256(12665697616816053464553685608559496052136261122222142867729314109943591015754),
                uint256(6051998485137480424856207640890397089),
                uint256(87617300905886048105866437119239048073159957382564843056571516236237121608608),
                uint256(10634102124677411946799263515026313413),
                uint256(64040208428763102104370976949313845538807892975225355818699706868960574854068),
                uint256(9790437446372267409736494228062217688),
                uint256(84718647226524725255019004369863264203108205468972348680699883185005433632338)
            ],
            pC: [
                uint256(5813280287475954323271733704717975580),
                uint256(23763792764603797328692382840135723114106796924529151365650978050209750609770),
                uint256(3178742565597861311701415040477857415),
                uint256(44332132520306597723180470057924869519466279516040935671669539451214623582779)
            ]
        });

        (bool ok, bytes memory data) = address(proofManager).call(
            abi.encodeCall(
                BridgeProofManager.verifyFinalBalancesGroth16, (channelId, finalBalances, permutation, proof)
            )
        );
        if (!ok) {
            revert(_decodeRevert(data));
        }
        assertEq(uint8(bridge.state()), uint8(IBridgeCore.ChannelState.Closed));
    }

    function _decodeRevert(bytes memory data) private pure returns (string memory) {
        if (data.length < 68) {
            return "verifyFinalBalancesGroth16 reverted";
        }
        bytes4 selector;
        assembly {
            selector := mload(add(data, 0x20))
        }
        if (selector == 0x08c379a0) {
            assembly {
                data := add(data, 0x04)
            }
            return abi.decode(data, (string));
        }
        return "verifyFinalBalancesGroth16 reverted (non-string)";
    }
}

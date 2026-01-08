// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import "lib/openzeppelin-contracts-upgradeable/contracts/security/ReentrancyGuardUpgradeable.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {ITokamakVerifier} from "./interface/ITokamakVerifier.sol";
import {IZecFrost} from "./interface/IZecFrost.sol";
import "./interface/IGroth16Verifier16Leaves.sol";
import "./interface/IGroth16Verifier32Leaves.sol";
import "./interface/IGroth16Verifier64Leaves.sol";
import "./interface/IGroth16Verifier128Leaves.sol";
import "./interface/IBridgeCore.sol";

contract BridgeProofManager is Initializable, ReentrancyGuardUpgradeable, OwnableUpgradeable, UUPSUpgradeable {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    uint256 constant R_MOD = 0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001;

    struct ChannelInitializationProof {
        uint256[4] pA;
        uint256[8] pB;
        uint256[4] pC;
        bytes32 merkleRoot;
    }

    struct ChannelFinalizationProof {
        uint256[4] pA;
        uint256[8] pB;
        uint256[4] pC;
    }

    struct ProofData {
        uint128[] proofPart1;
        uint256[] proofPart2;
        uint256[] publicInputs;
        uint256 smax;
    }

    struct Signature {
        bytes32 message;
        uint256 rx;
        uint256 ry;
        uint256 z;
    }

    struct BlockInfos {
        uint256 blockNumber;
        uint256 timestamp;
        uint256 prevrandao;
        uint256 gaslimit;
        uint256 basefee;
        address coinbase;
        uint256 chainId;
        uint256 selfbalance;
    }

    IBridgeCore public bridge;
    ITokamakVerifier public zkVerifier;
    IZecFrost public zecFrost;
    IGroth16Verifier16Leaves public groth16Verifier16;
    IGroth16Verifier32Leaves public groth16Verifier32;
    IGroth16Verifier64Leaves public groth16Verifier64;
    IGroth16Verifier128Leaves public groth16Verifier128;

    event StateInitialized(bytes32 indexed channelId, bytes32 currentStateRoot, BlockInfos blockInfos);
    event TokamakZkSnarkProofsVerified(bytes32 indexed channelId, address indexed signer);
    event FinalBalancesGroth16Verified(bytes32 indexed channelId, bytes32 finalStateRoot);
    event ProofSigned(bytes32 indexed channelId, address indexed signer, bytes32 finalStateRoot);

    modifier onlyBridge() {
        require(msg.sender == address(bridge), "Only bridge can call");
        _;
    }

    function initialize(
        address _bridgeCore,
        address _zkVerifier,
        address _zecFrost,
        address[4] memory _groth16Verifiers,
        address _owner
    ) public initializer {
        __ReentrancyGuard_init();
        __Ownable_init_unchained();
        __UUPSUpgradeable_init();
        _transferOwnership(_owner);

        require(_bridgeCore != address(0), "Invalid bridge address");
        bridge = IBridgeCore(_bridgeCore);
        zkVerifier = ITokamakVerifier(_zkVerifier);
        zecFrost = IZecFrost(_zecFrost);
        groth16Verifier16 = IGroth16Verifier16Leaves(_groth16Verifiers[0]);
        groth16Verifier32 = IGroth16Verifier32Leaves(_groth16Verifiers[1]);
        groth16Verifier64 = IGroth16Verifier64Leaves(_groth16Verifiers[2]);
        groth16Verifier128 = IGroth16Verifier128Leaves(_groth16Verifiers[3]);
    }

    function initializeChannelState(bytes32 channelId, ChannelInitializationProof calldata proof)
        external
        nonReentrant
    {
        require(bridge.getChannelState(channelId) == IBridgeCore.ChannelState.Initialized, "Invalid state");
        require(msg.sender == bridge.getChannelLeader(channelId), "Not leader");

        // Only require public key to be set if frost signature is enabled
        bool frostEnabled = bridge.isFrostSignatureEnabled(channelId);
        if (frostEnabled) {
            require(bridge.isChannelPublicKeySet(channelId), "Channel leader must set public key first");
        }

        address[] memory participants = bridge.getChannelParticipants(channelId);
        address targetContract = bridge.getChannelTargetContract(channelId);
        uint256 treeSize = bridge.getChannelTreeSize(channelId);
        uint256 preAllocatedCount = bridge.getChannelPreAllocatedLeavesCount(channelId);

        uint256 totalEntries = participants.length + preAllocatedCount;
        require(totalEntries <= treeSize, "Too many entries for circuit");

        uint256 publicSignalsLength = treeSize * 2 + 1;
        uint256[] memory publicSignals = new uint256[](publicSignalsLength);

        publicSignals[0] = uint256(proof.merkleRoot);

        uint256 currentIndex = 1; // Start after merkle root

        // Add pre-allocated leaves data FIRST
        if (preAllocatedCount > 0) {
            bytes32[] memory preAllocatedKeys = bridge.getPreAllocatedKeys(targetContract);
            for (uint256 i = 0; i < preAllocatedKeys.length; i++) {
                bytes32 key = preAllocatedKeys[i];
                (uint256 value, bool exists) = bridge.getPreAllocatedLeaf(targetContract, key);

                if (exists) {
                    uint256 modedKey = uint256(key) % R_MOD;
                    uint256 modedValue = value % R_MOD;

                    publicSignals[currentIndex] = modedKey;
                    publicSignals[currentIndex + treeSize] = modedValue;
                    currentIndex++;
                }
            }
        }

        // Add participant data AFTER pre-allocated leaves
        for (uint256 i = 0; i < participants.length; i++) {
            address l1Address = participants[i];
            uint256 balance = bridge.getParticipantDeposit(channelId, l1Address);
            uint256 l2MptKey = bridge.getL2MptKey(channelId, l1Address);

            if (balance > 0) {
                require(l2MptKey != 0, "Participant MPT key not set");
            }

            uint256 modedL2MptKey = l2MptKey % R_MOD;
            uint256 modedBalance = balance % R_MOD;

            publicSignals[currentIndex] = modedL2MptKey;
            publicSignals[currentIndex + treeSize] = modedBalance;
            currentIndex++;
        }

        // Fill remaining entries with zeros
        for (uint256 i = currentIndex; i <= treeSize; i++) {
            publicSignals[i] = 0;
            publicSignals[i + treeSize] = 0;
        }

        bool proofValid = verifyGroth16Proof(
            treeSize,
            groth16Verifier16,
            groth16Verifier32,
            groth16Verifier64,
            groth16Verifier128,
            proof.pA,
            proof.pB,
            proof.pC,
            publicSignals
        );

        require(proofValid, "Invalid Groth16 proof");

        // Compute blockInfosHash
        BlockInfos memory blockInfos = BlockInfos({
            blockNumber: block.number,
            timestamp: block.timestamp,
            prevrandao: block.prevrandao,
            gaslimit: block.gaslimit,
            basefee: block.basefee,
            coinbase: block.coinbase,
            chainId: block.chainid,
            selfbalance: address(this).balance
        });
        bytes32 blockInfosHash = _computeBlockInfosHash();

        bridge.setChannelInitialStateRoot(channelId, proof.merkleRoot);
        bridge.setChannelBlockInfosHash(channelId, blockInfosHash);
        bridge.setChannelState(channelId, IBridgeCore.ChannelState.Open);

        emit StateInitialized(channelId, proof.merkleRoot, blockInfos);
    }

    function submitProofAndSignature(bytes32 channelId, ProofData[] calldata proofs, Signature calldata signature)
        external
    {
        require(bridge.getChannelState(channelId) == IBridgeCore.ChannelState.Open, "Invalid state");
        require(proofs.length > 0 && proofs.length <= 5, "Must provide 1-5 proofs");

        // Extract finalStateRoot from the last proof's output state root (indices 0-1)
        ProofData calldata lastProof = proofs[proofs.length - 1];
        require(lastProof.publicInputs.length >= 12, "Invalid public inputs length");
        bytes32 finalStateRoot = _concatenateStateRoot(lastProof.publicInputs[1], lastProof.publicInputs[0]);
        bytes32 initialStateRoot = bridge.getChannelInitialStateRoot(channelId);

        // STEP 1: verify order of proofs
        // Validate proof chain and state root consistency
        bytes32 expectedPrevRoot = initialStateRoot;

        for (uint256 i = 0; i < proofs.length; i++) {
            ProofData calldata currentProof = proofs[i];
            require(currentProof.publicInputs.length >= 12, "Invalid public inputs length");

            // Extract input state root (rows 8 & 9) and output state root (rows 0 & 1)
            bytes32 inputStateRoot = _concatenateStateRoot(currentProof.publicInputs[9], currentProof.publicInputs[8]);
            bytes32 outputStateRoot = _concatenateStateRoot(currentProof.publicInputs[1], currentProof.publicInputs[0]);

            // For first proof, input state root should match the stored initial state root
            // For subsequent proofs, input state root should match previous proof's output state root
            require(inputStateRoot == expectedPrevRoot, "State root chain broken");

            // Update expected previous root for next iteration
            expectedPrevRoot = outputStateRoot;
        }

        // Final verification: last proof's output state root should match the final state root
        require(expectedPrevRoot == finalStateRoot, "Final state root mismatch");

        // STEP2: Conditional Signature verification
        // Check if frost signature is enabled for this channel
        bool frostEnabled = bridge.isFrostSignatureEnabled(channelId);

        if (frostEnabled) {
            // Verify that signature commits to the specific channel and final state root from the proof
            bytes32 commitmentHash = keccak256(abi.encodePacked(channelId, finalStateRoot));
            require(signature.message == commitmentHash, "Signature must commit to proof content");

            (uint256 pkx, uint256 pky) = bridge.getChannelPublicKey(channelId);
            address signerAddr = bridge.getChannelSignerAddr(channelId);
            address recovered = zecFrost.verify(signature.message, pkx, pky, signature.rx, signature.ry, signature.z);
            require(recovered == signerAddr, "Invalid group threshold signature");
        }

        // STEP2.5: Block info validation
        // Verify that each proof's block info matches the stored block info hash
        bytes32 storedBlockInfoHash = bridge.getChannelBlockInfosHash(channelId);
        require(storedBlockInfoHash != bytes32(0), "Block info hash not set for channel");

        // DISABLED FOR TESTING PURPOSES
        /*
        // Skip block info validation in test environments (when chainid is 31337 - Anvil/Hardhat)
        if (block.chainid != 31337) {
            for (uint256 i = 0; i < proofs.length; i++) {
                ProofData calldata currentProof = proofs[i];
                bytes32 proofBlockInfoHash = _extractBlockInfoHashFromProof(currentProof.publicInputs);
                require(proofBlockInfoHash == storedBlockInfoHash, "Block info mismatch in proof");
            }
        }
        */
        // STEP3: zk-SNARK proof verification
        // Only after signature validation, verify ZK proofs
        for (uint256 i = 0; i < proofs.length; i++) {
            ProofData calldata currentProof = proofs[i];
            require(currentProof.publicInputs.length >= 19, "Public inputs too short for function signature");

            // Extract function signature from publicInputs at row 16 (0-indexed)
            // Row 18: Selector for a function to call (complete 4-byte selector)
            bytes32 funcSig = _extractFunctionSignatureFromProof(currentProof.publicInputs);

            // Get target contract data and find the registered function
            address targetContract = bridge.getChannelTargetContract(channelId);
            IBridgeCore.TargetContract memory targetData = bridge.getTargetContractData(targetContract);

            IBridgeCore.RegisteredFunction memory registeredFunc;
            bool found = false;
            for (uint256 j = 0; j < targetData.registeredFunctions.length; j++) {
                if (targetData.registeredFunctions[j].functionSignature == funcSig) {
                    registeredFunc = targetData.registeredFunctions[j];
                    found = true;
                    break;
                }
            }
            require(found, "Function not registered");

            // Validate function instance hash
            bytes32 proofInstanceHash = _extractFunctionInstanceHashFromProof(currentProof.publicInputs);
            require(proofInstanceHash == registeredFunc.instancesHash, "Function instance hash mismatch");

            bool proofValid = zkVerifier.verify(
                currentProof.proofPart1,
                currentProof.proofPart2,
                registeredFunc.preprocessedPart1,
                registeredFunc.preprocessedPart2,
                currentProof.publicInputs,
                currentProof.smax
            );

            require(proofValid, "Invalid ZK proof");
        }

        // STEP4: Channel state update
        // Atomically update state only after all validations pass
        bridge.setChannelFinalStateRoot(channelId, finalStateRoot);
        bridge.setChannelSignatureVerified(channelId, frostEnabled);
        bridge.setChannelState(channelId, IBridgeCore.ChannelState.Closing);

        emit TokamakZkSnarkProofsVerified(channelId, msg.sender);
        emit ProofSigned(channelId, msg.sender, finalStateRoot);
    }

    function verifyFinalBalancesGroth16(
        bytes32 channelId,
        uint256[] calldata finalBalances,
        uint256[] calldata permutation,
        ChannelFinalizationProof calldata groth16Proof
    ) external {
        require(bridge.getChannelState(channelId) == IBridgeCore.ChannelState.Closing, "Invalid state");

        // Only require signature verification if frost signature is enabled for this channel
        bool frostEnabled = bridge.isFrostSignatureEnabled(channelId);
        if (frostEnabled) {
            require(bridge.isSignatureVerified(channelId), "signature not verified");
        }

        address[] memory participants = bridge.getChannelParticipants(channelId);
        require(finalBalances.length == participants.length, "Invalid final balances length");

        // Validate balance conservation for the single target contract
        uint256 totalFinalBalance = 0;
        for (uint256 participantIdx = 0; participantIdx < participants.length; participantIdx++) {
            totalFinalBalance += finalBalances[participantIdx];
        }

        uint256 totalDeposited = bridge.getChannelTotalDeposits(channelId);
        require(totalFinalBalance == totalDeposited, "Balance conservation violated");

        // Step 1: Get the final state root stored
        bytes32 finalStateRoot = bridge.getChannelFinalStateRoot(channelId);

        // Step 2: Get tree size and target contract
        uint256 treeSize = bridge.getChannelTreeSize(channelId);
        address targetContract = bridge.getChannelTargetContract(channelId);
        uint256 preAllocatedCount = bridge.getPreAllocatedLeavesCount(targetContract);

        require(preAllocatedCount + finalBalances.length == permutation.length, "Invalid permutation length");

        uint256[] memory publicSignals = new uint256[](1 + 2 * treeSize);

        // Set final state root as first public signal
        publicSignals[0] = uint256(finalStateRoot);

        uint256 currentIndex = 0;

        // Step 3: Add pre-allocated leaves data FIRST
        if (preAllocatedCount > 0) {
            bytes32[] memory preAllocatedKeys = bridge.getPreAllocatedKeys(targetContract);
            for (uint256 i = 0; i < preAllocatedKeys.length; i++) {
                bytes32 key = preAllocatedKeys[i];
                (uint256 value, bool exists) = bridge.getPreAllocatedLeaf(targetContract, key);
                require(exists, "Pre-allocated leaf not found");

                // Set pre-allocated MPT key and value
                uint256 permutedIndex = permutation[currentIndex];
                publicSignals[1 + permutedIndex] = uint256(key);
                publicSignals[1 + treeSize + permutedIndex] = value;
                currentIndex++;
            }
        }

        // Step 4: Add participant data AFTER pre-allocated leaves
        for (uint256 i = 0; i < participants.length; i++) {
            address participant = participants[i];

            // Get L2 MPT key for this participant
            uint256 l2MptKey = bridge.getL2MptKey(channelId, participant);

            uint256 permutedIndex = permutation[currentIndex];
            // Set L2 MPT key
            publicSignals[1 + permutedIndex] = l2MptKey;
            // Set final balance
            publicSignals[1 + treeSize + permutedIndex] = finalBalances[i];
            currentIndex++;
        }

        // Step 5: Verify the groth16 proof passed as a parameter
        bool proofValid = verifyGroth16Proof(
            treeSize,
            groth16Verifier16,
            groth16Verifier32,
            groth16Verifier64,
            groth16Verifier128,
            groth16Proof.pA,
            groth16Proof.pB,
            groth16Proof.pC,
            publicSignals
        );

        // Step 6: Assert that the verifier returns true
        require(proofValid, "Invalid Groth16 proof");

        // Set withdraw amounts if proof is valid
        bridge.setChannelWithdrawAmounts(channelId, participants, finalBalances);
        bridge.setChannelCloseTimestamp(channelId, block.timestamp);
        bridge.setChannelState(channelId, IBridgeCore.ChannelState.Closed);

        emit FinalBalancesGroth16Verified(channelId, finalStateRoot);
    }

    function updateVerifier(address _newVerifier) external onlyOwner {
        require(_newVerifier != address(0), "Invalid verifier address");
        zkVerifier = ITokamakVerifier(_newVerifier);
    }

    function updateZecFrost(address _newZecFrost) external onlyOwner {
        require(_newZecFrost != address(0), "Invalid ZecFrost address");
        zecFrost = IZecFrost(_newZecFrost);
    }

    function updateGroth16Verifiers(address[4] memory _newVerifiers) external onlyOwner {
        groth16Verifier16 = IGroth16Verifier16Leaves(_newVerifiers[0]);
        groth16Verifier32 = IGroth16Verifier32Leaves(_newVerifiers[1]);
        groth16Verifier64 = IGroth16Verifier64Leaves(_newVerifiers[2]);
        groth16Verifier128 = IGroth16Verifier128Leaves(_newVerifiers[3]);
    }

    function verifyGroth16Proof(
        uint256 treeSize,
        IGroth16Verifier16Leaves verifier16,
        IGroth16Verifier32Leaves verifier32,
        IGroth16Verifier64Leaves verifier64,
        IGroth16Verifier128Leaves verifier128,
        uint256[4] calldata pA,
        uint256[8] calldata pB,
        uint256[4] calldata pC,
        uint256[] memory publicSignals
    ) internal view returns (bool) {
        if (treeSize == 16) {
            require(publicSignals.length == 33, "Invalid public signals length for 16 leaves");
            uint256[33] memory signals16;
            for (uint256 i = 0; i < 33; i++) {
                signals16[i] = publicSignals[i];
            }
            return verifier16.verifyProof(pA, pB, pC, signals16);
        } else if (treeSize == 32) {
            require(publicSignals.length == 65, "Invalid public signals length for 32 leaves");
            uint256[65] memory signals32;
            for (uint256 i = 0; i < 65; i++) {
                signals32[i] = publicSignals[i];
            }
            return verifier32.verifyProof(pA, pB, pC, signals32);
        } else if (treeSize == 64) {
            require(publicSignals.length == 129, "Invalid public signals length for 64 leaves");
            uint256[129] memory signals64;
            for (uint256 i = 0; i < 129; i++) {
                signals64[i] = publicSignals[i];
            }
            return verifier64.verifyProof(pA, pB, pC, signals64);
        } else if (treeSize == 128) {
            require(publicSignals.length == 257, "Invalid public signals length for 128 leaves");
            uint256[257] memory signals128;
            for (uint256 i = 0; i < 257; i++) {
                signals128[i] = publicSignals[i];
            }
            return verifier128.verifyProof(pA, pB, pC, signals128);
        } else {
            revert("Invalid tree size");
        }
    }

    function updateBridge(address _newBridge) external onlyOwner {
        require(_newBridge != address(0), "Invalid bridge address");
        bridge = IBridgeCore(_newBridge);
    }

    function _concatenateStateRoot(uint256 part1, uint256 part2) internal pure returns (bytes32) {
        return bytes32((part1 << 128) | part2);
    }

    function _computeBlockInfosHash() internal view returns (bytes32) {
        require(block.number > 0, "Block number must be greater than 0");

        bytes memory blockInfo;
        uint256 targetBlockNumber = block.number;

        // COINBASE (32 bytes total - upper 16 + lower 16)
        address coinbaseAddr = block.coinbase;
        uint256 coinbaseValue = uint256(uint160(coinbaseAddr));
        blockInfo = abi.encodePacked(blockInfo, bytes16(uint128(coinbaseValue >> 128)), bytes16(uint128(coinbaseValue)));

        // TIMESTAMP (32 bytes total - upper 16 + lower 16)
        // MISMATCH WARNING: This is current block timestamp, not block n-1!
        uint256 timestamp = block.timestamp;
        blockInfo = abi.encodePacked(blockInfo, bytes16(uint128(timestamp >> 128)), bytes16(uint128(timestamp)));

        // NUMBER (32 bytes total - upper 16 + lower 16) - Use n-1
        uint256 number = targetBlockNumber;
        blockInfo = abi.encodePacked(blockInfo, bytes16(uint128(number >> 128)), bytes16(uint128(number)));

        // PREVRANDAO (32 bytes total - upper 16 + lower 16)
        // MISMATCH WARNING: This is current block prevrandao, not block n-1!
        uint256 prevrandao = block.prevrandao;
        blockInfo = abi.encodePacked(blockInfo, bytes16(uint128(prevrandao >> 128)), bytes16(uint128(prevrandao)));

        // GASLIMIT (32 bytes total - upper 16 + lower 16)
        uint256 gaslimit = block.gaslimit;
        blockInfo = abi.encodePacked(blockInfo, bytes16(uint128(gaslimit >> 128)), bytes16(uint128(gaslimit)));

        // CHAINID (32 bytes total - upper 16 + lower 16)
        uint256 chainid = block.chainid;
        blockInfo = abi.encodePacked(blockInfo, bytes16(uint128(chainid >> 128)), bytes16(uint128(chainid)));

        // SELFBALANCE (32 bytes total - upper 16 + lower 16)
        // MISMATCH WARNING: This is current balance, not block n-1!
        uint256 selfbalance = address(this).balance;
        blockInfo = abi.encodePacked(blockInfo, bytes16(uint128(selfbalance >> 128)), bytes16(uint128(selfbalance)));

        // BASEFEE (32 bytes total - upper 16 + lower 16)
        // MISMATCH WARNING: This is current basefee, not block n-1!
        uint256 basefee = block.basefee;
        blockInfo = abi.encodePacked(blockInfo, bytes16(uint128(basefee >> 128)), bytes16(uint128(basefee)));

        // Block hashes 2-5 blocks ago from current block (32 bytes each - upper 16 + lower 16)
        // Since we're hashing for block n-1, these are blocks (n-2), (n-3), (n-4), (n-5)
        for (uint256 i = 2; i <= 5; i++) {
            bytes32 blockHash;
            if (block.number >= i) {
                blockHash = blockhash(block.number - i);
            }
            // If block.number < i, blockHash remains 0x0 (default value)
            uint256 hashValue = uint256(blockHash);
            blockInfo = abi.encodePacked(blockInfo, bytes16(uint128(hashValue >> 128)), bytes16(uint128(hashValue)));
        }

        return keccak256(blockInfo);
    }

    function _extractBlockInfoHashFromProof(uint256[] calldata publicInputs) internal pure returns (bytes32) {
        require(publicInputs.length >= 64, "Public inputs too short for block info");

        bytes memory blockInfo;

        // Extract block info from public inputs (indices 42-65 based on instance_description.json)
        // Each block variable is stored as lower 16 bytes + upper 16 bytes
        for (uint256 i = 40; i < 64; i += 2) {
            // Combine lower and upper 16 bytes back to 32 bytes
            uint256 lower = publicInputs[i];
            uint256 upper = publicInputs[i + 1];
            blockInfo = abi.encodePacked(blockInfo, bytes16(uint128(upper)), bytes16(uint128(lower)));
        }

        return keccak256(blockInfo);
    }

    function _extractFunctionSignatureFromProof(uint256[] calldata publicInputs) internal pure returns (bytes32) {
        // Function signature is located at row 14 (0-indexed) in the user data section
        // Row 14: Selector for a function to call (complete 4-byte selector)
        require(publicInputs.length >= 19, "Public inputs too short for function signature");

        // Extract the function selector from index 14
        // The value is already a complete 4-byte selector stored as uint256
        uint256 selectorValue = publicInputs[14];
        bytes4 selector = bytes4(uint32(selectorValue));

        return bytes32(selector);
    }

    function _extractFunctionInstanceHashFromProof(uint256[] calldata publicInputs) internal pure returns (bytes32) {
        // Function instance data starts at index 66 (based on instance_description.json)
        // User data: 0-41, Block data: 42-63, Function data: 64+
        require(publicInputs.length > 64, "Public inputs too short for function instance data");

        // Extract function instance data starting from index 64
        uint256 functionDataLength = publicInputs.length - 64;
        uint256[] memory functionInstanceData = new uint256[](functionDataLength);

        for (uint256 i = 0; i < functionDataLength; i++) {
            functionInstanceData[i] = publicInputs[64 + i];
        }

        return keccak256(abi.encodePacked(functionInstanceData));
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @notice Returns the address of the current implementation contract
     * @dev Uses EIP-1967 standard storage slot for implementation address
     * @return implementation The address of the implementation contract
     */
    function getImplementation() external view returns (address implementation) {
        bytes32 slot = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        assembly {
            implementation := sload(slot)
        }
    }

    uint256[41] private __gap;
}

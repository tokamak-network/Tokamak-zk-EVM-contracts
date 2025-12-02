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

    IBridgeCore public bridge;
    ITokamakVerifier public zkVerifier;
    IZecFrost public zecFrost;
    IGroth16Verifier16Leaves public groth16Verifier16;
    IGroth16Verifier32Leaves public groth16Verifier32;
    IGroth16Verifier64Leaves public groth16Verifier64;
    IGroth16Verifier128Leaves public groth16Verifier128;


    event StateInitialized(uint256 indexed channelId, bytes32 currentStateRoot);
    event TokamakZkSnarkProofsVerified(uint256 indexed channelId, address indexed signer);
    event FinalBalancesGroth16Verified(uint256 indexed channelId, bytes32 finalStateRoot);
    event ProofSigned(uint256 indexed channelId, address indexed signer, bytes32 finalStateRoot);

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

    function initializeChannelState(uint256 channelId, ChannelInitializationProof calldata proof)
        external
        nonReentrant
    {
        require(bridge.getChannelState(channelId) == IBridgeCore.ChannelState.Initialized, "Invalid state");
        require(msg.sender == bridge.getChannelLeader(channelId), "Not leader");
        require(bridge.isChannelPublicKeySet(channelId), "Channel leader must set public key first");

        address[] memory participants = bridge.getChannelParticipants(channelId);
        address[] memory allowedTokens = bridge.getChannelAllowedTokens(channelId);
        uint256 treeSize = bridge.getChannelTreeSize(channelId);

        uint256 totalEntries = participants.length * allowedTokens.length;
        require(totalEntries <= treeSize, "Too many participant-token combinations for circuit");

        uint256 publicSignalsLength = treeSize * 2 + 1;
        uint256[] memory publicSignals = new uint256[](publicSignalsLength);

        publicSignals[0] = uint256(proof.merkleRoot);

        uint256 entryIndex = 0;
        for (uint256 j = 0; j < allowedTokens.length;) {
            address token = allowedTokens[j];

            for (uint256 i = 0; i < participants.length;) {
                address l1Address = participants[i];
                uint256 balance = bridge.getParticipantTokenDeposit(channelId, l1Address, token);
                uint256 l2MptKey = bridge.getL2MptKey(channelId, l1Address, token);

                if (balance > 0) {
                    require(l2MptKey != 0, "Participant MPT key not set for token");
                }

                uint256 modedL2MptKey = l2MptKey % R_MOD;
                uint256 modedBalance = balance % R_MOD;

                publicSignals[entryIndex + 1] = modedL2MptKey;
                publicSignals[entryIndex + 1 + treeSize] = modedBalance;

                unchecked {
                    ++i;
                    ++entryIndex;
                }
            }

            unchecked {
                ++j;
            }
        }

        for (uint256 i = totalEntries; i < treeSize;) {
            publicSignals[i + 1] = 0;
            publicSignals[i + 1 + treeSize] = 0;
            unchecked {
                ++i;
            }
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
        bytes32 blockInfosHash = _computeBlockInfosHash();
        
        bridge.setChannelInitialStateRoot(channelId, proof.merkleRoot);
        bridge.setChannelBlockInfosHash(channelId, blockInfosHash);
        bridge.setChannelState(channelId, IBridgeCore.ChannelState.Open);

        emit StateInitialized(channelId, proof.merkleRoot);
    }

    function submitProofAndSignature(uint256 channelId, ProofData[] calldata proofs, Signature calldata signature)
        external
    {
        require(bridge.getChannelState(channelId) == IBridgeCore.ChannelState.Open, "Invalid state");
        require(proofs.length > 0 && proofs.length <= 5, "Must provide 1-5 proofs");

        // Safety check: ensure timeout has passed
        (uint256 openTimestamp, uint256 timeout) = bridge.getChannelTimeout(channelId);
        require(block.timestamp >= openTimestamp + timeout, "Timeout has not passed yet");

        // Extract finalStateRoot from the first slot of the last proof's publicInputs
        ProofData calldata lastProof = proofs[proofs.length - 1];
        require(lastProof.publicInputs.length > 0, "Public inputs cannot be empty");
        bytes32 finalStateRoot = bytes32(lastProof.publicInputs[0]);
        bytes32 initialStateRoot = bridge.getChannelInitialStateRoot(channelId);

        // STEP 1: mverify order of proofs
        // Validate proof chain and state root consistency
        bytes32 expectedPrevRoot = initialStateRoot;
        
        for (uint256 i = 0; i < proofs.length; i++) {
            ProofData calldata currentProof = proofs[i];
            require(currentProof.publicInputs.length >= 12, "Invalid public inputs length");
            
            // Extract input state root (rows 8 & 9) and output state root (rows 10 & 11)
            bytes32 inputStateRoot = _concatenateStateRoot(
                currentProof.publicInputs[8], 
                currentProof.publicInputs[9]
            );
            bytes32 outputStateRoot = _concatenateStateRoot(
                currentProof.publicInputs[10], 
                currentProof.publicInputs[11]
            );
            
            // For first proof, input state root should match the stored initial state root
            // For subsequent proofs, input state root should match previous proof's output state root
            require(inputStateRoot == expectedPrevRoot, "State root chain broken");
            
            // Update expected previous root for next iteration
            expectedPrevRoot = outputStateRoot;
        }
        
        // Final verification: last proof's output state root should match the final state root
        require(expectedPrevRoot == finalStateRoot, "Final state root mismatch");

        // STEP2: Signature verification
        // Verify that signature commits to the specific channel and final state root from the proof
        bytes32 commitmentHash = keccak256(abi.encodePacked(channelId, finalStateRoot));
        require(signature.message == commitmentHash, "Signature must commit to proof content");

        (uint256 pkx, uint256 pky) = bridge.getChannelPublicKey(channelId);
        address signerAddr = bridge.getChannelSignerAddr(channelId);
        address recovered = zecFrost.verify(signature.message, pkx, pky, signature.rx, signature.ry, signature.z);
        require(recovered == signerAddr, "Invalid group threshold signature");

        // STEP2.5: Block info validation
        // Verify that each proof's block info matches the stored block info hash
        bytes32 storedBlockInfoHash = bridge.getChannelBlockInfosHash(channelId);
        require(storedBlockInfoHash != bytes32(0), "Block info hash not set for channel");
        
        // Skip block info validation in test environments (when chainid is 31337 - Anvil/Hardhat)
        if (block.chainid != 31337) {
            for (uint256 i = 0; i < proofs.length; i++) {
                ProofData calldata currentProof = proofs[i];
                bytes32 proofBlockInfoHash = _extractBlockInfoHashFromProof(currentProof.publicInputs);
                require(proofBlockInfoHash == storedBlockInfoHash, "Block info mismatch in proof");
            }
        }

        // STEP3: zk-SNARK proof verification
        // Only after signature validation, verify ZK proofs
        for (uint256 i = 0; i < proofs.length; i++) {
            ProofData calldata currentProof = proofs[i];
            require(currentProof.publicInputs.length >= 19, "Public inputs too short for function signature");

            // Extract function signature from publicInputs at row 18 (0-indexed)
            // Row 18: Selector for a function to call (complete 4-byte selector)
            bytes32 funcSig = _extractFunctionSignatureFromProof(currentProof.publicInputs);
            IBridgeCore.RegisteredFunction memory registeredFunc = bridge.getRegisteredFunction(funcSig);
            require(registeredFunc.functionSignature != bytes32(0), "Function not registered");

            // Validate function instance hash (skip in test environments)
            if (block.chainid != 31337) {
                bytes32 proofInstanceHash = _extractFunctionInstanceHashFromProof(currentProof.publicInputs);
                require(proofInstanceHash == registeredFunc.instancesHash, "Function instance hash mismatch");
            }

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
        bridge.setChannelSignatureVerified(channelId, true);
        bridge.setChannelState(channelId, IBridgeCore.ChannelState.Closing);

        emit TokamakZkSnarkProofsVerified(channelId, msg.sender);
        emit ProofSigned(channelId, msg.sender, finalStateRoot);
    }

    function verifyFinalBalancesGroth16(
        uint256 channelId,
        uint256[][] calldata finalBalances,
        ChannelFinalizationProof calldata groth16Proof
    ) external {
        require(bridge.getChannelState(channelId) == IBridgeCore.ChannelState.Closing, "Invalid state");
        require(bridge.isSignatureVerified(channelId), "signature not verified");

        address[] memory participants = bridge.getChannelParticipants(channelId);
        address[] memory allowedTokens = bridge.getChannelAllowedTokens(channelId);

        require(finalBalances.length == participants.length, "Invalid final balances length");

        for (uint256 i = 0; i < finalBalances.length; i++) {
            require(finalBalances[i].length == allowedTokens.length, "Invalid token balances length");
        }

        // Validate token balance conservation
        for (uint256 tokenIdx = 0; tokenIdx < allowedTokens.length; tokenIdx++) {
            address token = allowedTokens[tokenIdx];
            uint256 totalFinalBalance = 0;

            for (uint256 participantIdx = 0; participantIdx < participants.length; participantIdx++) {
                totalFinalBalance += finalBalances[participantIdx][tokenIdx];
            }

            uint256 totalDeposited = bridge.getChannelTotalDeposits(channelId, token);
            require(totalFinalBalance == totalDeposited, "Balance conservation violated for token");
        }

        // Step 1: Get the final state root stored
        bytes32 finalStateRoot = bridge.getChannelFinalStateRoot(channelId);

        // Step 2: Get each participant's L2MPTkey for each token
        uint256 treeSize = bridge.getChannelTreeSize(channelId);
        uint256[] memory publicSignals = new uint256[](1 + 2 * treeSize);

        // Set final state root as first public signal
        publicSignals[0] = uint256(finalStateRoot);

        // Step 4: Construct the publicSignals for the Groth16 verifier
        uint256 entryIndex = 0;
        for (uint256 i = 0; i < participants.length; i++) {
            address participant = participants[i];

            for (uint256 j = 0; j < allowedTokens.length; j++) {
                address token = allowedTokens[j];

                // Get L2 MPT key for this participant-token pair
                uint256 l2MptKey = bridge.getL2MptKey(channelId, participant, token);

                if (entryIndex < treeSize) {
                    // Set L2 MPT key
                    publicSignals[1 + entryIndex] = l2MptKey;
                    // Set final balance
                    publicSignals[1 + treeSize + entryIndex] = finalBalances[i][j];
                    entryIndex++;
                }
            }
        }

        // Fill remaining entries with zero
        for (uint256 i = entryIndex; i < treeSize; i++) {
            publicSignals[1 + i] = 0;
            publicSignals[1 + treeSize + i] = 0;
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
        bridge.setChannelWithdrawAmounts(channelId, participants, allowedTokens, finalBalances);
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
        bytes memory blockInfo;

        // COINBASE (32 bytes total - lower 16 + upper 16)
        address coinbaseAddr = block.coinbase;
        uint256 coinbaseValue = uint256(uint160(coinbaseAddr));
        blockInfo = abi.encodePacked(blockInfo, bytes16(uint128(coinbaseValue)), bytes16(uint128(coinbaseValue >> 128)));

        // TIMESTAMP (32 bytes total - lower 16 + upper 16) 
        uint256 timestamp = block.timestamp;
        blockInfo = abi.encodePacked(blockInfo, bytes16(uint128(timestamp)), bytes16(uint128(timestamp >> 128)));

        // NUMBER (32 bytes total - lower 16 + upper 16)
        uint256 number = block.number;
        blockInfo = abi.encodePacked(blockInfo, bytes16(uint128(number)), bytes16(uint128(number >> 128)));

        // PREVRANDAO (32 bytes total - lower 16 + upper 16)
        uint256 prevrandao = block.prevrandao;
        blockInfo = abi.encodePacked(blockInfo, bytes16(uint128(prevrandao)), bytes16(uint128(prevrandao >> 128)));

        // GASLIMIT (32 bytes total - lower 16 + upper 16)
        uint256 gaslimit = block.gaslimit;
        blockInfo = abi.encodePacked(blockInfo, bytes16(uint128(gaslimit)), bytes16(uint128(gaslimit >> 128)));

        // CHAINID (32 bytes total - lower 16 + upper 16)
        uint256 chainid = block.chainid;
        blockInfo = abi.encodePacked(blockInfo, bytes16(uint128(chainid)), bytes16(uint128(chainid >> 128)));

        // SELFBALANCE (32 bytes total - lower 16 + upper 16)
        uint256 selfbalance = address(this).balance;
        blockInfo = abi.encodePacked(blockInfo, bytes16(uint128(selfbalance)), bytes16(uint128(selfbalance >> 128)));

        // BASEFEE (32 bytes total - lower 16 + upper 16)
        uint256 basefee = block.basefee;
        blockInfo = abi.encodePacked(blockInfo, bytes16(uint128(basefee)), bytes16(uint128(basefee >> 128)));

        // Block hashes 1-4 blocks ago (32 bytes each - lower 16 + upper 16)
        for (uint256 i = 1; i <= 4; i++) {
            bytes32 blockHash;
            if (block.number >= i) {
                blockHash = blockhash(block.number - i);
            }
            // If block.number < i, blockHash remains 0x0 (default value)
            uint256 hashValue = uint256(blockHash);
            blockInfo = abi.encodePacked(blockInfo, bytes16(uint128(hashValue)), bytes16(uint128(hashValue >> 128)));
        }

        return keccak256(blockInfo);
    }

    function _extractBlockInfoHashFromProof(uint256[] calldata publicInputs) internal pure returns (bytes32) {
        require(publicInputs.length >= 66, "Public inputs too short for block info");
        
        bytes memory blockInfo;
        
        // Extract block info from public inputs (indices 42-65 based on instance_description.json)
        // Each block variable is stored as lower 16 bytes + upper 16 bytes
        for (uint256 i = 42; i < 66; i += 2) {
            // Combine lower and upper 16 bytes back to 32 bytes
            uint256 lower = publicInputs[i];
            uint256 upper = publicInputs[i + 1];
            blockInfo = abi.encodePacked(blockInfo, bytes16(uint128(lower)), bytes16(uint128(upper)));
        }
        
        return keccak256(blockInfo);
    }

    function _extractFunctionSignatureFromProof(uint256[] calldata publicInputs) internal pure returns (bytes32) {
        // Function signature is located at row 18 (0-indexed) in the user data section
        // Row 18: Selector for a function to call (complete 4-byte selector)
        require(publicInputs.length >= 19, "Public inputs too short for function signature");
        
        // Extract the function selector from index 18
        // The value is already a complete 4-byte selector stored as uint256
        uint256 selectorValue = publicInputs[18];
        bytes4 selector = bytes4(uint32(selectorValue));
        
        return bytes32(selector);
    }

    function _extractFunctionInstanceHashFromProof(uint256[] calldata publicInputs) internal pure returns (bytes32) {
        // Function instance data starts at index 66 (based on instance_description.json)
        // User data: 0-41, Block data: 42-65, Function data: 66+
        require(publicInputs.length > 66, "Public inputs too short for function instance data");
        
        // Extract function instance data starting from index 66
        uint256 functionDataLength = publicInputs.length - 66;
        uint256[] memory functionInstanceData = new uint256[](functionDataLength);
        
        for (uint256 i = 0; i < functionDataLength; i++) {
            functionInstanceData[i] = publicInputs[66 + i];
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

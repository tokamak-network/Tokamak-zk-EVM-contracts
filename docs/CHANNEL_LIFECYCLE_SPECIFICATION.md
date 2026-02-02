# Tokamak zkEVM Bridge: Channel Lifecycle Technical Specification

**Version:** 2.0 (Q2 2026)
**Last Updated:** January 2026
**Status:** Production

---

## Table of Contents

1. [Overview](#1-overview)
2. [Architecture](#2-architecture)
3. [Data Structures](#3-data-structures)
4. [Channel States](#4-channel-states)
5. [Lifecycle Phases](#5-lifecycle-phases)
6. [Access Control](#6-access-control)
7. [Events Reference](#7-events-reference)
8. [Security Considerations](#8-security-considerations)
9. [Q2 2026 Async Channels Extension](#9-q2-2026-async-channels-extension)
10. [Appendix](#10-appendix)

---

## 1. Overview

### 1.1 Purpose

The Tokamak zkEVM Bridge implements a state channel system that enables secure off-chain computation with on-chain settlement. Channels serve as isolated execution environments where participants can perform token operations that are later verified and settled on Layer 1 using Zero-Knowledge proofs.

### 1.2 Key Characteristics

| Property | Description |
|----------|-------------|
| **ZK Verification** | Groth16 proofs verify state transitions |
| **Token Support** | ERC20 tokens only (no native ETH) |
| **Signature Scheme** | Optional FROST threshold signatures |
| **Tree Sizes** | Dynamic: 16, 32, 64, or 128 leaves |
| **Upgrade Pattern** | UUPS (Universal Upgradeable Proxy Standard) |
| **Timeout Protection** | 7-day automatic timeout |

### 1.3 Lifecycle Summary

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          CHANNEL LIFECYCLE FLOW                             │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   ┌──────────┐    ┌───────────┐    ┌──────────┐    ┌──────────────────┐     │
│   │   None   │───>│Initialized│───>│   Open   │───>│     Closing      │     │
│   └──────────┘    └───────────┘    └──────────┘    └──────────────────┘     │
│        │               │               │                   │                │
│        │          Deposits &      ZK Proofs &         Groth16 Final         │
│   openChannel()   Key Setup    Signatures (opt)      Balance Proof          │
│                                      │                   │                  │
│                                      v                   v                  │
│                               ┌──────────┐        ┌──────────┐              │
│                               │Disputing │        │ Deleted  │              │
│                               │ (Q2 2026)│        │(Withdraw)│              │
│                               └──────────┘        └──────────┘              │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Architecture

### 2.1 Contract Hierarchy

```
                        ┌─────────────────────┐
                        │     BridgeCore      │
                        │  (State Management) │
                        └──────────┬──────────┘
                                   │
           ┌───────────────────────┼───────────────────────┐
           │                       │                       │
           v                       v                       v
┌─────────────────────┐ ┌─────────────────────┐ ┌─────────────────────┐
│ BridgeDepositManager│ │  BridgeProofManager │ │BridgeWithdrawManager│
│    (Deposits)       │ │   (ZK Proofs)       │ │   (Withdrawals)     │
└─────────────────────┘ └─────────────────────┘ └─────────────────────┘
           │                       │                       │
           │                       v                       │
           │            ┌─────────────────────┐            │
           │            │  TokamakVerifier    │            │
           │            │ (ZK-SNARK Verify)   │            │
           │            └─────────────────────┘            │
           │                       │                       │
           │            ┌─────────────────────┐            │
           │            │ Groth16Verifier*    │            │
           │            │ (16/32/64/128)      │            │
           │            └─────────────────────┘            │
           │                                               │
           └───────────────────┬───────────────────────────┘
                               │
                    ┌──────────┴──────────┐
                    │  Q2 2026 Managers   │
                    └──────────┬──────────┘
                               │
           ┌───────────────────┼───────────────────┐
           v                                       v
┌─────────────────────┐                 ┌──────────────────────┐
│BridgeStakingManager │                 │BridgeObjectionManager│
│   (TON Staking)     │<───────────────>│  (Challenges)        │
└─────────────────────┘                 └──────────────────────┘
```

### 2.2 File Locations

| Contract | Path | Purpose |
|----------|------|---------|
| `BridgeCore` | `src/BridgeCore.sol` | Core state management |
| `BridgeDepositManager` | `src/BridgeDepositManager.sol` | Token deposits |
| `BridgeProofManager` | `src/BridgeProofManager.sol` | ZK proof handling |
| `BridgeWithdrawManager` | `src/BridgeWithdrawManager.sol` | Withdrawal processing |
| `BridgeStakingManager` | `src/BridgeStakingManager.sol` | TON staking (Q2 2026) |
| `BridgeObjectionManager` | `src/BridgeObjectionManager.sol` | Challenge system (Q2 2026) |
| `IBridgeCore` | `src/interface/IBridgeCore.sol` | Core interface |

---

## 3. Data Structures

### 3.1 Channel Struct

The primary data structure representing a channel:

```solidity
struct Channel {
    // Slot 0: Unique identifier
    bytes32 id;

    // Slot 1-2: Addresses and flags (packed)
    address targetContract;         // ERC20 token address
    address leader;                 // Channel initiator
    ChannelState state;            // Current state (1 byte)
    bool sigVerified;              // FROST signature verified
    bool frostSignatureEnabled;    // FROST required flag

    // Slot 3: Signer info and tree configuration
    address signerAddr;            // Derived from public key
    uint64 requiredTreeSize;       // 16, 32, 64, or 128
    uint32 preAllocatedLeavesCount;// Pre-allocated Merkle leaves

    // Slot 4-5: Timestamps
    uint128 openTimestamp;         // Channel opening time
    uint128 closeTimestamp;        // Channel closing time
    uint128 _reserved;             // Future use

    // Slots 6-8: State roots
    bytes32 initialStateRoot;      // Initial Merkle root
    bytes32 finalStateRoot;        // Final Merkle root
    bytes32 blockInfosHash;        // Block context hash

    // Slots 9-10: FROST public key
    uint256 pkx;                   // Public key X coordinate
    uint256 pky;                   // Public key Y coordinate

    // Dynamic mappings
    mapping(address => bool) isWhiteListed;
    address[] participants;
    mapping(address => mapping(uint8 => uint256)) l2MptKey;
}
```

### 3.2 Supporting Structures

#### ChannelParams (Input)
```solidity
struct ChannelParams {
    bytes32 channelId;              // Unique channel identifier
    address targetContract;         // ERC20 token contract
    address[] whitelisted;          // Allowed participants
    bool enableFrostSignature;      // Enable FROST signatures
}
```

#### TargetContract (Configuration)
```solidity
struct TargetContract {
    PreAllocatedLeaf[] preAllocatedLeaves;      // Pre-set Merkle leaves
    RegisteredFunction[] registeredFunctions;   // Allowed functions
    UserStorageSlot[] userStorageSlots;         // Storage slot config
}
```

#### UserStorageSlot (Per-Token Configuration)
```solidity
struct UserStorageSlot {
    uint8 slotOffset;                    // Slot index
    bytes32 getterFunctionSignature;     // Function to fetch value
    bool isLoadedOnChain;                // false = balance, true = on-chain fetch
}
```

#### ValidatedUserStorage (Final Balances)
```solidity
struct ValidatedUserStorage {
    address targetContract;              // Associated token
    mapping(uint8 => uint256) value;     // value[SLOT_INDEX]
    bool isLocked;                       // Lock flag
}
```

#### ConfirmedState (Q2 2026)
```solidity
struct ConfirmedState {
    bytes32 stateRoot;      // Confirmed state root
    uint256 confirmedAt;    // Confirmation timestamp
    uint256 proofIndex;     // Associated proof index
    uint256 blockNumber;    // Block of confirmation
}
```

### 3.3 Proof Structures

#### ChannelInitializationProof
```solidity
struct ChannelInitializationProof {
    uint256[4] pA;          // Proof element A
    uint256[8] pB;          // Proof element B
    uint256[4] pC;          // Proof element C
    bytes32 merkleRoot;     // Initial state root
}
```

#### ChannelFinalizationProof
```solidity
struct ChannelFinalizationProof {
    uint256[4] pA;          // Proof element A
    uint256[8] pB;          // Proof element B
    uint256[4] pC;          // Proof element C
}
```

#### ProofData (Computation Proof)
```solidity
struct ProofData {
    uint128[] proofPart1;           // Proof component 1
    uint256[] proofPart2;           // Proof component 2
    uint256[] publicInputs;         // Public inputs array
    uint256 smax;                   // Max constraints
}
```

---

## 4. Channel States

### 4.1 State Enumeration

```solidity
enum ChannelState {
    None,           // 0 - Channel does not exist
    Initialized,    // 1 - Created, awaiting deposits
    Open,           // 2 - Active, accepting proofs
    Disputing,      // 3 - Objection raised (Q2 2026)
    Closing         // 4 - Awaiting finalization
}
```

### 4.2 State Transition Matrix

| From State | To State | Trigger | Contract |
|------------|----------|---------|----------|
| `None` | `Initialized` | `openChannel()` | BridgeCore |
| `Initialized` | `Open` | `initializeChannelState()` | BridgeProofManager |
| `Open` | `Closing` | `submitProofAndSignature()` | BridgeProofManager |
| `Open` | `Disputing` | `raiseObjection()` | BridgeObjectionManager |
| `Disputing` | `Open` | `resolveObjection()` | BridgeObjectionManager |
| `Closing` | `(Deleted)` | `updateValidatedUserStorage()` | BridgeProofManager |

### 4.3 State Diagram

```
                              openChannel()
                                   │
                                   v
┌──────────┐              ┌──────────────────┐
│   None   │─────────────>│   Initialized    │
└──────────┘              └────────┬─────────┘
     ^                             │
     │                     initializeChannelState()
     │                             │
     │                             v
     │                    ┌──────────────────┐
     │  cleanupChannel()  │      Open        │<─────────┐
     │        │           └────────┬─────────┘          │
     │        │                    │                    │
     │        │    submitProofAndSignature()    resolveObjection()
     │        │                    │                    │ (proof valid)
     │        │                    v                    │
     │        │           ┌──────────────────┐          │
     │        │           │     Closing      │          │
     │        │           └────────┬─────────┘          │
     │        │                    │                    │
     │        │   updateValidatedUserStorage()          │
     │        │                    │                    │
     │        v                    v                    │
     │   ┌────────────────────────────────┐             │
     └───│           (Deleted)            │             │
         └────────────────────────────────┘             │
                                                        │
                        raiseObjection()                │
                              │                         │
                              v                         │
                     ┌──────────────────┐               │
                     │    Disputing     │───────────────┘
                     │    (Q2 2026)     │
                     └──────────────────┘
```

---

## 5. Lifecycle Phases

### 5.1 Phase 1: Channel Initialization

#### Description
A channel leader creates a new channel by specifying the target token, whitelisted participants, and optional FROST signature requirement.

#### Function Signature
```solidity
function openChannel(ChannelParams calldata params) external returns (bytes32 channelId)
```

**Location:** `BridgeCore.sol:170-222`

#### Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `params.channelId` | `bytes32` | Unique channel identifier |
| `params.targetContract` | `address` | ERC20 token address |
| `params.whitelisted` | `address[]` | Allowed participants |
| `params.enableFrostSignature` | `bool` | Enable FROST requirement |

#### Preconditions

| Check | Error Message |
|-------|---------------|
| `params.channelId != bytes32(0)` | "Channel ID cannot be zero" |
| `params.targetContract != address(0)` | "Target contract cannot be zero address" |
| Target contract is allowed | "Target contract not allowed" |
| Channel ID is unique | "Channel ID already exists" |
| Participant count is valid | "Invalid whitelisted count considering pre-allocated leaves" |

#### State Changes

1. Creates new `Channel` struct
2. Sets `state = Initialized`
3. Sets `openTimestamp = block.timestamp`
4. Calculates `requiredTreeSize`
5. Auto-whitelists channel leader
6. Whitelists all provided participants

#### Tree Size Calculation

```solidity
function determineTreeSize(uint256 participantCount, uint256 contractCount)
    internal pure returns (uint256)
{
    uint256 totalLeaves = participantCount * contractCount;

    if (totalLeaves <= 16) return 16;
    else if (totalLeaves <= 32) return 32;
    else if (totalLeaves <= 64) return 64;
    else if (totalLeaves <= 128) return 128;
    else revert("Too many participant-contract combinations");
}
```

#### Event Emitted
```solidity
event ChannelOpened(bytes32 indexed channelId, address targetContract);
```

#### Example Usage

```solidity
// Generate channel ID
bytes32 salt = keccak256(abi.encodePacked(block.timestamp, msg.sender));
bytes32 channelId = bridgeCore.generateChannelId(msg.sender, salt);

// Prepare participants
address[] memory participants = new address[](3);
participants[0] = 0xAlice...;
participants[1] = 0xBob...;
participants[2] = 0xCharlie...;

// Create channel
IBridgeCore.ChannelParams memory params = IBridgeCore.ChannelParams({
    channelId: channelId,
    targetContract: USDC_ADDRESS,
    whitelisted: participants,
    enableFrostSignature: true
});

bridgeCore.openChannel(params);
```

---

### 5.2 Phase 2: Public Key Setup (FROST Enabled Only)

#### Description
If FROST signatures are enabled, the channel leader must set the threshold public key before deposits can begin.

#### Function Signature
```solidity
function setChannelPublicKey(bytes32 channelId, uint256 pkx, uint256 pky) external
```

**Location:** `BridgeCore.sol:224-241`

#### Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `channelId` | `bytes32` | Target channel |
| `pkx` | `uint256` | Public key X coordinate |
| `pky` | `uint256` | Public key Y coordinate |

#### Preconditions

| Check | Error Message |
|-------|---------------|
| Channel exists | "Channel does not exist" |
| Caller is leader | "Only channel leader can set public key" |
| FROST is enabled | "frost is disabled" |
| State is Initialized | "Can only set public key for initialized channel" |
| Key not already set | "Public key already set" |

#### State Changes

1. Sets `channel.pkx = pkx`
2. Sets `channel.pky = pky`
3. Derives and sets `channel.signerAddr`

#### Signer Address Derivation

```solidity
function deriveAddressFromPubkey(uint256 pkx, uint256 pky) internal pure returns (address) {
    bytes32 h = keccak256(abi.encodePacked(pkx, pky));
    return address(uint160(uint256(h)));
}
```

#### Event Emitted
```solidity
event ChannelPublicKeySet(
    bytes32 indexed channelId,
    uint256 pkx,
    uint256 pky,
    address signerAddr
);
```

---

### 5.3 Phase 3: Deposits

#### Description
Whitelisted participants deposit tokens into the channel. Each deposit records the amount and L2 MPT (Merkle Patricia Trie) keys for state tracking.

#### Function Signature
```solidity
function depositToken(
    bytes32 _channelId,
    uint256 _amount,
    bytes32[] calldata _mptKeys
) external nonReentrant
```

**Location:** `BridgeDepositManager.sol:39-92`

#### Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `_channelId` | `bytes32` | Target channel |
| `_amount` | `uint256` | Token amount to deposit |
| `_mptKeys` | `bytes32[]` | MPT keys for each storage slot |

#### Preconditions

| Check | Error Message |
|-------|---------------|
| State is Initialized | "Invalid channel state" |
| Caller is whitelisted | "Not whitelisted" |
| Public key set (if FROST) | "Channel leader must set public key first" |
| Valid target contract | "Invalid target contract" |
| MPT keys count matches | "MPT keys count mismatch" |
| Sufficient balance | "Insufficient token balance: X < Y" |
| Sufficient allowance | "Insufficient token allowance: X < Y" |

#### State Changes

1. Transfers tokens from user to DepositManager
2. Updates `ValidatedUserStorage` with deposit amount
3. Adds user to `participants` array (first deposit only)
4. Stores MPT keys for all storage slots

#### Process Flow

```
┌──────────────┐     ┌───────────────────┐     ┌─────────────────┐
│   User       │     │ BridgeDeposit     │     │   BridgeCore    │
│              │     │ Manager           │     │                 │
└──────┬───────┘     └────────┬──────────┘     └────────┬────────┘
       │                      │                         │
       │ depositToken()       │                         │
       │─────────────────────>│                         │
       │                      │                         │
       │                      │ getChannelState()       │
       │                      │────────────────────────>│
       │                      │<────────────────────────│
       │                      │                         │
       │                      │ safeTransferFrom()      │
       │<─────────────────────│                         │
       │                      │                         │
       │                      │ updateChannelUserDeposits()
       │                      │────────────────────────>│
       │                      │                         │
       │                      │ addParticipantOnDeposit()
       │                      │────────────────────────>│
       │                      │                         │
       │                      │ setChannelL2MptKeys()   │
       │                      │────────────────────────>│
       │                      │                         │
       │ Deposited event      │                         │
       │<─────────────────────│                         │
       │                      │                         │
```

#### Event Emitted
```solidity
event Deposited(
    bytes32 indexed channelId,
    address indexed user,
    address token,
    uint256 amount
);
```

#### MPT Key Validation

```solidity
// MPT keys must be less than the BLS12-381 scalar field modulus
uint256 constant R_MOD = 0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001;
require(mptKeys[i] < R_MOD, "MPT key exceeds R_MOD");
```

---

### 5.4 Phase 4: State Initialization

#### Description
The channel leader submits a Groth16 proof establishing the initial Merkle tree state, transitioning the channel to `Open`.

#### Function Signature
```solidity
function initializeChannelState(
    bytes32 channelId,
    ChannelInitializationProof calldata proof
) external nonReentrant
```

**Location:** `BridgeProofManager.sol:114-239`

#### Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `channelId` | `bytes32` | Target channel |
| `proof` | `ChannelInitializationProof` | Groth16 proof with Merkle root |

#### Preconditions

| Check | Error Message |
|-------|---------------|
| State is Initialized | "Invalid state" |
| Caller is leader | "Not leader" |
| Public key set (if FROST) | "Channel leader must set public key first" |
| Leader has deposited | "Leader must deposit before initializing" |
| Total entries <= tree size | "Too many entries for circuit" |

#### Public Signals Structure

The proof's public signals array has the following structure:

```
Index 0:                    Merkle root
Index 1 to treeSize:       MPT keys
Index (treeSize+1) to (2*treeSize): Leaf values
```

**Total Length:** `2 * treeSize + 1`

| Tree Size | Public Signals Length |
|-----------|----------------------|
| 16 | 33 |
| 32 | 65 |
| 64 | 129 |
| 128 | 257 |

#### Leaf Population Order

1. **Pre-allocated leaves** (if any)
2. **Participant data** (by storage slot, then by participant)
3. **Zero-fill** remaining slots

```solidity
// Example for 2 participants, 2 storage slots, 1 pre-allocated leaf:
// Tree Size = 16

// Pre-allocated leaves first
publicSignals[1] = preAllocatedKey1;
publicSignals[17] = preAllocatedValue1;

// Then participant data by slot
// Slot 0 (balance)
publicSignals[2] = participant1_slot0_key;
publicSignals[18] = participant1_slot0_value;
publicSignals[3] = participant2_slot0_key;
publicSignals[19] = participant2_slot0_value;

// Slot 1 (other data)
publicSignals[4] = participant1_slot1_key;
publicSignals[20] = participant1_slot1_value;
publicSignals[5] = participant2_slot1_key;
publicSignals[21] = participant2_slot1_value;

// Zero-fill remaining (indices 6-16 for keys, 22-32 for values)
```

#### Block Info Hash Computation

The block context is captured and hashed at initialization:

```solidity
struct BlockInfos {
    uint256 blockNumber;
    uint256 timestamp;
    uint256 prevrandao;
    uint256 gaslimit;
    uint256 basefee;
    address coinbase;
    uint256 chainId;
    uint256 selfbalance;
    uint256 blockHash1;  // blockhash(block.number - 1)
    uint256 blockHash2;  // blockhash(block.number - 2)
    uint256 blockHash3;  // blockhash(block.number - 3)
    uint256 blockHash4;  // blockhash(block.number - 4)
}
```

#### State Changes

1. Verifies Groth16 proof
2. Sets `channel.initialStateRoot = proof.merkleRoot`
3. Sets `channel.blockInfosHash = keccak256(blockInfo)`
4. Sets `channel.state = Open`

#### Event Emitted
```solidity
event StateInitialized(
    bytes32 indexed channelId,
    bytes32 currentStateRoot,
    BlockInfos blockInfos
);
```

---

### 5.5 Phase 5: Proof Submission & Signature Verification

#### Description
Participants submit computation proofs with optional FROST signatures to close the channel. Multiple proofs can be batched (1-5).

#### Function Signature
```solidity
function submitProofAndSignature(
    bytes32 channelId,
    ProofData[] calldata proofs,
    Signature calldata signature
) external
```

**Location:** `BridgeProofManager.sol:241-358`

#### Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `channelId` | `bytes32` | Target channel |
| `proofs` | `ProofData[]` | Array of 1-5 computation proofs |
| `signature` | `Signature` | FROST threshold signature |

#### Signature Structure
```solidity
struct Signature {
    bytes32 message;    // keccak256(channelId, finalStateRoot)
    uint256 rx;         // Signature R.x
    uint256 ry;         // Signature R.y
    uint256 z;          // Signature z
}
```

#### Preconditions

| Check | Error Message |
|-------|---------------|
| State is Open | "Invalid state" |
| 1-5 proofs provided | "Must provide 1-5 proofs" |
| Channel not timed out | "Cannot submit proof after timeout" |
| Proof chain is valid | "State root chain broken" |
| Signature commits to content | "Signature must commit to proof content" |
| Valid FROST signature | "Invalid group threshold signature" |
| Block info matches | "Block info mismatch in proof" |
| Function is registered | "Function not registered" |
| Valid ZK proof | "Invalid ZK proof" |

#### Verification Steps

```
┌─────────────────────────────────────────────────────────────────────┐
│                     PROOF VERIFICATION FLOW                          │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  STEP 1: Validate Proof Chain                                       │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │ Initial Root ──> Proof[0].input ──> Proof[0].output         │   │
│  │                                          │                   │   │
│  │                       ┌──────────────────┘                   │   │
│  │                       v                                      │   │
│  │                  Proof[1].input ──> Proof[1].output          │   │
│  │                                          │                   │   │
│  │                       ┌──────────────────┘                   │   │
│  │                       v                                      │   │
│  │                  Proof[n].input ──> Proof[n].output          │   │
│  │                                          │                   │   │
│  │                       ┌──────────────────┘                   │   │
│  │                       v                                      │   │
│  │                   Final State Root                           │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                                                                     │
│  STEP 2: Verify FROST Signature (if enabled)                        │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │ signature.message == keccak256(channelId, finalStateRoot)   │   │
│  │ zecFrost.verify(message, pkx, pky, rx, ry, z) == signerAddr │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                                                                     │
│  STEP 2.5: Validate Block Info                                      │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │ For each proof:                                              │   │
│  │   extractBlockInfoHash(proof) == storedBlockInfoHash        │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                                                                     │
│  STEP 3: Verify ZK-SNARK Proofs                                     │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │ For each proof:                                              │   │
│  │   1. Extract function signature from publicInputs[14]       │   │
│  │   2. Find registered function for target contract           │   │
│  │   3. Verify instance hash matches                           │   │
│  │   4. Verify proof via TokamakVerifier                       │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                                                                     │
│  STEP 4: Update Channel State                                       │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │ channel.finalStateRoot = extractedFinalRoot                 │   │
│  │ channel.sigVerified = frostEnabled                          │   │
│  │ channel.state = Closing                                     │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

#### Public Inputs Layout

The public inputs array contains:

| Index Range | Content |
|-------------|---------|
| 0-1 | Output state root (split 128-bit) |
| 8-9 | Input state root (split 128-bit) |
| 14 | Function selector |
| 40-63 | Block info data |
| 64+ | Function instance data |

#### State Changes

1. Stores `channel.finalStateRoot`
2. Sets `channel.sigVerified = true` (if FROST)
3. Sets `channel.state = Closing`

#### Events Emitted
```solidity
event TokamakZkSnarkProofsVerified(bytes32 indexed channelId, address indexed signer);
event ProofSigned(bytes32 indexed channelId, address indexed signer, bytes32 finalStateRoot);
```

---

### 5.6 Phase 6: Validated User Storage Update

#### Description
After proofs are verified, final balances are extracted and validated with a Groth16 proof, then stored for withdrawal.

#### Function Signature
```solidity
function updateValidatedUserStorage(
    bytes32 channelId,
    uint256[][] calldata finalSlotValues,
    uint256[] calldata permutation,
    ChannelFinalizationProof calldata groth16Proof
) external
```

**Location:** `BridgeProofManager.sol:360-447`

#### Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `channelId` | `bytes32` | Target channel |
| `finalSlotValues` | `uint256[][]` | `[participant][slot]` final values |
| `permutation` | `uint256[]` | Leaf ordering in Merkle tree |
| `groth16Proof` | `ChannelFinalizationProof` | Groth16 proof |

#### Preconditions

| Check | Error Message |
|-------|---------------|
| State is Closing | "Invalid state" |
| Signature verified (if FROST) | "signature not verified" |
| Final values dimensions match | "Invalid slot values length" |
| Permutation length matches | "Invalid permutation length" |

#### State Changes

1. Verifies Groth16 proof against final state root
2. Stores validated user storage for all participants
3. Sets `channel.closeTimestamp`
4. Calls `cleanupChannel()` to delete channel data

#### Channel Cleanup Process

```solidity
function cleanupChannel(bytes32 channelId) external onlyManager {
    // 1. Get participants and target contract
    address[] memory participants = channel.participants;
    address targetContract = channel.targetContract;

    // 2. Clear all whitelist mappings
    for (uint256 i = 0; i < participants.length; i++) {
        delete channel.isWhiteListed[participants[i]];
    }

    // 3. Clear all L2 MPT key mappings
    for (uint256 i = 0; i < participants.length; i++) {
        for (uint8 j = 0; j < numSlots; j++) {
            delete channel.l2MptKey[participants[i]][j];
        }
    }

    // 4. Delete channel struct
    delete channels[channelId];

    emit ChannelDeleted(channelId, block.timestamp);
}
```

#### Event Emitted
```solidity
event FinalBalancesGroth16Verified(bytes32 indexed channelId, bytes32 finalStateRoot);
event ChannelDeleted(bytes32 indexed channelId, uint256 cleanupTime);
```

---

### 5.7 Phase 7: Withdrawal

#### Description
After channel cleanup, participants can withdraw their final validated balances.

#### Function Signature
```solidity
function withdraw(bytes32 channelId, address targetContract) external nonReentrant
```

**Location:** `BridgeWithdrawManager.sol:43-70`

#### Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `channelId` | `bytes32` | Channel to withdraw from |
| `targetContract` | `address` | Token contract address |

#### Preconditions

| Check | Error Message |
|-------|---------------|
| Target contract valid | "Invalid target contract" |
| Channel deleted or timed out | "Channel must be deleted or timed out" |
| Target contract matches | "Target contract mismatch" |
| Withdrawable amount > 0 | "No withdrawable amount" |

#### State Changes

1. Reads validated balance for caller
2. Clears validated user storage
3. Transfers tokens from DepositManager to caller

#### Process Flow

```
┌──────────────┐     ┌───────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   User       │     │ BridgeWithdraw    │     │   BridgeCore    │     │ BridgeDeposit   │
│              │     │ Manager           │     │                 │     │ Manager         │
└──────┬───────┘     └────────┬──────────┘     └────────┬────────┘     └────────┬────────┘
       │                      │                         │                       │
       │ withdraw()           │                         │                       │
       │─────────────────────>│                         │                       │
       │                      │                         │                       │
       │                      │ getChannelLeader()      │                       │
       │                      │────────────────────────>│                       │
       │                      │<────────────────────────│                       │
       │                      │ (returns 0x0 = deleted) │                       │
       │                      │                         │                       │
       │                      │ getValidatedUserSlotValue()                     │
       │                      │────────────────────────>│                       │
       │                      │<────────────────────────│                       │
       │                      │                         │                       │
       │                      │ clearValidatedUserStorage()                     │
       │                      │────────────────────────>│                       │
       │                      │                         │                       │
       │                      │ transferForWithdrawal() │                       │
       │                      │────────────────────────────────────────────────>│
       │                      │                         │                       │
       │ tokens               │                         │                       │
       │<──────────────────────────────────────────────────────────────────────│
       │                      │                         │                       │
       │ Withdrawn event      │                         │                       │
       │<─────────────────────│                         │                       │
```

#### Event Emitted
```solidity
event Withdrawn(
    bytes32 indexed channelId,
    address indexed user,
    address token,
    uint256 amount
);
```

---

## 6. Access Control

### 6.1 Role Matrix

| Role | Functions | Description |
|------|-----------|-------------|
| **Contract Owner** | `setAllowedTargetContract()`, `registerFunction()`, `unregisterFunction()`, `updateManagerAddresses()`, `updateQ2Managers()` | System configuration |
| **Channel Leader** | `openChannel()`, `setChannelPublicKey()`, `initializeChannelState()` | Channel lifecycle initiation |
| **Whitelisted Participant** | `depositToken()`, `withdraw()` | Token operations |
| **Any Caller** | `submitProofAndSignature()`, `updateValidatedUserStorage()` | Proof submission |
| **Manager Contracts** | Internal state updates | Cross-contract calls |

### 6.2 Manager Authorization

```solidity
modifier onlyManager() {
    BridgeCoreStorage storage $ = _getBridgeCoreStorage();
    require(
        msg.sender == $.depositManager ||
        msg.sender == $.proofManager ||
        msg.sender == $.withdrawManager ||
        msg.sender == $.adminManager ||
        msg.sender == $.stakingManager ||       // Q2 2026
        msg.sender == $.objectionManager,       // Q2 2026
        "Only managers can call"
    );
    _;
}
```

### 6.3 Q2 2026 Modifiers

```solidity
// Staking Manager
modifier onlyObjectionManager() {
    require(msg.sender == $.objectionManager, "Only objection manager");
    _;
}

modifier onlyAuthorizedManager() {
    require(
        msg.sender == $.objectionManager || msg.sender == owner(),
        "Not authorized"
    );
    _;
}

// Objection Manager
modifier onlyParticipant(bytes32 channelId) {
    require($.bridge.isChannelWhitelisted(channelId, msg.sender), "Not a participant");
    _;
}

modifier requireStake(bytes32 channelId) {
    require($.stakingManager.hasMinimumStake(channelId, msg.sender), "Insufficient stake");
    _;
}
```

---

## 7. Events Reference

### 7.1 BridgeCore Events

```solidity
event ChannelOpened(bytes32 indexed channelId, address targetContract);
event ChannelPublicKeySet(bytes32 indexed channelId, uint256 pkx, uint256 pky, address signerAddr);
event PreAllocatedLeafSet(address indexed targetContract, bytes32 indexed mptKey, uint256 value);
event PreAllocatedLeafRemoved(address indexed targetContract, bytes32 indexed mptKey);
event ChannelDeleted(bytes32 indexed channelId, uint256 cleanupTime);
```

### 7.2 BridgeDepositManager Events

```solidity
event Deposited(bytes32 indexed channelId, address indexed user, address token, uint256 amount);
```

### 7.3 BridgeProofManager Events

```solidity
event StateInitialized(bytes32 indexed channelId, bytes32 currentStateRoot, BlockInfos blockInfos);
event TokamakZkSnarkProofsVerified(bytes32 indexed channelId, address indexed signer);
event FinalBalancesGroth16Verified(bytes32 indexed channelId, bytes32 finalStateRoot);
event ProofSigned(bytes32 indexed channelId, address indexed signer, bytes32 finalStateRoot);
```

### 7.4 BridgeWithdrawManager Events

```solidity
event ChannelClosed(bytes32 indexed channelId);
event EmergencyWithdrawalsEnabled(bytes32 indexed channelId);
event Withdrawn(bytes32 indexed channelId, address indexed user, address token, uint256 amount);
event TimeoutWithdrawn(bytes32 indexed channelId, address indexed user, address token, uint256 amount);
```

### 7.5 BridgeStakingManager Events (Q2 2026)

```solidity
event Staked(bytes32 indexed channelId, address indexed staker, uint256 amount);
event Unstaked(bytes32 indexed channelId, address indexed staker, uint256 amount);
event UnstakeRequested(bytes32 indexed channelId, address indexed staker, uint256 cooldownEnd);
event Slashed(bytes32 indexed channelId, address indexed staker, uint256 amount, bytes32 reason);
event RewardDistributed(bytes32 indexed channelId, address indexed recipient, uint256 amount);
event RewardsClaimed(address indexed recipient, uint256 amount);
```

### 7.6 BridgeObjectionManager Events (Q2 2026)

```solidity
event PendingProofSubmitted(bytes32 indexed channelId, uint256 indexed proofIndex, address submitter, bytes32 proofHash, uint256 challengeDeadline);
event ObjectionRaised(bytes32 indexed channelId, uint256 indexed proofIndex, address objector, bytes32 reason, uint256 resolutionDeadline);
event ObjectionResolved(bytes32 indexed channelId, uint256 indexed proofIndex, ObjectionStatus outcome, address slashedParty);
event ProofRejected(bytes32 indexed channelId, uint256 indexed proofIndex, bytes32 reason);
event StateConfirmed(bytes32 indexed channelId, bytes32 stateRoot, uint256 proofsConfirmed);
```

---

## 8. Security Considerations

### 8.1 Balance Conservation

The system guarantees that the sum of all participant balances after a channel closes equals the sum of all deposits:

```
Σ(initial_deposits) = Σ(final_balances)
```

This is enforced by:
1. Groth16 proof verification of initial state
2. ZK-SNARK verification of state transitions
3. Groth16 proof verification of final balances

### 8.2 Timeout Protection

```solidity
uint256 public constant CHANNEL_TIMEOUT = 7 days;

function isChannelTimedOut(bytes32 channelId) external view returns (bool) {
    Channel storage channel = $.channels[channelId];
    require(channel.leader != address(0), "Channel does not exist");
    return block.timestamp > channel.openTimestamp + CHANNEL_TIMEOUT;
}
```

If a channel times out, participants can:
1. Withdraw their original deposit amounts
2. Skip the proof submission process

### 8.3 Replay Protection

Block context is captured at initialization and verified in every proof:

| Field | Purpose |
|-------|---------|
| `blockNumber` | Temporal anchor |
| `timestamp` | Time verification |
| `prevrandao` | Randomness source |
| `chainId` | Network identification |
| `blockhash(n-1..n-4)` | Historical verification |

### 8.4 FROST Signature Security

When enabled, FROST signatures provide:
- **Threshold security**: t-of-n participants must sign
- **Non-repudiation**: Signed commitment to final state
- **Binding**: `message = keccak256(channelId, finalStateRoot)`

### 8.5 Field Modulus Validation

All values are validated against the BLS12-381 scalar field modulus:

```solidity
uint256 constant R_MOD = 0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001;

require(amount < R_MOD, "Amount exceeds R_MOD");
require(mptKey < R_MOD, "MPT key exceeds R_MOD");
```

---

## 9. Q2 2026 Async Channels Extension

### 9.1 Overview

The Q2 2026 upgrade introduces an asynchronous proof submission model with:
- **TON Staking**: Economic security through stake requirements
- **Challenge Period**: 24-hour window for objections
- **Slashing**: Penalties for malicious behavior
- **Confirmed States**: Intermediate checkpoints

### 9.2 Staking System

#### Constants

```solidity
uint256 public constant MINIMUM_STAKE = 100 ether;        // 100 TON
uint256 public constant STAKE_LOCK_PERIOD = 7 days;
uint256 public constant UNSTAKE_COOLDOWN = 2 days;
uint256 public constant INVALID_PROOF_SLASH = 50;         // 50%
uint256 public constant FALSE_OBJECTION_SLASH = 25;       // 25%
```

#### Stake Lifecycle

```
┌─────────────┐     stakeForChannel()     ┌─────────────┐
│  No Stake   │─────────────────────────>│   Staked    │
└─────────────┘                           └──────┬──────┘
       ^                                         │
       │                                         │ requestUnstake()
       │                                         │ (after lock period)
       │                                         v
       │                                  ┌─────────────┐
       │            unstake()             │  Cooldown   │
       └──────────────────────────────────│  (2 days)   │
                                          └─────────────┘
```

#### Slashing Flow

```
                    Objection Raised
                          │
                          v
              ┌───────────────────────┐
              │  On-Chain Verification │
              └───────────┬───────────┘
                          │
          ┌───────────────┴───────────────┐
          │                               │
          v                               v
   ┌─────────────┐                 ┌─────────────┐
   │ Proof Valid │                 │Proof Invalid│
   └──────┬──────┘                 └──────┬──────┘
          │                               │
          v                               v
   Slash Objector 25%              Slash Submitter 50%
   Reward Submitter                Reward Objector
```

### 9.3 Challenge System

#### Pending Proof Structure

```solidity
struct PendingProof {
    bytes32 channelId;
    bytes32 proofHash;              // Front-running protection
    bytes32 previousStateRoot;
    bytes32 newStateRoot;
    address submitter;
    uint256 submittedAt;
    uint256 challengeDeadline;      // submittedAt + 24 hours
    PendingProofStatus status;      // Pending, Challenged, Confirmed, Rejected
    uint256 proofIndex;
}
```

#### Objection Structure

```solidity
struct Objection {
    bytes32 channelId;
    uint256 proofIndex;
    address objector;
    bytes32 reason;
    uint256 raisedAt;
    uint256 resolutionDeadline;     // raisedAt + 48 hours
    ObjectionStatus status;         // Active, Upheld, Dismissed
}
```

#### Challenge Timeline

```
      submitPendingProof()                  confirmState()
             │                                    │
             v                                    v
    ─────────┼────────────────────────────────────┼─────────────>
             │◄──────── 24 hours ────────────────►│    time
             │      Challenge Period              │
             │                                    │
             │    raiseObjection()               If no objection,
             │         │                         proof is confirmed
             │         v
             │    ─────┼────────────────────────────────>
             │         │◄──────── 48 hours ──────►│
             │         │    Resolution Period     │
             │         │                          │
             │    resolveObjection()              │
             │         │                          │
             │         v                          │
             │    On-chain verification           │
```

### 9.4 Confirmed States

Intermediate confirmed states allow closing from any checkpoint:

```solidity
function updateValidatedUserStorageFromIntermediate(
    bytes32 channelId,
    uint256 fromStateIndex,      // 0 = initial, 1+ = confirmed states
    uint256[][] calldata finalSlotValues,
    uint256[] calldata permutation,
    ChannelFinalizationProof calldata groth16Proof
) external
```

This enables:
- Faster finalization from recent checkpoints
- Recovery from disputed proofs
- Reduced proof generation cost

---

## 10. Appendix

### 10.1 Constants Reference

| Constant | Value | Contract |
|----------|-------|----------|
| `MIN_PARTICIPANTS` | 1 | BridgeCore |
| `MAX_PARTICIPANTS` | 128 | BridgeCore |
| `CHANNEL_TIMEOUT` | 7 days | BridgeCore |
| `R_MOD` | `0x73eda...00001` | BridgeCore, BridgeProofManager |
| `MINIMUM_STAKE` | 100 ether | BridgeStakingManager |
| `STAKE_LOCK_PERIOD` | 7 days | BridgeStakingManager |
| `UNSTAKE_COOLDOWN` | 2 days | BridgeStakingManager |
| `INVALID_PROOF_SLASH` | 50% | BridgeStakingManager |
| `FALSE_OBJECTION_SLASH` | 25% | BridgeStakingManager |
| `CHALLENGE_PERIOD` | 24 hours | BridgeObjectionManager |
| `RESOLUTION_TIMEOUT` | 48 hours | BridgeObjectionManager |
| `MAX_PENDING_PROOFS` | 100 | BridgeObjectionManager |

### 10.2 Error Messages Reference

| Error | Contract | Cause |
|-------|----------|-------|
| "Channel ID cannot be zero" | BridgeCore | Invalid channel ID |
| "Target contract not allowed" | BridgeCore | Unregistered token |
| "Channel ID already exists" | BridgeCore | Duplicate channel |
| "Invalid whitelisted count considering pre-allocated leaves" | BridgeCore | Too many/few participants |
| "Channel does not exist" | BridgeCore | Unknown channel |
| "Only channel leader can set public key" | BridgeCore | Unauthorized caller |
| "frost is disabled" | BridgeCore | FROST not enabled |
| "Public key already set" | BridgeCore | Key already configured |
| "Invalid channel state" | BridgeDepositManager | Wrong state for deposits |
| "Not whitelisted" | BridgeDepositManager | Unauthorized depositor |
| "MPT keys count mismatch" | BridgeDepositManager | Wrong MPT key count |
| "Invalid state" | BridgeProofManager | Wrong channel state |
| "Not leader" | BridgeProofManager | Unauthorized initializer |
| "Leader must deposit before initializing" | BridgeProofManager | Leader has no deposit |
| "Too many entries for circuit" | BridgeProofManager | Exceeded tree capacity |
| "Invalid Groth16 proof" | BridgeProofManager | Proof verification failed |
| "Must provide 1-5 proofs" | BridgeProofManager | Invalid proof count |
| "Cannot submit proof after timeout" | BridgeProofManager | Channel timed out |
| "State root chain broken" | BridgeProofManager | Discontinuous proof chain |
| "Signature must commit to proof content" | BridgeProofManager | Wrong signature message |
| "Invalid group threshold signature" | BridgeProofManager | FROST verification failed |
| "Block info mismatch in proof" | BridgeProofManager | Block context mismatch |
| "Function not registered" | BridgeProofManager | Unknown function |
| "Invalid ZK proof" | BridgeProofManager | TokamakVerifier failed |
| "signature not verified" | BridgeProofManager | Missing FROST signature |
| "Channel must be deleted or timed out" | BridgeWithdrawManager | Channel still active |
| "Target contract mismatch" | BridgeWithdrawManager | Wrong token address |
| "No withdrawable amount" | BridgeWithdrawManager | Zero balance |

### 10.3 Gas Estimates

| Operation | Approximate Gas |
|-----------|-----------------|
| `openChannel()` | ~150,000 - 300,000 |
| `setChannelPublicKey()` | ~50,000 |
| `depositToken()` | ~150,000 - 200,000 |
| `initializeChannelState()` | ~500,000 - 2,000,000 |
| `submitProofAndSignature()` | ~500,000 - 3,000,000 |
| `updateValidatedUserStorage()` | ~400,000 - 1,500,000 |
| `withdraw()` | ~100,000 - 150,000 |

*Note: Gas varies significantly based on tree size, participant count, and proof complexity.*

### 10.4 Integration Checklist

- [ ] Target contract is registered with `setAllowedTargetContract()`
- [ ] Required functions are registered with `registerFunction()`
- [ ] User storage slots are properly configured
- [ ] Pre-allocated leaves are set if needed
- [ ] Groth16 verifiers are deployed for required tree sizes
- [ ] FROST key generation completed (if using signatures)
- [ ] Proof generation infrastructure ready
- [ ] Sufficient gas limits configured for ZK operations

---

*End of Technical Specification*

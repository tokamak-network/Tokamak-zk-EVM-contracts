# RollupBridgeCore - Getter Functions and Storage Documentation

## Overview
The `RollupBridgeCore` contract serves as the central hub for managing state channels in the Tokamak zk-EVM rollup bridge system. It provides comprehensive access to channel data, user information, and system analytics through a rich set of getter functions.

## Table of Contents
1. [Storage Structure](#storage-structure)
2. [Constants](#constants)
3. [Basic Channel Getters](#basic-channel-getters)
4. [Deposit & Withdrawal Getters](#deposit--withdrawal-getters)
5. [System Analytics](#system-analytics)
6. [User Analytics](#user-analytics)
7. [Advanced Search Functions](#advanced-search-functions)
8. [Validation Functions](#validation-functions)
9. [Manager Functions](#manager-functions)
10. [Implementation Details](#implementation-details)

---

## Storage Structure

### RollupBridgeCoreStorage
The main storage struct using ERC-7201 pattern for safe upgrades:

```solidity
struct RollupBridgeCoreStorage {
    mapping(uint256 => Channel) channels;              // Channel ID -> Channel data
    mapping(address => bool) isChannelLeader;          // Address -> Is currently a channel leader
    mapping(address => TargetContract) allowedTargetContracts;  // Token contract configurations
    mapping(address => bool) isTargetContractAllowed;  // Quick token allowance check
    mapping(bytes32 => RegisteredFunction) registeredFunctions; // ZK circuit function registry
    uint256 nextChannelId;                             // Next available channel ID
    address treasury;                                  // Treasury address for fees
    uint256 totalSlashedBonds;                        // Total bonds slashed across all channels
    address depositManager;                           // Deposit manager contract
    address proofManager;                             // Proof manager contract
    address withdrawManager;                          // Withdrawal manager contract
    address adminManager;                             // Admin manager contract
}
```

### Channel Structure
Individual channel data structure:

```solidity
struct Channel {
    uint256 id;                                       // Channel identifier
    address[] allowedTokens;                          // Tokens allowed in this channel
    mapping(address => bool) isTokenAllowed;          // Quick token check
    mapping(address => mapping(address => uint256)) tokenDeposits;  // user -> token -> amount
    mapping(address => uint256) tokenTotalDeposits;   // token -> total deposited
    bytes32 initialStateRoot;                         // Initial Merkle tree state root
    address[] participants;                           // Channel participants
    mapping(address => mapping(address => uint256)) l2MptKeys;  // user -> token -> L2 MPT key
    mapping(address => bool) isParticipant;           // Quick participant check
    ChannelState state;                               // Current channel state
    uint256 openTimestamp;                            // When channel was opened
    uint256 closeTimestamp;                           // When channel was closed
    uint256 timeout;                                  // Channel timeout duration
    address leader;                                   // Channel leader address
    uint256 leaderBond;                              // Leader's bond amount
    bool leaderBondSlashed;                          // Whether leader bond was slashed
    mapping(address => bool) hasWithdrawn;           // user -> has withdrawn funds
    mapping(address => mapping(address => uint256)) withdrawAmount; // user -> token -> withdrawable
    uint256 pkx;                                     // Public key X coordinate
    uint256 pky;                                     // Public key Y coordinate
    address signerAddr;                              // Derived signer address
    bool sigVerified;                                // Whether signature is verified
    uint256 requiredTreeSize;                        // Required Merkle tree size
}
```

### Supporting Structures

```solidity
enum ChannelState {
    None,           // 0 - Channel doesn't exist
    Initialized,    // 1 - Channel created, waiting for deposits
    Open,          // 2 - Channel open for deposits
    Active,        // 3 - Channel active with transactions
    Closing,       // 4 - Channel closing, in dispute period
    Closed         // 5 - Channel closed, funds withdrawable
}

struct ChannelParams {
    address[] allowedTokens;    // Tokens allowed in the channel
    address[] participants;     // Channel participants
    uint256 timeout;           // Channel timeout duration
    uint256 pkx;              // Public key X coordinate
    uint256 pky;              // Public key Y coordinate
}

struct TargetContract {
    address contractAddress;    // Contract address
    bytes1 storageSlot;        // Storage slot for circuit verification
}

struct RegisteredFunction {
    bytes32 functionSignature;     // Function signature hash
    uint128[] preprocessedPart1;   // Preprocessed circuit data part 1
    uint256[] preprocessedPart2;   // Preprocessed circuit data part 2
}
```

---

## Constants

```solidity
uint256 public constant MIN_PARTICIPANTS = 1;        // Minimum participants per channel
uint256 public constant MAX_PARTICIPANTS = 128;      // Maximum participants per channel
uint256 public constant LEADER_BOND_REQUIRED = 0.001 ether;  // Required leader bond
```

---

## Basic Channel Getters

### Channel Information

#### `getChannelState(uint256 channelId) → ChannelState`
Returns the current state of a channel.

**Parameters:**
- `channelId`: The channel ID to query

**Returns:**
- Current channel state enum value

---

#### `getChannelInfo(uint256 channelId) → (address[] allowedTokens, ChannelState state, uint256 participantCount, bytes32 initialRoot)`
Comprehensive channel information in a single call.

**Parameters:**
- `channelId`: The channel ID to query

**Returns:**
- `allowedTokens`: Array of token addresses allowed in the channel
- `state`: Current channel state
- `participantCount`: Number of participants
- `initialRoot`: Initial state root hash

---

#### `getChannelParticipants(uint256 channelId) → address[]`
Returns all participants in a channel.

**Parameters:**
- `channelId`: The channel ID to query

**Returns:**
- Array of participant addresses

---

#### `getChannelAllowedTokens(uint256 channelId) → address[]`
Returns all tokens allowed in a channel.

**Parameters:**
- `channelId`: The channel ID to query

**Returns:**
- Array of allowed token addresses

---

#### `getChannelLeader(uint256 channelId) → address`
Returns the leader of a specific channel.

**Parameters:**
- `channelId`: The channel ID to query

**Returns:**
- Leader's address

---

#### `getChannelTreeSize(uint256 channelId) → uint256`
Returns the required Merkle tree size for a channel.

**Parameters:**
- `channelId`: The channel ID to query

**Returns:**
- Required tree size (16, 32, 64, or 128)

---

#### `getChannelPublicKey(uint256 channelId) → (uint256 pkx, uint256 pky)`
Returns the channel's public key coordinates.

**Parameters:**
- `channelId`: The channel ID to query

**Returns:**
- `pkx`: Public key X coordinate
- `pky`: Public key Y coordinate

---

#### `getChannelSignerAddr(uint256 channelId) → address`
Returns the derived signer address from the channel's public key.

**Parameters:**
- `channelId`: The channel ID to query

**Returns:**
- Derived signer address

---

### Participation & Token Checks

#### `isChannelParticipant(uint256 channelId, address participant) → bool`
Checks if an address is a participant in a specific channel.

**Parameters:**
- `channelId`: The channel ID to check
- `participant`: Address to verify

**Returns:**
- `true` if address is a participant, `false` otherwise

---

#### `isTokenAllowedInChannel(uint256 channelId, address token) → bool`
Checks if a token is allowed in a specific channel.

**Parameters:**
- `channelId`: The channel ID to check
- `token`: Token address to verify

**Returns:**
- `true` if token is allowed, `false` otherwise

---

#### `isSignatureVerified(uint256 channelId) → bool`
Checks if the channel's signature has been verified.

**Parameters:**
- `channelId`: The channel ID to check

**Returns:**
- `true` if signature is verified, `false` otherwise

---

## Deposit & Withdrawal Getters

#### `getParticipantTokenDeposit(uint256 channelId, address participant, address token) → uint256`
Returns the deposit amount for a specific participant and token.

**Parameters:**
- `channelId`: The channel ID
- `participant`: Participant address
- `token`: Token address

**Returns:**
- Deposited amount

---

#### `getChannelTotalDeposits(uint256 channelId, address token) → uint256`
Returns total deposits for a token across all participants in a channel.

**Parameters:**
- `channelId`: The channel ID
- `token`: Token address

**Returns:**
- Total deposited amount for the token

---

#### `getL2MptKey(uint256 channelId, address participant, address token) → uint256`
Returns the L2 Merkle Patricia Tree key for a participant-token pair.

**Parameters:**
- `channelId`: The channel ID
- `participant`: Participant address
- `token`: Token address

**Returns:**
- L2 MPT key

---

#### `getWithdrawableAmount(uint256 channelId, address participant, address token) → uint256`
Returns the withdrawable amount for a participant and token after channel closure.

**Parameters:**
- `channelId`: The channel ID
- `participant`: Participant address
- `token`: Token address

**Returns:**
- Withdrawable amount

---

#### `hasUserWithdrawn(uint256 channelId, address participant) → bool`
Checks if a participant has already withdrawn from a channel.

**Parameters:**
- `channelId`: The channel ID
- `participant`: Participant address

**Returns:**
- `true` if user has withdrawn, `false` otherwise

---

## System Analytics

#### `getTotalChannels() → uint256`
Returns the total number of channels created.

**Returns:**
- Total channel count

---

#### `nextChannelId() → uint256`
Returns the ID that will be assigned to the next channel.

**Returns:**
- Next available channel ID

---

#### `getChannelStats() → (uint256 initialized, uint256 open, uint256 active, uint256 closing, uint256 closed)`
Comprehensive channel statistics across all states.

**Returns:**
- `initialized`: Number of initialized channels
- `open`: Number of open channels  
- `active`: Number of active channels
- `closing`: Number of closing channels
- `closed`: Number of closed channels

---

#### `getSystemAnalytics() → (uint256 totalChannels, uint256 totalValueLocked, uint256 totalUniqueUsers, uint256 averageChannelSize, uint256 totalSlashed)`
System-wide analytics and metrics.

**Returns:**
- `totalChannels`: Total channels ever created
- `totalValueLocked`: Total value locked across all channels
- `totalUniqueUsers`: Number of unique users who have participated
- `averageChannelSize`: Average number of participants per channel
- `totalSlashed`: Total amount that has been slashed

---

#### `getTreasuryAddress() → address`
Returns the treasury address for fee collection.

**Returns:**
- Treasury address

---

#### `getTotalSlashedBonds() → uint256`
Returns total amount of bonds that have been slashed.

**Returns:**
- Total slashed amount

---

## User Analytics

#### `getUserTotalBalance(address user) → (address[] tokens, uint256[] balances)`
Returns a user's total balance across all channels and tokens.

**Parameters:**
- `user`: User address to query

**Returns:**
- `tokens`: Array of token addresses the user has deposited
- `balances`: Array of corresponding total balances

---

#### `getUserAnalytics(address user) → (uint256 totalChannels, uint256 activeChannels, uint256 tokenTypes, uint256 channelsAsLeader)`
Comprehensive user analytics.

**Parameters:**
- `user`: User address to analyze

**Returns:**
- `totalChannels`: Number of channels the user has joined
- `activeChannels`: Number of active channels the user is in
- `tokenTypes`: Number of different token types the user has deposited
- `channelsAsLeader`: Number of channels where user is the leader

---

#### `getChannelHistory(address user) → (uint256[] channelIds, ChannelState[] states, uint256[] joinTimestamps, bool[] isLeaderFlags)`
Channel participation history for a user.

**Parameters:**
- `user`: User address to query

**Returns:**
- `channelIds`: Array of channel IDs the user has participated in
- `states`: Array of corresponding channel states
- `joinTimestamps`: Array of when the user joined each channel
- `isLeaderFlags`: Array indicating if user was leader in each channel

---

## Advanced Search Functions

#### `batchGetChannelStates(uint256[] channelIds) → ChannelState[]`
Batch retrieval of channel states for multiple channels.

**Parameters:**
- `channelIds`: Array of channel IDs to query

**Returns:**
- Array of corresponding channel states

---

#### `searchChannelsByParticipant(address participant, ChannelState state, uint256 limit, uint256 offset) → (uint256[] channelIds, uint256 totalMatches)`
Search channels by participant with pagination and state filtering.

**Parameters:**
- `participant`: Participant address to search for
- `state`: State filter (use `ChannelState.None` for no filter)
- `limit`: Maximum number of results to return
- `offset`: Offset for pagination

**Returns:**
- `channelIds`: Array of matching channel IDs
- `totalMatches`: Total number of matches (for pagination)

---

#### `searchChannelsByToken(address token, uint256 minTotalDeposits, uint256 limit, uint256 offset) → (uint256[] channelIds, uint256[] totalDeposits, uint256 totalMatches)`
Search channels by token with minimum deposit filtering and pagination.

**Parameters:**
- `token`: Token address to search for
- `minTotalDeposits`: Minimum total deposits required
- `limit`: Maximum number of results to return
- `offset`: Offset for pagination

**Returns:**
- `channelIds`: Array of matching channel IDs
- `totalDeposits`: Array of total deposits for each channel
- `totalMatches`: Total number of matches (for pagination)

---

#### `getChannelLiveMetrics(uint256 channelId) → (uint256 activeParticipants, uint256 totalDeposits, uint256 averageDepositSize, uint256 timeActive, uint256 lastActivityTime)`
Real-time metrics for a specific channel.

**Parameters:**
- `channelId`: Channel ID to analyze

**Returns:**
- `activeParticipants`: Number of participants who have made deposits
- `totalDeposits`: Total number of deposits made to this channel
- `averageDepositSize`: Average deposit size across all tokens
- `timeActive`: How long the channel has been active (in seconds)
- `lastActivityTime`: Timestamp of last activity

---

## Validation Functions

#### `canUserDeposit(address user, uint256 channelId, address token, uint256 amount) → (bool canDeposit, string reason)`
Validates whether a user can make a deposit.

**Parameters:**
- `user`: User address
- `channelId`: Target channel ID
- `token`: Token address
- `amount`: Deposit amount

**Returns:**
- `canDeposit`: Whether the deposit is allowed
- `reason`: Explanation if deposit is not allowed

**Possible reasons:**
- "Channel does not exist"
- "User is not a participant in this channel"
- "Token is not allowed in this channel"
- "Channel is not open for deposits"
- "Deposit amount must be greater than 0"

---

#### `canUserWithdraw(address user, uint256 channelId) → (bool canWithdraw, string reason)`
Validates whether a user can withdraw from a channel.

**Parameters:**
- `user`: User address
- `channelId`: Target channel ID

**Returns:**
- `canWithdraw`: Whether withdrawal is allowed
- `reason`: Explanation if withdrawal is not allowed

**Possible reasons:**
- "Channel does not exist"
- "User is not a participant in this channel"
- "Channel is not closed"
- "User has already withdrawn from this channel"

---

## Manager Functions

### Target Contract Management

#### `isAllowedTargetContract(address targetContract) → bool`
Checks if a contract is allowed as a target for bridge operations.

**Parameters:**
- `targetContract`: Contract address to check

**Returns:**
- `true` if contract is allowed, `false` otherwise

---

#### `getTargetContractData(address targetContract) → TargetContract`
Returns configuration data for an allowed target contract.

**Parameters:**
- `targetContract`: Contract address to query

**Returns:**
- `TargetContract` struct with contract address and storage slot

---

### Function Registry

#### `getRegisteredFunction(bytes32 functionSignature) → RegisteredFunction`
Returns preprocessed data for a registered ZK circuit function.

**Parameters:**
- `functionSignature`: Function signature hash

**Returns:**
- `RegisteredFunction` struct with signature and preprocessed data

---

### Implementation Details

#### `getImplementation() → address`
Returns the current implementation contract address (for proxy pattern).

**Returns:**
- Implementation contract address

---

## Usage Examples

### Basic Channel Query
```solidity
// Get channel information
(address[] memory tokens, ChannelState state, uint256 participants, bytes32 root) = 
    bridge.getChannelInfo(channelId);

// Check if user can deposit
(bool canDeposit, string memory reason) = 
    bridge.canUserDeposit(user, channelId, tokenAddress, amount);
```

### User Analytics Dashboard
```solidity
// Get user's complete analytics
(uint256 totalChannels, uint256 activeChannels, uint256 tokenTypes, uint256 asLeader) = 
    bridge.getUserAnalytics(userAddress);

// Get user's channel history
(uint256[] memory channelIds, ChannelState[] memory states, 
 uint256[] memory timestamps, bool[] memory isLeader) = 
    bridge.getChannelHistory(userAddress);
```

### System Analytics
```solidity
// Get system-wide statistics
(uint256 totalChannels, uint256 tvl, uint256 users, uint256 avgSize, uint256 slashed) = 
    bridge.getSystemAnalytics();

// Get channel state distribution
(uint256 init, uint256 open, uint256 active, uint256 closing, uint256 closed) = 
    bridge.getChannelStats();
```

### Advanced Searches
```solidity
// Find all active channels for a user
(uint256[] memory channelIds, uint256 totalMatches) = 
    bridge.searchChannelsByParticipant(user, ChannelState.Active, 10, 0);

// Find channels with significant token deposits
(uint256[] memory channelIds, uint256[] memory deposits, uint256 totalMatches) = 
    bridge.searchChannelsByToken(tokenAddress, 1000 ether, 20, 0);
```

---

## Security Considerations

1. **View Functions Only**: All getter functions are view/pure and cannot modify state
2. **Access Control**: Manager functions require `onlyManager` modifier
3. **Data Validation**: Functions validate channel existence and parameter bounds
4. **Gas Optimization**: Batch functions available for multiple queries
5. **Pagination**: Search functions include pagination to prevent gas exhaustion

---

## Storage Location

The contract uses ERC-7201 storage pattern with the storage location:
```solidity
bytes32 private constant RollupBridgeCoreStorageLocation = 
    0x1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e4f5a6b7c8d9e0f1a00;
```

This ensures storage compatibility across contract upgrades while preventing storage collisions.
# Tokamak Private App Channels Bridge Specification

This document describes the current bridge implementation in this repository. It is intentionally implementation-oriented.

## 1. Scope

The bridge currently consists of five primary contract roles:

- `BridgeAdminManager`
- `DAppManager`
- `BridgeCore`
- `ChannelManager`
- `L1TokenVault`

It also depends on two proof verifiers:

- a Groth16 verifier for token-vault updates
- the Tokamak verifier for channel transaction execution

This specification describes the current deployed behavior rather than a future abstract model.

## 2. Global Configuration

### 2.1 Merkle-tree depth

The bridge currently supports exactly one Merkle-tree depth:

- `nMerkleTreeLevels = 12`

Any other value is rejected by `BridgeAdminManager`.

The bridge therefore assumes:

- `MAX_MT_LEAVES = 2^12 = 4096`

This value is used both for channel creation assumptions and for token-vault leaf-index derivation from storage keys.

### 2.2 Zero root

Every new channel starts from a zero-filled Merkle-root vector.

- The bridge does not compute the zero root on-chain.
- The zero root is hardcoded.
- `BridgeCore.createChannel(...)` builds an initial root vector of that zero root repeated `managedStorageAddresses.length` times.

## 3. DApp Registration Model

### 3.1 DApp-wide storage layout

`DAppManager.registerDApp(...)` registers one DApp at a time.

Each DApp stores one shared managed storage-address vector:

- every function in that DApp must use that same storage-address vector
- the DApp must contain exactly one token-vault storage address
- the token-vault storage address determines the DApp-wide `tokenVaultTreeIndex`

For each registered storage address, the bridge stores:

- `storageAddr`
- `preAllocatedKeys`
- `userStorageSlots`
- `isTokenVaultStorage`

### 3.2 Function metadata

For each function in a DApp, the bridge stores:

- `entryContract`
- `functionSig`
- `preprocessInputHash`
- `instanceLayout`

`instanceLayout` currently contains:

- `entryContractOffsetWords`
- `functionSigOffsetWords`
- `currentRootVectorOffsetWords`
- `updatedRootVectorOffsetWords`
- `storageWrites[]`

Each `storageWrites[]` entry contains:

- `aPubOffsetWords`
- `storageAddrIndex`

This means the bridge stores, per function:

- where the relevant fields live inside `aPubUser`
- which managed storage address each storage-write descriptor targets

The DApp manager does not currently expose any mutation path for an already-registered DApp. Registration is additive only.

### 3.3 Preprocess uniqueness

Within one DApp:

- every function must have a nonzero `preprocessInputHash`
- no two functions may share the same `preprocessInputHash`

This lets the channel manager resolve a function from submitted preprocess calldata by hash.

## 4. Channel Creation Model

`BridgeCore.createChannel(...)` creates one channel for one registered DApp.

Inputs:

- `channelId`
- `dappId`
- `leader`
- `asset`
- `aPubBlockHash`

At creation time the bridge:

1. reads the DApp's shared managed storage-address vector
2. reads the DApp's `tokenVaultTreeIndex`
3. reads the full registered function list for that DApp
4. builds the zero-filled initial root vector
5. deploys `ChannelManager`
6. deploys `L1TokenVault`
7. binds the vault to the channel manager

The resulting channel has:

- a fixed `dappId`
- a fixed managed storage-address vector
- a fixed `tokenVaultTreeIndex`
- a fixed `aPubBlockHash`
- a fixed zero-root genesis state

`ChannelManager` also stores `genesisBlockNumber = block.number` at deployment time.

## 5. Channel State Model

### 5.1 What the channel stores

The channel manager does not store the full current root vector.

Instead it stores:

- `currentRootVectorHash`
- the managed storage-address vector
- resolved function metadata needed at runtime
- the latest known token-vault leaves by derived leaf index

The full current root vector is supplied by callers and checked by hash.

### 5.2 Current root-vector observation

Before a proof-backed state transition changes the channel state hash, the channel manager emits:

- `CurrentRootVectorObserved(bytes32 rootVectorHash, bytes32[] rootVector)`

This is the bridge's current off-chain reconstruction hook for the pre-state root vector.

### 5.3 No root history array

The channel manager no longer stores root-vector history in contract storage.

- no historical root-vector array is maintained
- no root-history getter exists
- only the current root-vector hash is stored

## 6. Token-Vault Registration and Custody

Each channel has one `L1TokenVault`.

When a user first registers in that vault, the user supplies:

- an L2 token-vault key
- an initial L1 funding amount

The bridge then:

1. derives `leafIndex = uint256(key) % 4096`
2. checks global key uniqueness
3. checks per-channel leaf-index non-collision
4. stores the registration

The L1 token vault stores, per user:

- `l2TokenVaultKey`
- `leafIndex`
- `availableBalance`

The bridge also records:

- `registeredUserAtLeafIndex[leafIndex]`

This registration model is used only for L1 token-vault authorization and for derived leaf placement in the L2 token-vault tree.

## 7. Groth16 Token-Vault Update Flow

### 7.1 User-facing operations

The L1 token vault exposes:

- `registerAndFund(...)`
- `fund(...)`
- `deposit(...)`
- `withdraw(...)`
- `claimToWallet(...)`

### 7.2 Groth update data

`deposit(...)` and `withdraw(...)` both accept:

- `GrothProof`
- `GrothUpdate`

`GrothUpdate` currently contains:

- `currentRootVector`
- `updatedRoot`
- `currentUserKey`
- `currentUserValue`
- `updatedUserKey`
- `updatedUserValue`

The vault derives the Groth verifier public signals from:

- `currentRoot = currentRootVector[tokenVaultTreeIndex]`
- `updatedRoot`
- `updatedUserKey`
- `currentUserValue`
- `updatedUserValue`

### 7.3 Authorization and settlement

For `deposit(...)`:

- the registered key must match both `currentUserKey` and `updatedUserKey`
- `updatedUserValue > currentUserValue`
- `availableBalance >= updatedUserValue - currentUserValue`
- the Groth proof must verify

For `withdraw(...)`:

- the registered key must match both `currentUserKey` and `updatedUserKey`
- `currentUserValue > updatedUserValue`
- the Groth proof must verify

After a successful Groth verification:

- the vault updates `availableBalance`
- it calls `ChannelManager.applyVaultUpdate(...)`
- it emits `StorageWriteObserved(address storageAddr, uint256 storageKey, uint256 value)`

For Groth vault updates:

- `storageAddr` is the channel token-vault storage address
- `storageKey` is the registered L2 token-vault key
- `value` is the updated L2 token-vault value

The vault no longer emits `DepositAccepted` or `WithdrawalAccepted`.

## 8. Tokamak Channel Execution Flow

### 8.1 User-facing operation

The channel manager exposes:

- `executeChannelTransaction(TokamakProofPayload payload)`

`TokamakProofPayload` contains:

- `proofPart1`
- `proofPart2`
- `functionPreprocessPart1`
- `functionPreprocessPart2`
- `aPubUser`
- `aPubBlock`

### 8.2 Function resolution

At runtime the channel manager:

1. hashes the submitted preprocess calldata
2. resolves the function key from that hash
3. loads the cached function metadata
4. decodes `entryContract` and `functionSig` from `aPubUser`
5. checks that those decoded values match the resolved function key

This means the bridge binds:

- submitted preprocess calldata
- function identity
- `aPubUser` layout

inside one proof-acceptance path.

### 8.3 Channel-scoped verification checks

Before calling the Tokamak verifier, the channel manager checks:

- `keccak256(functionPreprocessPart1, functionPreprocessPart2) == preprocessInputHash`
- `keccak256(aPubBlock) == aPubBlockHash`
- `keccak256(currentRootVector decoded from aPubUser) == currentRootVectorHash`

It also decodes:

- `currentRootVector`
- `updatedRootVector`
- `entryContract`
- `functionSig`

from `aPubUser` using function-scoped offsets.

### 8.4 Storage-write decoding

Under the current synthesizer format, each storage write contributes four words in `aPubUser`:

- storage-key lower 16 bytes
- storage-key upper 16 bytes
- storage-value lower 16 bytes
- storage-value upper 16 bytes

For every registered storage-write descriptor in that function, `executeChannelTransaction(...)`:

1. decodes the storage key from `aPubUser`
2. decodes the value from `aPubUser`
3. resolves the target storage address from cached channel metadata
4. emits `StorageWriteObserved(address storageAddr, uint256 storageKey, uint256 value)`

If the write targets the channel token-vault storage address, the channel manager also:

1. derives `leafIndex = storageKey % 4096`
2. updates the cached latest token-vault leaf value at that derived leaf index

### 8.5 Token-vault-root consistency check

`executeChannelTransaction(...)` rejects a proof if:

- `updatedRootVector[tokenVaultTreeIndex] != currentRootVector[tokenVaultTreeIndex]`
- and the function has no registered token-vault storage write

This prevents a token-vault root change without a matching token-vault storage-write descriptor.

### 8.6 Accepted state mutation

After successful Tokamak verification:

- the channel emits `CurrentRootVectorObserved(...)` for the pre-state
- it emits `StorageWriteObserved(...)` for all decoded storage writes
- it updates the token-vault leaf cache for token-vault writes
- it sets `currentRootVectorHash = keccak256(updatedRootVector)`
- it emits `TokamakStateUpdateAccepted(functionSig, entryContract)`

The full updated root vector is not stored on-chain.

## 9. Runtime Metadata Caching

At channel creation, the channel manager copies into channel-local storage:

- allowed function references
- `preprocessInputHash`
- `entryContractOffsetWords`
- `functionSigOffsetWords`
- `currentRootVectorOffsetWords`
- `updatedRootVectorOffsetWords`
- resolved storage-write descriptors

The resolved storage-write descriptors are cached as:

- target `storageAddr`
- `aPubOffsetWords`
- whether the target is the token-vault storage

This avoids per-call external metadata lookups.

## 10. Events

The bridge currently emits the following state-transition events of interest:

### ChannelManager

- `TokenVaultBound(address tokenVault)`
- `CurrentRootVectorObserved(bytes32 rootVectorHash, bytes32[] rootVector)`
- `StorageWriteObserved(address storageAddr, uint256 storageKey, uint256 value)`
- `TokamakStateUpdateAccepted(bytes4 functionSig, address entryContract)`

### L1TokenVault

- `UserRegistered(address user, bytes32 key, uint256 leafIndex)`
- `AssetsFunded(address user, uint256 amount)`
- `StorageWriteObserved(address storageAddr, uint256 storageKey, uint256 value)`
- `AssetsClaimed(address user, uint256 amount)`

## 11. Current Invariants

The current implementation is intended to maintain the following invariants:

- every channel has exactly one token-vault storage tree
- every channel uses the managed storage-address vector inherited from exactly one DApp
- all functions within a DApp share that same managed storage-address vector
- every channel starts from the hardcoded zero-filled root vector
- only proof-backed paths may change `currentRootVectorHash` after genesis initialization
- Groth-backed vault updates must supply the full current root vector and a new token-vault root
- Tokamak-backed updates must supply a current root vector whose hash matches `currentRootVectorHash`
- token-vault root changes inside Tokamak execution require at least one registered token-vault storage write
- the bridge stores only the latest token-vault leaves, not historical leaf versions
- storage-write events emit storage keys, not derived leaf indices
- token-vault leaf indices are derived internally from storage keys only when the bridge must update the token-vault leaf cache
- DApp registration is additive only in the current implementation

## 12. Out of Scope

The following are not part of the current bridge implementation:

- proposal-pool execution
- fork-choice mechanics for delayed Tokamak settlement
- mutable DApp metadata updates
- mutable per-channel DApp surface updates after channel creation
- on-chain storage of full root-vector history
- generalized support for Merkle-tree depths other than `12`

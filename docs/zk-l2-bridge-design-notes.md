# ZK-L2 Ethereum Bridge Design Notes

## 1. Introduction

### 1.1 Document Status

This document is the working design notebook for the Tokamak Private App Channels bridge architecture.

It is intentionally more flexible than the white paper:

- it records the current design state
- it keeps user-driven revisions in a dated log
- it distinguishes current decisions from deferred work

If later user input conflicts with earlier text, the later user input takes priority.

### 1.2 Purpose

The purpose of this document is to keep one coherent technical reference while the design is still moving. It should be readable enough to support implementation work, but flexible enough to absorb partial or spontaneous design input without losing structure.

### 1.3 Writing Rule

This document records the current design, not every intermediate argument. Repetition is minimized on purpose. When a concept appears in more than one part of the system, it is defined once and then referenced consistently.

### 1.4 Terminology

The following terms are used throughout this document:

- `System`: Tokamak Private App Channels, used as the default shorthand for the overall architecture described here
- `L1`: Ethereum mainnet or the canonical settlement layer
- `L2`: a zk-proof-based state-machine instance managed by the bridge; each such L2 is called a channel
- `Channel`: an individual L2 instance managed by the L1 bridge contracts
- `Bridge`: the cross-layer system that binds L1 custody to L2 state transitions
- `Canonical custody`: the asset position that remains authoritative on L1
- `L1 token vault`: the per-channel vault managed by the L1 bridge contracts for token approval, transfer, deposit, and withdrawal
- `L2 token vault` or `L2 accounting vault`: the per-channel vault domain represented inside the L2 state, with its own dedicated Merkle tree
- `L2 token vault key`: the key under which a user's balance is represented in a channel's L2 token-vault tree
- `L2 token-vault leaf index`: the index of the user's token-vault leaf in the channel's L2 token-vault tree, deterministically derived from the user's L2 token-vault key
- `L2 app storage`: all channel storage other than the single L2 token-vault storage domain
- `Merkle-root vector`: the vector composed of the roots of the Merkle trees that concretely represent an L2 state
- `Groth zkp`: the Groth16-based proof system used for token-vault control
- `Tokamak zkp`: the Tokamak zk-EVM proof system used for channel transaction processing
- `DApp`: the set of smart contracts and functions designed for a specific channel application
- `DApp manager`: the bridge component that stores supported DApps, their storage layout, and their function-level proof metadata
- `Channel manager`: the per-channel L1 bridge component that verifies channel updates and enforces the channel's inherited DApp surface

### 1.5 Baseline Assumptions

The following assumptions are currently treated as baseline unless later inputs revise them:

- L1 is the canonical settlement and custody domain.
- The System is divided at the highest level into bridge contracts deployed on Ethereum and an L2 server with its own independent state.
- The L1 bridge manages multiple L2 instances, and each managed L2 instance is called a channel.
- Channels are autonomous, application-specific, and operationally isolated from one another.
- L2 is a state machine, and its concrete state is realized by one or more Merkle trees.
- An authoritative L2 checkpoint is therefore represented by a Merkle-root vector.
- Every accepted Merkle-tree update in a channel remains under L1 control.
- Each channel has its own L1 token vault.
- Each channel's L2 state contains exactly one dedicated L2 token-vault or L2 accounting-vault tree.
- Each channel may additionally contain multiple L2 app-storage domains.
- The System uses two proof systems: Groth zkp for token-vault control and Tokamak zkp for channel transaction execution.
- Proposal-pool operation, fork management, and token-economics-driven rewards or penalties are not part of the current version and remain future work.

## 2. Main Body

### 2.1 Current System Model

Tokamak Private App Channels are best understood as a validity-proof-based Ethereum Layer 2 system built from many application-specific channels rather than one shared execution domain.

Each channel is created, operated, and closed on Ethereum. A channel has:

- its own participant set
- its own state domain
- its own L1 token vault
- its own dedicated DApp surface
- one designated leader acting as an operational coordinator

The leader may publish channel creation, run a relay server, and close the channel, but must not gain unilateral control over participant assets or accepted state validity.

The design distinguishes between:

- off-chain operational progression inside the channel
- economically authoritative progression on Ethereum

This distinction is fundamental. Off-chain execution may prepare candidate state transitions, but only Ethereum-verified state changes become authoritative for assets, withdrawals, and final settlement.

### 2.2 State Model

The current definition of state is concrete rather than abstract. The substance of channel state is one or more Merkle trees.

Under this model:

- a channel state is represented by a Merkle-root vector
- a state update means an update of that vector
- the channel may contain many trees, but exactly one of them is the L2 token-vault or accounting-vault tree

The present storage split is:

- `L2 token vault storage`: the dedicated vault or accounting tree for asset positions
- `L2 app storage`: all other application storage

This split matters because privacy, data availability, and safe exit are not identical across those two storage classes.

### 2.3 L1 Bridge Responsibilities Per Channel

At the channel level, the L1 bridge currently manages the following information and control points:

- the current Merkle-root vector
- the current `keccak256` hash of that root vector
- the latest leaves of the channel's current L2 token-vault tree
- the channel's L1 token vault
- each user's registered L2 token-vault key for that channel
- each user's registered token-vault leaf index derived from that key
- each user's token balance record in that channel's L1 token vault
- the channel-scoped `aPubBlockHash` expected by Tokamak verification
- the DApp contract-and-function surface inherited by that channel
- the deposit and withdrawal entrypoints for that channel
- the verifier path for immediate Tokamak-zkp-based state updates

The bridge currently does not store obsolete historical leaves once they are no longer current.

The bridge no longer stores the latest leaves of every current tree in a channel. The storage rule is now narrower: it stores only the latest leaves of each channel's current L2 token-vault tree.

The bridge also no longer stores full root-vector history on-chain. When the root vector changes, the current vector remains in storage, its `keccak256` hash is stored, and the full updated vector is emitted through an event log instead of being appended to a persistent on-chain history array.

### 2.4 Vault Registration and Authorization Model

Each channel has its own L1 token vault. Users may approve and transfer tokens into that vault, and may later invoke `deposit` or `withdraw` to move their position between the L1 vault domain and the L2 token-vault domain.

When a user first enters a channel's L1 token-vault path, the user must provide:

- the target channel
- the L2 token-vault key to be used in that channel

The bridge then deterministically derives the token-vault leaf index from that key by following the `TokamakL2MerkleTrees.getLeafIndex` rule in `TokamakL2JS`, currently:

`Number(key % BigInt(MAX_MT_LEAVES))`

The current registration rules are:

- the registered L2 token-vault key is immutable once stored
- the same user must use a different L2 token-vault key for each channel
- every registered L2 token-vault key must be globally unique across the entire System
- within a given channel, no two registered users may share the same derived token-vault leaf index
- if the derived leaf index collides with an already-registered user in that channel, registration fails and the user must try a different L2 token-vault key

The L1 token vault therefore stores, per user and per channel:

- the registered L2 token-vault key
- the leaf index derived from that key
- the user's token balance record in that L1 token vault

This registration layer is part of the authorization path for both deposit and withdrawal.

### 2.5 Groth zkp for Token-Vault Control

The System uses a Groth16-based proof system for vault control.

Channel users must submit a Groth zkp proof when they want to:

- deposit tokens from the L1 token vault into the L2 token-vault domain
- withdraw tokens from the L2 token-vault domain back to the L1 token vault

The Groth proof is paired with an instance containing:

- the current root of the L2 token-vault tree
- the updated root of the L2 token-vault tree
- the current user key and value in the tree
- the updated user key and value in the tree

Under the current bridge implementation, the Groth-controlled token-vault leaf is treated as the raw stored user value. The user key affects authorization and leaf placement through the registered L2 token-vault key and its derived leaf index rather than through direct inclusion in the leaf value.

Under the current interpretation, successful Groth verification means:

- the claimed user balance existed in the L2 token-vault tree
- the claimed increment or decrement was applied correctly
- the resulting L2 token-vault tree update is valid

Accordingly, the L1 token vault currently acts as follows:

1. It receives the Groth proof and its instance.
2. It verifies the proof.
3. It interprets the instance.
4. It determines whether the signed token delta corresponds to deposit into or withdrawal from the L2 token-vault domain.
5. For withdrawal, it checks that the instance's current user key matches the user's registered L2 token-vault key in the corresponding L1 token vault.
6. For deposit, it checks that the instance's updated user key matches the user's registered L2 token-vault key in the corresponding L1 token vault.
7. It updates the channel's Merkle-root vector accordingly.

The current authorization rules are therefore:

- withdrawal requires a valid Groth proof and instance, plus equality between the instance's current user key and the user's registered L2 token-vault key
- deposit requires a valid Groth proof and instance, plus equality between the instance's updated user key and the user's registered L2 token-vault key

### 2.6 Tokamak zkp for Channel Transaction Processing

Tokamak zkp is used for channel transaction execution.

The current verifier interface is concrete:

- `proofPart1`
- `proofPart2`
- `functionPreprocessPart1`
- `functionPreprocessPart2`
- `aPubUser`
- `aPubBlock`

The bridge still exposes a user-facing `transaction instance` containing:

- the current channel Merkle-root vector
- the updated channel Merkle-root vector
- the entry contract
- the target function signature

However, under the current implementation, those transaction-instance fields are not passed into the verifier as a separate calldata object. They are encoded inside `aPubUser`, and the channel manager checks that the user-supplied transaction instance matches the relevant words of `aPubUser` before accepting the update.

Under the current `instance_description.json` layout produced by the Tokamak synthesizer:

- `aPubUser` begins with a function-specific sequence of storage-write words
- each storage write contributes four words:
  - tree-index lower 16 bytes
  - tree-index upper 16 bytes
  - storage-write lower 16 bytes
  - storage-write upper 16 bytes
- each storage write in that prefix is described off-chain by `instance_description.json` through:
  - the target storage address
  - the Merkle-tree index within that storage tree
- the bridge no longer hardcodes the relevant `aPubUser` offsets in the channel manager
- instead, each registered DApp function stores the following layout metadata, derived from `instance_description.json`:
  - `entryContractOffsetWords`
  - `functionSigOffsetWords`
  - `currentRootVectorOffsetWords`
  - `updatedRootVectorOffsetWords`
  - `storageWrites[]`, where each element carries the `aPubUser` word offset of that write descriptor and the index of the corresponding storage address within the DApp-wide managed storage vector
- channel creation copies the per-function offsets and `preprocessInputHash` into channel-local storage, so `executeChannelTransaction` can validate the `aPubUser` layout without external metadata calls; the `storageWrites[]` descriptors remain bridge-managed function metadata

where `n` is the number of channel storage trees represented in the root vector.

The old separate `channel instance` model is no longer used in the bridge contracts. Its channel-scoped role is currently replaced by `aPubBlock`, whose hash is fixed at channel creation and later checked by the channel manager.

Likewise, the bridge no longer stores `function instance` and `function preprocess` as separate verification objects. Under the current implementation, both are treated as being embedded in `functionPreprocessPart1` and `functionPreprocessPart2`. The bridge enforces their correctness by comparing `keccak256(abi.encode(functionPreprocessPart1, functionPreprocessPart2))` against the DApp-managed `preprocessInputHash`.

The channel manager also no longer stores the full current root vector. It stores only `currentRootVectorHash`. Before `executeChannelTransaction` or the Groth-backed token-vault update path mutates that hash, the full current root vector is emitted in `CurrentRootVectorObserved`. This keeps the contract state minimal while still making the pre-state reconstructible off-chain.

Under the current interpretation, successful Tokamak verification means:

- the user executed a transaction that called the specified function on the specified contract
- the execution followed the procedure defined by that function
- the execution succeeded
- the consumed channel Merkle-tree leaves were correct
- the resulting channel Merkle-tree updates were correct

In the current version, Tokamak-zkp-based channel updates are verified immediately rather than being placed into a proposal pool.

### 2.7 DApp Manager and Channel Inheritance

Each channel is operated for a specific DApp. In the current design, a DApp is the set of smart contracts and functions designed for that channel application.

The L1 bridge manages supported DApps through a DApp manager. For each supported contract and function, the DApp manager stores:

- the DApp storage layout
- the function-level `preprocessInputHash`
- the function-level `storageWrites`, where each entry fixes:
  - the index of the target storage address within the DApp-wide managed storage vector
  - the `aPubUser` word offset at which the corresponding storage-write tree index appears

All functions registered for the same DApp must share that same managed storage-address vector. Therefore every channel created for that DApp has a fixed root-vector length and a fixed token-vault tree index regardless of which DApp function a Tokamak proof executes.

Only the System administrator may add a new DApp to the DApp manager.

Each channel manager is currently created by selecting one registered DApp. In the present implementation, the channel inherits the full registered contract-and-function surface of that DApp rather than an arbitrary post-registration subset.

This is a hard validation boundary:

- channel users may perform channel activity only with respect to contracts and functions in the inherited DApp surface
- a Tokamak proof that refers to a function outside that inherited surface must fail through metadata mismatch
- such a failed proof must not update channel state

This means that the bridge-managed DApp metadata currently consists of storage layout plus per-function preprocess-input commitments and per-function storage-write descriptors, while the channel-owned metadata currently consists primarily of the channel's fixed token-vault position and the expected `aPubBlockHash`.

### 2.8 Comparative Execution Model

An ordinary L1-native DApp operates as follows:

1. The developer deploys the contracts directly to Ethereum.
2. Users submit transactions that call those contracts.
3. Ethereum validators re-execute those transactions.
4. If re-execution succeeds, Ethereum updates the DApp state.
5. Ethereum full nodes provide the data from which the DApp state can be reconstructed.

A DApp operating through the System works differently:

1. The developer registers the relevant contract-storage information and function information with the L1 bridge.
2. A channel operator opens a channel dedicated to that DApp.
3. A user creates and locally executes a transaction.
4. The user generates a Tokamak zkp proving correct execution.
5. The user submits the proof and the required public inputs to Ethereum without submitting the original transaction itself.
6. Ethereum validates the update by proof verification rather than by transaction re-execution.
7. If verification succeeds, Ethereum updates the channel state and the relevant bridge state.

The central architectural shift is therefore:

- ordinary L1 DApp approval condition: successful transaction re-execution
- System approval condition: successful proof verification

### 2.9 Privacy Model

The System provides baseline privacy because the original DApp transaction is not normally revealed to Ethereum validators or outside observers.

However, the System alone does not provide strong application-level privacy, because the channel operator still observes state data and may infer user activity from state changes.

To obtain stronger privacy, the DApp itself must follow a private-state model. Under that model, visible state does not directly expose the user-level meaning of transactions.

The current example is a zk-note-style DApp:

- balances are represented by note commitments rather than explicit account balances
- transfers consume input notes, mark them spent, and create new output-note commitments
- visible state shows commitments and spent markers rather than the clear transfer record

This yields a layered privacy structure:

- the System hides the original transaction
- the private-state DApp hides the user-level meaning of visible state

The current working definition of `complete privacy` is intentionally narrow:

1. `Transaction-content privacy`: observers without the original transaction cannot recover the user-level transaction content from what is published on Ethereum.
2. `State-semantic privacy`: observers who inspect DApp state cannot directly reconstruct the user-level meaning of state changes from visible state alone.

Under that definition:

- `System alone` satisfies transaction-content privacy but not state-semantic privacy
- `System + private-state DApp` satisfies both

This definition does not claim to remove all metadata leakage, such as timing, note linkage, access patterns, or operator-side observation.

### 2.10 Data Availability and Safe Exit

Data availability is asymmetric across storage classes.

For `L2 token-vault storage`:

- updates are governed by Groth zkp
- Groth instances expose the relevant before-and-after vault data
- vault-state changes are therefore traceable from Ethereum
- users can recover relevant token-vault state through Ethereum full nodes

For `L2 app storage`:

- users do not publish the application data to Ethereum in the same way
- users rely on the channel operator to provide that data
- the operator may fail to provide it or may provide it incorrectly

If L2 app-storage data becomes unavailable or unreliable, users may no longer be able to continue normal L2 application activity. However, this should not imply loss of token-vault safety. Users should still be able to rely on Ethereum-visible token-vault state to withdraw assets and escape the channel.

This creates the current operational recommendation:

- if operator-provided app data is weak or unreliable, more frequent use of the token-vault path improves safe-exit robustness

That recommendation is not free of tradeoffs, because heavier reliance on vault-state anchoring may increase overhead and reduce how much application logic remains purely in L2 app storage.

### 2.11 Withdrawal Latency

The System is a validity-proof-based architecture rather than a fault-proof-based architecture.

The current reasoning is:

- in a fault-proof model, absence of a fault proof over a long window raises confidence but does not positively prove validity
- in a validity-proof model, successful proof verification positively establishes validity for the submitted state transition

Therefore, under the current design direction, withdrawal latency is expected to be dominated by:

- proof generation time
- normal Ethereum inclusion time

rather than by a long challenge window.

This does not mean withdrawal is literally zero-latency. It means the design avoids the protocol-imposed waiting window characteristic of challenge-window-based fault-proof exits.

### 2.12 Core Lifecycle

#### 2.12.1 Channel Creation

1. Participants agree to form a channel for a specific DApp.
2. A leader publishes the channel on Ethereum.
3. L1 fixes the channel's expected `aPubBlockHash`.
4. L1 associates the channel with the selected DApp and the storage-address vector derived from that DApp.

#### 2.12.2 Channel Entry

1. A user opens or joins a channel through a state change.
2. The resulting new state is submitted to Ethereum for validation.
3. The user is considered safely inside the channel only after Ethereum verifies that state.

#### 2.12.3 Deposit and Funding

1. A participant enters the channel's Ethereum-side custody path.
2. If this is the participant's first entry into that channel's vault path, the participant supplies the L2 token-vault key to be used in that channel.
3. The bridge derives the token-vault leaf index from that key by the `TokamakL2MerkleTrees.getLeafIndex` rule.
4. The bridge checks global key uniqueness and per-channel leaf-index non-collision.
5. If the derived leaf index collides inside that channel, registration fails and the participant must try a different key.
6. If accepted, L1 stores the user's key, derived leaf index, and token balance record in that channel's L1 token vault.
7. The participant approves and transfers tokens to the selected channel's L1 token vault.
8. The participant invokes `deposit` on that L1 token vault.
9. The participant submits a Groth proof and instance for the L2 token-vault tree update.
10. L1 checks that the instance's updated user key matches the registered key.
11. The funding event is reflected in a new candidate state.
12. Until Ethereum verifies that state, the participant's authoritative asset position remains based on the last verified state.
13. After verification, the new asset position becomes authoritative on Ethereum.

#### 2.12.4 In-Channel State Transition

1. A user creates a transaction that calls one of the channel's permitted functions.
2. The user executes that transaction on the L2 server.
3. Execution updates one or more Merkle trees and therefore updates the Merkle-root vector.
4. The user generates the Tokamak proof and transaction instance.
5. The user submits them directly to the relevant channel manager on L1.
6. The channel manager checks that the user-supplied transaction instance matches the relevant fields encoded inside `aPubUser`.
7. The channel manager checks that the submitted preprocess input matches the DApp-managed `preprocessInputHash`, and that `aPubBlock` matches the channel-managed `aPubBlockHash`.
8. If the proof verifies, L1 immediately updates the channel's Merkle-root vector.
9. If the proof fails or the function is outside the inherited DApp surface, the update is rejected and the previous verified state remains authoritative.

#### 2.12.5 Channel Closure

1. The leader or another authorized actor initiates closure according to the channel rules.
2. Closure settlement must still follow the verified-state model on Ethereum.
3. Final balances and rights are determined by the last Ethereum-verified state.

#### 2.12.6 Withdrawal

1. The participant invokes withdrawal through the channel's L1 token vault.
2. The participant submits a Groth proof and instance for the L2 token-vault tree update.
3. L1 checks that the instance's current user key matches the participant's registered L2 token-vault key.
4. Withdrawal entitlement is derived from the last Ethereum-verified state.
5. If verification succeeds, assets are released from L1 custody.

### 2.13 Invariants

The following invariants summarize the current design:

- no asset leaves L1 custody without a bridge-authorized settlement path
- no candidate state becomes economically authoritative on Ethereum without proof verification
- deposit and withdrawal accounting must remain conservation-safe across layers
- each channel must have its own L1 token vault managed by the bridge
- each channel must have exactly one dedicated L2 token-vault or accounting-vault tree inside its L2 state
- every authoritative L2 state must be representable as a Merkle-root vector
- every L2 state update must correspond to an update of that vector
- every channel Merkle-tree update must remain under L1 control
- every L2 vault-tree update must remain under L1 control
- every deposit or withdrawal must be backed by a valid Groth proof and instance
- every deposit must require that the Groth instance's updated user key match the user's registered L2 token-vault key
- every withdrawal must require that the Groth instance's current user key match the user's registered L2 token-vault key
- every registered token-vault leaf index must be deterministically derived from the registered L2 token-vault key by the `TokamakL2MerkleTrees.getLeafIndex` rule
- no two registered users in the same channel may share the same derived token-vault leaf index
- every channel transaction update must be backed by a Tokamak proof whose `aPubUser` fields match the submitted transaction instance
- every channel transaction update must be backed by the correct channel-scoped `aPubBlock`
- every channel transaction update must be backed by the correct preprocess input for the called function
- L1 must preserve the current Merkle-root vector for each channel and expose the accepted change stream through event logs
- L1 must store the latest leaves of each channel's current L2 token-vault tree while not retaining obsolete historical leaves
- only the System administrator may add a new DApp to the DApp manager
- a channel manager may accept Tokamak-zkp-based updates only for the contract-and-function surface it inherited from the selected DApp
- a function-metadata mismatch must prevent channel-state update acceptance
- opening a channel or entering a channel must not become final until Ethereum verifies the resulting new state
- failure of L2 app-storage availability must not prevent safe withdrawal according to the last accessible token-vault state
- the leader must not gain unilateral control over participant assets merely by hosting the relay server or publishing transactions

### 2.14 Deferred Work and Open Questions

The following questions remain open:

- the exact operating principles of the `deposit` and `withdraw` functions beyond the current high-level model
- whether `L2 token vault` should be interpreted as real L2 token custody or as an accounting-vault abstraction
- the exact operational meaning of the phrase `last verifiable state`
- the exact relation between provisional in-channel execution and verified Ethereum state
- the exact recovery, migration, or rotation policy if a user loses access to an immutable registered L2 token-vault key
- the exact storage and lookup design for enforcing global uniqueness of all registered L2 token-vault keys
- the exact storage and lookup design for enforcing per-channel non-collision of derived token-vault leaf indices
- whether channel operators alone are sufficient as practical data providers for state reconstruction, or whether the System needs stronger data-availability guarantees
- the exact residual privacy leakage that may remain even in a private-state DApp
- the exact operational tradeoff between frequent token-vault usage for safer escape and richer reliance on L2 app storage for application efficiency
- whether a channel manager's inherited DApp surface is immutable after channel creation or can be versioned later
- the exact lifecycle and governance process for updating per-channel `aPubBlockHash` and bridge-managed DApp preprocess metadata
- the exact Ethereum scalability cost of storing the latest L2 token-vault-tree leaves for many channels on L1
- the exact future proposal-pool design, if delayed Tokamak-zkp verification is ever reintroduced
- the exact tokenomics required to support any future proposal-pool operation, fork resolution, penalties, and rewards

### 2.15 Historical Input Record

The following condensed log records which major parts of the design were introduced directly by user input.

#### 2.15.1 2026-03-17

- The design target is a bridge for a zk-proof-based Ethereum L2.
- The documentation process should absorb spontaneous ideas while maintaining coherent system structure.
- `docs/spec.md` should be treated as provisional rather than absolute.
- Tokamak Private App Channels are autonomous private Layer 2 channels created, operated, and closed on Ethereum.
- Channels are app-specific, operationally independent, and use zero-knowledge proofs for state validity.
- One participant acts as channel leader for publication, relay operation, and closure coordination.
- Channel state transitions are generated off-chain and validated on Ethereum.
- For DeFi channels, participant assets are protected by proof-verified state progression, and asset balances on Ethereum change only when new state is verified.
- The term `System` refers to Tokamak Private App Channels.
- The System is divided into L1 bridge contracts and an L2 server with independent state.
- L2 is a state machine realized by Merkle trees and represented by a Merkle-root vector.
- The L1 bridge manages multiple channels by storing the current root vector, its hash, and accepted state-update events.
- Each channel has its own L1 token vault and one dedicated L2 token-vault or accounting-vault tree.
- Every accepted Merkle-tree update in a channel is under L1 control.
- The System uses Groth zkp for token-vault control and Tokamak zkp for channel transaction processing.
- Proposal-pool operation and tokenomics were deferred to future work.

#### 2.15.2 2026-03-18

- Tokamak-zkp-based channel updates are verified immediately on L1 in the current version.
- Tokamak zkp is currently submitted through the verifier interface `proofPart1`, `proofPart2`, `functionPreprocessPart1`, `functionPreprocessPart2`, `aPubUser`, and `aPubBlock`.
- Supported DApps are managed by the bridge, and channels currently inherit the full registered contract-and-function surface of the selected DApp.
- Each channel manager's L1 token vault stores the user's tokens together with the user's registered L2 token-vault key for that channel.
- The same user must use a different L2 token-vault key for each channel, and those keys are globally unique across the System.
- Deposit and withdrawal require Groth proof validation together with key matching against the registered L2 token-vault key.
- Compared with an ordinary L1-native DApp, the System replaces validator-side transaction re-execution with validator-side zkp verification.
- The System provides baseline privacy by hiding original transactions, but stronger privacy requires a private-state DApp design.
- `Complete privacy` was given a narrow working definition based on transaction-content privacy and state-semantic privacy.
- L2 token-vault-storage changes are Ethereum-traceable through Groth-instance data, while L2 app-storage availability depends on the channel operator.
- Withdrawal waiting time is expected to be dominated by proof generation and Ethereum inclusion rather than by a challenge window.

#### 2.15.3 2026-03-22

- Each channel's L1 token vault also records the token-vault leaf index derived from the user's registered L2 token-vault key.
- That leaf index is not chosen independently; it is determined by the `TokamakL2MerkleTrees.getLeafIndex` rule in `TokamakL2JS`, currently `Number(key % BigInt(MAX_MT_LEAVES))`.
- The bridge must check not only global key uniqueness but also whether the derived leaf index collides with another registered user's leaf index in that channel.
- Registration succeeds only if no such per-channel leaf-index collision exists.
- If the derived leaf index collides in that channel, the user must try a different L2 token-vault key.
- L1 no longer stores the latest leaves of all current channel trees; it stores only the latest leaves of each channel's current L2 token-vault tree.
- L1 no longer stores full root-vector history in storage; it stores the current root vector and its hash, and emits each accepted root-vector update as an event.
- The old separate `channel instance` object is no longer used by the bridge; channel-scoped verification context is currently represented by `aPubBlockHash`.
- The old separate `function instance` and `function preprocess` objects are currently treated as being embedded in the submitted preprocess calldata and enforced through `preprocessInputHash`.
- The current bridge implementation reads transaction-instance fields back out of `aPubUser` using function-scoped layout metadata derived from `instance_description.json` and cached in each channel. Under the current synthesizer format, each registered storage write still contributes four `aPubUser` words, but the bridge now stores the exact per-function `aPub` offsets rather than deriving the updated-root position from prefix length alone.

## 3. Conclusion

### 3.1 Current Working Conclusions

At the current stage, the System is best understood as a proof-based Ethereum settlement architecture with the following shape:

- Ethereum remains the canonical layer for custody, validity acceptance, and final settlement.
- Each channel is an application-specific L2 state machine represented by a Merkle-root vector.
- Every accepted Merkle-tree update remains under L1 control.
- Token-vault authorization depends on both proof validity and bridge-managed registration of L2 token-vault keys and their derived leaf indices.
- Tokamak-zkp verification depends not only on user-supplied transaction data but also on bridge-managed metadata, including the channel-scoped `aPubBlockHash` and the DApp-managed preprocess-input commitments.
- Privacy and data availability are layered rather than absolute: the System hides original transactions from L1 observers, but stronger privacy and stronger application-data guarantees require additional DApp design or protocol mechanisms.

### 3.2 Current Working Decisions

The following decisions are stable enough to be treated as the current working position of this document:

- Tokamak-zkp-based channel updates are verified immediately on L1 in the current version.
- Proposal-pool operation, fork handling, and tokenomics-linked incentives are not part of the current version.
- Each channel has exactly one L2 token-vault storage domain and may additionally contain multiple L2 app-storage domains.
- The bridge stores only the latest leaves of each channel's current L2 token-vault tree.
- Users must register an immutable per-channel L2 token-vault key.
- The bridge derives the corresponding token-vault leaf index by the `TokamakL2MerkleTrees.getLeafIndex` rule and rejects per-channel collisions of those derived indices.
- The bridge treats `aPubBlockHash` as channel-owned metadata and `preprocessInputHash` plus per-function storage-write descriptors as DApp-managed metadata.
- The bridge extracts current roots, updated roots, entry contract, and function signature from `aPubUser` and requires them to match the submitted transaction instance.
- Safe channel escape currently depends on the token-vault path rather than on full L2 app-storage availability.

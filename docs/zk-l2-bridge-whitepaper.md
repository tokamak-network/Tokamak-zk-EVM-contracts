# Tokamak Private App Channels White Paper

Last updated: 2026-03-18

## Table of Contents

1. Introduction
2. Main Body
   2.1 Terminology
   2.2 System Overview
   2.3 Comparison with an Ordinary L1-Native DApp
   2.4 Architecture
   2.5 State and Storage Model
   2.6 Proof Systems
   2.7 Core Operational Flows
   2.8 Privacy Model
   2.9 Data Availability and Safe Exit
   2.10 Security Properties and Design Tradeoffs
3. Conclusion

## 1. Introduction

Privacy Layer 2 systems are Ethereum-adjacent systems that try to preserve the settlement and asset-safety properties of Ethereum while reducing how much user activity must be exposed during execution. Common examples in this broad area include private rollups, application-specific channels, and confidential transfer systems. The field matters because many real applications need more than raw throughput: they need lower execution cost, stronger control over information disclosure, and a way to keep using Ethereum as the place where assets ultimately remain secured. Such systems can be used for payments, trading, games, social applications, and many other kinds of application-specific environments.

In this paper, a `channel` is the basic operating unit of Tokamak Private App Channels. A channel is a dedicated Layer 2 environment opened for one application rather than one shared global environment for every application. This paper focuses on an architecture in which many such channels can coexist while remaining separate from one another in operation and state.

The first problem that Tokamak Private App Channels aim to solve is to make proof-based Layer 2 channels easy to operate. Here, `easy to operate` means that an application developer should be able to open a dedicated channel by building ordinary Ethereum smart contracts, without needing to become an expert in proof construction, proof security, or the detailed operational assumptions of a Layer 2 protocol. The goal is to lower the barrier from protocol engineering to application development.

The System addresses that problem by dividing responsibilities. Ethereum remains the place where assets are settled and accepted state changes are confirmed, while the channel provides the dedicated execution environment for one application. Under this division, the developer focuses on the application itself and the System provides the shared framework that lets the application run inside a proof-based channel.

From the user's point of view, the System also addresses a privacy problem. In this introduction, `privacy baseline` means that the original user transaction does not need to be openly revealed during settlement, and the user does not need to hand proof generation to a third party. Instead, the user can generate the needed proof directly and submit it without disclosing the original transaction itself. This does not by itself solve every privacy problem, but it does define the System's basic privacy promise.

Another term that matters throughout this paper is `data availability`. In simple terms, this means whether users can actually obtain the state information they need in order to continue using a channel or to leave it safely. The current design makes a distinction between asset-related information, which remains more directly recoverable from Ethereum, and broader application information, which depends more heavily on the channel operator. This distinction is important for understanding both safe exit and the limits of the present design.

The main features of the current design are concise:

- `Usability`: developers can open dedicated channels for many kinds of applications without building a custom proof framework from scratch.
- `Security`: assets and authoritative state changes remain anchored to Ethereum rather than to the channel operator.
- `Anonymity`: the System provides a basic privacy layer by hiding the original user transaction from outside observers, and it avoids outsourcing proof generation to third parties.
- `Withdrawal latency`: users are not forced to wait through a long dispute period before exiting; delay is expected to come mainly from proof generation and normal Ethereum processing.
- `Data availability`: asset-related state remains practically recoverable from Ethereum, while broader application data still depends more heavily on the channel operator.

This white paper presents the current architecture in a concise form. It focuses on the present operating model rather than on historical design notes, and it intentionally allows the introduction to summarize core arguments that are developed in more detail in the main body.

## 2. Main Body

### 2.1 Terminology

The following terms are used throughout this paper:

- `System`: Tokamak Private App Channels as a whole
- `channel`: one independent L2 state-machine instance managed by the L1 bridge
- `L1 bridge`: the Ethereum-deployed contract system that manages channels, DApps, vaults, and proof verification
- `channel manager`: the bridge component that manages one specific channel
- `L2 server`: the off-chain execution environment that coordinates channel activity
- `Merkle-root vector`: the authoritative commitment to a channel state, formed from the roots of that channel's Merkle trees
- `L2 token vault`: the dedicated vault or accounting storage tree for user asset positions inside a channel
- `L2 app storage`: all non-vault storage used by the channel's DApp logic
- `Groth zkp`: the Groth16-based proof system used for token-vault updates
- `Tokamak zkp`: the Tokamak zk-EVM proof system used for channel transaction execution
- `DApp manager`: the bridge component that stores supported DApps and their function-specific proof metadata

### 2.2 System Overview

The System has two top-level parts:

- L1 bridge contracts deployed on Ethereum
- an L2 server that coordinates private execution for multiple channels

Each channel is an independent L2 state-machine instance managed by the bridge. A channel is created for one specific DApp, has its own participant set, and has one designated leader who acts as an operational coordinator. The leader may publish channel creation, run the relay server, and close the channel, but does not have unilateral authority over user assets or state validity.

The authoritative state of a channel is represented as a Merkle-root vector. Each channel may contain multiple Merkle trees, and an L2 state update means an update of that vector. Even though channels are operationally independent from one another, every accepted state update remains under L1 control.

### 2.3 Comparison with an Ordinary L1-Native DApp

An ordinary L1-native DApp works as follows:

1. The developer deploys smart contracts directly to Ethereum.
2. Users submit transactions that call those contracts.
3. Ethereum validators re-execute the transactions.
4. If re-execution succeeds, Ethereum updates the DApp storage roots.
5. Ethereum full nodes provide the data from which the DApp state can be reconstructed.

Under that model, DApp users propose state updates, Ethereum validators approve them, and successful transaction re-execution is the state-update condition.

A DApp operating through the System works differently:

1. The developer registers the DApp's relevant storage and function information with the L1 bridge.
2. A channel operator opens a channel dedicated to that DApp.
3. A user creates and locally executes a transaction.
4. The user generates a Tokamak zkp proving that the transaction executed correctly.
5. The user submits the proof and the required public inputs to Ethereum without submitting the original transaction itself.
6. Ethereum validators verify the proof rather than re-executing the original transaction.
7. If verification succeeds, Ethereum updates the channel state and the relevant bridge state.

Under the System model, DApp users still propose state updates and Ethereum validators still approve them, but the approval condition changes from transaction re-execution to proof verification. This is the central architectural shift of the System.

### 2.4 Architecture

The L1 bridge layer manages channels, asset custody, proof verification, and the Ethereum-visible commitment trail of channel state transitions. It also manages the supported DApps of the System and enforces which contracts and functions each channel may use.

The L2 server is the off-chain environment in which private channel execution occurs. It maintains candidate channel state, coordinates user activity, and produces the witness data required for proof generation. It is not a trust anchor. Its role is operational coordination, not authoritative settlement.

The DApp manager is the bridge component that stores the supported DApps and their function-specific Tokamak-zkp metadata. Only the System administrator may add a new DApp. Each channel manager inherits only a subset of contracts and functions from the DApp manager. A channel may therefore accept updates only for the DApp surface that it inherited at channel creation.

This inheritance rule is a hard validation boundary. If a user submits a Tokamak zkp for a contract function outside the channel's inherited subset, verification must fail and the channel state must not change.

### 2.5 State and Storage Model

Each channel has exactly one dedicated L2 token-vault storage domain. It may also contain multiple additional storage domains for application logic. All non-vault storage is grouped under the term `L2 app storage`.

The L2 token vault is linked to a per-channel L1 token vault. The L1 token vault stores:

- the user's channel-bound token position
- the user's registered L2 token-vault key for that channel

This registration model has four current rules:

1. A user must choose the target channel and supply the L2 token-vault key when first placing tokens into that channel's L1 token vault.
2. The registered key is immutable once stored.
3. The same user must use a different L2 token-vault key for each channel.
4. Every registered L2 token-vault key must be globally unique across the entire System.

Because the System uses one or more Merkle trees per channel, the authoritative checkpoint of a channel is the vector of current Merkle roots rather than one monolithic state root. This model supports both vault accounting and application-specific storage while preserving a bridge-visible commitment structure on Ethereum.

### 2.6 Proof Systems

The System uses two distinct proof systems.

`Groth zkp` is used for token-vault control. Its instance contains:

- the current root of the L2 token-vault tree
- the updated root of the L2 token-vault tree
- the current user key and value
- the updated user key and value

The user leaf is the Poseidon hash of the user key and user value. A successful Groth verification means that the claimed balance existed, the claimed increment or decrement was applied correctly, and the resulting L2 token-vault tree update is valid.

Groth verification also enforces key matching:

- for withdrawal, the instance's current user key must match the user's registered L2 token-vault key
- for deposit, the instance's updated user key must match the user's registered L2 token-vault key

`Tokamak zkp` is used for channel transaction processing. Under the current bridge implementation, the verifier interface accepts:

- a proof split into two calldata arrays
- a preprocess input split into two calldata arrays
- `aPubUser`
- `aPubBlock`

The bridge treats `aPubBlock` as channel-scoped metadata and treats the submitted preprocess input as the carrier of the function-scoped verification metadata. The bridge stores and checks:

- a channel-scoped `aPubBlockHash`
- a function-scoped `preprocessInputHash`
- a function-scoped `storageWrites` list, where each entry fixes:
  - the target storage address
  - the Merkle-tree index written within that storage tree

The transaction-instance fields relevant to bridge state updates are encoded inside `aPubUser`. Under the current synthesizer layout, the bridge reads from `aPubUser`:

- the current channel Merkle-root vector
- the updated channel Merkle-root vector
- the entry contract
- the target function signature

The updated root-vector offset is no longer treated as an independent bridge parameter. It is derived from the length of the function-scoped storage-write prefix encoded at the front of `aPubUser`. Under the current synthesizer format, each storage write contributes four words to that prefix: tree-index lower/upper and storage-write lower/upper.

A successful Tokamak verification means that the specified contract function was executed correctly, the execution succeeded, the consumed leaves were correct, and the resulting Merkle-tree updates were valid.

### 2.7 Core Operational Flows

`Channel creation and entry`

1. Participants agree to form a channel for a specific DApp.
2. A leader publishes the channel on Ethereum.
3. The channel inherits its permitted DApp surface from the bridge-managed DApp metadata.
4. Entry becomes economically valid only after Ethereum verifies the resulting state transition.

`In-channel transaction execution`

1. A user executes a DApp transaction locally on the channel server.
2. The system derives the resulting Merkle-tree update and produces witness data.
3. The user generates a Tokamak zkp and submits it with `aPubUser`, `aPubBlock`, and the preprocess input required by the verifier.
4. The channel manager checks that the submitted preprocess input matches the DApp-managed metadata, that `aPubBlock` matches the channel-managed metadata, and that the transaction-instance fields decoded from `aPubUser` are acceptable for the current channel state.
5. If the proof verifies, Ethereum immediately updates the channel's Merkle-root vector.
6. If the proof fails, the previous verified state remains authoritative.

`Deposit`

1. The user registers an L2 token-vault key if this is the first token-vault interaction for the channel.
2. The user places assets into the channel's L1 token vault.
3. The user submits a Groth proof for the L2 token-vault tree update.
4. The bridge verifies the proof and checks that the instance's updated user key matches the registered vault key.
5. If verification succeeds, the channel's vault-related state is updated.

`Withdrawal`

1. The user invokes withdrawal from the channel's L1 token vault.
2. The user submits a Groth proof for the L2 token-vault tree update.
3. The bridge verifies the proof and checks that the instance's current user key matches the registered vault key.
4. Withdrawal entitlement is derived from the last Ethereum-verified state.
5. If verification succeeds, assets are released from L1 custody.

### 2.8 Privacy Model

The System provides baseline privacy because the original transaction is not normally revealed to Ethereum validators or outside observers. However, the System alone does not provide strong application-level privacy, because the channel operator still observes state data and may infer user activity from state changes.

To obtain stronger privacy, the DApp itself must follow a private-state model. Under that model, visible state does not directly expose the user-level meaning of transactions.

The current example is a zk-note-style DApp. In that model:

- balances are represented by note commitments rather than explicit account balances
- transfers consume input notes, mark them spent, and create new output-note commitments
- visible state shows commitments and spent markers rather than the clear transfer record

This yields a complementary privacy structure:

- the System hides the original transaction
- the private-state DApp hides the user-level meaning of state data

For the purpose of this white paper, `complete privacy` is defined narrowly by two criteria:

1. `Transaction-content privacy`: observers without the original transaction cannot recover the user-level transaction content from what is published on Ethereum.
2. `State-semantic privacy`: observers who inspect DApp state cannot directly reconstruct the user-level meaning of state changes from visible state alone.

Under this working definition:

- `System alone` satisfies transaction-content privacy but not state-semantic privacy
- `System + private-state DApp` satisfies both

Under that narrow definition, `System + private-state DApp` achieves complete privacy, while `System alone` does not.

This definition is intentionally narrow. It does not claim to remove all metadata leakage, such as timing, note linkage, access patterns, or operator-side observation.

### 2.9 Data Availability and Safe Exit

Data availability is asymmetric across storage classes.

For `L2 token-vault storage`:

- updates are governed by Groth zkp
- Groth instances expose the relevant before-and-after vault data
- the corresponding vault-state changes are therefore traceable from Ethereum
- users can recover relevant token-vault state through Ethereum full nodes

For `L2 app storage`:

- users do not publish the application data to Ethereum in the same way
- users rely on the channel operator to provide that data
- the operator may fail to provide it, or may provide it incorrectly

If L2 app-storage data becomes unavailable or unreliable, users may no longer be able to continue normal L2 application activity. However, this does not imply loss of token-vault safety. Users can still rely on Ethereum-visible token-vault state to withdraw assets and escape the channel.

This yields an operational recommendation: when operator data availability is weak, frequent use of the token-vault path improves safe-exit robustness. That recommendation is not free of tradeoffs, because heavier reliance on vault-state anchoring may increase overhead and reduce how much application logic remains purely in L2 app storage.

### 2.10 Security Properties and Design Tradeoffs

The current architecture aims to preserve the following properties:

- canonical custody remains on Ethereum
- no state update becomes economically authoritative without proof verification
- each channel remains isolated from failures in other channels
- the leader remains an operational coordinator rather than a trust anchor
- DApp execution is constrained to the channel's inherited contract-and-function subset
- token-vault authorization is bound to immutable registered vault keys
- safe exit remains available even when app-storage availability fails

The current design also creates explicit tradeoffs:

- stronger safe-exit robustness favors more frequent use of token-vault storage
- stronger privacy requires private-state DApp design, not only System-level privacy
- global uniqueness of vault keys simplifies authorization but introduces registry and recovery complexity
- immediate Tokamak verification simplifies validity finality but leaves proposal-pool economics as future work

## 3. Conclusion

Tokamak Private App Channels define a validity-proof-based Ethereum Layer 2 architecture in which private, application-specific channels execute off-chain while Ethereum remains the canonical layer for custody, state validity, and final settlement. The bridge manages channels, DApps, proof metadata, token vaults, and the Ethereum-visible commitment trail of each channel. The L2 server coordinates execution, but authoritative state changes occur only after proof verification on L1.

The most important architectural consequence is that the System replaces validator-side transaction re-execution with validator-side proof verification. This makes channel execution private by default, shortens withdrawal latency relative to fault-proof challenge-window models, and preserves a clean settlement boundary on Ethereum. At the same time, the System does not by itself solve all privacy and data-availability problems. Strong privacy requires a private-state DApp model, and strong application-state availability requires assumptions or mechanisms beyond the token-vault path.

The current design is therefore best understood as a layered model. Ethereum guarantees custody, proof-verified state acceptance, and recoverable token-vault state. The System provides private execution and proof-based state advancement. DApp design determines whether application-state semantics remain exposed or hidden.

The main item of future work discussed in the design notes is the deferred proposal-pool model together with its rewards, penalties, and token economics. In the current version, Tokamak-zkp-based channel updates are verified immediately on L1, so that machinery is intentionally out of scope. If the System later reintroduces proposal-pool operation, its token-economics design may also serve as one mechanism for strengthening the practical availability and liveness of L2 app storage by creating explicit incentives to resolve forks, verify pending updates, and maintain reliable channel operation. Until those rules are specified precisely, however, that layer should remain outside the current white paper's operative model.

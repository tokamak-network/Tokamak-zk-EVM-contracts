# ZK-L2 Ethereum Bridge Design Notes

## 1. Introduction

### 1.1 Document Status

- Document type: living design paper
- Scope: zk-proof-based Ethereum Layer 2 bridge architecture
- Last updated: 2026-03-17
- Authoring mode: incremental capture of evolving design ideas

### 1.2 Purpose

This document is the working design paper for the bridge system. It is written in a paper-like form so that spontaneous design inputs can be absorbed without losing architectural coherence. The document therefore aims to do two things at once: preserve the evolving intent of the system and present that intent through a structured technical argument.

### 1.3 Method and Writing Rules

The current writing method follows these rules:

- preserve the substance of each user input, even when the wording is informal
- normalize terminology when different phrases refer to the same concept
- distinguish assumptions, interpretations, working decisions, and open questions
- keep all prose and comments in English
- prefer architectural clarity over premature implementation detail

### 1.4 Terminology

The following terms are used throughout this document:

- `System`: Tokamak Private App Channels, used as the default shorthand for the overall architecture described in this document
- `L1`: Ethereum mainnet or the canonical settlement layer
- `L2`: a zk-proof-based state-machine instance managed by the bridge; each such L2 is called a channel
- `Channel`: an individual L2 instance managed by the L1 bridge contracts
- `Bridge`: the cross-layer system that binds L1 custody to L2 state transitions
- `Canonical custody`: the asset position that remains authoritative on L1
- `L1 token vault`: the per-channel vault managed by the L1 bridge contracts for token approval, transfer, deposit, and withdrawal
- `L2 token vault` or `L2 accounting vault`: the per-channel vault domain represented inside the L2 state, with its own dedicated Merkle tree
- `L2 token vault key`: the key under which a user's balance is represented in a channel's L2 token-vault tree
- `L2 app storage`: the collection of all channel storage other than the single L2 token-vault storage
- `Groth zkp`: the Groth16-based proof system used for token-vault control
- `Tokamak zkp`: the custom Tokamak zk-EVM proof system used for L2 channel transaction processing
- `Instance`: the public data paired with a submitted proof
- `Transaction instance`: the user-supplied Tokamak-zkp input that contains the transaction-specific public data
- `Channel instance`: the channel-environment public data that is fixed when a channel is created
- `Function instance`: the function-specific public data required for a particular contract function to execute in the Tokamak zk-EVM
- `Function preprocess`: the circuit metadata or preprocessing data required for a particular contract function in the Tokamak zk-EVM
- `DApp`: the set of smart contracts and functions designed for a specific L2 channel application
- `DApp manager`: the L1 bridge component that stores the supported DApps and their function-specific Tokamak-zkp metadata
- `Channel manager`: the per-channel L1 bridge component that verifies channel updates and enforces the channel's inherited DApp surface
- `Verified state`: the channel state that Ethereum has already validated
- `Proposed state`: the channel state that has been suggested but is not yet economically authoritative on Ethereum
- `Merkle-root vector`: the vector composed of the roots of the Merkle trees that concretely represent an L2 state
- `State root`: shorthand for an element of the Merkle-root vector when one committed tree is being discussed in isolation
- `Proof`: the zero-knowledge proof that binds a state transition to the bridge rules

### 1.5 Design Goals

The current design goals are as follows:

- keep canonical asset custody on L1
- realize L2 as a set of private application-specific channels
- accept economically meaningful state changes only through proof-backed Ethereum verification
- keep the architecture compatible with zk-oriented execution constraints
- preserve a clean separation between protocol rules, operational coordination, and participant rights
- ensure that one channel failure does not compromise unrelated channels

### 1.6 Baseline Assumptions

The following assumptions are currently treated as the baseline unless later inputs revise them:

- L1 is the canonical settlement and custody domain
- the System is divided at the highest level into bridge contracts deployed on Ethereum and an L2 server with its own independent state
- the L1 bridge contracts manage multiple L2 instances, and each managed L2 instance is called a channel
- L2 is realized as a set of autonomous private channels created, operated, and closed on Ethereum
- L2 is a state machine, and its concrete state is represented by one or more Merkle trees
- each channel has its own L1 token vault managed by the bridge
- each channel's L1 token vault stores both the user's tokens and the user's registered L2 token-vault key for that channel
- each channel's L2 state always includes one dedicated Merkle tree for an L2 token vault or L2 accounting vault
- each channel may additionally contain multiple other storage domains, and those are collectively treated as L2 app storage
- the same user must use a different L2 token-vault key for each channel
- once a user registers an L2 token-vault key for a channel, that key is immutable
- every L2 token-vault key must be globally unique across all channels, and the L1 bridge checks uniqueness when a key is registered
- the System uses two proof systems: Groth zkp for token-vault control and Tokamak zkp for channel transaction processing
- Tokamak zkp is composed of a proof, a transaction instance, a channel instance, a function instance, and a function preprocess
- the transaction instance is supplied by the channel user, while the channel instance, function instance, and function preprocess are supplied and managed by the L1 bridge
- an L2 state can therefore be expressed as a vector of Merkle roots
- an L2 state update means an update of that Merkle-root vector
- every Merkle-tree update in a channel is under L1 control
- the L2 token-vault or accounting-vault tree is also updated only under L1 control
- bridge acceptance must be proof-gated rather than trust-gated
- public outputs should reveal commitments and state transitions, not full private transaction contents
- each channel is app-specific and is created with a preset DApp surface
- the L1 bridge manages the DApps supported by the System, and only the System administrator may add a new DApp
- each channel manager inherits only a subset of contracts and functions from the DApp manager, and users may execute only that inherited subset
- a channel failure must remain isolated from other channels
- a channel's economically authoritative state on Ethereum changes only when Ethereum verifies the relevant new state
- L2 token-vault storage changes are traceable from Ethereum because Groth-zkp instances expose the relevant before-and-after data
- L2 app-storage data availability and integrity currently depend on the channel operator rather than on Ethereum
- `docs/spec.md` is an important source of structure and constraints, but it is not immutable truth
- later user instructions may refine, replace, or override any provisional interpretation derived from `docs/spec.md`

## 2. Main Body

### 2.1 User-Provided Channel Model

The current highest-priority architectural direction comes from the user-provided description of Tokamak Private App Channels. Under that description, the fundamental Layer 2 unit is not one shared rollup-wide state machine, but an autonomous private channel.

Tokamak Private App Channels are currently understood as autonomous Layer 2 channels that participants create, operate, and close on Ethereum. Each such channel is an individual L2 instance managed by the L1 bridge contracts. This implies that the System is multi-channel, that each channel operates independently as a state domain, and that the total number of concurrent channels is bounded primarily by Ethereum scalability rather than by a single global channel design. It also implies that the lifetime and scale of a channel may differ according to its application purpose.

Each channel is private through zero-knowledge proofs. Channel transactions are not intended to be revealed outside the channel, including to Ethereum validators. Ethereum is expected to validate the correctness of channel state transitions without learning the underlying private transaction contents.

Each channel is formed by a group of users, one of whom is designated as the channel leader. The current leader responsibilities are operational rather than sovereign:

- publish channel creation on Ethereum
- provide the relay server used for channel data exchange
- close the channel on Ethereum

All participants, including the leader, are currently treated as equal contributors to channel operation. The leader is therefore an operational coordinator, not the owner of the channel state and not a unilateral controller of participant assets.

### 2.2 State-Machine and Verification Model

L2 is currently modeled as a state machine, and each channel is modeled as an application-specific state machine inside that L2 environment. Participants generate candidate channel state transitions on the leader-hosted server, and those transitions are intended to be validated on Ethereum with zero-knowledge proofs.

The current definition of state is concrete rather than purely abstract. The substance of an L2 state is one or more Merkle trees. A single L2 may therefore contain multiple Merkle trees at once. Under that definition, an L2 state is represented by the vector of those Merkle roots, and an L2 state update means that the Merkle-root vector has changed. However, even though the channel state domain is independent from other channels, every update to those Merkle trees is currently treated as being under L1 control.

The model explicitly distinguishes between candidate state and verified state. Candidate state may exist on the L2 server before Ethereum has fully verified it, and it may be used as the provisional operational state inside the channel. Verified state, however, is the only state that is economically authoritative on Ethereum.

In the current version, channel verification follows an immediate-verification model:

1. A participant generates a candidate channel state transition together with its validity proof.
2. The participant submits the proof together with the transaction instance directly to the relevant verifier on L1, while L1 supplies the matching channel instance, function instance, and function preprocess.
3. Ethereum verifies the submitted proof immediately.
4. If verification succeeds, the channel's Merkle-root vector is updated immediately.
5. If verification fails, the attempted update is rejected and the last verified state remains authoritative.

This model creates a deliberate separation between operational progression inside a channel and economically authoritative progression on Ethereum, while avoiding deferred proposal-pool machinery in the current version.

### 2.3 DeFi Safety Interpretation

If a channel is used for a DeFi application, the assets of all participants, including the leader, must remain protected by the zero-knowledge proof protocol. This leads to a stronger rule than simple eventual settlement.

The current asset interpretation is:

- when a user opens a channel or enters an existing channel, the validity of the resulting new state must be verified by Ethereum
- a participant may later move channel-bound funds back to Ethereum using the last Ethereum-verified state
- if a newly generated candidate state has not been verified by Ethereum, it must not change the participant's authoritative asset position on Ethereum

Under this reading, channel execution may advance provisionally, but Ethereum-side economic authority does not move until verification occurs.

The current vault interpretation is channel-specific:

- the L1 bridge manages a separate L1 token vault for each channel
- channel users may approve and transfer tokens into a chosen channel's L1 token vault
- when a user first places tokens into an L1 token vault, the user must choose the target channel and provide the L2 token-vault key to be used in that channel
- once registered, that per-channel L2 token-vault key cannot be changed
- the L1 bridge checks that the supplied L2 token-vault key is globally unique across all channels before accepting the registration
- channel users may also withdraw their tokens back out through that channel's L1 token vault
- the corresponding L2 state always contains one independent Merkle tree dedicated to an L2 token vault or an L2 accounting vault

At the current level of abstraction, deposit means moving a user's position from the L1 token vault into the L2 token-vault domain, and withdraw means moving a user's position from the L2 token-vault domain back into the L1 token vault. Because all channel-tree updates are under L1 control, updates to the L2 token-vault or accounting-vault tree are also under L1 control. The registered L2 token-vault key inside the L1 token vault is part of the authorization path for both deposit and withdrawal.

#### 2.3.1 Groth zkp for Token-Vault Control

The System currently uses a Groth16-based proof system for vault control. For convenience, this document refers to it as `Groth zkp`.

Channel users must submit a Groth zkp proof when they want to deposit tokens from the L1 token vault into the L2 token vault domain or withdraw tokens in the reverse direction.

The Groth zkp proof is paired with an instance. The current instance definition contains:

- the current root of the L2 token-vault tree
- the updated root of the L2 token-vault tree
- the current user key and value in the Merkle tree
- the updated user key and value in the Merkle tree

The current user leaf is formed by applying a Poseidon hash to the user key and user value. The user value represents the token amount currently held for that user in the token vault.

The L1 token vault also stores the registered L2 token-vault key for each user in that channel. This registration model imposes the following current rules:

- the user chooses the channel and supplies the L2 token-vault key when first depositing tokens into that channel's L1 token vault
- the registered key is immutable once stored
- the same user must use a different L2 token-vault key for each channel
- every L2 token-vault key must be globally unique across all channels, so the L1 bridge checks for duplicate keys before registration

Under the current interpretation, successful verification of a Groth zkp proof means:

- the user's claimed token amount really existed in the L2 token-vault tree
- the claimed increment or decrement was applied to that user balance
- the resulting L2 token-vault tree was updated correctly

Accordingly, the L1 token vault currently acts as follows:

1. It receives the Groth zkp proof and its instance.
2. It verifies the proof.
3. It interprets the instance.
4. It decides whether the signed token delta corresponds to deposit into or withdrawal from the L2 token-vault domain.
5. For withdrawal, it checks that the instance's current user key matches the user's registered L2 token-vault key in that L1 token vault.
6. For deposit, it checks that the instance's updated user key matches the user's registered L2 token-vault key in that L1 token vault.
7. It updates the channel's Merkle-root vector accordingly.

This makes the current key-matching rules explicit:

- withdrawal requires a valid Groth zkp proof and instance, and the instance's current user key must equal the user's registered L2 token-vault key in the L1 token vault
- deposit requires a valid Groth zkp proof and instance, and the instance's updated user key must equal the user's registered L2 token-vault key in the L1 token vault

#### 2.3.2 Tokamak zkp for Channel Transaction Processing

The System also uses a custom proof system, Tokamak zk-EVM, for L2 channel transaction processing. For convenience, this document refers to it as `Tokamak zkp`.

Channel users use Tokamak zkp to prove that an L2 channel transaction was executed correctly. In the current design, Tokamak zkp is not described as a proof plus one monolithic instance. Instead, it is composed of:

- a proof
- a transaction instance
- a channel instance
- a function instance
- a function preprocess

The transaction instance contains:

- the current channel Merkle-root vector
- the updated channel Merkle-root vector
- the entry contract
- the target function signature on that entry contract

The channel instance contains the channel-environment variables that are fixed when the channel is created.

The function instance contains the function-specific data needed when a particular contract function is executed in the EVM, and it is predetermined according to that function.

The function preprocess contains the circuit information for that particular contract function.

For the L1 bridge's Tokamak-zkp verifier to validate a proof, it must be given the correct transaction instance, channel instance, function instance, and function preprocess.

The source of these components is intentionally split:

- the transaction instance is supplied by the channel user
- the channel instance is supplied and managed by the L1 bridge
- the function instance is supplied and managed by the L1 bridge
- the function preprocess is supplied and managed by the L1 bridge

Under the current interpretation, successful verification of a Tokamak zkp proof means:

- the user executed a transaction that called the specified function on the specified contract
- the execution followed the procedure defined by that function
- the execution succeeded
- the channel Merkle-tree leaves consumed by execution were correct
- the resulting channel Merkle trees were updated correctly

Users submit Tokamak zkp proofs and transaction instances directly to the Tokamak-zkp verifier of the relevant channel manager on L1. The channel manager then combines that user-supplied transaction instance with the bridge-managed channel instance, function instance, and function preprocess for verification. In the current version, the submission is verified immediately rather than being stored in a proposal pool.

If the Tokamak zkp proof verifies successfully, the channel manager immediately updates the channel's Merkle-root vector to the transaction instance's post-state. If the proof does not verify, the attempted state update is rejected and the previously verified state remains authoritative.

#### 2.3.3 Deferred Proposal-Pool and Tokenomics Model

The previously discussed proposal-pool model, including fork accumulation, delayed verification, proposer penalties, verifier rewards, and related token economics, is now treated as future work rather than as current behavior.

The reason is structural: a proposal-pool design cannot operate coherently until the protocol first specifies how unresolved forks are maintained, who is permitted or incentivized to resolve them, and how penalties and rewards are funded and enforced.

Accordingly, the current version of the System does not rely on proposal-pool operation for Tokamak-zkp-based channel updates.

#### 2.3.4 DApp Manager and Channel-Manager Inheritance

Each channel is operated for a specific DApp. In the current design, a `DApp` means the set of smart contracts and functions designed for that L2 channel application.

The L1 bridge manages the DApps supported by the System. A DApp manager stores, for each supported contract and function:

- the function instance
- the function preprocess

Only the System administrator may add a new DApp to the DApp manager.

Each channel manager inherits only a subset of contracts and functions from the DApp manager. Channel users may perform channel activity only with respect to the contracts and functions contained in that inherited subset.

This restriction is security-relevant. If a user generates a Tokamak zkp for a channel transaction outside the inherited subset and submits it to L1, the channel state must not update, because the verification path will fail on the function-instance or function-preprocess mismatch.

#### 2.3.5 Comparative Description of DApp Operation

To describe the System more clearly, it is useful to compare an ordinary L1-native DApp with a DApp operating through the System.

An ordinary L1-native DApp operates as follows:

1. The DApp developer deploys the relevant smart contracts to Ethereum.
2. Those smart contracts contain the storage used by the DApp and the functions that manipulate that storage.
3. A DApp user creates a transaction that calls one of those functions and submits it to Ethereum.
4. Ethereum validators verify the transaction by re-executing it.
5. If re-execution succeeds, Ethereum updates the corresponding storage roots and publishes the result.

Under that model:

- the DApp is a state machine
- DApp users are the proposers of state updates
- Ethereum L1 validators are the approvers of state updates
- the state-update condition is successful transaction re-execution
- Ethereum full nodes are the data providers from which the DApp state can be reconstructed

A DApp operating through the System works differently:

1. The DApp developer first registers the relevant contract-storage information and function information with the L1 bridge.
2. A channel operator opens an L2 channel dedicated to that DApp by using the bridge-registered storage and function information.
3. A DApp user creates a transaction that calls one of the permitted functions.
4. The user executes that transaction locally, confirms that it is valid, and generates a Tokamak zkp proving that validity.
5. The user submits the Tokamak zkp proof and the related public inputs to Ethereum without submitting the original transaction itself.
6. Ethereum validators verify the transaction's validity by verifying the zkp rather than by re-executing the original transaction.
7. If zkp verification succeeds, Ethereum updates both the DApp-related storage roots and the relevant L1 bridge storage roots and publishes the result.

Under the System model:

- the DApp is a state machine
- DApp users are the proposers of state updates
- Ethereum L1 validators are the approvers of state updates
- the state-update condition is successful zkp verification rather than transaction re-execution
- the channel operator is the practical data provider from which the DApp state can be reconstructed

This comparison clarifies the central shift introduced by the System: Ethereum validators approve state changes by proof verification instead of by re-executing the private transaction itself. It also exposes a corresponding dependency: if channel operators are the effective data providers for state reconstruction, then the System must make its data-availability assumptions explicit.

#### 2.3.6 Privacy Baseline and Private-State DApps

The System provides a baseline level of privacy because the original DApp transaction generated by the user is not normally shared with Ethereum L1 validators or with outside observers. However, this baseline privacy is not sufficient by itself for strong application-level privacy.

The reason is structural: the channel operator still holds the DApp's state data. Even if the original transaction is hidden, the channel operator may still infer user activity by analyzing changes in that state data.

Under the current interpretation, the System therefore provides only minimal or baseline privacy on its own. Stronger privacy depends on how the DApp itself is designed.

To obtain stronger privacy, the DApp should be designed under a `private-state model`. In that model, the DApp's storage is arranged so that the visible state data does not directly reveal the user-level meaning of transactions.

One example is a zk-note-based DApp.

Suppose the goal of the DApp is cryptocurrency transfer. In a zk-note design, the DApp storage does not manage a user's balance as one explicit numeric balance slot. Instead, it manages commitments to `Note` objects.

Under the current example, a `Note` is a structure composed of:

- the owner of the balance
- the amount of the balance
- a randomizer value

The DApp stores only the commitment of that note, for example a hash of the note structure.

Under that model, token transfer does not follow a simple state-overwrite pattern in which the DApp loads one user's balance, edits it, and writes it back. Instead, transfer is performed in an unspent-note-output style:

- the sender proves ownership of existing notes
- the sender issues new notes for the recipient and for change
- the consumed notes are marked as spent

A concrete example is as follows:

1. User A controls two notes, one with value `7` and one with value `8`.
2. User A wants to send `10` tokens to user B.
3. User A creates a transaction that calls a `noteTransfer` function and includes the underlying data for those two notes.
4. The `noteTransfer` function recomputes the commitments of those notes from the supplied note data.
5. It checks that those commitments match commitments already stored in the DApp state, thereby validating that the transaction creator controls the input notes.
6. It records those two input notes as spent.
7. It creates two new notes: one note for user B with value `10`, and one change note for user A with value `5`.
8. It stores only the commitments of those new notes in the DApp state.

Under this design, a third party can recover the transfer details between A and B only if that third party obtains the original transaction or equivalent witness data. If the observer sees only the DApp state, the observer sees only note commitments and spent markers, not the clear transfer record itself.

This is the complementary privacy argument of the current System design:

- the System hides the original transaction but does not hide state data from the channel operator
- a private-state DApp hides the user-level meaning of state data, but does not by itself hide the original transaction from the execution environment

When these two properties are composed, the System can provide a much stronger privacy result than either layer could provide alone.

However, the phrase `complete privacy` should still be treated cautiously. Even with a private-state DApp, metadata such as timing, note linkage patterns, participant behavior, or channel-operator visibility may still leak information unless the DApp and the surrounding protocol explicitly address those channels as well.

#### 2.3.7 Working Definition of Complete Privacy

For the purpose of this document, `complete privacy` is defined narrowly as a two-criterion standard at the application-state level:

1. `Transaction-content privacy`: observers who do not possess the original transaction cannot recover the user-level transaction content from what is published to Ethereum.
2. `State-semantic privacy`: observers who can inspect the DApp state cannot directly reconstruct the user-level meaning of state changes from the visible state data alone.

This is intentionally a working definition rather than a universal one. It does not claim to cover every possible metadata leak, such as timing, access patterns, note-linkage heuristics, or operator-side observation. Those broader leaks remain a separate privacy category outside this narrow definition.

Under this working definition, the current privacy picture is concise:

- `System alone` achieves transaction-content privacy, because the original transaction is hidden from Ethereum-side observers, but it does not achieve state-semantic privacy, because a channel operator may still infer user actions from visible state changes.
- `System + private-state DApp` achieves transaction-content privacy and state-semantic privacy together, because the System hides the original transaction while the private-state DApp hides the user-level meaning of the stored state.

Therefore, under this document's narrow working definition, `System + private-state DApp` achieves complete privacy, while `System alone` does not.

#### 2.3.8 Data Availability Split Between Vault and App Storage

Each channel contains exactly one L2 token-vault storage domain. In addition, a channel may contain multiple other storage domains for application logic. In this document, all such non-vault storage is grouped under the name `L2 app storage`.

The data-availability and integrity assumptions are not the same for these two storage classes.

For `L2 token vault storage`:

- it is managed through Groth zkp
- the Groth-zkp instance contains the previous value and updated value of the relevant storage data
- the corresponding state change is therefore traceable from information provided on Ethereum
- the channel operator does not need to be the exclusive data provider for that storage domain

In practical terms, this means that the data of the L2 token-vault storage is still supplied to Ethereum by users through Groth-zkp submissions, even if the channel operator does not provide it separately. Users can therefore still access the relevant token-vault state through Ethereum full nodes.

For `L2 app storage`:

- its data is not supplied to Ethereum by users in the same way
- users obtain that data from the channel operator
- the channel operator may fail to provide it, or may provide it incorrectly, whether by mistake or by malicious intent

If that happens, users may lose the ability to continue normal L2 transaction activity, because they can no longer reconstruct or trust the required app-storage state.

However, this failure does not imply loss of token-vault safety. Even in that scenario:

- users can still access L2 token-vault-storage state through Ethereum full nodes
- the channel operator does not have a unilateral path to tamper with L2 token-vault-storage state
- users can still withdraw their own tokens and escape the channel safely

This creates the current operational recommendation: if users want a safer escape path under weak operator data availability, they should rely on L2 token-vault storage frequently enough that their withdrawable position remains anchored in the Ethereum-visible vault state.

This recommendation is pragmatic rather than free of tradeoffs. Greater reliance on token-vault storage may improve safe-exit robustness, but it may also increase operational overhead and constrain how much application logic can remain purely in L2 app storage.

#### 2.3.9 Withdrawal Waiting Time Under Validity Proofs

The System is fundamentally a validity-proof-based design. This has an immediate consequence for withdrawal latency from the L2 token vault back to the L1 token vault.

Under the current interpretation, the System has almost no protocol-level withdrawal waiting time beyond proof production and on-chain verification. The reason is that once the relevant validity proof is verified, the corresponding L2 state transition is no longer open to the same kind of dispute window that is typical in fault-proof systems.

The contrast with a fault-proof model is important:

- in a fault-proof system, the absence of a submitted fault proof does not by itself mean that the proposed state is already known to be valid at that moment
- instead, the protocol normally relies on a challenge window during which someone may still dispute the state
- because of that delayed dispute model, withdrawals usually require a nontrivial waiting period before they are treated as safely final

By contrast, in a validity-proof system:

- the protocol checks a positive proof of correctness
- once that proof verifies, the relevant state transition is accepted as valid immediately under the protocol rules
- no additional challenge window is needed for that same validity question

From the user's point of view, the main withdrawal delay is therefore the time required to generate the necessary validity proof and submit it for verification. Under the current design direction, that delay is expected to be short, on the order of seconds rather than the extended waiting windows typical of fault-proof exits.

This does not mean the withdrawal path is literally zero-latency. The user still depends on proof generation time, transaction inclusion time, and ordinary Ethereum confirmation behavior. But the System does avoid the long protocol-imposed withdrawal delay characteristic of challenge-window-based fault-proof designs.

### 2.4 Provisional Interpretation of `docs/spec.md`

The mathematical model in `docs/spec.md` is currently treated as a structural reference rather than as final protocol truth. The present reading is that the spec describes a bridge-facing model with three major layers.

First, the `Bridge Admin Manager` appears to define a control-plane registry. It records which function signatures are supported, which storage addresses they touch, which pre-allocated keys and user storage slots matter, and which proof configuration belongs to each function. Under the current user-provided refinement, this role aligns closely with a DApp-manager-like control plane that stores bridge-managed function metadata rather than treating the L2 application as a black box.

Second, the `Channel` section appears to define a per-channel state domain. Each channel has a participant set, a supported function set, a derived storage universe, channel-local user storage keys, a validated value table, and a history of verified state roots. The spec may also be read as leaving room for a future model with proposed roots organized by fork identifier, but that is no longer treated as part of the current operating design.

Third, the `Bridge Core` appears to lift the per-channel relations into a global channel-scoped namespace. Under this interpretation, the bridge core is a channel aggregator and query surface rather than a separate state-transition model.

The spec also suggests two proof-driven update paths:

- a single-leaf update path through `updateSingleStateLeaf(...)`
- a multi-storage transition path through `verifyProposedStateRoots(...)`

This implies that the architecture may need both narrow proof updates and full batched execution proofs, though the exact long-term necessity of both paths remains open.

### 2.5 Rough System Structure

Taking the user-provided model and the current reading of `docs/spec.md` together, the rough Layer 2 system structure can be stated as follows.

At the highest level, the System is currently divided into two major parts:

- L1, namely Ethereum, where the bridge contracts are deployed
- an L2 server that maintains state independent from Ethereum while coordinating private channel execution

The L1 side manages multiple L2 instances. Each managed L2 instance is called a channel. The remaining subsections refine this top-level split.

#### 2.5.1 L1 Bridge Layer

The L1 bridge layer is responsible for:

- managing multiple channels, where each channel is an individual L2 instance
- managing the DApps supported by the System
- channel creation registration
- canonical asset custody
- management of a separate L1 token vault for each channel
- management of the per-user L2 token-vault key registrations associated with those channel vaults
- enforcement of system-wide uniqueness for all registered L2 token-vault keys
- management of channel instances, function instances, and function preprocess data for Tokamak-zkp verification
- verification of Groth-zkp-based token-vault updates
- channel entry validation
- deposit acceptance
- withdrawal settlement
- Tokamak-zkp verifier entrypoints
- proof verification
- accepted state-root progression
- storage of each channel's Merkle-root-vector change history
- storage of the latest leaves of each channel's current Merkle trees, without retaining past leaves
- immediate verification of Tokamak-zkp-based channel update requests
- commitment of a verified Merkle-root-vector update immediately after successful verification
- final channel closure settlement
- bridge configuration and emergency controls

More concretely, L1 management of a channel currently means the following:

1. L1 stores the history of changes to the channel's Merkle-root vector.
2. L1 stores the latest leaves of the channel's current Merkle trees.
3. L1 does not store historical leaves once they are no longer current.
4. L1 stores each user's registered L2 token-vault key for the channel together with that user's token-vault position.
5. L1 rejects registration of any L2 token-vault key that duplicates a key already registered anywhere in the System.
6. L1 fixes the channel instance when the channel is created.
7. L1 associates the channel manager with the subset of DApp contracts and functions that the channel may use.
8. L1 accepts Tokamak-zkp-based requests to update the channel's Merkle-root vector.
9. L1 verifies the submitted proof evidence immediately through the channel manager's verifier, using the user-supplied transaction instance and the bridge-managed channel instance, function instance, and function preprocess.
10. If the proof verifies successfully, L1 updates the channel's Merkle-root vector according to the submitted transaction instance.
11. L1 manages the channel's token-vault deposit and withdrawal entrypoints.
12. L1 controls every accepted update to every Merkle tree belonging to the channel.

#### 2.5.2 L2 Server and Channel Execution Layer

The L2 side is currently modeled as a server with independent state. This server is not merely a stateless relayer. It is the off-chain environment in which the private channels are coordinated and in which channel state progresses before Ethereum accepts a verified checkpoint.

That state is currently understood as a state-machine state realized through one or more Merkle trees. Accordingly, the server-side state of an L2 checkpoint is represented by a Merkle-root vector rather than by a single scalar state root.

Within that L2 server, the execution layer is not one global execution fabric. It is a collection of app-specific private channels. Each channel performs:

- private transaction handling inside the channel
- participant-driven state transition generation
- provisional state progression between verified checkpoints
- updates to one or more Merkle trees and therefore to the resulting Merkle-root vector
- maintenance of one dedicated Merkle tree for the channel's L2 token vault or L2 accounting vault
- maintenance of additional L2 app-storage domains when required by the DApp
- bridge-relevant accounting transitions
- production of the witness required for proof generation

Although the L2 server computes and coordinates candidate transitions, the authoritative application of any channel Merkle-tree update remains under L1 control.

Because each channel is DApp-specific, the L2 server must also respect the contract-and-function subset inherited by that channel manager. Off-chain execution outside that inherited subset may still be attempted locally, but it cannot produce an L1-acceptable Tokamak-zkp state update for that channel.

#### 2.5.3 Proof and Coordination Layer

A distinct proof and coordination layer sits between channel execution and Ethereum-side acceptance. Its role is currently understood as:

- derive or collect the transition witness
- generate Groth zkp proofs for token-vault control
- generate Tokamak zkp proofs for channel transaction execution
- assemble the transaction instance from the user transaction
- submit proofs, transaction instances, and bridge-linked public inputs
- coordinate immediate verification of Tokamak-zkp-based channel updates
- coordinate verified-state advancement

#### 2.5.4 Leader-Hosted Relay Layer

The leader-hosted relay layer is an operational layer, not a trust anchor. It is currently responsible for:

- relaying channel data among participants
- hosting the coordination server for the channel
- helping participants assemble candidate state transitions

The key constraint is that this layer must not be trusted with unilateral authority over participant assets.

### 2.6 Core Lifecycle

The channel lifecycle can currently be described as follows.

#### 2.6.1 Channel Creation

1. A group of participants agrees to form an app-specific private channel.
2. One participant is designated as the channel leader.
3. The leader publishes the channel creation on Ethereum.
4. The channel is associated with its preset DApp surface and initial participant set.
5. The initial usable state is recognized only after Ethereum validates the relevant state transition.

#### 2.6.2 Channel Entry

1. A user opens a channel or joins an existing channel through a state change.
2. The resulting new state is submitted to Ethereum for validation.
3. The user is considered safely inside the channel only after Ethereum verifies that state.

#### 2.6.3 Deposit and Funding

1. A participant places assets into the Ethereum-side custody path required by the channel or its DeFi application.
2. When first entering that channel's custody path, the participant provides the L2 token-vault key to be used in that channel.
3. The L1 bridge checks that the supplied key is globally unique across all channels and, if accepted, stores it immutably for that user and channel.
4. The participant may approve and transfer tokens to the selected channel's L1 token vault.
5. The participant invokes the channel's `deposit` function on the L1 token vault.
6. The participant submits a Groth zkp proof and instance for the L2 token-vault tree update.
7. The L1 token vault checks that the instance's updated user key matches the user's registered L2 token-vault key.
8. The channel incorporates that funding event into a new candidate state, including the channel's L2 token-vault or accounting-vault tree.
9. Until Ethereum verifies that new state, the participant's authoritative asset position remains based on the last verified state.
10. After verification, the new asset position becomes authoritative on Ethereum.

#### 2.6.4 In-Channel State Transition

1. Users execute channel actions.
2. Participants coordinate the next channel state on the leader-hosted server.
3. The system derives the resulting bridge-relevant state transition.
4. In concrete terms, the transition updates the underlying Merkle-tree state and therefore updates the Merkle-root vector.
5. A validity proof is generated for the candidate state update.
6. In the transaction-processing path, that proof is a Tokamak zkp proof accompanied by a transaction instance.
7. The user submits the Tokamak zkp proof and transaction instance directly to the channel manager's verifier on L1.
8. The channel manager supplies the channel instance, function instance, and function preprocess required for the selected contract function.
9. If the proof verifies successfully, L1 immediately updates the channel's Merkle-root vector under its control rules.
10. If the selected contract function is not in the channel manager's inherited DApp subset, verification fails through a function-metadata mismatch and no state update is accepted.
11. The participant asset baseline on Ethereum remains the last verified state until verification occurs.

#### 2.6.5 Immediate Verification and Rejection

1. A user submits a Tokamak zkp proof and transaction instance for a channel state update.
2. The channel manager's Tokamak-zkp verifier on L1 checks that proof immediately against the correct channel instance, function instance, and function preprocess.
3. If the proof is valid, the channel's Merkle-root vector is updated and becomes the new verified reference point.
4. If the proof is invalid, or if the function metadata does not match the channel manager's inherited DApp subset, the submitted update is rejected and the channel remains at the previous verified state.

#### 2.6.6 Channel Closure

1. The channel leader closes the channel on Ethereum.
2. The last verified state at closure becomes the final channel state.
3. Settlement rights are derived from that final verified state.

#### 2.6.7 Withdrawal

1. A participant requests to move channel-bound funds from the L2 token-vault domain back toward the L1 token vault.
2. The participant invokes the channel's `withdraw` function on the L1 token vault.
3. The participant submits a Groth zkp proof and instance for the L2 token-vault tree update.
4. The L1 token vault checks that the instance's current user key matches the user's registered L2 token-vault key.
5. The withdrawal entitlement is determined from the last Ethereum-verified state.
6. The bridge verifies that the claim matches the authoritative verified state.
7. The bridge releases assets from Ethereum-side custody.

### 2.7 State Categories and Invariants

The exact state model remains open, but the system currently needs to track at least the following categories:

- channel definitions
- channel leaders
- channel participant sets
- channel app identifiers or preset DApp templates
- system-supported DApp definitions
- per-DApp contract and function registries
- function instances for supported contract functions
- function preprocess data for supported contract functions
- per-channel fixed channel instances
- per-channel inherited DApp subsets
- channel status across creation, operation, verification, and closure
- canonical L1 custody balances
- per-channel L1 token vault balances
- per-channel registered user-to-L2-token-vault-key mappings
- a global registry of all registered L2 token-vault keys
- verified channel asset balances
- provisional channel asset balances
- L2 accounting balances
- the set of Merkle trees that realize each L2 state
- the dedicated Merkle tree for each channel's L2 token vault or L2 accounting vault
- all non-vault storage grouped as L2 app storage
- the latest stored leaves of each channel's current Merkle trees
- accepted Merkle-root vectors
- per-channel history of Merkle-root-vector changes
- Groth zkp instances for vault updates
- Tokamak zkp transaction instances for channel transaction updates
- verified checkpoint history
- deposit records or commitments
- withdrawal claims or nullifiers
- relay-server and coordination metadata
- operator or prover configuration
- emergency or governance controls

The current invariants are:

- no asset leaves L1 custody without a bridge-authorized settlement path
- no candidate state becomes economically authoritative on Ethereum without proof verification
- deposit and withdrawal accounting must remain conservation-safe across layers
- each channel must have its own L1 token vault managed by the bridge
- each channel must have exactly one dedicated L2 vault tree inside its L2 state
- every authoritative L2 state must be representable as a Merkle-root vector
- every L2 state update must correspond to an update of that Merkle-root vector
- every channel Merkle-tree update must remain under L1 control
- every L2 vault-tree update must remain under L1 control
- every deposit or withdrawal must be backed by a valid Groth zkp proof and instance
- every deposit must require that the Groth instance's updated user key match the user's registered L2 token-vault key in the corresponding L1 token vault
- every withdrawal must require that the Groth instance's current user key match the user's registered L2 token-vault key in the corresponding L1 token vault
- every channel transaction update must be backed by a Tokamak zkp proof, a transaction instance, the correct channel instance, the correct function instance, and the correct function preprocess
- L1 must preserve the history of Merkle-root-vector changes for each channel
- L1 must store the latest leaves of each current channel tree while not retaining obsolete historical leaves
- no channel update becomes authoritative until its submitted Tokamak zkp evidence is verified by L1
- each user's registered L2 token-vault key for a channel must be immutable once stored
- no two registered L2 token-vault keys may coincide anywhere across the System
- L2 token-vault-storage data integrity and practical data availability must remain recoverable from Ethereum-visible Groth-zkp submissions
- L2 app-storage data integrity and availability currently depend on the channel operator unless stronger DA machinery is introduced
- failure of L2 app-storage availability must not prevent a user from withdrawing tokens according to the last accessible token-vault state
- only the System administrator may add a new DApp to the DApp manager
- a channel manager may accept Tokamak-zkp-based updates only for the contract-and-function subset it inherited from the DApp manager
- a function-instance or function-preprocess mismatch must prevent channel-state update acceptance
- opening a channel or entering a channel must not become final until Ethereum verifies the resulting new state
- a failed Tokamak zkp submission must not corrupt the last verifiable state
- a channel failure must remain isolated from other channels
- the leader must not gain unilateral control over participant assets merely by hosting the relay server or publishing transactions
- state-root progression must be well-defined and non-ambiguous
- replay of already-consumed bridge actions must be impossible or explicitly prevented
- administrative powers must be explicit, minimal, and justified

### 2.8 Historical Input Record

The following record is kept so that later revisions can identify which parts of the design came directly from user input.

#### 2.8.1 2026-03-17

- The design target is a bridge for operating a zk-proof-based Ethereum Layer 2.
- The documentation process should absorb spontaneous ideas while maintaining coherent system structure.
- `docs/spec.md` should be read and translated into a rough Layer 2 system structure in English.
- The structure derived from `docs/spec.md` is provisional and may be overridden later.
- Tokamak Private App Channels are autonomous Layer 2 channels created, operated, and closed by participants on Ethereum.
- Channels are independent from one another, app-specific, private through zero-knowledge proofs, and may differ in lifetime and scale.
- One participant acts as channel leader and is responsible for publication, relay-server operation, and closure.
- Channel state transitions are generated by participants on the leader's server and can be proposed to Ethereum with validity proofs.
- Other participants or third parties may object to a proposed state; upon objection, Ethereum verifies the proposal and reverts to the last verifiable state if verification fails.
- If proposals continue without objection until closure, the final proposed state is verified at closure and the last verified state becomes final.
- For DeFi channels, participant assets are protected by the proof protocol, channel entry or opening requires Ethereum verification of the resulting new state, and channel asset balances on Ethereum change only when the new state is verified.
- From this point onward, the term `System` refers to Tokamak Private App Channels.
- The System is divided at the highest level into L1 bridge contracts deployed on Ethereum and an L2 server with independent state.
- L2 is a state machine whose concrete state is realized by one or more Merkle trees, so an L2 state is represented by a vector of Merkle roots and an L2 state update means an update of that vector.
- The L1 bridge contracts manage multiple L2 instances, each called a channel, by storing root-vector history, current leaves, update proposals, and proof-validated state updates.
- Each channel has its own L1 token vault, and each channel's L2 state always contains one dedicated token-vault or accounting-vault Merkle tree.
- Users may approve and transfer tokens into a channel's L1 token vault, and may later invoke `deposit` or `withdraw` there to move their position between the L1 vault and the L2 vault domain.
- The detailed operating principles of `deposit` and `withdraw` are deferred for later specification.
- Every Merkle-tree update in a channel, including updates to the L2 token-vault or accounting-vault tree, is under L1 control.
- The System uses Groth zkp for token-vault control and Tokamak zkp for L2 channel transaction processing.
- Groth zkp proofs directly drive deposit and withdrawal updates on the L2 token-vault tree and the channel Merkle-root vector.
- In the current version, Tokamak zkp proofs are submitted directly to each channel manager's verifier on L1, and successful verification immediately updates the channel Merkle-root vector.
- Proposal-pool operation, fork management, and token-economics-driven rewards or penalties are deferred to future work.

#### 2.8.2 2026-03-18

- The current version does not operate a channel state-update proposal pool.
- A channel user submits Tokamak zkp directly to the Tokamak-zkp verifier of the relevant channel manager on L1.
- If the submitted Tokamak zkp verifies successfully, the channel's Merkle-root vector is updated immediately.
- Proposal-pool operation, fork handling, rewards, penalties, and tokenomics are deferred to future work.
- Tokamak zkp is composed of a proof, a transaction instance, a channel instance, a function instance, and a function preprocess.
- The transaction instance is supplied by the channel user, while the channel instance, function instance, and function preprocess are supplied and managed by the L1 bridge.
- Each channel is DApp-specific, and the DApp is defined as the set of contracts and functions designed for that channel application.
- The L1 bridge manages supported DApps through a DApp manager, and only the System administrator may add a new DApp.
- Each channel manager inherits only a subset of contracts and functions from the DApp manager.
- A Tokamak zkp that refers to a contract function outside the inherited subset must fail through function-metadata mismatch and must not update channel state.
- Each channel manager's L1 token vault stores the user's tokens together with that user's registered L2 token-vault key for the channel.
- The same user must use a different L2 token-vault key for each channel, and every registered L2 token-vault key is globally unique across the System.
- When a user first places tokens into a channel's L1 token vault, the user must provide the L2 token-vault key to be used in that channel, and that key becomes immutable once registered.
- Withdrawal requires both a valid Groth zkp proof and instance and equality between the instance's current user key and the user's registered L2 token-vault key.
- Deposit requires both a valid Groth zkp proof and instance and equality between the instance's updated user key and the user's registered L2 token-vault key.
- Compared with an ordinary L1-native DApp, the System replaces validator-side transaction re-execution with validator-side zkp verification.
- Under this comparative description, DApp users still propose state updates and Ethereum validators still approve them, but the practical data provider for state reconstruction becomes the channel operator rather than Ethereum full nodes.
- The System provides baseline privacy by hiding the original transaction from L1 observers, but that alone does not prevent channel operators from inferring user actions from state changes.
- Stronger privacy requires a private-state DApp design, such as a zk-note model in which storage contains note commitments rather than explicit user balances.
- In the zk-note example, transfer is modeled as spending input notes and creating new output notes, so state observers without the original transaction can see commitments but not the clear transfer record.
- Under the document's working definition, complete privacy means satisfying both transaction-content privacy and state-semantic privacy.
- Under that working definition, the System alone satisfies only transaction-content privacy, while `System + private-state DApp` satisfies both criteria.
- Each channel has exactly one L2 token-vault storage domain and may additionally contain multiple L2 app-storage domains.
- L2 token-vault-storage changes are traceable from Ethereum through Groth-zkp instance data, while L2 app-storage data currently depends on the channel operator for availability and integrity.
- Even if L2 app-storage data becomes unavailable or unreliable, users can still rely on Ethereum-visible token-vault state to withdraw tokens and escape safely.
- Because the System is validity-proof-based rather than fault-proof-based, withdrawal waiting time is expected to be dominated by proof generation and ordinary Ethereum inclusion, not by a long challenge window.

## 3. Conclusion

### 3.1 Current Working Conclusions

At the current stage, Tokamak Private App Channels are best understood as a System with two top-level parts: bridge contracts deployed on Ethereum and an L2 server with independent state. Within that System, the L1 bridge contracts manage multiple L2 instances, and each such L2 instance is called a channel. L2 itself is treated as a state machine whose concrete state is realized by one or more Merkle trees, so each authoritative checkpoint is represented by a Merkle-root vector. Each channel is app-specific, each channel has its own participant set and designated leader, and each channel has an independent state domain, but the authoritative update of every channel Merkle tree remains under L1 control.

The most important current conclusion is that the bridge must distinguish operational state from economically authoritative state. Channel execution may be prepared off-chain, but verified state alone determines the asset position that Ethereum recognizes. This distinction governs channel entry, DeFi safety, verification, channel closure, and withdrawal.

The second major conclusion is that token-vault authorization now depends not only on proof validity but also on a bridge-managed L2 token-vault key registry. Deposits and withdrawals are tied to the user's immutable registered key for the selected channel, and the bridge enforces global uniqueness of those keys across the System.

The third major conclusion is that the System changes the approval condition of DApp state transitions. In an ordinary L1-native DApp, Ethereum validators approve updates by re-executing transactions. In the System, validators approve updates by verifying zero-knowledge proofs, while the original transaction may remain private.

The fourth major conclusion is that data availability is asymmetric across channel storage classes. L2 token-vault storage remains practically recoverable from Ethereum-visible Groth-zkp data, whereas L2 app storage currently depends on the channel operator for integrity and availability.

The fifth major conclusion is that safe channel escape therefore depends on the token-vault path, not on continued availability of L2 app-storage data. Even if the operator stops serving app-storage data or serves it incorrectly, users should still be able to withdraw through the token-vault state that Ethereum can track.

The sixth major conclusion is that withdrawal latency is expected to be short because the System uses validity proofs rather than challenge-window-based fault proofs. In the current model, the dominant delay is proof generation plus normal Ethereum inclusion, not a long protocol-level withdrawal waiting period.

The seventh major conclusion is that this document now uses a narrow working definition of complete privacy. Under that definition, complete privacy means satisfying both transaction-content privacy and state-semantic privacy. The System alone satisfies only the first criterion, while the System combined with a private-state DApp satisfies both.

The eighth major conclusion is that System-level privacy and DApp-level private-state design are complementary rather than interchangeable. The System can hide original transactions from L1 observers, but if the DApp state itself is semantically transparent, a channel operator may still infer user actions from state changes. Stronger privacy therefore depends on a private-state DApp design such as a zk-note model.

The ninth major conclusion is that Tokamak-zkp verification depends on bridge-managed metadata, not only on user-supplied transaction data. A valid channel update now requires the correct combination of proof, transaction instance, channel instance, function instance, and function preprocess. This means the bridge controls not only when a state update is accepted, but also which contract functions are even admissible for a given channel.

The tenth major conclusion is that the leader should be modeled as an operational coordinator rather than as a privileged trust anchor. The relay server may coordinate the channel, but it must not create unilateral control over state validity or participant assets.

### 3.2 Open Questions and Remaining Work

The following questions remain open and will need to be resolved in later revisions:

- the exact proof-submission timing model
- the exact operating principles of the `deposit` and `withdraw` functions
- whether the phrase `L2 token vault` should be interpreted as real L2 token custody or as an accounting-vault abstraction inside the L2 state machine
- the exact operational meaning of the phrase "last verifiable state"
- the exact withdrawal authorization model
- the exact relation between provisional in-channel execution and verified Ethereum state
- the exact recovery, migration, or rotation policy if a user loses access to an immutable registered L2 token-vault key
- the exact storage and lookup design for enforcing global uniqueness of all registered L2 token-vault keys
- whether channel operators alone are sufficient as practical data providers for state reconstruction, or whether the System needs stronger data-availability guarantees
- whether the document's narrow definition of complete privacy should remain limited to transaction content and state semantics, or be expanded to include metadata privacy
- the exact residual privacy leakage that may remain even in a private-state DApp, including metadata, timing, note-linkage, and operator-observation channels
- the exact operational tradeoff between frequent token-vault usage for safer escape and richer reliance on L2 app storage for application efficiency
- whether a channel manager's inherited contract-and-function subset is immutable after channel creation or can be versioned later
- the exact lifecycle and governance process for updating channel instances, function instances, and function preprocess data
- the exact future design of proposal-pool operation, if the protocol later reintroduces delayed Tokamak-zkp verification
- the exact tokenomics required to support future proposal-pool operation, fork resolution, penalties, and rewards
- the exact Ethereum scalability cost of storing the latest leaves for many channels on L1
- the exact data-availability assumptions
- the exact failure and recovery model

### 3.3 Current Working Decisions

The following decisions are stable enough to be treated as the current working position of this document:

- The System is divided at the highest level into L1 bridge contracts on Ethereum and an L2 server with independent state.
- The L1 bridge contracts manage multiple L2 instances, each of which is called a channel.
- L2 is a state machine whose concrete state is represented by a vector of Merkle roots derived from one or more Merkle trees.
- Tokamak Private App Channels are treated as autonomous private Layer 2 channels created, operated, and closed on Ethereum.
- L1 management of a channel includes storing Merkle-root-vector change history, storing only the latest leaves of the current Merkle trees, immediately verifying submitted Tokamak zkp updates, and committing verified updates.
- Each channel has its own L1 token vault managed by the bridge.
- Each channel's L2 state includes exactly one dedicated Merkle tree for an L2 token vault or accounting vault.
- Each channel's L1 token vault stores the user's tokens together with the user's immutable registered L2 token-vault key for that channel.
- Users must supply the L2 token-vault key when they first place tokens into a channel's L1 token vault, and the bridge rejects any key that duplicates a registered key anywhere else in the System.
- Users may use the channel's L1 token vault to approve, transfer, deposit, and withdraw tokens, but deposit and withdrawal must match the Groth instance against the registered L2 token-vault key.
- Every Merkle-tree update in a channel, including every L2 vault-tree update, is under L1 control.
- The System uses Groth zkp for token-vault control and Tokamak zkp for channel transaction processing.
- Groth zkp proofs directly authorize deposit and withdrawal updates on the L2 token-vault tree and on the channel Merkle-root vector.
- Each channel contains exactly one L2 token-vault storage domain and may additionally contain multiple L2 app-storage domains.
- L2 token-vault-storage data remains practically available and integrity-protected through Ethereum-visible Groth-zkp submissions, while L2 app-storage data currently depends on the channel operator.
- Safe channel escape depends on the token-vault path, so frequent use of token-vault storage is currently the recommended robustness strategy when operator data availability is weak.
- Withdrawal waiting time is expected to be dominated by proof generation and ordinary Ethereum inclusion rather than by a long challenge window.
- Tokamak zkp is composed of a proof, a transaction instance, a channel instance, a function instance, and a function preprocess.
- The transaction instance is supplied by the user, while the channel instance, function instance, and function preprocess are supplied and managed by the L1 bridge.
- Tokamak zkp proofs are submitted directly to each channel manager's verifier on L1, and successful verification immediately updates the channel Merkle-root vector.
- Compared with an ordinary L1-native DApp, the System uses validator-side zkp verification instead of validator-side transaction re-execution.
- Under the current comparative description, channel operators are the practical data providers for reconstructing System DApp state.
- The System by itself provides baseline privacy by hiding original transactions, but stronger privacy depends on a private-state DApp design.
- A zk-note-style DApp is the current example of that private-state model: balances are represented by note commitments, transfers consume input notes, mark them spent, and create new output-note commitments.
- The L1 bridge manages supported DApps, and only the System administrator may add a new DApp.
- Each channel manager inherits a contract-and-function subset from the DApp manager and may accept only that subset for channel updates.
- Proposal-pool operation, fork handling, and tokenomics-linked incentives are not part of the current version and remain future work.
- Each channel is app-specific and uses a preset DApp surface.
- Each channel has a designated leader responsible for publication, relay-server operation, and closure.
- The leader is an operational coordinator, not the unilateral owner of participant assets or state authority.
- Off-chain candidate execution may exist before verification, but only Ethereum-verified states are economically authoritative.
- If a Tokamak zkp submission fails verification, the channel remains at the last verified state.
- For DeFi channels, user funds on Ethereum are determined only by the last verified state until a newer state is verified.

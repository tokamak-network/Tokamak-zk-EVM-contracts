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
- each channel's L2 state always includes one dedicated Merkle tree for an L2 token vault or L2 accounting vault
- an L2 state can therefore be expressed as a vector of Merkle roots
- an L2 state update means an update of that Merkle-root vector
- every Merkle-tree update in a channel is under L1 control
- the L2 token-vault or accounting-vault tree is also updated only under L1 control
- bridge acceptance must be proof-gated rather than trust-gated
- public outputs should reveal commitments and state transitions, not full private transaction contents
- each channel is app-specific and is created with a preset DApp surface
- a channel failure must remain isolated from other channels
- a channel's economically authoritative state on Ethereum changes only when Ethereum verifies the relevant new state
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

### 2.2 State-Machine, Proposal, and Dispute Model

L2 is currently modeled as a state machine, and each channel is modeled as an application-specific state machine inside that L2 environment. Participants generate candidate channel state transitions on the leader-hosted server, and those transitions are intended to be validated on Ethereum with zero-knowledge proofs.

The current definition of state is concrete rather than purely abstract. The substance of an L2 state is one or more Merkle trees. A single L2 may therefore contain multiple Merkle trees at once. Under that definition, an L2 state is represented by the vector of those Merkle roots, and an L2 state update means that the Merkle-root vector has changed. However, even though the channel state domain is independent from other channels, every update to those Merkle trees is currently treated as being under L1 control.

The model explicitly distinguishes between proposed state and verified state. Proposed state may exist before Ethereum has fully verified it, and it may be used as the provisional operational state inside the channel. Verified state, however, is the only state that is economically authoritative on Ethereum.

The current dispute model is as follows:

1. A participant proposes a new channel state to Ethereum together with its validity proof.
2. Other participants or third parties may object to that proposal.
3. If an objection is raised, Ethereum verifies the last proposed channel state.
4. If verification fails, the channel reverts to the last verifiable state.
5. If proposals continue without objection until closure, the final proposed state is verified at closure.
6. The last verified state at closure becomes the final channel state.

This model creates a deliberate separation between operational progression inside a channel and economically authoritative progression on Ethereum.

### 2.3 DeFi Safety Interpretation

If a channel is used for a DeFi application, the assets of all participants, including the leader, must remain protected by the zero-knowledge proof protocol. This leads to a stronger rule than simple eventual settlement.

The current asset interpretation is:

- when a user opens a channel or enters an existing channel, the validity of the resulting new state must be verified by Ethereum
- a participant may later move channel-bound funds back to Ethereum using the last Ethereum-verified state
- if a newly proposed state has not been verified by Ethereum, that proposal must not change the participant's authoritative asset position on Ethereum

Under this reading, channel execution may advance provisionally, but Ethereum-side economic authority does not move until verification occurs.

The current vault interpretation is channel-specific:

- the L1 bridge manages a separate L1 token vault for each channel
- channel users may approve and transfer tokens into a chosen channel's L1 token vault
- channel users may also withdraw their tokens back out through that channel's L1 token vault
- the corresponding L2 state always contains one independent Merkle tree dedicated to an L2 token vault or an L2 accounting vault

At the current level of abstraction, deposit means moving a user's position from the L1 token vault into the L2 token-vault domain, and withdraw means moving a user's position from the L2 token-vault domain back into the L1 token vault. Because all channel-tree updates are under L1 control, updates to the L2 token-vault or accounting-vault tree are also under L1 control. The exact operating logic of `deposit` and `withdraw` remains intentionally deferred until later input.

### 2.4 Provisional Interpretation of `docs/spec.md`

The mathematical model in `docs/spec.md` is currently treated as a structural reference rather than as final protocol truth. The present reading is that the spec describes a bridge-facing model with three major layers.

First, the `Bridge Admin Manager` appears to define a control-plane registry. It records which function signatures are supported, which storage addresses they touch, which pre-allocated keys and user storage slots matter, and which proof configuration belongs to each function. Under this reading, the bridge does not treat the L2 application as a black box. It maintains a structured model of which parts of L2 state it is willing to validate.

Second, the `Channel` section appears to define a per-channel state domain. Each channel has a participant set, a supported function set, a derived storage universe, channel-local user storage keys, a validated value table, a history of verified state roots, and a history of proposed roots organized by fork identifier.

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
- channel creation registration
- canonical asset custody
- management of a separate L1 token vault for each channel
- channel entry validation
- deposit acceptance
- objection handling and dispute-triggered verification
- withdrawal settlement
- proof verification
- accepted state-root progression
- storage of each channel's Merkle-root-vector change history
- storage of the latest leaves of each channel's current Merkle trees, without retaining past leaves
- acceptance and storage of proposed Merkle-root-vector updates for each channel
- proof-based verification of channel update proposals and commitment of the verified Merkle-root-vector update
- final channel closure settlement
- bridge configuration and emergency controls

More concretely, L1 management of a channel currently means the following:

1. L1 stores the history of changes to the channel's Merkle-root vector.
2. L1 stores the latest leaves of the channel's current Merkle trees.
3. L1 does not store historical leaves once they are no longer current.
4. L1 accepts and stores proposals to update the channel's Merkle-root vector.
5. When proof evidence for a proposal is submitted, L1 verifies that evidence.
6. If the proof verifies successfully, L1 updates the channel's Merkle-root vector according to the proposal.
7. L1 manages the channel's token-vault deposit and withdrawal entrypoints.
8. L1 controls every accepted update to every Merkle tree belonging to the channel.

#### 2.5.2 L2 Server and Channel Execution Layer

The L2 side is currently modeled as a server with independent state. This server is not merely a stateless relayer. It is the off-chain environment in which the private channels are coordinated and in which channel state progresses before Ethereum accepts a verified checkpoint.

That state is currently understood as a state-machine state realized through one or more Merkle trees. Accordingly, the server-side state of an L2 checkpoint is represented by a Merkle-root vector rather than by a single scalar state root.

Within that L2 server, the execution layer is not one global execution fabric. It is a collection of app-specific private channels. Each channel performs:

- private transaction handling inside the channel
- participant-driven state transition generation
- provisional state progression between verified checkpoints
- updates to one or more Merkle trees and therefore to the resulting Merkle-root vector
- maintenance of one dedicated Merkle tree for the channel's L2 token vault or L2 accounting vault
- bridge-relevant accounting transitions
- production of the witness required for proof generation

Although the L2 server computes and coordinates candidate transitions, the authoritative application of any channel Merkle-tree update remains under L1 control.

#### 2.5.3 Proof and Coordination Layer

A distinct proof and coordination layer sits between channel execution and Ethereum-side acceptance. Its role is currently understood as:

- derive or collect the transition witness
- generate validity proofs
- submit state proposals, proofs, and bridge-linked public inputs
- coordinate objection-triggered verification
- coordinate verified-state advancement or reversion

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
2. The participant may approve and transfer tokens to the selected channel's L1 token vault.
3. The participant invokes the channel's `deposit` function on the L1 token vault.
4. The channel incorporates that funding event into a new candidate state, including the channel's L2 token-vault or accounting-vault tree.
5. Until Ethereum verifies that new state, the participant's authoritative asset position remains based on the last verified state.
6. After verification, the new asset position becomes authoritative on Ethereum.

#### 2.6.4 In-Channel State Transition

1. Users execute channel actions.
2. Participants coordinate the next channel state on the leader-hosted server.
3. The system derives the resulting bridge-relevant state transition.
4. In concrete terms, the transition updates the underlying Merkle-tree state and therefore updates the Merkle-root vector.
5. A validity proof is generated for the proposed state update.
6. The proposed Merkle-root-vector update is submitted to L1 and stored as a proposal for the channel.
7. No Merkle-tree update becomes authoritative until L1 accepts the update under its control rules.
8. The proposed state may be published to Ethereum before it becomes economically final.
9. The participant asset baseline on Ethereum remains the last verified state until verification occurs.

#### 2.6.5 Objection and Verification

1. A proposed channel state appears on Ethereum as a candidate progression.
2. Another participant or a third party objects to the proposal.
3. Proof evidence for the proposed Merkle-root-vector update is submitted to Ethereum.
4. Ethereum verifies that evidence against the stored proposal.
5. If the proposal is valid, the channel's Merkle-root vector is updated and becomes the new verified reference point.
6. If the proposal is invalid, the channel falls back to the last verifiable state.

#### 2.6.6 Channel Closure

1. The channel leader closes the channel on Ethereum.
2. If there are unverified proposed states, the final proposed state is verified at closure.
3. The last verified state at closure becomes the final channel state.
4. Settlement rights are derived from that final verified state.

#### 2.6.7 Withdrawal

1. A participant requests to move channel-bound funds from the L2 token-vault domain back toward the L1 token vault.
2. The participant invokes the channel's `withdraw` function on the L1 token vault.
3. The withdrawal entitlement is determined from the last Ethereum-verified state.
4. The bridge verifies that the claim matches the authoritative verified state.
5. The bridge releases assets from Ethereum-side custody.

### 2.7 State Categories and Invariants

The exact state model remains open, but the system currently needs to track at least the following categories:

- channel definitions
- channel leaders
- channel participant sets
- channel app identifiers or preset DApp templates
- channel status across creation, operation, objection, and closure
- canonical L1 custody balances
- per-channel L1 token vault balances
- verified channel asset balances
- provisional channel asset balances
- L2 accounting balances
- the set of Merkle trees that realize each L2 state
- the dedicated Merkle tree for each channel's L2 token vault or L2 accounting vault
- the latest stored leaves of each channel's current Merkle trees
- accepted Merkle-root vectors
- proposed Merkle-root vectors
- per-channel history of Merkle-root-vector changes
- per-channel stored update proposals
- objection records
- verified checkpoint history
- deposit records or commitments
- withdrawal claims or nullifiers
- relay-server and coordination metadata
- operator or prover configuration
- emergency or governance controls

The current invariants are:

- no asset leaves L1 custody without a bridge-authorized settlement path
- no proposed state becomes economically authoritative on Ethereum without proof verification
- deposit and withdrawal accounting must remain conservation-safe across layers
- each channel must have its own L1 token vault managed by the bridge
- each channel must have exactly one dedicated L2 vault tree inside its L2 state
- every authoritative L2 state must be representable as a Merkle-root vector
- every L2 state update must correspond to an update of that Merkle-root vector
- every channel Merkle-tree update must remain under L1 control
- every L2 vault-tree update must remain under L1 control
- L1 must preserve the history of Merkle-root-vector changes for each channel
- L1 must store the latest leaves of each current channel tree while not retaining obsolete historical leaves
- no channel update proposal becomes authoritative until its submitted proof evidence is verified by L1
- opening a channel or entering a channel must not become final until Ethereum verifies the resulting new state
- a failed proposal must not corrupt the last verifiable state
- reversion after failed verification must return the channel to the last verifiable state
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

## 3. Conclusion

### 3.1 Current Working Conclusions

At the current stage, Tokamak Private App Channels are best understood as a System with two top-level parts: bridge contracts deployed on Ethereum and an L2 server with independent state. Within that System, the L1 bridge contracts manage multiple L2 instances, and each such L2 instance is called a channel. L2 itself is treated as a state machine whose concrete state is realized by one or more Merkle trees, so each authoritative checkpoint is represented by a Merkle-root vector. Each channel is app-specific, each channel has its own participant set and designated leader, and each channel has an independent state domain, but the authoritative update of every channel Merkle tree remains under L1 control.

The most important current conclusion is that the bridge must distinguish operational state from economically authoritative state. Proposed state may drive activity inside the channel, but verified state alone determines the asset position that Ethereum recognizes. This distinction governs channel entry, DeFi safety, dispute handling, channel closure, and withdrawal.

The second major conclusion is that the leader should be modeled as an operational coordinator rather than as a privileged trust anchor. The relay server may coordinate the channel, but it must not create unilateral control over state validity or participant assets.

### 3.2 Open Questions and Remaining Work

The following questions remain open and will need to be resolved in later revisions:

- the exact rights and limits of third-party objections
- the exact proof-submission timing model
- the exact operating principles of the `deposit` and `withdraw` functions
- whether the phrase `L2 token vault` should be interpreted as real L2 token custody or as an accounting-vault abstraction inside the L2 state machine
- the exact operational meaning of the phrase "last verifiable state"
- the exact withdrawal authorization model
- the exact relation between provisional in-channel execution and verified Ethereum state
- the exact Ethereum scalability cost of storing the latest leaves for many channels on L1
- the exact data-availability assumptions
- the exact failure and recovery model

### 3.3 Current Working Decisions

The following decisions are stable enough to be treated as the current working position of this document:

- The System is divided at the highest level into L1 bridge contracts on Ethereum and an L2 server with independent state.
- The L1 bridge contracts manage multiple L2 instances, each of which is called a channel.
- L2 is a state machine whose concrete state is represented by a vector of Merkle roots derived from one or more Merkle trees.
- Tokamak Private App Channels are treated as autonomous private Layer 2 channels created, operated, and closed on Ethereum.
- L1 management of a channel includes storing Merkle-root-vector change history, storing only the latest leaves of the current Merkle trees, storing update proposals, and committing proposed updates only after proof verification.
- Each channel has its own L1 token vault managed by the bridge.
- Each channel's L2 state includes exactly one dedicated Merkle tree for an L2 token vault or accounting vault.
- Users may use the channel's L1 token vault to approve, transfer, deposit, and withdraw tokens, while the exact deposit/withdraw logic remains to be specified.
- Every Merkle-tree update in a channel, including every L2 vault-tree update, is under L1 control.
- Each channel is app-specific and uses a preset DApp surface.
- Each channel has a designated leader responsible for publication, relay-server operation, and closure.
- The leader is an operational coordinator, not the unilateral owner of participant assets or state authority.
- Proposed states may exist before verification, but only Ethereum-verified states are economically authoritative.
- If a proposal is challenged and fails verification, the channel reverts to the last verifiable state.
- If proposals continue without objection until closure, the final proposed state is verified at closure and the last verified state becomes final.
- For DeFi channels, user funds on Ethereum are determined only by the last verified state until a newer state is verified.

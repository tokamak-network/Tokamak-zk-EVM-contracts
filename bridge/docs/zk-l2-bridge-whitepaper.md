# Tokamak Private App Channels White Paper

Last updated: 2026-04-01

## Table of Contents

1. Thesis
2. System Model
3. Design Philosophy
4. Architecture
5. State and Proof Model
6. Core Operational Flows
7. Security Posture and Tradeoffs
8. Conclusion

## 1. Thesis

Tokamak Private App Channels are not designed as a general-purpose rollup that asks every application to live inside one global execution environment. The current bridge implementation instead treats a channel as a dedicated validity-proven execution domain for one registered DApp, while Ethereum remains the canonical place for custody, proof verification, and settlement.

That choice is the core design thesis of the system:

- application specificity is a feature, not a limitation
- validity should be checked on Ethereum, not delegated to a trusted operator
- custody should remain on Ethereum even when execution moves off-chain
- privacy should be layered on top of proof-backed execution rather than assumed automatically

The result is a bridge architecture that tries to make proof-backed app channels operationally practical without collapsing everything into a single monolithic Layer 2. Each channel gets its own manager, its own state commitment, and its own proof-validated updates, while the bridge provides the shared control plane for DApp registration, channel creation, token custody, and verifier access.

## 2. System Model

The current implementation has six major parts:

- `BridgeCore`: the root coordination contract that creates channels, binds verifiers, and anchors the shared settlement surface
- `DAppManager`: the metadata registry that defines which storage addresses and function surfaces a DApp is allowed to use
- `BridgeAdminManager`: the administrative parameter surface, including the Merkle-tree depth that the bridge accepts
- `L1TokenVault`: the shared Ethereum-side custody contract for the canonical asset
- `ChannelManager`: a per-channel contract that validates Tokamak proofs and tracks the current state commitment of that channel
- off-chain execution and proving infrastructure: the environment in which users execute application logic, assemble witnesses, and produce proofs

Each channel belongs to exactly one registered DApp. The bridge does not treat a channel as an open-ended programmable sandbox. A channel inherits a bounded storage surface and a bounded function surface from the DApp metadata that was registered before the channel was created.

This is an opinionated model. The bridge is intentionally DApp-aware at the metadata layer, but DApp-agnostic at the settlement layer. In other words, the bridge does not need to understand application semantics in full detail; it needs enough metadata to decide whether the submitted proof is speaking about an allowed function, an allowed storage surface, and the expected public-input layout.

## 3. Design Philosophy

### 3.1 Ethereum Remains the Trust Anchor

The bridge is built around a simple boundary: off-chain systems may execute transactions and build proofs, but they do not finalize state by themselves. A state transition becomes economically meaningful only when Ethereum verifies the proof and the bridge accepts the resulting commitment update.

This is why the design keeps three responsibilities on L1:

- custody of the canonical asset
- acceptance or rejection of state transitions
- publication of the authoritative commitment trail that describes accepted channel state

The leader, relay server, or other channel-side operator is therefore an operational coordinator, not a trust anchor.

### 3.2 Proof Verification Replaces Re-Execution, Not Settlement

The system does not try to replace Ethereum as the final settlement layer. It replaces validator-side transaction re-execution with validator-side proof verification.

That distinction matters. The bridge does not ask Ethereum validators to understand the private transaction itself. It asks them to verify that a proof attests to a valid state transition over an agreed public input surface. Privacy and scalability come from moving execution and witness generation off-chain, while correctness is still decided on-chain.

This design also explains why the current bridge does not rely on a long fraud-proof dispute window for normal channel progress. The implemented model is immediate validity acceptance: if the proof verifies and the bridge-side checks pass, the new commitment is accepted immediately on L1.

### 3.3 Metadata-Driven Admission Is a Safety Boundary

The current bridge does not accept arbitrary proof payloads from arbitrary contracts. It admits DApps through explicit metadata:

- managed storage addresses
- one designated channel-token-vault storage address
- supported entry-contract and function-signature pairs
- one preprocess-input hash per supported function
- the public-input offsets needed to decode the relevant state-transition fields

This is a deliberate design choice. The bridge is not secure merely because a proof system exists. It is secure because the proof is interpreted through bridge-managed metadata that limits what a submitted proof is allowed to mean.

The design philosophy here is that programmability should enter through registration, not through ambiguous runtime interpretation.

### 3.4 Channel Isolation Matters More Than Global Composability

Each channel has its own `ChannelManager`, its own state commitment, and its own token-vault registrations. The current bridge prefers isolation over deep shared-state composability between channels.

That isolation has two benefits:

- failure or corruption in one channel does not directly rewrite another channel's accepted state
- the bridge can reason about each channel with a tight, DApp-scoped metadata surface instead of one globally entangled state machine

The tradeoff is equally clear: cross-channel composability is not the primary optimization target. The primary target is predictable validity boundaries per application channel.

### 3.5 Minimal On-Chain State, Maximum On-Chain Verifiability

The current implementation stores only the hash of the current root vector in the channel manager rather than the full root vector itself. This is another deliberate design choice.

The bridge wants on-chain state to be compact, but it does not want accepted transitions to become opaque. It resolves that tension by combining:

- a compact on-chain commitment (`currentRootVectorHash`)
- proof-backed state-transition checks
- emitted observations of accepted root vectors and storage writes

This means the bridge does not try to persist every detail forever in contract storage. Instead, it keeps the authoritative commitment on-chain and emits enough accepted observations for indexers and external observers to reconstruct the sequence of accepted states.

### 3.6 Custody and Application Execution Are Separated

The current architecture uses one shared L1 token vault for the canonical asset while application logic lives in channel-scoped proof updates. That separation is philosophical as much as technical.

The bridge treats asset custody as a conservative, settlement-facing concern. It treats application execution as a validity-proven concern. Combining both inside one opaque off-chain operator trust model would weaken the system boundary the bridge is trying to preserve.

This is why deposits and withdrawals are routed through a separate Groth16-backed vault path even when the channel also supports richer Tokamak-zkp application execution.

### 3.7 Privacy Is Layered, Not Absolute

The current bridge hides the original transaction from Ethereum by accepting a proof and public inputs instead of the original execution trace. That is useful, but it is not the full privacy story.

The design philosophy is intentionally narrower:

- the bridge provides transaction-submission privacy at the settlement boundary
- the DApp must provide state-semantic privacy if the application requires it

In other words, the bridge can help hide what was submitted to Ethereum, but it does not automatically hide what the application state means. Strong privacy still depends on a private-state DApp model.

## 4. Architecture

### 4.1 Shared Control Plane

`BridgeCore`, `DAppManager`, `BridgeAdminManager`, and `L1TokenVault` form the shared bridge control plane. In the current implementation these root-entry contracts are upgradeable through UUPS proxies so that the bridge can evolve without forcing a full address reset for the main control surface.

This is another explicit design choice: shared infrastructure may need controlled upgradeability, but accepted per-channel state transitions must still remain explicit and externally observable.

### 4.2 Per-Channel Execution Surface

A new channel is created by `BridgeCore` only after the bridge verifies that the DApp metadata exists, the configured Merkle-tree depth matches the supported value, and the managed storage surface is within the bridge's supported bounds.

At creation time the channel fixes:

- the DApp it belongs to
- the leader that coordinates the channel operationally
- the managed storage-address vector
- the designated channel-token-vault tree index
- the inherited supported functions
- the genesis `aPubBlockHash` binding for Tokamak proof context

This means a channel is born with a pre-committed execution grammar. The bridge does not let that grammar drift at runtime.

### 4.3 Token-Vault Identity Layer

The current bridge also introduces an explicit registration layer for token-vault identity inside each channel. A user registers:

- an L2 address
- a channel-token-vault key
- the derived leaf index
- a note-receive public key

The bridge enforces uniqueness across these identifiers inside the channel and checks that the provided leaf index matches the one derived from the registered storage key. This is not merely bookkeeping. It is part of the system's authorization model for vault-backed balance updates and safe exit.

## 5. State and Proof Model

### 5.1 Root-Vector State

The authoritative state commitment of a channel is a vector of Merkle roots, one root per managed storage address. One entry is reserved for the `channelTokenVault` tree, while the other entries can represent application-managed storage trees.

This vector model reflects the bridge's design priorities:

- one channel can cover both vault state and application state
- the bridge can stay agnostic to many application semantics
- accepted transitions can still be checked against a bounded, bridge-visible commitment structure

### 5.2 Tokamak Proofs for Application Execution

Tokamak proofs drive proof-backed application execution. The current bridge validates more than proof validity alone. It also checks that:

- the submitted preprocess input hashes to the registered function metadata
- the submitted `aPubBlock` hashes to the channel-fixed `aPubBlockHash`
- the decoded entry contract and function signature match an allowed function
- the decoded current root vector matches the channel's accepted commitment

The bridge therefore treats Tokamak proof submission as a three-layer check:

1. cryptographic proof validity
2. channel-context validity
3. DApp-metadata validity

This layered verification model is central to the current bridge design. A valid proof is not enough if it is not also a valid proof for this channel, this DApp, and this registered function surface.

### 5.3 Groth Proofs for Vault Accounting

Deposits and withdrawals use a separate Groth16 verifier path for the channel-token-vault tree. The bridge checks the registered vault key, the current accepted root, and the direction of the user-value change before applying the update.

This split is intentional. The bridge treats token-vault accounting as a narrow and highly structured proving problem, distinct from the broader execution surface that Tokamak proofs cover.

The practical effect is architectural separation:

- Tokamak proofs advance general channel execution
- Groth proofs advance the token-vault subtree
- the bridge keeps both paths consistent by updating the same channel root-vector commitment

### 5.4 Observable Acceptance Instead of Silent Mutation

When the bridge accepts a proof-backed transition, it emits the accepted root-vector observation. When a transition implies storage writes, it emits the observed storage writes as well. The vault path emits the same storage-write observation pattern for token-vault updates.

This is an important statement about the bridge's philosophy. Accepted changes should not be invisible. Even when the bridge keeps contract storage compact, it still publishes an auditable trail of what was accepted.

The system therefore favors:

- compact persistent commitments
- explicit accepted observations
- off-chain reconstruction by indexers and external observers

over large on-chain state mirrors.

## 6. Core Operational Flows

### 6.1 DApp Registration and Channel Creation

The lifecycle begins with DApp registration. The bridge owner registers the storage surface and function metadata that define the DApp's admissible execution surface. Only after that can `BridgeCore` create a channel for the DApp.

The design lesson is simple: the bridge wants the admissible state-transition language to be fixed before users start submitting proofs.

### 6.2 Funding and Vault Participation

Users first fund the shared L1 vault and then register their channel-token-vault identity inside the channel. After that, deposits and withdrawals are expressed as proof-backed updates to the channel-token-vault tree.

This flow preserves two important separations:

- the L1 vault remains the custody boundary
- the channel-token-vault tree remains the accounting boundary

### 6.3 In-Channel Transaction Execution

For a normal application transaction, the off-chain environment executes the DApp logic, assembles the public inputs, and produces the Tokamak proof. The user then submits the proof payload to the channel manager.

If the proof verifies and the bridge-side metadata checks pass:

- the accepted root-vector commitment advances
- the relevant storage writes are observed
- the channel state becomes authoritative immediately on Ethereum

If any of those checks fail, the previous accepted root-vector hash remains authoritative.

### 6.4 Withdrawal and Safe Exit

The current bridge is designed so that token-vault recovery does not depend on replaying arbitrary application state. Safe exit is therefore anchored primarily in the vault path rather than in full application-state reconstruction.

This does not mean application-state availability is solved. It means the bridge deliberately gives asset recovery a narrower and more robust path than general DApp execution.

## 7. Security Posture and Tradeoffs

The current implementation is built around the following security posture:

- Ethereum is the canonical custodian and validity gate
- proof acceptance is immediate once the bridge-side checks pass
- a leader can coordinate a channel but cannot unilaterally finalize invalid state
- DApp execution is limited to a registered metadata surface
- token-vault authorization is bound to explicit channel registrations
- accepted state changes remain externally observable through emitted commitments and writes

The same implementation also makes several explicit tradeoffs.

First, the bridge currently prefers operational clarity over unconstrained flexibility. It supports one designated channel-token-vault storage per DApp, a fixed supported Merkle-tree depth, and a bounded managed-storage surface. These constraints simplify soundness reasoning but reduce generality.

Second, the bridge prefers immediate validity acceptance over challenge-window-based optimistic flow. That gives clean validity finality, but it also means proving cost and proving latency sit directly on the critical path.

Third, the bridge separates asset safety from application-data availability. Asset recovery has a narrow vault-oriented path on Ethereum, while broader app-state availability still depends more heavily on off-chain data supply.

Fourth, the bridge assumes exact-transfer asset behavior in the shared L1 vault. This conservative rule protects custody accounting but excludes ERC-20 behaviors that mutate balances during transfer.

Finally, the bridge uses an upgradeable shared control plane together with immutable per-channel deployments. This balances evolvability of the bridge framework against explicit channel-local commitment boundaries, but it also requires disciplined governance for upgrades.

## 8. Conclusion

The current Tokamak Private App Channels bridge is best understood as a proof-first bridge for dedicated application channels, not as a generic rollup shell. Its design philosophy is consistent across the implementation:

- keep Ethereum as the trust anchor
- replace re-execution with proof verification rather than replacing settlement
- admit DApps through explicit metadata rather than ambiguous runtime interpretation
- isolate channels instead of forcing one global application state machine
- keep custody conservative and execution flexible
- publish accepted commitments and writes even when persistent storage stays compact
- treat privacy as a layered property that depends on both the bridge and the DApp

Under this model, the bridge offers a clear contract between Ethereum, the proving system, and the application developer. Ethereum decides custody and accepted validity. The bridge decides whether a proof matches an allowed channel and DApp surface. The DApp decides what application semantics live behind that proof surface. That division of responsibility is the defining architectural idea of the current implementation.

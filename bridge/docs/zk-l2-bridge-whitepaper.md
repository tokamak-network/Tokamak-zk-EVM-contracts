# Tokamak Private App Channels White Paper

Last updated: 2026-04-01

## Table of Contents

1. Thesis
2. System Model
3. Design Philosophy
4. Architecture
5. State and Proof Model
6. Core Operational Flows
7. Security Posture, Advantages, and Tradeoffs
8. Future Work
9. Conclusion

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
- `L1TokenVault`: the shared Ethereum-side custody contract for the canonical asset
- `ChannelManager`: a per-channel contract that validates Tokamak proofs and tracks the current state commitment of that channel
- off-chain execution and proving infrastructure: the environment in which users execute application logic, assemble witnesses, and produce proofs

The human-facing side of the system can also be understood through three principal actor classes. The DApp developer defines the application contracts, the bridge-facing metadata surface, and the client-side logic that lets users interact with that DApp over the bridge. The channel operator coordinates channel-side proving, relaying, and service operation, but is not a trust anchor for accepted state. The channel user funds custody on Ethereum, registers channel-local identity, reconstructs channel state from accepted outputs, and submits or relays the proof-backed actions that matter to that user's own channel participation.

These parts are not arranged as one flat network. Ethereum is the top-level settlement and ordering environment. The bridge control plane lives on Ethereum and is shared across all channels. Each channel then forms its own execution domain under that shared bridge surface, with its own accepted state commitment and its own user registrations. In other words, the system is not one global off-chain state machine with many applications inside it. It is one Ethereum-anchored bridge fabric with many parallel channel-scoped state machines attached to it.

Each channel belongs to exactly one registered DApp. The bridge does not treat a channel as an open-ended programmable sandbox. A channel inherits a bounded storage surface and a bounded function surface from the DApp metadata that was registered before the channel was created.

This is an opinionated model. The bridge is intentionally DApp-aware at the metadata layer, but DApp-agnostic at the settlement layer. In other words, the bridge does not need to understand application semantics in full detail; it needs enough metadata to decide whether the submitted proof is speaking about an allowed function, an allowed storage surface, and the expected public-input layout.

The user side of the topology is also layered. A user has one global Ethereum-facing existence, such as an L1 account and L1 asset custody relation, but that same user can participate in multiple channels through separate channel-local workspaces. Each such workspace is logically a distinct `user-in-channel` context. It carries the channel-specific registration, the channel-specific accepted commitment history, the channel-specific reconstructed application state, and any local secret material that the DApp requires for continued private activity. This means participation is not best understood as a single link between a user and the bridge. It is better understood as many links of the form `user in channel X` interacting with `channel X`, all under one shared Ethereum settlement surface.

## 3. Design Philosophy

<img src="overview.png" alt="High-level system overview" />

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

As a result, the bridge's notion of finality is not challenge-window finality. It is validity-proof finality anchored in Ethereum inclusion. For bridge purposes, a channel state becomes final when Ethereum accepts the proof-backed transition that consumes the current canonical commitment and replaces it with the next one. Competing transitions that still reference the previous commitment no longer finalize once that canonical head has advanced.

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

In other words, the bridge can help hide the original private execution payload, but it does not automatically hide the observable shape of channel activity. The bridge still publishes proof-backed state transitions, accepted root-vector updates, observed storage writes, and any DApp event logs that the registered function metadata instructs it to re-emit. An outside observer can therefore still learn that activity occurred, when it occurred, which channel function family was involved, and how the accepted commitment state moved.

This is why privacy remains DApp-dependent. The bridge provides a lower-information settlement boundary than direct calldata publication, but it does not by itself guarantee semantic privacy of user behavior.

The `private-state` DApp shows the intended extension of that model. There, an outside observer can still see the timing and rough shape of user activity such as mint-like, transfer-like, redeem-like, or vault-withdrawal-related transitions, and can observe that the note-related storage commitments changed. However, the observer cannot directly recover the plaintext note contents, the recipient-specific meaning of encrypted outputs, or the full semantic transaction story from those observations alone. In short:

- the bridge hides the original execution payload
- the DApp may further hide the user-level meaning of the resulting state transition

For readers who want one concrete intuition: an outside observer may be able to tell that a user participated in a transfer-shaped action and that certain commitment domains changed, while still being unable to tell which recipient actually received which note value.

## 4. Architecture

### 4.1 Shared Control Plane

`BridgeCore`, `DAppManager`, and `L1TokenVault` form the shared bridge control plane. In the current implementation these root-entry contracts are upgradeable through UUPS proxies so that the bridge can evolve without forcing a full address reset for the main control surface.

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

That fixed grammar should not be misunderstood as accidental incompleteness. The intended operating model is that the qap-compiler and its subcircuit library expose a bounded admissible function surface at any given release. A channel is expected to snapshot only the function families that fit within that proving-capacity bound when the channel is created.

Under that model, channels are one-shot deployments rather than long-lived mutable products. If a later compiler or subcircuit-library release expands the supportable function family, the intended response is to create fresh channels with the expanded execution grammar rather than retroactively reinterpret or patch older channels.

### 4.3 Token-Vault Identity Layer

The current bridge also introduces an explicit registration layer for token-vault identity inside each channel. A user registers:

- an L2 address
- a channel-token-vault key
- the derived leaf index
- a note-receive public key

The bridge enforces uniqueness across these identifiers inside the channel and checks that the provided leaf index matches the one derived from the registered storage key. This is not merely bookkeeping. It is part of the system's authorization model for vault-backed balance updates and safe exit.

### 4.4 User-Local Channel Workspaces

The bridge architecture implies that user activity is separated by channel even when the same person participates in several channels at once. The user's L1 wallet relation is global, but the user's actionable channel state is local to each channel.

This separation matters because each channel has its own accepted commitment head, its own token-vault registration set, and potentially its own privacy-specific recovery requirements. A user's local environment therefore has to maintain one channel workspace per channel of participation rather than one undifferentiated bridge-wide state cache.

The resulting high-level picture is:

- Ethereum provides shared settlement, custody, and final ordering
- the bridge provides a shared control plane and verifier access surface
- each channel provides an isolated accepted execution domain for one DApp
- each user participates through channel-local views rather than through one bridge-global application state

This is why many of the bridge's guarantees are expressed per channel and per user-in-channel. Data availability, transaction continuity, privacy exposure, safe exit scope, and state reconstruction all depend on what a particular user can recover inside a particular channel.

### 4.5 Information Flow Across Layers

The high-level information flow follows the same layered topology.

Administrative information flows from the bridge owner into the shared control plane through DApp
registration. Channel creation is permissionless after registration: the creator selects an
already-registered DApp policy, accepts its digest and verifier snapshot, and becomes the channel
leader. That flow fixes the admissible execution grammar before users begin interacting with a
channel.

Execution information flows from channel-local off-chain environments into Ethereum as proof-backed submissions. For general application execution, the submitted signal is a Tokamak proof payload together with the public inputs needed for the bridge to identify the channel function, the current accepted commitment, the updated commitment, and the bridge-visible outputs of that transition. For vault balance movement, the submitted signal is a Groth-backed token-vault update tied to the user's registered channel-token-vault identity.

Acceptance information then flows back out of Ethereum to every interested local environment. The bridge publishes the accepted commitment trail, the observed storage mutations, and the accepted event outputs that it is configured to surface. Users, relays, and external indexers can all consume that published information to reconstruct the accepted history that matters to them.

The key architectural rule is that no off-chain actor is authoritative by itself. Off-chain environments may compute, coordinate, relay, index, or assist, but accepted state exists only after Ethereum has accepted the corresponding proof-backed transition. That rule applies both to normal channel execution and to token-vault updates for deposits and withdrawals.

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

In this white paper, `data availability` means more than the existence of an audit trail. It means whether a channel user can reconstruct enough channel state from Ethereum-published data, together with the user's own local secrets when the DApp is intentionally private, to keep creating valid transactions without depending on a third-party operator or indexing service.

The current bridge contributes to that goal by publishing accepted root vectors, observed storage writes, and re-emitted DApp event logs. However, the bridge does not by itself guarantee that every DApp's full semantic storage state becomes publicly and completely reconstructible. It guarantees an accepted commitment trail and an observable mutation surface. Whether that is sufficient for user-independent transaction continuity remains DApp-specific.

## 6. Core Operational Flows

### 6.1 DApp Registration and Channel Creation

The lifecycle begins with DApp registration. The bridge owner registers the storage surface and
function metadata that define the DApp's admissible execution surface. Only after that can a channel
creator ask `BridgeCore` to create a channel for the DApp.

The design lesson is simple: the bridge wants the admissible state-transition language to be fixed before users start submitting proofs.

In the current intended workflow, that admissible language is chosen with full awareness of the proving stack's present capacity. If some DApp functions are not registered for a given channel generation, that omission is not necessarily an operator mistake. It can instead reflect the deliberate decision to launch that channel generation only with the function families that fit the current qap-compiler and subcircuit-library limits.

This also means future proving-capacity expansion is expected to produce new channel generations, not in-place mutation of old ones. A later channel may support a wider function family than an earlier one without implying that the earlier channel was malformed.

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

The current bridge is designed so that recovery of value that still resides in the designated `channelTokenVault` tree does not depend on replaying arbitrary application state. In that limited but important sense, safe exit is anchored in the vault path rather than in full application-state reconstruction.

This also means the current withdrawal path does not introduce a separate dispute-time waiting period before assets become claimable. A withdrawal is accepted against the currently authoritative channel-token-vault root, and once Ethereum has included that valid root update, the bridge treats the resulting post-withdrawal state as final for withdrawal purposes. In other words, the implementation does not wait for a later challenge window to confirm which channel state won. The winning state is the one whose valid proof advanced the canonical root on Ethereum.

That guarantee is narrower than a guarantee of universal economic exit for every DApp state. The bridge gives its strongest exit property to value that the DApp keeps in the bridge-recognized token-vault storage domain. If a DApp moves economically meaningful value into other app-managed storage domains, then exit of that value depends on the DApp's own state model and transition rules rather than on the bridge alone.

The `private-state` DApp illustrates this boundary clearly. Its bridge-recognized token-vault storage is the liquid accounting balance in `L2AccountingVault`, while note commitments and nullifiers live in `PrivateStateController`. A user can exit liquid balance through the bridge's vault path, but value that has already been transformed into notes must first be redeemed back into liquid balance before withdrawal to L1 is possible. In other words, the bridge alone does not guarantee safe exit of all note-held value at every moment; it guarantees safe exit of value that has been brought back into the designated token-vault accounting domain.

This does not mean application-state availability is solved. It means the bridge deliberately offers a narrow and robust asset-recovery path for one storage domain, while broader recovery of user position can still depend on DApp-specific state reconstruction and DApp-specific recovery flows.

### 6.5 Data Availability and User Continuity

For the current bridge, the practical data-availability question is not only whether channel history can be audited. The more important question is whether a channel user can continue transacting without asking a third party to supply missing state.

At the bridge layer, the answer is partial but meaningful. Any user can independently read Ethereum and recover:

- the accepted root-vector history
- the observed storage-write history that the bridge decoded from accepted proofs
- the DApp event logs that the bridge re-emitted from the accepted public output

This means the protocol does support self-hosted indexing. A user is not forced by the bridge contracts to trust a channel operator's server merely to obtain accepted history.

However, that is not the same as a universal guarantee that every DApp state can be fully and publicly reconstructed. The bridge does not impose one global rule that every semantic part of every DApp state must be recoverable by every observer from Ethereum alone. It publishes an accepted mutation surface, but the meaning of that surface remains DApp-dependent.

The `private-state` DApp is the clearest example. In that DApp, Ethereum-visible data is enough to let any observer track that commitment and nullifier-related storage changed and that encrypted note-delivery payloads were emitted. But the semantic note state is not fully public. The recipient still needs the relevant local secret material to decrypt delivered notes and reconstruct which notes are actually theirs. As a result:

- a user who runs an independent indexer and holds the correct note-receive secrets can continue transacting without relying on a third-party data provider
- an outside observer without those secrets cannot reconstruct the same semantic note state
- the bridge therefore supports user-local reconstructibility for private state, not universal public reconstructibility of the entire note graph

This distinction is intentional. For privacy-preserving DApps, `data availability` should be understood as the availability of enough data for the rightful user to recover their own actionable state, not necessarily enough data for every outside observer to derive the same semantic state view.

The broader architectural consequence is that third-party indexers are a convenience layer, not always a protocol requirement. For DApps whose public outputs and user-held secrets are sufficient, users can remain operationally independent. For DApps whose public outputs are too sparse to reconstruct the next valid pre-state, users may still need external data services even though the bridge itself has published the accepted commitment history.

## 7. Security Posture, Advantages, and Tradeoffs

The current implementation is built around the following security posture:

- Ethereum is the canonical custodian and validity gate
- proof acceptance is immediate once the bridge-side checks pass
- a leader can coordinate a channel but cannot unilaterally finalize invalid state
- DApp execution is limited to a registered metadata surface
- token-vault authorization is bound to explicit channel registrations
- accepted state changes remain externally observable through emitted commitments and writes

The same design also gives the system several distinctive advantages.

First, the bridge offers Ethereum-anchored validity finality without requiring a long fraud-proof dispute window for normal channel progress. That makes the settlement rule simple: the canonical state is the one whose valid proof advanced the accepted root on Ethereum.

Second, the bridge is DApp-scoped rather than generically permissive. Each channel admits a fixed metadata-described execution surface, which creates a sharper safety boundary than an open-ended execution model and makes the bridge's trust and verification envelope easier to reason about.

Third, the bridge separates custody from application execution. Assets remain conservatively anchored in the shared L1 vault, while richer application semantics can live in proof-backed channel execution. This gives the system a narrow and explicit custody boundary even when application logic is more expressive.

Fourth, the bridge combines compact persistent state with auditable observability. It does not mirror all application state on Ethereum, but it still publishes accepted commitments, observed writes, and accepted event outputs so that users and external observers can reconstruct what the bridge accepted.

Fifth, the bridge supports layered privacy rather than one uniform privacy promise. At the bridge layer it hides the full execution witness and original off-chain execution payload, and at the DApp layer it allows applications such as `private-state` to provide stronger user-local privacy on top of that settlement surface.

The same implementation also makes several explicit tradeoffs.

First, the bridge currently prefers operational clarity over unconstrained flexibility. It supports one designated channel-token-vault storage per DApp, a fixed supported Merkle-tree depth, and a bounded managed-storage surface. These constraints simplify soundness reasoning but reduce generality.

Second, the bridge prefers immediate validity acceptance over challenge-window-based optimistic flow. That gives clean validity finality and avoids an additional withdrawal-delay window, but it also means proving cost and proving latency sit directly on the critical path.

Third, the bridge separates asset safety from application-data availability. Asset recovery has a narrow vault-oriented path on Ethereum, while continued application activity depends on whether the DApp exposes enough accepted data for users to reconstruct their own next actionable state without third-party help.

Fourth, the bridge assumes exact-transfer asset behavior in the shared L1 vault. This conservative rule protects custody accounting but excludes ERC-20 behaviors that mutate balances during transfer.

Fifth, the bridge uses an upgradeable shared control plane together with immutable per-channel deployments. This balances evolvability of the bridge framework against explicit channel-local commitment boundaries, but it also requires disciplined governance for upgrades.

Sixth, some present-day integration and user-experience burden remains above the common proving stack. The reusable Tokamak-zk-EVM pipeline means a new DApp does not need a bespoke proving architecture from scratch, but DApp developers still need to package bridge metadata, client sync, recovery flows, and privacy-aware UX around that shared substrate. This is better understood as a tooling and productization gap than as a fundamental limitation of the bridge architecture, but today it still affects onboarding cost.

## 8. Future Work

Several of the present tradeoffs are expected to compress with better tooling.

One direction is DApp-integration tooling. The current bridge already benefits from a reusable proving pipeline, so future work can focus on standardizing the remaining bridge-facing work: generating admissible metadata, validating storage surfaces, scaffolding client sync and recovery components, and packaging common integration patterns so that new DApps require less bespoke adaptation.

Another direction is user-facing tooling. Wallet recovery, local state continuity, and private-state handling should become safer defaults rather than manual operator knowledge. Better developer and user tooling can turn many of today's integration chores into routine productization steps.

Finally, the current system's most visible architectural tradeoff is that it buys comparatively strong privacy and clean validity finality by paying the cost of expensive validity-proof verification on the critical path. A useful future-work direction is to explore whether that tradeoff can be mediated by optional third-party or server-assisted layers, such as delegated proving, relay services, aggregation services, or other assisted submission paths. The goal would not be to weaken Ethereum-anchored validity settlement, but to let applications choose how much cost, latency, privacy, and operational independence they want to carry directly versus outsource to specialized infrastructure.

## 9. Conclusion

The current Tokamak Private App Channels bridge is best understood as a proof-first bridge for dedicated application channels, not as a generic rollup shell. Its design philosophy is consistent across the implementation:

- keep Ethereum as the trust anchor
- replace re-execution with proof verification rather than replacing settlement
- admit DApps through explicit metadata rather than ambiguous runtime interpretation
- isolate channels instead of forcing one global application state machine
- keep custody conservative and execution flexible
- publish accepted commitments and writes even when persistent storage stays compact
- treat privacy as a layered property that depends on both the bridge and the DApp

Under this model, the bridge offers a clear contract between Ethereum, the proving system, and the application developer. Ethereum decides custody and accepted validity. The bridge decides whether a proof matches an allowed channel and DApp surface. The DApp decides what application semantics live behind that proof surface. That division of responsibility is the defining architectural idea of the current implementation.

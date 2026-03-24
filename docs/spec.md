# Tokamak Private App Channels Bridge Specification

This document defines an abstract model for the Tokamak Private App Channels bridge.
It is intended for theoretical analysis, security reasoning, and later paper writing.
It does not attempt to describe transient implementation details such as concrete ABI
shapes, event names, calldata layouts, or internal caching strategies.

## 1. Scope

The system is an Ethereum-settled bridge that manages many application-specific
channels. Each channel has:

- one canonical L1 settlement environment
- one L2 state represented by a vector of Merkle roots
- one distinguished L2 token-vault storage domain
- zero or more additional L2 application-storage domains
- one associated DApp definition

The bridge uses two proof systems:

- a Groth16 proof system for token-vault balance updates
- a Tokamak zk-EVM proof system for general channel transaction execution

The purpose of the bridge is to ensure that every authoritative channel-state
transition accepted on L1 is justified by a valid proof and is compatible with
the registered DApp metadata of the channel.

## 2. Mathematical Objects

### 2.1 Basic sets

Let:

- `D` be the set of registered DApps
- `C` be the set of registered channels
- `U` be the set of users
- `A` be the set of storage-domain addresses
- `K` be the set of storage keys
- `V` be the set of storage values
- `R` be the set of Merkle roots
- `H` be the set of 256-bit hash values

### 2.2 DApp-level objects

For each DApp `d ∈ D`, define:

- `S_d = (s_d,0, ..., s_d,n-1)` as the ordered vector of storage domains used by `d`
- `tv(d) ∈ {0, ..., n-1}` as the distinguished index of the token-vault storage domain
- `F_d` as the set of functions supported by `d`

The ordered vector `S_d` is shared by all functions of the same DApp. Therefore:

- every function of `d` uses the same root-vector length `|S_d|`
- every function of `d` uses the same token-vault-tree position `tv(d)`

For each function `f ∈ F_d`, define metadata:

- `id(f)` as the abstract function identifier
- `p(f) ∈ H` as the preprocess commitment associated with `f`
- `L(f)` as the abstract layout description needed to interpret the proof's public inputs
- `W(f)` as the ordered set of storage-write descriptors associated with `f`

The bridge does not need to model the exact syntax of `L(f)`. It is sufficient that
`L(f)` deterministically specifies how to extract from the public inputs:

- the called function identifier
- the pre-state root vector
- the post-state root vector
- the storage writes declared by the proof

### 2.3 Channel-level objects

For each channel `c ∈ C`, define:

- `d(c) ∈ D` as the DApp selected by channel `c`
- `S_c := S_d(c)` as the channel storage-domain vector
- `tv(c) := tv(d(c))` as the token-vault-tree position
- `g(c) ∈ R^{|S_c|}` as the genesis root vector
- `h(c) ∈ H` as the hash of the current root vector
- `b(c) ∈ H` as the channel-scoped block-context commitment

The bridge stores `h(c)` as the authoritative compact commitment to the current
channel state. The full root vector may be supplied or revealed at transition time,
but the bridge state itself is modeled by `h(c)`.

### 2.4 Token-vault registration objects

For each channel `c`, define:

- `Reg_c ⊆ U × K × I` as the user registration relation for the L2 token-vault domain
- `I = {0, ..., 2^m - 1}` as the set of token-vault leaf indices, where `m` is the
  bridge's Merkle-tree depth

For `(u, k, i) ∈ Reg_c`:

- `k` is the user's registered L2 token-vault key in channel `c`
- `i` is the deterministic leaf index derived from `k`

The registration relation is constrained by:

- uniqueness of the registered key per `(c, u)`
- uniqueness of the registered key globally across all channels
- uniqueness of the derived leaf index within a channel

## 3. State Model

### 3.1 Root-vector model

For each channel `c`, the L2 state is represented by a root vector

`ρ_c = (r_c,0, ..., r_c,n-1) ∈ R^{|S_c|}`.

The bridge stores only `h(c) = Hash(ρ_c)`.

The token-vault root is always:

`ρ_c[tv(c)]`.

All other entries represent application storage domains.

### 3.2 Genesis

Each channel starts from a deterministic genesis root vector `g(c)`. The genesis
transition is the only channel-state initialization that is not justified by a user
submitted zero-knowledge proof.

### 3.3 Proof-backed updates

After genesis, every accepted mutation of the current root commitment `h(c)` must
come from one of exactly two proof-backed transition classes:

- a Groth16 token-vault update
- a Tokamak channel-transaction update

No other transition may alter the authoritative channel-state commitment.

## 4. Transition Systems

### 4.1 Channel creation

`CreateChannel(d, b)` creates a new channel `c` such that:

- `d(c) = d`
- `S_c = S_d`
- `tv(c) = tv(d)`
- `b(c) = b`
- `h(c) = Hash(g(c))`

### 4.2 Token-vault registration

`RegisterUser(c, u, k)` is admissible only if:

- `u` has no prior token-vault registration in `c`
- `k` is not already registered anywhere else in the system
- the derived leaf index `i = LeafIndex(k)` is unused within `c`

The post-state adds `(u, k, i)` to `Reg_c`.

### 4.3 Groth16 vault update

A Groth update acts only on the token-vault component of a channel state.

Let:

- `ρ` be the current root vector of channel `c`
- `ρ'` be the next root vector

A Groth transition is admissible only if:

- `Hash(ρ) = h(c)`
- `ρ_j = ρ'_j` for all `j ≠ tv(c)`
- the Groth proof is valid for the token-vault transition from `ρ_tv(c)` to `ρ'_tv(c)`
- the submitted user key is consistent with the user's registration in `Reg_c`
- the associated L1 balance adjustment is valid for the claimed deposit or withdrawal

The post-state is:

- `h(c) := Hash(ρ')`
- the relevant L1 vault balance record is updated

### 4.4 Tokamak channel transaction

A Tokamak channel transaction acts on one function `f ∈ F_d(c)`.

Let:

- `ρ` be the current root vector of channel `c`
- `ρ'` be the next root vector
- `x` be the public-input payload interpreted under layout `L(f)`

A Tokamak transition is admissible only if:

- `Hash(ρ) = h(c)`
- the function identifier extracted from `x` equals `id(f)`
- the preprocess commitment submitted with the proof matches `p(f)`
- the channel-scoped block-context commitment submitted with the proof matches `b(c)`
- the pre-state root vector extracted from `x` equals `ρ`
- the post-state root vector extracted from `x` equals `ρ'`
- the declared storage writes extracted from `x` are compatible with `W(f)`
- the Tokamak proof is valid for the submitted execution statement

The post-state is:

- `h(c) := Hash(ρ')`

If the Tokamak transaction changes the token-vault component, then the token-vault
root transition still remains governed by the same distinguished token-vault position
`tv(c)` inside the shared root vector.

## 5. Observability Model

The bridge stores only the current root commitment `h(c)`, not an on-chain history
of full root vectors. Therefore any mechanism that allows off-chain reconstruction of
the full pre-state or the storage writes of an accepted transition belongs to the
observability layer rather than to the abstract state itself.

For analysis purposes, it is enough to require:

- each accepted proof-backed transition makes the relevant pre-state root vector
  observable to off-chain verifiers
- each accepted storage update makes the corresponding storage-write information
  observable to off-chain verifiers

The exact transport mechanism is intentionally left unspecified here.

## 6. Invariants

The bridge is intended to maintain the following invariants.

### 6.1 DApp-structure invariants

For every DApp `d`:

- all functions of `d` share the same ordered storage-domain vector `S_d`
- exactly one storage-domain position of `S_d` is designated as the token-vault position
- each registered function has a unique identifier within `d`
- each registered function has a nonzero preprocess commitment

### 6.2 Channel-state invariants

For every channel `c`:

- `d(c)` is fixed for the lifetime of the channel
- `S_c` and `tv(c)` are fixed for the lifetime of the channel
- `b(c)` is fixed unless the protocol explicitly defines an authorized update rule
- after genesis, every change of `h(c)` is proof-backed

### 6.3 Token-vault invariants

For every channel `c`:

- each registered user has at most one registered token-vault key
- each registered token-vault key is globally unique
- each derived token-vault leaf index is unique within `c`
- Groth deposit and withdrawal transitions may change only the token-vault root entry

### 6.4 Tokamak soundness invariants

For every accepted Tokamak transition in channel `c`:

- the proof is checked against metadata of the selected function of `d(c)`
- the submitted preprocess commitment is the one registered for that function
- the pre-state root vector used by the proof matches the channel's current root commitment
- the post-state root vector committed by the channel is the one justified by the proof

## 7. Security Goals

At the abstract level, the bridge aims to satisfy:

- state-integrity: no channel-state commitment changes without an authorized proof-backed transition
- custody-integrity: no L1 settlement balance changes without a valid token-vault transition
- function-binding: a Tokamak proof cannot be reused as if it were for another function
- channel-binding: a proof valid for one channel cannot be replayed as if it were for another channel context
- token-vault-position consistency: the token-vault storage domain remains fixed within a channel's root vector

## 8. Deliberate Omissions

This document intentionally does not specify:

- concrete Solidity interfaces
- calldata encodings
- event names or event payload layouts
- internal storage packing
- caching strategies
- off-chain script structure

Those belong to developer documentation and implementation notes rather than to the
abstract bridge specification.

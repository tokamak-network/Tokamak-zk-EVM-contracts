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

- \(D\) be the set of registered DApps
- \(C\) be the set of registered channels
- \(U\) be the set of users
- \(A\) be the set of storage-domain addresses
- \(K\) be the set of storage keys
- \(V\) be the set of storage values
- \(R\) be the set of Merkle roots
- \(H\) be the set of 256-bit hash values

Let the current bridge constants be:

- \(m = 12\), the fixed Merkle-tree depth accepted by the bridge
- \(N = 2^m = 4096\), the corresponding token-vault leaf-capacity bound
- \(M = 11\), the maximum number of storage domains allowed in one DApp

Let \(F_{\mathrm{BLS}}\) denote the scalar field used by the current Groth16 circuit.

### 2.2 DApp-level objects

For each DApp \(d \in D\), define:

- \(S_d = (s_{d,0}, \ldots, s_{d,n-1})\) as the ordered vector of storage domains used by \(d\)
- \(tv(d) \in \{0, \ldots, n-1\}\) as the distinguished index of the token-vault storage domain
- \(F_d\) as the set of functions supported by \(d\)

The current bridge admits only DApps satisfying:

- \(1 \le |S_d| \le M\)
- \(|F_d| \ge 1\)
- \(\exists! \, i \in \{0, \ldots, |S_d|-1\}\) such that \(i = tv(d)\)

The ordered vector \(S_d\) is shared by all functions of the same DApp. Therefore:

- \(\forall f \in F_d,\ \text{the root-vector length used by } f \text{ is } |S_d|\)
- \(\forall f \in F_d,\ \text{the token-vault position used by } f \text{ is } tv(d)\)

For each function \(f \in F_d\), define metadata:

- \(id(f)\) as the abstract function identifier
- \(p(f) \in H\) as the preprocess commitment associated with \(f\)
- \(L(f)\) as the abstract layout description needed to interpret the proof's public inputs
- \(W(f)\) as the ordered set of storage-write descriptors associated with \(f\)

The current bridge further requires:

- \(p(f) \ne 0\)
- \(\forall f_1, f_2 \in F_d,\ f_1 \ne f_2 \Rightarrow p(f_1) \ne p(f_2)\)
- every descriptor in \(W(f)\) points to some valid storage-domain position of \(S_d\)

The bridge does not need to model the exact syntax of \(L(f)\). It is sufficient that
\(L(f)\) deterministically specifies how to extract from the public inputs:

- the called function identifier
- the pre-state root vector
- the post-state root vector
- the storage writes declared by the proof

### 2.3 Channel-level objects

For each channel \(c \in C\), define:

- \(d(c) \in D\) as the DApp selected by channel \(c\)
- \(leader(c)\) as the distinguished coordinator address of channel \(c\)
- \(asset(c)\) as the L1 settlement asset of channel \(c\)
- \(S_c := S_{d(c)}\) as the channel storage-domain vector
- \(tv(c) := tv(d(c))\) as the token-vault-tree position
- \(g(c) \in R^{|S_c|}\) as the genesis root vector
- \(h(c) \in H\) as the hash of the current root vector
- \(b(c) \in H\) as the channel-scoped block-context commitment

The current bridge admits only channels satisfying:

- \(leader(c) \ne 0\)
- \(asset(c) \ne 0\)
- \(b(c) \ne 0\)
- \(|S_c| = |S_{d(c)}| \le M\)

The bridge stores \(h(c)\) as the authoritative compact commitment to the current
channel state. The full root vector may be supplied or revealed at transition time,
but the bridge state itself is modeled by \(h(c)\).

### 2.4 Token-vault registration objects

For each channel \(c\), define:

- \(Reg_c \subseteq U \times K \times I\) as the user registration relation for the L2 token-vault domain
- \(I = \{0, \ldots, 2^m - 1\}\) as the set of token-vault leaf indices

For \((u, k, i) \in Reg_c\):

- \(k\) is the user's registered L2 token-vault key in channel \(c\)
- \(i\) is the deterministic leaf index derived from \(k\)

The registration relation is constrained by:

- uniqueness of the registered key per \((c, u)\)
- uniqueness of the registered key globally across all channels
- uniqueness of the derived leaf index within a channel

For the current bridge, the deterministic derivation is

\[
i = LeafIndex(k) = k \bmod N,
\]

where \(k\) is interpreted as an integer representative of the registered storage key.

Each registration also carries an L1 available-balance component:

- \(bal(c,u) \in \mathbb{N}\)

with initial registration requiring a positive funded amount.

### 2.5 Asset-behavior assumption

The current bridge accepts only assets that behave as exact-transfer tokens. Abstractly,
for any admissible transfer of amount \(a > 0\):

- the sender-side balance decreases by exactly \(a\)
- the recipient-side balance increases by exactly \(a\)

Assets with fee-on-transfer or other balance-distorting semantics are outside the
supported asset model.

## 3. State Model

### 3.1 Root-vector model

For each channel \(c\), the L2 state is represented by a root vector

\[
\rho_c = (r_{c,0}, \ldots, r_{c,n-1}) \in R^{|S_c|}.
\]

The bridge stores only

\[
h(c) = Hash(\rho_c).
\]

The token-vault root is always

\[
\rho_c[tv(c)].
\]

All other entries represent application storage domains.

### 3.2 Genesis

Each channel starts from a deterministic genesis root vector \(g(c)\). The genesis
transition is the only channel-state initialization that is not justified by a user
submitted zero-knowledge proof.

### 3.3 Proof-backed updates

After genesis, every accepted mutation of the current root commitment \(h(c)\) must
come from one of exactly two proof-backed transition classes:

- a Groth16 token-vault update
- a Tokamak channel-transaction update

No other transition may alter the authoritative channel-state commitment.

## 4. Transition Systems

### 4.1 Channel creation

\[
CreateChannel(d,b) = c
\]

creates a new channel \(c\) such that:

- \(d(c) = d\)
- \(S_c = S_d\)
- \(tv(c) = tv(d)\)
- \(b(c) = b\)
- \(h(c) = Hash(g(c))\)

It is admissible only if:

- \(d\) is already registered
- \(b \ne 0\)
- the bridge Merkle-tree parameter equals the fixed supported depth \(m\)
- \(|S_d| \le M\)

### 4.2 Token-vault registration

\[
RegisterUser(c,u,k)
\]

is admissible only if:

- \(u\) has no prior token-vault registration in \(c\)
- \(k\) is not already registered anywhere else in the system
- the derived leaf index \(i = LeafIndex(k)\) is unused within \(c\)
- the initial funded amount is strictly positive

The post-state adds \((u,k,i)\) to \(Reg_c\).

### 4.3 Groth16 vault update

A Groth update acts only on the token-vault component of a channel state.

Let:

- \(\rho\) be the current root vector of channel \(c\)
- \(\rho'\) be the next root vector

A Groth transition is admissible only if:

- \(Hash(\rho) = h(c)\)
- \(\rho_j = \rho'_j\) for all \(j \ne tv(c)\)
- the Groth proof is valid for the token-vault transition from \(\rho_{tv(c)}\) to \(\rho'_{tv(c)}\)
- the submitted user key is consistent with the user's registration in \(Reg_c\)
- the associated L1 balance adjustment is valid for the claimed deposit or withdrawal
- the submitted current and updated L2 values lie in \(F_{\mathrm{BLS}}\)

More specifically:

- for deposit, the updated L2 value must be strictly larger than the current L2 value
  and the L1 available balance must cover the increase
- for withdrawal, the current L2 value must be strictly larger than the updated L2 value

The post-state is:

- \(h(c) := Hash(\rho')\)
- the relevant L1 vault balance record is updated

### 4.4 Tokamak channel transaction

A Tokamak channel transaction acts on one function \(f \in F_{d(c)}\).

Let:

- \(\rho\) be the current root vector of channel \(c\)
- \(\rho'\) be the next root vector
- \(x\) be the public-input payload interpreted under layout \(L(f)\)

A Tokamak transition is admissible only if:

- \(Hash(\rho) = h(c)\)
- the function identifier extracted from \(x\) equals \(id(f)\)
- the preprocess commitment submitted with the proof matches \(p(f)\)
- the channel-scoped block-context commitment submitted with the proof matches \(b(c)\)
- the pre-state root vector extracted from \(x\) equals \(\rho\)
- the post-state root vector extracted from \(x\) equals \(\rho'\)
- the declared storage writes extracted from \(x\) are compatible with \(W(f)\)
- the Tokamak proof is valid for the submitted execution statement
- the public-input payload is long enough to contain all fields required by \(L(f)\)
- any decoded word used as a split-field component lies in the \(128\)-bit range assumed by the bridge decoder
- any decoded function identifier lies in the valid range of its target type
- any decoded contract identifier lies in the valid range of an address

The post-state is:

- \(h(c) := Hash(\rho')\)

If the Tokamak transaction changes the token-vault component, then the token-vault
root transition still remains governed by the same distinguished token-vault position
\(tv(c)\) inside the shared root vector.

The current bridge adds one more admissibility guard:

- if \(\rho'_{tv(c)} \ne \rho_{tv(c)}\), then the storage writes declared by the proof
  must include at least one write to the token-vault storage domain

## 5. Observability Model

The bridge stores only the current root commitment \(h(c)\), not an on-chain history
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

For every DApp \(d\):

- all functions of \(d\) share the same ordered storage-domain vector \(S_d\)
- exactly one storage-domain position of \(S_d\) is designated as the token-vault position
- each registered function has a unique identifier within \(d\)
- each registered function has a nonzero preprocess commitment
- preprocess commitments are unique within \(d\)
- each storage-write descriptor of each function points to a valid index of \(S_d\)

### 6.2 Channel-state invariants

For every channel \(c\):

- \(d(c)\) is fixed for the lifetime of the channel
- \(S_c\) and \(tv(c)\) are fixed for the lifetime of the channel
- \(b(c)\) is fixed unless the protocol explicitly defines an authorized update rule
- after genesis, every change of \(h(c)\) is proof-backed
- the token-vault storage address of \(c\) is fixed by \(tv(c)\) and never relocates

### 6.3 Token-vault invariants

For every channel \(c\):

- each registered user has at most one registered token-vault key
- each registered token-vault key is globally unique
- each derived token-vault leaf index is unique within \(c\)
- Groth deposit and withdrawal transitions may change only the token-vault root entry
- only exact-transfer assets belong to the supported custody model

### 6.4 Tokamak soundness invariants

For every accepted Tokamak transition in channel \(c\):

- the proof is checked against metadata of the selected function of \(d(c)\)
- the submitted preprocess commitment is the one registered for that function
- the pre-state root vector used by the proof matches the channel's current root commitment
- the post-state root vector committed by the channel is the one justified by the proof
- if the token-vault root changes, the proof must also declare a token-vault storage write

## 7. Security Goals

At the abstract level, the bridge aims to satisfy:

- state-integrity: no channel-state commitment changes without an authorized proof-backed transition
- custody-integrity: no L1 settlement balance changes without a valid token-vault transition
- function-binding: a Tokamak proof cannot be reused as if it were for another function
- channel-binding: a proof valid for one channel cannot be replayed as if it were for another channel context
- token-vault-position consistency: the token-vault storage domain remains fixed within a channel's root vector
- key-registration integrity: no two users can legitimately claim the same registered token-vault key
- leaf-position integrity: no two users in one channel can legitimately occupy the same token-vault leaf position
- asset-model integrity: settlement assumes exact-transfer ERC-20 behavior and rejects assets that violate that assumption

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

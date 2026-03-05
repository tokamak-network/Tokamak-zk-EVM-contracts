# Tokamak Private App Channels - Bridge Contract

### General

브릿지 컨트랙트는 다수의 채널 정보를 기록 및 관리한다.

$\mathbb{F}_{b}$ 는 $b$-bit word의 field이다.

### Bridge manager

The Bridge Manager maintains normalized state for three core objects: $\mathbb{A}, \mathbb{T}, \mathbb{F}$.  
All getter and setter functions are derived from these definitions.

#### Domains

- $G := \texttt{FcnSigs}$
- $S := \texttt{StorageAddrs}$
- $K := \mathbb{F}_{256}$ (pre-allocated key domain)
- $U := \mathbb{F}_{8}$ (user slot domain)
- $I := \mathbb{F}_{256}$ (instance hash domain)
- $P := \mathbb{F}_{256}$ (preprocess hash domain)
- $H := I \times P$

#### Normalized canonical form

Define the state as three maps over finite sets:

- $A: G \to \mathcal{P}_{\mathrm{fin}}(S)$
- $T: S \to \mathcal{P}_{\mathrm{fin}}(K)\times\mathcal{P}_{\mathrm{fin}}(U)$
- $F: G \to H_{\bot}$, where $H_{\bot}:=H\cup\{\bot\}$ and $\bot$ means "unset"

This form is normalization-oriented for simple updates:

- $A$ stores only membership of storage addresses per function signature.
- $T$ stores only membership of pre-allocated keys and user slots per storage address.
- $F$ stores exactly one config pair (or unset) per function signature.

#### Equivalent relational graphs

The map form above is equivalent to these relations:

- $\mathbb{A}:=\{(f,s)\in G\times S\mid s\in A(f)\}$
- $\mathbb{T}_K:=\{(s,k)\in S\times K\mid k\in\pi_1(T(s))\}$
- $\mathbb{T}_U:=\{(s,u)\in S\times U\mid u\in\pi_2(T(s))\}$
- $\mathbb{F}:=\{(f,h)\in G\times H\mid F(f)=h\neq\bot\}$

where $\pi_1,\pi_2$ are first and second projections.

#### Derived getters

- $\texttt{GetFcnStorages}(f):=A(f)$
- $\texttt{GetPreAllocKeys}(s):=\pi_1(T(s))$
- $\texttt{GetUserSlots}(s):=\pi_2(T(s))$
- $\texttt{GetTreeCfg}(s):=(\pi_1(T(s)),\pi_2(T(s)))$
- $\texttt{GetFcnCfg}(f):=F(f)\in H_{\bot}$

Batch getters are pure set comprehensions:

- $\texttt{GetTreeCfgs}(X):=\{(s,T(s))\mid \exists f\in X,\ s\in A(f)\}$
- $\texttt{GetFcnCfgs}(X):=\{(f,F(f))\mid f\in X,\ F(f)\neq\bot\}$

#### Setter semantics

Let $f\in G$, $s\in S$, $k\in K$, $u\in U$, $h\in H$.  
Each setter is a primitive set insertion/deletion or single overwrite:

- $\texttt{AddStorageAddr}(f,s):\ A(f)\leftarrow A(f)\cup\{s\}$
- $\texttt{DelStorageAddr}(f,s):\ A(f)\leftarrow A(f)\setminus\{s\}$
- $\texttt{AddPreAllocKey}(s,k):\ \pi_1(T(s))\leftarrow \pi_1(T(s))\cup\{k\}$
- $\texttt{DelPreAllocKey}(s,k):\ \pi_1(T(s))\leftarrow \pi_1(T(s))\setminus\{k\}$
- $\texttt{AddUserSlot}(s,u):\ \pi_2(T(s))\leftarrow \pi_2(T(s))\cup\{u\}$
- $\texttt{DelUserSlot}(s,u):\ \pi_2(T(s))\leftarrow \pi_2(T(s))\setminus\{u\}$
- $\texttt{SetFcnCfg}(f,h):\ F(f)\leftarrow h$
- $\texttt{ClearFcnCfg}(f):\ F(f)\leftarrow \bot$

#### Stability and consistency invariants

- (Set uniqueness) $A(f)$, $\pi_1(T(s))$, and $\pi_2(T(s))$ are sets, so duplicate inserts are idempotent.
- (Read-after-write) Each setter immediately changes the corresponding getter result by construction.
- (Single-valued config) $F$ is a function, so one $f$ has at most one active $(\texttt{instanceHash},\texttt{preprocessHash})$ pair.
- (Total getter behavior) For unseen keys, use defaults:
  - $A(f)=\varnothing$
  - $T(s)=(\varnothing,\varnothing)$
  - $F(f)=\bot$

These defaults eliminate undefined reads and keep getter logic branch-minimal.

### Channel

브릿지 컨트랙트가 관리하는 각 채널은 다음의 변수들로 구성되어있다:

- Length params
    - $\texttt{nUsers}\in\mathbb{F}_{16}$
    - $\texttt{nAppFcns}\in\mathbb{F_{16}}$
    - $\texttt{nRootTrans}\in\mathbb{F_{16}}$
- Variables
    - $\texttt{UserAddrs}:=\{\texttt{userAddr}_i\in\mathbb{F}_{256}\mid i\in[\texttt{nUsers}]\}$
    - $\texttt{AppFcnSigs}:=\{\texttt{appFcnSig}_i\in\texttt{FcnSigs}\}_{i\in[\texttt{nAppFcns}]}$
    - $\texttt{AppStorageAddrs}:=\texttt{GetFcnStorages}(\texttt{AppFcnSigs})$
    - $\texttt{nAppTrees}:=|\texttt{AppStorageAddrs}|\in\mathbb{F}_{16}$
    - $\texttt{StateRootsTr}:=\{\texttt{stateRoots}_i\in\mathbb{F_{256}}^{\texttt{nAppStorages}}\mid i\in[\texttt{nRootTrans]}\}$
    - $\texttt{AppTreeCfgs}:=\texttt{GetTreeCfgs}(\texttt{AppFcnSigs})$
    - $\texttt{AppFcnCfgs}:=\texttt{GetFcnCfgs}(\texttt{AppFcnSigs})$
    - $\texttt{ChannelStorageKeys}:=\{\texttt{chStorageKey}_{i,k}\in\mathbb{F}_{256}\mid i\in[\texttt{nUsers}],k\in[\texttt{nAppStorages}]\}$
    - $\texttt{ValidatedStorageValues}:=\{\texttt{value}_{i,k}\in\mathbb{F}_{256}\mid i\in[\texttt{nUsers}],k\in[\texttt{nAppStorages}]\}$
- Structures
    - $\mathbb{K}:=\{(\texttt{userAddr},\texttt{storageAddr},\texttt{key})\in\texttt{UserAddrs}\times\texttt{AppStorageAddrs}\times\texttt{ChannelStorageKeys}\}$
    - $\mathbb{V}:=\{(\texttt{storageAddr},\texttt{chStorageKey},\texttt{value})\in\texttt{AppStorageAddrs}\times\texttt{ChannelStorageKeys}\times\texttt{ValidatedStorageValues}\}$
- Functions
    - $\texttt{GetChainStorageKey}:\texttt{UserAddr}\times\texttt{AppStorageAddrs}\to \mathbb{F_{256}}$
        - $\texttt{GetChainStorageKey}(u,s):=\texttt{Keccak256}(u,t)\ \text{where}\ \texttt{TreeInfo}(s)=(p,t)$
    - $\texttt{GetChannelStorageKey}:\texttt{UserAddr}\times\texttt{AppStorageAddrs}\to\texttt{ChannelStorageKeys}$
        - $\texttt{GetChannelStorageKey}(u,s):=k\ \text{where}\ (u,s,k)\in\mathbb{K}$
    - $\texttt{GetValidatedStorageValue}:\texttt{AppStorageAddrs}\times\texttt{ChannelStorageKeys}\to\texttt{ValidatedStorageValues}$
        - $\texttt{GetValidatedStorageValue}(s,k):=v\ \text{where}\ (s,k,v)\in\mathbb{V}$
    - $\texttt{UpdateValidatedStorageValue}:\texttt{AppStorageAddrs}\times\texttt{ChannelStorageKeys}\times\texttt{ValidatedStorageValues}\to \mathbb{V}$

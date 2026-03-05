# Tokamak Private App Channels - Bridge Contract

### General

브릿지 컨트랙트는 다수의 채널 정보를 기록 및 관리한다.

$\mathbb{F}_{b}$ 는 $b$-bit word의 field이다.

### Bridge manager

The Bridge Manager maintains normalized state for three core relations: $\mathbb{A}, \mathbb{T}, \mathbb{F}$.  
All getter and setter functions are derived from these definitions.

#### Primary normalized relations

The primary state is relational (not map-first):

Let $G := \texttt{FcnSigs}$, $S := \texttt{StorageAddrs}$, $K := \mathbb{F}_{256}$, $U := \mathbb{F}_{8}$, $I := \mathbb{F}_{256}$, $P := \mathbb{F}_{256}$, and $H := I \times P$.

- $\mathbb{A} \subseteq G\times S$
- $\mathbb{T}_K \subseteq S\times K$
- $\mathbb{T}_U \subseteq S\times U$
- $\mathbb{T} := (\mathbb{T}_K, \mathbb{T}_U)$
- $\mathbb{F} \subseteq G\times H$

Semantics:

- $\mathbb{A}$ pairs one function signature with a set of storage addresses.
- $\mathbb{T}$ pairs one storage address with a pair of sets: pre-allocated keys and user slots.
- $\mathbb{F}$ pairs one function signature with one $(\texttt{instanceHash},\texttt{preprocessHash})$ pair.

Functional constraint for $\mathbb{F}$:

- $\forall f\in G,\ \forall h_1,h_2\in H,\ ((f,h_1)\in\mathbb{F}\wedge(f,h_2)\in\mathbb{F})\Rightarrow h_1=h_2$

#### Derived maps from relations

Maps are derived views and are not primary state:

- $\mathbb{A}^{\sharp}: G\to \mathcal{P}_{\mathrm{fin}}(S),\quad \mathbb{A}^{\sharp}(f):=\{s\in S\mid(f,s)\in\mathbb{A}\}$
- $\mathbb{T}^{\sharp}: S\to \mathcal{P}_{\mathrm{fin}}(K)\times\mathcal{P}_{\mathrm{fin}}(U)$
- $\mathbb{T}^{\sharp}(s):=\left(\{k\in K\mid(s,k)\in\mathbb{T}_K\},\ \{u\in U\mid(s,u)\in\mathbb{T}_U\}\right)$
- $\mathbb{F}^{\sharp}: G\to H_{\bot},\quad H_{\bot}:=H\cup\{\bot\}$
- $\mathbb{F}^{\sharp}(f):=\begin{cases}
    h & \text{if }(f,h)\in\mathbb{F}\\
    \bot & \text{if }\nexists h\in H:(f,h)\in\mathbb{F}
  \end{cases}$

#### Derived getters

- $\texttt{GetFcnStorages}(f):=\mathbb{A}^{\sharp}(f)$
- $\texttt{GetPreAllocKeys}(s):=\pi_1(\mathbb{T}^{\sharp}(s))$
- $\texttt{GetUserSlots}(s):=\pi_2(\mathbb{T}^{\sharp}(s))$
- $\texttt{GetTreeCfg}(s):=\mathbb{T}^{\sharp}(s)$
- $\texttt{GetFcnCfg}(f):=\mathbb{F}^{\sharp}(f)\in H_{\bot}$

Batch getters are pure set comprehensions:

- $\texttt{GetTreeCfgs}(X):=\{(s,\mathbb{T}^{\sharp}(s))\mid \exists f\in X:(f,s)\in\mathbb{A}\}$
- $\texttt{GetFcnCfgs}(X):=\{(f,h)\mid f\in X,\ (f,h)\in\mathbb{F}\}$

#### Setter semantics

Let $f\in G$, $s\in S$, $k\in K$, $u\in U$, $h\in H$.  
Each setter is a direct relational update:

- $\texttt{AddStorageAddr}(f,s):\ \mathbb{A}\leftarrow\mathbb{A}\cup\{(f,s)\}$
- $\texttt{DelStorageAddr}(f,s):\ \mathbb{A}\leftarrow\mathbb{A}\setminus\{(f,s)\}$
- $\texttt{AddPreAllocKey}(s,k):\ \mathbb{T}_K\leftarrow\mathbb{T}_K\cup\{(s,k)\}$
- $\texttt{DelPreAllocKey}(s,k):\ \mathbb{T}_K\leftarrow\mathbb{T}_K\setminus\{(s,k)\}$
- $\texttt{AddUserSlot}(s,u):\ \mathbb{T}_U\leftarrow\mathbb{T}_U\cup\{(s,u)\}$
- $\texttt{DelUserSlot}(s,u):\ \mathbb{T}_U\leftarrow\mathbb{T}_U\setminus\{(s,u)\}$
- $\texttt{SetFcnCfg}(f,h):\ \mathbb{F}\leftarrow\left(\mathbb{F}\setminus\{(f,h')\mid h'\in H\}\right)\cup\{(f,h)\}$
- $\texttt{ClearFcnCfg}(f):\ \mathbb{F}\leftarrow\mathbb{F}\setminus\{(f,h')\mid h'\in H\}$

#### Stability and consistency invariants

- (Set uniqueness) $\mathbb{A}$, $\mathbb{T}_K$, and $\mathbb{T}_U$ are sets of tuples, so repeated insertions are idempotent.
- (Read-after-write) Each relational update immediately changes the corresponding derived getter.
- (Single-valued config) Functionality of $\mathbb{F}$ guarantees at most one active config for each $f$.
- (Total getter behavior) For unseen keys in derived maps:
  - $\mathbb{A}^{\sharp}(f)=\varnothing$
  - $\mathbb{T}^{\sharp}(s)=(\varnothing,\varnothing)$
  - $\mathbb{F}^{\sharp}(f)=\bot$

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

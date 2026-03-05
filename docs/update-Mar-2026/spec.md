# Tokamak Private App Channels - Bridge Contract

### General

브릿지 컨트랙트는 다수의 채널 정보를 기록 및 관리한다.

$\mathbb{F}_{b}$ 는 $b$-bit word의 field이다.

### Bridge manager

#### Primary relations
- $\mathcal{A} \subset \mathbb{F}_{32}\times \mathbb{F}_{160}$
  - This relation pairs function signatures with storage addresses.
- $\mathcal{P} \subset \mathbb{F}_{160}\times \mathbb{F}_{256}$
  - This relation pairs storage addresses with pre-allocated keys.
- $\mathcal{U} \subset \mathbb{F}_{160}\times \mathbb{F}_{8}$
  - This relation pairs storage addresses with user storage slots.
- $\mathcal{F} \subset \mathbb{F}_{32}\times \mathbb{F}_{256} \times \mathbb{F}_{256}$
  - This relation pairs function signatures with pairs of an instance hash and a preprocess hash.
  - Uniqueness: $\forall f\in\mathbb{F}_{32},\ \forall i_1,p_1,i_2,p_2\in\mathbb{F}_{256},\ ((f,i_1,p_1)\in\mathcal{F}\wedge(f,i_2,p_2)\in\mathcal{F})\Rightarrow(i_1=i_2\wedge p_1=p_2)$

#### Getters

Exactly one getter is defined per primary relation:

- For $\mathcal{A}$:
  - $\texttt{GetFcnStorages}:\mathbb{F}_{32}\to\mathcal{P}(\mathbb{F}_{160})$
  - $\texttt{GetFcnStorages}(f):=\{s\in\mathbb{F}_{160}\mid (f,s)\in\mathcal{A}\}$
- For $\mathcal{P}$:
  - $\texttt{GetPreAllocKeys}:\mathbb{F}_{160}\to\mathcal{P}(\mathbb{F}_{256})$
  - $\texttt{GetPreAllocKeys}(s):=\{k\in\mathbb{F}_{256}\mid (s,k)\in\mathcal{P}\}$
- For $\mathcal{U}$:
  - $\texttt{GetUserSlots}:\mathbb{F}_{160}\to\mathcal{P}(\mathbb{F}_{8})$
  - $\texttt{GetUserSlots}(s):=\{u\in\mathbb{F}_{8}\mid (s,u)\in\mathcal{U}\}$
- For $\mathcal{F}$:
  - $\texttt{GetFcnCfg}:\mathbb{F}_{32}\to(\mathbb{F}_{256}\times\mathbb{F}_{256})_{\bot}$
  - $\texttt{GetFcnCfg}(f):=\begin{cases}
      (i,p) & \text{if } (f,i,p)\in\mathcal{F}\\
      \bot & \text{if } \nexists(i,p)\in\mathbb{F}_{256}\times\mathbb{F}_{256}:\ (f,i,p)\in\mathcal{F}
    \end{cases}$

### Channel

브릿지 컨트랙트가 관리하는 각 채널은 다음의 변수들로 구성되어있다:

- Length params
    - $\texttt{nUsers}\in\mathbb{F}_{16}$
    - $\texttt{nAppFcns}\in\mathbb{F_{16}}$
    - $\texttt{nRootTrans}\in\mathbb{F_{16}}$
- Variables
    - $\texttt{UserAddrs}:=\{\texttt{userAddr}_i\in\mathbb{F}_{256}\mid i\in[\texttt{nUsers}]\}$
    - $\texttt{AppFcnSigs}:=\{\texttt{appFcnSig}_i\in\texttt{FcnSigs}\}_{i\in[\texttt{nAppFcns}]}$
    - $\texttt{AppStorageAddrs}:=\bigcup_{f\in\texttt{AppFcnSigs}}\texttt{GetFcnStorages}(f)$
    - $\texttt{nAppTrees}:=|\texttt{AppStorageAddrs}|\in\mathbb{F}_{16}$
    - $\texttt{StateRootsTr}:=\{\texttt{stateRoots}_i\in\mathbb{F_{256}}^{\texttt{nAppStorages}}\mid i\in[\texttt{nRootTrans]}\}$
    - $\texttt{AppTreeCfgs}:=\{(s,\texttt{GetPreAllocKeys}(s),\texttt{GetUserSlots}(s))\mid s\in\texttt{AppStorageAddrs}\}$
    - $\texttt{AppFcnCfgs}:=\{(f,\texttt{GetFcnCfg}(f))\mid f\in\texttt{AppFcnSigs},\ \texttt{GetFcnCfg}(f)\neq\bot\}$
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

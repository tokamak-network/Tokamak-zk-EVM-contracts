# Tokamak Private App Channels - Bridge Contract

### General

브릿지 컨트랙트는 다수의 채널 정보를 기록 및 관리한다.

$\mathbb{F}_{b}$ 는 $b$-bit word의 field이다.

### Bridge manager

#### Primary relations
- $\mathcal{A} \subset \mathbb{F}_{32}\times \mathbb{F}_{160}$
  - This relation pairs function signatures with storage addresses.
  - Existence: $\forall f\in\mathbb{F}_{32},\ \exists s\in\mathbb{F}_{160},\ (f,s)\in\mathcal{A}$
- $\mathcal{P} \subset \mathbb{F}_{160}\times \mathbb{F}_{256}$
  - This relation pairs storage addresses with pre-allocated keys.
- $\mathcal{U} \subset \mathbb{F}_{160}\times \mathbb{F}_{8}$
  - This relation pairs storage addresses with user storage slots.
- $\mathcal{F} \subset \mathbb{F}_{32}\times \mathbb{F}_{256} \times \mathbb{F}_{256}$
  - This relation pairs function signatures with pairs of an instance hash and a preprocess hash.
  - Existence: $\forall f\in\mathbb{F}_{32},\ \exists i,p\in\mathbb{F}_{256},\ (f,i,p)\in\mathcal{F}$
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
  - $\texttt{GetFcnCfg}:\mathbb{F}_{32}\to\mathbb{F}_{256}\times\mathbb{F}_{256}$
  - $\texttt{GetFcnCfg}(f):=(i,p)\ \text{where}\ (f,i,p)\in\mathcal{F}$

### Channel

A channel is defined by a user set and a function-signature subset:

- $\texttt{UserAddrs}\subseteq\mathbb{F}_{256}$
- $\texttt{AppFcnSigs}\subseteq\{f\in\mathbb{F}_{32}\mid \exists s\in\mathbb{F}_{160},\ (f,s)\in\mathcal{A}\}$

Let the channel-local storage domain be:

- $\widetilde{S}:=\{s\in\mathbb{F}_{160}\mid \exists f\in\texttt{AppFcnSigs},\ (f,s)\in\mathcal{A}\}$

The channel manages exactly six relations:

- $\widetilde{\mathcal{A}}:=\mathcal{A}\cap\left(\texttt{AppFcnSigs}\times\mathbb{F}_{160}\right)$
- $\widetilde{\mathcal{P}}:=\mathcal{P}\cap\left(\widetilde{S}\times\mathbb{F}_{256}\right)$
- $\widetilde{\mathcal{U}}:=\mathcal{U}\cap\left(\widetilde{S}\times\mathbb{F}_{8}\right)$
- $\widetilde{\mathcal{F}}:=\mathcal{F}\cap\left(\texttt{AppFcnSigs}\times\mathbb{F}_{256}\times\mathbb{F}_{256}\right)$
- $\mathcal{K}\subseteq \texttt{UserAddrs}\times\widetilde{S}\times\mathbb{F}_{256}$
- $\mathcal{V}\subseteq \widetilde{S}\times\mathbb{F}_{256}\times\mathbb{F}_{256}$

By construction:

- $\widetilde{\mathcal{A}}\subseteq\mathcal{A}$
- $\widetilde{\mathcal{P}}\subseteq\mathcal{P}$
- $\widetilde{\mathcal{U}}\subseteq\mathcal{U}$
- $\widetilde{\mathcal{F}}\subseteq\mathcal{F}$

Channel key/value read relations:

- $\texttt{GetChannelStorageKey}(u,s):=k\ \text{where}\ (u,s,k)\in\mathcal{K}$
- $\texttt{GetValidatedStorageValue}(s,k):=v\ \text{where}\ (s,k,v)\in\mathcal{V}$

Consistency constraints:

- $\forall (u,s)\in\texttt{UserAddrs}\times\widetilde{S},\ \exists!k\in\mathbb{F}_{256},\ (u,s,k)\in\mathcal{K}$
- $\forall s\in\widetilde{S},\ \forall k\in\{k'\in\mathbb{F}_{256}\mid \exists u\in\texttt{UserAddrs},\ (u,s,k')\in\mathcal{K}\},\ \exists!v\in\mathbb{F}_{256},\ (s,k,v)\in\mathcal{V}$

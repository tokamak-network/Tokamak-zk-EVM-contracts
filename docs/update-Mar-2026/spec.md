# Tokamak Private App Channels - Bridge Contract

### General

The bridge contract records and manages channel data.

$\mathbb{F}_{b}$ is the field of $b$-bit words.

### Bridge manager

Let $\texttt{FcnSigns}\subseteq\mathbb{F}_{32}$ be the function-signature set managed by the bridge manager.

#### Primary relations

- $\mathcal{S} \subseteq \texttt{FcnSigns}\times \mathbb{F}_{160}$
  - This relation pairs function signatures with storage addresses.
  - Existence on managed signatures: $\forall f\in\texttt{FcnSigns},\ \exists s\in\mathbb{F}_{160},\ (f,s)\in\mathcal{S}$
- $\mathcal{P} \subseteq \mathbb{F}_{160}\times \mathbb{F}_{256}$
  - This relation pairs storage addresses with pre-allocated keys.
- $\mathcal{U} \subseteq \mathbb{F}_{160}\times \mathbb{F}_{8}$
  - This relation pairs storage addresses with user storage slots.
- $\mathcal{F} \subseteq \texttt{FcnSigns}\times \mathbb{F}_{256} \times \mathbb{F}_{256}$
  - This relation pairs function signatures with $(\texttt{instanceHash},\texttt{preprocessHash})$.
  - Existence on managed signatures: $\forall f\in\texttt{FcnSigns},\ \exists i,p\in\mathbb{F}_{256},\ (f,i,p)\in\mathcal{F}$
  - Uniqueness: $\forall f\in\texttt{FcnSigns},\ \forall i_1,p_1,i_2,p_2\in\mathbb{F}_{256},\ ((f,i_1,p_1)\in\mathcal{F}\wedge(f,i_2,p_2)\in\mathcal{F})\Rightarrow(i_1=i_2\wedge p_1=p_2)$

#### Getters

Exactly one getter is defined per primary relation:

- For $\mathcal{S}$:
  - $\texttt{GetFcnStorages}:\texttt{FcnSigns}\to\mathcal{P}(\mathbb{F}_{160})$
  - $\texttt{GetFcnStorages}(f):=\{s\in\mathbb{F}_{160}\mid (f,s)\in\mathcal{S}\}$
- For $\mathcal{P}$:
  - $\texttt{GetPreAllocKeys}:\mathbb{F}_{160}\to\mathcal{P}(\mathbb{F}_{256})$
  - $\texttt{GetPreAllocKeys}(s):=\{k\in\mathbb{F}_{256}\mid (s,k)\in\mathcal{P}\}$
- For $\mathcal{U}$:
  - $\texttt{GetUserSlots}:\mathbb{F}_{160}\to\mathcal{P}(\mathbb{F}_{8})$
  - $\texttt{GetUserSlots}(s):=\{u\in\mathbb{F}_{8}\mid (s,u)\in\mathcal{U}\}$
- For $\mathcal{F}$:
  - $\texttt{GetFcnCfg}:\texttt{FcnSigns}\to\mathbb{F}_{256}\times\mathbb{F}_{256}$
  - $\texttt{GetFcnCfg}(f):=(i,p)\ \text{where}\ (f,i,p)\in\mathcal{F}$

### Channel

A channel is defined by a user set and a function-signature subset:

- $\texttt{UserAddrs}\subseteq\mathbb{F}_{256}$
- $\texttt{AppFcnSigs}\subseteq\texttt{FcnSigns}$

The channel manages exactly six relations:

- $\widetilde{\mathcal{S}}:=\{(f,s)\mid f\in\texttt{AppFcnSigs}\ \wedge\ s\in\texttt{GetFcnStorages}(f)\}$
- $\widetilde{\mathcal{P}}:=\{(s,k)\mid s\in\widetilde{\texttt{Storages}}\ \wedge\ k\in\texttt{GetPreAllocKeys}(s)\}$
- $\widetilde{\mathcal{U}}:=\{(s,u)\mid s\in\widetilde{\texttt{Storages}}\ \wedge\ u\in\texttt{GetUserSlots}(s)\}$
- $\widetilde{\mathcal{F}}:=\{(f,i,p)\mid f\in\texttt{AppFcnSigs}\ \wedge\ \texttt{GetFcnCfg}(f)=(i,p)\}$
- $\mathcal{K}\subseteq \texttt{UserAddrs}\times\widetilde{\texttt{Storages}}\times\mathbb{F}_{256}$
- $\mathcal{V}\subseteq \widetilde{\texttt{Storages}}\times\mathbb{F}_{256}\times\mathbb{F}_{256}$

where:

- $\widetilde{\texttt{Storages}}:=\{s\in\mathbb{F}_{160}\mid \exists f\in\texttt{AppFcnSigs},\ (f,s)\in\widetilde{\mathcal{S}}\}$

By construction:

- $\widetilde{\mathcal{S}}\subseteq\mathcal{S}$
- $\widetilde{\mathcal{P}}\subseteq\mathcal{P}$
- $\widetilde{\mathcal{U}}\subseteq\mathcal{U}$
- $\widetilde{\mathcal{F}}\subseteq\mathcal{F}$

Channel key/value read relations:

- $\texttt{GetChannelStorageKey}(u,s):=k\ \text{where}\ (u,s,k)\in\mathcal{K}$
- $\texttt{GetValidatedStorageValue}(s,k):=v\ \text{where}\ (s,k,v)\in\mathcal{V}$

Consistency constraints:

- $\forall (u,s)\in\texttt{UserAddrs}\times\widetilde{\texttt{Storages}},\ \exists!k\in\mathbb{F}_{256},\ (u,s,k)\in\mathcal{K}$
- $\forall s\in\widetilde{\texttt{Storages}},\ \forall k\in\{k'\in\mathbb{F}_{256}\mid \exists u\in\texttt{UserAddrs},\ (u,s,k')\in\mathcal{K}\},\ \exists!v\in\mathbb{F}_{256},\ (s,k,v)\in\mathcal{V}$

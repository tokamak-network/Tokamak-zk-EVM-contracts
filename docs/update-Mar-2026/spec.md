# Tokamak Private App Channels - Bridge Contract

This document defines the minimal requirements needed to keep the bridge contract's storage structure secure. All mathematical constraints in this document can be converted into security guardrails, in the form of skills, so that any core update to the bridge contract can be safely performed by generative LLMs without security leakage.

Director: Jehyuk Jang, Ph.D

### Finite-Field notation

$\mathbb{F}_{b}$ is the field of $b$-bit words.

### Bridge manager

#### Scope

- $\mathrm{FcnSigns}\subseteq\mathbb{F}_{32}$
  - A set of contract function signatures
- $\mathrm{StorageAddrs}\subseteq\mathbb{F}_{160}$
  - A set of storage addresses
- $\mathrm{PreAllocKeys}\subseteq\mathbb{F}_{256}$
  - A set of pre-allocated keys
- $\mathrm{UserStorageSlots}\subseteq\mathbb{F}_{8}$
  - A set of user storage slots
- $\mathrm{FcnCfgs}\subseteq\mathbb{F}_{256}\times\mathbb{F}_{256}$
  - A set of function-configuration pairs of instance hashes and preprocess hashes

#### Relations

Given $\mathrm{FcnSigns}$ and MPT structural information involved with each of the contract functions, the bridge manager maintains and manages the following relations:

- $\mathcal{S}_M\subseteq\mathrm{FcnSigns}\times\mathrm{StorageAddrs}$
  - Existence: $\forall f\in\mathrm{FcnSigns},\ \exists s\in\mathrm{StorageAddrs},\ (f,s)\in\mathcal{S}_M$
  - Getter: $\mathrm{getFcnStorages}:\mathrm{FcnSigns}\to\mathcal{P}(\mathrm{StorageAddrs})$, where $\mathrm{getFcnStorages}(f):=\{s\in\mathrm{StorageAddrs}\mid(f,s)\in\mathcal{S}_M\}$
- $\mathcal{P}_M\subseteq\mathrm{StorageAddrs}\times\mathrm{PreAllocKeys}$
  - Getter: $\mathrm{getPreAllocKeys}:\mathrm{StorageAddrs}\to\mathcal{P}(\mathrm{PreAllocKeys})$, where $\mathrm{getPreAllocKeys}(s):=\{k\in\mathrm{PreAllocKeys}\mid(s,k)\in\mathcal{P}_M\}$
- $\mathcal{U}_M\subseteq\mathrm{StorageAddrs}\times\mathrm{UserStorageSlots}$
  - Getter: $\mathrm{getUserSlots}:\mathrm{StorageAddrs}\to\mathcal{P}(\mathrm{UserStorageSlots})$, where $\mathrm{getUserSlots}(s):=\{u\in\mathrm{UserStorageSlots}\mid(s,u)\in\mathcal{U}_M\}$
- $\mathcal{F}_M\subseteq\mathrm{FcnSigns}\times\mathrm{FcnCfgs}$
  - Existence and uniqueness: $\forall f\in\mathrm{FcnSigns},\ \exists!q\in\mathrm{FcnCfgs}\ \text{s.t.}\ (f,q)\in\mathcal{F}_M$
  - Getter: $\mathrm{getFcnCfg}:\mathrm{FcnSigns}\to\mathrm{FcnCfgs}$, where $\mathrm{getFcnCfg}(f):=q\ \text{where}\ (f,q)\in\mathcal{F}_M$

### Channel

#### Scope

- $\mathrm{UserAddrs}\subseteq\mathbb{F}_{256}$
  - A set of user addresses registered in a channel
- $\mathrm{AppFcnSigs}\subseteq\mathrm{FcnSigns}$
  - A set of contract function signatures supported by a channel
- $\mathrm{AppStorageAddrs}:=\mathrm{getFcnStorages}[\mathrm{AppFcnSigs}]$
  - A set of storage addresses referenced by the functions in $\mathrm{AppFcnSigs}$
  - Inclusion: $\mathrm{AppStorageAddrs}\subseteq\mathrm{StorageAddrs}$
- $\mathrm{AppPreAllocKeys}:=\mathrm{getPreAllocKeys}[\mathrm{AppStorageAddrs}]$
  - A set of pre-allocated keys associated with $\mathrm{AppStorageAddrs}$
  - Inclusion: $\mathrm{AppPreAllocKeys}\subseteq\mathrm{PreAllocKeys}$
- $\mathrm{AppUserStorageSlots}:=\mathrm{getUserSlots}[\mathrm{AppStorageAddrs}]$
  - A set of user storage slots associated with $\mathrm{AppStorageAddrs}$
  - Inclusion: $\mathrm{AppUserStorageSlots}\subseteq\mathrm{UserStorageSlots}$
- $\mathrm{AppFcnCfgs}:=\mathrm{getFcnCfg}[\mathrm{AppFcnSigs}]$
  - A set of function-configuration pairs of instance hash and preprocess hash referenced by the functions in $\mathrm{AppFcnSigs}$
  - Inclusion: $\mathrm{AppFcnCfgs}\subseteq\mathrm{FcnCfgs}$
- $\mathrm{AppUserStorageKeys}\subseteq\mathbb{F}_{256}$
  - A set of channel storage access keys used by users, distinct from Ethereum storage access keys
- $\mathrm{AppValidatedStorageValues}\subseteq\mathbb{F}_{256}$
  - A set of validated channel storage values associated with user accesses
- $\mathrm{AppPreAllocValues}\subseteq\mathbb{F}_{256}$
  - A set of fixed values assigned to pre-allocated keys in channel storage
- $\mathrm{stateIndex}\in\mathbb{N}$
  - The current state index of the channel state machine
- $\mathrm{StateIndices}:=\{t\in\mathbb{N}\mid t\le\mathrm{stateIndex}\}$
  - A set of valid state indices in the channel state machine
- $\mathrm{VerifiedStateRoots}\subseteq\mathbb{F}_{255}$
  - A set of verified state roots

#### Relations

Given $\mathrm{AppFcnSigs}$, a channel derives the following projected relations:

- $\mathcal{S}:=\bigcup_{f\in\mathrm{AppFcnSigs}}\left(\{f\}\times\mathrm{getFcnStorages}(f)\right)$
  - Inclusion: $\mathcal{S}\subseteq\mathcal{S}_M$
  - Getter: $\mathrm{getAppFcnStorages}:\mathrm{AppFcnSigs}\to\mathcal{P}(\mathrm{AppStorageAddrs})$, where $\mathrm{getAppFcnStorages}(f):=\{s\in\mathrm{AppStorageAddrs}\mid(f,s)\in\mathcal{S}\}$
- $\mathcal{D}:=\bigcup_{s\in\mathrm{AppStorageAddrs}}\left(\{s\}\times\mathrm{getPreAllocKeys}(s)\right)$
  - Inclusion: $\mathcal{D}\subseteq\mathcal{P}_M$
  - Getter: $\mathrm{getAppPreAllocKeys}:\mathrm{AppStorageAddrs}\to\mathcal{P}(\mathrm{AppPreAllocKeys})$, where $\mathrm{getAppPreAllocKeys}(s):=\{k\in\mathrm{AppPreAllocKeys}\mid(s,k)\in\mathcal{D}\}$
- $\mathcal{U}:=\bigcup_{s\in\mathrm{AppStorageAddrs}}\left(\{s\}\times\mathrm{getUserSlots}(s)\right)$
  - Inclusion: $\mathcal{U}\subseteq\mathcal{U}_M$
  - Getter: $\mathrm{getAppUserSlots}:\mathrm{AppStorageAddrs}\to\mathcal{P}(\mathrm{AppUserStorageSlots})$, where $\mathrm{getAppUserSlots}(s):=\{u\in\mathrm{AppUserStorageSlots}\mid(s,u)\in\mathcal{U}\}$
- $\mathcal{F}:=\bigcup_{f\in\mathrm{AppFcnSigs}}\left(\{f\}\times\{\mathrm{getFcnCfg}(f)\}\right)$
  - Inclusion: $\mathcal{F}\subseteq\mathcal{F}_M$
  - Getter: $\mathrm{getAppFcnCfg}:\mathrm{AppFcnSigs}\to\mathrm{AppFcnCfgs}$, where $\mathrm{getAppFcnCfg}(f):=q\ \text{where}\ (f,q)\in\mathcal{F}$

Given $\mathrm{UserAddrs}$ and their channel storage access keys, a channel maintains and manages the following relations:

- $\mathcal{K}\subseteq\mathrm{UserAddrs}\times\mathrm{AppStorageAddrs}\times\mathrm{AppUserStorageKeys}$
  - Uniqueness (without existence): $\forall u\in\mathrm{UserAddrs},\ \forall s\in\mathrm{AppStorageAddrs},\ \forall k_1,k_2\in\mathrm{AppUserStorageKeys},\ ((u,s,k_1)\in\mathcal{K}\wedge(u,s,k_2)\in\mathcal{K})\Rightarrow k_1=k_2$
  - Getter: $\mathrm{getAppUserStorageKey}:\mathrm{UserAddrs}\times\mathrm{AppStorageAddrs}\to\mathrm{AppUserStorageKeys}$, where $\mathrm{getAppUserStorageKey}(u,s):=k\ \text{where}\ (u,s,k)\in\mathcal{K}$
- $\mathcal{V}\subseteq\mathrm{AppStorageAddrs}\times\mathrm{AppUserStorageKeys}\times\mathrm{AppValidatedStorageValues}$
  - Conditional existence and uniqueness on channel keys: $\forall s\in\mathrm{AppStorageAddrs},\ \forall k\in\mathrm{AppUserStorageKeys},\ \left((\exists u\in\mathrm{UserAddrs},\ (u,s,k)\in\mathcal{K})\Rightarrow \exists!v\in\mathrm{AppValidatedStorageValues},\ (s,k,v)\in\mathcal{V}\right)$
  - Setter-gated value update: $\forall s\in\mathrm{AppStorageAddrs},\ \forall k\in\mathrm{AppUserStorageKeys},\ \forall \mathrm{updatedStorageValue}\in\mathbb{F}_{256},\ \left((s,k,\mathrm{updatedStorageValue})\in\mathcal{V}\Rightarrow \exists \mathrm{updatedRoot}\in\mathrm{VerifiedStateRoots},\ \mathrm{updateStorage}(s,k,\mathrm{updatedStorageValue},\mathrm{updatedRoot})=\mathrm{true}\right)$
  - Getter: $\mathrm{getAppValidatedStorageValue}:\{(s,k)\in\mathrm{AppStorageAddrs}\times\mathrm{AppUserStorageKeys}\mid \exists u\in\mathrm{UserAddrs},\ (u,s,k)\in\mathcal{K}\}\to\mathrm{AppValidatedStorageValues}$, where $\mathrm{getAppValidatedStorageValue}(s,k):=v\ \text{where}\ (s,k,v)\in\mathcal{V}$
- $\mathcal{A}\subseteq\mathrm{AppStorageAddrs}\times\mathrm{AppPreAllocKeys}\times\mathrm{AppPreAllocValues}$
  - Conditional existence and uniqueness on app pre-allocated keys: $\forall (s,k)\in\mathcal{D},\ \exists!v\in\mathrm{AppPreAllocValues},\ (s,k,v)\in\mathcal{A}$
  - Getter: $\mathrm{getAppPreAllocValue}:\mathcal{D}\to\mathrm{AppPreAllocValues}$, where $\mathrm{getAppPreAllocValue}(s,k):=v\ \text{where}\ (s,k,v)\in\mathcal{A}$

Given state-machine indexing and verified state roots, a channel maintains and manages the following relation:

- $\mathcal{R}\subseteq\mathrm{AppStorageAddrs}\times\mathrm{StateIndices}\times\mathrm{VerifiedStateRoots}$
  - Existence and uniqueness per storage-index pair: $\forall s\in\mathrm{AppStorageAddrs},\ \forall t\in\mathrm{StateIndices},\ \exists!r\in\mathrm{VerifiedStateRoots},\ (s,t,r)\in\mathcal{R}$
  - State transition by one-step index increment with root update: $\forall t\in\mathrm{StateIndices},\ \left(t<\mathrm{stateIndex}\Rightarrow \exists s\in\mathrm{AppStorageAddrs},\ \exists r_t,r_{t+1}\in\mathrm{VerifiedStateRoots},\ (s,t,r_t)\in\mathcal{R}\wedge(s,t+1,r_{t+1})\in\mathcal{R}\wedge r_t\neq r_{t+1}\right)$
  - Setter-gated root update: $\forall s\in\mathrm{AppStorageAddrs},\ \forall t\in\mathrm{StateIndices},\ \forall r_t,\mathrm{updatedRoot}\in\mathrm{VerifiedStateRoots},\ \left((t<\mathrm{stateIndex}\wedge(s,t,r_t)\in\mathcal{R}\wedge(s,t+1,\mathrm{updatedRoot})\in\mathcal{R}\wedge r_t\neq \mathrm{updatedRoot})\Rightarrow \exists k\in\mathrm{AppUserStorageKeys},\ \exists \mathrm{updatedStorageValue}\in\mathbb{F}_{256},\ \mathrm{updateStorage}(s,k,\mathrm{updatedStorageValue},\mathrm{updatedRoot})=\mathrm{true}\right)$
  - Getter: $\mathrm{getVerifiedStateRoot}:\mathrm{AppStorageAddrs}\times\mathrm{StateIndices}\to\mathrm{VerifiedStateRoots}$, where $\mathrm{getVerifiedStateRoot}(s,t):=r\ \text{where}\ (s,t,r)\in\mathcal{R}$

#### Setter functions

- $\mathrm{updateStorage}:\mathrm{AppStorageAddrs}\times\mathrm{AppUserStorageKeys}\times\mathbb{F}_{256}\times\mathbb{F}_{255}\to\{\mathrm{true},\mathrm{false}\}$
  - Inputs:
    - $\mathrm{appStorageAddr}\in\mathrm{AppStorageAddrs}$
    - $\mathrm{appUserStorageKey}\in\mathrm{AppUserStorageKeys}$
    - $\mathrm{updatedStorageValue}\in\mathbb{F}_{256}$
    - $\mathrm{updatedRoot}\in\mathbb{F}_{255}$
  - Output: $\mathrm{true}$ or $\mathrm{false}$


### Bridge Core

#### Scope

- $\mathrm{ChannelIds}\subseteq\mathbb{F}_{256}$
  - A set of registered channel IDs
- For each $c\in\mathrm{ChannelIds}$, let $X_c$ denote one channel instance satisfying the Channel section:

$$
\begin{aligned}
X_c:=(&\mathrm{UserAddrs}_c,\mathrm{AppFcnSigs}_c,\mathrm{AppStorageAddrs}_c,\mathrm{AppPreAllocKeys}_c,\mathrm{AppUserStorageSlots}_c,\\
     &\mathrm{AppFcnCfgs}_c,\mathrm{AppUserStorageKeys}_c,\mathrm{AppValidatedStorageValues}_c,\mathrm{AppPreAllocValues}_c,\\
     &\mathrm{stateIndex}_c,\mathrm{StateIndices}_c,\mathrm{VerifiedStateRoots}_c,\\
     &\mathcal{S}_c,\mathcal{D}_c,\mathcal{U}_c,\mathcal{F}_c,\mathcal{K}_c,\mathcal{V}_c,\mathcal{A}_c,\mathcal{R}_c)
\end{aligned}
$$

#### Relations

Given $\mathrm{ChannelIds}$ and channel instances $\{X_c\}_{c\in\mathrm{ChannelIds}}$, the core relations are lifted from channel relations:

- $\widetilde{\mathcal{M}}:=\bigcup_{c\in\mathrm{ChannelIds}}\left(\{c\}\times\mathrm{UserAddrs}_c\right)$
  - Getter: $\mathrm{getChannelUsers}:\mathrm{ChannelIds}\to\mathcal{P}(\mathrm{UserAddrs}_c)$, where $\mathrm{getChannelUsers}(c):=\{u\in\mathrm{UserAddrs}_c\mid(c,u)\in\widetilde{\mathcal{M}}\}$
- $\widetilde{\mathcal{S}}:=\bigcup_{c\in\mathrm{ChannelIds}}\left(\{c\}\times\mathcal{S}_c\right)$
  - Bridge-manager consistency: $\forall(c,f,s)\in\widetilde{\mathcal{S}},\ (f,s)\in\mathcal{S}_M$
  - Getter: $\mathrm{getChannelFcnStorages}:\{(c,f)\mid c\in\mathrm{ChannelIds}\ \wedge\ f\in\mathrm{AppFcnSigs}_c\}\to\mathcal{P}(\mathrm{AppStorageAddrs}_c)$, where $\mathrm{getChannelFcnStorages}(c,f):=\mathrm{getAppFcnStorages}_c(f)$
- $\widetilde{\mathcal{D}}:=\bigcup_{c\in\mathrm{ChannelIds}}\left(\{c\}\times\mathcal{D}_c\right)$
  - Bridge-manager consistency: $\forall(c,s,k)\in\widetilde{\mathcal{D}},\ (s,k)\in\mathcal{P}_M$
  - Getter: $\mathrm{getChannelPreAllocKeys}:\{(c,s)\mid c\in\mathrm{ChannelIds}\ \wedge\ s\in\mathrm{AppStorageAddrs}_c\}\to\mathcal{P}(\mathrm{AppPreAllocKeys}_c)$, where $\mathrm{getChannelPreAllocKeys}(c,s):=\mathrm{getAppPreAllocKeys}_c(s)$
- $\widetilde{\mathcal{U}}:=\bigcup_{c\in\mathrm{ChannelIds}}\left(\{c\}\times\mathcal{U}_c\right)$
  - Bridge-manager consistency: $\forall(c,s,u)\in\widetilde{\mathcal{U}},\ (s,u)\in\mathcal{U}_M$
  - Getter: $\mathrm{getChannelUserSlots}:\{(c,s)\mid c\in\mathrm{ChannelIds}\ \wedge\ s\in\mathrm{AppStorageAddrs}_c\}\to\mathcal{P}(\mathrm{AppUserStorageSlots}_c)$, where $\mathrm{getChannelUserSlots}(c,s):=\mathrm{getAppUserSlots}_c(s)$
- $\widetilde{\mathcal{F}}:=\bigcup_{c\in\mathrm{ChannelIds}}\left(\{c\}\times\mathcal{F}_c\right)$
  - Bridge-manager consistency: $\forall(c,f,q)\in\widetilde{\mathcal{F}},\ (f,q)\in\mathcal{F}_M$
  - Existence and uniqueness per channel-function pair: $\forall c\in\mathrm{ChannelIds},\ \forall f\in\mathrm{AppFcnSigs}_c,\ \exists!q\in\mathrm{AppFcnCfgs}_c,\ (c,f,q)\in\widetilde{\mathcal{F}}$
  - Getter: $\mathrm{getChannelFcnCfg}:\{(c,f)\mid c\in\mathrm{ChannelIds}\ \wedge\ f\in\mathrm{AppFcnSigs}_c\}\to\mathrm{AppFcnCfgs}_c$, where $\mathrm{getChannelFcnCfg}(c,f):=\mathrm{getAppFcnCfg}_c(f)$
- $\widetilde{\mathcal{K}}:=\bigcup_{c\in\mathrm{ChannelIds}}\left(\{c\}\times\mathcal{K}_c\right)$
  - Uniqueness (without existence): $\forall c\in\mathrm{ChannelIds},\ \forall u\in\mathrm{UserAddrs}_c,\ \forall s\in\mathrm{AppStorageAddrs}_c,\ \forall k_1,k_2\in\mathrm{AppUserStorageKeys}_c,\ ((c,u,s,k_1)\in\widetilde{\mathcal{K}}\wedge(c,u,s,k_2)\in\widetilde{\mathcal{K}})\Rightarrow k_1=k_2$
  - Getter: $\mathrm{getChannelUserStorageKey}:\{(c,u,s)\mid c\in\mathrm{ChannelIds}\ \wedge\ (c,u)\in\widetilde{\mathcal{M}}\ \wedge\ s\in\mathrm{AppStorageAddrs}_c\}\to\mathrm{AppUserStorageKeys}_c$, where $\mathrm{getChannelUserStorageKey}(c,u,s):=\mathrm{getAppUserStorageKey}_c(u,s)$
- $\widetilde{\mathcal{V}}:=\bigcup_{c\in\mathrm{ChannelIds}}\left(\{c\}\times\mathcal{V}_c\right)$
  - Conditional existence and uniqueness on channel keys: $\forall c\in\mathrm{ChannelIds},\ \forall s\in\mathrm{AppStorageAddrs}_c,\ \forall k\in\mathrm{AppUserStorageKeys}_c,\ \left((\exists u\in\mathrm{UserAddrs}_c,\ (c,u,s,k)\in\widetilde{\mathcal{K}})\Rightarrow \exists!v\in\mathrm{AppValidatedStorageValues}_c,\ (c,s,k,v)\in\widetilde{\mathcal{V}}\right)$
  - Getter: $\mathrm{getChannelValidatedStorageValue}:\{(c,s,k)\mid c\in\mathrm{ChannelIds}\ \wedge\ s\in\mathrm{AppStorageAddrs}_c\ \wedge\ k\in\mathrm{AppUserStorageKeys}_c\ \wedge\ \exists u\in\mathrm{UserAddrs}_c,\ (c,u,s,k)\in\widetilde{\mathcal{K}}\}\to\mathrm{AppValidatedStorageValues}_c$, where $\mathrm{getChannelValidatedStorageValue}(c,s,k):=\mathrm{getAppValidatedStorageValue}_c(s,k)$
- $\widetilde{\mathcal{A}}:=\bigcup_{c\in\mathrm{ChannelIds}}\left(\{c\}\times\mathcal{A}_c\right)$
  - Conditional existence and uniqueness on channel pre-allocated keys: $\forall c\in\mathrm{ChannelIds},\ \forall (s,k)\in\mathcal{D}_c,\ \exists!v\in\mathrm{AppPreAllocValues}_c,\ (c,s,k,v)\in\widetilde{\mathcal{A}}$
  - Getter: $\mathrm{getChannelPreAllocValue}:\{(c,s,k)\mid c\in\mathrm{ChannelIds}\ \wedge\ (s,k)\in\mathcal{D}_c\}\to\mathrm{AppPreAllocValues}_c$, where $\mathrm{getChannelPreAllocValue}(c,s,k):=\mathrm{getAppPreAllocValue}_c(s,k)$
- $\widetilde{\mathcal{R}}:=\bigcup_{c\in\mathrm{ChannelIds}}\left(\{c\}\times\mathcal{R}_c\right)$
  - Getter: $\mathrm{getChannelVerifiedStateRoot}:\{(c,s,t)\mid c\in\mathrm{ChannelIds}\ \wedge\ s\in\mathrm{AppStorageAddrs}_c\ \wedge\ t\in\mathrm{StateIndices}_c\}\to\mathrm{VerifiedStateRoots}_c$, where $\mathrm{getChannelVerifiedStateRoot}(c,s,t):=\mathrm{getVerifiedStateRoot}_c(s,t)$

Core access constraints:

- Every channel-scoped getter is indexed by channel ID $c\in\mathrm{ChannelIds}$.
- Every user-scoped getter requires a membership witness $(c,u)\in\widetilde{\mathcal{M}}$ in its domain.

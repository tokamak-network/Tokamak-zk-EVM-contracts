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
  - Getter: $\mathrm{GetFcnStorages}:\mathrm{FcnSigns}\to\mathcal{P}(\mathrm{StorageAddrs})$, where $\mathrm{GetFcnStorages}(f):=\{s\in\mathrm{StorageAddrs}\mid(f,s)\in\mathcal{S}_M\}$
- $\mathcal{P}_M\subseteq\mathrm{StorageAddrs}\times\mathrm{PreAllocKeys}$
  - Getter: $\mathrm{GetPreAllocKeys}:\mathrm{StorageAddrs}\to\mathcal{P}(\mathrm{PreAllocKeys})$, where $\mathrm{GetPreAllocKeys}(s):=\{k\in\mathrm{PreAllocKeys}\mid(s,k)\in\mathcal{P}_M\}$
- $\mathcal{U}_M\subseteq\mathrm{StorageAddrs}\times\mathrm{UserStorageSlots}$
  - Getter: $\mathrm{GetUserSlots}:\mathrm{StorageAddrs}\to\mathcal{P}(\mathrm{UserStorageSlots})$, where $\mathrm{GetUserSlots}(s):=\{u\in\mathrm{UserStorageSlots}\mid(s,u)\in\mathcal{U}_M\}$
- $\mathcal{F}_M\subseteq\mathrm{FcnSigns}\times\mathrm{FcnCfgs}$
  - Existence and uniqueness: $\forall f\in\mathrm{FcnSigns},\ \exists!q\in\mathrm{FcnCfgs}\ \text{s.t.}\ (f,q)\in\mathcal{F}_M$
  - Getter: $\mathrm{GetFcnCfg}:\mathrm{FcnSigns}\to\mathrm{FcnCfgs}$, where $\mathrm{GetFcnCfg}(f):=q\ \text{where}\ (f,q)\in\mathcal{F}_M$

### Channel

#### Scope

- $\mathrm{UserAddrs}\subseteq\mathbb{F}_{256}$
  - A set of user addresses registered in a channel
- $\mathrm{AppFcnSigs}\subseteq\mathrm{FcnSigns}$
  - A set of contract function signatures supported by a channel
- $\mathrm{AppStorageAddrs}:=\mathrm{GetFcnStorages}[\mathrm{AppFcnSigs}]$
  - A set of storage addresses referenced by the functions in $\mathrm{AppFcnSigs}$
  - Inclusion: $\mathrm{AppStorageAddrs}\subseteq\mathrm{StorageAddrs}$
- $\mathrm{AppPreAllocKeys}:=\mathrm{GetPreAllocKeys}[\mathrm{AppStorageAddrs}]$
  - A set of pre-allocated keys associated with $\mathrm{AppStorageAddrs}$
  - Inclusion: $\mathrm{AppPreAllocKeys}\subseteq\mathrm{PreAllocKeys}$
- $\mathrm{AppUserStorageSlots}:=\mathrm{GetUserSlots}[\mathrm{AppStorageAddrs}]$
  - A set of user storage slots associated with $\mathrm{AppStorageAddrs}$
  - Inclusion: $\mathrm{AppUserStorageSlots}\subseteq\mathrm{UserStorageSlots}$
- $\mathrm{AppFcnCfgs}:=\mathrm{GetFcnCfg}[\mathrm{AppFcnSigs}]$
  - A set of function-configuration pairs of instance hash and preprocess hash referenced by the functions in $\mathrm{AppFcnSigs}$
  - Inclusion: $\mathrm{AppFcnCfgs}\subseteq\mathrm{FcnCfgs}$
- $\mathrm{AppUserStorageKey}\subseteq\mathbb{F}_{256}$
  - A set of channel storage access keys used by users, distinct from Ethereum storage access keys
- $\mathrm{AppValidatedStorageValues}\subseteq\mathbb{F}_{256}$
  - A set of validated channel storage values associated with user accesses
- $\mathrm{AppPreAllocValues}\subseteq\mathbb{F}_{256}$
  - A set of fixed values assigned to pre-allocated keys in channel storage

#### Relations

Given $\mathrm{AppFcnSigs}$, a channel derives the following projected relations:

- $\mathcal{S}:=\bigcup_{f\in\mathrm{AppFcnSigs}}\left(\{f\}\times\mathrm{GetFcnStorages}(f)\right)$
  - Inclusion: $\mathcal{S}\subseteq\mathcal{S}_M$
  - Getter: $\mathrm{GetAppFcnStorages}:\mathrm{AppFcnSigs}\to\mathcal{P}(\mathrm{AppStorageAddrs})$, where $\mathrm{GetAppFcnStorages}(f):=\{s\in\mathrm{AppStorageAddrs}\mid(f,s)\in\mathcal{S}\}$
- $\mathcal{P}:=\bigcup_{s\in\mathrm{AppStorageAddrs}}\left(\{s\}\times\mathrm{GetPreAllocKeys}(s)\right)$
  - Inclusion: $\mathcal{P}\subseteq\mathcal{P}_M$
  - Getter: $\mathrm{GetAppPreAllocKeys}:\mathrm{AppStorageAddrs}\to\mathcal{P}(\mathrm{AppPreAllocKeys})$, where $\mathrm{GetAppPreAllocKeys}(s):=\{k\in\mathrm{AppPreAllocKeys}\mid(s,k)\in\mathcal{P}\}$
- $\mathcal{U}:=\bigcup_{s\in\mathrm{AppStorageAddrs}}\left(\{s\}\times\mathrm{GetUserSlots}(s)\right)$
  - Inclusion: $\mathcal{U}\subseteq\mathcal{U}_M$
  - Getter: $\mathrm{GetAppUserSlots}:\mathrm{AppStorageAddrs}\to\mathcal{P}(\mathrm{AppUserStorageSlots})$, where $\mathrm{GetAppUserSlots}(s):=\{u\in\mathrm{AppUserStorageSlots}\mid(s,u)\in\mathcal{U}\}$
- $\mathcal{F}:=\bigcup_{f\in\mathrm{AppFcnSigs}}\left(\{f\}\times\{\mathrm{GetFcnCfg}(f)\}\right)$
  - Inclusion: $\mathcal{F}\subseteq\mathcal{F}_M$
  - Getter: $\mathrm{GetAppFcnCfg}:\mathrm{AppFcnSigs}\to\mathrm{AppFcnCfgs}$, where $\mathrm{GetAppFcnCfg}(f):=q\ \text{where}\ (f,q)\in\mathcal{F}$

Given $\mathrm{UserAddrs}$ and their channel storage access keys, a channel maintains and manages the following relations:

- $\mathcal{K}\subseteq\mathrm{UserAddrs}\times\mathrm{AppStorageAddrs}\times\mathrm{AppUserStorageKey}$
  - Uniqueness (without existence): $\forall u\in\mathrm{UserAddrs},\ \forall s\in\mathrm{AppStorageAddrs},\ \forall k_1,k_2\in\mathrm{AppUserStorageKey},\ ((u,s,k_1)\in\mathcal{K}\wedge(u,s,k_2)\in\mathcal{K})\Rightarrow k_1=k_2$
  - Getter: $\mathrm{GetAppUserStorageKey}:\mathrm{UserAddrs}\times\mathrm{AppStorageAddrs}\to\mathrm{AppUserStorageKey}$, where $\mathrm{GetAppUserStorageKey}(u,s):=k\ \text{where}\ (u,s,k)\in\mathcal{K}$
- $\mathcal{V}\subseteq\mathrm{AppStorageAddrs}\times\mathrm{AppUserStorageKey}\times\mathrm{AppValidatedStorageValues}$
  - Conditional existence and uniqueness on channel keys: $\forall s\in\mathrm{AppStorageAddrs},\ \forall k\in\mathrm{AppUserStorageKey},\ \left((\exists u\in\mathrm{UserAddrs},\ (u,s,k)\in\mathcal{K})\Rightarrow \exists!v\in\mathrm{AppValidatedStorageValues},\ (s,k,v)\in\mathcal{V}\right)$
  - Getter: $\mathrm{GetAppValidatedStorageValue}:\{(s,k)\in\mathrm{AppStorageAddrs}\times\mathrm{AppUserStorageKey}\mid \exists u\in\mathrm{UserAddrs},\ (u,s,k)\in\mathcal{K}\}\to\mathrm{AppValidatedStorageValues}$, where $\mathrm{GetAppValidatedStorageValue}(s,k):=v\ \text{where}\ (s,k,v)\in\mathcal{V}$
- $\mathcal{A}\subseteq\mathrm{AppStorageAddrs}\times\mathrm{AppPreAllocKeys}\times\mathrm{AppPreAllocValues}$
  - Conditional existence and uniqueness on app pre-allocated keys: $\forall (s,k)\in\mathcal{P},\ \exists!v\in\mathrm{AppPreAllocValues},\ (s,k,v)\in\mathcal{A}$
  - Getter: $\mathrm{GetAppPreAllocValue}:\mathcal{P}\to\mathrm{AppPreAllocValues}$, where $\mathrm{GetAppPreAllocValue}(s,k):=v\ \text{where}\ (s,k,v)\in\mathcal{A}$


### Bridge Core

#### Scope

- $\mathrm{ChannelIds}\subseteq\mathbb{F}_{256}$
  - A set of registered channel IDs
- For each $c\in\mathrm{ChannelIds}$, let $X_c$ denote one channel instance satisfying the Channel section:

$$
\begin{aligned}
X_c:=(&\mathrm{UserAddrs}_c,\mathrm{AppFcnSigs}_c,\mathrm{AppStorageAddrs}_c,\mathrm{AppPreAllocKeys}_c,\mathrm{AppUserStorageSlots}_c,\\
     &\mathrm{AppFcnCfgs}_c,\mathrm{AppUserStorageKey}_c,\mathrm{AppValidatedStorageValues}_c,\mathrm{AppPreAllocValues}_c,\\
     &\mathcal{S}_c,\mathcal{P}_c,\mathcal{U}_c,\mathcal{F}_c,\mathcal{K}_c,\mathcal{V}_c,\mathcal{A}_c)
\end{aligned}
$$

#### Relations

Given $\mathrm{ChannelIds}$ and channel instances $\{X_c\}_{c\in\mathrm{ChannelIds}}$, the core relations are lifted from channel relations:

- $\widetilde{\mathcal{M}}:=\bigcup_{c\in\mathrm{ChannelIds}}\left(\{c\}\times\mathrm{UserAddrs}_c\right)$
  - Getter: $\mathrm{GetChannelUsers}:\mathrm{ChannelIds}\to\mathcal{P}(\mathrm{UserAddrs}_c)$, where $\mathrm{GetChannelUsers}(c):=\{u\in\mathrm{UserAddrs}_c\mid(c,u)\in\widetilde{\mathcal{M}}\}$
- $\widetilde{\mathcal{S}}:=\bigcup_{c\in\mathrm{ChannelIds}}\left(\{c\}\times\mathcal{S}_c\right)$
  - Bridge-manager consistency: $\forall(c,f,s)\in\widetilde{\mathcal{S}},\ (f,s)\in\mathcal{S}_M$
  - Getter: $\mathrm{GetChannelFcnStorages}:\{(c,f)\mid c\in\mathrm{ChannelIds}\ \wedge\ f\in\mathrm{AppFcnSigs}_c\}\to\mathcal{P}(\mathrm{AppStorageAddrs}_c)$, where $\mathrm{GetChannelFcnStorages}(c,f):=\mathrm{GetAppFcnStorages}_c(f)$
- $\widetilde{\mathcal{P}}:=\bigcup_{c\in\mathrm{ChannelIds}}\left(\{c\}\times\mathcal{P}_c\right)$
  - Bridge-manager consistency: $\forall(c,s,k)\in\widetilde{\mathcal{P}},\ (s,k)\in\mathcal{P}_M$
  - Getter: $\mathrm{GetChannelPreAllocKeys}:\{(c,s)\mid c\in\mathrm{ChannelIds}\ \wedge\ s\in\mathrm{AppStorageAddrs}_c\}\to\mathcal{P}(\mathrm{AppPreAllocKeys}_c)$, where $\mathrm{GetChannelPreAllocKeys}(c,s):=\mathrm{GetAppPreAllocKeys}_c(s)$
- $\widetilde{\mathcal{U}}:=\bigcup_{c\in\mathrm{ChannelIds}}\left(\{c\}\times\mathcal{U}_c\right)$
  - Bridge-manager consistency: $\forall(c,s,u)\in\widetilde{\mathcal{U}},\ (s,u)\in\mathcal{U}_M$
  - Getter: $\mathrm{GetChannelUserSlots}:\{(c,s)\mid c\in\mathrm{ChannelIds}\ \wedge\ s\in\mathrm{AppStorageAddrs}_c\}\to\mathcal{P}(\mathrm{AppUserStorageSlots}_c)$, where $\mathrm{GetChannelUserSlots}(c,s):=\mathrm{GetAppUserSlots}_c(s)$
- $\widetilde{\mathcal{F}}:=\bigcup_{c\in\mathrm{ChannelIds}}\left(\{c\}\times\mathcal{F}_c\right)$
  - Bridge-manager consistency: $\forall(c,f,q)\in\widetilde{\mathcal{F}},\ (f,q)\in\mathcal{F}_M$
  - Existence and uniqueness per channel-function pair: $\forall c\in\mathrm{ChannelIds},\ \forall f\in\mathrm{AppFcnSigs}_c,\ \exists!q\in\mathrm{AppFcnCfgs}_c,\ (c,f,q)\in\widetilde{\mathcal{F}}$
  - Getter: $\mathrm{GetChannelFcnCfg}:\{(c,f)\mid c\in\mathrm{ChannelIds}\ \wedge\ f\in\mathrm{AppFcnSigs}_c\}\to\mathrm{AppFcnCfgs}_c$, where $\mathrm{GetChannelFcnCfg}(c,f):=\mathrm{GetAppFcnCfg}_c(f)$
- $\widetilde{\mathcal{K}}:=\bigcup_{c\in\mathrm{ChannelIds}}\left(\{c\}\times\mathcal{K}_c\right)$
  - Uniqueness (without existence): $\forall c\in\mathrm{ChannelIds},\ \forall u\in\mathrm{UserAddrs}_c,\ \forall s\in\mathrm{AppStorageAddrs}_c,\ \forall k_1,k_2\in\mathrm{AppUserStorageKey}_c,\ ((c,u,s,k_1)\in\widetilde{\mathcal{K}}\wedge(c,u,s,k_2)\in\widetilde{\mathcal{K}})\Rightarrow k_1=k_2$
  - Getter: $\mathrm{GetChannelUserStorageKey}:\{(c,u,s)\mid c\in\mathrm{ChannelIds}\ \wedge\ (c,u)\in\widetilde{\mathcal{M}}\ \wedge\ s\in\mathrm{AppStorageAddrs}_c\}\to\mathrm{AppUserStorageKey}_c$, where $\mathrm{GetChannelUserStorageKey}(c,u,s):=\mathrm{GetAppUserStorageKey}_c(u,s)$
- $\widetilde{\mathcal{V}}:=\bigcup_{c\in\mathrm{ChannelIds}}\left(\{c\}\times\mathcal{V}_c\right)$
  - Conditional existence and uniqueness on channel keys: $\forall c\in\mathrm{ChannelIds},\ \forall s\in\mathrm{AppStorageAddrs}_c,\ \forall k\in\mathrm{AppUserStorageKey}_c,\ \left((\exists u\in\mathrm{UserAddrs}_c,\ (c,u,s,k)\in\widetilde{\mathcal{K}})\Rightarrow \exists!v\in\mathrm{AppValidatedStorageValues}_c,\ (c,s,k,v)\in\widetilde{\mathcal{V}}\right)$
  - Getter: $\mathrm{GetChannelValidatedStorageValue}:\{(c,s,k)\mid c\in\mathrm{ChannelIds}\ \wedge\ s\in\mathrm{AppStorageAddrs}_c\ \wedge\ k\in\mathrm{AppUserStorageKey}_c\ \wedge\ \exists u\in\mathrm{UserAddrs}_c,\ (c,u,s,k)\in\widetilde{\mathcal{K}}\}\to\mathrm{AppValidatedStorageValues}_c$, where $\mathrm{GetChannelValidatedStorageValue}(c,s,k):=\mathrm{GetAppValidatedStorageValue}_c(s,k)$
- $\widetilde{\mathcal{A}}:=\bigcup_{c\in\mathrm{ChannelIds}}\left(\{c\}\times\mathcal{A}_c\right)$
  - Conditional existence and uniqueness on channel pre-allocated keys: $\forall c\in\mathrm{ChannelIds},\ \forall (s,k)\in\mathcal{P}_c,\ \exists!v\in\mathrm{AppPreAllocValues}_c,\ (c,s,k,v)\in\widetilde{\mathcal{A}}$
  - Getter: $\mathrm{GetChannelPreAllocValue}:\{(c,s,k)\mid c\in\mathrm{ChannelIds}\ \wedge\ (s,k)\in\mathcal{P}_c\}\to\mathrm{AppPreAllocValues}_c$, where $\mathrm{GetChannelPreAllocValue}(c,s,k):=\mathrm{GetAppPreAllocValue}_c(s,k)$

Core access constraints:

- Every channel-scoped getter is indexed by channel ID $c\in\mathrm{ChannelIds}$.
- Every user-scoped getter requires a membership witness $(c,u)\in\widetilde{\mathcal{M}}$ in its domain.

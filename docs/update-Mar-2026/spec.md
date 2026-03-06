# Tokamak Private App Channels - Bridge Contract

### General

The bridge contract records and manages channel data.

$\mathbb{F}_{b}$ is the field of $b$-bit words.

### Bridge manager

#### Scope

- $\texttt{FcnSigns}\subseteq\mathbb{F}_{32}$
  - A set of contract function signatures
- $\texttt{StorageAddrs}\subseteq\mathbb{F}_{160}$
  - A set of storage addresses
- $\texttt{PreAllocKeys}\subseteq\mathbb{F}_{256}$
  - A set of pre-allocated keys
- $\texttt{UserStorageSlots}\subseteq\mathbb{F}_{8}$
  - A set of user storage slots
- $\texttt{InstanceHashes}\subseteq\mathbb{F}_{256}$
  - A set of instance hashes
- $\texttt{PreprocessHashes}\subseteq\mathbb{F}_{256}$
  - A set of preprocess hashes

#### Relations

Given $\texttt{FcnSigns}$ and MPT structural information involved with each of the contract functions, the bridge manager maintains and manages the following relations:

- $\mathcal{S}_M\subseteq\texttt{FcnSigns}\times\texttt{StorageAddrs}$
  - Existence: $\forall f\in\texttt{FcnSigns},\ \exists s\in\texttt{StorageAddrs},\ (f,s)\in\mathcal{S}_M$
  - Getter: $\texttt{GetFcnStorages}:\texttt{FcnSigns}\to\mathcal{P}(\texttt{StorageAddrs})$, where $\texttt{GetFcnStorages}(f):=\{s\in\texttt{StorageAddrs}\mid(f,s)\in\mathcal{S}_M\}$
- $\mathcal{P}_M\subseteq\texttt{StorageAddrs}\times\texttt{PreAllocKeys}$
  - Getter: $\texttt{GetPreAllocKeys}:\texttt{StorageAddrs}\to\mathcal{P}(\texttt{PreAllocKeys})$, where $\texttt{GetPreAllocKeys}(s):=\{k\in\texttt{PreAllocKeys}\mid(s,k)\in\mathcal{P}_M\}$
- $\mathcal{U}_M\subseteq\texttt{StorageAddrs}\times\texttt{UserStorageSlots}$
  - Getter: $\texttt{GetUserSlots}:\texttt{StorageAddrs}\to\mathcal{P}(\texttt{UserStorageSlots})$, where $\texttt{GetUserSlots}(s):=\{u\in\texttt{UserStorageSlots}\mid(s,u)\in\mathcal{U}_M\}$
- $\mathcal{F}_M\subseteq\texttt{FcnSigns}\times\texttt{InstanceHashes}\times\texttt{PreprocessHashes}$
  - Existence and uniqueness: $\forall f\in\texttt{FcnSigns},\ \exists!(i,p)\in\texttt{InstanceHashes}\times\texttt{PreprocessHashes}\ \text{s.t.}\ (f,i,p)\in\mathcal{F}_M$
  - Getter: $\texttt{GetFcnCfg}:\texttt{FcnSigns}\to\texttt{InstanceHashes}\times\texttt{PreprocessHashes}$, where $\texttt{GetFcnCfg}(f):=(i,p)\ \text{where}\ (f,i,p)\in\mathcal{F}_M$

### Channel

#### Scope

- $\texttt{UserAddrs}\subseteq\mathbb{F}_{256}$
  - A set of user addresses
- $\texttt{AppFcnSigs}\subseteq\texttt{FcnSigns}$
  - A set of contract function signatures that is supported by a channel
- $\texttt{AppStorageAddrs}:=\bigcup_{f\in\texttt{AppFcnSigs}}\texttt{GetFcnStorages}(f)$
  - A set of storage addresses that the contract functions in $\texttt{AppFcnSigs}$ handle
  - Inclusion: $\texttt{AppStorageAddrs}\subseteq\texttt{StorageAddrs}$
- $\texttt{AppPreAllocKeys}:=\bigcup_{s\in\texttt{AppStorageAddrs}}\texttt{GetPreAllocKeys}(s)$
  - Inclusion: $\texttt{AppPreAllocKeys}\subseteq\texttt{PreAllocKeys}$
- $\texttt{AppUserStorageSlots}:=\bigcup_{s\in\texttt{AppStorageAddrs}}\texttt{GetUserSlots}(s)$
  - Inclusion: $\texttt{AppUserStorageSlots}\subseteq\texttt{UserStorageSlots}$
- $\texttt{AppInstanceHashes}:=\{i\in\texttt{InstanceHashes}\mid \exists f\in\texttt{AppFcnSigs},\ \exists p\in\texttt{PreprocessHashes},\ \texttt{GetFcnCfg}(f)=(i,p)\}$
  - Inclusion: $\texttt{AppInstanceHashes}\subseteq\texttt{InstanceHashes}$
- $\texttt{AppPreprocessHashes}:=\{p\in\texttt{PreprocessHashes}\mid \exists f\in\texttt{AppFcnSigs},\ \exists i\in\texttt{InstanceHashes},\ \texttt{GetFcnCfg}(f)=(i,p)\}$
  - Inclusion: $\texttt{AppPreprocessHashes}\subseteq\texttt{PreprocessHashes}$

#### Relations

Given $\texttt{AppFcnSigs}$, a channel derives the following projected relations:

- $\mathcal{S}:=\{(f,s)\mid f\in\texttt{AppFcnSigs}\ \wedge\ s\in\texttt{GetFcnStorages}(f)\}$
  - Inclusion: $\mathcal{S}\subseteq\mathcal{S}_M$
  - Getter: $\texttt{GetAppFcnStorages}:\texttt{AppFcnSigs}\to\mathcal{P}(\texttt{AppStorageAddrs})$, where $\texttt{GetAppFcnStorages}(f):=\{s\in\texttt{AppStorageAddrs}\mid(f,s)\in\mathcal{S}\}$
- $\mathcal{P}:=\{(s,k)\mid s\in\texttt{AppStorageAddrs}\ \wedge\ k\in\texttt{AppPreAllocKeys}\ \wedge\ k\in\texttt{GetPreAllocKeys}(s)\}$
  - Inclusion: $\mathcal{P}\subseteq\mathcal{P}_M$
  - Getter: $\texttt{GetAppPreAllocKeys}:\texttt{AppStorageAddrs}\to\mathcal{P}(\texttt{AppPreAllocKeys})$, where $\texttt{GetAppPreAllocKeys}(s):=\{k\in\texttt{AppPreAllocKeys}\mid(s,k)\in\mathcal{P}\}$
- $\mathcal{U}:=\{(s,u)\mid s\in\texttt{AppStorageAddrs}\ \wedge\ u\in\texttt{AppUserStorageSlots}\ \wedge\ u\in\texttt{GetUserSlots}(s)\}$
  - Inclusion: $\mathcal{U}\subseteq\mathcal{U}_M$
  - Getter: $\texttt{GetAppUserSlots}:\texttt{AppStorageAddrs}\to\mathcal{P}(\texttt{AppUserStorageSlots})$, where $\texttt{GetAppUserSlots}(s):=\{u\in\texttt{AppUserStorageSlots}\mid(s,u)\in\mathcal{U}\}$
- $\mathcal{F}:=\{(f,i,p)\mid f\in\texttt{AppFcnSigs}\ \wedge\ i\in\texttt{AppInstanceHashes}\ \wedge\ p\in\texttt{AppPreprocessHashes}\ \wedge\ \texttt{GetFcnCfg}(f)=(i,p)\}$
  - Inclusion: $\mathcal{F}\subseteq\mathcal{F}_M$
  - Getter: $\texttt{GetAppFcnCfg}:\texttt{AppFcnSigs}\to\texttt{AppInstanceHashes}\times\texttt{AppPreprocessHashes}$, where $\texttt{GetAppFcnCfg}(f):=(i,p)\ \text{where}\ (f,i,p)\in\mathcal{F}$

Given $\texttt{UserAddrs}$ and their channel storage access keys, a channel maintains and manages the following relations:

- $\mathcal{K}\subseteq\texttt{UserAddrs}\times\texttt{AppStorageAddrs}\times\mathbb{F}_{256}$
  - Uniqueness (without existence): $\forall u\in\texttt{UserAddrs},\ \forall s\in\texttt{AppStorageAddrs},\ \forall k_1,k_2\in\mathbb{F}_{256},\ ((u,s,k_1)\in\mathcal{K}\wedge(u,s,k_2)\in\mathcal{K})\Rightarrow k_1=k_2$
  - Getter: $\texttt{GetAppUserStorageKey}:\texttt{UserAddrs}\times\texttt{AppStorageAddrs}\to\mathbb{F}_{256}$, where $\texttt{GetAppUserStorageKey}(u,s):=k\ \text{where}\ (u,s,k)\in\mathcal{K}$
- $\mathcal{V}\subseteq\texttt{AppStorageAddrs}\times\mathbb{F}_{256}\times\mathbb{F}_{256}$
  - Conditional existence and uniqueness on channel keys: $\forall s\in\texttt{AppStorageAddrs},\ \forall k\in\mathbb{F}_{256},\ \left((\exists u\in\texttt{UserAddrs},\ (u,s,k)\in\mathcal{K})\Rightarrow \exists!v\in\mathbb{F}_{256},\ (s,k,v)\in\mathcal{V}\right)$
  - Getter: $\texttt{GetAppValidatedStorageValue}:\{(s,k)\in\texttt{AppStorageAddrs}\times\mathbb{F}_{256}\mid \exists u\in\texttt{UserAddrs},\ (u,s,k)\in\mathcal{K}\}\to\mathbb{F}_{256}$, where $\texttt{GetAppValidatedStorageValue}(s,k):=v\ \text{where}\ (s,k,v)\in\mathcal{V}$
- $\mathcal{A}\subseteq\texttt{AppStorageAddrs}\times\texttt{AppPreAllocKeys}\times\mathbb{F}_{256}$
  - Conditional existence and uniqueness on app pre-allocated keys: $\forall (s,k)\in\mathcal{P},\ \exists!v\in\mathbb{F}_{256},\ (s,k,v)\in\mathcal{A}$
  - Getter: $\texttt{GetAppPreAllocValue}:\mathcal{P}\to\mathbb{F}_{256}$, where $\texttt{GetAppPreAllocValue}(s,k):=v\ \text{where}\ (s,k,v)\in\mathcal{A}$


### Bridge Core

#### Scope

- $\texttt{ChannelIds}\subseteq\mathbb{F}_{256}$
  - A set of registered channel IDs
- For each $c\in\texttt{ChannelIds}$, let $X_c$ denote one channel instance satisfying the Channel section:
  - $X_c=(\texttt{UserAddrs}_c,\texttt{AppFcnSigs}_c,\texttt{AppStorageAddrs}_c,\mathcal{S}_c,\mathcal{P}_c,\mathcal{U}_c,\mathcal{F}_c,\mathcal{K}_c,\mathcal{V}_c,\mathcal{A}_c)$

#### Relations

Given $\texttt{ChannelIds}$ and channel instances $\{X_c\}_{c\in\texttt{ChannelIds}}$, the core relations are lifted from channel relations:

- $\widetilde{\mathcal{M}}:=\{(c,u)\mid c\in\texttt{ChannelIds}\ \wedge\ u\in\texttt{UserAddrs}_c\}$
  - Getter: $\texttt{GetChannelUsers}:\texttt{ChannelIds}\to\mathcal{P}(\mathbb{F}_{256})$, where $\texttt{GetChannelUsers}(c):=\{u\in\mathbb{F}_{256}\mid(c,u)\in\widetilde{\mathcal{M}}\}$
- $\widetilde{\mathcal{S}}:=\{(c,f,s)\mid c\in\texttt{ChannelIds}\ \wedge\ (f,s)\in\mathcal{S}_c\}$
  - Bridge-manager consistency: $\forall(c,f,s)\in\widetilde{\mathcal{S}},\ (f,s)\in\mathcal{S}_M$
  - Getter: $\texttt{GetChannelFcnStorages}:\texttt{ChannelIds}\times\mathbb{F}_{32}\to\mathcal{P}(\mathbb{F}_{160})$, where $\texttt{GetChannelFcnStorages}(c,f):=\{s\in\texttt{AppStorageAddrs}_c\mid(c,f,s)\in\widetilde{\mathcal{S}}\}=\texttt{GetAppFcnStorages}_c(f)$
- $\widetilde{\mathcal{P}}:=\{(c,s,k)\mid c\in\texttt{ChannelIds}\ \wedge\ (s,k)\in\mathcal{P}_c\}$
  - Bridge-manager consistency: $\forall(c,s,k)\in\widetilde{\mathcal{P}},\ (s,k)\in\mathcal{P}_M$
  - Getter: $\texttt{GetChannelPreAllocKeys}:\texttt{ChannelIds}\times\mathbb{F}_{160}\to\mathcal{P}(\mathbb{F}_{256})$, where $\texttt{GetChannelPreAllocKeys}(c,s):=\{k\in\mathbb{F}_{256}\mid(c,s,k)\in\widetilde{\mathcal{P}}\}=\texttt{GetAppPreAllocKeys}_c(s)$
- $\widetilde{\mathcal{U}}:=\{(c,s,u)\mid c\in\texttt{ChannelIds}\ \wedge\ (s,u)\in\mathcal{U}_c\}$
  - Bridge-manager consistency: $\forall(c,s,u)\in\widetilde{\mathcal{U}},\ (s,u)\in\mathcal{U}_M$
  - Getter: $\texttt{GetChannelUserSlots}:\texttt{ChannelIds}\times\mathbb{F}_{160}\to\mathcal{P}(\mathbb{F}_{8})$, where $\texttt{GetChannelUserSlots}(c,s):=\{u\in\mathbb{F}_{8}\mid(c,s,u)\in\widetilde{\mathcal{U}}\}=\texttt{GetAppUserSlots}_c(s)$
- $\widetilde{\mathcal{F}}:=\{(c,f,i,p)\mid c\in\texttt{ChannelIds}\ \wedge\ (f,i,p)\in\mathcal{F}_c\}$
  - Bridge-manager consistency: $\forall(c,f,i,p)\in\widetilde{\mathcal{F}},\ (f,i,p)\in\mathcal{F}_M$
  - Existence and uniqueness per channel-function pair: $\forall c\in\texttt{ChannelIds},\ \forall f\in\texttt{AppFcnSigs}_c,\ \exists!(i,p)\in\mathbb{F}_{256}\times\mathbb{F}_{256},\ (c,f,i,p)\in\widetilde{\mathcal{F}}$
  - Getter: $\texttt{GetChannelFcnCfg}:\{(c,f)\mid c\in\texttt{ChannelIds}\ \wedge\ f\in\texttt{AppFcnSigs}_c\}\to\mathbb{F}_{256}\times\mathbb{F}_{256}$, where $\texttt{GetChannelFcnCfg}(c,f):=(i,p)\ \text{where}\ (c,f,i,p)\in\widetilde{\mathcal{F}}=\texttt{GetAppFcnCfg}_c(f)$
- $\widetilde{\mathcal{K}}:=\{(c,u,s,k)\mid c\in\texttt{ChannelIds}\ \wedge\ (u,s,k)\in\mathcal{K}_c\}$
  - Uniqueness (without existence): $\forall c\in\texttt{ChannelIds},\ \forall u\in\texttt{UserAddrs}_c,\ \forall s\in\texttt{AppStorageAddrs}_c,\ \forall k_1,k_2\in\mathbb{F}_{256},\ ((c,u,s,k_1)\in\widetilde{\mathcal{K}}\wedge(c,u,s,k_2)\in\widetilde{\mathcal{K}})\Rightarrow k_1=k_2$
  - Getter: $\texttt{GetChannelUserStorageKey}:\{(c,u,s)\mid c\in\texttt{ChannelIds}\ \wedge\ (c,u)\in\widetilde{\mathcal{M}}\ \wedge\ s\in\texttt{AppStorageAddrs}_c\}\to\mathbb{F}_{256}$, where $\texttt{GetChannelUserStorageKey}(c,u,s):=k\ \text{where}\ (c,u,s,k)\in\widetilde{\mathcal{K}}=\texttt{GetAppUserStorageKey}_c(u,s)$
- $\widetilde{\mathcal{V}}:=\{(c,s,k,v)\mid c\in\texttt{ChannelIds}\ \wedge\ (s,k,v)\in\mathcal{V}_c\}$
  - Conditional existence and uniqueness on channel keys: $\forall c\in\texttt{ChannelIds},\ \forall s\in\texttt{AppStorageAddrs}_c,\ \forall k\in\mathbb{F}_{256},\ \left((\exists u\in\texttt{UserAddrs}_c,\ (c,u,s,k)\in\widetilde{\mathcal{K}})\Rightarrow \exists!v\in\mathbb{F}_{256},\ (c,s,k,v)\in\widetilde{\mathcal{V}}\right)$
  - Getter: $\texttt{GetChannelValidatedStorageValue}:\{(c,s,k)\mid c\in\texttt{ChannelIds}\ \wedge\ \exists u\in\texttt{UserAddrs}_c,\ (c,u,s,k)\in\widetilde{\mathcal{K}}\}\to\mathbb{F}_{256}$, where $\texttt{GetChannelValidatedStorageValue}(c,s,k):=v\ \text{where}\ (c,s,k,v)\in\widetilde{\mathcal{V}}=\texttt{GetAppValidatedStorageValue}_c(s,k)$
- $\widetilde{\mathcal{A}}:=\{(c,s,k,v)\mid c\in\texttt{ChannelIds}\ \wedge\ (s,k,v)\in\mathcal{A}_c\}$
  - Conditional existence and uniqueness on channel pre-allocated keys: $\forall c\in\texttt{ChannelIds},\ \forall (s,k)\in\mathcal{P}_c,\ \exists!v\in\mathbb{F}_{256},\ (c,s,k,v)\in\widetilde{\mathcal{A}}$
  - Getter: $\texttt{GetChannelPreAllocValue}:\{(c,s,k)\mid c\in\texttt{ChannelIds}\ \wedge\ (s,k)\in\mathcal{P}_c\}\to\mathbb{F}_{256}$, where $\texttt{GetChannelPreAllocValue}(c,s,k):=v\ \text{where}\ (c,s,k,v)\in\widetilde{\mathcal{A}}=\texttt{GetAppPreAllocValue}_c(s,k)$

Core access constraints:

- Every channel-scoped getter is indexed by channel ID $c\in\texttt{ChannelIds}$.
- Every user-scoped getter requires a membership witness $(c,u)\in\widetilde{\mathcal{M}}$ in its domain.

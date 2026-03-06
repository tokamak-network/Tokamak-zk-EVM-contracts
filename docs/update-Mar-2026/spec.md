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
- $\texttt{FcnCfgs}\subseteq\mathbb{F}_{256}\times\mathbb{F}_{256}$
  - A set of function-configuration pairs of instance hash and preprocess hash

#### Relations

Given $\texttt{FcnSigns}$ and MPT structural information involved with each of the contract functions, the bridge manager maintains and manages the following relations:

- $\mathcal{S}_M\subseteq\texttt{FcnSigns}\times\texttt{StorageAddrs}$
  - Existence: $\forall f\in\texttt{FcnSigns},\ \exists s\in\texttt{StorageAddrs},\ (f,s)\in\mathcal{S}_M$
  - Getter: $\texttt{GetFcnStorages}:\texttt{FcnSigns}\to\mathcal{P}(\texttt{StorageAddrs})$, where $\texttt{GetFcnStorages}(f):=\{s\in\texttt{StorageAddrs}\mid(f,s)\in\mathcal{S}_M\}$
- $\mathcal{P}_M\subseteq\texttt{StorageAddrs}\times\texttt{PreAllocKeys}$
  - Getter: $\texttt{GetPreAllocKeys}:\texttt{StorageAddrs}\to\mathcal{P}(\texttt{PreAllocKeys})$, where $\texttt{GetPreAllocKeys}(s):=\{k\in\texttt{PreAllocKeys}\mid(s,k)\in\mathcal{P}_M\}$
- $\mathcal{U}_M\subseteq\texttt{StorageAddrs}\times\texttt{UserStorageSlots}$
  - Getter: $\texttt{GetUserSlots}:\texttt{StorageAddrs}\to\mathcal{P}(\texttt{UserStorageSlots})$, where $\texttt{GetUserSlots}(s):=\{u\in\texttt{UserStorageSlots}\mid(s,u)\in\mathcal{U}_M\}$
- $\mathcal{F}_M\subseteq\texttt{FcnSigns}\times\texttt{FcnCfgs}$
  - Existence and uniqueness: $\forall f\in\texttt{FcnSigns},\ \exists!q\in\texttt{FcnCfgs}\ \text{s.t.}\ (f,q)\in\mathcal{F}_M$
  - Getter: $\texttt{GetFcnCfg}:\texttt{FcnSigns}\to\texttt{FcnCfgs}$, where $\texttt{GetFcnCfg}(f):=q\ \text{where}\ (f,q)\in\mathcal{F}_M$

### Channel

#### Scope

- $\texttt{UserAddrs}\subseteq\mathbb{F}_{256}$
  - A set of user addresses registered in a channel
- $\texttt{AppFcnSigs}\subseteq\texttt{FcnSigns}$
  - A set of contract function signatures supported by a channel
- $\texttt{AppStorageAddrs}:=\texttt{GetFcnStorages}[\texttt{AppFcnSigs}]$
  - A set of storage addresses referenced by the functions in $\texttt{AppFcnSigs}$
  - Inclusion: $\texttt{AppStorageAddrs}\subseteq\texttt{StorageAddrs}$
- $\texttt{AppPreAllocKeys}:=\texttt{GetPreAllocKeys}[\texttt{AppStorageAddrs}]$
  - A set of pre-allocated keys associated with $\texttt{AppStorageAddrs}$
  - Inclusion: $\texttt{AppPreAllocKeys}\subseteq\texttt{PreAllocKeys}$
- $\texttt{AppUserStorageSlots}:=\texttt{GetUserSlots}[\texttt{AppStorageAddrs}]$
  - A set of user storage slots associated with $\texttt{AppStorageAddrs}$
  - Inclusion: $\texttt{AppUserStorageSlots}\subseteq\texttt{UserStorageSlots}$
- $\texttt{AppFcnCfgs}:=\texttt{GetFcnCfg}[\texttt{AppFcnSigs}]$
  - A set of function-configuration pairs of instance hash and preprocess hash referenced by the functions in $\texttt{AppFcnSigs}$
  - Inclusion: $\texttt{AppFcnCfgs}\subseteq\texttt{FcnCfgs}$
- $\texttt{AppUserStorageKey}\subseteq\mathbb{F}_{256}$
  - A set of channel storage access keys used by users, distinct from Ethereum storage access keys
- $\texttt{AppValidatedStorageValues}\subseteq\mathbb{F}_{256}$
  - A set of validated channel storage values associated with user accesses
- $\texttt{AppPreAllocValues}\subseteq\mathbb{F}_{256}$
  - A set of fixed values assigned to pre-allocated keys in channel storage

#### Relations

Given $\texttt{AppFcnSigs}$, a channel derives the following projected relations:

- $\mathcal{S}:=\bigcup_{f\in\texttt{AppFcnSigs}}\left(\{f\}\times\texttt{GetFcnStorages}(f)\right)$
  - Inclusion: $\mathcal{S}\subseteq\mathcal{S}_M$
  - Getter: $\texttt{GetAppFcnStorages}:\texttt{AppFcnSigs}\to\mathcal{P}(\texttt{AppStorageAddrs})$, where $\texttt{GetAppFcnStorages}(f):=\{s\in\texttt{AppStorageAddrs}\mid(f,s)\in\mathcal{S}\}$
- $\mathcal{P}:=\bigcup_{s\in\texttt{AppStorageAddrs}}\left(\{s\}\times\texttt{GetPreAllocKeys}(s)\right)$
  - Inclusion: $\mathcal{P}\subseteq\mathcal{P}_M$
  - Getter: $\texttt{GetAppPreAllocKeys}:\texttt{AppStorageAddrs}\to\mathcal{P}(\texttt{AppPreAllocKeys})$, where $\texttt{GetAppPreAllocKeys}(s):=\{k\in\texttt{AppPreAllocKeys}\mid(s,k)\in\mathcal{P}\}$
- $\mathcal{U}:=\bigcup_{s\in\texttt{AppStorageAddrs}}\left(\{s\}\times\texttt{GetUserSlots}(s)\right)$
  - Inclusion: $\mathcal{U}\subseteq\mathcal{U}_M$
  - Getter: $\texttt{GetAppUserSlots}:\texttt{AppStorageAddrs}\to\mathcal{P}(\texttt{AppUserStorageSlots})$, where $\texttt{GetAppUserSlots}(s):=\{u\in\texttt{AppUserStorageSlots}\mid(s,u)\in\mathcal{U}\}$
- $\mathcal{F}:=\bigcup_{f\in\texttt{AppFcnSigs}}\left(\{f\}\times\{\texttt{GetFcnCfg}(f)\}\right)$
  - Inclusion: $\mathcal{F}\subseteq\mathcal{F}_M$
  - Getter: $\texttt{GetAppFcnCfg}:\texttt{AppFcnSigs}\to\texttt{AppFcnCfgs}$, where $\texttt{GetAppFcnCfg}(f):=q\ \text{where}\ (f,q)\in\mathcal{F}$

Given $\texttt{UserAddrs}$ and their channel storage access keys, a channel maintains and manages the following relations:

- $\mathcal{K}\subseteq\texttt{UserAddrs}\times\texttt{AppStorageAddrs}\times\texttt{AppUserStorageKey}$
  - Uniqueness (without existence): $\forall u\in\texttt{UserAddrs},\ \forall s\in\texttt{AppStorageAddrs},\ \forall k_1,k_2\in\texttt{AppUserStorageKey},\ ((u,s,k_1)\in\mathcal{K}\wedge(u,s,k_2)\in\mathcal{K})\Rightarrow k_1=k_2$
  - Getter: $\texttt{GetAppUserStorageKey}:\texttt{UserAddrs}\times\texttt{AppStorageAddrs}\to\texttt{AppUserStorageKey}$, where $\texttt{GetAppUserStorageKey}(u,s):=k\ \text{where}\ (u,s,k)\in\mathcal{K}$
- $\mathcal{V}\subseteq\texttt{AppStorageAddrs}\times\texttt{AppUserStorageKey}\times\texttt{AppValidatedStorageValues}$
  - Conditional existence and uniqueness on channel keys: $\forall s\in\texttt{AppStorageAddrs},\ \forall k\in\texttt{AppUserStorageKey},\ \left((\exists u\in\texttt{UserAddrs},\ (u,s,k)\in\mathcal{K})\Rightarrow \exists!v\in\texttt{AppValidatedStorageValues},\ (s,k,v)\in\mathcal{V}\right)$
  - Getter: $\texttt{GetAppValidatedStorageValue}:\{(s,k)\in\texttt{AppStorageAddrs}\times\texttt{AppUserStorageKey}\mid \exists u\in\texttt{UserAddrs},\ (u,s,k)\in\mathcal{K}\}\to\texttt{AppValidatedStorageValues}$, where $\texttt{GetAppValidatedStorageValue}(s,k):=v\ \text{where}\ (s,k,v)\in\mathcal{V}$
- $\mathcal{A}\subseteq\texttt{AppStorageAddrs}\times\texttt{AppPreAllocKeys}\times\texttt{AppPreAllocValues}$
  - Conditional existence and uniqueness on app pre-allocated keys: $\forall (s,k)\in\mathcal{P},\ \exists!v\in\texttt{AppPreAllocValues},\ (s,k,v)\in\mathcal{A}$
  - Getter: $\texttt{GetAppPreAllocValue}:\mathcal{P}\to\texttt{AppPreAllocValues}$, where $\texttt{GetAppPreAllocValue}(s,k):=v\ \text{where}\ (s,k,v)\in\mathcal{A}$


### Bridge Core

#### Scope

- $\texttt{ChannelIds}\subseteq\mathbb{F}_{256}$
  - A set of registered channel IDs
- For each $c\in\texttt{ChannelIds}$, let $X_c$ denote one channel instance satisfying the Channel section:

$$
\begin{aligned}
X_c:=(&\texttt{UserAddrs}_c,\texttt{AppFcnSigs}_c,\texttt{AppStorageAddrs}_c,\texttt{AppPreAllocKeys}_c,\texttt{AppUserStorageSlots}_c,\\
     &\texttt{AppFcnCfgs}_c,\texttt{AppUserStorageKey}_c,\texttt{AppValidatedStorageValues}_c,\texttt{AppPreAllocValues}_c,\\
     &\mathcal{S}_c,\mathcal{P}_c,\mathcal{U}_c,\mathcal{F}_c,\mathcal{K}_c,\mathcal{V}_c,\mathcal{A}_c)
\end{aligned}
$$

#### Relations

Given $\texttt{ChannelIds}$ and channel instances $\{X_c\}_{c\in\texttt{ChannelIds}}$, the core relations are lifted from channel relations:

- $\widetilde{\mathcal{M}}:=\bigcup_{c\in\texttt{ChannelIds}}\left(\{c\}\times\texttt{UserAddrs}_c\right)$
  - Getter: $\texttt{GetChannelUsers}:\texttt{ChannelIds}\to\mathcal{P}(\texttt{UserAddrs}_c)$, where $\texttt{GetChannelUsers}(c):=\{u\in\texttt{UserAddrs}_c\mid(c,u)\in\widetilde{\mathcal{M}}\}$
- $\widetilde{\mathcal{S}}:=\bigcup_{c\in\texttt{ChannelIds}}\left(\{c\}\times\mathcal{S}_c\right)$
  - Bridge-manager consistency: $\forall(c,f,s)\in\widetilde{\mathcal{S}},\ (f,s)\in\mathcal{S}_M$
  - Getter: $\texttt{GetChannelFcnStorages}:\{(c,f)\mid c\in\texttt{ChannelIds}\ \wedge\ f\in\texttt{AppFcnSigs}_c\}\to\mathcal{P}(\texttt{AppStorageAddrs}_c)$, where $\texttt{GetChannelFcnStorages}(c,f):=\texttt{GetAppFcnStorages}_c(f)$
- $\widetilde{\mathcal{P}}:=\bigcup_{c\in\texttt{ChannelIds}}\left(\{c\}\times\mathcal{P}_c\right)$
  - Bridge-manager consistency: $\forall(c,s,k)\in\widetilde{\mathcal{P}},\ (s,k)\in\mathcal{P}_M$
  - Getter: $\texttt{GetChannelPreAllocKeys}:\{(c,s)\mid c\in\texttt{ChannelIds}\ \wedge\ s\in\texttt{AppStorageAddrs}_c\}\to\mathcal{P}(\texttt{AppPreAllocKeys}_c)$, where $\texttt{GetChannelPreAllocKeys}(c,s):=\texttt{GetAppPreAllocKeys}_c(s)$
- $\widetilde{\mathcal{U}}:=\bigcup_{c\in\texttt{ChannelIds}}\left(\{c\}\times\mathcal{U}_c\right)$
  - Bridge-manager consistency: $\forall(c,s,u)\in\widetilde{\mathcal{U}},\ (s,u)\in\mathcal{U}_M$
  - Getter: $\texttt{GetChannelUserSlots}:\{(c,s)\mid c\in\texttt{ChannelIds}\ \wedge\ s\in\texttt{AppStorageAddrs}_c\}\to\mathcal{P}(\texttt{AppUserStorageSlots}_c)$, where $\texttt{GetChannelUserSlots}(c,s):=\texttt{GetAppUserSlots}_c(s)$
- $\widetilde{\mathcal{F}}:=\bigcup_{c\in\texttt{ChannelIds}}\left(\{c\}\times\mathcal{F}_c\right)$
  - Bridge-manager consistency: $\forall(c,f,q)\in\widetilde{\mathcal{F}},\ (f,q)\in\mathcal{F}_M$
  - Existence and uniqueness per channel-function pair: $\forall c\in\texttt{ChannelIds},\ \forall f\in\texttt{AppFcnSigs}_c,\ \exists!q\in\texttt{AppFcnCfgs}_c,\ (c,f,q)\in\widetilde{\mathcal{F}}$
  - Getter: $\texttt{GetChannelFcnCfg}:\{(c,f)\mid c\in\texttt{ChannelIds}\ \wedge\ f\in\texttt{AppFcnSigs}_c\}\to\texttt{AppFcnCfgs}_c$, where $\texttt{GetChannelFcnCfg}(c,f):=\texttt{GetAppFcnCfg}_c(f)$
- $\widetilde{\mathcal{K}}:=\bigcup_{c\in\texttt{ChannelIds}}\left(\{c\}\times\mathcal{K}_c\right)$
  - Uniqueness (without existence): $\forall c\in\texttt{ChannelIds},\ \forall u\in\texttt{UserAddrs}_c,\ \forall s\in\texttt{AppStorageAddrs}_c,\ \forall k_1,k_2\in\texttt{AppUserStorageKey}_c,\ ((c,u,s,k_1)\in\widetilde{\mathcal{K}}\wedge(c,u,s,k_2)\in\widetilde{\mathcal{K}})\Rightarrow k_1=k_2$
  - Getter: $\texttt{GetChannelUserStorageKey}:\{(c,u,s)\mid c\in\texttt{ChannelIds}\ \wedge\ (c,u)\in\widetilde{\mathcal{M}}\ \wedge\ s\in\texttt{AppStorageAddrs}_c\}\to\texttt{AppUserStorageKey}_c$, where $\texttt{GetChannelUserStorageKey}(c,u,s):=\texttt{GetAppUserStorageKey}_c(u,s)$
- $\widetilde{\mathcal{V}}:=\bigcup_{c\in\texttt{ChannelIds}}\left(\{c\}\times\mathcal{V}_c\right)$
  - Conditional existence and uniqueness on channel keys: $\forall c\in\texttt{ChannelIds},\ \forall s\in\texttt{AppStorageAddrs}_c,\ \forall k\in\texttt{AppUserStorageKey}_c,\ \left((\exists u\in\texttt{UserAddrs}_c,\ (c,u,s,k)\in\widetilde{\mathcal{K}})\Rightarrow \exists!v\in\texttt{AppValidatedStorageValues}_c,\ (c,s,k,v)\in\widetilde{\mathcal{V}}\right)$
  - Getter: $\texttt{GetChannelValidatedStorageValue}:\{(c,s,k)\mid c\in\texttt{ChannelIds}\ \wedge\ s\in\texttt{AppStorageAddrs}_c\ \wedge\ k\in\texttt{AppUserStorageKey}_c\ \wedge\ \exists u\in\texttt{UserAddrs}_c,\ (c,u,s,k)\in\widetilde{\mathcal{K}}\}\to\texttt{AppValidatedStorageValues}_c$, where $\texttt{GetChannelValidatedStorageValue}(c,s,k):=\texttt{GetAppValidatedStorageValue}_c(s,k)$
- $\widetilde{\mathcal{A}}:=\bigcup_{c\in\texttt{ChannelIds}}\left(\{c\}\times\mathcal{A}_c\right)$
  - Conditional existence and uniqueness on channel pre-allocated keys: $\forall c\in\texttt{ChannelIds},\ \forall (s,k)\in\mathcal{P}_c,\ \exists!v\in\texttt{AppPreAllocValues}_c,\ (c,s,k,v)\in\widetilde{\mathcal{A}}$
  - Getter: $\texttt{GetChannelPreAllocValue}:\{(c,s,k)\mid c\in\texttt{ChannelIds}\ \wedge\ (s,k)\in\mathcal{P}_c\}\to\texttt{AppPreAllocValues}_c$, where $\texttt{GetChannelPreAllocValue}(c,s,k):=\texttt{GetAppPreAllocValue}_c(s,k)$

Core access constraints:

- Every channel-scoped getter is indexed by channel ID $c\in\texttt{ChannelIds}$.
- Every user-scoped getter requires a membership witness $(c,u)\in\widetilde{\mathcal{M}}$ in its domain.

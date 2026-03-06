# Tokamak Private App Channels - Bridge Contract

### General

The bridge contract records and manages channel data.

$\mathbb{F}_{b}$ is the field of $b$-bit words.

### Bridge manager

#### Scope

- $\texttt{FcnSigns}\subseteq\mathbb{F}_{32}$
  - A set of contract function signatures

#### Relations

Given $\texttt{FcnSigns}$ and MPT structural information involved with each of the contract functions, the bridge manager maintains and manages the following relations:

- $\mathcal{S}_M\subseteq\texttt{FcnSigns}\times\mathbb{F}_{160}$
  - Existence: $\forall f\in\texttt{FcnSigns},\ \exists s\in\mathbb{F}_{160},\ (f,s)\in\mathcal{S}_M$
  - Getter: $\texttt{GetFcnStorages}:\texttt{FcnSigns}\to\mathcal{P}(\mathbb{F}_{160})$, where $\texttt{GetFcnStorages}(f):=\{s\in\mathbb{F}_{160}\mid(f,s)\in\mathcal{S}_M\}$
- $\mathcal{P}_M\subseteq\mathbb{F}_{160}\times\mathbb{F}_{256}$
  - Getter: $\texttt{GetPreAllocKeys}:\mathbb{F}_{160}\to\mathcal{P}(\mathbb{F}_{256})$, where $\texttt{GetPreAllocKeys}(s):=\{k\in\mathbb{F}_{256}\mid(s,k)\in\mathcal{P}_M\}$
- $\mathcal{U}_M\subseteq\mathbb{F}_{160}\times\mathbb{F}_{8}$
  - Getter: $\texttt{GetUserSlots}:\mathbb{F}_{160}\to\mathcal{P}(\mathbb{F}_{8})$, where $\texttt{GetUserSlots}(s):=\{u\in\mathbb{F}_{8}\mid(s,u)\in\mathcal{U}_M\}$
- $\mathcal{F}_M\subseteq\texttt{FcnSigns}\times\mathbb{F}_{256}\times\mathbb{F}_{256}$
  - Existence and uniqueness: $\forall f\in\texttt{FcnSigns},\ \exists!(i,p)\in\mathbb{F}_{256}\times\mathbb{F}_{256}\ \text{s.t.}\ (f,i,p)\in\mathcal{F}_M$
  - Getter: $\texttt{GetFcnCfg}:\texttt{FcnSigns}\to\mathbb{F}_{256}\times\mathbb{F}_{256}$, where $\texttt{GetFcnCfg}(f):=(i,p)\ \text{where}\ (f,i,p)\in\mathcal{F}_M$

### Channel

#### Scope

- $\texttt{UserAddrs}\subseteq\mathbb{F}_{256}$
  - A set of user addresses
- $\texttt{AppFcnSigs}\subseteq\texttt{FcnSigns}$
  - A set of contract function signatures that is supported by a channel
- $\texttt{AppStorages}:=\bigcup_{f\in\texttt{AppFcnSigs}}\texttt{GetFcnStorages}(f)$
  - A set of storage addresses that the contract functions in $\texttt{AppFcnSigs}$ handle

#### Relations

Given $\texttt{AppFcnSigs}$, a channel derives the following projected relations:

- $\mathcal{S}_C:=\{(f,s)\mid f\in\texttt{AppFcnSigs}\ \wedge\ s\in\texttt{GetFcnStorages}(f)\}$
  - Inclusion: $\mathcal{S}_C\subseteq\mathcal{S}_M$
  - Getter: $\texttt{GetAppFcnStorages}:\texttt{AppFcnSigs}\to\mathcal{P}(\mathbb{F}_{160})$, where $\texttt{GetAppFcnStorages}(f):=\{s\in\mathbb{F}_{160}\mid(f,s)\in\mathcal{S}_C\}$
- $\mathcal{P}_C:=\{(s,k)\mid s\in\texttt{AppStorages}\ \wedge\ k\in\texttt{GetPreAllocKeys}(s)\}$
  - Inclusion: $\mathcal{P}_C\subseteq\mathcal{P}_M$
  - Getter: $\texttt{GetAppPreAllocKeys}:\texttt{AppStorages}\to\mathcal{P}(\mathbb{F}_{256})$, where $\texttt{GetAppPreAllocKeys}(s):=\{k\in\mathbb{F}_{256}\mid(s,k)\in\mathcal{P}_C\}$
- $\mathcal{U}_C:=\{(s,u)\mid s\in\texttt{AppStorages}\ \wedge\ u\in\texttt{GetUserSlots}(s)\}$
  - Inclusion: $\mathcal{U}_C\subseteq\mathcal{U}_M$
  - Getter: $\texttt{GetAppUserSlots}:\texttt{AppStorages}\to\mathcal{P}(\mathbb{F}_{8})$, where $\texttt{GetAppUserSlots}(s):=\{u\in\mathbb{F}_{8}\mid(s,u)\in\mathcal{U}_C\}$
- $\mathcal{F}_C:=\{(f,i,p)\mid f\in\texttt{AppFcnSigs}\ \wedge\ \texttt{GetFcnCfg}(f)=(i,p)\}$
  - Inclusion: $\mathcal{F}_C\subseteq\mathcal{F}_M$
  - Getter: $\texttt{GetAppFcnCfg}:\texttt{AppFcnSigs}\to\mathbb{F}_{256}\times\mathbb{F}_{256}$, where $\texttt{GetAppFcnCfg}(f):=(i,p)\ \text{where}\ (f,i,p)\in\mathcal{F}_C$

Given $\texttt{UserAddrs}$ and their channel storage access keys, a channel maintains and manages the following relations:

- $\mathcal{K}_C\subseteq\texttt{UserAddrs}\times\texttt{AppStorages}\times\mathbb{F}_{256}$
  - Uniqueness (without existence): $\forall u\in\texttt{UserAddrs},\ \forall s\in\texttt{AppStorages},\ \forall k_1,k_2\in\mathbb{F}_{256},\ ((u,s,k_1)\in\mathcal{K}_C\wedge(u,s,k_2)\in\mathcal{K}_C)\Rightarrow k_1=k_2$
  - Getter: $\texttt{GetAppUserStorageKey}:\texttt{UserAddrs}\times\texttt{AppStorages}\to\mathbb{F}_{256}$, where $\texttt{GetAppUserStorageKey}(u,s):=k\ \text{where}\ (u,s,k)\in\mathcal{K}_C$
- $\mathcal{V}_C\subseteq\texttt{AppStorages}\times\mathbb{F}_{256}\times\mathbb{F}_{256}$
  - Conditional existence and uniqueness on channel keys: $\forall s\in\texttt{AppStorages},\ \forall k\in\mathbb{F}_{256},\ \left((\exists u\in\texttt{UserAddrs},\ (u,s,k)\in\mathcal{K}_C)\Rightarrow \exists!v\in\mathbb{F}_{256},\ (s,k,v)\in\mathcal{V}_C\right)$
  - Getter: $\texttt{GetAppValidatedStorageValue}:\{(s,k)\in\texttt{AppStorages}\times\mathbb{F}_{256}\mid \exists u\in\texttt{UserAddrs},\ (u,s,k)\in\mathcal{K}_C\}\to\mathbb{F}_{256}$, where $\texttt{GetAppValidatedStorageValue}(s,k):=v\ \text{where}\ (s,k,v)\in\mathcal{V}_C$
- $\mathcal{A}_C\subseteq\texttt{AppStorages}\times\mathbb{F}_{256}\times\mathbb{F}_{256}$
  - Conditional existence and uniqueness on app pre-allocated keys: $\forall (s,k)\in\mathcal{P}_C,\ \exists!v\in\mathbb{F}_{256},\ (s,k,v)\in\mathcal{A}_C$
  - Getter: $\texttt{GetAppPreAllocValue}:\mathcal{P}_C\to\mathbb{F}_{256}$, where $\texttt{GetAppPreAllocValue}(s,k):=v\ \text{where}\ (s,k,v)\in\mathcal{A}_C$


### Bridge Core

#### Scope

- $\texttt{ChannelIds}\subseteq\mathbb{F}_{256}$
  - A set of registered channel IDs
- For each $c\in\texttt{ChannelIds}$, let $X_c$ denote one channel instance satisfying the Channel section:
  - $X_c=(\texttt{UserAddrs}_c,\texttt{AppFcnSigs}_c,\texttt{AppStorages}_c,\mathcal{S}_{C,c},\mathcal{P}_{C,c},\mathcal{U}_{C,c},\mathcal{F}_{C,c},\mathcal{K}_{C,c},\mathcal{V}_{C,c},\mathcal{A}_{C,c})$

#### Relations

Given $\texttt{ChannelIds}$ and channel instances $\{X_c\}_{c\in\texttt{ChannelIds}}$, the core relations are lifted from channel relations:

- $\mathcal{M}:=\{(c,u)\mid c\in\texttt{ChannelIds}\ \wedge\ u\in\texttt{UserAddrs}_c\}$
  - Getter: $\texttt{GetChannelUsers}:\texttt{ChannelIds}\to\mathcal{P}(\mathbb{F}_{256})$, where $\texttt{GetChannelUsers}(c):=\{u\in\mathbb{F}_{256}\mid(c,u)\in\mathcal{M}\}$
- $\mathcal{S}:=\{(c,f,s)\mid c\in\texttt{ChannelIds}\ \wedge\ (f,s)\in\mathcal{S}_{C,c}\}$
  - Bridge-manager consistency: $\forall(c,f,s)\in\mathcal{S},\ (f,s)\in\mathcal{S}_M$
  - Getter: $\texttt{GetChannelFcnStorages}:\texttt{ChannelIds}\times\mathbb{F}_{32}\to\mathcal{P}(\mathbb{F}_{160})$, where $\texttt{GetChannelFcnStorages}(c,f):=\{s\in\mathbb{F}_{160}\mid(c,f,s)\in\mathcal{S}\}=\texttt{GetAppFcnStorages}_c(f)$
- $\mathcal{P}:=\{(c,s,k)\mid c\in\texttt{ChannelIds}\ \wedge\ (s,k)\in\mathcal{P}_{C,c}\}$
  - Bridge-manager consistency: $\forall(c,s,k)\in\mathcal{P},\ (s,k)\in\mathcal{P}_M$
  - Getter: $\texttt{GetChannelPreAllocKeys}:\texttt{ChannelIds}\times\mathbb{F}_{160}\to\mathcal{P}(\mathbb{F}_{256})$, where $\texttt{GetChannelPreAllocKeys}(c,s):=\{k\in\mathbb{F}_{256}\mid(c,s,k)\in\mathcal{P}\}=\texttt{GetAppPreAllocKeys}_c(s)$
- $\mathcal{U}:=\{(c,s,u)\mid c\in\texttt{ChannelIds}\ \wedge\ (s,u)\in\mathcal{U}_{C,c}\}$
  - Bridge-manager consistency: $\forall(c,s,u)\in\mathcal{U},\ (s,u)\in\mathcal{U}_M$
  - Getter: $\texttt{GetChannelUserSlots}:\texttt{ChannelIds}\times\mathbb{F}_{160}\to\mathcal{P}(\mathbb{F}_{8})$, where $\texttt{GetChannelUserSlots}(c,s):=\{u\in\mathbb{F}_{8}\mid(c,s,u)\in\mathcal{U}\}=\texttt{GetAppUserSlots}_c(s)$
- $\mathcal{F}:=\{(c,f,i,p)\mid c\in\texttt{ChannelIds}\ \wedge\ (f,i,p)\in\mathcal{F}_{C,c}\}$
  - Bridge-manager consistency: $\forall(c,f,i,p)\in\mathcal{F},\ (f,i,p)\in\mathcal{F}_M$
  - Existence and uniqueness per channel-function pair: $\forall c\in\texttt{ChannelIds},\ \forall f\in\texttt{AppFcnSigs}_c,\ \exists!(i,p)\in\mathbb{F}_{256}\times\mathbb{F}_{256},\ (c,f,i,p)\in\mathcal{F}$
  - Getter: $\texttt{GetChannelFcnCfg}:\{(c,f)\mid c\in\texttt{ChannelIds}\ \wedge\ f\in\texttt{AppFcnSigs}_c\}\to\mathbb{F}_{256}\times\mathbb{F}_{256}$, where $\texttt{GetChannelFcnCfg}(c,f):=(i,p)\ \text{where}\ (c,f,i,p)\in\mathcal{F}=\texttt{GetAppFcnCfg}_c(f)$
- $\mathcal{K}:=\{(c,u,s,k)\mid c\in\texttt{ChannelIds}\ \wedge\ (u,s,k)\in\mathcal{K}_{C,c}\}$
  - Uniqueness (without existence): $\forall c\in\texttt{ChannelIds},\ \forall u\in\texttt{UserAddrs}_c,\ \forall s\in\texttt{AppStorages}_c,\ \forall k_1,k_2\in\mathbb{F}_{256},\ ((c,u,s,k_1)\in\mathcal{K}\wedge(c,u,s,k_2)\in\mathcal{K})\Rightarrow k_1=k_2$
  - Getter: $\texttt{GetChannelUserStorageKey}:\{(c,u,s)\mid c\in\texttt{ChannelIds}\ \wedge\ (c,u)\in\mathcal{M}\ \wedge\ s\in\texttt{AppStorages}_c\}\to\mathbb{F}_{256}$, where $\texttt{GetChannelUserStorageKey}(c,u,s):=k\ \text{where}\ (c,u,s,k)\in\mathcal{K}=\texttt{GetAppUserStorageKey}_c(u,s)$
- $\mathcal{V}:=\{(c,s,k,v)\mid c\in\texttt{ChannelIds}\ \wedge\ (s,k,v)\in\mathcal{V}_{C,c}\}$
  - Conditional existence and uniqueness on channel keys: $\forall c\in\texttt{ChannelIds},\ \forall s\in\texttt{AppStorages}_c,\ \forall k\in\mathbb{F}_{256},\ \left((\exists u\in\texttt{UserAddrs}_c,\ (c,u,s,k)\in\mathcal{K})\Rightarrow \exists!v\in\mathbb{F}_{256},\ (c,s,k,v)\in\mathcal{V}\right)$
  - Getter: $\texttt{GetChannelValidatedStorageValue}:\{(c,s,k)\mid c\in\texttt{ChannelIds}\ \wedge\ \exists u\in\texttt{UserAddrs}_c,\ (c,u,s,k)\in\mathcal{K}\}\to\mathbb{F}_{256}$, where $\texttt{GetChannelValidatedStorageValue}(c,s,k):=v\ \text{where}\ (c,s,k,v)\in\mathcal{V}=\texttt{GetAppValidatedStorageValue}_c(s,k)$
- $\mathcal{A}:=\{(c,s,k,v)\mid c\in\texttt{ChannelIds}\ \wedge\ (s,k,v)\in\mathcal{A}_{C,c}\}$
  - Conditional existence and uniqueness on channel pre-allocated keys: $\forall c\in\texttt{ChannelIds},\ \forall (s,k)\in\mathcal{P}_{C,c},\ \exists!v\in\mathbb{F}_{256},\ (c,s,k,v)\in\mathcal{A}$
  - Getter: $\texttt{GetChannelPreAllocValue}:\{(c,s,k)\mid c\in\texttt{ChannelIds}\ \wedge\ (s,k)\in\mathcal{P}_{C,c}\}\to\mathbb{F}_{256}$, where $\texttt{GetChannelPreAllocValue}(c,s,k):=v\ \text{where}\ (c,s,k,v)\in\mathcal{A}=\texttt{GetAppPreAllocValue}_c(s,k)$

Core access constraints:

- Every channel-scoped getter is indexed by channel ID $c\in\texttt{ChannelIds}$.
- Every user-scoped getter requires a membership witness $(c,u)\in\mathcal{M}$ in its domain.

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

- $\mathcal{S}\subseteq\texttt{FcnSigns}\times\mathbb{F}_{160}$
  - Existence: $\forall f\in\texttt{FcnSigns},\ \exists s\in\mathbb{F}_{160},\ (f,s)\in\mathcal{S}$
  - Getter: $\texttt{GetFcnStorages}:\texttt{FcnSigns}\to\mathcal{P}(\mathbb{F}_{160})$, where $\texttt{GetFcnStorages}(f):=\{s\in\mathbb{F}_{160}\mid(f,s)\in\mathcal{S}\}$
- $\mathcal{P}\subseteq\mathbb{F}_{160}\times\mathbb{F}_{256}$
  - Getter: $\texttt{GetPreAllocKeys}:\mathbb{F}_{160}\to\mathcal{P}(\mathbb{F}_{256})$, where $\texttt{GetPreAllocKeys}(s):=\{k\in\mathbb{F}_{256}\mid(s,k)\in\mathcal{P}\}$
- $\mathcal{U}\subseteq\mathbb{F}_{160}\times\mathbb{F}_{8}$
  - Getter: $\texttt{GetUserSlots}:\mathbb{F}_{160}\to\mathcal{P}(\mathbb{F}_{8})$, where $\texttt{GetUserSlots}(s):=\{u\in\mathbb{F}_{8}\mid(s,u)\in\mathcal{U}\}$
- $\mathcal{F}\subseteq\texttt{FcnSigns}\times\mathbb{F}_{256}\times\mathbb{F}_{256}$
  - Existence and uniqueness: $\forall f\in\texttt{FcnSigns},\ \exists!(i,p)\in\mathbb{F}_{256}\times\mathbb{F}_{256}\ \text{s.t.}\ (f,i,p)\in\mathcal{F}$
  - Getter: $\texttt{GetFcnCfg}:\texttt{FcnSigns}\to\mathbb{F}_{256}\times\mathbb{F}_{256}$, where $\texttt{GetFcnCfg}(f):=(i,p)\ \text{where}\ (f,i,p)\in\mathcal{F}$

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

- $\widetilde{\mathcal{S}}:=\{(f,s)\mid f\in\texttt{AppFcnSigs}\ \wedge\ s\in\texttt{GetFcnStorages}(f)\}$
  - Inclusion: $\widetilde{\mathcal{S}}\subseteq\mathcal{S}$
  - Getter: $\texttt{GetAppFcnStorages}:\texttt{AppFcnSigs}\to\mathcal{P}(\mathbb{F}_{160})$, where $\texttt{GetAppFcnStorages}(f):=\{s\in\mathbb{F}_{160}\mid(f,s)\in\widetilde{\mathcal{S}}\}$
- $\widetilde{\mathcal{P}}:=\{(s,k)\mid s\in\texttt{AppStorages}\ \wedge\ k\in\texttt{GetPreAllocKeys}(s)\}$
  - Inclusion: $\widetilde{\mathcal{P}}\subseteq\mathcal{P}$
  - Getter: $\texttt{GetAppPreAllocKeys}:\texttt{AppStorages}\to\mathcal{P}(\mathbb{F}_{256})$, where $\texttt{GetAppPreAllocKeys}(s):=\{k\in\mathbb{F}_{256}\mid(s,k)\in\widetilde{\mathcal{P}}\}$
- $\widetilde{\mathcal{U}}:=\{(s,u)\mid s\in\texttt{AppStorages}\ \wedge\ u\in\texttt{GetUserSlots}(s)\}$
  - Inclusion: $\widetilde{\mathcal{U}}\subseteq\mathcal{U}$
  - Getter: $\texttt{GetAppUserSlots}:\texttt{AppStorages}\to\mathcal{P}(\mathbb{F}_{8})$, where $\texttt{GetAppUserSlots}(s):=\{u\in\mathbb{F}_{8}\mid(s,u)\in\widetilde{\mathcal{U}}\}$
- $\widetilde{\mathcal{F}}:=\{(f,i,p)\mid f\in\texttt{AppFcnSigs}\ \wedge\ \texttt{GetFcnCfg}(f)=(i,p)\}$
  - Inclusion: $\widetilde{\mathcal{F}}\subseteq\mathcal{F}$
  - Getter: $\texttt{GetAppFcnCfg}:\texttt{AppFcnSigs}\to\mathbb{F}_{256}\times\mathbb{F}_{256}$, where $\texttt{GetAppFcnCfg}(f):=(i,p)\ \text{where}\ (f,i,p)\in\widetilde{\mathcal{F}}$

Given $\texttt{UserAddrs}$ and their channel storage access keys, a channel maintains and manages the following relations:

- $\mathcal{K}\subseteq\texttt{UserAddrs}\times\texttt{AppStorages}\times\mathbb{F}_{256}$
  - Uniqueness (without existence): $\forall u\in\texttt{UserAddrs},\ \forall s\in\texttt{AppStorages},\ \forall k_1,k_2\in\mathbb{F}_{256},\ ((u,s,k_1)\in\mathcal{K}\wedge(u,s,k_2)\in\mathcal{K})\Rightarrow k_1=k_2$
  - Getter: $\texttt{GetUserStorageKey}:\texttt{UserAddrs}\times\texttt{AppStorages}\to\mathbb{F}_{256}$, where $\texttt{GetUserStorageKey}(u,s):=k\ \text{where}\ (u,s,k)\in\mathcal{K}$
- $\mathcal{V}\subseteq\texttt{AppStorages}\times\mathbb{F}_{256}\times\mathbb{F}_{256}$
  - Conditional existence and uniqueness on channel keys: $\forall s\in\texttt{AppStorages},\ \forall k\in\mathbb{F}_{256},\ \left((\exists u\in\texttt{UserAddrs},\ (u,s,k)\in\mathcal{K})\Rightarrow \exists!v\in\mathbb{F}_{256},\ (s,k,v)\in\mathcal{V}\right)$
  - Getter: $\texttt{GetValidatedStorageValue}:\{(s,k)\in\texttt{AppStorages}\times\mathbb{F}_{256}\mid \exists u\in\texttt{UserAddrs},\ (u,s,k)\in\mathcal{K}\}\to\mathbb{F}_{256}$, where $\texttt{GetValidatedStorageValue}(s,k):=v\ \text{where}\ (s,k,v)\in\mathcal{V}$
- $\mathcal{A}\subseteq\texttt{AppStorages}\times\mathbb{F}_{256}\times\mathbb{F}_{256}$
  - Conditional existence and uniqueness on app pre-allocated keys: $\forall (s,k)\in\widetilde{\mathcal{P}},\ \exists!v\in\mathbb{F}_{256},\ (s,k,v)\in\mathcal{A}$
  - Getter: $\texttt{GetAppPreAllocValue}:\widetilde{\mathcal{P}}\to\mathbb{F}_{256}$, where $\texttt{GetAppPreAllocValue}(s,k):=v\ \text{where}\ (s,k,v)\in\mathcal{A}$


### Bridge Core

#### Scope

- $\mathcal{C}\subseteq\mathbb{F}_{256}$
  - A set of registered channel IDs

#### Relations

Given $\mathcal{C}$, the bridge core stores channel-indexed relations and serves as the unique access layer for channel state.

- $\mathcal{M}^{\mathrm{C}}\subseteq\mathcal{C}\times\mathbb{F}_{256}$
  - Meaning: channel-user membership
  - Getter: $\texttt{GetChannelUsers}:\mathcal{C}\to\mathcal{P}(\mathbb{F}_{256})$, where $\texttt{GetChannelUsers}(c):=\{u\in\mathbb{F}_{256}\mid(c,u)\in\mathcal{M}^{\mathrm{C}}\}$
- $\mathcal{S}^{\mathrm{C}}\subseteq\mathcal{C}\times\mathbb{F}_{32}\times\mathbb{F}_{160}$
  - Inclusion: $\forall c\in\mathcal{C},\ \forall f\in\mathbb{F}_{32},\ \forall s\in\mathbb{F}_{160},\ (c,f,s)\in\mathcal{S}^{\mathrm{C}}\Rightarrow(f,s)\in\mathcal{S}$
  - Getter: $\texttt{GetChannelFcnStorages}:\mathcal{C}\times\mathbb{F}_{32}\to\mathcal{P}(\mathbb{F}_{160})$, where $\texttt{GetChannelFcnStorages}(c,f):=\{s\in\mathbb{F}_{160}\mid(c,f,s)\in\mathcal{S}^{\mathrm{C}}\}$
- $\mathcal{P}^{\mathrm{C}}\subseteq\mathcal{C}\times\mathbb{F}_{160}\times\mathbb{F}_{256}$
  - Inclusion: $\forall c\in\mathcal{C},\ \forall s\in\mathbb{F}_{160},\ \forall k\in\mathbb{F}_{256},\ (c,s,k)\in\mathcal{P}^{\mathrm{C}}\Rightarrow(s,k)\in\mathcal{P}$
  - Getter: $\texttt{GetChannelPreAllocKeys}:\mathcal{C}\times\mathbb{F}_{160}\to\mathcal{P}(\mathbb{F}_{256})$, where $\texttt{GetChannelPreAllocKeys}(c,s):=\{k\in\mathbb{F}_{256}\mid(c,s,k)\in\mathcal{P}^{\mathrm{C}}\}$
- $\mathcal{U}^{\mathrm{C}}\subseteq\mathcal{C}\times\mathbb{F}_{160}\times\mathbb{F}_{8}$
  - Inclusion: $\forall c\in\mathcal{C},\ \forall s\in\mathbb{F}_{160},\ \forall u\in\mathbb{F}_{8},\ (c,s,u)\in\mathcal{U}^{\mathrm{C}}\Rightarrow(s,u)\in\mathcal{U}$
  - Getter: $\texttt{GetChannelUserSlots}:\mathcal{C}\times\mathbb{F}_{160}\to\mathcal{P}(\mathbb{F}_{8})$, where $\texttt{GetChannelUserSlots}(c,s):=\{u\in\mathbb{F}_{8}\mid(c,s,u)\in\mathcal{U}^{\mathrm{C}}\}$
- $\mathcal{F}^{\mathrm{C}}\subseteq\mathcal{C}\times\mathbb{F}_{32}\times\mathbb{F}_{256}\times\mathbb{F}_{256}$
  - Inclusion: $\forall c\in\mathcal{C},\ \forall f\in\mathbb{F}_{32},\ \forall i,p\in\mathbb{F}_{256},\ (c,f,i,p)\in\mathcal{F}^{\mathrm{C}}\Rightarrow(f,i,p)\in\mathcal{F}$
  - Existence and uniqueness per channel-function pair: $\forall c\in\mathcal{C},\ \forall f\in\{f'\in\mathbb{F}_{32}\mid \exists s\in\mathbb{F}_{160},\ (c,f',s)\in\mathcal{S}^{\mathrm{C}}\},\ \exists!(i,p)\in\mathbb{F}_{256}\times\mathbb{F}_{256},\ (c,f,i,p)\in\mathcal{F}^{\mathrm{C}}$
  - Getter: $\texttt{GetChannelFcnCfg}:\{(c,f)\in\mathcal{C}\times\mathbb{F}_{32}\mid \exists s\in\mathbb{F}_{160},\ (c,f,s)\in\mathcal{S}^{\mathrm{C}}\}\to\mathbb{F}_{256}\times\mathbb{F}_{256}$, where $\texttt{GetChannelFcnCfg}(c,f):=(i,p)\ \text{where}\ (c,f,i,p)\in\mathcal{F}^{\mathrm{C}}$
- $\mathcal{K}^{\mathrm{C}}\subseteq\mathcal{C}\times\mathbb{F}_{256}\times\mathbb{F}_{160}\times\mathbb{F}_{256}$
  - Uniqueness (without existence): $\forall c\in\mathcal{C},\ \forall u\in\mathbb{F}_{256},\ \forall s\in\mathbb{F}_{160},\ \forall k_1,k_2\in\mathbb{F}_{256},\ ((c,u,s,k_1)\in\mathcal{K}^{\mathrm{C}}\wedge(c,u,s,k_2)\in\mathcal{K}^{\mathrm{C}})\Rightarrow k_1=k_2$
  - Getter: $\texttt{GetChannelUserStorageKey}:\{(c,u,s)\in\mathcal{C}\times\mathbb{F}_{256}\times\mathbb{F}_{160}\mid (c,u)\in\mathcal{M}^{\mathrm{C}}\}\to\mathbb{F}_{256}$, where $\texttt{GetChannelUserStorageKey}(c,u,s):=k\ \text{where}\ (c,u,s,k)\in\mathcal{K}^{\mathrm{C}}$
- $\mathcal{V}^{\mathrm{C}}\subseteq\mathcal{C}\times\mathbb{F}_{160}\times\mathbb{F}_{256}\times\mathbb{F}_{256}$
  - Conditional existence and uniqueness on channel keys: $\forall c\in\mathcal{C},\ \forall s\in\mathbb{F}_{160},\ \forall k\in\mathbb{F}_{256},\ \left((\exists u\in\mathbb{F}_{256},\ (c,u,s,k)\in\mathcal{K}^{\mathrm{C}})\Rightarrow \exists!v\in\mathbb{F}_{256},\ (c,s,k,v)\in\mathcal{V}^{\mathrm{C}}\right)$
  - Getter: $\texttt{GetChannelValidatedStorageValue}:\{(c,s,k)\in\mathcal{C}\times\mathbb{F}_{160}\times\mathbb{F}_{256}\mid \exists u\in\mathbb{F}_{256},\ (c,u,s,k)\in\mathcal{K}^{\mathrm{C}}\}\to\mathbb{F}_{256}$, where $\texttt{GetChannelValidatedStorageValue}(c,s,k):=v\ \text{where}\ (c,s,k,v)\in\mathcal{V}^{\mathrm{C}}$
- $\mathcal{A}^{\mathrm{C}}\subseteq\mathcal{C}\times\mathbb{F}_{160}\times\mathbb{F}_{256}\times\mathbb{F}_{256}$
  - Conditional existence and uniqueness on channel pre-allocated keys: $\forall c\in\mathcal{C},\ \forall (s,k)\in\{(s',k')\in\mathbb{F}_{160}\times\mathbb{F}_{256}\mid (c,s',k')\in\mathcal{P}^{\mathrm{C}}\},\ \exists!v\in\mathbb{F}_{256},\ (c,s,k,v)\in\mathcal{A}^{\mathrm{C}}$
  - Getter: $\texttt{GetChannelPreAllocValue}:\{(c,s,k)\in\mathcal{C}\times\mathbb{F}_{160}\times\mathbb{F}_{256}\mid (c,s,k)\in\mathcal{P}^{\mathrm{C}}\}\to\mathbb{F}_{256}$, where $\texttt{GetChannelPreAllocValue}(c,s,k):=v\ \text{where}\ (c,s,k,v)\in\mathcal{A}^{\mathrm{C}}$

Core access constraints:

- Every channel-scoped getter is indexed by $c\in\mathcal{C}$.
- Every user-scoped getter requires a membership witness $(c,u)\in\mathcal{M}^{\mathrm{C}}$ in its domain.

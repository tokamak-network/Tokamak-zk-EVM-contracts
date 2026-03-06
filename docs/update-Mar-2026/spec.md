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
- $\texttt{AppFcnSigs}\subseteq\texttt{FcnSigns}$
- $\texttt{AppStorages}:=\bigcup_{f\in\texttt{AppFcnSigs}}\texttt{GetFcnStorages}(f)$

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

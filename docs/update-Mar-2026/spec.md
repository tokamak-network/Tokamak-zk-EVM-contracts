# Tokamak Private App Channels - Bridge Contract

### General

The bridge contract records and manages channel data.

$\mathbb{F}_{b}$ is the field of $b$-bit words.

### Bridge manager

#### Scope

- $\texttt{FcnSigns}\subseteq\mathbb{F}_{32}$ (managed function-signature set)

#### Relations

- $\mathcal{S}\subseteq\texttt{FcnSigns}\times\mathbb{F}_{160}$
- $\mathcal{P}\subseteq\mathbb{F}_{160}\times\mathbb{F}_{256}$
- $\mathcal{U}\subseteq\mathbb{F}_{160}\times\mathbb{F}_{8}$
- $\mathcal{F}\subseteq\texttt{FcnSigns}\times\mathbb{F}_{256}\times\mathbb{F}_{256}$

#### Constraints

- $\forall f\in\texttt{FcnSigns},\ \exists s\in\mathbb{F}_{160},\ (f,s)\in\mathcal{S}$
- $\forall f\in\texttt{FcnSigns},\ \exists i,p\in\mathbb{F}_{256},\ (f,i,p)\in\mathcal{F}$
- $\forall f\in\texttt{FcnSigns},\ \forall i_1,p_1,i_2,p_2\in\mathbb{F}_{256},\ ((f,i_1,p_1)\in\mathcal{F}\wedge(f,i_2,p_2)\in\mathcal{F})\Rightarrow(i_1=i_2\wedge p_1=p_2)$

#### Getters

- $\texttt{GetFcnStorages}:\texttt{FcnSigns}\to\mathcal{P}(\mathbb{F}_{160})$
- $\texttt{GetFcnStorages}(f):=\{s\in\mathbb{F}_{160}\mid(f,s)\in\mathcal{S}\}$
- $\texttt{GetPreAllocKeys}:\mathbb{F}_{160}\to\mathcal{P}(\mathbb{F}_{256})$
- $\texttt{GetPreAllocKeys}(s):=\{k\in\mathbb{F}_{256}\mid(s,k)\in\mathcal{P}\}$
- $\texttt{GetUserSlots}:\mathbb{F}_{160}\to\mathcal{P}(\mathbb{F}_{8})$
- $\texttt{GetUserSlots}(s):=\{u\in\mathbb{F}_{8}\mid(s,u)\in\mathcal{U}\}$
- $\texttt{GetFcnCfg}:\texttt{FcnSigns}\to\mathbb{F}_{256}\times\mathbb{F}_{256}$
- $\texttt{GetFcnCfg}(f):=(i,p)\ \text{where}\ (f,i,p)\in\mathcal{F}$

### Channel

#### Scope

- $\texttt{UserAddrs}\subseteq\mathbb{F}_{256}$
- $\texttt{AppFcnSigs}\subseteq\texttt{FcnSigns}$
- $\texttt{AppStorages}:=\bigcup_{f\in\texttt{AppFcnSigs}}\texttt{GetFcnStorages}(f)$

#### Relations

- $\widetilde{\mathcal{S}}:=\{(f,s)\mid f\in\texttt{AppFcnSigs}\ \wedge\ s\in\texttt{GetFcnStorages}(f)\}$
- $\widetilde{\mathcal{P}}:=\{(s,k)\mid s\in\texttt{AppStorages}\ \wedge\ k\in\texttt{GetPreAllocKeys}(s)\}$
- $\widetilde{\mathcal{U}}:=\{(s,u)\mid s\in\texttt{AppStorages}\ \wedge\ u\in\texttt{GetUserSlots}(s)\}$
- $\widetilde{\mathcal{F}}:=\{(f,i,p)\mid f\in\texttt{AppFcnSigs}\ \wedge\ \texttt{GetFcnCfg}(f)=(i,p)\}$
- $\mathcal{K}\subseteq\texttt{UserAddrs}\times\texttt{AppStorages}\times\mathbb{F}_{256}$
- $\mathcal{V}\subseteq\texttt{AppStorages}\times\mathbb{F}_{256}\times\mathbb{F}_{256}$

#### Constraints

- $\widetilde{\mathcal{S}}\subseteq\mathcal{S}$
- $\widetilde{\mathcal{P}}\subseteq\mathcal{P}$
- $\widetilde{\mathcal{U}}\subseteq\mathcal{U}$
- $\widetilde{\mathcal{F}}\subseteq\mathcal{F}$
- $\forall (u,s)\in\texttt{UserAddrs}\times\texttt{AppStorages},\ \exists!k\in\mathbb{F}_{256},\ (u,s,k)\in\mathcal{K}$
- $\forall s\in\texttt{AppStorages},\ \forall k\in\{k'\in\mathbb{F}_{256}\mid \exists u\in\texttt{UserAddrs},\ (u,s,k')\in\mathcal{K}\},\ \exists!v\in\mathbb{F}_{256},\ (s,k,v)\in\mathcal{V}$

#### Getters

- $\texttt{GetChannelStorages}:\texttt{AppFcnSigs}\to\mathcal{P}(\mathbb{F}_{160})$
- $\texttt{GetChannelStorages}(f):=\{s\in\mathbb{F}_{160}\mid(f,s)\in\widetilde{\mathcal{S}}\}$
- $\texttt{GetChannelPreAllocKeys}:\texttt{AppStorages}\to\mathcal{P}(\mathbb{F}_{256})$
- $\texttt{GetChannelPreAllocKeys}(s):=\{k\in\mathbb{F}_{256}\mid(s,k)\in\widetilde{\mathcal{P}}\}$
- $\texttt{GetChannelUserSlots}:\texttt{AppStorages}\to\mathcal{P}(\mathbb{F}_{8})$
- $\texttt{GetChannelUserSlots}(s):=\{u\in\mathbb{F}_{8}\mid(s,u)\in\widetilde{\mathcal{U}}\}$
- $\texttt{GetChannelFcnCfg}:\texttt{AppFcnSigs}\to\mathbb{F}_{256}\times\mathbb{F}_{256}$
- $\texttt{GetChannelFcnCfg}(f):=(i,p)\ \text{where}\ (f,i,p)\in\widetilde{\mathcal{F}}$
- $\texttt{GetChannelStorageKey}(u,s):=k\ \text{where}\ (u,s,k)\in\mathcal{K}$
- $\texttt{GetValidatedStorageValue}(s,k):=v\ \text{where}\ (s,k,v)\in\mathcal{V}$

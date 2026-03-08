# Tokamak Private App Channels - Bridge Contract

This document defines the minimal requirements needed to keep the bridge contract's storage structure secure. All mathematical constraints in this document can be converted into security guardrails, in the form of skills, so that any core update to the bridge contract can be safely performed by generative LLMs without security leakage.

Director: Jehyuk Jang, Ph.D

### Finite-Field notation

$\mathbb{F}_{b}$ is the field of $b$-bit words.

### Bridge Admin Manager

#### Variables

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
- $\mathrm{nTokamakPublicInputs}\in\mathbb{F}_{16}$
  - The length of public inputs required to verify a Tokamak zk-EVM proof
- $\mathrm{nMerkleTreeLevels}\in\mathbb{F}_{8}$
  - The number of levels for each channel Merkle tree
  - Each Merkle tree has $2^{\mathrm{nMerkleTreeLevels}}$ leaves

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

#### Variables

- $\mathrm{UserAddrs}\subseteq\mathbb{F}_{256}$
  - A set of user addresses registered in a channel
- $\mathrm{AppFcnSigs}\subseteq\mathrm{FcnSigns}$
  - A set of contract function signatures supported by a channel
- $\mathrm{AppStorageAddrs}:=\mathrm{getFcnStorages}[\mathrm{AppFcnSigs}]$
  - A set of storage addresses referenced by the functions in $\mathrm{AppFcnSigs}$
- $\mathrm{nAppStorages}\in\mathbb{F}_{16}$
  - The cardinality of $\mathrm{AppStorageAddrs}$
  - Cardinality: $\mathrm{nAppStorages}=\left|\mathrm{AppStorageAddrs}\right|$
- $\mathrm{AppPreAllocKeys}:=\mathrm{getPreAllocKeys}[\mathrm{AppStorageAddrs}]$
  - A set of pre-allocated keys associated with $\mathrm{AppStorageAddrs}$
- $\mathrm{AppUserStorageSlots}:=\mathrm{getUserSlots}[\mathrm{AppStorageAddrs}]$
  - A set of user storage slots associated with $\mathrm{AppStorageAddrs}$
- $\mathrm{AppFcnCfgs}:=\mathrm{getFcnCfg}[\mathrm{AppFcnSigs}]$
  - A set of function-configuration pairs of instance hash and preprocess hash referenced by the functions in $\mathrm{AppFcnSigs}$
- $\mathrm{UserChannelStorageKeys}\subseteq\mathbb{F}_{256}$
  - A set of channel storage access keys used by users, distinct from Ethereum storage access keys
- $\mathrm{ValidatedStorageValues}\subseteq\mathbb{F}_{256}$
  - A set of validated channel storage values associated with user accesses
- $\mathrm{PreAllocValues}\subseteq\mathbb{F}_{256}$
  - A set of fixed values assigned to pre-allocated keys in channel storage
- $\mathrm{StateIndices}\subseteq\mathbb{F}_{16}$
  - A unified set of state indices used for both verified and unverified channel states
- $\mathrm{ProposedStateRoots}\subseteq\mathbb{F}_{255}$
  - A set of proposed state roots
- $\mathrm{VerifiedStateRoots}\subseteq\mathbb{F}_{255}$
  - A set of verified state roots
  - Inclusion: $\mathrm{VerifiedStateRoots}\subseteq\mathrm{ProposedStateRoots}$
- $\mathrm{ForkIds}\subseteq\mathbb{F}_{8}$
  - A set of fork identifiers for unverified proposed state-root vectors

#### Relations

Given $\mathrm{AppFcnSigs}$, a channel derives the following projected relations:

- $\mathcal{S}:=\bigcup_{f\in\mathrm{AppFcnSigs}}\left(\{f\}\times\mathrm{getFcnStorages}(f)\right)$
  - Getter: $\mathrm{getAppFcnStorages}:\mathrm{AppFcnSigs}\to\mathcal{P}(\mathrm{AppStorageAddrs})$, where $\mathrm{getAppFcnStorages}(f):=\{s\in\mathrm{AppStorageAddrs}\mid(f,s)\in\mathcal{S}\}$
- $\mathcal{D}:=\bigcup_{s\in\mathrm{AppStorageAddrs}}\left(\{s\}\times\mathrm{getPreAllocKeys}(s)\right)$
  - Getter: $\mathrm{getAppPreAllocKeys}:\mathrm{AppStorageAddrs}\to\mathcal{P}(\mathrm{AppPreAllocKeys})$, where $\mathrm{getAppPreAllocKeys}(s):=\{k\in\mathrm{AppPreAllocKeys}\mid(s,k)\in\mathcal{D}\}$
- $\mathcal{U}:=\bigcup_{s\in\mathrm{AppStorageAddrs}}\left(\{s\}\times\mathrm{getUserSlots}(s)\right)$
  - Getter: $\mathrm{getAppUserSlots}:\mathrm{AppStorageAddrs}\to\mathcal{P}(\mathrm{AppUserStorageSlots})$, where $\mathrm{getAppUserSlots}(s):=\{u\in\mathrm{AppUserStorageSlots}\mid(s,u)\in\mathcal{U}\}$
- $\mathcal{F}:=\bigcup_{f\in\mathrm{AppFcnSigs}}\left(\{f\}\times\{\mathrm{getFcnCfg}(f)\}\right)$
  - Getter: $\mathrm{getAppFcnCfg}:\mathrm{AppFcnSigs}\to\mathrm{AppFcnCfgs}$, where $\mathrm{getAppFcnCfg}(f):=q\ \text{where}\ (f,q)\in\mathcal{F}$

Given $\mathrm{UserAddrs}$ and their channel storage access keys, a channel maintains and manages the following relations:

- $\mathcal{K}\subseteq\mathrm{UserAddrs}\times\mathrm{AppStorageAddrs}\times\mathrm{UserChannelStorageKeys}$
  - Uniqueness (without existence): $\forall u\in\mathrm{UserAddrs},\ \forall s\in\mathrm{AppStorageAddrs},\ \forall k_1,k_2\in\mathrm{UserChannelStorageKeys},\ ((u,s,k_1)\in\mathcal{K}\wedge(u,s,k_2)\in\mathcal{K})\Rightarrow k_1=k_2$
  - Conditional existence and uniqueness on validated values: $\forall s\in\mathrm{AppStorageAddrs},\ \forall k\in\mathrm{UserChannelStorageKeys},\ \forall v\in\mathrm{ValidatedStorageValues},\ \left((s,k,v)\in\mathcal{V}\Rightarrow \exists!u\in\mathrm{UserAddrs},\ (u,s,k)\in\mathcal{K}\right)$
  - Getter: $\mathrm{getAppUserStorageKey}:\mathrm{UserAddrs}\times\mathrm{AppStorageAddrs}\to\mathrm{UserChannelStorageKeys}$, where $\mathrm{getAppUserStorageKey}(u,s):=k\ \text{where}\ (u,s,k)\in\mathcal{K}$
- $\mathcal{V}\subseteq\mathrm{AppStorageAddrs}\times\mathrm{UserChannelStorageKeys}\times\mathrm{ValidatedStorageValues}$
  - Uniqueness (without existence): $\forall s\in\mathrm{AppStorageAddrs},\ \forall k\in\mathrm{UserChannelStorageKeys},\ \forall v_1,v_2\in\mathrm{ValidatedStorageValues},\ ((s,k,v_1)\in\mathcal{V}\wedge(s,k,v_2)\in\mathcal{V})\Rightarrow v_1=v_2$
  - Conditional existence and uniqueness on channel keys: $\forall s\in\mathrm{AppStorageAddrs},\ \forall k\in\mathrm{UserChannelStorageKeys},\ \left((\exists u\in\mathrm{UserAddrs},\ (u,s,k)\in\mathcal{K})\Rightarrow \exists!v\in\mathrm{ValidatedStorageValues},\ (s,k,v)\in\mathcal{V}\right)$
  - Setter-gated value update:
    $$
    \begin{aligned}
    &\forall s\in\mathrm{AppStorageAddrs},\ \forall k\in\mathrm{UserChannelStorageKeys},\ \forall \mathrm{updatedStorageValue}\in\mathbb{F}_{256},\\
    &\big((s,k,\mathrm{updatedStorageValue})\in\mathcal{V}\big)\Rightarrow\Big(\\
    &\qquad\exists \mathrm{leafIndex}\in\mathbb{F}_{16},\ \exists \mathrm{updatedRoot}\in\mathrm{VerifiedStateRoots},\ \exists \mathrm{proofGroth16}\in\mathbb{F}_{256}^{16},\ \exists \mathrm{publicInputGroth16}\in\mathbb{F}_{256}^{5},\\
    &\qquad\ \mathrm{updateSingleStateLeaf}(s,\mathrm{leafIndex},k,\mathrm{updatedStorageValue},\mathrm{updatedRoot},\mathrm{proofGroth16},\mathrm{publicInputGroth16})=\mathrm{true}\\
    &\qquad\vee\ \exists \mathrm{forkId}\in\mathrm{ForkIds},\ \exists \mathrm{unverifiedStateIndex}\in\mathrm{StateIndices},\ \exists \mathrm{appStorageAddrs}\in\mathrm{AppStorageAddrs}^{\mathrm{nAppStorages}},\ \exists \mathrm{userChannelStorageKeys}\in(\mathrm{UserChannelStorageKeys}^{(2^{\mathrm{nMerkleTreeLevels}})})^{\mathrm{nAppStorages}},\\
    &\qquad\ \exists \mathrm{updatedStorageValues}\in(\mathbb{F}_{256}^{(2^{\mathrm{nMerkleTreeLevels}})})^{\mathrm{nAppStorages}},\ \exists \mathrm{updatedRoots}\in\mathrm{ProposedStateRoots}^{\mathrm{nAppStorages}},\\
    &\qquad\ \exists \mathrm{proofTokamak}\in\mathbb{F}_{256}^{42},\ \exists \mathrm{preprocessTokamak}\in\mathbb{F}_{256}^{4},\ \exists \mathrm{publicInputTokamak}\in\mathbb{F}_{256}^{\mathrm{nTokamakPublicInputs}},\\
    &\qquad\ \mathrm{verifyUnverifiedStateRoots}(\mathrm{forkId},\mathrm{unverifiedStateIndex},\mathrm{appStorageAddrs},\mathrm{userChannelStorageKeys},\mathrm{updatedStorageValues},\mathrm{updatedRoots},\mathrm{proofTokamak},\mathrm{preprocessTokamak},\mathrm{publicInputTokamak})=\mathrm{true}
    \Big)
    \end{aligned}
    $$
  - Verified-commit synchronized update:
    $$
    \begin{aligned}
    &\forall \mathrm{forkId}\in\mathrm{ForkIds},\ \forall \mathrm{unverifiedStateIndex}\in\mathrm{StateIndices},\ \forall \mathrm{appStorageAddrs}\in\mathrm{AppStorageAddrs}^{\mathrm{nAppStorages}},\\
    &\forall \mathrm{userChannelStorageKeys}\in(\mathrm{UserChannelStorageKeys}^{(2^{\mathrm{nMerkleTreeLevels}})})^{\mathrm{nAppStorages}},\ \forall \mathrm{updatedStorageValues}\in(\mathbb{F}_{256}^{(2^{\mathrm{nMerkleTreeLevels}})})^{\mathrm{nAppStorages}},\\
    &\forall \mathrm{updatedRoots}\in\mathrm{ProposedStateRoots}^{\mathrm{nAppStorages}},\ \forall \mathrm{proofTokamak}\in\mathbb{F}_{256}^{42},\ \forall \mathrm{preprocessTokamak}\in\mathbb{F}_{256}^{4},\\
    &\forall \mathrm{publicInputTokamak}\in\mathbb{F}_{256}^{\mathrm{nTokamakPublicInputs}},\\
    &\mathrm{verifyUnverifiedStateRoots}(\mathrm{forkId},\mathrm{unverifiedStateIndex},\mathrm{appStorageAddrs},\mathrm{userChannelStorageKeys},\mathrm{updatedStorageValues},\mathrm{updatedRoots},\mathrm{proofTokamak},\mathrm{preprocessTokamak},\mathrm{publicInputTokamak})=\mathrm{true}\\
    &\Rightarrow \forall i\in\{0,\dots,\mathrm{nAppStorages}-1\},\ \forall j\in\{0,\dots,2^{\mathrm{nMerkleTreeLevels}}-1\},\ (\mathrm{appStorageAddrs}_i,\mathrm{userChannelStorageKeys}_{i,j},\mathrm{updatedStorageValues}_{i,j})\in\mathcal{V}\ \text{in the post-state}
    \end{aligned}
    $$
  - Getter: $\mathrm{getAppValidatedStorageValue}:\{(s,k)\in\mathrm{AppStorageAddrs}\times\mathrm{UserChannelStorageKeys}\mid \exists u\in\mathrm{UserAddrs},\ (u,s,k)\in\mathcal{K}\}\to\mathrm{ValidatedStorageValues}$, where $\mathrm{getAppValidatedStorageValue}(s,k):=v\ \text{where}\ (s,k,v)\in\mathcal{V}$
- $\mathcal{A}\subseteq\mathrm{AppStorageAddrs}\times\mathrm{AppPreAllocKeys}\times\mathrm{PreAllocValues}$
  - Uniqueness (without existence): $\forall s\in\mathrm{AppStorageAddrs},\ \forall k\in\mathrm{AppPreAllocKeys},\ \forall v_1,v_2\in\mathrm{PreAllocValues},\ ((s,k,v_1)\in\mathcal{A}\wedge(s,k,v_2)\in\mathcal{A})\Rightarrow v_1=v_2$
  - Conditional existence and uniqueness on app pre-allocated keys: $\forall (s,k)\in\mathcal{D},\ \exists!v\in\mathrm{PreAllocValues},\ (s,k,v)\in\mathcal{A}$
  - Getter: $\mathrm{getAppPreAllocValue}:\mathcal{D}\to\mathrm{PreAllocValues}$, where $\mathrm{getAppPreAllocValue}(s,k):=v\ \text{where}\ (s,k,v)\in\mathcal{A}$

Given state-machine indexing and verified/proposed state roots, a channel maintains and manages the following relations:

- $\mathcal{R}\subseteq\mathrm{StateIndices}\times\mathrm{AppStorageAddrs}\times\mathrm{VerifiedStateRoots}$
  - Existence and uniqueness per storage-index pair: $\forall t\in\mathrm{StateIndices},\ \forall s\in\mathrm{AppStorageAddrs},\ \exists!r\in\mathrm{VerifiedStateRoots},\ (t,s,r)\in\mathcal{R}$
  - Getter: $\mathrm{getLastVerifiedStateIndex}:\{\ast\}\to\mathrm{StateIndices}$, where $\mathrm{getLastVerifiedStateIndex}(\ast):=\max\{t\in\mathrm{StateIndices}\mid\exists s\in\mathrm{AppStorageAddrs},\ \exists r\in\mathrm{VerifiedStateRoots},\ (t,s,r)\in\mathcal{R}\}$
  - State transition by one-step index increment with root update: $\forall t\in\mathrm{StateIndices},\ \left(t<\mathrm{getLastVerifiedStateIndex}(\ast)\Rightarrow \exists s\in\mathrm{AppStorageAddrs},\ \exists r_t,r_{t+1}\in\mathrm{VerifiedStateRoots},\ (t,s,r_t)\in\mathcal{R}\wedge(t+1,s,r_{t+1})\in\mathcal{R}\wedge r_t\neq r_{t+1}\right)$
  - Setter-gated root update:
    $$
    \begin{aligned}
    &\forall s\in\mathrm{AppStorageAddrs},\ \forall \mathrm{updatedRoot}\in\mathrm{VerifiedStateRoots},\\
    &\Big((\mathrm{getLastVerifiedStateIndex}(\ast)+1,s,\mathrm{updatedRoot})\in\mathcal{R}\wedge\exists r_t\in\mathrm{VerifiedStateRoots},\ (\mathrm{getLastVerifiedStateIndex}(\ast),s,r_t)\in\mathcal{R}\wedge r_t\neq \mathrm{updatedRoot}\Big)\Rightarrow\Big(\\
    &\qquad\exists \mathrm{forkId}\in\mathrm{ForkIds},\ \exists \mathrm{unverifiedStateIndex}\in\mathrm{StateIndices},\ \exists \mathrm{appStorageAddrs}\in\mathrm{AppStorageAddrs}^{\mathrm{nAppStorages}},\ \exists \mathrm{userChannelStorageKeys}\in(\mathrm{UserChannelStorageKeys}^{(2^{\mathrm{nMerkleTreeLevels}})})^{\mathrm{nAppStorages}},\\
    &\qquad\ \exists \mathrm{updatedStorageValues}\in(\mathbb{F}_{256}^{(2^{\mathrm{nMerkleTreeLevels}})})^{\mathrm{nAppStorages}},\ \exists \mathrm{updatedRoots}\in\mathrm{ProposedStateRoots}^{\mathrm{nAppStorages}},\\
    &\qquad\ \exists \mathrm{proofTokamak}\in\mathbb{F}_{256}^{42},\ \exists \mathrm{preprocessTokamak}\in\mathbb{F}_{256}^{4},\ \exists \mathrm{publicInputTokamak}\in\mathbb{F}_{256}^{\mathrm{nTokamakPublicInputs}},\\
    &\qquad\ \mathrm{unverifiedStateIndex}=\mathrm{getLastVerifiedStateIndex}(\ast)+1\ \wedge\\
    &\qquad\ \mathrm{verifyUnverifiedStateRoots}(\mathrm{forkId},\mathrm{unverifiedStateIndex},\mathrm{appStorageAddrs},\mathrm{userChannelStorageKeys},\mathrm{updatedStorageValues},\mathrm{updatedRoots},\mathrm{proofTokamak},\mathrm{preprocessTokamak},\mathrm{publicInputTokamak})=\mathrm{true}
    \Big)
    \end{aligned}
    $$
  - Verified-commit insertion:
    $$
    \begin{aligned}
    &\forall \mathrm{forkId}\in\mathrm{ForkIds},\ \forall \mathrm{unverifiedStateIndex}\in\mathrm{StateIndices},\ \forall \mathrm{appStorageAddrs}\in\mathrm{AppStorageAddrs}^{\mathrm{nAppStorages}},\\
    &\forall \mathrm{userChannelStorageKeys}\in(\mathrm{UserChannelStorageKeys}^{(2^{\mathrm{nMerkleTreeLevels}})})^{\mathrm{nAppStorages}},\ \forall \mathrm{updatedStorageValues}\in(\mathbb{F}_{256}^{(2^{\mathrm{nMerkleTreeLevels}})})^{\mathrm{nAppStorages}},\\
    &\forall \mathrm{updatedRoots}\in\mathrm{ProposedStateRoots}^{\mathrm{nAppStorages}},\ \forall \mathrm{proofTokamak}\in\mathbb{F}_{256}^{42},\ \forall \mathrm{preprocessTokamak}\in\mathbb{F}_{256}^{4},\\
    &\forall \mathrm{publicInputTokamak}\in\mathbb{F}_{256}^{\mathrm{nTokamakPublicInputs}},\\
    &\mathrm{verifyUnverifiedStateRoots}(\mathrm{forkId},\mathrm{unverifiedStateIndex},\mathrm{appStorageAddrs},\mathrm{userChannelStorageKeys},\mathrm{updatedStorageValues},\mathrm{updatedRoots},\mathrm{proofTokamak},\mathrm{preprocessTokamak},\mathrm{publicInputTokamak})=\mathrm{true}\\
    &\Rightarrow \forall i\in\{0,\dots,\mathrm{nAppStorages}-1\},\ (\mathrm{unverifiedStateIndex},\mathrm{appStorageAddrs}_i,\mathrm{updatedRoots}_i)\in\mathcal{R}\ \text{in the post-state}
    \end{aligned}
    $$
  - State-index advancement on successful verified commit:
    $$
    \begin{aligned}
    &\forall \mathrm{forkId}\in\mathrm{ForkIds},\ \forall \mathrm{unverifiedStateIndex}\in\mathrm{StateIndices},\ \forall \mathrm{appStorageAddrs}\in\mathrm{AppStorageAddrs}^{\mathrm{nAppStorages}},\\
    &\forall \mathrm{userChannelStorageKeys}\in(\mathrm{UserChannelStorageKeys}^{(2^{\mathrm{nMerkleTreeLevels}})})^{\mathrm{nAppStorages}},\ \forall \mathrm{updatedStorageValues}\in(\mathbb{F}_{256}^{(2^{\mathrm{nMerkleTreeLevels}})})^{\mathrm{nAppStorages}},\\
    &\forall \mathrm{updatedRoots}\in\mathrm{ProposedStateRoots}^{\mathrm{nAppStorages}},\ \forall \mathrm{proofTokamak}\in\mathbb{F}_{256}^{42},\ \forall \mathrm{preprocessTokamak}\in\mathbb{F}_{256}^{4},\\
    &\forall \mathrm{publicInputTokamak}\in\mathbb{F}_{256}^{\mathrm{nTokamakPublicInputs}},\\
    &\mathrm{verifyUnverifiedStateRoots}(\mathrm{forkId},\mathrm{unverifiedStateIndex},\mathrm{appStorageAddrs},\mathrm{userChannelStorageKeys},\mathrm{updatedStorageValues},\mathrm{updatedRoots},\mathrm{proofTokamak},\mathrm{preprocessTokamak},\mathrm{publicInputTokamak})=\mathrm{true}\\
    &\Rightarrow \left(\mathrm{unverifiedStateIndex}\in\mathrm{StateIndices}\ \wedge\ \mathrm{getLastVerifiedStateIndex}(\ast)=\mathrm{unverifiedStateIndex}\right)\ \text{in the post-state}
    \end{aligned}
    $$
  - Getter: $\mathrm{getVerifiedStateRoot}:\mathrm{AppStorageAddrs}\times\mathrm{StateIndices}\to\mathrm{VerifiedStateRoots}$, where $\mathrm{getVerifiedStateRoot}(s,t):=r\ \text{where}\ (t,s,r)\in\mathcal{R}$
- $\mathcal{N}\subseteq\mathrm{ForkIds}\times\mathrm{StateIndices}\times\mathrm{AppStorageAddrs}\times\mathrm{ProposedStateRoots}$
  - Uniqueness per state-fork-storage triple (without existence): $\forall t\in\mathrm{StateIndices},\ \forall f\in\mathrm{ForkIds},\ \forall s\in\mathrm{AppStorageAddrs},\ \forall r_1,r_2\in\mathrm{ProposedStateRoots},\ ((f,t,s,r_1)\in\mathcal{N}\wedge(f,t,s,r_2)\in\mathcal{N})\Rightarrow r_1=r_2$
  - Vector-wise completeness per state-fork pair: $\forall t\in\mathrm{StateIndices},\ \forall f\in\mathrm{ForkIds},\ \left(\left(\exists s\in\mathrm{AppStorageAddrs},\ \exists r\in\mathrm{ProposedStateRoots},\ (f,t,s,r)\in\mathcal{N}\right)\Rightarrow\left(\forall s^\prime\in\mathrm{AppStorageAddrs},\ \exists r^\prime\in\mathrm{ProposedStateRoots},\ (f,t,s^\prime,r^\prime)\in\mathcal{N}\right)\right)$
  - Getter: $\mathrm{getProposedStateRoot}:\mathrm{ForkIds}\times\mathrm{AppStorageAddrs}\times\mathrm{StateIndices}\to\mathrm{ProposedStateRoots}$, where $\mathrm{getProposedStateRoot}(f,s,t):=r\ \text{where}\ (f,t,s,r)\in\mathcal{N}$
  - Getter: $\mathrm{getProposedStateFork}:\mathrm{ForkIds}\to\mathcal{P}(\mathrm{StateIndices}\times\mathrm{AppStorageAddrs}\times\mathrm{ProposedStateRoots})$, where $\mathrm{getProposedStateFork}(f):=\{(t,s,r)\in\mathrm{StateIndices}\times\mathrm{AppStorageAddrs}\times\mathrm{ProposedStateRoots}\mid(f,t,s,r)\in\mathcal{N}\}$

#### Setter functions

- $\mathrm{updateSingleStateLeaf}:\mathrm{AppStorageAddrs}\times\mathbb{F}_{16}\times\mathrm{UserChannelStorageKeys}\times\mathbb{F}_{256}\times\mathbb{F}_{255}\times\mathbb{F}_{256}^{16}\times\mathbb{F}_{256}^{5}\to\{\mathrm{true},\mathrm{false}\}$
  - Inputs:
    - $\mathrm{appStorageAddr}\in\mathrm{AppStorageAddrs}$
    - $\mathrm{leafIndex}\in\mathbb{F}_{16}$
    - $\mathrm{userChannelStorageKey}\in\mathrm{UserChannelStorageKeys}$
    - $\mathrm{updatedStorageValue}\in\mathbb{F}_{256}$
    - $\mathrm{updatedRoot}\in\mathbb{F}_{255}$
    - $\mathrm{proofGroth16}\in\mathbb{F}_{256}^{16}$
    - $\mathrm{publicInputGroth16}\in\mathbb{F}_{256}^{5}$
  - Output: $\mathrm{true}$ or $\mathrm{false}$
- $\mathrm{verifyUnverifiedStateRoots}:\mathrm{ForkIds}\times\mathrm{StateIndices}\times\mathrm{AppStorageAddrs}^{\mathrm{nAppStorages}}\times(\mathrm{UserChannelStorageKeys}^{(2^{\mathrm{nMerkleTreeLevels}})})^{\mathrm{nAppStorages}}\times(\mathbb{F}_{256}^{(2^{\mathrm{nMerkleTreeLevels}})})^{\mathrm{nAppStorages}}\times\mathrm{ProposedStateRoots}^{\mathrm{nAppStorages}}\times\mathbb{F}_{256}^{42}\times\mathbb{F}_{256}^{4}\times\mathbb{F}_{256}^{\mathrm{nTokamakPublicInputs}}\to\{\mathrm{true},\mathrm{false}\}$
  - Inputs:
    - $\mathrm{forkId}\in\mathrm{ForkIds}$
    - $\mathrm{unverifiedStateIndex}\in\mathrm{StateIndices}$
    - $\mathrm{appStorageAddrs}\in\mathrm{AppStorageAddrs}^{\mathrm{nAppStorages}}$
    - $\mathrm{userChannelStorageKeys}\in(\mathrm{UserChannelStorageKeys}^{(2^{\mathrm{nMerkleTreeLevels}})})^{\mathrm{nAppStorages}}$
    - $\mathrm{updatedStorageValues}\in(\mathbb{F}_{256}^{(2^{\mathrm{nMerkleTreeLevels}})})^{\mathrm{nAppStorages}}$
    - $\mathrm{updatedRoots}\in\mathrm{ProposedStateRoots}^{\mathrm{nAppStorages}}$
    - $\mathrm{proofTokamak}\in\mathbb{F}_{256}^{42}$
    - $\mathrm{preprocessTokamak}\in\mathbb{F}_{256}^{4}$
    - $\mathrm{publicInputTokamak}\in\mathbb{F}_{256}^{\mathrm{nTokamakPublicInputs}}$
  - Constraints:
    - Immediate-next-index constraint: $\mathrm{unverifiedStateIndex}=\mathrm{getLastVerifiedStateIndex}(\ast)+1$
    - Membership in selected fork of $\mathcal{N}$: $\forall i\in\{0,\dots,\mathrm{nAppStorages}-1\},\ (\mathrm{forkId},\mathrm{unverifiedStateIndex},\mathrm{appStorageAddrs}_i,\mathrm{updatedRoots}_i)\in\mathcal{N}$
  - Output: $\mathrm{true}$ or $\mathrm{false}$


### Bridge Core

#### Variables

- $\mathrm{ChannelIds}\subseteq\mathbb{F}_{256}$
  - A set of registered channel IDs
- For each $c\in\mathrm{ChannelIds}$, let $X_c$ denote one channel instance satisfying the Channel section:

$$
\begin{aligned}
X_c:=(&\mathrm{UserAddrs}_c,\mathrm{AppFcnSigs}_c,\mathrm{AppStorageAddrs}_c,\mathrm{nAppStorages}_c,\mathrm{AppPreAllocKeys}_c,\mathrm{AppUserStorageSlots}_c,\\
     &\mathrm{AppFcnCfgs}_c,\mathrm{UserChannelStorageKeys}_c,\mathrm{ValidatedStorageValues}_c,\mathrm{PreAllocValues}_c,\\
     &\mathrm{StateIndices}_c,\mathrm{ProposedStateRoots}_c,\mathrm{VerifiedStateRoots}_c,\mathrm{ForkIds}_c,\\
     &\mathcal{S}_c,\mathcal{D}_c,\mathcal{U}_c,\mathcal{F}_c,\mathcal{K}_c,\mathcal{V}_c,\mathcal{A}_c,\mathcal{R}_c,\mathcal{N}_c)
\end{aligned}
$$

#### Relations

Given $\mathrm{ChannelIds}$ and channel instances $\{X_c\}_{c\in\mathrm{ChannelIds}}$, the core relations are lifted from channel relations:

- $\widetilde{\mathcal{M}}:=\bigcup_{c\in\mathrm{ChannelIds}}\left(\{c\}\times\mathrm{UserAddrs}_c\right)$
  - Getter: $\mathrm{getChannelUsers}:\mathrm{ChannelIds}\to\mathcal{P}(\mathrm{UserAddrs}_c)$, where $\mathrm{getChannelUsers}(c):=\{u\in\mathrm{UserAddrs}_c\mid(c,u)\in\widetilde{\mathcal{M}}\}$
- $\widetilde{\mathcal{S}}:=\bigcup_{c\in\mathrm{ChannelIds}}\left(\{c\}\times\mathcal{S}_c\right)$
  - Getter: $\mathrm{getChannelFcnStorages}:\{(c,f)\mid c\in\mathrm{ChannelIds}\ \wedge\ f\in\mathrm{AppFcnSigs}_c\}\to\mathcal{P}(\mathrm{AppStorageAddrs}_c)$, where $\mathrm{getChannelFcnStorages}(c,f):=\mathrm{getAppFcnStorages}_c(f)$
- $\widetilde{\mathcal{D}}:=\bigcup_{c\in\mathrm{ChannelIds}}\left(\{c\}\times\mathcal{D}_c\right)$
  - Getter: $\mathrm{getChannelPreAllocKeys}:\{(c,s)\mid c\in\mathrm{ChannelIds}\ \wedge\ s\in\mathrm{AppStorageAddrs}_c\}\to\mathcal{P}(\mathrm{AppPreAllocKeys}_c)$, where $\mathrm{getChannelPreAllocKeys}(c,s):=\mathrm{getAppPreAllocKeys}_c(s)$
- $\widetilde{\mathcal{U}}:=\bigcup_{c\in\mathrm{ChannelIds}}\left(\{c\}\times\mathcal{U}_c\right)$
  - Getter: $\mathrm{getChannelUserSlots}:\{(c,s)\mid c\in\mathrm{ChannelIds}\ \wedge\ s\in\mathrm{AppStorageAddrs}_c\}\to\mathcal{P}(\mathrm{AppUserStorageSlots}_c)$, where $\mathrm{getChannelUserSlots}(c,s):=\mathrm{getAppUserSlots}_c(s)$
- $\widetilde{\mathcal{F}}:=\bigcup_{c\in\mathrm{ChannelIds}}\left(\{c\}\times\mathcal{F}_c\right)$
  - Getter: $\mathrm{getChannelFcnCfg}:\{(c,f)\mid c\in\mathrm{ChannelIds}\ \wedge\ f\in\mathrm{AppFcnSigs}_c\}\to\mathrm{AppFcnCfgs}_c$, where $\mathrm{getChannelFcnCfg}(c,f):=\mathrm{getAppFcnCfg}_c(f)$
- $\widetilde{\mathcal{K}}:=\bigcup_{c\in\mathrm{ChannelIds}}\left(\{c\}\times\mathcal{K}_c\right)$
  - Getter: $\mathrm{getChannelUserStorageKey}:\{(c,u,s)\mid c\in\mathrm{ChannelIds}\ \wedge\ (c,u)\in\widetilde{\mathcal{M}}\ \wedge\ s\in\mathrm{AppStorageAddrs}_c\}\to\mathrm{UserChannelStorageKeys}_c$, where $\mathrm{getChannelUserStorageKey}(c,u,s):=\mathrm{getAppUserStorageKey}_c(u,s)$
- $\widetilde{\mathcal{V}}:=\bigcup_{c\in\mathrm{ChannelIds}}\left(\{c\}\times\mathcal{V}_c\right)$
  - Getter: $\mathrm{getChannelValidatedStorageValue}:\{(c,s,k)\mid c\in\mathrm{ChannelIds}\ \wedge\ s\in\mathrm{AppStorageAddrs}_c\ \wedge\ k\in\mathrm{UserChannelStorageKeys}_c\ \wedge\ \exists u\in\mathrm{UserAddrs}_c,\ (c,u,s,k)\in\widetilde{\mathcal{K}}\}\to\mathrm{ValidatedStorageValues}_c$, where $\mathrm{getChannelValidatedStorageValue}(c,s,k):=\mathrm{getAppValidatedStorageValue}_c(s,k)$
- $\widetilde{\mathcal{A}}:=\bigcup_{c\in\mathrm{ChannelIds}}\left(\{c\}\times\mathcal{A}_c\right)$
  - Getter: $\mathrm{getChannelPreAllocValue}:\{(c,s,k)\mid c\in\mathrm{ChannelIds}\ \wedge\ (s,k)\in\mathcal{D}_c\}\to\mathrm{PreAllocValues}_c$, where $\mathrm{getChannelPreAllocValue}(c,s,k):=\mathrm{getAppPreAllocValue}_c(s,k)$
- $\widetilde{\mathcal{R}}:=\bigcup_{c\in\mathrm{ChannelIds}}\left(\{c\}\times\mathcal{R}_c\right)$
  - Getter: $\mathrm{getChannelVerifiedStateRoot}:\{(c,s,t)\mid c\in\mathrm{ChannelIds}\ \wedge\ s\in\mathrm{AppStorageAddrs}_c\ \wedge\ t\in\mathrm{StateIndices}_c\}\to\mathrm{VerifiedStateRoots}_c$, where $\mathrm{getChannelVerifiedStateRoot}(c,s,t):=\mathrm{getVerifiedStateRoot}_c(s,t)$
- $\widetilde{\mathcal{N}}:=\bigcup_{c\in\mathrm{ChannelIds}}\left(\{c\}\times\mathcal{N}_c\right)$
  - Getter: $\mathrm{getChannelUnverifiedStateRoot}:\{(c,f,s,t)\mid c\in\mathrm{ChannelIds}\ \wedge\ f\in\mathrm{ForkIds}_c\ \wedge\ s\in\mathrm{AppStorageAddrs}_c\ \wedge\ t\in\mathrm{StateIndices}_c\}\to\mathrm{ProposedStateRoots}_c$, where $\mathrm{getChannelUnverifiedStateRoot}(c,f,s,t):=\mathrm{getProposedStateRoot}_c(f,s,t)$
  - Getter: $\mathrm{getChannelUnverifiedForks}:\{(c,f)\mid c\in\mathrm{ChannelIds}\ \wedge\ f\in\mathrm{ForkIds}_c\}\to\mathcal{P}(\mathrm{StateIndices}_c\times\mathrm{AppStorageAddrs}_c\times\mathrm{ProposedStateRoots}_c)$, where $\mathrm{getChannelUnverifiedForks}(c,f):=\mathrm{getProposedStateFork}_c(f)$

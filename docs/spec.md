# Tokamak Private App Channels - Bridge Contract

This document defines the minimal mathematical constraints needed to keep the bridge
contract secure.

Director: Jehyuk Jang, Ph.D

### Finite-Field notation

\[
\mathbb{F}_{b} := \{0,1\}^{b}.
\]

\[
\mathbb{F}_{\mathrm{BLS}} := \{0,\dots,r-1\},
\]

where \(r\) is the scalar-field modulus of the Groth16 circuit currently used by the
bridge.

### Global constants

\[
\mathrm{MTDepth}=12,\qquad
\mathrm{MaxMTLeaves}=2^{\mathrm{MTDepth}}=4096,\qquad
\mathrm{MaxDAppStorages}=11.
\]

### Bridge Admin Manager

#### Variables

- \(\mathrm{MerkleTreeLevels}\subseteq\mathbb{F}_{8}\)
- \(\mathrm{AllowedMerkleTreeLevels}:=\{12\}\)

#### Relations

- Supported-level constraint:
  \[
  \mathrm{MerkleTreeLevels}\subseteq \mathrm{AllowedMerkleTreeLevels}.
  \]

- Exact-level constraint:
  \[
  \forall \ell\in\mathrm{MerkleTreeLevels},\ \ell=\mathrm{MTDepth}.
  \]

### DApp Manager

#### Variables

- \(\mathrm{DAppIds}\subseteq\mathbb{F}_{256}\)
- \(\mathrm{EntryContracts}\subseteq\mathbb{F}_{160}\)
- \(\mathrm{FcnSigns}\subseteq\mathbb{F}_{32}\)
- \(\mathrm{FcnIds}:=\mathrm{EntryContracts}\times\mathrm{FcnSigns}\)
- \(\mathrm{StorageAddrs}\subseteq\mathbb{F}_{160}\)
- \(\mathrm{PreAllocKeys}\subseteq\mathbb{F}_{256}\)
- \(\mathrm{UserStorageSlots}\subseteq\mathbb{F}_{8}\)
- \(\mathrm{PreprocessHashes}\subseteq\mathbb{F}_{256}\setminus\{0\}\)
- \(\mathrm{WordOffsets}\subseteq\mathbb{F}_{8}\)
- \(\mathrm{StorageAddrIndices}\subseteq\mathbb{F}_{8}\)

- \(\mathrm{StorageWriteMeta}:=\mathrm{WordOffsets}\times\mathrm{StorageAddrIndices}\)
- \(\mathrm{InstanceLayouts}:=\mathrm{WordOffsets}^{4}\times(\mathrm{StorageWriteMeta})^{*}\)

- \(\mathrm{DAppStorageVectors}\subseteq(\mathrm{StorageAddrs})^{\le \mathrm{MaxDAppStorages}}\)
- \(\mathrm{TokenVaultPositions}\subseteq\mathbb{F}_{8}\)

#### Relations

- DApp storage-vector relation:
  \[
  \mathcal{S}_D\subseteq \mathrm{DAppIds}\times \mathrm{DAppStorageVectors}.
  \]

- DApp token-vault-position relation:
  \[
  \mathcal{T}_D\subseteq \mathrm{DAppIds}\times \mathrm{TokenVaultPositions}.
  \]

- DApp function relation:
  \[
  \mathcal{F}_D\subseteq \mathrm{DAppIds}\times \mathrm{FcnIds}\times \mathrm{PreprocessHashes}\times \mathrm{InstanceLayouts}.
  \]

- DApp pre-allocated-key relation:
  \[
  \mathcal{P}_D\subseteq \mathrm{DAppIds}\times \mathrm{StorageAddrs}\times \mathrm{PreAllocKeys}.
  \]

- DApp user-slot relation:
  \[
  \mathcal{U}_D\subseteq \mathrm{DAppIds}\times \mathrm{StorageAddrs}\times \mathrm{UserStorageSlots}.
  \]

#### Constraints

- DApp existence and uniqueness:
  \[
  \forall d\in\mathrm{DAppIds},\ \exists! S\in\mathrm{DAppStorageVectors},\ (d,S)\in\mathcal{S}_D.
  \]

- Storage-vector cardinality:
  \[
  \forall (d,S)\in\mathcal{S}_D,\ 1\le |S|\le \mathrm{MaxDAppStorages}.
  \]

- Distinct storage-address constraint:
  \[
  \forall (d,S)\in\mathcal{S}_D,\ \forall i,j\in\{0,\dots,|S|-1\},\ i\neq j \Rightarrow S_i\neq S_j.
  \]

- Token-vault existence and uniqueness:
  \[
  \forall d\in\mathrm{DAppIds},\ \exists! t\in\{0,\dots,|S_d|-1\},\ (d,t)\in\mathcal{T}_D,
  \]
  where \(S_d\) is the unique storage vector satisfying \((d,S_d)\in\mathcal{S}_D\).

- Function existence:
  \[
  \forall d\in\mathrm{DAppIds},\ \exists (f,p,L)\ \text{s.t.}\ (d,f,p,L)\in\mathcal{F}_D.
  \]

- Function uniqueness inside one DApp:
  \[
  \forall d\in\mathrm{DAppIds},\ \forall f\in\mathrm{FcnIds},\ \forall p_1,p_2\in\mathrm{PreprocessHashes},\ \forall L_1,L_2\in\mathrm{InstanceLayouts},
  \]
  \[
  (d,f,p_1,L_1)\in\mathcal{F}_D\wedge(d,f,p_2,L_2)\in\mathcal{F}_D \Rightarrow (p_1,L_1)=(p_2,L_2).
  \]

- Preprocess-hash uniqueness inside one DApp:
  \[
  \forall d\in\mathrm{DAppIds},\ \forall f_1,f_2\in\mathrm{FcnIds},\ \forall p\in\mathrm{PreprocessHashes},\ \forall L_1,L_2\in\mathrm{InstanceLayouts},
  \]
  \[
  (d,f_1,p,L_1)\in\mathcal{F}_D\wedge(d,f_2,p,L_2)\in\mathcal{F}_D \Rightarrow f_1=f_2.
  \]

- Storage-write-index validity:
  letting \(L=(o_e,o_s,o_c,o_u,W)\),
  \[
  \forall (d,f,p,L)\in\mathcal{F}_D,\ \forall (o,a)\in W,\ a<|S_d|.
  \]

### Bridge Core

#### Variables

- \(\mathrm{ChannelIds}\subseteq\mathbb{F}_{256}\)
- \(\mathrm{Leaders}\subseteq\mathbb{F}_{160}\setminus\{0\}\)
- \(\mathrm{Assets}\subseteq\mathbb{F}_{160}\setminus\{0\}\)
- \(\mathrm{BlockHashes}\subseteq\mathbb{F}_{256}\setminus\{0\}\)
- \(\mathrm{ChannelManagers}\subseteq\mathbb{F}_{160}\)
- \(\mathrm{TokenVaults}\subseteq\mathbb{F}_{160}\)
- \(\mathrm{VaultKeys}\subseteq\mathbb{F}_{256}\)
- \(\mathrm{LeafIndices}:=\{0,\dots,\mathrm{MaxMTLeaves}-1\}\)

#### Relations

- Channel deployment relation:
  \[
  \mathcal{C}\subseteq
  \mathrm{ChannelIds}\times
  \mathrm{DAppIds}\times
  \mathrm{Leaders}\times
  \mathrm{Assets}\times
  \mathrm{ChannelManagers}\times
  \mathrm{TokenVaults}\times
  \mathrm{BlockHashes}.
  \]

- Global vault-key reservation relation:
  \[
  \mathcal{K}_G\subseteq \mathrm{VaultKeys}.
  \]

- Channel leaf-owner relation:
  \[
  \mathcal{L}_C\subseteq \mathrm{ChannelIds}\times \mathrm{LeafIndices}\times \mathbb{F}_{160}.
  \]

#### Constraints

- Channel uniqueness:
  \[
  \forall c\in\mathrm{ChannelIds},\ \exists! (d,\ell,a,m,v,b)\ \text{s.t.}\ (c,d,\ell,a,m,v,b)\in\mathcal{C}.
  \]

- DApp existence at creation:
  \[
  \forall (c,d,\ell,a,m,v,b)\in\mathcal{C},\ d\in\mathrm{DAppIds}.
  \]

- Merkle-tree admissibility at creation:
  \[
  \forall (c,d,\ell,a,m,v,b)\in\mathcal{C},\ \mathrm{MerkleTreeLevels}=\{12\}.
  \]

- Global vault-key uniqueness:
  \[
  \forall k_1,k_2\in\mathcal{K}_G,\ k_1=k_2 \Rightarrow k_1 \text{ and } k_2 \text{ denote the same reserved key}.
  \]

- Per-channel leaf-index uniqueness:
  \[
  \forall c\in\mathrm{ChannelIds},\ \forall i\in\mathrm{LeafIndices},\ \forall u_1,u_2\in\mathbb{F}_{160},
  \]
  \[
  (c,i,u_1)\in\mathcal{L}_C\wedge(c,i,u_2)\in\mathcal{L}_C \Rightarrow u_1=u_2.
  \]

- Leaf-index derivation:
  \[
  \mathrm{LeafIndex}(k):=k\bmod \mathrm{MaxMTLeaves}.
  \]

### Channel

#### Variables

- \(\mathrm{CurrentRootVectorHashes}\subseteq\mathbb{F}_{256}\)
- \(\mathrm{RootVectors}:=\bigcup_{d\in\mathrm{DAppIds}} R^{|S_d|}\)
- \(\mathrm{GenesisBlocks}\subseteq\mathbb{F}_{256}\)
- \(\mathrm{TokenVaultLeafValues}\subseteq\mathbb{F}_{256}\)

- For each \(c\in\mathrm{ChannelIds}\), define
  \[
  d(c),\quad S_c:=S_{d(c)},\quad tv(c):=t_{d(c)},
  \]
  where \((d(c),S_{d(c)})\in\mathcal{S}_D\) and \((d(c),t_{d(c)})\in\mathcal{T}_D\).

#### Relations

- Channel-state-commitment relation:
  \[
  \mathcal{H}\subseteq \mathrm{ChannelIds}\times \mathrm{CurrentRootVectorHashes}.
  \]

- Channel genesis-block relation:
  \[
  \mathcal{G}_B\subseteq \mathrm{ChannelIds}\times \mathrm{GenesisBlocks}.
  \]

- Latest token-vault-leaf relation:
  \[
  \mathcal{V}_T\subseteq \mathrm{ChannelIds}\times \mathrm{LeafIndices}\times \mathrm{TokenVaultLeafValues}.
  \]

- Allowed-function relation:
  \[
  \mathcal{F}_C\subseteq \mathrm{ChannelIds}\times \mathrm{FcnIds}\times \mathrm{PreprocessHashes}\times \mathrm{InstanceLayouts}.
  \]

#### Constraints

- State-commitment uniqueness:
  \[
  \forall c\in\mathrm{ChannelIds},\ \exists! h\in\mathrm{CurrentRootVectorHashes},\ (c,h)\in\mathcal{H}.
  \]

- Channel/DApp inheritance:
  \[
  \forall c\in\mathrm{ChannelIds},\ \forall (f,p,L),\ (c,f,p,L)\in\mathcal{F}_C \Leftrightarrow (d(c),f,p,L)\in\mathcal{F}_D.
  \]

- Root-vector arity:
  \[
  \forall c\in\mathrm{ChannelIds},\ \forall \rho\in\mathrm{RootVectors}\ \text{admissible for } c,\ |\rho|=|S_c|.
  \]

- Token-vault-position constancy:
  \[
  \forall c\in\mathrm{ChannelIds},\ tv(c)\in\{0,\dots,|S_c|-1\}
  \]
  and \(tv(c)\) is fixed for the lifetime of \(c\).

- Genesis commitment:
  \[
  \forall c\in\mathrm{ChannelIds},\ \exists g_c\in R^{|S_c|},\ Hash(g_c)=h_c,
  \]
  where \((c,h_c)\in\mathcal{H}\) immediately after creation.

#### Proof-gated transition constraints

- Groth-only token-vault root replacement:
  \[
  \forall c\in\mathrm{ChannelIds},\ \forall \rho,\rho'\in R^{|S_c|},
  \]
  \[
  \Big(\rho_i=\rho'_i\ \forall i\neq tv(c)\ \wedge\ \rho_{tv(c)}\neq\rho'_{tv(c)}\Big)
  \]
  may be accepted only through the Groth update path or the Tokamak execution path with
  an explicit token-vault storage write.

- No non-proof root transition after genesis:
  \[
  \forall c\in\mathrm{ChannelIds},\ \forall h,h'\in\mathrm{CurrentRootVectorHashes},
  \]
  \[
  (c,h)\in\mathcal{H}\wedge(c,h')\in\mathcal{H}\wedge h\neq h'
  \Rightarrow
  \]
  \[
  \exists \rho,\rho'\in R^{|S_c|}\ \text{s.t.}\ h=Hash(\rho),\ h'=Hash(\rho')
  \]
  and the transition \(\rho\to\rho'\) was accepted by a valid proof-backed path.

### L1 Token Vault

#### Variables

- \(\mathrm{Registrations}\subseteq \mathrm{ChannelIds}\times \mathbb{F}_{160}\times \mathrm{VaultKeys}\times \mathrm{LeafIndices}\times \mathbb{N}\)
- \(\mathrm{GrothProofs}\subseteq\mathbb{F}_{256}^{16}\)
- \(\mathrm{GrothPublicInputs}\subseteq \mathbb{F}_{256}^{5}\)

#### Constraints

- Registration uniqueness per user:
  \[
  \forall c\in\mathrm{ChannelIds},\ \forall u\in\mathbb{F}_{160},\ \forall k_1,k_2\in\mathrm{VaultKeys},\ \forall i_1,i_2\in\mathrm{LeafIndices},\ \forall b_1,b_2\in\mathbb{N},
  \]
  \[
  (c,u,k_1,i_1,b_1)\in\mathrm{Registrations}\wedge(c,u,k_2,i_2,b_2)\in\mathrm{Registrations}
  \Rightarrow
  (k_1,i_1)=(k_2,i_2).
  \]

- Registration key uniqueness across the whole system:
  \[
  \forall c_1,c_2\in\mathrm{ChannelIds},\ \forall u_1,u_2\in\mathbb{F}_{160},\ \forall k\in\mathrm{VaultKeys},\ \forall i_1,i_2\in\mathrm{LeafIndices},\ \forall b_1,b_2\in\mathbb{N},
  \]
  \[
  (c_1,u_1,k,i_1,b_1)\in\mathrm{Registrations}\wedge(c_2,u_2,k,i_2,b_2)\in\mathrm{Registrations}
  \Rightarrow
  (c_1,u_1)=(c_2,u_2).
  \]

- Registration leaf-index uniqueness inside one channel:
  \[
  \forall c\in\mathrm{ChannelIds},\ \forall u_1,u_2\in\mathbb{F}_{160},\ \forall k_1,k_2\in\mathrm{VaultKeys},\ \forall i\in\mathrm{LeafIndices},\ \forall b_1,b_2\in\mathbb{N},
  \]
  \[
  (c,u_1,k_1,i,b_1)\in\mathrm{Registrations}\wedge(c,u_2,k_2,i,b_2)\in\mathrm{Registrations}
  \Rightarrow
  u_1=u_2.
  \]

- Positive-funding constraint:
  \[
  \forall (c,u,k,i,b)\in\mathrm{Registrations},\ b>0.
  \]

- Exact-transfer asset assumption:
  for every accepted transfer amount \(a>0\),
  \[
  \Delta_{\mathrm{vault}}=a\quad\text{and}\quad \Delta_{\mathrm{recipient}}=a.
  \]

- Unsupported-asset exclusion:
  any asset violating the exact-transfer assumption is inadmissible.

#### Groth setter constraint

Let \(\rho,\rho'\in R^{|S_c|}\). A Groth transition for user \(u\) in channel \(c\) is
admissible only if:

\[
Hash(\rho)=h_c,\qquad
\rho_i=\rho'_i\ \forall i\neq tv(c),
\]
\[
\mathrm{currentUserKey}=\mathrm{updatedUserKey}=k_{c,u},
\]
\[
\mathrm{currentUserValue},\mathrm{updatedUserValue}\in\mathbb{F}_{\mathrm{BLS}},
\]

and:

- deposit case:
  \[
  \mathrm{updatedUserValue}>\mathrm{currentUserValue}
  \]
  \[
  bal(c,u)\ge \mathrm{updatedUserValue}-\mathrm{currentUserValue}
  \]

- withdrawal case:
  \[
  \mathrm{currentUserValue}>\mathrm{updatedUserValue}.
  \]

After acceptance:

\[
h_c:=Hash(\rho'),
\]

and the L1 available balance is adjusted by the proved difference.

### Tokamak Execution

#### Variables

- \(\mathrm{TokamakProofs}\subseteq \mathbb{F}_{256}^{*}\)
- \(\mathrm{APubUser}\subseteq \mathbb{F}_{256}^{*}\)
- \(\mathrm{APubBlock}\subseteq \mathbb{F}_{256}^{*}\)

#### Setter constraint

Let \(c\in\mathrm{ChannelIds}\), let \((f,p,L)\in\mathcal{F}_C\), and let
\(\rho,\rho'\in R^{|S_c|}\) be the pre-state and post-state root vectors decoded from
the Tokamak public input under \(L\).

The Tokamak transition is admissible only if:

\[
Hash(\rho)=h_c,
\]
\[
\mathrm{Hash}(\mathrm{submitted\ preprocess})=p,
\]
\[
\mathrm{Hash}(\mathrm{submitted\ block\ context})=b(c),
\]
\[
\mathrm{decodedFunctionId}=f,
\]
\[
\mathrm{declaredWrites}\ \text{are compatible with}\ W(f),
\]
\[
\mathrm{TokamakVerify}(\mathrm{proof},\mathrm{preprocess},\mathrm{aPubUser},\mathrm{aPubBlock})=\mathrm{true}.
\]

If
\[
\rho'_{tv(c)}\neq \rho_{tv(c)},
\]
then admissibility further requires
\[
\exists w\in W(f)\ \text{s.t.}\ w\ \text{targets the token-vault storage domain}.
\]

After acceptance:

\[
h_c:=Hash(\rho').
\]

### Security invariants

- DApp-wide shared storage surface:
  \[
  \forall d\in\mathrm{DAppIds},\ \forall f_1,f_2\in F_d,\ S_{d,f_1}=S_{d,f_2}=S_d.
  \]

- Unique token-vault position per DApp:
  \[
  \forall d\in\mathrm{DAppIds},\ \exists! t_d\ \text{s.t.}\ (d,t_d)\in\mathcal{T}_D.
  \]

- Proof-backed channel-state mutation:
  \[
  \forall c\in\mathrm{ChannelIds},\ \forall h\neq h',\ (c,h)\in\mathcal{H}\wedge(c,h')\in\mathcal{H}
  \Rightarrow
  \]
  \[
  \text{the transition } h\to h' \text{ was accepted by Groth or Tokamak verification}.
  \]

- Function-binding:
  \[
  \forall d\in\mathrm{DAppIds},\ \forall f_1,f_2\in F_d,\ f_1\neq f_2 \Rightarrow p(f_1)\neq p(f_2).
  \]

- Channel-binding:
  \[
  \forall c_1,c_2\in\mathrm{ChannelIds},\ c_1\neq c_2 \Rightarrow b(c_1)\neq b(c_2)\ \text{is sufficient but not required;}
  \]
  the accepted proof context of a channel is always checked against that channel's own
  \(b(c)\).

- Token-vault-isolation:
  \[
  \forall c\in\mathrm{ChannelIds},\ \forall \rho,\rho'\in R^{|S_c|},
  \]
  \[
  \rho_i=\rho'_i\ \forall i\neq tv(c)\ \wedge\ \rho_{tv(c)}\neq\rho'_{tv(c)}
  \]
  must satisfy the corresponding Groth or Tokamak token-vault-write admissibility
  conditions.

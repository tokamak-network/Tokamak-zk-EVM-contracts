# Tokamak Private App Channels / private-state DApp / the-great-first-channel

## Promotion and Operation Checklist for Avoiding Domestic Centralized Exchange Delisting Risk

**Reference date:** 2026-05-11  
**Target:** Tokamak Network, TON, Tokamak Private App Channels, private-state DApp, `the-great-first-channel`  
**Purpose:** External promotional materials, GitHub/NPM documentation, CLI guidance text, exchange explanatory materials, operational policy review  
**Caution:** This document is not a legal opinion and does not guarantee the actual judgment of Upbit, Bithumb, Coinone, DAXA, FIU, or FSC. The final judgment on listing maintenance and applicability under the Specified Financial Information Act / VASP rules must be separately confirmed with an external law firm and exchange compliance teams.

---

## 0. Core Purpose Of The Document

This document has one goal.

> **To consistently explain Tokamak Private App Channels not as "a privacy deposit and withdrawal network directly supported by exchanges," but as "a private-state application channel used optionally on top of a transparent L1 boundary," without making TON itself appear to be "a virtual asset whose transfer records cannot be verified."**

The public standards of domestic centralized exchanges commonly consider the following elements.

- Ability to monitor major wallet information
- Appropriate monitoring means such as block explorers
- Ability to verify transfer records
- Possibility of use for money laundering, terrorist financing, legal/regulatory circumvention, illegal gambling, and similar purposes
- Credibility of the issuer and operator
- Technical, security, and operational stability
- Need for user protection

Therefore Tokamak's external message must be fixed in the following structure.

> **TON remains a transparent L1 asset handled by centralized exchanges. Tokamak Private App Channels is a confidential application-state layer that users use on an opt-in basis from self-custody wallets. TON deposits/withdrawals and L1 bridge deposits/withdrawals directly handled by exchanges are transparently observable, and what is private is the counterparty relationship and provenance of note transfers inside the channel.**

---

## 1. Absolute Principle: "TON Is A Transparent L1 Asset, private-state Is Opt-In DApp State"

The same sentence must be repeated in promotional materials, GitHub README, NPM README, CLI help, exchange explanatory materials, FAQ, and press releases.

> **Tokamak Private App Channels does not change TON's own L1 transfer rules. TON deposits and withdrawals handled by centralized exchanges remain transparent TON transfers on the existing exchange-supported network. The private-state DApp is a proof-backed confidential state layer that users optionally use inside a separate application channel after moving TON to a self-custody L1 wallet.**

If this sentence wavers, exchanges may view TON as an asset with privacy functionality attached. Conversely, if this sentence is consistent, the defensive logic becomes close to AZTEC's public listing strategy.

The key points confirmed from AZTEC's public listing materials are as follows.

- The exchange deposit and withdrawal network was limited to Ethereum.
- The AZTEC token was handled by exchanges on the ERC-20 surface of Ethereum L1.
- The Aztec network's private state functionality was not hidden, but it was separated from the deposit and withdrawal network directly supported by exchanges.
- Monitoring tools, node status, and asset explanation materials were provided together.

Tokamak should explain itself in the same way.

- The TON that exchanges see is the existing transparent L1 TON.
- A private-state note is not an exchange-supported asset.
- `the-great-first-channel` is not an exchange deposit and withdrawal network, but an opt-in application channel.
- L1 bridge deposits and withdrawals are observable on-chain.
- The counterparty relationship and provenance of internal note transfers are not reconstructed by default by a public observer.

---

## 2. Public Listing Strategy To Imitate From AZTEC

### 2.1 Fix The CEX Edge As A Transparent L1/ERC-20 Surface

AZTEC's most important strategy was **separating the exchange deposit/withdrawal network from the private execution network**. The surface actually handled by Korean exchanges was not internal private network state, but a transparent token on Ethereum.

Tokamak should follow the following approach.

- [x] Explain that what exchanges handle is only **TON's existing L1 transfer**.
- [x] Do not express private-state notes, channel balances, note commitments, or encrypted note payloads as **assets subject to exchange deposits and withdrawals**.
- [x] Do not say "TON becomes private"; instead say **"self-custody users can use private-state functionality in an opt-in DApp channel."**
- [x] Clearly state that exchanges do not directly support the private-state channel as a deposit network.
- [x] Do not call a private note only "TON"; call it **"channel-local note representation"**, **"private-state note"**, or **"application-level accounting state"**.

### 2.2 Positioning As "Programmable Privacy Infrastructure," Not As A "Privacy Coin"

Aztec did not hide privacy. Instead, it explained itself not as an "anonymous coin" but as the following.

- A programmable privacy L2 that supports both public/private state
- Infrastructure where users can choose what to make public/private
- No-backdoor principle
- Customizable controls that can create compliant apps

Tokamak promotion should go in the same direction.

#### Prohibited Frames

- [x] "TON anonymous transfer"
- [x] "Even exchanges cannot trace it"
- [x] "Can hide source of funds"
- [x] "untraceable TON"
- [x] "mixer"
- [x] "tumbler"
- [x] "dark coin"
- [x] "cash-out tracking prevention"
- [x] "avoidance of regulator/exchange monitoring"

#### Recommended Frames

- [x] "proof-backed confidential application state"
- [x] "L1-transparent bridge edge"
- [x] "user-controlled private note state"
- [x] "selective disclosure capable architecture"
- [x] "privacy-preserving DApp channel"
- [x] "TON custody remains anchored on L1"
- [x] "internal note transfer privacy, transparent L1 entry/exit"

### 2.3 Publish Monitoring Materials First

An important point in AZTEC's public materials was not "exchanges can see all private history," but **providing enough public surface that exchanges need to see**.

Tokamak must also publish the following before promotion.

- [x] Bridge contract address
- [x] Vault contract address
- [x] ChannelManager address
- [x] `the-great-first-channel` creation transaction
- [x] private-state DApp registration information
- [x] verifier contract addresses
- [x] proxy/admin/owner/multisig addresses
- [x] Upgrade authority structure
- [x] event schema
- [x] explorer links
- [x] accepted transition log
- [x] nullifier/commitment/event observation method
- [x] "what is visible and what is not visible" matrix

Without these materials, exchanges may judge that "appropriate monitoring means are insufficient."

---

## 3. Required Wording Checklist For Promotional Materials

The following items must be reflected in the homepage, blog, GitHub README, NPM README, CLI help, press release, and exchange explanatory materials.

### 3.1 Wording That Must Be Included

- [x] **TON deposits and withdrawals on centralized exchanges are transparently performed on the existing exchange-supported network.**
- [x] **Tokamak Private App Channels is not a centralized exchange deposit and withdrawal network.**
- [ ] **private-state notes are not separate assets that can be deposited to an exchange.**
- [x] **Users first hold TON in a self-custody L1 wallet and then use the channel on an opt-in basis.**
- [x] **L1 bridge deposits and withdrawals are observable on-chain.**
- [x] **Public registration events such as channel join, L1/L2 identity registration, and note-receive public key registration are observable.**
- [x] **The counterparties and provenance of internal note transfers are not reconstructed by default from public contract state.**
- [x] **Tokamak or the channel operator does not hold users' spending keys, wallet secrets, or note viewing secrets.**
- [x] **Users may selectively prove notes or transaction facts they hold when needed. However, promote only the scope that is actually implemented.**
- [ ] **This system must not be used for money laundering, terrorist financing, sanctions evasion, legal/regulatory circumvention, illegal gambling, or concealment of criminal proceeds.**

### 3.2 Wording That Must Be Avoided

- [x] "Anonymizes TON."
- [x] "Exchanges cannot trace the source of funds."
- [x] "Can hide the source when cashing out."
- [x] "CEX off-ramp privacy."
- [x] "untraceable TON."
- [x] "Fully anonymous transfer."
- [x] "Prevention of regulator/exchange tracking."
- [x] "Safer than a mixer."
- [x] "Dark coin functionality."
- [x] "Privacy transfer recognized by listed exchanges."

The last expression is especially dangerous. The AZTEC case can be a positive comparison case, but it does not mean that "Korean exchanges approved private-state transfers." The strategy confirmed from AZTEC's public materials is **Ethereum CEX edge + optional private state + public monitoring materials**, not that exchanges accepted or guaranteed all internal private history.

---

## 4. Response Matrix For "Ability To Verify Transfer Records"

From the perspective of exchanges and the FIU, this matrix is the most important document. Promotional materials should include a summary, and GitHub should publish the detailed version.

| Category | Publicly visible / monitorable | What exchanges/monitors can know | What cannot be known | Documentation method |
|---|---:|---|---|---|
| CEX -> user L1 wallet TON withdrawal | Possible | Exchange customer's withdrawal address, amount, time | What the user will do later from a self-custody wallet | Existing CEX records + L1 explorer |
| User L1 wallet -> Tokamak bridge deposit | Possible | L1 address, bridge address, amount, tx hash, time | User's future note counterparty | Etherscan / bridge event |
| Channel join | Possible | L1 account, L2 address pair, note-receive public key, channel name/id | User's future private note counterparty | ChannelManager event |
| Deposit-channel / accounting move | Possible | Amount and state change entering channel accounting from the bridge vault | Which note transfer that amount will later lead to | bridge/channel event |
| Note mint | Partially possible | commitment creation, encrypted note-delivery event, storage update | note plaintext, owner meaning, internal purpose | commitment/nullifier/event explorer |
| Note transfer | Partially possible | transition accepted, commitment/nullifier/ciphertext event | sender-recipient relationship, note provenance | public observer + user selective proof |
| Redeem note to channel balance | Partially possible | redeem transition, nullifier usage, accounting update | From whom that note came internally | channel event |
| Withdraw-channel / bridge withdraw | Possible | L1 address, amount, tx hash, time | internal note provenance | Etherscan / bridge event |
| User L1 wallet -> CEX deposit | Possible | CEX deposit address, amount, time, and source may be a bridge withdrawal address | internal note sender/provenance | CEX + L1 explorer |

The most important sentence in this table is the following.

> **Tokamak does not hide transfer records of CEX-facing TON transfers. However, the counterparty relationship and note provenance of note transfers inside the private-state DApp cannot be reconstructed by default by a public observer. This limitation is not hidden and is stated explicitly.**

This approach is the defensive logic for the exchange-policy question of "ability to verify transfer records." In other words, the TON deposit and withdrawal records handled by exchanges are verifiable, and what is difficult to verify is the internal history of an opt-in private-state DApp that exchanges do not directly handle.

---

## 5. "Monitoring Packet" Checklist For Exchange Submission

Before promotion, a **CEX Monitoring Packet** must be published as a separate document or repository directory. File names may be structured as follows, for example.

- `TPAC-CEX-Boundary-Memo.md`
- `TPAC-Contract-Addresses.json`
- `the-great-first-channel-Policy-Snapshot.json`
- `Private-State-Observability-Matrix.md`
- `Admin-Wallets-and-Upgrade-Policy.md`
- `Security-and-Incident-Response.md`
- `Selective-Disclosure-Design.md`
- `Marketing-Compliance-Guidelines.md`

### 5.1 Contract Address Pack

Publish the following information without omission.

- [x] chain ID
- [x] canonical TON contract address
- [x] bridge core address
- [x] L1 token vault address
- [x] ChannelManager address
- [x] `the-great-first-channel` channel id/name
- [x] channel creation tx hash
- [x] private-state DApp id
- [x] private-state DApp registration tx hash
- [x] verifier contract addresses
- [x] Groth16 verifier / Tokamak zk-EVM verifier addresses
- [x] proxy addresses
- [x] implementation addresses
- [x] proxy admin addresses
- [x] owner/admin/multisig/timelock addresses
- [x] treasury or fee recipient addresses
- [x] channel leader/operator address
- [x] deployment block number
- [x] deployed Git commit hash
- [x] NPM package version used for deployment/proving/CLI
- [x] source verification status
- [x] ABI links
- [x] bytecode hash

### 5.2 Event And Monitoring Map

Document the following events.

- [x] bridge deposit event
- [x] bridge withdraw event
- [x] channel created event
- [x] channel joined event
- [x] L1/L2 identity registration event
- [x] note-receive public key registration event
- [x] deposit-channel event
- [x] withdraw-channel event
- [x] note commitment created event
- [x] nullifier used event
- [x] encrypted note-delivery event
- [x] proof accepted event
- [x] storage root / commitment root update event
- [x] policy snapshot event
- [x] verifier or metadata update event
- [x] proxy upgrade event
- [x] emergency pause or migration event, if it exists

For each event, the following must be written.

- event name
- contract address
- indexed fields
- non-indexed fields
- explorer query example
- what can be known from this event
- what cannot be known from this event
- meaning for exchange monitoring

### 5.3 Public Channel Observer

Similar to AZTEC's Etherscan + Aztec monitoring materials, Tokamak should also provide a separate explorer or observer page. Its function is not internal note deanonymization, but **public edge visibility**.

Required functions:

- [ ] `the-great-first-channel` status page
- [ ] latest accepted transition
- [ ] total L1 bridge deposits
- [ ] total L1 bridge withdrawals
- [ ] channel participants count
- [ ] channel join list
- [ ] registered L1/L2 address pair list
- [ ] note-receive public key list
- [ ] commitment event list
- [ ] nullifier event list
- [ ] encrypted payload event list
- [ ] verifier version
- [ ] channel policy hash
- [ ] DApp metadata hash
- [ ] source code / ABI link
- [ ] admin wallet status
- [ ] upgrade history
- [ ] incident notices

Recommended explanatory text:

> **This observer does not deanonymize private note transfers. It provides exchange-grade visibility into L1 bridge edges, channel registration, accepted transitions, commitments, nullifiers, encrypted note events, verifier versions, and channel policy.**

---

## 6. Selective Disclosure / Viewing Key Policy

This item is very important. The direction must not be to add a **global auditor backdoor** for exchange listing maintenance. AZTEC's public strategy is also basically a "no backdoor" structure and a structure where "apps can selectively create compliant controls," not a structure where exchanges reconstruct all note history.

Tokamak documentation should also explain that the note-receive public key is registered on-chain, but the note-receive private key and L2 spending key are derived and managed on the user side. In other words, it must not be promoted as a structure where the operator sees users' notes.

### 6.1 Principles That Must Be Kept

- [x] Tokamak, the company, and the channel operator do not hold users' spending keys.
- [x] Tokamak, the company, and the channel operator do not hold users' wallet secrets.
- [x] Tokamak, the company, and the channel operator do not hold a master viewing key that can see all note plaintext.
- [x] Do not promote a structure where all note copies are automatically delivered to an auditor or exchange as a listing-maintenance device.
- [x] Selective disclosure must be **user-controlled**.
- [ ] Viewing key sharing must be clearly separated from spending key sharing.
- [ ] Document the scope of evidence that users can selectively submit.
- [x] Do not promote disclosure functionality that has not been implemented.

### 6.2 Items To Prepare As User Selective Disclosure Functions

Already existing CLI functions and functions to be added later must be separately documented.

Items to document immediately:

- [x] A user decrypts notes they hold locally.
- [x] A user checks the commitment, creation tx, amount, and channel id of a specific note.
- [ ] A user exports material that can prove that a specific note was delivered to them.
- [ ] A user exports material that can connect a specific redeem or withdraw with their note use.
- [ ] This export does not include the spending key.
- [ ] This export does not forcibly disclose the entire wallet history.

Items to express only as a "roadmap" if not implemented yet:

- [ ] note receipt proof for a specific period
- [ ] selective disclosure only for transactions with a specific counterparty
- [ ] user-driven linkage proof between a specific bridge deposit and note mint
- [ ] linkage proof between a specific redeem and note ownership
- [ ] user consent disclosure package for exchange request response

Recommended wording to put in CLI documentation:

> **Tokamak cannot disclose a user's private note history on behalf of the user because Tokamak does not hold the user's viewing or spending secrets. A user may voluntarily generate selected evidence from their local wallet state.**

### 6.3 Policy On Auditor Note-Copy Functionality

Aztec has a primitive that can deliver notes to a third party at the contract level, but this is close to a compliance primitive that a specific app can optionally use, not a functionality confirmed as a listing condition. Aztec simultaneously emphasizes no backdoor and customizable compliance controls.

Tokamak's recommended policy is as follows.

- [x] Do not put global auditor note-copy into the default policy of `the-great-first-channel`.
- [x] Do not put a master auditor that lets the company or exchanges see all notes.
- [ ] If auditor functionality is added, separate it into a separate channel or separate DApp policy.
- [ ] Clearly label a channel with auditor functionality as an "audited channel."
- [ ] Do not confuse unaudited/private channels with audited channels.
- [x] Explain to exchanges that "there is no global backdoor, but user selective disclosure and public edge monitoring are provided."

---

## 7. Operational Checklist Dedicated To `the-great-first-channel`

Because `the-great-first-channel` is a channel directly opened and operated by Tokamak, exchanges are more likely to view it as an **issuer/operator-linked utility** than as a third-party external overlay. Therefore this channel must be operated on the assumption that it can be treated not as a general technical demo, but as an official utility related to a listed asset.

### 7.1 Channel Public Profile

Publish the following information on one page.

- [x] Channel name: `the-great-first-channel`
- [x] Channel id
- [x] creation tx hash
- [x] creator / channel leader address
- [x] DApp id
- [x] DApp label: private-state DApp
- [x] ChannelManager address
- [x] linked bridge address
- [x] linked vault address
- [x] canonical TON address
- [x] accepted function root
- [ ] storage layout hash
- [x] verifier snapshot
- [x] metadata digest
- [x] join policy
- [x] toll/refund policy
- [x] upgradeability policy
- [ ] emergency policy
- [ ] latest accepted transition
- [ ] latest policy version
- [x] source commit and package versions

### 7.2 Channel Operator Explanation

When using the word "operator" in documentation, it must be explained in a limited way. Expressions that make it look like the operator coordinates proving, relaying, and service operation can be read by exchanges as a possibility of operator intervention, so the actual operating model must be clearly written.

Recommended wording:

> **The channel operator opens and maintains public channel metadata and policy. The operator does not custody user TON, does not hold user note secrets, does not intermediate user transfers, and does not have a protocol backdoor to reconstruct private note provenance.**

Operating methods that must be prohibited:

- [x] The server collects users' private keys or wallet secrets.
- [x] The server stores users' note plaintext.
- [x] The operator server exclusively generates users' transfer proofs.
- [x] Users cannot redeem/withdraw without the operator server.
- [x] The operator receives user queries and executes them on behalf of users.
- [x] The operator intermediates transfers between users.
- [x] The operator arbitrarily views private history.

If any one of these actually exists, a separate VASP/AML legal review is needed before promotion.

---

## 8. GitHub / NPM / CLI Documentation Checklist

Tokamak's public repository and NPM package must support the logic of "non-custodial, user-local execution." If documentation is unclear, exchanges may misunderstand it as operator intermediation.

### 8.1 Sections To Add To The GitHub README

- [ ] `CEX Boundary and Monitoring`
- [ ] `What is public and what is private`
- [ ] `Not a mixer / not a CEX deposit network`
- [ ] `User-controlled selective disclosure`
- [ ] `No operator-held viewing key`
- [ ] `No custody by Tokamak`
- [ ] `Known limitations`
- [ ] `AML / sanctions / illegal-use prohibition`
- [ ] `Contract addresses and monitoring`
- [ ] `the-great-first-channel public profile`
- [ ] `Upgrade and incident response policy`

### 8.2 Wording To Add To The NPM README

Put the following warnings on the CLI installation page and usage examples.

> **Do not use a centralized exchange deposit address as a private-state wallet address. Private-state notes are not supported exchange assets. Always withdraw TON to a self-custody L1 wallet before using a channel.**

> **Bridge deposits and withdrawals are public L1 events. Internal note transfers are private by design and are not automatically reconstructible by Tokamak, exchanges, or public observers.**

> **This CLI does not send your spending key, wallet secret, or private note plaintext to Tokamak.**

### 8.3 Warnings To Display During CLI Execution

In particular, before `join`, `deposit-channel`, `mint`, `transfer`, `redeem`, and `withdraw-channel`, display the following information.

- [ ] Whether this action emits a public event on L1
- [ ] Whether this action changes private note state
- [ ] Which address and amount are public
- [ ] Which information is not public
- [ ] That note provenance is not reconstructed by a public observer
- [ ] Prohibition of illegal-purpose use
- [ ] Prohibition of CEX deposit address use
- [ ] Recovery limit when wallet secret is lost
- [ ] Confirmation that the user checked the policy snapshot

---

## 9. Security And Governance Checklist

From an exchange perspective, the issue is not only the privacy functionality itself, but also whether the operating entity is trustworthy, whether major wallets can be monitored, and whether upgrades and incident response are transparent.

### 9.1 Admin Wallet / Upgrade Policy

- [x] Publish UUPS/proxy owner address
- [x] Publish whether multisig is used
- [x] Publish whether timelock is used
- [ ] Publish owner change history
- [ ] Publish implementation upgrade history
- [ ] Publish emergency pause authority
- [x] Publish verifier replacement authority
- [x] Publish metadata update authority
- [x] Publish the principle that channel policy cannot be silently mutated
- [x] Publish the principle that a new channel is created if existing channel policy needs to be changed

If the bridge owner's upgrade authority and privileged owner authority are accepted as trust assumptions in Tokamak's security model, this part must not be hidden. It should instead be put directly in the monitoring packet for exchanges.

### 9.2 Audit / Security Disclosure

- [ ] Publish whether external audit has been completed
- [ ] If unaudited, display "unaudited / experimental"
- [x] Publish known limitations
- [x] Publish verifier soundness assumption
- [x] Publish metadata correctness assumption
- [x] Publish exact-transfer canonical token assumption
- [x] Publish L1 custody / L2 accounting separation
- [ ] Publish incident contact
- [ ] Publish vulnerability disclosure process
- [ ] Publish emergency migration process

---

## 10. Exchange Communication Checklist

Before promotion, prepare explanatory materials that can be sent to Upbit, Bithumb, and Coinone. The core is not "we made internal private note provenance automatically reconstructible by exchanges."

The core is the following.

> **The TON surface handled by exchanges is transparent, private-state is opt-in DApp internal state, and public edges, major wallets, and contract events are monitorable.**

### 10.1 Composition Of Exchange Explanatory Materials

#### 1. Executive Summary

- TON's L1 transfer rules do not change
- CEX deposit/withdraw network is the existing TON-supported network
- Tokamak Private App Channels is not a CEX deposit network
- The private-state DApp is an opt-in DApp for self-custody users

#### 2. AZTEC Comparison

- Similarity: L1/Ethereum edge is transparent, internal private state is optional
- Similarity: Public/private state is distinguished in explanation
- Similarity: Monitoring tools and explorer are provided
- Difference: Tokamak is directly connected to already-listed TON, so stricter disclosure is provided
- Difference: `the-great-first-channel` is a channel-specific DApp, and private notes are not separate listed assets

#### 3. CEX Boundary

- TON deposits/withdrawals visible to CEX
- How to observe bridge deposits/withdrawals
- When a user cashes out on a CEX, L1 bridge withdrawal provenance may be visible
- Internal note sender/provenance is not reconstructed by default by public observers

#### 4. Monitoring Packet

- contract address table
- admin wallet table
- event map
- explorer links
- upgrade history
- incident response

#### 5. Selective Disclosure

- Tokamak does not hold user keys
- Users can selectively submit note evidence
- Distinguish implemented functions from planned functions

#### 6. Illegal-Use Policy

- Prohibit use for AML/TF/sanctions evasion/legal circumvention/illegal gambling purposes
- Response policy when related addresses or activities are discovered
- Scope of public data that can be provided upon request from investigative agencies or exchanges

#### 7. Legal Memo

- Non-custodial structure
- Operator role
- Direct user L1 interaction
- Review of VASP applicability
- Travel Rule boundary

Considering the Korean Travel Rule and FIU policy environment, exchange explanatory materials should not say "circumvents the Travel Rule," but should have the following structure.

> **It provides opt-in DApp state after self-custody without touching the information-provision system for VASP-to-VASP CEX transfers.**

---

## 11. Promotional Wording Samples

### 11.1 Recommended Press Release Wording: English

> Tokamak Private App Channels is an Ethereum-settled, proof-backed application channel framework. TON custody and settlement remain anchored on L1, while users may opt into private-state DApps that keep internal note ownership and note transfer semantics confidential from public contract state.

> the-great-first-channel is a public mainnet channel for the private-state DApp. Its L1 bridge deposits, withdrawals, channel registration, policy snapshot, verifier information, commitments, nullifiers, and encrypted note-delivery events are publicly observable. Internal note transfer counterparties are private by design and are not automatically reconstructed by Tokamak or public observers.

> Tokamak does not hold user spending keys, wallet secrets, or note viewing secrets. Users interact with the bridge and channel from self-custody wallets and may selectively disclose their own note-related evidence where technically supported.

> Tokamak Private App Channels are not a centralized exchange deposit network and private-state notes are not exchange-supported assets. TON deposits and withdrawals on centralized exchanges remain standard transparent TON transfers on the exchange-supported network.

### 11.2 Recommended Press Release Wording: Korean

> Tokamak Private App Channels is a proof-backed application channel framework settled on L1. TON deposits/withdrawals on centralized exchanges and L1 bridge deposits/withdrawals are transparently observable, and only the meaning and counterparty relationship of note transfers inside the private-state DApp are not exposed by default in public contract state.

> `the-great-first-channel` is a public mainnet channel for the private-state DApp. Channel creation, user join, bridge deposit/withdraw, verifier, policy snapshot, commitment, nullifier, and encrypted note-delivery events can be publicly monitored. However, internal note provenance is not reconstructed by default without user selective disclosure.

> Tokamak does not hold users' spending keys, wallet secrets, or note viewing secrets, and does not intermediate user-to-user transfers or custody user assets.

### 11.3 Prohibited Wording

- [x] "Fully anonymizes TON."
- [x] "Can hide source when cashing out through an exchange."
- [x] "Upbit, Bithumb, and Coinone cannot trace it."
- [x] "Can avoid regulator monitoring."
- [x] "Can be used like a mixer."
- [x] "TON evolved into a privacy coin."
- [x] "Can launder source of funds."
- [x] "CEX off-ramp privacy."

---

## 12. P0 Checklist From A Function Implementation And Operation Perspective

The following items are **P0 blockers** that must be completed before promotion.

### 12.1 Public Monitoring

- [x] All mainnet contract sources are verified on Etherscan
- [x] Publish contract address table
- [x] Publish `the-great-first-channel` public profile
- [x] Publish public observer or explorer
- [x] Publish bridge deposit/withdraw event query method
- [x] Publish channel join / L1-L2 pair monitoring method
- [x] Publish commitment/nullifier/encrypted event monitoring method
- [ ] Publish admin wallet / proxy / implementation / upgrade history
- [ ] Publish emergency notice page

### 12.2 Documentation Consistency

- [ ] Use the same terminology in GitHub README and NPM README
- [x] Remove the expression "TON itself becomes a private asset"
- [x] Remove "untraceable" expression
- [x] Remove "anonymous cash-out" expression
- [x] Remove "mixer" expression
- [ ] State `private-state note != exchange-supported TON`
- [x] State `CEX edge remains transparent`
- [x] Accurately state the non-visibility of internal note provenance without hiding it

### 12.3 User Protection

- [ ] CLI warning prohibiting CEX deposit address use
- [x] CLI guidance to use self-custody wallet
- [ ] CLI display of bridge deposit/withdraw public visibility
- [ ] CLI display of note transfer privacy scope
- [x] Warning about keeping wallet secret / spending key / viewing key
- [x] Display lost secret recovery limits
- [ ] Display illegal-use prohibition
- [ ] channel policy review confirmation

### 12.4 Operator Risk

- [x] State that Tokamak does not hold user keys
- [x] State that Tokamak does not hold user note plaintext
- [x] State that Tokamak does not intermediate user-to-user transfers
- [x] State that Tokamak cannot arbitrarily reconstruct private provenance
- [x] State that users can directly interact with L1 even without an operating server
- [ ] If relayer/prover/indexer services are actually operated, publish their scope and log retention policy
- [x] If operator fees exist, publish the receiving address and charging basis
- [x] Publish channel leader/operator authority

### 12.5 Legal And Exchange Response

- [ ] Obtain external law firm review memo on the Specified Financial Information Act / VASP
- [ ] Prepare explanatory materials for each exchange
- [ ] Prepare response table for DAXA best-practice standards
- [ ] Review Travel Rule impact
- [ ] Prepare illegal-use response policy
- [ ] Define the scope of public data that can be provided upon request from investigative agencies or exchanges
- [ ] Define user selective disclosure request procedure

---

## 13. P1 Recommended Checklist

These are not P0 items, but they greatly reduce listing-maintenance risk.

- [ ] Provide public observer API
- [ ] Automatically generate daily monitoring report
- [ ] Major contract event RSS/Telegram/Slack alert
- [ ] Admin wallet movement alert
- [ ] Verifier or implementation change alert
- [ ] Large bridge deposit/withdraw alert
- [ ] Suspicious L1 address interaction policy
- [ ] Establish a policy to review sanctions-screening targets at least at the L1 bridge edge
- [ ] optional user disclosure export command
- [ ] Standardize note evidence export format
- [ ] third-party security audit
- [ ] bug bounty
- [ ] reproducible build documentation
- [ ] NPM package integrity documentation
- [ ] release signing
- [x] deployment artifact archive
- [ ] Korean whitepaper summary
- [ ] Korean FAQ for exchanges and users

---

## 14. "What Must Be Honestly Told To Exchanges"

The question exchanges will be most concerned about is this.

> "When a user withdraws TON from the bridge and deposits it back to an exchange, can we know from whom that TON came inside L2?"

The answer to this should not be evaded.

Recommended answer:

> **Internal private-state note provenance cannot be reconstructed from default public data alone. Exchanges and public observers can see the user's L1 bridge entry/exit, channel join, public commitments, nullifiers, encrypted note-delivery events, and accepted transitions. However, internal note sender-recipient relationships and provenance chains are not reconstructed by default without the user's selective disclosure. This design does not hide CEX-facing TON transfers, but provides privacy for opt-in DApp internal note state after self-custody.**

This answer is better because it does not hide the risk. Rather than exaggerating that "everything is traceable," it is safer from a listing-maintenance perspective to **accurately separate what is visible from what is not visible**.

---

## 15. AZTEC Comparison Wording: Usable Version And Prohibited Version

### 15.1 Usable Comparison

> Tokamak Private App Channels can be compared to privacy-preserving L2 architectures such as Aztec in the limited sense that both separate a transparent L1 exchange boundary from optional private application state. Like Aztec's public materials, Tokamak distinguishes between public settlement/monitoring surfaces and private execution or note state.

This comparison is possible. The key point is that it is a **structural comparison in a limited sense**.

### 15.2 Comparison That Must Be Prohibited

> "Because AZTEC was also listed, Tokamak private-state has no delisting risk."

This sentence is dangerous. AZTEC is a separate token and separate network, and Korean exchanges limited the deposit/withdrawal surface to Ethereum. Tokamak can be read as an issuer/operator-linked utility of already-listed TON, so stronger explanatory materials and monitoring materials than AZTEC are needed.

### 15.3 Accurate Comparison Wording

> **Aztec is a positive precedent for the principle that privacy-preserving application infrastructure is not automatically incompatible with Korean centralized exchange support, provided that the exchange-supported token transfer surface remains transparent and adequate public monitoring materials are available. Tokamak applies the same boundary principle to TON: CEX-facing TON transfers and L1 bridge edges are transparent, while opt-in private-state note transfers remain confidential inside the application channel.**

---

## 16. Operational Mistakes That Increase Delisting Risk

The following are red flags to avoid.

- [x] Putting "anonymous transfer" in the first sentence of promotional materials
- [x] Speaking of "exchange cash-out source tracking prevention" as an advantage
- [x] Providing a CEX withdrawal -> bridge -> note transfer -> CEX deposit tutorial
- [x] Calling private notes only "TON notes" and confusing them with TON itself
- [x] Putting a CEX deposit address in CLI usage examples
- [x] Not publishing contract addresses and admin wallets
- [x] Promoting without source code verification
- [x] Hiding upgrade authority
- [x] Not explaining what the channel operator can do
- [x] Hiding that the server stores user viewing keys or note plaintext
- [x] Concluding that "there is no problem because AZTEC was listed"
- [x] Hiding the fact that internal note provenance cannot be reconstructed
- [x] Promoting unimplemented selective disclosure functionality as already existing
- [x] Adding an auditor backdoor while promoting it as "complete privacy"
- [x] Saying "all internal flows can be provided upon exchange request" despite having no auditor backdoor

---

## 17. Final GO / NO-GO Criteria

If any one of the following is "NO" during internal approval before promotion, external promotion must stop.

| Item | GO criterion |
|---|---|
| CEX boundary | All documents consistently explain that TON exchange deposits/withdrawals remain on the existing transparent L1 network |
| Private-state expression | Explain it as "opt-in DApp internal note privacy," not "TON anonymization" |
| Contract monitoring | Publish all major contract, verifier, vault, manager, and channel addresses |
| the-great-first-channel | Publish channel id, policy snapshot, creation tx, and operator authority |
| Explorer | bridge deposit/withdraw, channel join, commitments, nullifiers, encrypted events are monitorable |
| Admin wallet | Publish owner/proxy/admin/multisig/timelock/upgrade history |
| Selective disclosure | Explain only as user-controlled and no operator-held master viewing key |
| CLI warning | Warn against CEX deposit address use, L1 visibility, and note privacy scope |
| Illegal-use policy | State prohibition of AML/TF/sanctions evasion/legal circumvention/illegal gambling |
| Legal memo | Obtain external review of the Specified Financial Information Act / VASP / Travel Rule impact |
| Exchange memo | Prepare monitoring packet for submission to Upbit, Bithumb, and Coinone |
| Marketing review | 0 instances of "anonymous/untraceable/mixer/cash-out privacy" expressions |

---

## 18. Most Important Final Message

The message Tokamak should make externally must converge to the following one message.

### English

> **Tokamak Private App Channels does not make TON a dark coin. TON remains a transparent exchange-supported L1 asset. Private-state DApps provide opt-in confidential application state after a user moves TON into self-custody and interacts with a public L1 bridge. The bridge entry and exit, channel registration, policy, verifier, commitments, nullifiers, and encrypted events are publicly monitorable. Internal note provenance is private by design and can be disclosed only by the user within the limits of implemented selective-disclosure tools.**

### Korean

> **Tokamak Private App Channels does not make TON a dark coin. TON remains a transparent L1 asset supported by centralized exchanges. The private-state DApp is confidential application state that users optionally use through a public L1 bridge after moving TON to a self-custody wallet. Bridge deposits/withdrawals, channel registration, policy, verifier, commitments, nullifiers, and encrypted events can be publicly monitored. Internal note provenance is private by design and can be selectively disclosed only by the user within the scope of implemented selective-disclosure functionality.**

Aligning promotional materials, GitHub, NPM, CLI, and exchange explanatory materials around this sentence is the most important strategy to reduce delisting risk under the current structure.

---

## 19. Reference Links

The links below are public materials used as comparison and review targets when preparing this document. In actual submission documents, the latest status and date of each link must be checked again.

- Upbit trading support termination policy: <https://static.upbit.com/guide/market_policy_close.pdf>
- Bithumb AZTEC trading support notice: <https://feed.bithumb.com/notice/1652023>
- Bithumb AZTEC asset description: <https://feed-content.bithumb.com/cms/3224fc67-35a4-4bce-985f-f41f4e7c4b0c.pdf>
- Aztec official site: <https://aztec.network/>
- Aztec token page: <https://aztec.network/aztec-token>
- Aztec private world computer article: <https://aztec.network/blog/aztec-the-private-world-computer>
- Aztec policy principles: <https://aztec.network/policy-principles>
- Tokamak zk-EVM contracts repo: <https://github.com/tokamak-network/Tokamak-zk-EVM-contracts>
- Tokamak Private State security model: <https://github.com/tokamak-network/Tokamak-zk-EVM-contracts/blob/main/packages/apps/private-state/docs/security-model.md>
- Tokamak Private State workflow: <https://github.com/tokamak-network/Tokamak-zk-EVM-contracts/blob/main/packages/apps/private-state/docs/workflow.md>
- Tokamak private-state README: <https://github.com/tokamak-network/Tokamak-zk-EVM-contracts/blob/main/packages/apps/private-state/README.md>
- Tokamak zk-L2 bridge whitepaper: <https://github.com/tokamak-network/Tokamak-zk-EVM-contracts/blob/main/bridge/docs/zk-l2-bridge-whitepaper.md>
- private-state CLI NPM: <https://www.npmjs.com/package/@tokamak-private-dapps/private-state-cli>
- Tokamak zk-EVM CLI NPM: <https://www.npmjs.com/package/@tokamak-zk-evm/cli>
- Specified Financial Information Act Enforcement Decree link: <https://www.law.go.kr/lumLsLinkPop.do?chrClsCd=010202&lspttninfSeq=82843>

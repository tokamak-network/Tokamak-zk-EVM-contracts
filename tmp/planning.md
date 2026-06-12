# Private-State DApp and Tonnel Channel Terms Plan

## Purpose

This document plans the terms acceptance flow for the Private-State DApp, Tonnel, its dedicated Channel
`the-great-first-channel`, and the CLI used to access them. The CLI is only one interface and acceptance mechanism. The
Terms are for the Service as a whole.

The target reader is an ordinary user, not a protocol developer. The terms text must therefore define necessary technical
terms first, use those terms consistently, and avoid marketing language that could misstate the public and private
boundaries of the system.

This document is a product and implementation plan. It is not legal advice. Provider Party authority, governing law,
venue, consumer-law carveouts, liability caps, and dispute provisions remain recorded for far-future counsel review.

## References Reviewed

Coverage in this plan is informed by the following materials:

- `checklist.md` in this repository.
- Aztec Foundation Terms of Service, including service scope, warranty disclaimers, third-party materials, restrictions,
  indemnity, liability limitation, changes to terms, development-tooling risk disclosures, wallet-safekeeping risk,
  bridging risk, blockchain finality risk, and sanctions compliance: `https://aztec.network/terms-of-service`.
- Uniswap Labs Terms of Service, including non-custodial responsibility, prohibited activity, no investment advice,
  third-party products, sanctions restrictions, user responsibility, and indemnity:
  `https://support.uniswap.org/hc/en-us/articles/30935100859661-Uniswap-Labs-Terms-of-Service`.
- Aave App Terms of Service, including jurisdictional restrictions, sanctions restrictions, no warranties, limitation of
  liability, user compliance obligations, and third-party service risk:
  `https://aave.com/legal/app/terms-of-service`.
- MetaMask self-custody guidance, including the principle that a self-custodial wallet leaves funds and access under the
  user's control: `https://support.metamask.io/start/metamask-is-a-self-custodial-wallet/`.

## Product Compliance Position

The Service terms must preserve the following position:

- TON remains a transparent Ethereum mainnet asset at the exchange-facing boundary.
- Tonnel is the branded name for Tokamak Private App Channels.
- The private-state DApp uses Tonnel and its dedicated Channel `the-great-first-channel`.
- A Channel, including `the-great-first-channel`, is an opt-in Tonnel application environment, not an exchange deposit or
  withdrawal network.
- Private Notes are channel-local private application records, not exchange-depositable assets.
- Ethereum mainnet bridge deposits, bridge withdrawals, Channel joins, identity registrations, note-receive public key
  registrations, and other public registration or accounting events remain observable.
- Tonnel is designed so public contract state does not, by itself, reconstruct some internal Private Note
  sender-recipient relationships or note provenance by default, but no privacy, anonymity, compliance result, or
  exchange acceptance is guaranteed.
- The system must not be described as a mixer, tumbler, privacy coin, untraceable TON transfer method, exchange-monitoring
  avoidance method, or asset-history concealment method.

## Checklist Coverage Review

The one-time install acceptance model does not clearly violate `checklist.md` if the CLI enforces acceptance before
installation or first use of the Service and if JSON mode instructs User-Controlled AI Agents to explain the terms
without accepting them for the user.

| Checklist concern | Terms coverage |
|---|---|
| TON must not be described as untraceable | Sections 2, 4, 5, 6, and 10 state that Ethereum mainnet records remain public or observable. |
| Tonnel must not be described as an exchange deposit network | Sections 1 and 2 define Tonnel, the private-state DApp, and Channels as opt-in application environments, not exchange deposit or withdrawal networks. |
| Private Notes must not be exchange-depositable assets | Sections 1 and 2 state that Private Notes are channel-local application records. |
| Users first hold TON in a self-custody Ethereum account | Sections 1, 2, 6, and 8 define self-custody and user-controlled Ethereum accounts. |
| Bridge deposit and withdrawal observability must be disclosed | Sections 4 and 10 disclose public bridge records and observer surfaces. |
| Channel join and public registration observability must be disclosed | Sections 4 and 10 disclose Channel joins, identity registration, and note-receive public key registration. |
| Internal note privacy limits must be disclosed | Section 5 states what public contract state generally cannot reconstruct and what may still reveal information. |
| Provider Parties and Channel Operators must not claim custody of user secrets | Sections 6, 8, and 9 state that they do not possess user keys or secrets. |
| Selective disclosure must be limited to implemented features | Section 10 states that selective disclosure depends on implemented features and preserved user evidence. |
| Illegal use must be prohibited | Section 7 prohibits money laundering, terrorist financing, sanctions evasion, regulatory evasion, fraud, illegal gambling, criminal-proceeds concealment, and exchange-monitoring evasion. |
| Public monitoring surfaces must be available | Section 10 states that an Official Public Observer exists and describes its limits. |
| Marketing must avoid mixer or privacy-coin framing | Sections 2, 5, and 7 expressly avoid or prohibit that framing. |

Conclusion: the terms draft below covers every checklist item that affects Service users. Far-future counsel review
remains recorded separately from the current implementation plan.

## Ambiguity and Dispute-Risk Review

The following drafting choices reduce ambiguity and dispute risk:

- Use "Ethereum mainnet" for the public chain boundary and avoid developer shorthand for that boundary.
- Define "L2" once because users may encounter the term elsewhere, then prefer "Tonnel private application state" in
  user-facing text.
- Define the relationship among Tonnel, Channels, and the Tonnel private application state before describing user duties.
- State that no recovery method exists if all required secret material and backups are lost.
- Replace informal actor labels with "Provider Parties", "Channel Operators", and "Third-Party Services".
- Avoid absolute privacy claims. Describe what is public, what may be hidden from public contract state by default, and
  what can still leak through metadata or third-party services.
- Use a terms version and deterministic terms hash to decide when renewed acceptance is required.
- Avoid saying that continued use alone accepts changed terms unless an official Service interface has shown the changed
  terms and collected a fresh acceptance record.
- Avoid statements that imply Provider Parties can reverse Ethereum mainnet transactions, recover lost secrets, guarantee
  exchange treatment, or guarantee legal, tax, accounting, regulatory, or compliance outcomes.
- Draft public documents under the assumption that selected planning items have been completed. Public Terms, Privacy
  Notice, README, help, and agent-facing documents must not include implementation-status assumptions such as "if
  implemented", "when released", or "future implementation". If a missing business or legal decision prevents
  completion-assumption drafting, move that decision ahead of public-document drafting.

## Draft Terms Content

### 1. Definitions

For purposes of these Terms:

- **Terms** means these terms governing access to and use of the Service.
- **Service** means the private-state DApp, Tonnel, `the-great-first-channel`, the Bridge workflows, the CLI, official
  public observer services, official documentation, official examples, official deployment artifacts, and related
  software or interfaces officially made available by the Provider Parties for the private-state DApp.
- **CLI** means the command-line software that a user may install and execute to access or operate parts of the Service.
- **Private-State DApp** means the application that allows users to use Tonnel private application state through supported
  Channels.
- **Tonnel** means the branded user-facing name for Tokamak Private App Channels.
- **Tokamak Private App Channels** means the application-channel system exposed to users through Tonnel.
- **Channel** means a specific opt-in Tonnel application environment with its own policy, membership rules, accounting
  records, and private note records. A Channel is not an exchange deposit or withdrawal network.
- **The Great First Channel** means the dedicated initial Channel identified as `the-great-first-channel`.
- **Join Toll** means the one-time Channel entry fee paid when a user joins a Channel. The implemented policy is that,
  for Channel exits, the refundable portion is returned to the exiting user and the non-refundable portion is sent to the
  Ethereum address
  `0x000000000000000000000000000000000000dEaD`. The Service must describe this as a burn-address transfer, not as a
  TON total-supply reduction. The Bridge default refund policy may be updated, while each Channel fixes its own refund
  policy at Channel creation. User-facing documents must direct users to the relevant on-chain getters, official
  observer views, CLI output, or Monitoring Packet files rather than hardcoding a single refund schedule as universal.
- **Ethereum mainnet** means the public Ethereum network where relevant bridge, Channel-management, registration, and
  transaction records can be observed.
- **TON** means the token used with the relevant bridge and Channel workflows. These Terms do not state that TON itself
  becomes private, anonymous, or untraceable.
- **Ethereum Account** means the user's externally controlled Ethereum wallet account used to sign transactions and pay
  Ethereum mainnet gas.
- **Self-Custody** means that the user, not any Provider Party or Channel Operator, controls wallet access, keys, secret
  material, and transaction decisions.
- **Private Note** means a Channel-local private application record that may be transferred, redeemed, or used inside
  Tonnel. A Private Note is not a separate asset that an exchange can receive as a deposit.
- **Bridge** means the Ethereum mainnet smart-contract path through which public deposits, withdrawals, and related
  accounting updates are recorded.
- **Channel Provider** means the person or entity that provides or operates Channel-specific services for a Channel,
  including Channel-scoped observer services or workspace mirror services when those services are registered on-chain or
  otherwise made available for that Channel.
- **Official Public Observer** means a public observer service registered in a Channel's on-chain metadata or otherwise
  made available by that Channel's Channel Provider for that Channel. An Official Public Observer is Channel-scoped and
  is not a Tonnel-wide default observer for every Channel.
- **Official Workspace Mirror** means a workspace mirror URL registered in a Channel's on-chain metadata or otherwise
  made available by that Channel's Channel Provider for that Channel. An Official Workspace Mirror is Channel-scoped and
  is not a Tonnel-wide default mirror for every Channel.
- **Provider** means Jehyuk Jang, the individual who officially makes the Service available. The Provider's public
  privacy and notice contact is `cjhyuck213@gmail.com`. The Provider's stated jurisdiction is Singapore. The Provider's
  residential address is not published in the Privacy Notice or these Terms.
- **Provider Parties** means the Provider and the Provider's affiliates, contractors, agents, service providers, and
  authorized representatives, to the extent each acts within an authorized Service-related role. Provider Parties do not
  include Tokamak Network PTE. LTD. unless a separate binding Service document expressly includes it.
- **Tokamak Network PTE. LTD.** means a separate software contributor and licensor associated with Tokamak private app
  channel source code, Tokamak private DApp packages, upstream Tokamak zk-EVM tooling, and related repository materials.
  For Tokamak-controlled repositories, package registries, published artifacts, token infrastructure, bridge
  infrastructure, or upstream tooling that is not operated by the Provider, Tokamak Network PTE. LTD. is a Third-Party
  Service or infrastructure/tooling provider. Tokamak Network PTE. LTD. is not the Provider, does not accept Provider
  obligations, and does not provide custody, recovery, legal, tax, compliance, wallet, RPC, or user-support services
  through these Terms.
- **Channel Operators** means persons or entities that create, configure, administer, publish policies for, publish
  recovery metadata for, or otherwise operate a Channel.
- **Channel Operation Abandonment** means an on-chain Channel state initiated by the Channel leader that immediately
  disables new Channel joins and new `deposit-channel` actions for that Channel while leaving note activity,
  `redeem-notes`, `withdraw-channel`, and `exit-channel` unrestricted by that abandonment state.
- **Third-Party Services** means wallets, RPC providers, exchanges, explorers, analytics providers, browsers, package
  registries, operating systems, cloud services, and other services not controlled by the Provider Parties.
- **User-Controlled AI Agent** means an AI tool, assistant, or automated system selected, configured, or used by the user
  to interpret Service output or assist with Service use.
- **Official Machine-Readable Output** means JSON or similar structured output generated by the CLI or another official
  Service interface for software tools or User-Controlled AI Agents.
- **Privacy Notice** means the Provider's published privacy notice for the Service.

### 2. Product boundary

- These Terms govern access to and use of the Service.
- The Service includes the Private-State DApp, Tonnel, The Great First Channel, Bridge workflows, the CLI, official
  Tonnel-level documentation, official examples, official deployment artifacts, official proof-runtime artifacts, and
  related software or interfaces officially made available by the Provider. Channel-scoped observer services and
  workspace mirror services are part of the Service only for the Channel to which they are registered or otherwise made
  available by the applicable Channel Provider.
- Observer services and workspace mirror services are Channel-scoped. The URL for a Channel's observer or workspace
  mirror is read from that Channel's on-chain metadata when registered. A URL shown in documentation for a specific
  Channel is a Channel-specific example and is not a Tonnel-wide default for every Channel.
- For The Great First Channel, Jehyuk Jang is both the Provider and the Channel Provider. That does not make The Great
  First Channel's observer or workspace mirror a default observer or mirror for other Channels.
- Tonnel is the branded name for Tokamak Private App Channels.
- Tonnel is an opt-in private application-channel system used from a Self-Custody Ethereum Account.
- The Great First Channel is a Channel within Tonnel.
- Tonnel does not alter TON transfer rules on Ethereum mainnet.
- Through the Service, Provider Parties do not provide exchange deposit services, exchange withdrawal services,
  brokerage, custodial wallet services, hosted transfer services, asset recovery services, compliance services, or tax
  services.
- The Service is made available as open software and public-good infrastructure. Provider Parties do not operate the
  Service as a fee-generating custodial, brokerage, exchange, hosted transfer, or paid asset-management service.
- Join Tolls paid through the Service must not be monetized by Provider Parties. The final Terms must describe the
  selected policy as a burn-address transfer of the non-refundable Join Toll portion to
  `0x000000000000000000000000000000000000dEaD`, not as a TON total-supply reduction.
- The final Terms and user-facing documents must state that the Bridge default Join Toll refund policy may be updated,
  that each Channel fixes its own Join Toll refund policy at Channel creation, and that later Bridge default policy
  updates do not automatically rewrite an existing Channel's fixed policy.
- The final Terms and user-facing documents must direct users to verify the Bridge default policy through
  `BridgeCore.defaultJoinTollRefundCutoff*` and `BridgeCore.defaultJoinTollRefundBps*`, and to verify a specific
  Channel's fixed policy through that Channel's `ChannelManager.joinTollRefundCutoff*` and
  `ChannelManager.joinTollRefundBps*`. The remaining non-refundable portion is transferred to
  `0x000000000000000000000000000000000000dEaD` on Channel exit.
- The final Terms and user-facing documents must state that a Channel leader may initiate Channel Operation Abandonment.
  Once initiated on-chain, the affected Channel immediately rejects new joins and new `deposit-channel` actions. Other
  note activity, `redeem-notes`, `withdraw-channel`, and `exit-channel` remain available subject to ordinary proof,
  balance, and registration requirements.
- Nothing in these Terms is a determination of the regulatory status of any person, entity, software, transaction,
  network, token, or service under applicable law.
- Private Notes are Channel-local application records. They are not separate exchange-depositable assets.
- Exchange-facing TON transfers, Ethereum mainnet bridge deposits, and Ethereum mainnet bridge withdrawals remain public
  or observable through Ethereum mainnet records.

### 3. Acceptance and eligibility

- By submitting the required acceptance confirmation or by clicking an acceptance control after these Terms are
  presented, the user accepts these Terms.
- If the user does not accept these Terms, the user must not access, install, or use the Service.
- The user represents that the user has legal capacity to accept these Terms.
- If the user acts for an organization, the user represents that the user has authority to bind that organization.
- The user represents that use of the Service is not prohibited by laws applicable to the user.
- The user represents that use would not violate applicable sanctions, export control, anti-money laundering,
  counter-terrorist financing, securities, commodities, tax, data-protection, or other applicable laws.
- The Service is based on public blockchain infrastructure. Provider Parties may not have a technical method to identify,
  screen, or block every natural person or legal entity that attempts to use the Service. If account-level restrictions
  are implemented, they may block Ethereum Accounts or contract interactions, not necessarily the real-world person or
  entity behind an address.

### 4. Public Ethereum mainnet records

- Ethereum mainnet transactions are public by design.
- Bridge deposits and withdrawals recorded on Ethereum mainnet include or reveal Ethereum Accounts, contract addresses,
  token amounts, transaction hashes, block numbers, timing, and related event data.
- Public Channel records can include Channel creation, Channel joining, identity registration, note-receive public key
  registration, Channel accounting updates, and technical records such as note commitments, nullifiers, encrypted
  note-delivery events, accepted transitions, and root updates.
- Gas-paying accounts and transaction submitters are visible on Ethereum mainnet when they submit public transactions.
- The Service must not be used or described as a way to hide exchange-facing TON transfer records.

### 5. Private application-state limits

- Tonnel is designed so public contract state does not, by itself, reconstruct some internal Private Note
  sender-recipient relationships, Private Note plaintext, or Private Note provenance by default.
- Tonnel does not make all user activity secret.
- Public events, metadata, timing, amounts, user behavior, Third-Party Services, wallet software, RPC providers, browser
  behavior, user disclosure, or compromised devices may reveal information.
- No privacy, anonymity, unlinkability, confidentiality, exchange acceptance, compliance result, legal result, tax result,
  regulatory outcome, or third-party acceptance of the user's explanation of asset history is guaranteed.

### 6. Self-custody, secrets, and no recovery method

- The Service is designed for Self-Custody use.
- Provider Parties and Channel Operators do not possess, control, store, or recover the user's Ethereum private keys,
  seed phrases, wallet secrets, spending keys, viewing keys, source files, backup files, or Private Note plaintext.
- The user is solely responsible for securing the user's devices, wallet software, operating system, files, backups,
  passwords, private keys, seed phrases, wallet secrets, spending keys, viewing keys, and equivalent secret material.
- If all required copies of a private key, seed phrase, wallet secret, spending key, viewing key, source file, backup
  file, or other required recovery material are lost, no recovery method exists for the affected access, Private Notes,
  funds, evidence, or disclosure capability.
- Provider Parties, Channel Operators, support channels, websites, and User-Controlled AI Agents do not need the user's
  private keys, seed phrases, wallet secrets, spending keys, viewing keys, or equivalent secrets to provide ordinary
  Service access, support, explanations, or guidance.
- The user must not share private keys, seed phrases, wallet secrets, spending keys, viewing keys, or equivalent secrets
  with any User-Controlled AI Agent, Provider Party, Channel Operator, support channel, website, or third party.

### 7. Prohibited use

The user must not use the Service for:

- money laundering,
- terrorist financing,
- sanctions evasion,
- regulatory evasion,
- illegal gambling,
- fraud,
- theft,
- ransomware,
- market manipulation,
- tax evasion,
- criminal-proceeds concealment,
- exchange-monitoring evasion,
- unauthorized access,
- cybersecurity abuse,
- harassment, threats, or abuse of any person,
- infringement of intellectual-property, publicity, privacy, or data-protection rights,
- any activity prohibited by applicable law.

The user must not attempt to use Tonnel to make an unlawful transaction appear lawful or to conceal the source,
ownership, control, or destination of assets.

### 8. User responsibilities

- The user is solely responsible for determining whether the user's use of the Service is lawful.
- The user is solely responsible for wallet selection, network selection, RPC selection, Channel selection, transaction
  parameters, amounts, recipients, note selection, fees, failed transactions, wrong-network use, wrong-address use, and
  irreversible confirmed transactions.
- The user is solely responsible for preserving source files, wallet-secret files, backup files, evidence files,
  transaction records, and disclosure material that the user may later need.
- The user is solely responsible for preserving local evidence needed for selective disclosure, exchange review, tax
  records, accounting records, disputes, audits, investigations, or any other explanation of asset history or Private
  Note ownership.
- The user must review applicable Channel policy before joining a Channel.
- The user must use only trustworthy software, package sources, websites, wallets, RPC providers, and devices.

### 9. Channel policy and Channel Operator limitations

- Joining a Channel means accepting that Channel's policy snapshot.
- Channel policy may include Join Tolls, refund rules, administrative roles, operator roles, backup or recovery information
  expectations, monitoring practices, fee rules, or other operating rules.
- Channel Operators may publish public metadata, policy information, event records, or recovery information.
- Channel Operators do not control the user's Ethereum Account or user secrets.
- Channel Operators do not guarantee recovery of lost user secrets, lost Private Notes, lost evidence, failed
  transactions, Third-Party Service failures, or rejected exchange deposits.

### 10. Channel-scoped observers, monitoring, and evidence

- Channel Providers may provide Channel-scoped Official Public Observers. When a Channel's observer URL is registered
  on-chain, users can verify that URL through the Channel's on-chain metadata and through official CLI or Monitoring
  Packet views that read that metadata.
- For The Great First Channel, the current registered observer URL is `https://observer.tonnel.io`. That URL is the
  observer for The Great First Channel and is not a Tonnel-wide observer URL for all Channels.
- An Official Public Observer may display public Ethereum mainnet records, public Channel records, accepted transitions,
  commitments, nullifiers, encrypted note-delivery events, accounting updates, and related monitoring data for the
  Channel it observes.
- An Official Public Observer is not intended to receive or display user secrets. It displays only records available to
  it and does not guarantee that every fact needed for legal, accounting, tax, exchange, asset-history, or compliance
  review is available.
- Exchanges, analytics providers, regulators, Channel Providers, Channel Operators, users, and other observers may
  independently monitor Ethereum mainnet and public Channel records.
- The user may need to preserve local evidence to explain asset history, transaction history, Private Note ownership, or
  facts the user chooses to prove.
- Selective disclosure depends on implemented software features and on records preserved by the user.

### 11. Third-party services

- The Service may require or interact with Third-Party Services.
- Provider Parties do not control Third-Party Services and are not responsible for their security, availability,
  correctness, fees, privacy practices, data retention, terms, sanctions screening, account restrictions, transaction
  policies, or failures.
- The user is responsible for reviewing and complying with Third-Party Service terms.

### 12. Privacy and data

- Public blockchain records are public and may be copied, indexed, analyzed, or retained by any person.
- The Official Public Observer may display public blockchain records and public Channel records.
- Provider Parties may operate websites, public observer services, software repositories, package distribution channels,
  support channels, or other official interfaces that process logs, device information, network information, usage data,
  contact information, or other data.
- Provider Parties process certain data through official interfaces as described in the Privacy Notice.
- The initial Privacy Notice publication location is the GitHub repository document
  `docs/dapps/private-state/privacy-notice.md`.
- Third-Party Services may collect or process user data under their own terms and privacy policies.

### 13. No professional advice

- Provider Parties do not provide legal, tax, accounting, financial, investment, trading, compliance, sanctions, or
  regulatory advice through the Service or Official Machine-Readable Output.
- Information provided through the Service or Official Machine-Readable Output is for operational and informational
  purposes only.
- User-Controlled AI Agents are selected, configured, or used by the user. They are not agents, representatives, service
  providers, or support providers of Provider Parties unless an official Service document expressly says otherwise.
- Provider Parties do not control and are not responsible for User-Controlled AI Agents.
- The user is responsible for reviewing any recommendation, explanation, or action proposed by a User-Controlled AI Agent.
- The user should consult qualified professionals before making legal, tax, accounting, financial, compliance, sanctions,
  or regulatory decisions.

### 14. Risk disclosures

- Public blockchain systems, smart contracts, bridges, zero-knowledge systems, cryptographic software, wallets, and RPC
  providers involve significant operational, technical, security, market, regulatory, and legal risks.
- Transactions recorded on Ethereum mainnet may be irreversible.
- Software bugs, user mistakes, compromised devices, malicious third parties, governance actions, protocol upgrades,
  network congestion, RPC failure, bridge failure, smart-contract failure, cryptographic implementation defects, or
  changes in law may cause loss, delay, rejected transactions, unavailable services, or loss of access.
- Zero-knowledge proof systems, proving circuits, verifier contracts, CRS or proving artifacts, proving runtimes,
  local proof generation, proof input construction, and proof verification can contain defects, incompatibilities, or
  operational failures.
- Public observer services and indexing systems can be delayed, incomplete, unavailable, misconfigured, inconsistent
  with a user's local state, or insufficient for legal, accounting, tax, exchange, audit, or compliance review.
- Digital assets may be volatile and may lose value.
- The user assumes all risks permitted by applicable law.

### 15. No warranties

- The Service is provided "as is" and "as available" to the maximum extent permitted by applicable law.
- No Provider Party warrants that the software or services will be uninterrupted, secure, error-free, accurate, complete,
  compatible, available in any jurisdiction, accepted by any exchange, or suitable for any particular purpose.
- No Provider Party warrants any token value, transaction result, privacy result, legal result, regulatory result,
  compliance result, tax result, accounting result, third-party acceptance of the user's asset-history explanation, or
  selective-disclosure result.

### 16. Limitation of liability

- The Service is non-custodial open software and public-good infrastructure, and is not operated for Provider Party
  Service revenue. The user accesses and uses the Service at the user's own risk to the maximum extent permitted by
  applicable law.
- To the maximum extent permitted by applicable law, Provider Parties are not liable for indirect, incidental, special,
  consequential, exemplary, punitive, or similar damages.
- To the maximum extent permitted by applicable law, Provider Parties are not liable for lost profits, loss of data, lost
  secrets, failed transactions, wrong transactions, loss of access, loss of assets, loss of evidence, business
  interruption, Third-Party Service failures, exchange actions, regulatory actions, tax consequences, user error, device
  compromise, or unauthorized access.
- To the maximum extent permitted by applicable law, Provider Parties are not liable for the user's access to, use of,
  inability to use, or reliance on the Service.
- Join Tolls and other Service fees, if any, must not be described as Provider Party revenue unless an implemented
  protocol, treasury, or operating flow actually routes value to Provider Parties. If the implemented protocol burns any
  Join Toll or non-refunded fee amount, the burned amount does not create a custodial, refund, credit, account-balance,
  or revenue-sharing relationship between the user and Provider Parties.
- Nothing in these Terms excludes or limits liability that cannot be excluded or limited under applicable law, including
  liability for fraud, willful misconduct, gross negligence, death, or personal injury where such exclusion or limitation
  is not permitted.

### 17. User indemnity

- To the maximum extent permitted by applicable law, the user must indemnify, defend, and hold harmless the Provider
  Parties from claims, damages, losses, liabilities, penalties, costs, and expenses arising from the user's breach of the
  Terms, unlawful use, misuse, violation of third-party rights, interaction with Third-Party Services, or use of the
  Service on behalf of another person or organization.

### 18. Changes to terms and renewed acceptance

- Provider Parties may update these Terms.
- If the current Terms differ from the Terms previously accepted by the user, the user must accept the current Terms
  before continuing to use terms-gated Service operations.
- Renewed acceptance may be collected only after the current Terms are displayed to the user.
- Terms-gated Service operations must compare the current `termsVersion` and deterministic `termsHash` against the
  user's stored acceptance record.
- A valid acceptance record must include the accepted terms version, deterministic terms hash, acceptance timestamp,
  CLI package version, and acceptance source.
- If no acceptance record exists, or if the stored version or hash is stale, the Service must reject terms-gated
  operations until the current Terms are displayed and the user submits the required explicit acceptance phrase or
  acceptance control.
- The user must not rely on Official Machine-Readable Output or a User-Controlled AI Agent to accept changed Terms on the
  user's behalf.

### 19. Suspension, discontinuation, and software changes

- Provider Parties may modify, suspend, discontinue, or stop supporting software, documentation, public observer services,
  deployment artifacts, examples, or related services.
- Open-source smart contracts and public blockchain records may continue to exist independently of any supported
  interface.
- Provider Parties cannot reverse public Ethereum mainnet transactions or recover user secrets.

### 20. Governing law, venue, dispute resolution, and notices

- These Terms are governed by the laws of Singapore, excluding conflict-of-law rules.
- Subject to non-waivable rights under applicable law, disputes arising from or relating to these Terms or the Service
  will be resolved in the courts located in Singapore.
- These Terms do not require arbitration and do not include a class-action waiver, collective-action waiver,
  representative-action waiver, or jury-trial waiver.
- Provider Parties may provide notices through official Service interfaces, official websites, official repositories,
  release notes, email, or other contact methods stated in these Terms.
- These Terms do not limit any non-waivable consumer rights or mandatory local-law rights that apply in the user's
  jurisdiction.

## User-Controlled AI Agent Strategy for JSON Mode

JSON mode exists so a User-Controlled AI Agent can help the user complete the minimum safe next action without collecting
secrets, accepting legal terms, or requiring the user to understand protocol internals first.

### Required `install --json` behavior

`private-state-cli install --json` must not install Service-facing CLI components when terms acceptance is missing and
must not accept Terms on the user's behalf.

It should return structured output that includes:

- `terms_required: true`,
- `terms_source: "private-state-cli install"`,
- `terms_acceptance_flow: "browser_localhost_interactive"`,
- `terms_acceptance_actor: "human_user_only"`,
- `terms_refs`, containing section numbers from the installed terms document,
- `terms_acceptance_action: "accept_terms_and_continue_installation_button"`,
- a directive that the User-Controlled AI Agent must instruct the user to run interactive `private-state-cli install`
  directly and let the browser-based local Terms page open,
- a directive that the User-Controlled AI Agent must summarize the Terms before the user accepts,
- a directive that the User-Controlled AI Agent must not ask the user to disclose private keys, seed phrases, wallet
  secrets, spending keys, viewing keys, or equivalent secrets,
- a directive that the User-Controlled AI Agent must not click browser acceptance controls, submit the browser acceptance
  page, or type fallback acceptance phrases for the user.

The JSON output should identify referenced terms as terms-document section numbers, for example:

```json
{
  "ok": false,
  "next_action": "human_interactive_install_required",
  "terms_required": true,
  "terms_source": "private-state-cli install",
  "terms_acceptance_flow": "browser_localhost_interactive",
  "terms_acceptance_actor": "human_user_only",
  "terms_refs": ["1", "2", "3", "4", "5", "6", "7", "8", "10", "11", "12", "13", "14", "15", "16", "17", "18", "19", "20"],
  "terms_acceptance_action": "accept_terms_and_continue_installation_button",
  "agent_directives": [
    "Explain the referenced terms sections to the user before interactive install.",
    "Direct the user to run private-state-cli install and complete the browser-based local Terms page personally.",
    "Do not collect or display the user's secret material.",
    "Do not click browser acceptance controls or type fallback acceptance phrases for the user."
  ]
}
```

### Required `help guide --json` behavior

`help guide --json` should continue to serve User-Controlled AI Agents, but legal and safety guidance must refer to
canonical section numbers rather than duplicating full terms text. This prevents the machine-readable guide from drifting
away from the human-facing Terms.

For each guided setup task, the JSON output should include:

- the minimum safe next action,
- the exact CLI command or command family needed by the user,
- the related terms section numbers,
- the related `agents.md` guidance section numbers if applicable,
- a directive that the User-Controlled AI Agent must explain user-facing warnings in ordinary language before the user
  acts,
- a directive that the User-Controlled AI Agent must not request or handle secret material.

## Human Acceptance Strategy

Interactive `private-state-cli install` should use browser-based Terms acceptance as the primary human flow:

1. Start a localhost-only Terms acceptance server bound to `127.0.0.1` on an ephemeral port.
2. Generate a high-entropy one-time nonce and include it in the local acceptance URL.
3. Open the user's default browser to the local Terms page and also print the local URL in the terminal if automatic
   browser opening fails or the user needs to copy it manually.
4. Display only the current terms version, a short plain-language instruction, and the full canonical Terms text in the
   browser page.
5. Make the only browser acceptance action an explicit button such as `Accept Terms and Continue Installation`.
6. After the browser sends the nonce-protected local acceptance callback, immediately print
   `Terms accepted in browser. Starting installation...` in the terminal before any artifact download, runtime install,
   deployment artifact materialization, or other long-running install step begins.
7. Record the accepted version, hash, timestamp, CLI package version, acceptance source, Terms coverage metadata, and
   browser-local acceptance method in the user's Service state.
8. Proceed with installation only after the browser acceptance callback has been received, validated, persisted, and
   acknowledged in the terminal.

The existing terminal prompt should become the non-browser fallback for environments where a local browser cannot be
opened or where the user explicitly requests terminal-only acceptance. This fallback must display the full Terms once,
require one explicit acceptance phrase, and keep the same Terms coverage persistence and immediate acknowledgement
behavior.

The human flow should not require the user to understand technical implementation details before accepting. Definitions
must be available at the top of the Terms, and the CLI should use plain labels such as "Ethereum mainnet", "Channel",
"Private Note", "wallet secret", and "Official Public Observer" consistently.

Internal Terms coverage groups:

| Category ID | Category title | Terms sections |
|---|---|---|
| `scope-and-eligibility` | Service scope, product boundary, acceptance, and eligibility | 1, 2, 3 |
| `public-records-and-privacy-limits` | Public Ethereum mainnet records and private application-state limits | 4, 5, 10 |
| `self-custody-and-secrets` | Self-custody, secrets, no recovery method, and user responsibilities | 6, 8 |
| `prohibited-use-and-third-parties` | Prohibited use and Third-Party Services | 7, 11, 12, 13 |
| `risks-and-liability` | Risk disclosures, no warranties, limitation of liability, and user indemnity | 14, 15, 16, 17 |
| `changes-and-disputes` | Changes to Terms, Service changes, governing law, venue, and notices | 18, 19, 20 |

These groups are for internal coverage tracking and JSON Terms references only. They should not be presented as separate
human acceptance steps. Browser mode should use one accept button, and terminal fallback mode should use one explicit
acceptance phrase. User-Controlled AI Agents must not click browser acceptance controls or type fallback acceptance
phrases for the user.

## Documentation and Terms Finalization Plan

Code implementation must not begin until this section is complete, except for non-shipping technical spikes that do not
create public terms behavior. The next planned work is to finalize the Service terms and supporting documents first.

### Phase 1: Freeze service scope and document set

- Confirmed Service scope: the Terms govern the Private-State DApp, Tonnel, The Great First Channel, Bridge workflows,
  CLI, Official Public Observer, and official Service documentation.
- Confirmed official document set for pre-implementation finalization: Terms, CLI README, human `help guide`,
  `help guide --json`, `agents.md`, public observer notes, and privacy notice.
- Privacy notice is included in the document set. The initial standalone Privacy Notice draft is published at
  `docs/dapps/private-state/privacy-notice.md`, while the Service scope includes the hosted Official Public Observer,
  included Service web surfaces, support channels, logs, package distribution, and other interfaces that can process
  personal data. Treat Privacy Notice review and finalization as part of Phase 1 rather than a later decision.
- Record privacy notice inputs during Phase 1: official hosted surfaces, server logs, IP address handling, analytics,
  cookies, support/contact channels, package distribution logs, CLI telemetry if any, RPC provider metadata, retention,
  sharing, user rights, and Provider Party contact point.
- Confirm that all documents use "Ethereum mainnet" for the public chain boundary and avoid developer-only shorthand for
  ordinary users.
- Confirm that the documents consistently avoid privacy-coin, mixer, untraceable TON, exchange-monitoring avoidance, and
  asset-history concealment framing.

Current status:

- Created the repository Terms release-candidate document at `docs/dapps/private-state/terms.md` with fixed section
  numbering, Provider identity, Privacy Notice cross-reference, selected Join Toll language, selected Channel Operation
  Abandonment language, and selected dispute/liability/sanctions positions. Far-future counsel review remains recorded
  separately from the current release-candidate text.
- Updated the public-document drafting rule: public documents must assume selected planning items are complete and must
  not include implementation-status assumptions. Removed implementation-condition wording from the Terms release
  candidate.
- Updated human `help guide`, CLI README, and `agents.md` wording for the selected prompt policy: public guide surfaces
  no longer instruct users or User-Controlled AI Agents to add per-command action-impact acknowledgement flags.
- Updated `help guide --json` agent guidance to include canonical Terms section references alongside indexed
  `agents.md` references.
- Extended `help guide --json` Terms references to include the Definitions section and clarified in `agents.md` that
  User-Controlled AI Agents must read the referenced Terms sections before advising users.
- Completed an additional Provider/Tokamak role-boundary wording pass for the private-state docs index and CLI README so
  Tokamak Network PTE. LTD. is not implied to be the Service Provider.
- Updated CLI command-reference and transaction-warning output so real-funds commands show warning summaries without
  exposing or requiring per-command action-impact acknowledgement flags. The install-time Terms gate and renewed
  acceptance mechanism are implemented in local source.
- Implemented the selected `uninstall` behavior: default `uninstall` preserves wallet spending-key and viewing-key files
  under the CLI secret root while deleting the rest of the local private-state CLI data, and
  `uninstall --include-wallet-keys` deletes every local private-state CLI file.
- Completed current-repository terminology pass for the root README, private-state DApp README, CLI README, human
  `help guide` strings, `help commands` metadata, fee-help descriptions, and `agents.md`.
- Completed current-repository framing pass for the same surfaces. The remaining occurrences of `L1`, `L2`, and
  `--join-toll` in those audited paths are command names, option names, contract names, JSON field names, code
  identifiers, or explicit agent instructions about when not to use developer shorthand with ordinary users.
- Terms counsel-facing review topics are deferred to a far-future review cycle by business-owner decision. The Privacy
  Notice content and initial GitHub repository publication location are drafted, and the repository-level final
  consistency review is complete.

### Immediate priority: Privacy Notice preparation

Privacy Notice preparation has been handled for the initial GitHub repository draft. The Service scope includes an
Official Public Observer, included Service web surfaces, support channels, logs, package distribution, and other
interfaces that can process personal data. The project must keep a finalized Privacy Notice in the repository before
shipping production terms behavior; any different publication strategy is deferred to a later business-owner or counsel
review decision.

Completed preparation checklist for the initial draft:

1. Inventory official surfaces:
   - Official Public Observer hosting and CDN.
   - Official websites or documentation hosting.
   - CLI package distribution, npm metadata, and release-download logs that Provider Parties can access.
   - Support/contact channels such as email, Discord, Telegram, GitHub issues, or forms.
   - Analytics, cookies, error reporting, uptime monitoring, logging, and abuse-protection tools.
   - CLI telemetry, if any.
   - RPC endpoints officially operated, proxied, recommended, or documented by Provider Parties.
2. For each surface, record data categories:
   - IP address, user agent, device/browser data, request path, timestamps, wallet addresses, transaction hashes,
     support messages, email or contact identifiers, analytics IDs, cookies, and public blockchain records.
3. For each data category, record purpose, retention, sharing, storage location, cross-border transfer, and deletion or
   access route.
4. Separate Provider Party processing from Third-Party Service processing. RPC providers, wallets, exchanges, explorers,
   package registries, analytics tools, and hosting providers must be described as third parties when Provider Parties do
   not control their collection or retention.
5. Draft Privacy Notice sections:
   - Scope and controller/provider identity.
   - Data collected directly from users.
   - Data collected automatically by official interfaces.
   - Public blockchain and public Channel records.
   - Official Public Observer records and limits.
   - Cookies, analytics, logs, and security monitoring.
   - Support/contact data.
   - Third-Party Services.
   - Retention.
   - International transfers.
   - User rights and contact route.
   - Security.
   - Changes to the Privacy Notice.
6. Add a Terms cross-reference to the final Privacy Notice publication location.

Surface inventory status after the current repository pass:

| Surface | Current evidence | Privacy Notice handling |
|---|---|---|
| Official Public Observer | `packages/apps/private-state/cli/lib/runtime.mjs` hardcodes `https://observer.tonnel.io`; monitoring docs identify the same deployed observer URL. The separate `/Users/jehyuk/repo/channel-workspace-mirror/` repository shows that the observer is a Next.js app deployed on Vercel, uses `@vercel/analytics`, serves public mirror and observer APIs through Vercel, stores indexed observer and mirror metadata in Neon, stores large mirror artifacts in Vercel Blob, and uses an EC2 worker for persistent CLI recovery, raw RPC history, observer sync, and mirror publishing. Vercel account/API checks confirm the project is on the Hobby plan, Observability Plus is not enabled, and no Vercel Log Drains are configured. | Treat as an official hosted surface operated by the individual Provider. The Privacy Notice must cover Vercel hosting/runtime request metadata, Vercel Web Analytics page-view data, Vercel Blob artifact access, Neon-stored public observer and mirror metadata, EC2 worker operational logs, public blockchain and Channel records displayed through the observer, and any logs available to the Provider. Runtime log retention is 1 hour under the confirmed Hobby plan. Vercel Web Analytics reporting window is 1 month under the confirmed Hobby plan. |
| Official documentation and repository pages | Root and CLI READMEs point users to GitHub-hosted documentation and repository pages. The Vercel account also contains a separate `tonnel-airdrop` project serving `tonnel.io`, `www.tonnel.io`, and `airdrop.tonnel.io`, but the audited private-state repository docs do not reference those domains as the private-state documentation host. The Provider has decided to include `tonnel.io` and `www.tonnel.io` in the current Service scope and to exclude `airdrop.tonnel.io` from the current Service scope. | Treat GitHub as the confirmed Third-Party Service for the audited private-state documentation and repository pages. Treat `tonnel.io` and `www.tonnel.io` as Vercel-hosted Tonnel web surfaces in the current Privacy Notice. Exclude `airdrop.tonnel.io` from the current Privacy Notice unless the Provider later adds it to the Service scope. The included Tonnel web surfaces use the same confirmed Vercel Hobby plan, 1 hour runtime-log retention, 1 month Web Analytics reporting window, no Observability Plus, and no Log Drains. |
| GitHub issues and repository support | CLI `package.json` uses `https://github.com/tokamak-network/Tokamak-zk-EVM-contracts/issues` as the bug-report URL. The Provider has also designated `t.me/tonnel_ethereum` as an official Telegram support channel. No separate support email, Discord, or form was found in the audited paths. | Treat GitHub issues and `t.me/tonnel_ethereum` as official support/contact channels that may include user-submitted wallet addresses, transaction hashes, logs, screenshots, Telegram handles, GitHub account identifiers, and contact identifiers. Treat GitHub and Telegram as Third-Party Services for their own account, metadata, and retention practices. |
| CLI package distribution | CLI `package.json` publishes `@tokamak-private-dapps/private-state-cli` to the public npm registry. The CLI also checks the npm registry for latest private-state CLI metadata. Public npm APIs confirm package metadata, public maintainer metadata, latest version metadata, and aggregate public download counts by period. | Treat npm as a Third-Party Service for package install/update metadata, download logs, and account-level registry data. The notice should disclose Provider access to public package metadata and aggregate public download counts. Do not state that Provider can access individual npm downloader logs; no confirmed npm source reviewed in this planning pass shows such access. |
| Public deployment artifact distribution | Root README states that bridge deployment artifacts and DApp registration artifacts are published to Google Drive. `packages/common/src/artifact-cache.mjs` downloads the public Drive artifact index and files. Official Google documentation confirms that Drive download events are audit-log events for supported Google Workspace administrators, not a general guarantee that an individual personal Drive file owner can see every public download. | Treat Google Drive as a Third-Party Service for artifact access/download metadata. The notice should disclose artifact-download requests, Drive-managed cookies or confirmation tokens, and Google-controlled Drive processing. Do not claim that the Provider can access individual public download logs unless the Provider later confirms a supported Google Workspace admin/audit setup for the artifact account. |
| Public CRS and proof-runtime artifact distribution | CLI README requires access to the public Groth16 CRS archive source and install mode downloads proof/runtime artifacts. `packages/groth16/lib/public-drive-crs.mjs` confirms that the public Groth16 MPC CRS archive source is a Provider-operated artifact publication surface hosted on Google Drive. Official Google documentation confirms that Drive download events are audit-log events for supported Google Workspace administrators, not a general guarantee that an individual personal Drive file owner can see every public download. | Treat the CRS/proof-runtime artifact publication surface as Provider-operated and Google Drive-hosted. The Privacy Notice must cover request metadata, artifact paths, timestamps, IP address/user agent if processed by Google Drive, retention, storage location, and Google Drive as the hosting provider. Do not claim that the Provider can access individual public download logs unless the Provider later confirms a supported Google Workspace admin/audit setup for the CRS artifact account. |
| User-selected RPC providers | CLI docs require `set rpc`; built-in presets and guidance mention Alchemy, Ankr, Chainstack, Chainnodes, and QuickNode. The user supplies the RPC URL. The Provider states that there is no Provider-operated or Provider-proxied RPC endpoint and all RPC endpoints are user-selected third-party RPC services. | Treat all RPC providers as user-selected Third-Party Services. The notice should explain that RPC providers can see request metadata and public blockchain queries, and should not state that Provider Parties operate, proxy, or receive RPC traffic. |
| Workspace mirror hosts | CLI supports Channel workspace mirror recovery from registered mirror URLs. Mirror URLs can be operated by Channel Operators or other parties. The Provider states that The Great First Channel has an official workspace mirror and that it is operated by the same individual Provider. | Treat The Great First Channel workspace mirror as an official Provider-operated surface. The notice should cover mirror manifest/checkpoint/delta requests, request metadata, Vercel/Vercel Blob access, Neon metadata, EC2 worker logs, and any Provider-accessible logs. For other Channels, treat mirror hosts as Channel Operator or Third-Party Services unless Provider operation is confirmed. |
| ETH/USD price lookup | `packages/apps/private-state/cli/lib/runtime.mjs` fetches ETH/USD price data from CoinGecko for fee display. | Treat CoinGecko as a Third-Party Service for CLI fee-estimation requests. The notice should disclose that request metadata may be sent when commands fetch ETH/USD price data. |
| Analytics, cookies, telemetry, error reporting, uptime monitoring, and abuse-protection tools | No private-state CLI telemetry was found in the audited CLI paths. The separate observer repository imports `@vercel/analytics/next` in `app/layout.tsx`, so the observer uses Vercel Web Analytics. Vercel account/API checks confirm Hobby plan, no Observability Plus, and no Vercel Log Drains. Google Drive download code handles Drive-provided cookies or confirmation tokens for third-party artifact downloads. | State that the CLI itself has no current first-party telemetry evidence, but the official observer uses Vercel Web Analytics and Vercel runtime logs. The notice must cover Vercel Analytics, Vercel runtime logs, Drive-managed cookies or confirmation tokens, and Google Drive/Vercel platform processing. Do not claim that no analytics, cookies, logging, or monitoring exists across the whole Service. |
| Local CLI workspace | CLI docs state that local artifacts, account secrets, wallet key files, channel workspaces, and proof outputs are stored under `~/tokamak-private-channels/`. | Treat local workspace files as user-controlled local data, not Provider Party collection, unless the user submits them through support, evidence export, issue reports, or another official interface. The Privacy Notice should distinguish local-only data from data transmitted to official or third-party services. |

Business-owner confirmations to preserve in the Privacy Notice draft:

- The Provider is the individual business owner, not Tokamak Network PTE. LTD.
- The Provider's public identity is Jehyuk Jang.
- The Provider's public privacy and notice contact is `cjhyuck213@gmail.com`.
- The Provider's stated jurisdiction is Singapore.
- The Provider's residential address is not published. If a physical notice address becomes legally or operationally
  required, use a non-residential route such as a P.O. box, business mailing address, registered agent, or counsel
  address.
- Google Drive artifact-folder ownership or publication metadata may be Provider-accessible through the artifact account,
  but individual public download logs must not be described as Provider-accessible unless a supported Google Workspace
  admin/audit setup is later confirmed for that artifact account.
- npm package metadata and aggregate download counts are Provider-accessible through public npm APIs. Individual npm
  downloader logs or private owner-only analytics must not be described as Provider-accessible unless npm later exposes
  such data through a confirmed account feature.
- The public CRS/proof-runtime artifact publication surface is operated by the individual Provider through Google Drive.
  Google Drive itself may process artifact access metadata; Provider access to individual public download logs is not
  confirmed for a personal file-owner model.
- The Great First Channel has an official workspace mirror operated by the individual Provider.
- The Provider does not operate or proxy RPC endpoints; all RPC endpoints are user-selected third-party RPC services.
- Official support channels are GitHub issues and the Telegram channel `t.me/tonnel_ethereum`.
- The current Service scope includes `tonnel.io` and `www.tonnel.io`, but excludes `airdrop.tonnel.io`.
- The initial Privacy Notice publication location is the GitHub repository document
  `docs/dapps/private-state/privacy-notice.md`. The CLI README should mention and reference that document only. A
  `tonnel.io` publication may be added later.
- The Provider has decided to publish the current confirmed operating state as-is in the Privacy Notice. If the Provider
  later changes operational settings such as EC2 raw-history deletion, EBS encryption, backup policy, observer cadence,
  Vercel plan, analytics, or logging, the Privacy Notice must be updated.

Confirmed deployment and account settings:

- `observer.tonnel.io` is a Vercel-hosted Next.js deployment for the `mirror-the-great-first-channel` project. The
  deployed domain, production deployments, and recent runtime logs are visible through the Vercel project tools available
  to the Provider.
- Vercel account/API checks confirm that the Vercel team is on the Hobby plan.
- Vercel API checks confirm that Observability Plus is not enabled for the team.
- Vercel API checks confirm that no Vercel Log Drains are configured for the team.
- The observer repository imports `@vercel/analytics/next` in `app/layout.tsx`; the Official Public Observer therefore
  uses Vercel Web Analytics.
- Vercel's public runtime-log documentation lists dashboard-visible request details such as method, path, timestamp,
  status, host, request ID, user agent, search parameters, region, cache status, function metadata, deployment metadata,
  and outgoing request data. The same documentation states that Hobby runtime-log retention is 1 hour.
- Vercel's public Web Analytics pricing documentation states that Hobby Web Analytics has a 1 month reporting window.
- The observer and workspace mirror use Neon tables for `mirror_publish_history`, `observer_channels`,
  `observer_events`, observer sync state, runtime RPC configuration, and indexer run state. The repository contains no
  automatic deletion policy for observer tables. The existing cleanup command is dry-run only and only reports old mirror
  publish rows outside the latest retained checkpoints.
- Vercel Storage API checks confirm that the Great First Channel mirror Neon database is a Neon Launch-plan resource in
  region `iad1`.
- Large mirror artifacts are stored in Vercel Blob and served through redirects from the Vercel app. Vercel Storage API
  checks confirm that the mirror Blob store is in region `iad1`. The repository-managed cleanup command is dry-run only,
  so Blob objects currently have no repository-managed automatic deletion policy.
- The persistent worker is an EC2/systemd worker. It stores the private-state CLI workspace and raw RPC history on the
  worker filesystem, uses systemd journal logs, and sends mirror publish result notifications through Telegram when
  configured. AWS API and host inspection confirm AWS region `ap-southeast-1`, availability zone `ap-southeast-1a`,
  instance type `t3.micro`, a 30 GB gp3 root EBS volume with `DeleteOnTermination=true`, no self-owned EBS snapshots for
  the worker volume, no AWS DLM lifecycle policies, and no AWS Backup plans. The inspected root EBS volume is not
  encrypted. Host inspection confirms the worker timer is enabled and active with `OnCalendar=*-*-* 07:00:00 UTC` and
  `OnUnitInactiveSec=3h`; this differs from earlier 5 minute observer-cadence documentation and must be treated as the
  current production setting until the operator changes it. Host inspection found no explicit journald retention
  override in `/etc/systemd/journald.conf`; archived and active journals used 175.3 MB at inspection time. The worker
  workspace under `/var/lib/channel-workspace-mirror` used 1.9 GB at inspection time and contained 160 raw RPC history
  files. There is no repository-managed automatic raw-history deletion policy.
- The public private-state deployment artifact index and deployment artifacts are downloaded from Google Drive through
  public Drive file IDs. `packages/common/src/artifact-cache.mjs` uses the public Drive download endpoint and handles
  Google Drive confirmation cookies or tokens when Google serves a download-warning page.
- The public Groth16 MPC CRS archive source is a Provider-operated artifact publication surface hosted on Google Drive.
  `packages/groth16/lib/public-drive-crs.mjs` reads public archive listings from Google Drive folder
  `1jAIBqV-KG6PxFPDFpgtg9PDIceDDqk6N` and downloads matching archive files by Drive file ID. Official Google
  documentation confirms that Drive download events can be available in Google Workspace admin audit logs for supported
  editions and administrators. It does not confirm that an individual personal Drive file owner can access individual
  public download logs.
- The public npm registry confirms `@tokamak-private-dapps/private-state-cli` package metadata and public download-count
  statistics. Public metadata currently exposes maintainer name `jehyuk` and contact email `cjhyuck213@gmail.com`.
  npm's public download-count API exposes aggregate package downloads by period, not individual downloader logs. No
  confirmed npm source reviewed in this planning pass shows Provider access to individual npm downloader logs.
- The Provider does not operate or proxy RPC endpoints for users. The observer worker has an operational RPC URL stored
  in Neon runtime configuration for observer sync, but end-user CLI RPC configuration remains user-selected third-party
  RPC.
- No first-party private-state CLI telemetry was found in the audited CLI paths. The CLI does contact Third-Party
  Services for package update checks, artifact downloads, CRS downloads, user-selected RPC, and CoinGecko ETH/USD fee
  lookup when relevant commands require those functions.

Privacy Notice data-category matrix:

| Surface | Data categories | Purpose | Retention status | Sharing, storage, and transfer | User access or deletion route |
|---|---|---|---|---|---|
| Official Public Observer at `observer.tonnel.io` | Vercel request metadata, Vercel Web Analytics data, public blockchain records, public Channel records, observer API paths, timestamps, user agent, search parameters, region, cache/function metadata, and Neon-stored observer metadata such as contract addresses, wallet addresses visible in public events, transaction hashes, block data, decoded event data, raw topics, and raw event data. | Serve public observer pages and APIs, monitor public Channel state, debug availability, and provide public monitoring for The Great First Channel. | Confirmed Vercel Hobby plan: runtime logs are retained for 1 hour; Web Analytics reporting window is 1 month; Observability Plus is disabled; Log Drains are not configured. Neon observer tables currently have no repository-managed deletion policy. | Vercel hosts the app and analytics; Neon stores indexed observer data in region `iad1`; Vercel may process hosting logs globally according to its service settings. Public blockchain data can be copied by anyone. | Privacy contact: `cjhyuck213@gmail.com`. Public blockchain records cannot be deleted by the Provider. Provider-controlled logs or database rows can be reviewed only within technical, legal, and operational limits after request verification. |
| Official workspace mirror for The Great First Channel | Mirror manifest/checkpoint/delta request metadata, public mirror paths, Vercel Blob URLs, Neon mirror publish rows, checkpoint block, recovery root vector hash, checkpoint hashes and sizes, leader metadata, publish timestamps, EC2 worker operational logs, raw RPC history paths, and Telegram mirror publish status messages. | Provide Channel workspace recovery, publish verified mirror checkpoints, and operate the public mirror needed by CLI recovery flows. | Mirror cleanup is currently dry-run only. The Neon mirror DB and Vercel Blob store are both confirmed in region `iad1`. Neon mirror rows and Blob objects have no repository-managed automatic deletion policy. EC2 runs in AWS region `ap-southeast-1` on a 30 GB gp3 root EBS volume with `DeleteOnTermination=true`; no self-owned snapshots, AWS DLM lifecycle policies, or AWS Backup plans were found for the worker. The inspected EBS volume is not encrypted. The current host timer uses a 3 hour observer cadence. Journald uses OS defaults with no explicit retention override; journals used 175.3 MB at inspection time. Raw RPC history has no repository-managed automatic deletion policy; 160 raw RPC history files were present at inspection time. | Vercel hosts route handlers; Vercel Blob stores artifacts; Neon stores mirror metadata; AWS EC2 stores worker state; Telegram receives publish status notifications when configured. | Privacy contact: `cjhyuck213@gmail.com`. Public mirror artifacts and public blockchain-derived data may be retained for recovery integrity. Provider-controlled operational logs or mirror metadata can be reviewed within technical, legal, and operational limits. |
| Public deployment artifact distribution on Google Drive | Public Drive file IDs, artifact index requests, artifact file download requests, Google Drive confirmation cookies or tokens when presented by Google, request metadata processed by Google, and artifact file metadata such as size and hash. | Distribute bridge deployment artifacts, DApp registration artifacts, ABI snapshots, CRS snapshots, source snapshots, and related public artifacts needed by the CLI. | Google Drive controls request metadata and retention. Individual public download-log access is not confirmed for the Provider's personal file-owner model; Google Workspace admin audit logs can include download events only for supported Workspace admin contexts. | Google Drive hosts files and processes downloads as a Third-Party Service. The Provider controls publication of the public artifact folder or files to the extent allowed by Google Drive. | Privacy contact: `cjhyuck213@gmail.com` for Provider-controlled publication issues. Google account, request metadata, and download-log rights must be handled under Google's own terms and privacy controls. |
| Public Groth16 MPC CRS and proof-runtime artifacts on Google Drive | Public CRS folder listing requests, archive file download requests, Drive file IDs, Google Drive confirmation cookies or tokens when presented by Google, archive names, CRS compatibility versions, archive hashes, and artifact provenance metadata. | Install or verify proof runtime artifacts required for proof-backed CLI operation. | Google Drive controls request metadata and retention. Individual public download-log access is not confirmed for the Provider's personal file-owner model; Google Workspace admin audit logs can include download events only for supported Workspace admin contexts. Local installed CRS files are retained on the user's device until the user deletes them or uninstalls. | Google Drive hosts public CRS archives as a Third-Party Service. The Provider operates the artifact publication surface and can control public publication to the extent allowed by Google Drive. | Privacy contact: `cjhyuck213@gmail.com` for Provider-controlled artifact-publication issues. Google-controlled request metadata must be handled under Google's own terms and privacy controls. |
| npm package distribution | Public package metadata, maintainer metadata, package version metadata, aggregate public download counts, install/update request metadata processed by npm, and npm account metadata where npm makes it available to package owners. | Distribute the CLI, allow update checks, and publish package metadata. | Public npm APIs expose aggregate download counts by period and public package metadata. Individual downloader logs are not exposed by the confirmed public npm APIs and no confirmed npm source reviewed here shows Provider access to individual downloader logs. | npm hosts package tarballs and registry APIs as a Third-Party Service. Public metadata currently exposes maintainer name `jehyuk` and `cjhyuck213@gmail.com`. | Privacy contact: `cjhyuck213@gmail.com` for Provider-controlled package metadata. npm account, install, and registry metadata rights must be handled under npm's own terms and privacy controls. |
| GitHub repository, GitHub issues, and official Telegram support | GitHub account identifiers, issue comments, pull requests, logs or screenshots submitted by users, Telegram handles, Telegram messages, contact identifiers, wallet addresses, transaction hashes, and diagnostic files voluntarily submitted by users. | Provide support, receive bug reports, investigate incidents, and communicate Service status or operational help. | Retention is controlled by GitHub or Telegram unless the Provider copies data elsewhere. Provider-side retention policy for copied support records remains to be defined. | GitHub and Telegram are Third-Party Services. Support messages may be visible publicly if users post them in public GitHub issues or public Telegram channels. | Users should contact `cjhyuck213@gmail.com` for Provider-controlled support data. GitHub or Telegram account and message rights must be handled through those services. |
| User-selected third-party RPC providers | RPC URL selected by the user, public blockchain queries, `eth_getLogs` filters, block ranges, contract addresses, transaction submissions, wallet or transaction submitter addresses visible in public transactions, timestamps, IP address, and user agent or client metadata processed by the RPC provider. | Let the CLI read public blockchain state, recover workspaces, estimate fees, submit transactions, and monitor confirmations. | Provider does not control third-party RPC retention. The user's selected RPC provider controls its own logs and retention. | RPC providers are user-selected Third-Party Services. End-user RPC traffic is not operated or proxied by the Provider. | Users must use the selected RPC provider's privacy and support routes for provider-controlled logs. Provider can only help explain CLI configuration. |
| Observer worker operational RPC | Runtime RPC URL and scan parameters stored in Neon `indexer_runtime_config`, observer `eth_getLogs` and `eth_getBlockByNumber` requests, raw RPC history stored on the EC2 worker, sync state, indexer errors, and last-run status. | Operate the Official Public Observer and workspace mirror for The Great First Channel. | Neon runtime rows have no repository-managed deletion policy. EC2 runs in AWS region `ap-southeast-1`; the current host timer uses a 3 hour observer cadence. Journald uses OS defaults with no explicit retention override; journals used 175.3 MB at inspection time. Raw RPC history has no repository-managed automatic deletion policy; 160 raw RPC history files were present at inspection time. No self-owned EBS snapshots, AWS DLM lifecycle policies, or AWS Backup plans were found for the worker volume. The inspected EBS volume is not encrypted. | Neon stores runtime config and sync state in region `iad1`; the configured RPC provider processes observer sync requests; AWS EC2 stores worker state. | This is Provider-controlled infrastructure data. Requests can be sent to `cjhyuck213@gmail.com`, subject to public-record, security, operational, and legal limits. |
| CoinGecko ETH/USD price lookup | Fee-estimation HTTP request metadata processed by CoinGecko, including IP address, timestamp, and user agent or client metadata as handled by CoinGecko. | Display ETH/USD fee estimates for CLI fee-help flows. | Provider does not control CoinGecko retention. | CoinGecko is a Third-Party Service. | Users must use CoinGecko's privacy route for CoinGecko-controlled data. Provider can only explain when the CLI calls CoinGecko. |
| Local CLI workspace on the user's device | Local private keys or source files created by the user, wallet secret source files, local account aliases, wallet metadata, Private Note data, proofs, backups, recovery indexes, raw RPC history, and local evidence exports. | Let the user operate the Service from the user's own device and preserve data needed for recovery or selective disclosure. | Retained locally until the user deletes it or runs an uninstall/removal flow. Provider does not receive it unless the user sends it through support or another official interface. | Stored on the user's device under user-controlled paths such as `~/tokamak-private-channels/`. No Provider transfer occurs by default. | The user controls local deletion. The Provider cannot recover lost local secrets or delete files on the user's device. |
| Official documentation and source pages | Page request metadata, GitHub account data if signed in, documentation paths viewed, and any comments or issue content submitted by users. `tonnel.io` and `www.tonnel.io` are included Tonnel web surfaces, so Vercel request metadata and Web Analytics data for those surfaces must also be covered. `airdrop.tonnel.io` is excluded from the current Service scope. | Provide documentation, source references, release notes, support links, and included Tonnel web pages. | GitHub controls GitHub-hosted documentation retention. For `tonnel.io` and `www.tonnel.io`, the confirmed Vercel team settings are Hobby plan, 1 hour runtime-log retention, 1 month Web Analytics reporting window, no Observability Plus, and no Log Drains. | GitHub is the confirmed Third-Party Service for repository documentation and issues. `tonnel.io` and `www.tonnel.io` are Vercel-hosted under the same Provider-controlled Vercel team. | Users must use GitHub's privacy route for GitHub-controlled data. Provider-controlled contact remains `cjhyuck213@gmail.com`. |

Next Privacy Notice task:

- Completed the first Privacy Notice consistency review against the Terms definitions, Provider identity, Official
  Public Observer disclosures, support routes, Third-Party Service boundaries, confirmed deployment/account settings,
  EC2 worker disclosures, current 3 hour observer cadence, inspected unencrypted worker EBS volume, included
  `tonnel.io` and `www.tonnel.io` Service web surfaces, excluded `airdrop.tonnel.io`, and later-update rule. The review
  found no direct conflict in the drafted Privacy Notice. The only issues found were stale planning statuses that still
  treated the Privacy Notice draft, GitHub repository publication location, and Terms cross-reference as missing; those
  statuses have been corrected.

Current next step:

- Import the generated Safe Transaction Builder JSON into the current bridge owner Safe, review every
  target/method/calldata, collect the required 2-of-3 approvals, and execute the batch from the Safe.
- After Safe execution, regenerate final deployment artifacts and the Monitoring Packet from on-chain state before
  public documents represent the Join Toll burn-address transfer and Channel Operation Abandonment policies as deployed
  mainnet behavior.

### Phase 2: Complete pre-counsel redline and risk review

- Run the Pre-Counsel Redline and Risk Review Plan below.
- Produce a redlined Terms draft, risk register, counsel-question list, checklist mapping, and release-risk list.
- Resolve drafting issues that do not require counsel judgment.
- Mark issues that are current implementation blockers separately from issues deferred to far-future counsel review.

Current status:

- Completed an initial pre-counsel operational redline/risk review pass. See "Pre-Counsel Review Results" below.
- The review identified legal review topics and product consistency items. The legal review topics are deferred to a
  far-future counsel review cycle by business-owner decision. The current implementation blockers are product and
  deployment consistency items, especially final prompt-policy verification and final Terms/implementation consistency
  for the selected Join Toll burn-address transfer and Channel Operation Abandonment policies.

### Phase 3: Resolve open legal and business decisions

- Record the Provider Party decision: the Provider is Jehyuk Jang, an individual. The Provider's public privacy and
  notice contact is `cjhyuck213@gmail.com`, the Provider's stated jurisdiction is Singapore, and the Provider's
  residential address is not published. Tokamak Network PTE. LTD. is a separate software contributor/licensor and a
  Third-Party Service or infrastructure/tooling provider for Tokamak-controlled repositories, package registries,
  published artifacts, token infrastructure, bridge infrastructure, or upstream tooling not operated by the Provider. It
  must not be treated as the Provider unless it expressly assumes Provider obligations in a separate binding Service
  document.
- Use the recommended dispute strategy for an individual Provider: governing law and forum should default to Singapore,
  unless a later business-owner or counsel review decision selects a different jurisdiction with a sufficient connection.
  The clause must preserve mandatory consumer-law and local-court rights. Do not include arbitration, class-action
  waiver, collective-action waiver, representative-action waiver, or jury-trial waiver provisions in the current draft.
- Adopt the no-monetary-liability-cap approach for the current draft. The draft position is that Provider Parties do not
  operate the Service for Service revenue, do not monetize Join Tolls, do not provide custody or paid asset-management
  services, and are not liable for use of the Service to the maximum extent permitted by applicable law. The draft must
  still preserve non-waivable liability carveouts. For future Channel exits after implementation, the non-refundable Join
  Toll portion is sent to `0x000000000000000000000000000000000000dEaD`.
- Adopt generalized public wording for Join Toll refund schedules: the Bridge default policy may change, each Channel's
  policy is fixed at Channel creation, and users must verify the applicable policy through on-chain getters or official
  convenience views. Do not present one concrete refund schedule as universal for all Channels.
- Adopt a principles-based restricted-use and sanctions policy for the current draft. Do not name specific restricted
  jurisdictions, sanctions lists, or sanctions authorities in the current draft. Require users to comply with applicable
  sanctions, export-control, anti-money-laundering, counter-terrorist-financing, and other applicable laws. Record the
  technical constraint that the Service may not be able to block real-world users; future restrictions may be implemented
  at the Ethereum Account or contract-interaction level.
- Preserve the drafted Privacy Notice and GitHub repository publication location unless a later business-owner or
  counsel review decision requires changes.
- Adopt the prompt strategy that install-time Terms acceptance replaces all per-command `--acknowledge-action-impact`
  options, while `uninstall`, secret-bearing material exports, and plaintext note or evidence exports become
  interactive human-confirmation flows. Human and `--json` modes must still print concise command-specific information
  and warning summaries for every command that handles real funds.

Decision guide:

| Decision | Current status | How to decide |
|---|---|---|
| Provider Party | Selected: the Provider is Jehyuk Jang, an individual. Public privacy and notice contact is `cjhyuck213@gmail.com`. Stated jurisdiction is Singapore. Residential address is not published. | Use these Provider details in the Privacy Notice and Terms. Do not name Tokamak Network PTE. LTD. as Provider unless it expressly assumes provider obligations. |
| Developer vs provider split | Selected: Tokamak Network PTE. LTD. is separate from the Provider. | Define Tokamak Network PTE. LTD. as software contributor/licensor and Third-Party Service or infrastructure/tooling provider for Tokamak-controlled repositories, package registries, published artifacts, token infrastructure, bridge infrastructure, or upstream tooling not operated by the Provider. Do not make Tokamak Network responsible for Provider obligations unless it expressly assumes them in a separate binding Service document. |
| Global online forum | Strategy selected: use Singapore as the Provider-connected baseline jurisdiction with mandatory consumer-law carveouts. | Use a baseline governing law and forum connected to Singapore, but add mandatory consumer-law carveouts because global online users may retain local non-waivable rights. Far-future counsel review remains recorded. |
| Individual provider forum | Strategy selected: Singapore. | Use Singapore courts and Singapore law for the individual Provider model. Far-future counsel review remains recorded for notice handling, personal-liability exposure, and any tax/accounting issues tied to grants, sponsorships, reimbursements, operating expenses, or non-fee funding. |
| Bridge owner and upgrade authority | Completed: root bridge proxy ownership was migrated from the single EOA owner to an Ethereum mainnet Safe multisig. | The current root bridge proxy owner is `0xBE637160D21975EF1e0270D32Bfc547c2EA8DcC3`, a Safe multisig with a 2-of-3 threshold and no timelock. Safe signer recovery details are an off-repository Safe operations matter, not a public repository decision. |
| Liability cap | Selected: do not include a nominal monetary liability cap in the current draft. | Use broad liability exclusions to the maximum extent permitted by applicable law, explain that the Service is non-custodial open software/public-good infrastructure and not operated for Provider Party Service revenue, and preserve non-waivable liability carveouts for liability that cannot legally be excluded or limited. Far-future counsel review remains recorded, but the current business position is no monetary cap. |
| Restricted users | Selected: use a principles-based restricted-use and sanctions policy without naming specific jurisdictions, sanctions lists, or sanctions authorities in the current draft. | State prohibited uses and applicable-law compliance, including sanctions, export-control, anti-money-laundering, and counter-terrorist-financing compliance. Do not promise user-level blocking unless a real user-identification and access-control system exists. Preserve the technical constraint that future restrictions may operate only at the Ethereum Account or contract-interaction level. Far-future counsel review remains recorded for named-list questions. |
| Technical blocking | Constraint recorded. | Future blacklist features may block Ethereum Accounts or contract interactions, not necessarily real-world users. Terms and docs must not overstate user-level blocking. |
| Privacy Notice | Initial draft completed in `docs/dapps/private-state/privacy-notice.md`; initial publication location selected as GitHub repository documentation only. CLI README references the document. `tonnel.io` publication is deferred. | Review the draft against Terms definitions, Provider identity, Official Public Observer disclosures, support routes, and Third-Party Service boundaries before final Terms, guide, JSON mode, or implementation work. |
| Provider identity and privacy contact | Selected: Jehyuk Jang; `cjhyuck213@gmail.com`; Singapore; residential address not published. | Use the email address for privacy/contact and notice routing. Keep Telegram as an official support channel, not the sole privacy contact. If a physical notice address later becomes required, use a non-residential route such as a P.O. box, business mailing address, registered agent, or counsel address. |
| Arbitration and class-action waiver | Not included in the current draft. | Keep these provisions out for the current implementation. Far-future counsel review may revisit whether adding them is appropriate and enforceable enough for the individual Provider model and expected user jurisdictions. |
| Separate prompts | Selected: remove `--acknowledge-action-impact` from all commands, enforce install-time Terms acceptance, make `uninstall`, secret-bearing material exports, and plaintext note or evidence exports interactive confirmation flows, and print warning summaries for real-funds commands in both human and `--json` modes every time. | The guide, command reference, transaction-warning output, default key-preserving `uninstall`, `uninstall --include-wallet-keys`, wallet viewing-key/spending-key export confirmations, plaintext note/evidence export confirmation review, canonical Terms gate, and renewed acceptance mechanism are implemented in local source. |
| Channel Operation Abandonment | Selected: immediate on-chain abandonment state with no grace period. | Implement leader-only abandonment in the shared bridge/vault path so existing Channels, including `the-great-first-channel`, can have new joins and `deposit-channel` blocked after the leader initiates abandonment. Do not restrict note activity, `redeem-notes`, `withdraw-channel`, or `exit-channel` on-chain. CLI must error for join/deposit on abandoned Channels and warn for other Channel activities. |

### Phase 4: Finalize human-facing documents

- Finalize Terms text and section numbering. Repository release-candidate created at
  `docs/dapps/private-state/terms.md`; far-future counsel review remains recorded separately from the current
  release-candidate text.
- Completed repository-level final verification of human `help guide` text for ordinary users.
- Completed repository-level final verification of CLI README language explaining the Service terms and the purpose of
  `--json`.
- Completed an additional human-facing wording pass for Terms, CLI README, and command-reference output: install now
  has documented explicit human Terms acceptance, human command help no longer uses AI-agent-first fee wording,
  no-recovery wording says no recovery method exists, and the Terms definitions avoid unnecessary `L2` shorthand.
- Completed repository-level Phase 4 consistency verification for the current release-candidate documents and human
  guide output: Terms section numbering is contiguous, the Terms and Privacy Notice cover the checklist's public
  Ethereum mainnet boundary, Self-Custody, no-recovery, Official Public Observer, Third-Party Service, prohibited-use,
  and user-controlled disclosure themes, the CLI README RPC example now matches the recommended Ankr provider, and the
  README no longer uses chat-oriented wording in the User-Controlled AI Agent guidance section.
- Completed repository-level verification that Terms, Privacy Notice, CLI README, and human guide documentation explain
  public Ethereum mainnet records, public Channel records, Official Public Observer limits, Self-Custody, no recovery
  method, and Third-Party Service risk without contradicting the checklist's exchange-boundary and monitoring themes.
- Completed repository-level plain-language review for ordinary users and legal/compliance reviewers without weakening
  legal precision. Far-future counsel review remains recorded separately.

### Phase 5: Finalize machine-readable and agent-facing documents

- Completed repository-level final verification of the `help guide --json` output contract: it references canonical Terms
  section numbers and indexed `agents.md` sections, and it does not duplicate full legal text.
- Completed `install --json` behavior for the current pre-terms-gate implementation: JSON mode reports that
  interactive Terms acceptance is required, returns `installed: false`, and does not install artifacts.
- Completed User-Controlled AI Agent directive pass for warnings, prohibitions, public/private boundaries,
  Self-Custody, no recovery method, Third-Party Service risk, no professional advice, no warranties, liability limits,
  and Official Public Observer limits by adding `agents.md` item `E.3` and including it in every `help guide --json`
  `agentGuidance.refs` result.
- Confirmed and test-covered that Official Machine-Readable Output cannot accept Terms, renewed Terms, or
  secret-handling decisions for the user in the implemented `help guide --json` and `install --json` surfaces.

### Phase 6: Final documentation verification

- Verify that the final Terms still cover every relevant `checklist.md` item.
- Verify that the final Terms, README, human `help guide`, `help guide --json`, and `agents.md` do not conflict.
- Verify that human-facing wording is appropriate for ordinary users and legal/compliance reviewers.
- Verify that machine-readable guidance remains useful for User-Controlled AI Agents without handling secrets or accepting
  Terms for users.
- Freeze the canonical Terms text for implementation only after these checks pass.

Phase 6 repository-wide public-document review findings to resolve before public finalization:

- Resolved in local source: Terms and CLI README describe install-time Terms acceptance as required behavior, and human
  `install` now renders the Terms, persists an acceptance record, and enforces the deterministic `termsHash`.
- Resolved in local source: Terms describe Join Toll policy without hardcoding a universal refund schedule. The Bridge
  default policy may be updated, each Channel's policy is fixed at Channel creation, and official documents direct users
  to verify the applicable policy through on-chain getters or official convenience views.
- Resolved in local source: Terms describe Channel Operation Abandonment as an available on-chain state, and the bridge
  plus CLI now implement abandonment state, events, join/deposit rejection, and warnings. Generated Monitoring Packet
  JSON has been regenerated after the Safe-executed mainnet bridge upgrade. Public observer support still needs a
  separate `channel-workspace-mirror` update for the new `ChannelExitTollBurned` and `ChannelOperationAbandoned` event
  ABI entries, decoded fields, and operation-status display.
- Resolved: `packages/apps/private-state/README.md` stale CLI behavior was updated to match the current CLI policy:
  install-time Terms acceptance, interactive destructive/sensitive exports, default wallet-key-preserving `uninstall`,
  `uninstall --include-wallet-keys`, warning summaries without per-command legal acknowledgement flags, and interactive
  evidence export confirmation.
- Resolved: `packages/apps/private-state/README.md` now links to the current `User-Controlled AI Agent Guidance` section
  and uses current User-Controlled AI Agent terminology instead of stale `LLM agent` wording.
- Release-readiness rule: public documents may assume the selected planning items are complete, but final publication
  must occur only after the corresponding implementation and verification items are complete. If any selected feature is
  intentionally deferred, public documents must be revised before publication so they do not describe the deferred
  feature as current behavior.

## Bridge Governance Migration Plan

This section records the completed migration of root bridge owner and upgrade authority from a single EOA to an Ethereum
mainnet Safe multisig. The migration did not change Channel leader authority for existing Channels.

### Current governance state

- `BridgeCore`, `DAppManager`, and `L1TokenVault` are UUPS proxy contracts that use `OwnableUpgradeable`.
- Each contract authorizes upgrades through `_authorizeUpgrade(address) internal override onlyOwner`.
- The current recorded owner for `BridgeCore`, `DAppManager`, and `L1TokenVault` is the Safe multisig
  `0xBE637160D21975EF1e0270D32Bfc547c2EA8DcC3`.
- The current deployment artifacts record the Safe multisig and no timelock.
- The EIP-1967 admin slot is expected to remain empty because the deployment uses UUPS proxies.
- The Safe multisig can authorize upgrades and owner-only bridge administration. This does not rewrite existing Channel
  policy snapshots or transfer control over user secrets.

### Target state

- `BridgeCore.owner()` equals the selected Ethereum mainnet multisig address.
- `DAppManager.owner()` equals the selected Ethereum mainnet multisig address.
- `L1TokenVault.owner()` equals the selected Ethereum mainnet multisig address.
- The old EOA remains only a signer if intentionally included in the multisig signer set; it must no longer be the sole
  owner of any root bridge proxy.
- The deployment artifacts and monitoring documents disclose the multisig address, signer threshold, absence or presence
  of a timelock, and the current upgrade policy.
- No timelock is assumed unless one is explicitly selected, deployed, verified, and documented.

### Selected migration settings

The following settings are selected for the current migration:

- Multisig implementation: Safe.
- Safe address: `0xBE637160D21975EF1e0270D32Bfc547c2EA8DcC3`.
- Network: Ethereum mainnet.
- Threshold: 2-of-3.
- Safe owners confirmed on-chain:
  - `0x850dD0721B93D455b55bdf1324595fA1BD2B3ce7`,
  - `0xafeE17Be51cB3AB0BDfDc7440Dafb5201D5dbB24`,
  - `0x392CB2777354bf1A6FaD95D277394060621Cb66B`.
- Existing owner EOA `0x850dD0721B93D455b55bdf1324595fA1BD2B3ce7` remains one Safe signer.
- Timelock: none for this migration.
- Public disclosure: publish only the Safe address, 2-of-3 threshold, and no-timelock status. Do not publish signer
  identity or signer-control details in user-facing documents.
- Public notice timing: post-execution notice only for this ownership hardening migration.
- Immediate post-migration owner-only actions: none.
- Safe signer recovery details remain off-repository and are handled through Safe operations.

### Scope

In scope:

- Create or select the Ethereum mainnet multisig.
- Transfer ownership of `BridgeCore`, `DAppManager`, and `L1TokenVault` from the current EOA to the multisig.
- Update monitoring artifacts, admin wallet documentation, Terms, Privacy Notice, README, and observer documentation if
  they describe bridge owner or upgrade authority.
- Add verification steps for owner address, signer threshold, proxy implementation addresses, and UUPS admin-slot status.

Out of scope unless separately approved:

- Changing Channel leader or operator roles for `the-great-first-channel`.
- Adding a timelock, guardian, emergency council, pause mechanism, or protocol-level governance module.
- Upgrading bridge implementations during the ownership migration transaction sequence.
- Changing the current Provider identity or support contact.

### Known mainnet addresses

Use these addresses for the migration runbook unless a fresh deployment artifact or live-chain check proves that the
deployment has changed:

| Role | Address |
|---|---|
| Previous owner EOA | `0x850dD0721B93D455b55bdf1324595fA1BD2B3ce7` |
| `BridgeCore` proxy | `0x992E2Ae206620d811832a8F697c526c4f95974b6` |
| `DAppManager` proxy | `0x88Ab290a9dc0a169240EBC282Ec1F7C8524645aA` |
| `L1TokenVault` proxy | `0xf127Aef661c815ad46c5159146078f6F1E9f5F61` |
| Current `BridgeCore` implementation | `0x1713171adc06BF82b4f05945d742FFd351a8d1bD` |
| Current `DAppManager` implementation | `0x76f0e95c0E5c9bA26289062637c68aEc1199ddc5` |
| Current `L1TokenVault` implementation | `0x4c6dDcf807309d49Ac9a1f6583B5A19ef6c6a710` |

The selected multisig address is `0xBE637160D21975EF1e0270D32Bfc547c2EA8DcC3`.

### Multisig selection requirements

- Use an audited Ethereum mainnet multisig implementation such as Safe.
- The multisig must be deployed on Ethereum mainnet before ownership transfer.
- Verify the multisig address in the official Safe interface and on Etherscan.
- Verify that the multisig address has deployed bytecode.
- Verify the owner list and threshold on-chain.
- Recommended threshold:
  - minimum acceptable baseline: 2-of-3,
  - stronger operational baseline: 3-of-5, if enough independent signers are available.
- Signers should use hardware wallets or equivalent strong custody. The signer set should avoid a single shared device,
  single cloud account, single seed phrase, or single person controlling enough keys to meet the threshold.
- Confirm that the selected Safe can perform signer replacement and threshold changes through ordinary Safe owner
  transactions. The detailed signer recovery procedure must remain an off-repository operational matter handled through
  Safe and the signers' own custody processes.

### Decisions required from the Provider before execution

| Decision | What the decision means | Why it matters | Decision criteria | Recommended default |
|---|---|---|---|---|
| Multisig implementation | Choose the contract and interface that will become the owner of the three root bridge proxies. | The multisig will control UUPS upgrades and owner-only bridge administration. A wrong or untrusted implementation can permanently weaken governance. | Use a widely used, audited, Ethereum mainnet multisig with transparent owner and threshold inspection, transaction simulation support, and good operational tooling. | Use Safe on Ethereum mainnet. |
| Exact multisig address | Select the deployed contract address that receives ownership. | `transferOwnership` is immediate and sends authority to the exact address. A wrong address can lock or misdirect upgrade authority. | Verify the address in Safe UI, Etherscan, and `cast code`; verify chain ID is Ethereum mainnet; verify no copied address mismatch. | Decide only after the Safe is deployed and independently checked. |
| Signer set | Choose the Ethereum accounts that can approve multisig transactions. | Signers become the practical controllers of bridge upgrades and admin actions. Weak signer selection can recreate single-person or single-device risk. | Prefer independent devices and independent people; avoid one person controlling enough keys to meet threshold; prefer hardware wallets; avoid custodial exchange accounts and shared seed phrases. | At least three signers, each with separate hardware-wallet custody. |
| Threshold | Choose how many signer approvals are required. | Too low a threshold is easy to compromise; too high a threshold can block urgent upgrades or recovery if a signer is unavailable. | Balance security against availability. Use 2-of-3 only when the team is small. Use 3-of-5 when enough reliable independent signers exist. Avoid 1-of-N. | 2-of-3 minimum; 3-of-5 preferred. |
| Old owner EOA as signer | Decide whether `0x850d...B3ce7` remains one multisig signer. | Keeping it as one signer preserves operational continuity but may preserve part of the original key risk. Removing it reduces old-key dependency but requires other signers to be ready. | Keep it only if it is stored securely and does not control enough other signer keys to meet threshold. Remove it if the goal is to eliminate reliance on that key entirely. | Keep as one signer only if hardware-secured; otherwise replace it. |
| Timelock now or later | Decide whether a timelock contract should own the proxies instead of the Safe, or whether Safe ownership is enough for this migration. | A timelock gives users public reaction time before upgrades, but it adds operational complexity and can slow emergency fixes. | Add a timelock only if delay length, proposer/executor roles, emergency policy, and documentation are ready. Otherwise migrate to Safe first and document that no timelock exists. | Defer timelock; migrate to Safe first. |
| Public signer disclosure | Decide whether public docs disclose signer identities or only the multisig address and threshold. | Public identities increase accountability but can create personal security and harassment risk. Address-only disclosure is less transparent but safer for individuals. | Publish enough to let users verify governance structure without exposing unnecessary personal information. Do not use wording such as "Provider-controlled Safe" in public user-facing documents. Also do not imply independent third-party governance, community governance, or external oversight unless that is actually true. | Publish multisig address, threshold, and timelock status; do not publish personal signer identities or signer-control details unless intentionally chosen. |
| Public notice timing | Decide whether to announce the migration before execution, after execution, or both. | Pre-notice improves transparency. Post-notice confirms final state. Long pre-notice may create operational delay or invite targeted attacks. | For a pure single-EOA-to-multisig hardening migration with no implementation upgrade, post-execution notice may be sufficient; for any upgrade combined with migration, pre-notice should be required. | Post-execution notice for ownership migration only; separate notice for later upgrades. |
| Immediate owner-only actions | Decide whether any owner-only action will be executed right after migration. | Combining migration with upgrades or config changes makes review harder and increases user trust risk. | Keep migration isolated unless there is an urgent and documented reason. If another owner-only action is needed, schedule it as a separate multisig transaction after migration verification. | No immediate owner-only action. |
| Safe signer recovery scope | Decide only whether signer recovery details stay out of public repository planning. | The repository should not expose operational key-management details. Safe signer replacement is performed through Safe itself when enough valid signers remain. | Public docs should disclose the on-chain owner, threshold, and timelock status, but not private key-management or recovery procedures. | Keep detailed signer recovery off-repository; verify only that Safe supports owner replacement. |

### Preflight checks

Before any on-chain transaction:

- Confirm the selected multisig address, owner list, threshold, and chain ID.
- Confirm the current owner for all three root bridge proxies.
- Confirm the current implementation address for all three proxies.
- Confirm that the EIP-1967 admin slot is still empty for all three UUPS proxies.
- Confirm that OpenZeppelin `OwnableUpgradeable.transferOwnership(newOwner)` is a single-step ownership transfer in the
  deployed codebase and does not require `acceptOwnership`.
- Prepare the three EOA-signed ownership-transfer calls:
  - `BridgeCore.transferOwnership(multisig)`,
  - `DAppManager.transferOwnership(multisig)`,
  - `L1TokenVault.transferOwnership(multisig)`.
- Simulate the calls with the exact target addresses and calldata on a mainnet fork or a trusted transaction-simulation
  tool.
- Do not include any `upgradeTo` call in the ownership-migration transaction sequence.

Concrete read-only checks:

```sh
export ETH_RPC_URL="<ethereum-mainnet-rpc-url>"
export MULTISIG_ADDRESS="<selected-safe-address>"

cast call 0x992E2Ae206620d811832a8F697c526c4f95974b6 "owner()(address)" --rpc-url "$ETH_RPC_URL"
cast call 0x88Ab290a9dc0a169240EBC282Ec1F7C8524645aA "owner()(address)" --rpc-url "$ETH_RPC_URL"
cast call 0xf127Aef661c815ad46c5159146078f6F1E9f5F61 "owner()(address)" --rpc-url "$ETH_RPC_URL"
cast code "$MULTISIG_ADDRESS" --rpc-url "$ETH_RPC_URL"
```

Expected preflight results:

- All three `owner()` calls return the pre-migration owner
  `0x850dD0721B93D455b55bdf1324595fA1BD2B3ce7`.
- `cast code "$MULTISIG_ADDRESS"` returns non-empty bytecode.
- Safe UI and on-chain Safe reads show the selected signer list and threshold.
- The proxy implementation addresses match the known mainnet addresses above.
- The migration transaction set contains only three `transferOwnership` calls.

Preflight result on 2026-06-10:

- Safe code exists at `0xBE637160D21975EF1e0270D32Bfc547c2EA8DcC3`.
- Safe threshold is 2.
- Safe owners are
  `0x850dD0721B93D455b55bdf1324595fA1BD2B3ce7`,
  `0xafeE17Be51cB3AB0BDfDc7440Dafb5201D5dbB24`, and
  `0x392CB2777354bf1A6FaD95D277394060621Cb66B`.
- `BridgeCore.owner()`, `DAppManager.owner()`, and `L1TokenVault.owner()` all return
  `0x850dD0721B93D455b55bdf1324595fA1BD2B3ce7`.
- Implementation slots match the known mainnet implementation addresses.
- EIP-1967 admin slots are empty for all three UUPS proxies.
- `the-great-first-channel` still resolves to Channel manager
  `0x3108d92A38bFb4B3396DE7ad4D92318a8fbE61D7`.

### Execution plan

- Execute ownership transfers from the then-current owner EOA.
- Prefer a scripted or checklist-driven sequence that signs and submits exactly the three ownership-transfer
  transactions.
- After each transaction confirms, immediately verify the corresponding `owner()` value.
- If one transfer succeeds and another fails, treat the deployment as partially migrated, stop non-essential governance
  activity, diagnose the failed transaction, and complete the remaining ownership transfers before any unrelated
  owner-only action.
- Do not perform implementation upgrades, verifier changes, DApp metadata changes, Join Toll schedule changes, or Channel
  deployer changes in the same transaction sequence.

Concrete transaction sequence:

```sh
export ETH_RPC_URL="<ethereum-mainnet-rpc-url>"
export PRIVATE_KEY="<current-owner-eoa-private-key-or-secure-signer-adapter>"
export MULTISIG_ADDRESS="<selected-safe-address>"

cast send 0x992E2Ae206620d811832a8F697c526c4f95974b6 \
  "transferOwnership(address)" "$MULTISIG_ADDRESS" \
  --rpc-url "$ETH_RPC_URL" --private-key "$PRIVATE_KEY"

cast send 0x88Ab290a9dc0a169240EBC282Ec1F7C8524645aA \
  "transferOwnership(address)" "$MULTISIG_ADDRESS" \
  --rpc-url "$ETH_RPC_URL" --private-key "$PRIVATE_KEY"

cast send 0xf127Aef661c815ad46c5159146078f6F1E9f5F61 \
  "transferOwnership(address)" "$MULTISIG_ADDRESS" \
  --rpc-url "$ETH_RPC_URL" --private-key "$PRIVATE_KEY"
```

The command form above is only an execution shape. Use the safest available signing method for the then-current owner EOA.
Do not paste a private key into an untrusted shell, chat tool, ticket, or browser.

Equivalent calldata for each target proxy:

```text
0xf2fde38b000000000000000000000000be637160d21975ef1e0270d32bfc547c2ea8dcc3
```

Use this calldata only with the three migration target proxies listed in this plan.

### Post-transfer verification

After all three transfers:

- Verify that `BridgeCore.owner()`, `DAppManager.owner()`, and `L1TokenVault.owner()` all return the multisig address.
- Verify that the old EOA can no longer execute owner-only actions directly.
- Verify that the multisig address has deployed bytecode and the expected owner threshold.
- Verify that implementation addresses did not change during the migration.
- Verify that the EIP-1967 admin slot remains empty for all three UUPS proxies.
- Verify that existing Channel records, including `the-great-first-channel`, still resolve to their existing Channel
  manager addresses.
- Verify that no Channel policy snapshot was unintentionally changed.

Concrete post-transfer checks:

```sh
export ETH_RPC_URL="<ethereum-mainnet-rpc-url>"
export MULTISIG_ADDRESS="<selected-safe-address>"

cast call 0x992E2Ae206620d811832a8F697c526c4f95974b6 "owner()(address)" --rpc-url "$ETH_RPC_URL"
cast call 0x88Ab290a9dc0a169240EBC282Ec1F7C8524645aA "owner()(address)" --rpc-url "$ETH_RPC_URL"
cast call 0xf127Aef661c815ad46c5159146078f6F1E9f5F61 "owner()(address)" --rpc-url "$ETH_RPC_URL"
cast code "$MULTISIG_ADDRESS" --rpc-url "$ETH_RPC_URL"
```

Expected post-transfer results:

- All three `owner()` calls return `MULTISIG_ADDRESS`.
- The old owner EOA no longer has direct `onlyOwner` authority over any root bridge proxy.
- The multisig address has non-empty bytecode and the expected signer threshold.
- The implementation addresses are unchanged from the preflight snapshot.
- The EIP-1967 admin slots remain empty.

Post-transfer result on 2026-06-10:

- Ownership transfer transactions:
  - `BridgeCore`: `0xbf02088103cc8082136d3832daa46ac668ad1beee27e353ef8a8102f39690691`,
  - `DAppManager`: `0x921c168547b2fc284bf9aa9bf981cf79c1dca4e1ac0cfdb4cc40144e6631aef3`,
  - `L1TokenVault`: `0xaabe73295adcfc3f5380c66ce46df36dd0adcd47c94fe41757c32ef81ba1044e`.
- `BridgeCore.owner()`, `DAppManager.owner()`, and `L1TokenVault.owner()` all return
  `0xBE637160D21975EF1e0270D32Bfc547c2EA8DcC3`.
- Safe threshold remains 2-of-3.
- Implementation slots remained unchanged.
- EIP-1967 admin slots remained empty.
- `the-great-first-channel` still resolves to Channel manager
  `0x3108d92A38bFb4B3396DE7ad4D92318a8fbE61D7`.

### Safe-side operational verification

After ownership transfer, perform one Safe-side dry operational check before any real upgrade:

- Prepare a Safe transaction that calls a harmless read-only target through the Safe interface if the tool supports
  simulation-only transactions, or simulate an owner-only call without broadcasting it.
- Verify that the Safe UI can build, simulate, collect approvals for, and reject or discard a transaction.
- Do not execute a state-changing owner-only call solely for testing unless the action is explicitly approved and has no
  production side effect.

### Documentation and monitoring updates

After successful on-chain transfer:

- Completed: update `docs/audit/monitoring/data/TPAC-Contract-Addresses.json`:
  - set the three owner fields to the multisig address,
  - set `multisig` to the multisig address,
  - keep `timelock` as `null` unless a timelock is actually deployed and owns the contracts,
  - update the governance note.
- Completed: update `docs/audit/monitoring/data/Admin-Wallets-and-Upgrade-Policy.md` with the multisig address, signer
  threshold, no-timelock status, ownership transfer transactions, and UUPS upgrade policy.
- Completed: update `docs/whitepaper.md` to remove stale single-EOA launch wording and describe the current Safe
  multisig owner posture.
- Remaining: update any additional monitoring packet, observer documentation, Terms, README, or release notes if later
  review finds stale owner or upgrade-authority wording.
- Public user-facing documentation should use neutral on-chain wording such as "the root bridge proxy owner is the Safe
  multisig at `<address>` with a 2-of-3 threshold and no timelock" after migration. It must not say "Provider-controlled
  Safe" or similar signer-control wording, and it must not imply independent third-party governance, community
  governance, or external oversight unless the signer set and operating model actually support that claim.
- Add a post-migration changelog entry for the CLI or Service documentation only if the user-facing documentation package
  is changed.

### Checklist review

No explicit `checklist.md` violation is expected from moving bridge owner and upgrade authority from a single EOA to a
multisig. The change improves the admin-wallet and upgrade-policy disclosure posture if it is accurately documented.

The migration must preserve the following constraints:

- Do not describe the multisig as user custody.
- Do not imply that the multisig can recover user secrets, reverse Ethereum mainnet transactions, or guarantee user
  recovery.
- Do not imply that existing Channel policy snapshots are rewritten by the ownership transfer.
- Do disclose that the multisig can authorize upgrades to the UUPS root bridge proxies and can execute owner-only bridge
  administration functions.
- Do disclose whether a timelock exists. If no timelock exists, state that plainly.

### Open decisions before execution

- None. Execution and post-transfer verification are complete.

## Pre-Counsel Redline and Risk Review Plan

This review is a pre-legal operational risk review. It does not replace counsel review and must not be presented as a
legal opinion. Its purpose is to identify unclear terms, likely negotiation points, missing disclosures, and issues that
remain useful for a far-future counsel review cycle.

### Review outputs

- A redlined terms draft that marks every proposed wording change.
- A risk register with severity, affected section, affected user flow, likely jurisdictional sensitivity, and proposed
  mitigation.
- A counsel-question list that separates business decisions from legal-validity questions.
- A checklist mapping that confirms every `checklist.md` item remains covered after redlines.
- A release-risk list that separates implementation blockers from long-term counsel-review topics.

### Governing law and forum review

- Use the selected Provider Party model: the Provider is Jehyuk Jang, an individual, with public privacy and notice
  contact `cjhyuck213@gmail.com` and stated jurisdiction Singapore.
- Review whether a Singapore governing-law clause may be invalid, partially invalid, or limited for users in mandatory
  consumer-protection jurisdictions.
- Review whether a Singapore courts forum clause may be considered unfair, unenforceable, or partially unenforceable
  where a consumer is entitled to sue or defend claims in the consumer's local courts.
- Record that the Terms use court litigation in the Provider-connected forum with mandatory consumer-law exceptions and
  do not include arbitration or class-action waiver provisions for the current implementation.
- Confirm whether the current conflict-of-law exclusion is appropriate for the Service and for international consumer
  users.

### Arbitration and class-action review

- Treat arbitration, class-action waiver, collective-action waiver, representative-action waiver, and jury-trial waiver
  provisions as excluded from the current draft.
- If a later counsel or business-owner review recommends adding any such provision, first decide the arbitral
  institution, seat, language, number of arbitrators, emergency relief rules, confidentiality, fees, small-claims
  exceptions, and consumer exceptions.
- Review whether any later arbitration or waiver clause would be valid in the expected user jurisdictions before adding
  it to the Terms.
- Avoid adding arbitration or class-action waiver language in the current implementation.

### Consumer-law carveout review

- Identify expected user jurisdictions and the mandatory consumer rights that cannot be waived in those jurisdictions.
- Review whether the current non-waivable rights carveout is sufficient for consumer users.
- Review whether acceptance, renewed acceptance, notices, unilateral updates, liability limits, indemnity, and forum
  clauses could be considered unfair or insufficiently clear for ordinary users.
- Confirm whether additional cooling-off, withdrawal, cancellation, refund, language, accessibility, or notice
  requirements apply to the Service.

### Sanctions, restricted jurisdictions, and AML review

- Review sanctions and restricted-jurisdiction wording against the Provider Party's applicable sanctions regimes and
  operational policy.
- Review the selected principles-based approach, under which the current draft does not name specific restricted
  jurisdictions, sanctions lists, sanctions authorities, or prohibited user categories.
- Review whether the Service needs geoblocking, access controls, screening, warnings, or additional user representations.
- Confirm that prohibited-use language covers money laundering, terrorist financing, sanctions evasion, regulatory
  evasion, criminal-proceeds concealment, exchange-monitoring evasion, fraud, illegal gambling, ransomware, and market
  manipulation without marketing the Service as useful for those purposes.
- Review whether the Official Public Observer and monitoring disclosures are sufficient for exchange-facing and
  regulator-facing risk.

### Liability, warranty, and indemnity review

- Review the selected no-monetary-liability-cap approach and confirm that it is appropriate for the Service's
  no-Service-revenue, open-software, non-custodial model.
- Review whether the current warranty disclaimer is valid for consumer users and mandatory local-law rights.
- Review whether the liability exclusion for lost secrets, failed transactions, third-party failures, exchange actions,
  regulatory actions, and tax consequences is enforceable or should be narrowed.
- Review whether the fraud, willful misconduct, gross negligence, death, and personal-injury carveout is sufficient for
  expected jurisdictions.
- Review whether the user indemnity is enforceable against ordinary consumers or should be limited to business users,
  unlawful use, or third-party claims.

### Blockchain and privacy-state risk review

- Confirm that the Terms do not imply that TON becomes private, anonymous, untraceable, exchange-depositable as a Private
  Note, or hidden from Ethereum mainnet records.
- Confirm that the Terms adequately explain Self-Custody, secret-loss risk, no recovery method, irreversible public
  transactions, bridge risk, smart-contract risk, RPC risk, wallet risk, zero-knowledge implementation risk, and
  Third-Party Service risk.
- Confirm that the Terms do not overstate privacy, confidentiality, unlinkability, selective disclosure, source
  explanation, exchange acceptance, compliance outcomes, or regulatory outcomes.
- Review whether bridge, Channel, Private Note, and Official Public Observer disclosures are clear enough for ordinary
  users and detailed enough for legal, compliance, and exchange reviewers.
- Confirm that the Terms and product docs are not free of blockchain, self-custody, bridge, private-state, sanctions, or
  AML risk, and that they accurately disclose and allocate those risks instead of implying that the risks do not exist.

### Privacy and data review

- Determine whether the Service processes personal data through the Official Public Observer, websites, logs, package
  distribution, support channels, telemetry, RPC configuration, or other official interfaces.
- Produce the privacy notice.
- Review whether public blockchain records, public Channel records, IP addresses, device data, usage logs, support
  communications, and analytics data are sufficiently disclosed.
- Confirm that Third-Party Service data collection and retention are clearly separated from Provider Party obligations.

### AI-agent and machine-readable output review

- Confirm that Official Machine-Readable Output cannot accept Terms, renewed Terms, or secret-handling decisions on
  behalf of the user.
- Confirm that User-Controlled AI Agent guidance requires explanation of warnings, prohibitions, public/private
  boundaries, Self-Custody, no recovery method, Third-Party Service risk, no professional advice, no warranties,
  liability limits, and Official Public Observer limits.
- Review whether AI-agent guidance creates any implied advisory, fiduciary, custody, support, or compliance relationship.

## Pre-Counsel Review Results

This section records the first pre-counsel operational review result. It is not a legal opinion and must not be used as a
substitute for counsel review. It is intended to identify drafting changes, business decisions, implementation blockers,
and long-term legal review topics.

### Comparable-service coverage notes

The current review checked the current official public terms or guidance for Aztec Foundation, Uniswap Labs, Aave App,
and MetaMask self-custody guidance. The following coverage patterns are relevant to this Service:

- Aztec expressly identifies the contracting entity, links privacy policy coverage, restricts unlawful and sanctions use,
  disclaims warranties, caps liability, includes arbitration with consumer exceptions, and lists development-tooling
  risks including wallet safekeeping, public blockchain risk, transaction irreversibility, digital-asset risk, bridging
  risk, third-party risk, and legal/regulatory uncertainty.
- Uniswap Labs covers third-party services, prohibited activity, no professional advice, indemnity, broad liability
  exclusions, a liability cap, governing law, arbitration, and class-action waiver mechanics.
- Aave App covers tax responsibility, third-party service disputes, third-party terms, restricted-person concepts,
  warranty disclaimers, liability limitation, and broad indemnity tied to user assets, private keys, devices,
  third-party services, and legal compliance.
- MetaMask explains the self-custody baseline in ordinary language: the user controls access, the provider cannot
  recover funds or secrets if the user's recovery material is lost, and the provider will not ask for secret recovery
  phrases, private keys, or passwords.

Coverage impact for the current draft: Sections 6, 11, 13, 14, 15, 16, 17, and 20 are directionally aligned, but the
current draft still needs counsel confirmation of Tokamak Network PTE. LTD.'s separate role wording, Privacy Notice, the
selected no-monetary-liability-cap approach, restricted-jurisdiction policy, consumer-law carveouts, and notice mechanics
as long-term review topics.

### Redline items

| ID | Section | Proposed change before counsel review | Rationale | Status |
|---|---|---|---|---|
| R-01 | 1, 2, 20 | Replace generic Provider Party references in the operative clauses with Jehyuk Jang, `cjhyuck213@gmail.com`, Singapore, and the no-residential-address publication policy. Define Tokamak Network PTE. LTD. separately as software contributor/licensor and Third-Party Service or infrastructure/tooling provider for Tokamak-controlled surfaces not operated by the Provider. | Users and legal reviewers need to know who offers the Service, who developed the software, who receives notices, and who accepts provider obligations. | Applied to draft Terms; far-future counsel review remains recorded. |
| R-02 | 3 | Remove passive "continuing to access or use" acceptance for terms-gated CLI operations, or limit it to non-CLI informational surfaces. Require explicit acceptance for install and renewed acceptance. | The planned CLI gate relies on explicit acceptance and deterministic terms hash records. Passive acceptance may conflict with that product design. | Applied to draft Terms; verify implementation follows explicit acceptance. |
| R-03 | 3 | Add an age-of-majority or minimum-age statement if the Service is made available to natural persons. | "Legal capacity" may be too abstract for ordinary users and consumer review. | Far-future counsel review topic. |
| R-04 | 3, 7 | Use a principles-based restricted-use and sanctions policy in the current draft. Do not name specific restricted jurisdictions, sanctions lists, sanctions authorities, or prohibited user categories unless a later counsel or business-owner review requires them. State that the Service may only be able to restrict Ethereum Accounts or contract interactions, not identify and block real-world users. | Comparable services often name sanctions regimes or restricted regions, but naming lists creates maintenance obligations and can be misleading when the Service lacks user-identification and user-level blocking. The current product position is to require applicable-law compliance without overpromising enforcement. | Selected business position; far-future counsel review remains recorded. |
| R-05 | 5 | Replace "Tonnel may prevent public contract state..." with a more precise non-guarantee: "Tonnel is designed so public contract state does not, by itself, reconstruct..." | "May prevent" is vague; a design-purpose statement is clearer while avoiding guarantees. | Applied to draft Terms. |
| R-06 | 6 | Add a short ordinary-user warning that Provider Parties, Channel Operators, and User-Controlled AI Agents will never need the user's private keys, seed phrases, wallet secrets, spending keys, or viewing keys. | Aligns with self-custody guidance and reduces secret-disclosure risk. | Applied to draft Terms. |
| R-07 | 7 | Keep prohibited-use wording, but avoid repeating prohibited marketing phrases outside prohibited-use and checklist contexts. | Terms can prohibit misuse without creating marketing language that suggests the Service is useful for that misuse. | Reviewed current ordinary-user and agent-facing surfaces; prohibited framing appears only in Product Compliance Position, prohibited-use/checklist contexts, or operational illegal-use warnings. Keep final wording check before release. |
| R-08 | 8 | Add user responsibility for preserving the local evidence needed for selective disclosure, exchange review, tax records, disputes, and audits. | Section 10 mentions evidence but Section 8 should allocate the preservation duty expressly. | Applied to draft Terms. |
| R-09 | 9 | Clarify whether Channel Operators are independent from Provider Parties unless officially appointed, and state that Channel policy may differ by Channel. | Users must distinguish the Service provider from third-party or community Channel operators. | Product decision complete; far-future counsel review remains recorded. |
| R-10 | 10 | Replace "Official Public Observer does not reveal user secrets" with "is not intended to receive or display user secrets" and "only displays records available to it." | Avoids an absolute security or non-disclosure guarantee. | Applied to draft Terms. |
| R-11 | 12 | Keep the standalone Privacy Notice in `docs/dapps/private-state/privacy-notice.md` and keep the Terms cross-reference to that location unless the final publication location changes. | The Service scope includes official hosted observer and possible logs/support/package-distribution data. The initial standalone draft, GitHub repository publication location, Terms cross-reference, and repository-level final consistency review now exist. | Repository-level final consistency review applied; far-future counsel review remains recorded. |
| R-12 | 13 | Clarify that User-Controlled AI Agents are selected by the user and are not agents, representatives, or service providers of Provider Parties unless expressly stated. | Reduces implied advisory, support, fiduciary, or agency relationship risk. | Applied to draft Terms. |
| R-13 | 14 | Add explicit ZK/proof-system risk, CRS/proving-artifact risk, local proof-generation risk, and public observer indexing risk. | Current blockchain risks are broad but do not fully reflect this Service's proof and observer architecture. | Applied to draft Terms. |
| R-14 | 16 | Do not include a nominal monetary liability cap in the current draft. Preserve broad liability exclusions to the maximum extent permitted by applicable law and preserve non-waivable liability carveouts. | The Service is non-custodial open software/public-good infrastructure, Provider Parties do not operate it for Service revenue, and Join Tolls are not Provider Party revenue. A fee-based cap would create a zero-fee problem, while a nominal cap could imply a paid-service liability model that does not fit the Service. | Selected business position; far-future counsel review remains recorded. |
| R-15 | 17 | Narrow consumer indemnity or add business-user/unlawful-use limitations if a later counsel or business-owner review recommends it. | Broad consumer indemnity can be unenforceable or unfair in some jurisdictions. | Far-future counsel review topic. |
| R-16 | 18 | Specify the technical renewed-acceptance mechanism: terms version, deterministic hash, displayed terms, explicit phrase, stored record, stale-record rejection. | The product can implement this and should not rely only on legal notice wording. | Applied to draft Terms; verify implementation follows this mechanism after Terms freeze. |
| R-17 | 20 | Use Singapore court litigation and Singapore law as the Provider-connected baseline, with mandatory consumer-law and local-court carveouts. Do not include arbitration, class-action waiver, collective-action waiver, representative-action waiver, or jury-trial waiver provisions in the current implementation. | Forum and waiver clauses may be invalid or problematic for consumers in some jurisdictions. | Applied to draft Terms; far-future counsel review remains recorded. |
| R-18 | 20 | Add `cjhyuck213@gmail.com` as the public privacy and notice contact for Jehyuk Jang, and state that the Provider's residential address is not published. If a physical notice address becomes required, use a non-residential notice route. | Notices are incomplete without an official contact route, but residential address publication is not the default policy. | Applied to draft Terms; far-future counsel review remains recorded. |
| R-19 | 1, 2, 9, 16 | Apply generalized Join Toll policy wording to Terms and user-facing documents. The local source now stores Join Tolls in `L1TokenVault._tollTreasuryBalance`, records `joinTollPaid`, refunds the refundable portion from the toll treasury, and transfers the non-refundable portion to `0x000000000000000000000000000000000000dEaD` on Channel exits. Existing already-exited users' historical non-refundable Toll portions are not in scope for retroactive burn-address transfer. | The user-facing economic representation must match the protocol. Because mainnet TON does not expose an external `burn` function and rejects transfer to `address(0)`, the Service must describe this as a burn-address transfer, not as TON total-supply reduction. Bridge default Join Toll refund policy may be updated, but each Channel fixes its own refund policy at Channel creation. Public documents must not present a single refund schedule as universal for all Channels. Users must verify Bridge defaults through `BridgeCore.defaultJoinTollRefundCutoff*` and `BridgeCore.defaultJoinTollRefundBps*`, and a specific Channel's fixed policy through that Channel's `ChannelManager.joinTollRefundCutoff*` and `ChannelManager.joinTollRefundBps*`; observer pages, CLI output, and Monitoring Packet files are convenience views of those on-chain values. | Source implementation completed, Safe upgrade executed, Monitoring Packet support added, and final public-document blocker resolved by generalized policy wording. |
| R-20 | Prompt policy | Remove `--acknowledge-action-impact` from every command, enforce install-time Terms acceptance, make `uninstall` interactive like `install`; default uninstall preserves wallet workspace spending-key and viewing-key files while deleting the rest, and `--include-wallet-keys` deletes everything without exception. Make secret-bearing material export commands and plaintext note/evidence export commands interactive. For each such interactive flow, print the command impact, leakage or destructive risk, precautions, and Provider Party disclaimers, then require human confirmation before continuing. For every command that handles real funds, print command-specific information and warning summaries in human mode and `--json` mode on every run without requiring a command-level acknowledgement option. | This implements the selected product policy: one-time install Terms acceptance replaces repeated action-impact acknowledgement flags, while moment-specific human confirmations remain for destructive deletion and sensitive exports, and ordinary transaction commands still show relevant warnings. | Guide/command-reference/warning-output, uninstall prompt, wallet viewing-key/spending-key export confirmation, plaintext note/evidence export confirmation review, install Terms gate, and renewed acceptance mechanism completed in local source. |
| R-21 | 2, 9, 10, 14 | Add Channel Operation Abandonment to Terms, docs, monitoring, and implementation planning. The Channel leader may initiate abandonment on-chain with no grace period. After abandonment, new joins and `deposit-channel` are rejected for that Channel; note activity, `redeem-notes`, `withdraw-channel`, and `exit-channel` remain unrestricted by abandonment. | This gives the Channel leader a clear public way to stop onboarding and new deposits without trapping existing users or claiming control over user notes. The feature is compatible with existing Channels if enforcement is placed in the shared upgradeable vault path for join/deposit. Existing `the-great-first-channel` note activity cannot and should not be restricted under the revised request. | Implemented in local bridge source, bridge tests, CLI command/status handling, `help guide`/`help guide --json`, `agents.md`, private-state README, bridge changelog, private-state workflow/security docs, mainnet bridge upgrade, and Monitoring Packet data. Public observer support remains pending in the separate `channel-workspace-mirror` repository. |

### Risk register

| ID | Severity | Area | Risk | Proposed mitigation | Owner |
|---|---|---|---|---|---|
| K-01 | Medium | Provider identity | The Provider model and public Provider details are selected, and Tokamak Network PTE. LTD. is separated from Provider obligations. Far-future counsel review remains recorded for the exact Tokamak role wording. | Insert Jehyuk Jang, `cjhyuck213@gmail.com`, Singapore, and the no-residential-address publication policy; use the selected Tokamak software contributor/licensor and Third-Party Service or infrastructure/tooling provider wording; preserve personal-liability and notice-handling implications for far-future counsel review. | Business/counsel. |
| K-02 | Low | Privacy/data | A standalone Privacy Notice draft now exists in the repository, the initial GitHub repository publication location is selected, the Terms cross-reference is drafted, and the repository-level final consistency review is complete. | Preserve the reviewed draft unless a later business-owner or counsel review decision requires changes. | Product/counsel. |
| K-03 | High | Consumer law | A Provider-connected forum clause may be limited or unenforceable for consumers with mandatory local rights. | Preserve explicit non-waivable consumer-rights and local-court carveouts; keep this as a far-future counsel review topic. | Counsel. |
| K-04 | Medium | Dispute resolution | The current draft excludes arbitration and class-action waiver provisions. This reduces clause-validity and user-friction risk but may increase litigation exposure for the individual Provider. | Preserve the no-arbitration and no-class-action-waiver strategy for the current implementation; keep this as a far-future counsel review topic. | Counsel/business. |
| K-05 | Medium | Liability | The current draft intentionally uses no nominal monetary liability cap. This matches the no-Service-revenue, open-software, non-custodial model. Far-future counsel review remains recorded for disclaimer structure and non-waivable liability carveouts. | Keep the no-monetary-cap business position and preserve broad disclaimers and mandatory-law carveouts. | Counsel/business. |
| K-06 | Medium | Sanctions/AML | The draft uses a principles-based restricted-use and sanctions policy without naming specific restricted jurisdictions, sanctions lists, sanctions authorities, or prohibited user categories. This avoids stale lists and overpromised user-level blocking. Far-future counsel review remains recorded for named restrictions, account-level restriction, screening, or additional warnings. | Preserve applicable-law compliance wording and the technical limitation that restrictions may operate only at the Ethereum Account or contract-interaction level unless a real user-identification system exists. | Compliance/counsel. |
| K-07 | Low | Privacy claims | Draft wording now avoids "may prevent" and "does not reveal" in Sections 5 and 10, but final text still needs legal and technical review for overstatement. | Keep the design-intent and observer-limit wording during final Terms review. | Product/counsel. |
| K-08 | Medium | Self-custody | Secret-loss warning is legally useful but should be more visible in install and AI-agent flows. | Add section refs to install/JSON guide and ensure human guide explains no recovery method before secret-dependent use. | Product. |
| K-09 | Medium | Third-party services | RPC providers, wallets, exchanges, package registries, and browsers have independent terms and data practices. | Keep Section 11 and privacy notice cross-references; add RPC-provider metadata disclosure if applicable. | Product/counsel. |
| K-10 | Medium | Channel operators | Channel Operators may not be Provider Parties, but users may confuse them. | Clarify independence, responsibilities, and policy variance by Channel. | Product/counsel. |
| K-11 | Medium | AI agents | User-Controlled AI Agents could be perceived as acting with official authority if JSON directives are too prescriptive. | State that AI agents are user-selected tools and cannot accept terms, handle secrets, or create advisory relationship. | Product/counsel. |
| K-12 | Medium | Evidence/observer | Official Public Observer may be insufficient for exchange, tax, audit, or compliance review. | Preserve observer-limit wording and add local evidence preservation duties. | Product/compliance. |
| K-13 | Low | Terminology | Final terminology search for ordinary-user and agent-facing surfaces found only `--join-toll` as a command option in the private-state app README and one `L1` occurrence in `agents.md` that explicitly instructs agents not to use `L1` with ordinary users. Technical documents may still use `L1` and `L2` where the target reader is technical. | Keep final terminology search before release; no current ordinary-user wording change is required from this pass. | Product. |
| K-14 | Medium | Burn-address transfer and refund policy | Resolved in local source and public wording. `L1TokenVault.exitChannel` now refunds the refundable portion, transfers the non-refundable portion to `0x000000000000000000000000000000000000dEaD`, and reduces `_tollTreasuryBalance` by both amounts. Bridge default refund policy may be updated, while each Channel fixes its refund policy at Channel creation. | Preserve the burn-address-transfer wording, avoid retroactive promises for already-exited users, and keep user-facing documents pointed at on-chain getters or official convenience views instead of a universal hardcoded schedule. | Product/security/counsel. |
| K-15 | Medium | Channel abandonment | Channel abandonment can be misunderstood as a pause, emergency recovery, custody control, or operator ability to censor existing note use. | Define it narrowly: leader-only, immediate, public, no grace period, blocks only new joins and `deposit-channel`, does not restrict note activity, `redeem-notes`, `withdraw-channel`, or `exit-channel`. Add observer/CLI status display and checklist-facing wording that existing users can still redeem, withdraw, and exit. | Product/security/counsel. |

### Counsel-question list

Business decisions to prepare before counsel review:

- Is Jehyuk Jang, `cjhyuck213@gmail.com`, Singapore, and no published residential address sufficient for the individual
  Provider identity and public notice/contact route? Is the selected Tokamak Network PTE. LTD. software
  contributor/licensor and Third-Party Service or infrastructure/tooling provider wording legally sufficient?
- Is the Service intended for all ordinary users, only users in selected jurisdictions, or only non-restricted users who
  pass some operational access control?
- Is the selected principles-based sanctions and restricted-use approach sufficient, or must the Terms name specific
  restricted jurisdictions, sanctions lists, sanctions authorities, or prohibited user categories? If the Service can
  block only Ethereum Accounts or contract interactions, what should the Terms say about the limits of user-level
  blocking?
- Should the Service use Singapore court litigation with mandatory consumer-law carveouts, and no arbitration or
  class-action waiver provisions?
- Is the selected no-monetary-liability-cap approach appropriate for a non-custodial open-software/public-good Service
  that is not operated for Provider Party Service revenue and does not monetize Join Tolls?
- Should user indemnity apply to ordinary consumers, business users only, unlawful use only, or third-party claims only?
- What official interfaces process personal data, including observer hosting, logs, analytics, support, package
  distribution, and telemetry?
- Is the initial GitHub repository Privacy Notice publication location and Terms cross-reference sufficient, or should a
  later business-owner or counsel review require an additional publication surface?
- Are the selected separate prompt rules sufficient: interactive `uninstall`, interactive secret-bearing material
  exports, interactive plaintext note/evidence exports, and non-blocking warnings for every real-funds command in human
  and `--json` modes?
- Is the selected Join Toll wording sufficient if it describes future non-refundable Join Toll handling as transfer to
  `0x000000000000000000000000000000000000dEaD`, and not as TON total-supply reduction?
- Is the generalized Join Toll policy wording sufficiently clear for ordinary users, including the burn-address-transfer
  handling of the non-refundable portion and the distinction between Bridge default policy and fixed per-Channel policy?
- Is the selected Channel Operation Abandonment policy sufficient and not misleading: immediate leader-only abandonment,
  no grace period, join/deposit blocked, all note activity and exit paths left unrestricted by abandonment?

Legal-validity questions for counsel:

- Is Singapore governing law and forum enforceable enough for expected users, including consumers outside Singapore?
- What consumer-law, cooling-off, withdrawal, language, accessibility, or local notice requirements apply?
- Is the current decision to omit arbitration, class-action waiver, collective-action waiver, representative-action
  waiver, and jury-trial waiver provisions advisable for the expected user base?
- Are the warranty disclaimer, liability exclusions, no-monetary-liability-cap approach, mandatory-law carveouts, and
  indemnity enforceable as drafted?
- Are sanctions, AML, anti-evasion, restricted-jurisdiction, and export-control provisions sufficient for the individual
  Provider, any separate Tokamak Network PTE. LTD. role, and the Service's expected availability?
- Does the privacy notice need GDPR, Singapore PDPA, UK GDPR, CCPA/CPRA, or other jurisdiction-specific coverage?
- Do Official Machine-Readable Output and User-Controlled AI Agent guidance create any advisory, agency, fiduciary,
  custody, or compliance-support obligations?

### Checklist mapping after review

| Checklist concern | Current coverage | Redline impact |
|---|---|---|
| TON must not be described as untraceable | Sections 2, 4, 5, 7, and 10 keep Ethereum mainnet records public or observable. | Keep; avoid prohibited framing outside prohibited-use context. |
| Tonnel must not be described as an exchange deposit network | Sections 1 and 2 define Channels as opt-in application environments, not exchange deposit or withdrawal networks. | Keep. |
| Private Notes must not be exchange-depositable assets | Sections 1 and 2 state that Private Notes are Channel-local application records. | Keep. |
| Users first hold TON in a self-custody Ethereum account | Sections 1, 2, 6, and 8 define Ethereum Account and Self-Custody. | Stronger no-secret-sharing warning added to Section 6. |
| Bridge deposit and withdrawal observability must be disclosed | Sections 4 and 10 disclose public bridge and observer records. | Keep observer-limit precision. |
| Channel join and public registration observability must be disclosed | Sections 4 and 10 disclose Channel joins, identity registration, note-receive public key registration, and public Channel records. | Keep. |
| Internal note privacy limits must be disclosed | Section 5 discloses limits and non-guarantees. | Keep design-intent wording. |
| Provider Parties and Channel Operators must not claim custody of user secrets | Sections 6, 8, and 9 disclaim possession, control, storage, and recovery of user secrets. | Section 6 now includes the stronger secret-warning text. |
| Selective disclosure must be limited to implemented features | Section 10 ties selective disclosure to implemented features and user-preserved records. | Section 8 now allocates local evidence preservation duty. |
| Illegal use must be prohibited | Section 7 covers money laundering, terrorist financing, sanctions evasion, regulatory evasion, fraud, illegal gambling, criminal-proceeds concealment, and exchange-monitoring evasion. | Keep; far-future counsel review remains recorded for sanctions scope. |
| Public monitoring surfaces must be available | Section 10 identifies the Official Public Observer. | Keep; privacy notice must disclose hosted observer data if applicable. |
| Marketing must avoid mixer or privacy-coin framing | Product Compliance Position and Sections 2, 5, and 7 avoid or prohibit that framing. | Keep terminology/framing verification before publishing final public documents. |
| Channel leader abandonment must not trap users or imply custody | New Channel Operation Abandonment plan blocks only new joins and `deposit-channel`, while preserving note activity, `redeem-notes`, `withdraw-channel`, and `exit-channel`. | No explicit `checklist.md` violation found. The feature must be documented as public operational status, not as a private-history control, exchange deposit network control, custody power, or operator backdoor. |

### Release blockers

The following items are the current implementation or deployment blockers. Counsel-review topics are listed separately
as long-term deferred review items in the release blocker triage below.

- Final Terms/docs/implementation consistency for the selected Join Toll policy: future Channel exits refund the
  refundable portion and transfer only the non-refundable portion to
  `0x000000000000000000000000000000000000dEaD`, with no retroactive burn-address transfer promise for already-exited
  users. Public documents must state that Bridge default policy may be updated, each Channel fixes its refund policy at
  Channel creation, and applicable values should be verified through on-chain getters or official convenience views.
- Final Terms/docs/implementation consistency for Channel Operation Abandonment: leader-only immediate abandonment
  blocks new joins and `deposit-channel`, keeps note activity, `redeem-notes`, `withdraw-channel`, and `exit-channel`
  unrestricted by abandonment, and is surfaced through CLI and public monitoring.
- Final redlined Terms wording for Sections 3, 5, 6, 10, 12, 13, 14, 16, 17, 18, and 20.
- Final verification that Terms, CLI README, human `help guide`, `help guide --json`, and `agents.md` do not conflict.

### Release blocker triage

This triage separates items that can be advanced inside the repository from items that require counsel or mainnet
deployment. It is a planning aid and not a legal opinion.

Counsel review deferral status:

- Business owner decision: counsel review is deferred to a far-future review cycle.
- The counsel-review items below remain recorded as long-term legal review topics, but they are not immediate
  implementation blockers unless a later release decision reopens them.
- Public documents must not state or imply that the current release is a draft, counsel-pending release, or legally
  unreviewed release.

Long-term deferred counsel-review items:

- Confirm whether the Privacy Notice requires counsel-directed changes and whether the Terms cross-reference to
  `docs/dapps/private-state/privacy-notice.md` is sufficient for the selected GitHub-only initial publication location.
- Confirm that Jehyuk Jang, `cjhyuck213@gmail.com`, Singapore, and no published residential address are sufficient for
  the individual Provider identity and public notice/contact route.
- Confirm the selected Tokamak Network PTE. LTD. separate-role wording as software contributor/licensor and, for
  Tokamak-controlled surfaces not operated by the Provider, Third-Party Service or infrastructure/tooling provider.
- Confirm the no-monetary-liability-cap approach and mandatory-law liability carveouts.
- Confirm Singapore governing-law/forum wording, including mandatory consumer-law and local-court carveouts.
- Confirm that arbitration, class-action waiver, collective-action waiver, representative-action waiver, and jury-trial
  waiver provisions remain excluded from the current draft.
- Confirm the selected principles-based sanctions/restricted-use policy and whether any named restricted jurisdictions,
  sanctions lists, sanctions authorities, account-level restrictions, screening, or additional warnings are required.
- Confirm final redlined Terms wording for Sections 3, 5, 6, 10, 12, 13, 14, 16, 17, 18, and 20.

Repository-action blockers that can be advanced without counsel:

- Keep the canonical Terms file and packaged CLI Terms asset identical after any counsel or product wording changes.
- Keep `termsVersion` and deterministic `termsHash` aligned with the final canonical Terms text.
- Re-run repository checks that Terms, CLI README, human `help guide`, `help guide --json`, and `agents.md` do not
  conflict after every final wording change.
- Re-run ordinary-user and User-Controlled AI Agent wording checks after every final wording change.
- Keep generated/public docs from manually claiming deployed behavior that has not been deployed or regenerated.

Deployment-dependent blockers:

- Completed: deploy the bridge upgrade that contains the Join Toll burn-address transfer and Channel Operation
  Abandonment source behavior.
- Completed: after the bridge upgrade, regenerate final deployment artifacts and Monitoring Packet JSON so
  `TPAC-Contract-Addresses.json`, `the-great-first-channel-Policy-Snapshot.json`, and ABI-derived monitoring data match
  the deployed mainnet ABI and state.
- Completed in the separate `channel-workspace-mirror` repository: observer ABI support, event decoding, event-list
  grouping, API payloads, and UI display now expose Channel Operation Abandonment and Join Toll burn-address transfer
  surfaces without implying custody, private-history monitoring, exchange-network control, or user-level blocking.

Current repository status:

- Repository-level consistency checks for Terms, Privacy Notice, CLI README, human `help guide`, `help guide --json`,
  `agents.md`, and monitoring companion documents have been completed for the current local source.
- Counsel-review items are deferred by business-owner decision. The next practical blockers are deployment-dependent
  unless new Terms wording changes are introduced.

### Practical minimum legal remediation plan

This section records the pre-counsel work completed before release planning advanced to deployment-dependent blockers. It
is based on
common treatment in comparable self-custody/open-software services, Singapore statutory risk areas, and Singapore
case-law direction that exclusion clauses are interpreted in context and remain subject to statutory limits such as UCTA
reasonableness where applicable. It is not intended to expand the project into a jurisdiction-by-jurisdiction legal
compliance program before counsel review.

Minimum document changes completed for the current implementation plan:

1. Privacy rights and request route:
   - Add a compact Privacy Notice section that states how users may contact the Provider about Provider-controlled
     processing, access requests, correction requests, consent withdrawal where applicable, deletion/review requests,
     and complaints.
   - State the practical limits clearly: public blockchain records, third-party service records, user-selected RPC logs,
     and user-local CLI files cannot be deleted or corrected by the Provider.
   - Do not add a full GDPR/CCPA-style supplement unless a later business-owner or counsel review concludes that the
     Service is intentionally offered to, or monitors, users in a jurisdiction requiring that supplement.
   - Status: Completed in `docs/dapps/private-state/privacy-notice.md` Section 19.
2. Retention and deletion limits:
   - Keep the existing operational-retention disclosures, but add a short plain statement that Provider-controlled
     operational logs and database rows are retained only as needed for operation, security, abuse prevention, debugging,
     evidence integrity, and legal purposes, subject to technical limits.
   - Do not promise fixed deletion periods for Neon, Vercel Blob, EC2 raw history, or public mirror artifacts unless the
     repository implements those retention controls.
   - Status: Completed in `docs/dapps/private-state/privacy-notice.md` Section 17.
3. International processing:
   - Add a concise Privacy Notice statement that official hosting, support, repository, package, artifact, analytics, and
     infrastructure providers may process data outside the user's country and that third-party services apply their own
     terms and safeguards.
   - Avoid overpromising specific transfer mechanisms unless a later counsel review confirms them.
   - Status: Completed in `docs/dapps/private-state/privacy-notice.md` Section 18.
4. Data breach contact:
   - Add a practical incident-contact statement: users may report suspected compromise of Provider-controlled systems to
     the privacy contact; the Provider will assess and notify affected persons or authorities when required by
     applicable law.
   - Do not add detailed statutory deadlines in user-facing text unless a later counsel review approves the exact
     wording.
   - Status: Completed in `docs/dapps/private-state/privacy-notice.md` Section 20.
5. Legal capacity:
   - Add ordinary-user wording that the Service is for users who have legal capacity to accept the Terms and operate a
     self-custody wallet. If a later counsel or business-owner review adds an age threshold, use exact reviewed wording;
     otherwise avoid creating a broad age-verification obligation that the Service cannot enforce.
   - Status: Completed in `docs/dapps/private-state/terms.md` Section 3 and
     `packages/apps/private-state/cli/assets/service-terms.md` Section 3.
6. Liability and indemnity:
   - Keep the no-Service-revenue, non-custodial, no-recovery, no-warranty, and no-monetary-cap position.
   - Keep mandatory-law carveouts for liability that cannot be excluded or limited.
   - Do not add a nominal monetary liability cap, arbitration clause, class-action waiver, jury-trial waiver, or detailed
     consumer-jurisdiction schedule in the current implementation.
   - For indemnity, keep the current clause for now and preserve the scope question for far-future counsel review.
   - Status: Completed by review. Current Terms Sections 15, 16, 17, and 20 already preserve the selected no-warranty,
     no-Service-revenue, no-monetary-cap, mandatory-law carveout, no-arbitration/no-waiver, and counsel-flagged
     indemnity approach without requiring wording changes.
7. Regulatory and sanctions wording:
   - Keep the existing position that the Service is not custody, exchange, brokerage, hosted transfer, legal advice,
     financial advice, tax advice, or compliance advice.
   - Keep the principles-based prohibited-use and sanctions wording.
   - Do not name restricted jurisdictions, sanctions lists, or screening mechanics in the current implementation.
   - Do not claim that the Service is unregulated, exempt, licensed, compliant, or approved by any regulator.
   - Status: Completed by review. Current public docs, CLI warning text, and canonical Terms preserve the no-custody,
     no-exchange, no-brokerage, no-hosted-transfer, no-advice, principles-based prohibited-use/sanctions approach and do
     not make regulator-approval, exemption, licensing, or compliance-status claims.
8. Electronic acceptance evidence:
   - Keep install-time explicit acceptance with Terms version and deterministic hash.
   - Keep acceptance local-only unless the Provider deliberately accepts additional server-side personal-data processing.
   - Ensure the CLI displays enough accepted-version/hash information for a user to preserve their own record.
   - Status: Completed by implementation and documentation review. Install and renewed acceptance require explicit
     interactive human acceptance, display the current Terms version and deterministic hash, persist the accepted
     version/hash metadata in the local CLI workspace, reject stale acceptance records, and document that the acceptance
     record is local by default.
9. Public-document consistency:
   - Re-run the public-document consistency pass after the minimum Privacy Notice and Terms changes.
   - Public documents must be written as if the planned release is complete, but must not claim mainnet deployment of
     Join Toll burn-address transfer, Channel Operation Abandonment, observer indexing, or monitoring packet changes
     until the deployment-dependent blockers are actually completed.
   - Status: Completed by repository-wide public-document review. Terms, Privacy Notice, CLI README, human `help guide`,
     `help guide --json`, `agents.md`, and monitoring companion documents were rechecked. Monitoring Packet companion
     rows for Join Toll burn-address transfer and Channel Operation Abandonment now remain marked pending until the
     bridge upgrade is deployed and the packet is regenerated.

Items to leave for counsel instead of expanding now:

- Whether Singapore PDPA applies to the individual Provider as an "organisation" for every Service surface.
- Whether a GDPR, UK GDPR, CCPA/CPRA, or other jurisdiction-specific supplement is required.
- Whether a physical notice address, registered agent, counsel address, or DPO-style contact label is required.
- Whether MAS Payment Services Act or Digital Token Service Provider analysis requires any wording beyond the current
  non-custody and no-service-revenue statements.
- Whether consumer indemnity should be narrowed and whether the current forum clause needs jurisdiction-specific
  consumer exceptions beyond the existing mandatory-rights carveout.
- Whether sanctions/restricted-use language must name specific lists, authorities, jurisdictions, or account-level
  restrictions.

## Open Legal Decisions

Status: the legal positions below are selected for current implementation and deferred to a far-future counsel review
cycle unless the business owner later reopens them.

- Provider Party model and public Provider details are selected: Jehyuk Jang, `cjhyuck213@gmail.com`, Singapore, and no
  published residential address. Tokamak Network PTE. LTD. is separately defined as software contributor/licensor and,
  for Tokamak-controlled surfaces not operated by the Provider, Third-Party Service or infrastructure/tooling provider;
  far-future counsel review remains recorded.
- Governing law and forum strategy is selected in principle: use Singapore with mandatory consumer-law carveouts unless a
  later business-owner or counsel review decision selects a different Provider-connected jurisdiction.
- Arbitration, class-action waiver, collective-action waiver, representative-action waiver, and jury-trial waiver
  provisions are excluded from the current draft. Far-future counsel review may revisit this decision.
- Liability cap business position is selected: the current draft does not include a nominal monetary liability cap. The
  draft position is that Provider Parties have no liability for Service use to the maximum extent permitted by applicable
  law, that mandatory-law liability carveouts remain preserved, and that future non-refundable Join Toll portions are
  not Provider Party revenue because they are transferred to `0x000000000000000000000000000000000000dEaD`.
- Sanctions and restricted-jurisdiction business position is selected: use a principles-based restricted-use and
  sanctions policy without naming specific restricted jurisdictions, sanctions lists, sanctions authorities, or prohibited
  user categories in the current draft. The draft must account for the technical constraint that the Service may block
  Ethereum Accounts or contract interactions, not real-world users. Far-future counsel review remains recorded.
- Repository-level final Privacy Notice review is complete. The initial Privacy Notice content, GitHub repository
  publication location, and Terms cross-reference are drafted.
- Required notice method for future terms changes.
- Separate command-level prompt policy is selected: install-time Terms acceptance replaces all repeated per-command
  `--acknowledge-action-impact` options. `uninstall`, secret-bearing material exports, and plaintext note/evidence
  exports must be interactive confirmation flows. Real-funds commands must print command-specific information and
  warning summaries in human and `--json` modes every time without requiring a command-level acknowledgement option.

## Post-Finalization Implementation Plan

Implementation must begin only after the Documentation and Terms Finalization Plan is complete, open legal and business
decisions are resolved or explicitly deferred, and the canonical Terms text has been frozen for implementation.

Current gating status: legal review items have been explicitly deferred by business-owner decision. Implementation may
continue to deployment-dependent blockers as long as no new public Terms or Privacy Notice wording changes are introduced.

### Phase 1: Canonical terms source

- Completed: add a packaged canonical terms file for the Service at
  `packages/apps/private-state/cli/assets/service-terms.md`.
- Completed: assign `termsVersion` = `2026-06-10`.
- Completed: compute a deterministic `termsHash` from the exact UTF-8 bytes of the packaged Service Terms Markdown.
- Completed: ensure install command results and `install --json` use the same canonical terms metadata.
- Completed: add repository test coverage that the packaged canonical Terms asset matches
  `docs/dapps/private-state/terms.md`.

### Phase 1A: Join Toll burn-address transfer implementation

- Completed: update `ChannelManager` refund schedule validation so `joinTollRefundBps1 <= joinTollRefundBps2 <=
  joinTollRefundBps3 <= joinTollRefundBps4`. Equal adjacent values remain valid, but the configured refund percentage
  must not decrease as participation time increases.
- Completed: update `BridgeCore` default Join Toll refund schedule. Public documents must still avoid presenting the
  Bridge default schedule as universal because each Channel fixes its own refund policy at Channel creation.
- Completed: update `L1TokenVault.exitChannel` so future Channel exits calculate `burnAddressTransferAmount =
  registration.joinTollPaid - refundAmount`.
- Completed: transfer `refundAmount` to the exiting user when non-zero.
- Completed: transfer `burnAddressTransferAmount` to `0x000000000000000000000000000000000000dEaD` when non-zero.
- Completed: reduce `_tollTreasuryBalance` by `refundAmount + burnAddressTransferAmount`.
- Completed: treat the change as future-only. Do not add a retroactive migration promise for users who already exited
  before this implementation ships.
- Completed: Terms and docs describe the non-refundable portion as a burn-address transfer, not as TON total-supply
  reduction.
- Completed: Terms and docs describe that Bridge default Join Toll refund policy may be updated, each Channel fixes its
  own refund policy at Channel creation, and users should verify the applicable policy through on-chain getters or
  official convenience views.

### Phase 1B: Channel Operation Abandonment implementation

- Completed: add an on-chain Channel Operation Abandonment state in the shared bridge/vault enforcement path, preferably in
  `L1TokenVault` or another upgradeable contract that `L1TokenVault` can check before join and deposit execution.
- Completed: add `abandonChannelOperation(channelId)` or equivalent. The caller must be the current Channel leader read from the
  canonical `ChannelManager.leader()` for the target `channelId`.
- Completed: record `channelOperationAbandonedAt[channelId]` and emit a public event with `channelId`, leader, and timestamp.
- Completed: do not add a grace period. The Channel becomes abandoned in the same transaction that records abandonment.
- Completed: reject `joinChannel(channelId, ...)` when the target Channel is abandoned.
- Completed: reject `depositToChannelVault(channelId, ...)` when the target Channel is abandoned.
- Completed: do not restrict `executeChannelTransaction`, note activity, `redeem-notes`, `withdrawFromChannelVault`, or
  `exitChannel` because of abandonment.
- Completed in local source: preserve compatibility with existing Channels, including `the-great-first-channel`, for the join/deposit enforcement
  path because those actions pass through the shared vault. Do not claim retroactive or on-chain restriction of existing
  Channel note activity. Existing mainnet Channels receive this behavior after the shared vault upgrade is deployed.
- Completed: add `channel abandon-operation` so the Channel leader can initiate abandonment through the CLI.
- Completed: update the CLI to read Channel Operation Abandonment status before Channel-scoped commands.
- Completed: in the CLI, return an error before `channel join` and `wallet deposit-channel` when the target Channel is abandoned.
- Completed: in the CLI, print an additional warning before other Channel activities when the target Channel is abandoned, including
  note activity, `redeem-notes`, `withdraw-channel`, and `exit-channel`.
- Completed for repository source/docs: update `help guide`, `help guide --json`, `agents.md`, README, Terms, and private-state
  workflow/security docs so users and User-Controlled AI Agents can distinguish active and abandoned Channels.
- Completed in this repository: Monitoring Packet docs/data now include Channel Operation Abandonment and Join Toll
  burn-address transfer event surfaces after the bridge upgrade.
- Completed in the separate `channel-workspace-mirror` repository: public observer data support now indexes
  `ChannelOperationAbandoned` and `ChannelExitTollBurned` from the upgraded mainnet ABI.
- Checklist review result: no explicit `checklist.md` violation was found because this plan preserves transparent L1
  boundaries, does not make private notes exchange-depositable, does not add a custody or viewing-key backdoor, and keeps
  redeem/withdraw/exit paths available. The final wording must still avoid presenting abandonment as exchange-network
  control, operator custody, or private-history monitoring.

### Phase 2: Interactive install gate

- Completed: change `private-state-cli install` from non-interactive to interactive.
- Completed: render the canonical Terms before installation.
- Completed: require explicit human acceptance before installation proceeds.
- Completed: persist the accepted `termsVersion`, `termsHash`, timestamp, CLI package version, and acceptance source in
  Service state.
- Completed UX issue review from local read-only artifact update: printing the entire Terms as one long terminal block can be
  cut off by terminal scrollback or make users lose context before acceptance.
- Completed in local source: replaced the single long Terms prompt with category-by-category Terms prompts using the
  categories in the Human Acceptance Strategy.
- Completed in local source: require a separate explicit human acceptance phrase for each category and persist the
  accepted category IDs alongside `termsVersion`, `termsHash`, timestamp, CLI package version, and acceptance source.
- Completed in local source: after each correct category phrase, print an immediate acknowledgement line before showing
  the next category.
- Completed in local source: after the final category phrase, print an immediate final acknowledgement line before any
  long-running install step begins so the user does not mistake a slow install for a failed acceptance input.
- Completed verification that JSON mode refuses to accept Terms for the user while describing the category-based human
  flow.
- New UX issue found during attempted local artifact update: even category-by-category terminal acceptance remains too
  cumbersome for ordinary users, and Terms display is still constrained by terminal scrollback and text-entry ergonomics.
- Completed in local source: made browser-based localhost Terms acceptance the primary `install` flow. The CLI opens a
  nonce-protected `127.0.0.1` Terms page, lets the human user review the full Terms and accept them once, then
  returns to the terminal and starts installation only after the validated browser callback.
- Completed in local source: removed the TTY requirement from the browser-based Terms flow so a User-Controlled AI Agent
  can run `private-state-cli install` through a non-TTY process while the human user accepts Terms in the browser.
- Completed in local source: kept terminal acceptance only as an explicit `--terminal-terms` fallback for environments
  where the local browser flow cannot be used.
- Completed in local source: updated `install --json` so it still never accepts Terms, reports
  `browser_localhost_interactive`, describes the localhost browser flow, and instructs User-Controlled AI Agents not to
  click browser acceptance controls or type fallback acceptance phrases for the user.
- Completed in local source: after browser acceptance succeeds, immediately print
  `Terms accepted in browser. Starting installation...` before any slow install work begins.
- Remaining human verification: run interactive install in a terminal, verify that the browser opens to a simple
  localhost Terms page, the single accept button returns control to the CLI, the terminal prints the immediate
  acknowledgement before slow work, and JSON mode still refuses to accept Terms for the user.

### Phase 3: Renewed acceptance mechanism

- Completed: add a terms-gate helper that compares the accepted record against the canonical `termsVersion` and
  `termsHash`.
- Completed: require renewed interactive acceptance when the accepted record is missing, mismatched, or unreadable.
- Completed: apply this helper before installation and before any terms-gated command that can affect user funds, user secrets,
  Channel membership, Channel accounting, or public observer state.
- Completed: do not allow JSON mode or User-Controlled AI Agent mode to write an acceptance record.

### Phase 4: Complete warning-summary and confirmation prompt implementation

- Keep `--acknowledge-action-impact` removed from ordinary transaction commands and command-reference surfaces.
- Do not keep any command-level legal acknowledgement flag for ordinary transaction commands.
- Completed: implemented the install-time Terms gate so ordinary transaction commands are protected by the one-time Terms
  acceptance model rather than repeated per-command acknowledgement flags.
- Completed: change `uninstall` to an interactive confirmation flow like `install`.
- Completed: make default `uninstall` preserve wallet workspace spending-key and viewing-key files while deleting the
  rest of the local private-state CLI workspace.
- Completed: add `uninstall --include-wallet-keys`; when this option is present, delete all local private-state CLI data
  without preserving wallet key files.
- Completed: before uninstall deletion, print the destructive result, retained or deleted wallet-key scope, relevant
  precautions, no-recovery limits, and Provider Party disclaimers, then require explicit human confirmation.
- Completed: change secret-bearing material export commands, including viewing-key and spending-key exports, to
  interactive confirmation flows. Before export, print secret-leakage risk, storage precautions, no Provider recovery,
  and Provider Party disclaimers, then require explicit human confirmation.
- Completed: change plaintext note/evidence export commands to interactive confirmation flows. Before export, print
  plaintext disclosure risk, full wallet-history or evidence-scope risk, sharing precautions, no Provider recovery,
  User-Controlled AI Agent handling limits, and Provider Party disclaimers, then require explicit human confirmation.
- Completed: for every command that handles real funds, print command-specific information and warning summaries on every run in
  human mode and in `--json` mode. These summaries must be non-blocking unless the command also falls into an
  interactive destructive or sensitive-export category above.

### Phase 5: JSON and User-Controlled AI Agent updates

- Completed early as a repository-level safety fix: `install --json` reports that human interactive acceptance is
  required, returns `installed: false`, and does not install artifacts.
- Completed early as a repository-level safety fix: `help guide --json` references canonical Terms sections and indexed
  `agents.md` sections instead of duplicating long warnings.
- Completed early as a repository-level safety fix: User-Controlled AI Agent directives require explanation of
  public/private boundaries, prohibited uses, Self-Custody, no recovery method, Third-Party Service risk, no
  professional advice, no warranties, liability limits, and Official Public Observer limits through `agents.md` item
  `E.3`, which every `help guide --json` result now references.

### Phase 6: Human help and documentation integration

- Completed: integrate finalized human `help guide` text into the CLI.
- Completed: integrate finalized CLI README language stating that `--json` exists for User-Controlled AI Agents that help users
  complete minimum safe next actions without handling secrets or accepting Terms for users.
- Completed: update `packages/apps/private-state/README.md` so its CLI overview matches the current and planned final CLI behavior:
  no ordinary command-level `--acknowledge-action-impact`, interactive install-time Terms acceptance, interactive
  destructive and sensitive-export confirmations, default wallet-key-preserving `uninstall`, `uninstall
  --include-wallet-keys`, interactive plaintext evidence export, and the current `User-Controlled AI Agent Guidance`
  link and terminology.
- Completed repository-level terminology check for the implemented human-facing Terms, README, and command-reference
  surfaces: unnecessary `L2` shorthand was removed from Terms definitions, and public-chain boundary wording remains
  expressed as "Ethereum mainnet" on those surfaces.

### Phase 7: Implementation verification

- Completed: verify that interactive install blocks installation until Terms are accepted.
- Completed: verify that future `exitChannel` calls refund the refundable Join Toll portion and transfer the non-refundable portion
  to `0x000000000000000000000000000000000000dEaD`.
- Completed: verify that `_tollTreasuryBalance` decreases by both the refunded amount and the burn-address transfer
  amount.
- Completed: verify that Terms and docs do not describe the Join Toll burn-address transfer as TON total-supply
  reduction.
- Completed: verify that `ChannelManager` rejects decreasing Join Toll refund schedules and accepts flat or increasing
  schedules.
- Completed: verify that refund quotes increase or remain flat as elapsed Channel participation time increases.
- Completed: verify that Terms and user-facing docs do not present one concrete refund schedule as universal for all
  Channels.
- Completed: verify that only the Channel leader can initiate Channel Operation Abandonment for that Channel.
- Completed: verify that abandonment is immediate and records a public timestamp/event.
- Completed: verify that abandoned Channels reject new `joinChannel` and `depositToChannelVault` calls.
- Completed: verify that abandoned Channels still allow `withdrawFromChannelVault` and `exitChannel`.
- Completed: verify that abandonment does not restrict `executeChannelTransaction` or note activity on-chain.
- Completed by source-level CLI checks: verify that the CLI errors for `channel join` and `wallet deposit-channel` on abandoned Channels.
- Completed by source-level CLI checks: verify that the CLI warns, but does not block, other Channel activity on abandoned Channels.
- Completed by shared-vault source design: verify that `the-great-first-channel` can be covered by join/deposit abandonment enforcement after the shared vault
  upgrade, while existing Channel note activity remains unrestricted on-chain.
- Completed: verify that final docs and machine-readable guidance describe abandonment without implying custody, private-history
  access, exchange deposit network control, or user-level blocking.
- Verified that `install --json` does not install artifacts or accept Terms.
- Verified that `install --json` reports the canonical Terms version and deterministic Terms hash from the packaged
  Service Terms source.
- Completed: verify that a changed terms hash requires renewed interactive acceptance.
- Completed: verify that terms-gated commands reject execution when acceptance is missing or stale.
- Completed: verify that per-command `--acknowledge-action-impact` options are no longer required.
- Completed: verify that no command still exposes `--acknowledge-action-impact`.
- Verified command schema, command help, README, non-interactive rejection, and isolated destructive end-to-end behavior
  with a temporary HOME and fake npm for default `uninstall` wallet-key preservation and `uninstall --include-wallet-keys`
  full deletion. Destructive uninstall was not run against the user's real workspace.
- Verified command help, non-interactive rejection, and isolated interactive export behavior for wallet viewing-key and
  spending-key exports.
- Verified plaintext note/evidence export confirmation wording, command help, README, investigator README, and
  evidence-scope documentation for plaintext disclosure risk, wallet-history scope, User-Controlled AI Agent handling
  limits, no Provider recovery, and Provider Party disclaimer coverage.
- Completed: verify that real-funds commands print command-specific information and warning summaries in both human and `--json`
  modes without requiring a command-level acknowledgement option.
- Verified that `help guide --json` points to canonical section numbers and does not duplicate full legal text.
- Completed: verify that human `help guide` remains readable for ordinary users.
- Completed repository-level public-document consistency review for Terms, Privacy Notice, root README, private-state
  app README, CLI README, human `help guide`, `help guide --json`, `agents.md`, public observer documentation,
  monitoring packet companion docs, and audit-facing docs. The review found and fixed the monitoring companion-document
  gap for Channel Operation Abandonment and Join Toll burn-address transfer event surfaces.
- Completed: after the bridge upgrade and final deployment artifact regeneration, regenerated the Monitoring Packet JSON
  and ABI-derived data so `TPAC-Contract-Addresses.json` and `the-great-first-channel-Policy-Snapshot.json` reflect the
  deployed Join Toll burn-address and Channel Operation Abandonment surface.
- Completed in the separate `channel-workspace-mirror` repository: observer indexing and UI/API exposure for
  `ChannelExitTollBurned`, `ChannelOperationAbandoned`, and Channel Operation status have been updated and redeployed.
- Completed: verify that no public document still describes `--acknowledge-action-impact` or
  `--acknowledge-full-note-plaintext-export` as required user options after the final prompt policy is implemented.
- Completed: verify that no public document uses stale `LLM Agent Guidance` anchors or older agent terminology where the intended
  audience is a User-Controlled AI Agent.

### Phase 8: Safe multisig mainnet upgrade flow

- Completed in repository tooling: replace the previous EOA-executed `upgrade` mode in
  `bridge/scripts/deploy-bridge.mjs` with a Safe-based upgrade plan flow.
- Completed in repository tooling: add `bridge/scripts/PrepareSafeBridgeUpgrade.s.sol` to deploy new implementation and
  support contracts without calling owner-only proxy or bridge administration functions.
- Completed in repository tooling: remove the previous direct EOA upgrade script.
- Completed in repository tooling: write Safe Transaction Builder JSON and a raw transaction review plan under
  `deployment/chain-id-<chain-id>/bridge-upgrade-plans/<timestamp>/`.
- Completed in repository tooling: verify that the planned Safe owner owns `DAppManager`, `BridgeCore`, and
  `L1TokenVault` before writing the Safe batch.
- Completed in repository documentation: document that `upgrade` plan generation does not update the canonical deployed
  bridge artifact before the generated Safe batch is executed.
- Completed operator step: ran `node bridge/scripts/deploy-bridge.mjs --network mainnet --mode upgrade` from commit
  `9882c1a5e372089ca83e358ba3310fce3af1f698`, deployed the new implementation and support contracts, and generated the
  local Safe plan under `deployment/chain-id-1/bridge-upgrade-plans/20260610T194641Z/`.
- Completed operator step: imported
  `deployment/chain-id-1/bridge-upgrade-plans/20260610T194641Z/safe-transaction-builder.1.json` into the Safe, reviewed
  the batch, collected 2-of-3 approvals, and executed it.
- Completed verification: confirmed on Ethereum mainnet that `DAppManager`, `BridgeCore`, and `L1TokenVault` use the
  expected new implementation addresses, still have the Safe as owner, and point at the expected support contracts.
- Completed follow-up: regenerated final bridge deployment artifacts and regenerated the Monitoring Packet.
- Observer verification result: the public observer API now reports the upgraded bridge implementation addresses, the
  existing `the-great-first-channel` fixed Join Toll refund schedule, `join_toll_burn_address:
  0x000000000000000000000000000000000000dEaD`, `channel_operation_abandoned_at: null`, and UI/API support for
  `ChannelExitTollBurned` and `ChannelOperationAbandoned`.

### Phase 9: Channel-Scoped Mirror And Observer Responsibility Realignment

Purpose: realign Service responsibility and URL discovery so the CLI belongs to Tonnel, while mirror servers and
observer services belong to each Channel. Tonnel-level software must not hardcode a Channel-specific mirror or observer
URL. Users, User-Controlled AI Agents, public documents, and generated monitoring data must be able to distinguish
Tonnel-level software responsibility from Channel-scoped mirror and observer responsibility, even when the same person
is responsible for both scopes.

Selected responsibility model:

- Tonnel Provider: Jehyuk Jang.
- The Great First Channel Provider: Jehyuk Jang.
- Tokamak Network PTE. LTD. remains a separate software contributor/licensor and Third-Party Service or
  infrastructure/tooling provider where applicable. It is not the Tonnel Provider under this plan unless it expressly
  assumes that role in a separate binding Service document.
- Mirror servers and observer services are Channel-scoped services, not Tonnel-wide services.
- Each Channel Provider is responsible for that Channel's mirror server and observer service if the Channel Provider
  registers those URLs on-chain.
- For The Great First Channel, the mirror server and observer service are provided by Jehyuk Jang as The Great First
  Channel Provider. This is the same person as the Tonnel Provider, but the responsibility is still Channel-scoped.
- Public documents must generalize this model for all Channels. They must not imply that every Channel's mirror server
  or observer is operated by Jehyuk Jang, Tokamak Network PTE. LTD., or by the same operator as The Great First Channel.

Phase baseline findings:

- Mirror URL discovery is already Channel-scoped. `BridgeCore.setChannelWorkspaceMirror(channelId, uri)` and
  `BridgeCore.getChannelWorkspaceMirror(channelId)` store and read one workspace mirror URL per Channel. Only the
  on-chain Channel leader can update the registered mirror URL.
- The Great First Channel's current registered mirror URL is `https://project-scw1r.vercel.app`, as reflected by the
  generated Monitoring Packet.
- Original observer URL discovery was wrong for the selected responsibility model. The CLI hardcoded
  `https://observer.tonnel.io` in `PRIVATE_STATE_OBSERVER_URL`, and `help observer` printed that deployed public observer
  URL without resolving it from the selected Channel. The local CLI source has since been updated under item 2.
- Current Terms, packaged Service Terms, Privacy Notice, public observer docs, and monitoring docs still use older or
  conflicting model text in places: `observer.tonnel.io` is described as the Official Public Observer, and Tokamak
  Network PTE. LTD. must not be identified as Provider under the corrected plan. Those statements must be rewritten.

Implementation plan:

1. Contract model:
   - Keep the existing Channel workspace mirror registry for backward-compatible mirror URL discovery.
   - Add a Channel-scoped observer URL registry to the bridge. Use explicit methods rather than a Tonnel-wide constant,
     for example `setChannelObserver(uint256 channelId, string uri)` and
     `getChannelObserver(uint256 channelId)`, or an equivalent clearly named API.
   - Restrict observer URL updates to the Channel leader, matching the mirror URL authority model.
   - Emit an event such as `ChannelObserverUpdated(channelId, leader, previousUri, newUri)`.
   - Apply the same basic constraints as mirror URLs where appropriate: existing Channel required, Channel leader
     required, URI length bounded, empty URI clears the observer URL.
   - Add tests for leader-only update, clearing, oversized URI rejection, unknown Channel rejection, and independent
     mirror/observer values.
   - Status: completed in local bridge source with `setChannelObserver`, `getChannelObserver`,
     `ChannelObserverUpdated`, leader-only updates, 2048-byte URI limit, empty-URI clearing, and focused
     `BridgeFlow.t.sol` coverage. The bridge-specific test suite passes with
     `cd bridge && forge test --match-path test/BridgeFlow.t.sol`.

2. CLI model:
   - Remove the Tonnel-level hardcoded observer URL constant from user-visible behavior.
   - Change `help observer` so it requires or resolves a Channel selector and network selector, reads that Channel's
     observer URL from the bridge, and prints the Channel-scoped observer URL.
   - If no observer URL is registered for the selected Channel, show a clear human error and a JSON error explaining
     that no Channel Provider has registered an observer for that Channel.
   - Keep mirror recovery behavior Channel-scoped through the existing on-chain mirror URL.
   - Update `help guide` and `help guide --json` so User-Controlled AI Agents understand that mirror and observer URLs
     must be obtained from on-chain Channel metadata, not from Tonnel-wide defaults.
   - Update command registry metadata and CLI README text that currently describes a single deployed observer URL.
   - Status: completed in local CLI source. `help observer` now requires `--network` and `--channel-name`, validates the
     selected RPC chain, reads `BridgeCore.getChannelObserver(channelId)`, fails when no Channel observer is registered,
     and no longer contains a Tonnel-level observer URL constant. `help guide --json` now exposes `observerUrl` and
     `observerError` under Channel on-chain state. Command registry, README, and `agents.md` now describe observer URLs
     as Channel-scoped on-chain metadata. The CLI agent-guidance test passes with
     `npm run test:agent-guidance` from `packages/apps/private-state/cli`.

3. Public documents:
   - Redefine Terms actors:
     - Tonnel Provider means Jehyuk Jang for Tonnel-level software and Tonnel-level official interfaces.
     - Channel Provider means the person or entity that operates or provides Channel-specific services for a Channel.
     - The Great First Channel Provider means Jehyuk Jang.
     - Tokamak Network PTE. LTD. must remain separately defined as software contributor/licensor and Third-Party Service
       or infrastructure/tooling provider where applicable, not as Provider.
     - Provider Parties must be scoped or qualified so Tonnel-level responsibilities and Channel-scoped mirror/observer
       responsibilities are not confused.
   - Update Terms and packaged CLI Terms so "Service", "Provider", "Provider Parties", "Official Public Observer",
     "Official workspace mirror", and "Third-Party Services" match the new split responsibility model.
   - Update Privacy Notice so it no longer presents `observer.tonnel.io` as a universal Tonnel observer. It should say
     that observer and mirror services are Channel-scoped and that The Great First Channel's current registered URLs are
     operated by Jehyuk Jang as The Great First Channel Provider.
   - Update all public docs to state that mirror and observer URLs are read from on-chain Channel metadata. Static URL
     examples may be shown only as examples for a specific Channel and must not be described as Tonnel-wide defaults.
   - Update monitoring docs and Monitoring Packet generation so Channel observer URL, if available, is read from
     on-chain state alongside the workspace mirror URL.
   - Status: completed in local public documentation and monitoring sources. Terms and packaged CLI Terms now define
     Tonnel Provider, Channel Provider, Channel-scoped Official Public Observer, and Channel-scoped Official Workspace
     Mirror separately. Privacy Notice now treats `observer.tonnel.io` and the workspace mirror as The Great First
     Channel-specific services operated by Jehyuk Jang as The Great First Channel Provider, not as Tonnel-wide defaults.
     Monitoring Packet documentation and the policy snapshot generator now include the selected Channel's observer URL
     from on-chain Channel metadata, and the current The Great First Channel policy snapshot includes
     `channelObserverUrl`.

4. Deployment and migration:
   - Deploy the bridge upgrade that adds Channel observer URL registry support.
   - Have The Great First Channel leader register the current observer URL on-chain after deployment.
   - Regenerate deployment artifacts and Monitoring Packet data so the on-chain observer URL appears in generated data.
   - After the separate `channel-workspace-mirror` observer update is deployed, verify that the registered observer URL
     serves the expected Channel.
   - Status: bridge upgrade executed; Channel observer URL registration completed. Commit
     `1f350c52d18033a4e6872e0005d0b3c8684718e2` was pushed to
     `origin/main`, the remote-main deployment gate passed, and the bridge Solidity diff check found
     `bridge/src/BridgeCore.sol` changed since deployment commit `9882c1a5e372089ca83e358ba3310fce3af1f698`. After
     deployer funding was restored, `node bridge/scripts/deploy-bridge.mjs --network mainnet --mode upgrade` deployed
     implementation contracts and produced an initial Safe upgrade batch at
     `deployment/chain-id-1/bridge-upgrade-plans/20260611T081202Z/safe-transaction-builder.1.json`.
   - The initial `20260611T081202Z` Safe batch is invalid and must not be executed. Safe simulation failed because the
     generated batch mapped the BridgeCore proxy upgrade to `0x4A250bf7355a585aaDC54759D09AaF03C60Ef065`, which on-chain
     selector checks identify as an `L1TokenVault` implementation, not a `BridgeCore` implementation.
   - A corrected minimal Safe upgrade batch was generated at
     `deployment/chain-id-1/bridge-upgrade-plans/20260611T084416Z/safe-transaction-builder.1.json`. It contains only
     `BridgeCore.upgradeTo(0xCd96A6205207470E293E0dd770EA74d736b7F5bf)` for BridgeCore proxy
     `0x992E2Ae206620d811832a8F697c526c4f95974b6`. The `BridgeCore.sol` source is the only bridge source changed since
     the previous mainnet deployment, and an `eth_call` simulation from Safe
     `0xBE637160D21975EF1e0270D32Bfc547c2EA8DcC3` to the BridgeCore proxy with this calldata succeeded.
   - Completed: the Safe executed the corrected BridgeCore-only batch. On-chain verification confirmed BridgeCore proxy
     `0x992E2Ae206620d811832a8F697c526c4f95974b6` now stores implementation
     `0xCd96A6205207470E293E0dd770EA74d736b7F5bf` in the EIP-1967 implementation slot, and the proxy owner remains Safe
     `0xBE637160D21975EF1e0270D32Bfc547c2EA8DcC3`.
   - Completed: The Great First Channel leader `0x32e6EE3d9820F0843E3e596132368747d36425F0` registered
     `https://observer.tonnel.io` through `BridgeCore.setChannelObserver(channelId, uri)` for Channel ID
     `108336797649051254585401751173864353497144788660297920004548699607442466523065` in transaction
     `0xe0f8b3d17a2396d5462208127d6d7d9652ce5b5ec2c4bef6898d33993a2bec51`. On-chain verification confirmed
     `BridgeCore.getChannelObserver(channelId)` returns `https://observer.tonnel.io`.
   - Completed: generated a final local bridge deployment snapshot at
     `deployment/chain-id-1/bridge/20260611T091000Z/` with BridgeCore implementation
     `0xCd96A6205207470E293E0dd770EA74d736b7F5bf` and deployed source commit
     `1f350c52d18033a4e6872e0005d0b3c8684718e2`. Regenerated Monitoring Packet data from this final snapshot and
     on-chain state; the public policy snapshot now matches the registered Channel observer URL.
   - Completed: changed Monitoring Packet generation so ChannelCreated anchors are read through Etherscan when an API
     key is available, with a wider RPC chunk fallback. The previous 10-block-only RPC scan path made mainnet
     regeneration impractically slow over mainnet ranges and failed to preserve ChannelCreated anchors on providers with
     strict `eth_getLogs` range limits.
   - Completed: fixed `help observer` command metadata and BridgeCore ABI feature detection. The command now declares
     read-only deployment artifact requirements, and stale installed artifacts now produce a clear
     `MISSING_DEPLOYMENT_ARTIFACTS` reinstall message instead of an internal TypeError.
   - Remaining local-operator step: run interactive `private-state-cli install --read-only --include-local-artifacts`,
     or publish updated read-only deployment artifacts and then run interactive `private-state-cli install --read-only`,
     before expecting an already installed local CLI cache to resolve `help observer` directly from the upgraded ABI.
     The CLI correctly reports a `MISSING_DEPLOYMENT_ARTIFACTS` reinstall-required error while the local installed ABI
     is stale. Local CLI agent-guidance tests pass.

5. Verification:
   - Completed: verified that public Terms, packaged CLI Terms, Privacy Notice, CLI README, `agents.md`, and Monitoring
     Packet docs do not state that `observer.tonnel.io` is the universal Official Public Observer for all Tonnel
     Channels. The only remaining references describe it as The Great First Channel's registered observer URL.
   - Completed: verified that the CLI source no longer contains a user-visible `PRIVATE_STATE_OBSERVER_URL` constant and
     that `help observer` reads `BridgeCore.getChannelObserver(channelId)` for the selected Channel.
   - Completed: verified that current `help observer --json` and human `help observer` fail clearly with
     `MISSING_DEPLOYMENT_ARTIFACTS` when the already installed local read-only ABI is stale and lacks
     `BridgeCore.getChannelObserver`. The command does not fall back to a hardcoded URL.
   - Remaining after local artifact update: verify that `help observer --json` and human `help observer` print the
     registered Channel observer URL for `the-great-first-channel`, and verify that both modes fail clearly when the
     selected Channel exists but has no registered observer URL.
   - Completed: verified that `help guide --json` includes `agentGuidance.termsRefs`, `agentGuidance.refs`, and
     Channel on-chain observer metadata fields for User-Controlled AI Agents.
   - Completed: verified that Terms and Privacy Notice consistently identify Jehyuk Jang as both Provider and The Great
     First Channel Provider while still treating mirror and observer responsibility as Channel-scoped.
   - Completed: verified that Terms and Privacy Notice do not identify Tokamak Network PTE. LTD. as Provider under the
     current plan.
   - Completed: verified that generated Monitoring Packet JSON distinguishes Channel-scoped `workspaceMirrorUrl` and
     `channelObserverUrl` from Tonnel-wide software or documentation URLs.

Release blocker:

- Completed: public release documents have been updated away from the old provider model for Terms, Privacy Notice, CLI
  README, packaged Terms, human help, JSON help, `agents.md`, and monitoring docs.
- Completed: the CLI no longer hardcodes `observer.tonnel.io` as a Tonnel-level URL after the on-chain Channel observer
  registry implementation.
- Remaining local release-readiness action: update local installed read-only deployment artifacts through the
  browser-based interactive human install flow. The user must read and accept the Terms personally in the browser;
  User-Controlled AI Agents and automation must not click browser acceptance controls or type fallback Terms acceptance
  phrases for the user.
- After that human install flow, rerun the `help observer` registered and unregistered observer checks.

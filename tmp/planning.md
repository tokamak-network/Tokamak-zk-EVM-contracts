# Private-State DApp and Tonnel Channel Terms Plan

## Purpose

This document plans the terms acceptance flow for the Private-State DApp, Tonnel, its dedicated Channel
`the-great-first-channel`, and the CLI used to access them. The CLI is only one interface and acceptance mechanism. The
Terms are for the Service as a whole.

The target reader is an ordinary user, not a protocol developer. The terms text must therefore define necessary technical
terms first, use those terms consistently, and avoid marketing language that could misstate the public and private
boundaries of the system.

This document is a product and implementation plan. It is not legal advice. Final legal entity names, governing law,
venue, consumer-law carveouts, liability caps, and dispute provisions must be reviewed by counsel before release.

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
- Internal Private Note transfers may prevent public contract state from reconstructing sender-recipient relationships
  and note provenance by default, but no privacy, anonymity, compliance result, or exchange acceptance is guaranteed.
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

Conclusion: the terms draft below covers every checklist item that affects Service users. Counsel should still review
the final legal wording before production release.

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
- **L2** means the Tonnel private application state used for Channel accounting and Private Notes. Because this term is
  technical, these Terms use "Tonnel private application state" whenever possible.
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
- **Official Public Observer** means the public Tonnel observer service provided at `https://observer.tonnel.io`, or a
  successor URL published through an official project channel.
- **Provider Parties** means the legal entities that officially make the Service available and their affiliates,
  directors, officers, employees, contractors, agents, licensors, service providers, and authorized representatives.
- **Channel Operators** means persons or entities that create, configure, administer, publish policies for, publish
  recovery metadata for, or otherwise operate a Channel.
- **Third-Party Services** means wallets, RPC providers, exchanges, explorers, analytics providers, browsers, package
  registries, operating systems, cloud services, and other services not controlled by the Provider Parties.
- **User-Controlled AI Agent** means an AI tool, assistant, or automated system selected, configured, or used by the user
  to interpret Service output or assist with Service use.
- **Official Machine-Readable Output** means JSON or similar structured output generated by the CLI or another official
  Service interface for software tools or User-Controlled AI Agents.

### 2. Product boundary

- These Terms govern access to and use of the Service.
- The Service includes the Private-State DApp, Tonnel, The Great First Channel, Bridge workflows, the CLI, official
  public observer services, official documentation, official examples, official deployment artifacts, and related
  software or interfaces officially made available by the Provider Parties.
- Tonnel is the branded name for Tokamak Private App Channels.
- Tonnel is an opt-in private application-channel system used from a Self-Custody Ethereum Account.
- The Great First Channel is a Channel within Tonnel.
- Tonnel does not alter TON transfer rules on Ethereum mainnet.
- Through the Service, Provider Parties do not provide exchange deposit services, exchange withdrawal services,
  brokerage, custodial wallet services, hosted transfer services, asset recovery services, compliance services, or tax
  services.
- Nothing in these Terms is a determination of the regulatory status of any person, entity, software, transaction,
  network, token, or service under applicable law.
- Private Notes are Channel-local application records. They are not separate exchange-depositable assets.
- Exchange-facing TON transfers, Ethereum mainnet bridge deposits, and Ethereum mainnet bridge withdrawals remain public
  or observable through Ethereum mainnet records.

### 3. Acceptance and eligibility

- By submitting the required acceptance confirmation, by clicking an acceptance control, or by continuing to access or use
  the Service after these Terms are presented, the user accepts these Terms.
- If the user does not accept these Terms, the user must not access, install, or use the Service.
- The user represents that the user has legal capacity to accept these Terms.
- If the user acts for an organization, the user represents that the user has authority to bind that organization.
- The user represents that use of the Service is not prohibited by laws applicable to the user.
- The user represents that the user is not subject to sanctions and is not located, organized, resident, or ordinarily
  resident in a jurisdiction where use would be prohibited by applicable sanctions, export control, anti-money laundering,
  counter-terrorist financing, securities, commodities, tax, data-protection, or other applicable laws.

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

- Tonnel may prevent public contract state from reconstructing some internal Private Note sender-recipient relationships,
  Private Note plaintext, and Private Note provenance by default.
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
- The user must review applicable Channel policy before joining a Channel.
- The user must use only trustworthy software, package sources, websites, wallets, RPC providers, and devices.

### 9. Channel policy and Channel Operator limitations

- Joining a Channel means accepting that Channel's policy snapshot.
- Channel policy may include join fees, refund rules, administrative roles, operator roles, backup or recovery information
  expectations, monitoring practices, fee rules, or other operating rules.
- Channel Operators may publish public metadata, policy information, event records, or recovery information.
- Channel Operators do not control the user's Ethereum Account or user secrets.
- Channel Operators do not guarantee recovery of lost user secrets, lost Private Notes, lost evidence, failed
  transactions, Third-Party Service failures, or rejected exchange deposits.

### 10. Official public observer, monitoring, and evidence

- Tonnel provides an Official Public Observer at `https://observer.tonnel.io`.
- The Official Public Observer may display public Ethereum mainnet records, public Channel records, accepted
  transitions, commitments, nullifiers, encrypted note-delivery events, accounting updates, and related monitoring data.
- The Official Public Observer does not reveal user secrets and does not guarantee that every fact needed for legal,
  accounting, tax, exchange, asset-history, or compliance review is available.
- Exchanges, analytics providers, regulators, Channel Operators, users, and other observers may independently monitor
  Ethereum mainnet and public Channel records.
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
- If Provider Parties collect or process personal data through any official interface, that processing must be described
  in an applicable privacy notice or privacy policy.
- Third-Party Services may collect or process user data under their own terms and privacy policies.

### 13. No professional advice

- Provider Parties do not provide legal, tax, accounting, financial, investment, trading, compliance, sanctions, or
  regulatory advice through the Service or Official Machine-Readable Output.
- Information provided through the Service or Official Machine-Readable Output is for operational and informational
  purposes only.
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

- To the maximum extent permitted by applicable law, Provider Parties are not liable for indirect, incidental, special,
  consequential, exemplary, punitive, or similar damages.
- To the maximum extent permitted by applicable law, Provider Parties are not liable for lost profits, loss of data, lost
  secrets, failed transactions, wrong transactions, loss of access, loss of assets, loss of evidence, business
  interruption, Third-Party Service failures, exchange actions, regulatory actions, tax consequences, user error, device
  compromise, or unauthorized access.
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
- The user must not rely on Official Machine-Readable Output or a User-Controlled AI Agent to accept changed Terms on the
  user's behalf.

### 19. Suspension, discontinuation, and software changes

- Provider Parties may modify, suspend, discontinue, or stop supporting software, documentation, public observer services,
  deployment artifacts, examples, or related services.
- Open-source smart contracts and public blockchain records may continue to exist independently of any supported
  interface.
- Provider Parties cannot reverse public Ethereum mainnet transactions or recover user secrets.

### 20. Governing law, venue, dispute resolution, and notices

- These Terms are governed by the laws of [Governing Jurisdiction], excluding conflict-of-law rules.
- Subject to non-waivable rights under applicable law, disputes arising from or relating to these Terms or the Service
  will be resolved in [Forum and Venue].
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
- `terms_acceptance_actor: "human_user_only"`,
- `terms_refs`, containing section numbers from the installed terms document,
- a directive that the User-Controlled AI Agent must instruct the user to run interactive `private-state-cli install`
  directly,
- a directive that the User-Controlled AI Agent must summarize the Terms before the user accepts,
- a directive that the User-Controlled AI Agent must not ask the user to disclose private keys, seed phrases, wallet
  secrets, spending keys, viewing keys, or equivalent secrets,
- a directive that the User-Controlled AI Agent must not type or submit the acceptance phrase for the user.

The JSON output should identify referenced terms as terms-document section numbers, for example:

```json
{
  "ok": false,
  "next_action": "human_interactive_install_required",
  "terms_required": true,
  "terms_source": "private-state-cli install",
  "terms_acceptance_actor": "human_user_only",
  "terms_refs": ["1", "2", "4", "5", "6", "7", "10", "11", "12", "13", "14", "15", "16", "18", "20"],
  "agent_directives": [
    "Explain the referenced terms sections to the user before interactive install.",
    "Direct the user to run private-state-cli install in an interactive terminal.",
    "Do not collect or display the user's secret material.",
    "Do not accept the terms for the user."
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
- the related `AGENTS.md` guidance section numbers if applicable,
- a directive that the User-Controlled AI Agent must explain user-facing warnings in ordinary language before the user
  acts,
- a directive that the User-Controlled AI Agent must not request or handle secret material.

## Human Acceptance Strategy

Interactive `private-state-cli install` should:

1. Print the current Terms in readable sections.
2. Display the current terms version and deterministic terms hash.
3. Ask the user to confirm acceptance with an explicit phrase.
4. Record the accepted version, hash, timestamp, CLI package version, and acceptance source in the user's Service state.
5. Proceed with installation only after acceptance is recorded.

The human flow should not require the user to understand technical implementation details before accepting. Definitions
must be available at the top of the Terms, and the CLI should use plain labels such as "Ethereum mainnet", "Channel",
"Private Note", "wallet secret", and "Official Public Observer" consistently.

## Implementation Plan

### Phase 1: Canonical terms source

- Add a canonical terms file for the Service.
- Assign a `termsVersion`.
- Compute a deterministic `termsHash` from the exact rendered terms content.
- Ensure the install command and JSON mode use the same canonical terms metadata.

### Phase 2: Interactive install gate

- Change `private-state-cli install` from non-interactive to interactive.
- Render the canonical Terms before installation.
- Require explicit human acceptance before installation proceeds.
- Persist the accepted `termsVersion`, `termsHash`, timestamp, CLI package version, and acceptance source in Service
  state.

### Phase 3: Renewed acceptance mechanism

- Add a terms-gate helper that compares the accepted record against the canonical `termsVersion` and `termsHash`.
- Require renewed interactive acceptance when the accepted record is missing, mismatched, or unreadable.
- Apply this helper before installation and before any terms-gated command that can affect user funds, user secrets,
  Channel membership, Channel accounting, or public observer state.
- Do not allow JSON mode or User-Controlled AI Agent mode to write an acceptance record.

### Phase 4: Remove per-command action-impact acknowledgement

- Remove `--acknowledge-action-impact` from individual commands only after the install-time terms gate is enforced.
- Replace command-specific blocking acknowledgements with concise contextual warnings only where they improve user
  understanding.
- Keep command-specific prompts only for unusually destructive or irreversible operations if they are still necessary
  after legal review.

### Phase 5: JSON and User-Controlled AI Agent updates

- Update `install --json` to report that human interactive acceptance is required.
- Update `help guide --json` so User-Controlled AI Agent guidance references canonical terms sections and `AGENTS.md`
  sections instead of duplicating long warnings.
- Ensure User-Controlled AI Agent directives require explanation of public/private boundaries, prohibited uses,
  self-custody, no recovery method, Third-Party Service risk, no professional advice, no warranties, liability limits,
  and Official Public Observer limits.

### Phase 6: Human help and documentation

- Update human `help guide` text to remain plain-language and user-facing.
- Update the CLI README to state that `--json` exists for User-Controlled AI Agents that help users complete minimum safe
  next actions without handling secrets or accepting Terms for users.
- Ensure documentation uses "Ethereum mainnet" for the public chain boundary.

### Phase 7: Verification

- Verify that interactive install blocks installation until Terms are accepted.
- Verify that `install --json` does not install or accept Terms.
- Verify that a changed terms hash requires renewed interactive acceptance.
- Verify that terms-gated commands reject execution when acceptance is missing or stale.
- Verify that per-command `--acknowledge-action-impact` options are no longer required after the terms gate is active.
- Verify that `help guide --json` points to canonical section numbers and does not duplicate full legal text.
- Verify that human `help guide` remains readable for ordinary users.

## Open Legal Decisions

- Final Provider Party legal names.
- Governing law, venue, arbitration, class-action waiver, language, limitation period, and consumer-law carveouts.
- Liability cap and jurisdiction-specific non-waivable rights.
- Required sanctions and restricted-jurisdiction wording for production use.
- Required privacy-policy references if the public observer or any hosted interface processes personal data.
- Required notice method for future terms changes.
- Whether any operation still needs a separate command-level prompt after install-time acceptance is enforced.

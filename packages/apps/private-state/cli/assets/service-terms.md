# Tonnel Terms of Service

Last updated: June 12, 2026

## 1. Definitions

For purposes of these Terms:

- **Terms** means these terms governing access to and use of the Service.
- **Service** means the Private-State DApp, Tonnel, The Great First Channel, Bridge workflows, the CLI, official
  documentation, official examples, official software, official interfaces, and related materials made available by the
  Provider. Channel-scoped observer services and workspace mirror services are part of the Service only for the Channel
  to which they are registered or otherwise made available by the applicable Channel Provider.
- **CLI** means command-line software that a user may install and execute to access or operate parts of the Service.
- **Private-State DApp** means the application that allows users to use Tonnel private application state through
  supported Channels.
- **Tonnel** means the branded user-facing name for Tokamak Private App Channels.
- **Tokamak Private App Channels** means the application-channel system exposed to users through Tonnel.
- **Channel** means a specific opt-in Tonnel application environment with its own policy, membership rules, accounting
  records, and Private Note records. A Channel is not an exchange deposit or withdrawal network.
- **The Great First Channel** means the dedicated initial Channel identified as `the-great-first-channel`.
- **Join Toll** means the one-time Channel entry fee paid when a user joins a Channel.
- **Ethereum mainnet** means the public Ethereum network where relevant Bridge, Channel-management, registration, and
  transaction records can be observed.
- **TON** means the token used with the relevant Bridge and Channel workflows. These Terms do not state that TON itself
  becomes private, anonymous, or untraceable.
- **Ethereum Account** means the user's externally controlled Ethereum wallet account used to sign transactions and pay
  Ethereum mainnet gas.
- **Self-Custody** means that the user, not the Provider, any Provider Party, any Channel Provider, or any Channel
  Operator, controls wallet access, keys, secret material, and transaction decisions.
- **Private Note** means a Channel-local private application record that may be transferred, redeemed, or used inside
  Tonnel. A Private Note is not a separate asset that an exchange can receive as a deposit.
- **Bridge** means the Ethereum mainnet smart-contract path through which public deposits, withdrawals, and related
  accounting updates are recorded.
- **Channel Provider** means the person or entity that provides or operates Channel-specific services for a Channel,
  including Channel-scoped observer services or workspace mirror services for that Channel.
- **Official Public Observer** means a Channel-scoped public observer service made available by a Channel Provider for a
  specific Channel. An Official Public Observer is not a Tonnel-wide default observer for every Channel.
- **Official Workspace Mirror** means a Channel-scoped workspace mirror made available by a Channel Provider for a
  specific Channel. An Official Workspace Mirror is not a Tonnel-wide default mirror for every Channel.
- **Provider** means Jehyuk Jang, the individual who officially makes the Service available. The Provider's public
  privacy and notice contact is `cjhyuck213@gmail.com`. The Provider's stated jurisdiction is Singapore. The Provider's
  residential address is not published in the Privacy Notice or these Terms.
- **Provider Parties** means the Provider and the Provider's affiliates, contractors, agents, service providers, and
  authorized representatives, to the extent each acts within an authorized Service-related role. Provider Parties do not
  include Tokamak Network PTE. LTD. under these Terms.
- **Tokamak Network PTE. LTD.** means a separate software contributor and licensor. Tokamak Network PTE. LTD. is not the
  Provider, does not accept Provider obligations, and does not provide custody, recovery, legal, tax, compliance, wallet,
  RPC, or user-support services through these Terms.
- **Channel Operators** means persons or entities that create, configure, administer, publish policies for, publish
  recovery information for, or otherwise operate a Channel. A Channel Operator may also be a Channel Provider when that
  person or entity provides Channel-scoped services for the Channel.
- **Channel Operation Abandonment** means a Channel state initiated by the Channel leader that stops new Channel joins
  and new Channel deposits while leaving existing Private Note activity, Private Note redemption, Channel withdrawal, and
  Channel exit available subject to ordinary requirements.
- **Third-Party Services** means wallets, RPC providers, exchanges, explorers, analytics providers, browsers, package
  registries, operating systems, cloud services, and other services not controlled by the Provider Parties.
- **Privacy Notice** means the Provider's published privacy notice for the Service.

## 2. Service Scope And Product Boundary

These Terms govern access to and use of the Service.

Tonnel is the branded name for Tokamak Private App Channels. Tonnel is an opt-in private application-channel system used
from a Self-Custody Ethereum Account. The Great First Channel is a Channel within Tonnel.

Observer services and workspace mirror services are Channel-scoped. A URL shown for one Channel is specific to that
Channel and is not a Tonnel-wide default for every Channel.

For The Great First Channel, Jehyuk Jang is both the Provider and the Channel Provider. That does not make The Great
First Channel's observer or workspace mirror a default observer or mirror for other Channels.

Tonnel does not alter TON transfer rules on Ethereum mainnet. Through the Service, Provider Parties do not provide
exchange deposit services, exchange withdrawal services, brokerage, custodial wallet services, hosted transfer services,
asset recovery services, compliance services, or tax services.

The Service is made available as open software and public-good infrastructure. Provider Parties do not operate the
Service as a fee-generating custodial, brokerage, exchange, hosted transfer, or paid asset-management service.

Join Tolls paid through the Service must not be monetized by Provider Parties. When a user exits a Channel, the
refundable portion is returned to the exiting user and the non-refundable portion is transferred to
`0x000000000000000000000000000000000000dEaD`. These Terms describe that non-refundable portion as a burn-address
transfer, not as a TON total-supply reduction.

The Bridge default Join Toll refund policy may be updated through the applicable on-chain governance or administration
path. Each Channel fixes its own Join Toll refund policy when that Channel is created, and later Bridge default policy
updates do not automatically rewrite an existing Channel's fixed policy. Users should verify Bridge and Channel policy
values through official on-chain contract records. Official observer pages, CLI output, and other official interfaces
may provide convenience views of those on-chain values, but the on-chain values control.

A Channel leader may initiate Channel Operation Abandonment. Once initiated, the affected Channel immediately rejects new
joins and new Channel deposits. Existing Private Note activity, Private Note redemption, Channel withdrawal, and Channel
exit remain available subject to ordinary proof, balance, registration, and transaction requirements.

Nothing in these Terms is a determination of the regulatory status of any person, entity, software, transaction, network,
token, or service under applicable law.

Private Notes are Channel-local application records. They are not separate exchange-depositable assets.

Exchange-facing TON transfers, Ethereum mainnet Bridge deposits, and Ethereum mainnet Bridge withdrawals remain public or
observable through Ethereum mainnet records.

## 3. Acceptance And Eligibility

These Terms become effective for a user when the user accepts them through an official Service interface or another
acceptance method provided by the Provider.

If the user does not accept these Terms, the user must not access, install, or use the Service.

The user represents that the user has legal capacity to accept these Terms and to operate a self-custody wallet. If the
user acts for an organization, the user represents that the user has authority to bind that organization.

The user represents that use of the Service is not prohibited by laws applicable to the user. The user represents that
use would not violate applicable sanctions, export control, anti-money laundering, counter-terrorist financing,
securities, commodities, tax, data-protection, or other applicable laws.

The Service is based on public blockchain infrastructure. Provider Parties may not have a technical method to identify,
screen, or block every natural person or legal entity that attempts to use the Service. Account-level restrictions may
block Ethereum Accounts or contract interactions, not necessarily the real-world person or entity behind an address.

## 4. Public Ethereum Mainnet Records

Ethereum mainnet transactions are public by design.

Bridge deposits and withdrawals recorded on Ethereum mainnet include or reveal Ethereum Accounts, contract addresses,
token amounts, transaction hashes, block numbers, timing, and related event data.

Public Channel records can include Channel creation, Channel joining, identity registration, note-receive public key
registration, Channel accounting updates, and other technical records needed to verify Channel state.

Gas-paying accounts and transaction submitters are visible on Ethereum mainnet when they submit public transactions.

The Service must not be used or described as a way to hide exchange-facing TON transfer records.

## 5. Private Application-State Limits

Tonnel is designed so public contract state does not, by itself, reconstruct some internal Private Note sender-recipient
relationships, Private Note plaintext, or Private Note provenance by default.

Tonnel does not make all user activity secret.

Public events, metadata, timing, amounts, user behavior, Third-Party Services, wallet software, RPC providers, browser
behavior, user disclosure, or compromised devices may reveal information.

No privacy, anonymity, unlinkability, confidentiality, exchange acceptance, compliance result, legal result, tax result,
regulatory outcome, or third-party acceptance of the user's explanation of asset history is guaranteed.

## 6. Self-Custody, Secrets, And No Recovery Method

The Service is designed for Self-Custody use.

Provider Parties, Channel Providers, and Channel Operators do not possess, control, store, or recover the user's Ethereum
private keys, seed phrases, wallet secrets, spending keys, viewing keys, source files, backup files, or Private Note
plaintext.

The user is solely responsible for securing the user's devices, wallet software, operating system, files, backups,
passwords, private keys, seed phrases, wallet secrets, spending keys, viewing keys, and equivalent secret material.

If all required copies of a private key, seed phrase, wallet secret, spending key, viewing key, source file, backup file,
or other required recovery material are lost, no recovery method exists for the affected access, Private Notes, funds,
evidence, or disclosure capability.

Provider Parties, Channel Providers, Channel Operators, support channels, websites, automated tools, and third parties do
not need the user's private keys, seed phrases, wallet secrets, spending keys, viewing keys, or equivalent secrets to
provide ordinary Service access, support, explanations, or guidance.

The user must not share private keys, seed phrases, wallet secrets, spending keys, viewing keys, or equivalent secrets
with any automated tool, Provider Party, Channel Operator, support channel, website, or third party.

## 7. Prohibited Use

The user must not use the Service for money laundering, terrorist financing, sanctions evasion, regulatory evasion,
illegal gambling, fraud, theft, ransomware, market manipulation, tax evasion, criminal-proceeds concealment,
exchange-monitoring evasion, unauthorized access, cybersecurity abuse, harassment, threats, abuse of any person,
infringement of intellectual-property, publicity, privacy, or data-protection rights, or any activity prohibited by
applicable law.

The user must not attempt to use Tonnel to make an unlawful transaction appear lawful or to conceal the source,
ownership, control, or destination of assets.

## 8. User Responsibilities

The user is solely responsible for determining whether the user's use of the Service is lawful.

The user is solely responsible for wallet selection, network selection, RPC selection, Channel selection, transaction
parameters, amounts, recipients, note selection, fees, failed transactions, wrong-network use, wrong-address use, and
irreversible confirmed transactions.

The user is solely responsible for preserving source files, wallet-secret files, backup files, evidence files,
transaction records, and disclosure material that the user may later need.

The user is solely responsible for preserving local evidence needed for selective disclosure, exchange review, tax
records, accounting records, disputes, audits, investigations, or any other explanation of asset history or Private Note
ownership.

The user must review applicable Channel policy before joining a Channel.

The user must use only trustworthy software, package sources, websites, wallets, RPC providers, and devices.

## 9. Channel Policy And Channel Operator Limitations

Joining a Channel means accepting that Channel's policy snapshot.

Channel policy may include Join Tolls, refund rules, administrative roles, operator roles, backup or recovery
information expectations, monitoring practices, fee rules, or other operating rules.

Channel Providers and Channel Operators may publish public metadata, policy information, event records, or recovery
information.

Channel Providers and Channel Operators do not control the user's Ethereum Account or user secrets.

Channel Providers and Channel Operators do not guarantee recovery of lost user secrets, lost Private Notes, lost
evidence, failed transactions, Third-Party Service failures, or rejected exchange deposits.

## 10. Channel-Scoped Observers, Monitoring, And Evidence

Channel Providers may provide Channel-scoped Official Public Observers. When a Channel's observer URL is registered or
otherwise made available for a Channel, users can verify that URL through official Channel records or official interfaces
that read those records.

For The Great First Channel, the current registered observer URL is `https://observer.tonnel.io`. That URL is the
observer for The Great First Channel and is not a Tonnel-wide observer URL for all Channels.

An Official Public Observer may display public Ethereum mainnet records, public Channel records, accepted Channel
activity, accounting updates, and related monitoring data for the Channel it observes.

An Official Public Observer is not intended to receive or display user secrets. It displays only records available to it
and does not guarantee that every fact needed for legal, accounting, tax, exchange, asset-history, or compliance review
is available.

Exchanges, analytics providers, regulators, Channel Providers, Channel Operators, users, and other observers may
independently monitor Ethereum mainnet and public Channel records.

The user may need to preserve local evidence to explain asset history, transaction history, Private Note ownership, or
facts the user chooses to prove.

Selective disclosure depends on Service features and on records preserved by the user.

## 11. Third-Party Services

The Service may require or interact with Third-Party Services.

Provider Parties do not control Third-Party Services and are not responsible for their security, availability,
correctness, fees, privacy practices, data retention, terms, sanctions screening, account restrictions, transaction
policies, or failures.

The user is responsible for reviewing and complying with Third-Party Service terms.

## 12. Privacy And Data

Public blockchain records are public and may be copied, indexed, analyzed, or retained by any person.

Channel-scoped observer services may display public blockchain records and public Channel records.

Provider Parties may operate websites, software repositories, package distribution channels, support channels, or other
official interfaces that process logs, device information, network information, usage data, contact information, or other
data. Provider Parties may also operate Channel-scoped observer or workspace mirror services for a Channel when they act
as that Channel's Channel Provider.

Provider Parties process certain data through official interfaces as described in the Privacy Notice. The current Privacy
Notice is published at [Tonnel Privacy Notice](privacy-notice.md).

Third-Party Services may collect or process user data under their own terms and privacy policies.

## 13. No Professional Advice

Provider Parties do not provide legal, tax, accounting, financial, investment, trading, compliance, sanctions, or
regulatory advice through the Service.

Information provided through the Service is for operational and informational purposes only.

Automated tools selected, configured, or used by the user are not agents, representatives, service providers, or support
providers of Provider Parties unless an official Service document expressly says otherwise.

Provider Parties do not control and are not responsible for automated tools selected, configured, or used by the user.

The user is responsible for reviewing any recommendation, explanation, or action proposed by an automated tool.

The user should consult qualified professionals before making legal, tax, accounting, financial, compliance, sanctions,
or regulatory decisions.

## 14. Risk Disclosures

Public blockchain systems, smart contracts, bridges, privacy-preserving cryptographic software, wallets, and RPC
providers involve significant operational, technical, security, market, regulatory, and legal risks.

Transactions recorded on Ethereum mainnet may be irreversible.

Software bugs, user mistakes, compromised devices, malicious third parties, governance actions, protocol upgrades,
network congestion, RPC failure, Bridge failure, smart-contract failure, cryptographic implementation defects, or
changes in law may cause loss, delay, rejected transactions, unavailable services, or loss of access.

Cryptographic proof systems and related tools can contain defects, incompatibilities, or operational failures.

Public observer services and indexing systems can be delayed, incomplete, unavailable, misconfigured, inconsistent with a
user's local state, or insufficient for legal, accounting, tax, exchange, audit, or compliance review.

Digital assets may be volatile and may lose value.

The user assumes all risks permitted by applicable law.

## 15. No Warranties

The Service is provided "as is" and "as available" to the maximum extent permitted by applicable law.

No Provider Party warrants that the software or services will be uninterrupted, secure, error-free, accurate, complete,
compatible, available in any jurisdiction, accepted by any exchange, or suitable for any particular purpose.

No Provider Party warrants any token value, transaction result, privacy result, legal result, regulatory result,
compliance result, tax result, accounting result, third-party acceptance of the user's asset-history explanation, or
selective-disclosure result.

## 16. Limitation Of Liability

The Service is non-custodial open software and public-good infrastructure, and is not operated for Provider Party
Service revenue. The user accesses and uses the Service at the user's own risk to the maximum extent permitted by
applicable law.

To the maximum extent permitted by applicable law, Provider Parties are not liable for indirect, incidental, special,
consequential, exemplary, punitive, or similar damages.

To the maximum extent permitted by applicable law, Provider Parties are not liable for lost profits, loss of data, lost
secrets, failed transactions, wrong transactions, loss of access, loss of assets, loss of evidence, business
interruption, Third-Party Service failures, exchange actions, regulatory actions, tax consequences, user error, device
compromise, or unauthorized access.

To the maximum extent permitted by applicable law, Provider Parties are not liable for the user's access to, use of,
inability to use, or reliance on the Service.

Join Tolls are not Provider Party revenue. Non-refunded Join Toll amounts transferred to a burn address do not create a
custodial, refund, credit, account-balance, or revenue-sharing relationship between the user and Provider Parties.

Nothing in these Terms excludes or limits liability that cannot be excluded or limited under applicable law, including
liability for fraud, willful misconduct, gross negligence, death, or personal injury where such exclusion or limitation is
not permitted.

## 17. User Indemnity

To the maximum extent permitted by applicable law, the user must indemnify, defend, and hold harmless the Provider
Parties from claims, damages, losses, liabilities, penalties, costs, and expenses arising from the user's breach of the
Terms, unlawful use, misuse, violation of third-party rights, interaction with Third-Party Services, or use of the
Service on behalf of another person or organization.

## 18. Changes To Terms And Renewed Acceptance

Provider Parties may update these Terms.

If the current Terms differ from the Terms previously accepted by the user, the user must accept the current Terms before
continuing to use terms-gated Service operations.

Renewed acceptance may be collected only after the current Terms are displayed to the user.

The Service may store acceptance metadata needed to verify whether the user accepted the current Terms.

If no current acceptance record exists, or if the stored acceptance record is stale, the Service may reject terms-gated
operations until the current Terms are displayed and the user submits the required acceptance.

The user must not rely on automated output or an automated tool to accept changed Terms on the user's behalf.

## 19. Suspension, Discontinuation, And Software Changes

Provider Parties may modify, suspend, discontinue, or stop supporting software, documentation, Channel-scoped observer
services or workspace mirror services they operate, examples, or related services.

Open-source smart contracts and public blockchain records may continue to exist independently of any supported
interface.

Provider Parties cannot reverse public Ethereum mainnet transactions or recover user secrets.

## 20. Governing Law, Venue, Dispute Resolution, And Notices

These Terms are governed by the laws of Singapore, excluding conflict-of-law rules.

Subject to non-waivable rights under applicable law, disputes arising from or relating to these Terms or the Service will
be resolved in the courts located in Singapore.

These Terms do not require arbitration and do not include a class-action waiver, collective-action waiver,
representative-action waiver, or jury-trial waiver.

Provider Parties may provide notices through official Service interfaces, official websites, official repositories,
release notes, email, or other contact methods stated in these Terms.

These Terms do not limit any non-waivable consumer rights or mandatory local-law rights that apply in the user's
jurisdiction.

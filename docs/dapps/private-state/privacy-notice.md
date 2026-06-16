# Tonigma Privacy Notice

Last updated: June 16, 2026

## 1. Overview

This Privacy Notice explains how personal data and related technical data may be processed when a user accesses or uses
the private-state DApp, Tonigma, The Great First Channel, the private-state CLI, Channel-scoped observer services,
Channel-scoped workspace mirror services, official documentation, official support channels, and related official
artifact distribution surfaces.

This Privacy Notice should be read together with the [Tonigma Terms of Service](terms.md).

This Privacy Notice applies to the Service. The Service web surfaces include `tonigma.network` and `www.tonigma.network`. The Service
scope does not include `airdrop.tonigma.network`.

The Service uses public blockchain infrastructure. Public blockchain records are public by design and may be copied,
indexed, stored, analyzed, or redistributed by anyone.

## 2. Provider And Contact

The Provider is Jehyuk Jang, an individual. The Provider's stated jurisdiction is Singapore.

For privacy requests, notices, or questions about Provider-controlled processing, contact:

- `cjhyuck213@gmail.com`

The Provider's residential address is not published.

## 3. Important Terms

For this Privacy Notice:

- **Service** means the private-state DApp, Tonigma, The Great First Channel, Bridge workflows, the CLI, official
  Tonigma-level documentation, official support channels, official deployment artifacts, official proof-runtime artifacts,
  and related software or interfaces officially made available for the private-state DApp. Channel-scoped observer
  services and workspace mirror services are part of the Service only for the Channel to which they are registered or
  otherwise made available by the applicable Channel Provider.
- **Provider** means Jehyuk Jang, the individual who officially makes the Service available.
- **Channel Provider** means the person or entity that provides or operates Channel-specific services for a Channel,
  including Channel-scoped observer services or workspace mirror services when those services are registered on-chain or
  otherwise made available for that Channel.
- **Tonigma** means the branded user-facing name for Tokamak Private App Channels.
- **The Great First Channel** means the dedicated initial Tonigma Channel identified as `the-great-first-channel`.
- **Official Public Observer** means a public observer service registered in a Channel's on-chain metadata or otherwise
  made available by that Channel's Channel Provider for that Channel.
- **Official Workspace Mirror** means a workspace mirror URL registered in a Channel's on-chain metadata or otherwise
  made available by that Channel's Channel Provider for that Channel.
- **CLI** means the command-line software used to access or operate parts of the Service.
- **Ethereum mainnet** means the public Ethereum network where relevant Bridge, Channel-management, registration, and
  transaction records can be observed.
- **Third-Party Services** means services not controlled by the Provider, including wallets, RPC providers, GitHub,
  Telegram, npm, Google Drive, Vercel, Neon, AWS, CoinGecko, browsers, operating systems, exchanges, and blockchain
  explorers. Tokamak Network PTE. LTD. is not the Provider for this Privacy Notice. Tokamak Network PTE. LTD.-controlled
  repositories, package registries, published artifacts, token infrastructure, bridge infrastructure, and upstream
  tooling not operated by the Provider are Third-Party Services for this Privacy Notice.

## 4. Data Processed Through Public Blockchain Records

Ethereum mainnet transactions and public Channel records can include Ethereum Accounts, contract addresses, token
amounts, transaction hashes, block numbers, timestamps, gas-paying accounts, Bridge deposit and withdrawal records,
Channel joins, identity registrations, note-receive public key registrations, note commitments, nullifiers, encrypted
note-delivery events, accepted transitions, and root updates.

These records are public blockchain records. The Provider cannot delete, alter, hide, reverse, or make private public
Ethereum mainnet records or public Channel records.

## 5. Channel-Scoped Observer Services

Observer services are Channel-scoped. A Channel's observer URL is read from that Channel's on-chain metadata when
registered. A URL shown in documentation for a specific Channel is a Channel-specific example and is not a Tonigma-wide
default for every Channel.

The current registered observer URL for The Great First Channel is `https://observer.tonigma.network`. It is a Vercel-hosted
Next.js deployment operated by Jehyuk Jang as The Great First Channel Provider. It serves public observer pages and APIs,
monitors public Channel state, and provides public monitoring for The Great First Channel.

Use of a Channel-scoped Official Public Observer may involve the following data:

- Hosting request metadata, including request paths, timestamps, status information, host information, user agent,
  search parameters, region, cache status, and function metadata.
- Vercel Web Analytics data for observer pages.
- Public blockchain records and public Channel records.
- Observer database records needed to display and verify public Channel state, including public contract addresses,
  transaction identifiers, block data, decoded event data, observer sync state, runtime RPC configuration, and indexer
  run state.

Observer service providers and database providers control their own platform logs, analytics, retention settings, and
security practices. Provider-controlled observer database rows currently have no repository-managed automatic deletion
policy.

## 6. Channel-Scoped Workspace Mirror Services

Workspace mirror services are Channel-scoped. A Channel's workspace mirror URL is read from that Channel's on-chain
metadata when registered. A URL shown in documentation for a specific Channel is a Channel-specific example and is not a
Tonigma-wide default for every Channel.

The Great First Channel has an official workspace mirror operated by Jehyuk Jang as The Great First Channel Provider.
The workspace mirror publishes verified mirror checkpoints and related recovery data used by CLI recovery flows.

Use of a Channel-scoped Official Workspace Mirror may involve the following data:

- Mirror manifest, checkpoint, and delta request metadata.
- Public mirror paths and object-storage URLs.
- Mirror database records, checkpoint block numbers, recovery root vector hashes, checkpoint hashes and sizes, leader
  metadata, and publish timestamps.
- Worker operational logs, raw RPC history paths, and mirror publish status messages when configured.

The Great First Channel mirror uses Vercel, Vercel Blob, Neon, AWS EC2, and Telegram where configured. Neon mirror data
and Vercel Blob objects are stored in region `iad1` according to the current deployment settings. The EC2 worker runs in
AWS region `ap-southeast-1`.

The current repository-managed mirror cleanup command for The Great First Channel is dry-run only. Mirror database rows,
mirror artifacts, and raw RPC history currently have no repository-managed automatic deletion policy.

## 7. Official Documentation And Web Surfaces

Official repository documentation is published through GitHub. GitHub may process page requests, GitHub account data if
the user is signed in, repository paths viewed, comments, issues, pull requests, and other GitHub-controlled metadata.

The Service web surfaces `tonigma.network` and `www.tonigma.network` are Vercel-hosted Tonigma web surfaces. Use of those surfaces may
involve Vercel request metadata and Vercel Web Analytics data. Vercel controls its own platform logs, analytics,
retention settings, and security practices.

The Service scope does not include `airdrop.tonigma.network`.

## 8. Artifact Distribution Through Google Drive

The Service distributes public deployment artifacts, DApp registration artifacts, ABI snapshots, CRS snapshots, source
snapshots, public Groth16 MPC CRS archives, and proof-runtime artifacts through Google Drive.

Use of these artifact distribution surfaces may involve public Drive file IDs, public folder listing requests, artifact
index requests, artifact file download requests, Drive confirmation cookies or tokens when presented by Google, request
metadata processed by Google, archive names, archive hashes, CRS compatibility versions, artifact sizes, and artifact
provenance metadata.

Google Drive is a Third-Party Service and controls Google account data, Drive request metadata, Drive cookies or
confirmation tokens, download processing, and Google-controlled retention. Individual public download-log access is not
confirmed for the Provider's personal file-owner model. Google Workspace administrator audit logs can include download
events only in supported Workspace administrator contexts.

## 9. CLI Package Distribution Through npm

The private-state CLI is distributed through the public npm registry as
`@tokamak-private-dapps/private-state-cli`.

npm may process package install requests, package update requests, package metadata requests, npm account data, IP
addresses, timestamps, user agents, and registry metadata according to npm's own terms and privacy practices.

The Provider can access public package metadata, maintainer metadata, package version metadata, and aggregate public
download counts exposed through public npm APIs. Individual npm downloader logs are not exposed by the confirmed public
npm APIs reviewed for this notice.

## 10. Support Channels

Official support channels currently include GitHub issues and the Telegram channel `t.me/tonigma_network`.

If a user submits support requests, issue reports, screenshots, logs, wallet addresses, transaction hashes, diagnostic
files, Telegram messages, GitHub comments, or other information through support channels, that information may be
processed for support, debugging, incident investigation, Service-status communication, abuse prevention, and security
review.

Support messages may be public if the user posts them in a public GitHub issue or public Telegram channel. GitHub and
Telegram are Third-Party Services and control their own account data, message data, metadata, retention, and deletion
processes.

Users must not send private keys, seed phrases, wallet secrets, spending keys, viewing keys, source files containing
secrets, or plaintext Private Note data through support channels.

## 11. CLI Network Requests And Telemetry

Based on the currently audited CLI paths, the CLI does not include first-party telemetry that sends private-state usage
data to the Provider by default.

The CLI does contact Third-Party Services when needed for package update checks, public deployment artifact downloads,
public CRS and proof-runtime artifact downloads, user-selected RPC requests, and CoinGecko ETH/USD fee lookups.

## 12. User-Selected RPC Providers

The Provider does not operate or proxy end-user RPC endpoints. End-user CLI RPC configuration is selected by the user.

User-selected RPC providers may process RPC URLs, public blockchain queries, `eth_getLogs` filters, block ranges,
contract addresses, transaction submissions, wallet or transaction submitter addresses visible in public transactions,
timestamps, IP addresses, user agents, and other client metadata according to the selected RPC provider's own terms and
privacy practices.

The Provider can explain how the CLI uses an RPC endpoint, but the Provider does not control the selected RPC provider's
logs, retention, access controls, or deletion process.

## 13. CoinGecko ETH/USD Price Lookup

The CLI may request ETH/USD price data from CoinGecko for fee-estimation and fee-display flows. CoinGecko may process
HTTP request metadata, including IP address, timestamp, user agent, and other client metadata, according to CoinGecko's
own terms and privacy practices.

The Provider does not control CoinGecko retention or CoinGecko-controlled data rights.

## 14. Local CLI Workspace On The User's Device

The CLI stores local private-state data on the user's device under user-controlled paths such as
`~/tokamak-private-channels/`.

Local CLI workspace data may include local private keys or source files created by the user, wallet secret source files,
local account aliases, wallet metadata, Private Note data, proofs, backups, recovery indexes, raw RPC history, and local
evidence exports.

This local workspace data is not sent to the Provider by default. The Provider receives it only if the user sends it
through support, issue reports, evidence export, or another communication route.

The user controls local deletion. The Provider cannot recover lost local secrets and cannot delete files on the user's
device.

## 15. Purposes Of Processing

Data described in this Privacy Notice may be processed for the following purposes:

- Operating, maintaining, and securing the Service.
- Serving official documentation, official web pages, Channel-scoped observer pages, Channel-scoped observer APIs, and
  mirror recovery artifacts.
- Publishing and verifying public deployment artifacts and proof-runtime artifacts.
- Distributing the CLI through npm and allowing package update checks.
- Reading public blockchain state and submitting user-authorized transactions through user-selected RPC providers.
- Showing fee estimates.
- Providing support and responding to user requests.
- Debugging errors, availability issues, mirror publication issues, observer sync issues, and security incidents.
- Preserving public mirror integrity and Channel recovery integrity.
- Complying with applicable legal, security, or abuse-prevention obligations.

## 16. Third-Party Services

The Service depends on Third-Party Services. These Third-Party Services may process data independently under their own
terms and privacy notices. Current Third-Party Services include GitHub, Telegram, npm, Google Drive, Vercel, Vercel Blob,
Neon, AWS, CoinGecko, user-selected RPC providers, wallets, browsers, operating systems, blockchain explorers, public
blockchain infrastructure, and Tokamak Network PTE. LTD.-controlled repositories, package registries, published
artifacts, token infrastructure, bridge infrastructure, or upstream tooling that is not operated by the Provider.

The Provider does not control Third-Party Service retention, deletion, access, account, security, cookie, analytics, or
logging practices.

## 17. Retention

Retention depends on the data surface:

- Provider-controlled operational logs and database rows are retained only as needed for operation, security, abuse
  prevention, debugging, evidence integrity, and legal purposes, subject to technical limits.
- Public Ethereum mainnet records and public Channel records are public blockchain records and cannot be deleted by the
  Provider.
- Provider-controlled observer database rows, mirror database rows, mirror artifacts, and raw RPC history currently have
  no repository-managed automatic deletion policy unless a specific Channel notice states otherwise.
- Hosting providers, database providers, object-storage providers, worker-hosting providers, and messaging providers
  retain their own platform logs and service records under their own terms, plan settings, and technical controls.
- Google Drive, GitHub, Telegram, npm, CoinGecko, user-selected RPC providers, wallets, browsers, operating systems, and
  other Third-Party Services control their own retention.
- Local CLI workspace files remain on the user's device until the user deletes them or runs a removal flow.

## 18. International Storage And Transfers

The Service and Third-Party Services may process or store data in multiple jurisdictions.

Official hosting, support, repository, package-distribution, artifact-distribution, analytics, and infrastructure
providers may process data outside the user's country. Third-Party Services apply their own terms, privacy notices,
security practices, and any transfer safeguards described by those services.

Current deployment information includes:

- The Great First Channel observer and included Tonigma web surfaces are hosted on Vercel.
- The Great First Channel mirror Neon database and Vercel Blob store are in region `iad1`.
- The EC2 worker runs in AWS region `ap-southeast-1`.
- End-user RPC traffic is sent to the RPC provider selected by the user.

Third-Party Services may process data in additional regions according to their own infrastructure and policies.

## 19. User Requests, Access, Correction, Withdrawal, And Deletion Limits

Users can contact `cjhyuck213@gmail.com` for requests, notices, or complaints concerning Provider-controlled processing.
These requests may include access requests, correction requests, withdrawal of consent where applicable, deletion or
review requests, and complaints about Provider-controlled processing.

The Provider may need information sufficient to verify the request and identify the relevant Provider-controlled record.
The Provider will review requests within technical, legal, security, operational, and public-record limits.

Requests concerning Third-Party Service data must be directed to the relevant Third-Party Service. Requests concerning
GitHub account data, Telegram account or message data, Google account or Drive data, npm account data, CoinGecko request
data, RPC provider logs, wallet data, browser data, or operating-system data must be handled through those services or
software providers.

Public blockchain records cannot be deleted, corrected, hidden, or made private by the Provider. Provider-controlled logs
or database rows can be reviewed only within technical, legal, security, operational, and public-record limits after
request verification.

Users can delete local CLI workspace files from their own devices. The Provider cannot delete local files from a user's
device and cannot recover lost local secrets.

## 20. Security

The Provider uses technical and operational measures intended to operate the Service and reduce unauthorized access to
Provider-controlled systems. No system can be guaranteed secure.

Users are responsible for securing their own devices, wallets, private keys, seed phrases, wallet secrets, spending
keys, viewing keys, source files, backup files, passwords, and equivalent secret material.

Users must not disclose private keys, seed phrases, wallet secrets, spending keys, viewing keys, or equivalent secrets
to the Provider, support channels, User-Controlled AI Agents, websites, or third parties.

Users may report suspected compromise of Provider-controlled systems to `cjhyuck213@gmail.com`. The Provider will assess
reported incidents and notify affected persons or authorities when required by applicable law.

## 21. Changes To This Privacy Notice

The Provider may update this Privacy Notice when the Service scope, data practices, operational settings, Third-Party
Services, support routes, publication surfaces, or applicable requirements change.

If Service-scope domains, data categories, retention practices, Third-Party Services, or user-facing processing
boundaries change, this Privacy Notice will be updated to reflect the changed state.

## 22. Contact

Privacy contact:

- `cjhyuck213@gmail.com`

Official support channels:

- GitHub issues for the repository.
- Telegram channel: `t.me/tonigma_network`.

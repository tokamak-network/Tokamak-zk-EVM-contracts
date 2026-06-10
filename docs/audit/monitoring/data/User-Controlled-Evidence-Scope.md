# User-Controlled Evidence Scope

This file defines the limited evidence scope for exceptional exchange disputes, deposit or
withdrawal explanations, and compliance questions involving the current `private-state` DApp and
`the-great-first-channel`.

This is not general user-facing product documentation. It is a Monitoring Packet companion that
describes what a user may voluntarily submit when an exchange, compliance team, or
investigator asks the user to explain activity that passed through self-custody and the
private-state channel.

## Boundary

Tokamak, the bridge operator, and the channel leader cannot disclose a user's private note history
on the user's behalf. They do not hold the user's L1 private key, wallet secret source, viewing key,
spending key, note plaintext, or master viewing key.

The available evidence therefore splits into two categories:

- public chain and packet data that anyone can inspect
- user-held local wallet evidence that only the user can decide to disclose

Public data can show bridge-edge activity, channel registration, accepted transitions, commitments,
nullifiers, encrypted note-delivery events, verifier information, policy snapshots, and upgrade
events. Public data alone is not expected to reconstruct the sender-recipient relationship or full
note provenance inside the private-state DApp.

## Public Evidence A User May Reference

A user may reference public data without disclosing wallet secrets:

- L1 bridge deposit transaction hash, block number, sender address, bridge vault address, amount,
  and event log
- L1 bridge withdrawal or claim transaction hash, block number, recipient address, amount, and event
  log
- channel creation and channel policy snapshot for `the-great-first-channel`
- channel join and L1/L2 identity registration event for the user's address
- registered note-receive public key coordinates emitted during channel registration
- channel operation abandonment event and public operation status, when present in the deployed ABI and regenerated
  Monitoring Packet
- channel exit refund events, and burn-address transfer events when present in the deployed ABI and regenerated
  Monitoring Packet
- accepted transition events and root-vector movement related to the channel
- commitment observations, nullifier observations, and encrypted note-delivery events
- verifier, DApp metadata, source verification, ABI, bytecode hash, owner, proxy, and upgrade data
  published in this Monitoring Packet

These materials can support statements such as "this Ethereum account joined this channel", "this bridge deposit
occurred", "this withdrawal claim occurred", or "this transition was accepted by the public channel contracts." They do
not, by themselves, prove the full private note path.

## User-Held Evidence A User May Voluntarily Submit

A user may voluntarily generate wallet-derived facts that they can inspect locally. The CLI provides
`wallet get-notes --export-evidence <PATH>` as a local raw evidence bundle export after interactive confirmation. When
the selected wallet has retained exited epochs, those local epochs are included so the user can still inspect historical
notes after channel exit. This raw bundle is not the final exchange submission package. The local investigator opened by
`private-state-cli investigator`, or directly at `packages/apps/private-state/cli/investigator/index.html`, filters the
raw bundle into a narrower user-consent package for the specific request.

User-Controlled AI Agents must not confirm the raw evidence export for the user and must not receive the raw evidence
ZIP. Provider Parties cannot recover leaked plaintext evidence or undo third-party disclosure.

Examples of user-held facts include:

- wallet registration metadata shown by read-only wallet inspection
- the user's local channel address and its match against the on-chain channel registration
- locally tracked note commitment and nullifier values
- locally decrypted note amount and status for notes addressed to the user's registered
  note-receive public key
- local note source metadata, such as creation transaction hash, spend transaction hash, block
  number, log index when available, and accepted transition transaction calldata
- the user's explanation connecting their own L1 bridge entry or exit to their own local note view

The user controls whether to disclose these facts. Tokamak should not claim that it can generate
them for the user from public logs alone.

## Local Raw Evidence Bundle

The raw evidence bundle is a ZIP file. It contains:

- `manifest.json` with network, channel, wallet scope, warning, and excluded-secret declarations
- one note record per locally known note; epoch-aware bundles store records under
  `wallets/<wallet>/epochs/<epoch>/notes/<commitment>.json`
- indexes by commitment, nullifier, creation transaction, spend transaction, block range, and
  available counterparty metadata
- transaction calldata, receipts, and event logs for referenced note creation or note spend
  transactions when available from the configured RPC endpoint

Each note record includes the selected note plaintext fields `owner`, `value`, and `salt`, the
derived commitment and nullifier, encrypted note payload, creation metadata, spend metadata when the
note is spent, and relationship hints when the CLI has direct local metadata. This lets a separate
filter program produce narrower packages for:

- a specific note receipt
- a specific redeem or withdraw explanation linked to a note nullifier
- a specific block or time range
- a specific counterparty when direct local metadata exists
- a bridge deposit to note mint explanation when the user provides the bridge transaction context
- an exchange request package that contains only user-approved records

The raw evidence bundle does not include viewing keys, spending keys, wallet secret material, L1
private keys, protected `.key` files, or machine-local secret directories. The bundle should not be
submitted as-is unless full wallet-history disclosure is intended.

## Selective Disclosure Investigator

The repository provides a static HTML investigator under
`packages/apps/private-state/cli/investigator/`. It runs in the user's browser and does not require a
server. The user loads a local raw evidence ZIP, chooses the disclosure request type, inspects an
interactive note-linkage graph, and exports a new user-consent disclosure ZIP or a Markdown
ASCII-art linkage report.

The investigator supports purpose-first request presets and can filter by:

- specific note commitment or nullifier
- note creation transaction or note spend transaction
- creation or spend block range
- current note status
- relationship direction and available counterparty L2 address metadata
- user-provided bridge deposit or withdraw transaction context

The graph view renders matched notes as nodes and shows external creation edges, external spend
edges, and locally recoverable note-to-note linkage edges. Clicking a note shows that note's
commitment, nullifier, value, status, creation reference, spend reference, direction, and available
counterparty metadata. The ASCII-art report separates the compact graph from per-note detail
sections for text-based dispute records.

The output package contains only the selected note records, directly referenced transaction calldata,
receipts, event files, a scope manifest, and optional user statement. It does not include viewing
keys, spending keys, wallet secret material, L1 private keys, protected `.key` files, or unrelated
note records.

This investigator is the intended filtering step for producing:

- a specific note receipt package
- a specific redeem or withdraw explanation linked to note use
- a period-scoped note receipt package
- a counterparty-scoped package when direct local metadata exists
- a bridge-deposit-to-note-mint explanation with user-provided bridge transaction context
- an exchange request package with a user-selected disclosure scope

## Evidence Not Available In The Current Tooling

The current repository does not provide a new zero-knowledge disclosure circuit that proves
decryption or counterparty linkage without revealing selected note plaintext. The implemented path
is selected note plaintext disclosure backed by accepted on-chain proof transactions and public
events.

The following items should not be represented as available from public data alone or without the
user's local raw evidence bundle and investigator filtering step:

- an operator-generated report that reconstructs every private note provenance path from public data
- a keyless cryptographic decryption proof for "I decrypted this note"
- a universal counterparty graph reconstructed from public logs alone

## Materials A User Should Not Submit

The evidence scope does not require users to reveal authority-bearing secrets or unrelated wallet
history. A user should not submit:

- L1 private keys or seed phrases
- wallet secret source files
- viewing private keys
- spending private keys
- protected `.key` files
- full wallet backups unless specifically reviewed as appropriate for the dispute
- unrelated full wallet history
- machine-local secret directories under `~/tokamak-private-channels/secrets/`

Viewing-key disclosure and spending-key disclosure are different risks. A viewing key can reveal
readable note contents for the registered viewing scope. A spending key authorizes note use. Neither
key should be sent to an exchange or third party as routine evidence.

## Interpretation

This document describes the current evidence-scope documentation and the local raw evidence export.
It does not mean that all note provenance is publicly reconstructible, that Tokamak can disclose
private note history on behalf of users, or that the raw evidence ZIP is itself an exchange-ready
submission package.

The correct monitoring posture remains:

- exchange-facing TON transfers and L1 bridge edges are public and monitorable.
- Private-state note provenance is not reconstructed from public data alone.
- A user may voluntarily generate a local raw evidence bundle and then provide a selected subset in
  exceptional dispute or compliance contexts.
- User-held keys and full wallet history remain outside the normal evidence scope.

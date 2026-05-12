# User-Controlled Evidence Scope

This file defines the limited evidence scope for exceptional exchange disputes, deposit or
withdrawal explanations, and compliance questions involving the current `private-state` DApp and
`the-great-first-channel`.

This is not general user-facing product documentation. It is a CEX Monitoring Packet companion that
describes what a user may voluntarily submit when a centralized exchange, compliance team, or
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
- accepted transition events and root-vector movement related to the channel
- commitment observations, nullifier observations, and encrypted note-delivery events
- verifier, DApp metadata, source verification, ABI, bytecode hash, owner, proxy, and upgrade data
  published in this Monitoring Packet

These materials can support statements such as "this L1 address joined this channel", "this bridge
deposit occurred", "this withdrawal claim occurred", or "this transition was accepted by the public
channel contracts." They do not, by themselves, prove the full private note path.

## User-Held Evidence A User May Voluntarily Submit

A user may voluntarily submit wallet-derived facts that they can inspect locally. The current CLI
does not package these facts into a standardized selective-disclosure export, so the user should
treat any submission as an ad hoc explanation rather than a protocol-defined evidence package.

Examples of user-held facts include:

- wallet registration metadata shown by read-only wallet inspection
- the user's local L2 address and its match against the on-chain channel registration
- locally tracked note commitment and nullifier values
- locally decrypted note amount and status for notes addressed to the user's registered
  note-receive public key
- local note source metadata available in the wallet's read-only output, such as the source
  transaction hash when present
- the user's explanation connecting their own L1 bridge entry or exit to their own local note view

The user controls whether to disclose these facts. Tokamak should not claim that it can generate
them for the user from public logs alone.

## Evidence Not Available In The Current Tooling

The current repository does not provide a standardized selective-disclosure export command or a
cryptographic dispute package for exchanges.

The following items are not implemented and should not be represented as available evidence:

- a standard note receipt proof export
- a counterparty-specific disclosure package
- a bridge-deposit-to-note-mint linkage proof
- a redeem-to-withdraw provenance proof package
- an exchange-ready user-consent disclosure package
- an operator-generated report that reconstructs every private note provenance path from public data

If any of these capabilities are added later, they should be documented as a separate versioned
evidence format and reviewed independently before this checklist item is treated as stronger than
scope documentation.

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

This document satisfies only the evidence-scope documentation requirement. It does not mean that a
selective-disclosure export feature exists, that all note provenance is publicly reconstructible, or
that Tokamak can disclose private note history on behalf of users.

The correct monitoring posture remains:

- CEX-facing TON transfers and L1 bridge edges are public and monitorable.
- Private-state note provenance is not reconstructed from public data alone.
- A user may voluntarily provide selected local evidence in exceptional dispute or compliance
  contexts.
- User-held keys and full wallet history remain outside the normal evidence scope.

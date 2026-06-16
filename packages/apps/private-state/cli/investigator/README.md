# Private-State Evidence Investigator

This directory contains a static browser tool for filtering a local raw evidence bundle produced by:

```bash
private-state-cli wallet get-notes \
  --network <NETWORK> \
  --wallet <WALLET> \
  --export-evidence ./wallet-evidence.zip
```

Mainnet evidence export asks for interactive confirmation before writing plaintext note evidence;
Sepolia and anvil evidence export do not. User-Controlled AI Agents must not confirm the export or
receive the raw evidence ZIP. Open `index.html` in a modern browser, load the raw ZIP, choose the
disclosure request type, inspect the graph, and build a narrower user-consent disclosure ZIP. From
an installed CLI package, `private-state-cli investigator` prints the bundled HTML path and opens it
in the default browser.

The tool does not run a server and does not send files over the network. It reads the selected ZIP in
the browser. It can write a new ZIP with selected note records plus directly referenced transaction,
receipt, and event files, and it can export a Markdown plain-text linkage report.

The raw evidence bundle contains plaintext for all locally known notes and may include retained exited epochs for the
selected wallet. Do not submit the raw bundle as an exchange or auditor package unless full wallet-history disclosure is
intended. Use the investigator output package for scoped disclosure.

The investigator accepts current epoch-aware evidence bundles only. Supported note records live under
`wallets/<wallet>/epochs/<epoch-id>/notes/` inside the ZIP. If a bundle uses an older layout, rebuild the local wallet
workspace with `wallet recover-workspace` and export a new evidence ZIP with `wallet get-notes --export-evidence`.

## Supported Investigation Views

- purpose-first request presets for full graph view, specific note receipt, specific note use, transaction linkage,
  period receipts, and counterparty subsets
- an interactive SVG note-linkage graph where every matched note is a node
- graph edges for external note creation, external note spend, and locally recoverable note-to-note linkage
- node detail overlays showing commitment, nullifier, value, status, creation reference, spend reference, direction, and
  available counterparty metadata
- a Markdown plain-text report with a compact graph section and separate note detail sections

## Supported Filtering Inputs

- note commitment or nullifier
- creation transaction or spend transaction
- creation or spend block range
- current note status
- relationship direction
- available counterparty channel-local address metadata
- user-provided bridge deposit or withdraw transaction context

Counterparty filtering is only as complete as the relationship hints present in the raw evidence
bundle. The investigator does not create a keyless cryptographic decryption proof and does not
reconstruct private note provenance from public data alone.

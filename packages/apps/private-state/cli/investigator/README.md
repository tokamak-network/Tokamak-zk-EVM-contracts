# Private-State Evidence Investigator

This directory contains a static browser tool for filtering a local raw evidence bundle produced by:

```bash
private-state-cli wallet get-notes \
  --network <NETWORK> \
  --wallet <WALLET> \
  --export-evidence ./wallet-evidence.zip \
  --acknowledge-full-note-plaintext-export
```

Open `index.html` in a modern browser, load the raw ZIP, select a filter scope, and build a narrower
user-consent disclosure ZIP. From an installed CLI package, `private-state-cli investigator` prints the bundled
HTML path and opens it in the default browser.

The tool does not run a server and does not send files over the network. It reads the selected ZIP in
the browser and writes a new ZIP with selected note records plus directly referenced transaction,
receipt, and event files.

The raw evidence bundle contains plaintext for all locally known notes. Do not submit the raw bundle
as an exchange or auditor package unless full wallet-history disclosure is intended. Use the
investigator output package for scoped disclosure.

The investigator accepts current epoch-aware evidence bundles only. Supported note records live under
`wallets/<wallet>/epochs/<epoch-id>/notes/` inside the ZIP. If a bundle uses an older layout, rebuild the local wallet
workspace with `wallet recover-workspace` and export a new evidence ZIP with `wallet get-notes --export-evidence`.

## Supported Filtering

- note commitment or nullifier
- creation transaction or spend transaction
- creation or spend block range
- current note status
- relationship direction
- available counterparty L2 address metadata
- user-provided bridge deposit or withdraw transaction context

Counterparty filtering is only as complete as the relationship hints present in the raw evidence
bundle. The investigator does not create a keyless cryptographic decryption proof and does not
reconstruct private note provenance from public data alone.

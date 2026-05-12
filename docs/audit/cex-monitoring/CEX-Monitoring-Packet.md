# CEX Monitoring Packet

This document explains how the repository generates the data-backed CEX Monitoring Packet and where each generated output is written.

The packet generator is [scripts/cex-monitoring-packet/generate.mjs](../../../scripts/cex-monitoring-packet/generate.mjs). It is a read-only script that collects current evidence from the mainnet bridge deployment artifacts, Ethereum RPC, Etherscan, and the configured Google Drive artifact folder.

The external policy model for monitoring, public disclosure boundaries, user-controlled selective disclosure, and channel policy is described in [docs/whitepaper.md](../../whitepaper.md). The generator does not create separate policy memos; it creates data files that support the white paper's policy statements.

## How To Generate

```bash
node scripts/cex-monitoring-packet/generate.mjs
```

Useful options:

```bash
node scripts/cex-monitoring-packet/generate.mjs \
  --chain-id 1 \
  --dapp private-state \
  --channel the-great-first-channel \
  --rpc-url "$MAINNET_RPC_URL" \
  --drive-folder-id "$TOKAMAK_MPC_DRIVE_FOLDER_ID"
```

The default public output directory is:

```text
docs/audit/cex-monitoring/data/
```

The default internal validation output directory is:

```text
scripts/cex-monitoring-packet/output/
```

Passing `--output <dir>` changes only the internal validation output directory. The public packet data remains under `docs/audit/cex-monitoring/data/`.

## Method

The generator performs the following steps:

1. Locates the latest local bridge and private-state DApp deployment artifacts for the selected chain.
2. Reads mainnet state through RPC, including channel state, owner state, proxy implementation slots, verifier pointers, root-vector state, and bytecode hashes.
3. Reads Etherscan source verification status when an API key is available.
4. Reads Google Drive artifact metadata from the configured artifact publication folder.
5. Builds ABI-derived event monitoring coverage for the Monitoring Packet checklist.
6. Writes public packet data to `docs/audit/cex-monitoring/data/`.
7. Writes internal run receipts and raw validation data to `scripts/cex-monitoring-packet/output/`.

## Public Outputs

These files are intended to be included in the public Monitoring Packet.

| File | Path | Description |
| --- | --- | --- |
| `TPAC-Contract-Addresses.json` | [data/TPAC-Contract-Addresses.json](data/TPAC-Contract-Addresses.json) | Chain ID, canonical TON address, bridge and DApp contract addresses, proxy and implementation addresses, owner/admin information, verifier addresses, deployment anchors, source verification status, ABI references, bytecode hashes, and monitored event checklist coverage. |
| `the-great-first-channel-Policy-Snapshot.json` | [data/the-great-first-channel-Policy-Snapshot.json](data/the-great-first-channel-Policy-Snapshot.json) | Current channel policy snapshot for `the-great-first-channel`, including channel manager, vault, leader/operator, join toll, managed storage addresses, root-vector hash, workspace mirror URL, DApp metadata digest, function root, verifier snapshot, and storage-layout source. |
| `Private-State-Observability-Matrix.md` | [data/Private-State-Observability-Matrix.md](data/Private-State-Observability-Matrix.md) | Human-readable matrix mapping each Monitoring Packet event checklist item to the current public event surface, including event names, contract addresses, indexed fields, non-indexed fields, explorer query examples, what the event reveals, what it does not reveal, and exchange monitoring meaning. |
| `Admin-Wallets-and-Upgrade-Policy.md` | [data/Admin-Wallets-and-Upgrade-Policy.md](data/Admin-Wallets-and-Upgrade-Policy.md) | Current owner and proxy-slot state for the monitored mainnet bridge deployment, plus notes that connect the generated data to the white paper's upgrade and channel-immutability policy. |

## Internal Validation Outputs

These files are generated for operator validation and audit traceability. They are not the primary public packet.

| File | Path | Description |
| --- | --- | --- |
| `event-monitoring-map.json` | [../../../scripts/cex-monitoring-packet/output/event-monitoring-map.json](../../../scripts/cex-monitoring-packet/output/event-monitoring-map.json) | Machine-readable event coverage data used to render `Private-State-Observability-Matrix.md`. |
| `drive-artifacts.json` | [../../../scripts/cex-monitoring-packet/output/drive-artifacts.json](../../../scripts/cex-monitoring-packet/output/drive-artifacts.json) | Google Drive artifact folder IDs, file IDs, checksums, sizes, modified times, and web links read during generation. |
| `coverage-report.json` | [../../../scripts/cex-monitoring-packet/output/coverage-report.json](../../../scripts/cex-monitoring-packet/output/coverage-report.json) | Checklist coverage report showing which required address-pack and event-map items are covered, need review, or are not present in the current ABI. |
| `packet-summary.json` | [../../../scripts/cex-monitoring-packet/output/packet-summary.json](../../../scripts/cex-monitoring-packet/output/packet-summary.json) | Run receipt containing generation timestamp, selected chain/DApp/channel, artifact directories, latest RPC block, Drive status, source verification status, warnings, and generated file lists. |

## Notes

Plain Ethereum RPC cannot discover every contract creation block without an indexer. When the generator cannot derive a field from RPC or local artifacts, it records the limitation in the generated JSON instead of silently inventing a value.

Source verification is read through Etherscan. A `partial` source verification status means at least one monitored address was not verified or could not be checked successfully at generation time.

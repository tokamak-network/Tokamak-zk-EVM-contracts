# Bridge Gas Assessment

Measurement timestamp: 2026-05-02T03:25:21Z / 2026-05-02 11:25:21 +08.

ETH/USD: 2,303.96 USD.

All contract gas values below are measured values from the current worktree. They are not gas
estimates.

USD values use `gasUsed * effectiveGasPriceGwei * 1e-9 * ETH_USD`. The call cost tables use the
six-month historical `Typical effective gas price` baselines from the distribution section below:

- `Block p50`: 0.106 gwei.
- `Block p90`: 0.886 gwei.

The MetaMask Ethereum mainnet gas API returned the following wallet fee snapshot at the measurement
timestamp:

- Estimated base fee: 0.216144485 gwei.
- Low suggested max fee: 0.217144485 gwei with a 0.001 gwei priority fee.
- Medium suggested max fee: 2.309086614 gwei with a 2 gwei priority fee.
- High suggested max fee: 2.309086614 gwei with a 2 gwei priority fee.

The MetaMask values are a point-in-time wallet quote. The USD tables below use the historical
`Typical effective gas price` baselines instead of the MetaMask point quote so that the tables remain
comparable with the six-month distribution.

## Six-Month Historical Distribution

The chart below summarizes Ethereum mainnet block-level fee history from 2025-11-01 to 2026-05-01,
generated at 2026-05-01T02:48:26Z. It covers blocks 23,701,606 through 24,997,205, for 1,295,600
blocks total.

![Ethereum mainnet gas fee distribution](assets/ethereum-gas-fee-distribution-2025-11-01-to-2026-05-01.svg)

The historical data comes from Ethereum JSON-RPC `eth_feeHistory` with reward percentiles 10, 50,
and 90. Effective gas price is calculated as `block base fee + priority reward percentile`. This is
a block-level historical fee distribution, not a historical MetaMask recommendation backfill. The
chart's x-axis is focused on 0-3 gwei; that window contains 97.72% of the typical effective gas
price series and 89.82% of the fast effective gas price series in the measured range.

The table columns are percentiles across the measured six-month block set: `Block p50` is the median
block-level value, `Block p90` means 90% of measured blocks were at or below that value, and
`Block p99` means 99% of measured blocks were at or below that value. `Typical effective gas price`
uses the in-block p50 priority reward from `eth_feeHistory`; `Fast effective gas price` uses the
in-block p90 priority reward.

| Metric | Block p10 | Block p50 | Block p90 | Block p99 | Max |
|---|---:|---:|---:|---:|---:|
| Base fee | 0.032 gwei | 0.080 gwei | 0.510 gwei | 3.445 gwei | 97.679 gwei |
| Typical effective gas price | 0.035 gwei | 0.106 gwei | 0.886 gwei | 5.190 gwei | 13,492.028 gwei |
| Fast effective gas price | 0.237 gwei | 1.425 gwei | 3.030 gwei | 21.873 gwei | 13,492.028 gwei |

The raw RPC response chunks used to generate the chart are stored at
`assets/ethereum-gas-fee-history-2025-11-01-to-2026-05-01.eth-fee-history.raw.jsonl.gz`. Each JSONL
record stores the original `eth_feeHistory` request parameters and result payload; gas quantities
remain in the original hex-encoded wei format returned by the RPC endpoint.

## Owner And Operator Calls

| Function | Caller role | Measured gas used | Measurement source | USD at 0.106 gwei (Typical Block p50) | USD at 0.886 gwei (Typical Block p90) |
|---|---|---:|---|---:|---:|
| `DAppManager.bindBridgeCore` | Owner | 26,091 | Forge gas report | $0.006 | $0.053 |
| `DAppManager.registerDApp` | Owner | 5,338-1,043,732 | Forge gas report | $0.001-$0.255 | $0.011-$2.13 |
| `DAppManager.updateDAppMetadata` | Owner | 119,040-395,746 | Forge gas report | $0.029-$0.097 | $0.243-$0.808 |
| `DAppManager.deleteDApp` | Owner, Sepolia/local only | 13,902-149,012 | Forge gas report | $0.003-$0.036 | $0.028-$0.304 |
| `BridgeCore.bindBridgeTokenVault` | Owner | 5,119-9,164 | Forge gas report | $0.001-$0.002 | $0.010-$0.019 |
| `BridgeCore.setChannelDeployer` | Owner | 11,663 | Forge gas report | $0.003 | $0.024 |
| `BridgeCore.setGrothVerifier` | Owner | 9,045 | Forge gas report | $0.002 | $0.018 |
| `BridgeCore.setTokamakVerifier` | Owner | 8,957 | Forge gas report | $0.002 | $0.018 |
| `BridgeCore.setJoinFeeRefundSchedule` | Owner | 16,517 | Forge gas report | $0.004 | $0.034 |
| `BridgeCore.createChannel` | Owner | 3,884,651 | CLI E2E receipt | $0.949 | $7.93 |
| `ChannelManager.setJoinFee` | Channel leader | 22,119-28,418 | Forge gas report | $0.005-$0.007 | $0.045-$0.058 |

## User Calls

| Function | Caller role | Measured gas used | Measurement source | USD at 0.106 gwei (Typical Block p50) | USD at 0.886 gwei (Typical Block p90) |
|---|---|---:|---|---:|---:|
| `L1TokenVault.fund` | User | 72,845-89,945 | CLI E2E receipts | $0.018-$0.022 | $0.149-$0.184 |
| `L1TokenVault.joinChannel` | User | 323,722-326,534 | CLI E2E receipts | $0.079-$0.080 | $0.661-$0.667 |
| `L1TokenVault.depositToChannelVault` | User | 336,335-336,359 | CLI E2E receipts | $0.082-$0.082 | $0.687-$0.687 |
| `ChannelManager.executeChannelTransaction` | User | 830,814-865,674 | CLI E2E receipts | $0.203-$0.211 | $1.70-$1.77 |
| `L1TokenVault.withdrawFromChannelVault` | User | 380,295 | CLI E2E receipt | $0.093 | $0.776 |
| `L1TokenVault.exitChannel` | User | 130,148 | CLI E2E receipt | $0.032 | $0.266 |
| `L1TokenVault.claimToWallet` | User | 52,317 | CLI E2E receipt | $0.013 | $0.107 |

Supporting ERC-20 approvals are not bridge contract calls, but the CLI E2E measured `ERC20.approve`
at 45,957 gas, which is about $0.011 at 0.106 gwei and $0.094 at 0.886 gwei using the same ETH/USD
input.

## Measurement Sources

| Source | Scope |
|---|---|
| `packages/apps/private-state/scripts/e2e/output/private-state-bridge-cli/summary.json` | Actual local EOA transaction receipts for the private-state bridge CLI flow, generated after the BridgeAdminManager removal. |
| `forge test --root bridge --gas-report` | Current-worktree function gas measurements for owner/operator functions that do not have CLI E2E receipts. |
| MetaMask gas API, Ethereum mainnet network 1 | Timestamped low/medium/high fee inputs. |
| Ethereum JSON-RPC `eth_feeHistory` | Six-month block-level base fee and priority reward percentile distribution for the embedded chart; raw chunk responses are stored under `bridge/docs/assets`. |
| CoinGecko simple price API | Timestamped ETH/USD input. |

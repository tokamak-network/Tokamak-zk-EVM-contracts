# Bridge Gas Prices

Measurement timestamp: 2026-05-01T02:12:20Z / 2026-05-01 10:12:20 +08.

ETH/USD: 2,267.90 USD.

MetaMask Ethereum mainnet gas inputs at the measurement timestamp:

| MetaMask tier | Estimated base fee | Suggested priority fee | Effective gas price used below | Suggested max fee cap |
|---|---:|---:|---:|---:|
| Low | 0.232963096 gwei | 0.001198516 gwei | 0.234161612 gwei | 0.234161612 gwei |
| Medium | 0.232963096 gwei | 2 gwei | 2.232963096 gwei | 2.333137228 gwei |
| High | 0.232963096 gwei | 2 gwei | 2.232963096 gwei | 2.333137228 gwei |

USD values use `gasUsed * effectiveGasPriceGwei * 1e-9 * ETH_USD`. The suggested max fee cap is a ceiling, not the amount necessarily charged after EIP-1559 base-fee refunding.

## Owner And Operator Calls

| Function | Caller role | Measured gas used | Measurement source | USD at MetaMask Low | USD at MetaMask Medium/High |
|---|---|---:|---|---:|---:|
| `DAppManager.bindBridgeCore` | Owner | 26,069 | Forge gas report | $0.014 | $0.132 |
| `DAppManager.registerDApp` | Owner | 276,832-1,007,387 | Forge gas report | $0.147-$0.535 | $1.40-$5.10 |
| `DAppManager.updateDAppMetadata` | Owner | 194,667-390,176 | Forge gas report | $0.103-$0.207 | $0.986-$1.98 |
| `DAppManager.deleteDApp` | Owner, Sepolia/local only | 13,880-148,990 | Forge gas report | $0.007-$0.079 | $0.070-$0.755 |
| `BridgeCore.bindBridgeTokenVault` | Owner | 5,163-9,208 | Forge gas report | $0.003-$0.005 | $0.026-$0.047 |
| `BridgeCore.setGrothVerifier` | Owner | 9,089 | Forge gas report | $0.005 | $0.046 |
| `BridgeCore.setTokamakVerifier` | Owner | 9,001 | Forge gas report | $0.005 | $0.046 |
| `BridgeCore.setJoinFeeRefundSchedule` | Owner | 16,561 | Forge gas report | $0.009 | $0.084 |
| `BridgeCore.createChannel` | Owner | 3,796,845 | CLI E2E receipt | $2.02 | $19.23 |
| `BridgeAdminManager.setMerkleTreeLevels` | Owner | 2,554 | Forge gas report | $0.001 | $0.013 |
| `ChannelManager.setJoinFee` | Channel leader | 22,119-28,418 | Forge gas report | $0.012-$0.015 | $0.112-$0.144 |

## User Calls

| Function | Caller role | Measured gas used | Measurement source | USD at MetaMask Low | USD at MetaMask Medium/High |
|---|---|---:|---|---:|---:|
| `L1TokenVault.fund` | User | 72,845-89,945 | CLI E2E receipt | $0.039-$0.048 | $0.369-$0.455 |
| `L1TokenVault.joinChannel` | User | 323,678-326,490 | CLI E2E receipt | $0.172-$0.173 | $1.64-$1.65 |
| `L1TokenVault.depositToChannelVault` | User | 336,289-336,293 | CLI E2E receipt | $0.179 | $1.70 |
| `ChannelManager.executeChannelTransaction` | User | 830,792-865,664 | CLI E2E receipt | $0.441-$0.460 | $4.21-$4.38 |
| `L1TokenVault.withdrawFromChannelVault` | User | 380,285 | CLI E2E receipt | $0.202 | $1.93 |
| `L1TokenVault.exitChannel` | User | 130,113 | CLI E2E receipt | $0.069 | $0.659 |
| `L1TokenVault.claimToWallet` | User | 52,317 | CLI E2E receipt | $0.028 | $0.265 |

Supporting ERC-20 approvals are not bridge contract calls, but the CLI E2E measured `ERC20.approve` at 45,957 gas, which is about $0.024 at MetaMask Low and $0.233 at MetaMask Medium/High using the same timestamped inputs.

## Measurement Sources

| Source | Scope |
|---|---|
| `packages/apps/private-state/scripts/e2e/output/private-state-bridge-cli/summary.json` | Actual local EOA transaction receipts for the private-state bridge CLI flow. |
| `forge test --root bridge --gas-report` | Current-worktree function gas measurements for owner/operator functions that do not have CLI E2E receipts. |
| MetaMask gas API, Ethereum mainnet network 1 | Timestamped low/medium/high fee inputs. |
| CoinGecko simple price API | Timestamped ETH/USD input. |

# Bridge Changelog

This changelog records bridge-contract and bridge-deployment changes against Ethereum
mainnet deployments. It has two jobs:

- identify which repository changes exist after the latest mainnet deployment but are not
  yet included in a mainnet bridge implementation
- record which source commit, contract addresses, verifier versions, and policy changes were
  included in each mainnet deployment

The deployment artifact is the source of truth for deployed code. For mainnet, the current
artifact is `deployment/chain-id-1/bridge/20260511T065651Z/bridge.1.json`.

## Status Definitions

- **Mainnet deployed**: the change is included in a mainnet bridge deployment artifact and
  the artifact records the source commit.
- **Pending GitHub main**: the change exists on `origin/main` after the source commit of the
  latest mainnet deployment, but no mainnet bridge deployment artifact includes it yet.
- **Local pending**: the change exists in this working repository after the deployed source
  commit, but is not yet on `origin/main` at the time this changelog entry was written.
- **No bridge deployment required**: the change affects CLI, docs, tests, package metadata,
  or operational tooling only. It may still need a package release or artifact upload, but it
  does not require a bridge UUPS upgrade or fresh bridge deployment.

## Current Mainnet Deployment State

| Field | Value |
| --- | --- |
| Network | Ethereum mainnet |
| Chain ID | `1` |
| Deployment timestamp | `20260511T065651Z` |
| Deployment artifact | `deployment/chain-id-1/bridge/20260511T065651Z/bridge.1.json` |
| Deployed source commit | `b3910b39d49cd4d13bb167999dca48c917878b56` |
| `origin/main` at changelog update | `b3910b39d49cd4d13bb167999dca48c917878b56` |
| GitHub-main changes pending mainnet deployment | None at the time this entry was written |
| Merkle tree depth | `36` |
| Groth16 compatible backend version | `0.2` |
| Tokamak compatible backend version | `2.1` |

### Mainnet Addresses

| Component | Address |
| --- | --- |
| `BridgeCore` proxy | `0x992E2Ae206620d811832a8F697c526c4f95974b6` |
| `BridgeCore` implementation | `0x1713171adc06BF82b4f05945d742FFd351a8d1bD` |
| `DAppManager` proxy | `0x88Ab290a9dc0a169240EBC282Ec1F7C8524645aA` |
| `DAppManager` implementation | `0x76f0e95c0E5c9bA26289062637c68aEc1199ddc5` |
| `L1TokenVault` proxy | `0xf127Aef661c815ad46c5159146078f6F1E9f5F61` |
| `L1TokenVault` implementation | `0x4c6dDcf807309d49Ac9a1f6583B5A19ef6c6a710` |
| `ChannelDeployer` | `0xEB8eBE0E09bb897785a3bB9A60f93cef7b1AEf78` |
| `Groth16Verifier` | `0x21cfF039c1FC4FC621923Db18D8E4ca746C287D5` |
| `TokamakVerifier` | `0x0C467a5082323Cc6F4b7077A9dFb0bbdaf6eC626` |
| Owner at deployment | `0x850dD0721B93D455b55bdf1324595fA1BD2B3ce7` |
| Deployer | `0x850dD0721B93D455b55bdf1324595fA1BD2B3ce7` |

## Pending Changes Not Yet Included in Mainnet

### Pending GitHub Main

None. `origin/main` currently points to the same commit recorded in the latest mainnet
deployment artifact.

### Local Pending

#### Internal bridge hashing and upload-tooling refactors

Status: **Local pending**

Deployment requirement: **No bridge deployment required**

Summary:

- Centralizes DApp function metadata hashing in `DAppFunctionMetadataHasher` so registration-time
  leaves and execution-time function proof verification share the same domain constants and field
  order.
- Adds behavior-equivalence coverage for the function metadata leaf and Merkle root formulas.
- Wraps repeated `ChannelManager` access checks in private helper functions while preserving custom
  errors, public ABI, and storage layout.
- Centralizes bridge and DApp Drive upload orchestration in a shared upload helper while preserving
  script-local artifact collection, receipt payloads, index updates, and console summaries.
- Treats these changes as behavior-preserving maintenance; no mainnet bridge deployment is required
  unless operators separately choose to deploy a new source-synchronization release.

#### Safe-based bridge upgrade flow

Status: **Local pending**

Deployment requirement: **No bridge deployment required**

Summary:

- Replaces the previous EOA-executed `upgrade` flow in `bridge/scripts/deploy-bridge.mjs` with a Safe-based upgrade
  plan flow for bridge deployments whose current owner is a Safe multisig.
- Adds `bridge/scripts/PrepareSafeBridgeUpgrade.s.sol` to deploy new implementation and support
  contracts without calling owner-only proxy or bridge administration functions from the EOA
  deployer.
- Removes the previous direct EOA upgrade script.
- Writes Safe Transaction Builder JSON and a raw transaction review plan under
  `deployment/chain-id-<chain-id>/bridge-upgrade-plans/<timestamp>/`.
- Refuses to write the Safe batch unless the planned Safe owner owns `DAppManager`, `BridgeCore`,
  and `L1TokenVault`.
- Intentionally does not update the canonical deployed bridge artifact until the Safe batch has
  been executed and final deployment artifacts are regenerated from on-chain state.

#### Join Toll refund and burn-address transfer policy

Status: **Local pending**

Deployment requirement: **Bridge UUPS upgrade required**

Summary:

- Changes the default Join Toll refund schedule to a time-based policy. Exact Bridge
  default values are available through the `BridgeCore.defaultJoinTollRefundCutoff*`
  and `BridgeCore.defaultJoinTollRefundBps*` getters, while each Channel's fixed
  policy is available through that Channel's `ChannelManager.joinTollRefundCutoff*`
  and `ChannelManager.joinTollRefundBps*` getters.
- Inverts Join Toll refund schedule validation so configured refund percentages must stay
  flat or increase as participation time increases.
- Updates `L1TokenVault.exitChannel(...)` so future exits transfer the refundable portion
  to the exiting user and transfer the non-refundable portion to
  `0x000000000000000000000000000000000000dEaD`.
- Reduces `_tollTreasuryBalance` by both the refunded amount and the burn-address transfer
  amount.
- Treats the change as future-only and does not add retroactive handling for users who
  already exited before this implementation ships.

#### Channel Operation Abandonment policy

Status: **Local pending**

Deployment requirement: **Bridge UUPS upgrade required**

Summary:

- Adds a leader-only `L1TokenVault.abandonChannelOperation(channelId)` function.
- Records the public abandonment timestamp in `channelOperationAbandonedAt(channelId)`.
- Emits `ChannelOperationAbandoned(channelId, leader, abandonedAt)`.
- Rejects future `joinChannel(...)` calls for abandoned channels.
- Rejects future `depositToChannelVault(...)` calls for abandoned channels.
- Leaves `withdrawFromChannelVault(...)`, `exitChannel(...)`, and `ChannelManager.executeChannelTransaction(...)`
  unrestricted by abandonment.
- Supports existing channels after the shared `L1TokenVault` proxy is upgraded because
  join and deposit enforcement runs through the shared vault path.

## Mainnet Deployments

### 2026-05-11 Bridge Mainnet Upgrade

Status: **Mainnet deployed**

Source commit: `b3910b39d49cd4d13bb167999dca48c917878b56`

Artifact: `deployment/chain-id-1/bridge/20260511T065651Z/bridge.1.json`

Included bridge changes:

- Upgraded the UUPS bridge stack on Ethereum mainnet while preserving the existing
  `BridgeCore`, `DAppManager`, and `L1TokenVault` proxy addresses.
- Added the `BridgeCore` channel workspace mirror registry, allowing each channel leader
  to set, update, read, or clear the official workspace mirror URI for that channel.
- Added `ChannelWorkspaceMirrorUpdated`, `OnlyChannelLeader`, and
  `WorkspaceMirrorUriTooLong` to support mirror URI management and validation.
- Validated `ChannelManager` verifier compatible backend version strings against the
  `DAppManager` snapshot during channel creation.
- Replaced the recorded implementations and standalone support contracts for the current
  source commit while keeping Merkle tree depth `36`, Groth16 backend version `0.2`, and
  Tokamak backend version `2.1`.

Verification:

- `BridgeCore` implementation `0x1713171adc06BF82b4f05945d742FFd351a8d1bD` was submitted
  to Etherscan and verified.
- `DAppManager`, `L1TokenVault`, and proxy verification links were confirmed as already
  verified or successfully linked.
- The post-upgrade EIP-1967 implementation slot for the `BridgeCore` proxy matched the
  deployment artifact.

Operational notes:

- Existing channel managers were not redeployed.
- The workspace mirror registry starts empty for existing channels. Channel leaders must
  register mirror URIs before users can recover channel workspaces from mirror servers.

### 2026-05-04 Initial Mainnet Bridge Deployment

Status: **Mainnet deployed**

Source commit: `caecf7679d17ad9855580390edc9da469bbafb81`

Artifact: `deployment/chain-id-1/bridge/20260504T001437Z/bridge.1.json`

Included bridge changes:

- Deployed the UUPS bridge stack for Ethereum mainnet:
  `BridgeCore`, `DAppManager`, and `L1TokenVault` proxies plus their implementations.
- Deployed standalone `ChannelDeployer`, `Groth16Verifier`, and `TokamakVerifier`.
- Set the bridge Merkle tree depth to `36`, matching the generated `TokamakEnvironment`
  and the published Groth16 `updateTree` CRS package.
- Snapshotted Groth16 compatible backend version `0.2` and Tokamak compatible backend
  version `2.1`.
- Included DApp metadata digest management, DApp metadata update support, function root
  commitments, and per-execution function metadata Merkle proofs.
- Included permissionless channel creation where `leader = msg.sender`.
- Included immutable per-channel policy snapshots for DApp digest, function root, verifier
  addresses, verifier compatible backend versions, managed storage vector, and refund policy.
- Included channel join toll accounting and time-decayed toll refund schedule.
- Included channel-vault zero-balance tracking from Groth-backed vault writes and
  Tokamak-observed liquid-balance storage writes, so `exitChannel` is rejected while the
  channel L2 balance is nonzero.
- Included mainnet deployment safety gates: remote source metadata, Drive deployment-history
  checks for redeploy protection, generated ABI manifests, Groth16 artifact mirrors, and
  Tokamak verifier reflection metadata.

Operational notes:

- This was the first mainnet bridge deployment. There is no earlier mainnet bridge deployment
  entry in this changelog.
- Future changes to `BridgeCore`, `DAppManager`, or `L1TokenVault` implementation code must
  be classified here before deployment as either UUPS-upgrade-required or no-deployment-required.
- Future replacement of `ChannelDeployer`, Groth16 verifier, or Tokamak verifier is a privileged
  deployment event and must be recorded as a mainnet deployment entry even if proxy addresses
  remain stable.

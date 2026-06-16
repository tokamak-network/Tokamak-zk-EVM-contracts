# Bridge Changelog

This changelog records bridge-contract and bridge-deployment changes against Ethereum
mainnet deployments. It has two jobs:

- identify which repository changes exist after the latest mainnet deployment but are not
  yet included in a mainnet bridge implementation
- record which source commit, contract addresses, verifier versions, and policy changes were
  included in each mainnet deployment

The deployment artifact is the source of truth for deployed code. For mainnet, the current
artifact is `deployment/chain-id-1/bridge/20260616T171250Z/bridge.1.json`.

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
| Deployment timestamp | `20260616T171250Z` |
| Deployment artifact | `deployment/chain-id-1/bridge/20260616T171250Z/bridge.1.json` |
| Deployed source commit | `e18854c8a228b5ab3e4e308c7f7404e15caf465d` |
| `origin/main` at changelog update | `e18854c8a228b5ab3e4e308c7f7404e15caf465d` |
| GitHub-main changes pending mainnet deployment | None at the time this entry was written |
| Merkle tree depth | `36` |
| Groth16 compatible backend version | `0.2` |
| Tokamak compatible backend version | `2.1` |

### Mainnet Addresses

| Component | Address |
| --- | --- |
| `BridgeCore` proxy | `0x992E2Ae206620d811832a8F697c526c4f95974b6` |
| `BridgeCore` implementation | `0xB1815dF9382449F48E2c26cAd75a07a51E3d72Fa` |
| `DAppManager` proxy | `0x88Ab290a9dc0a169240EBC282Ec1F7C8524645aA` |
| `DAppManager` implementation | `0xB04F5137707aC1747aA3a92110B8cd084Db8f7F0` |
| `L1TokenVault` proxy | `0xf127Aef661c815ad46c5159146078f6F1E9f5F61` |
| `L1TokenVault` implementation | `0xfF78b4395E4e37E4d107c4CCC98380A51bD0FebF` |
| `ChannelDeployer` | `0x30f4AF8263fAC1E46f2795D44A5eb894D02658ff` |
| `Groth16Verifier` | `0x5618176233C03f9693BBF3E90d8881729B2bEB55` |
| `TokamakVerifier` | `0x9fDBDFDfD5CFbd38348FE709296E2E1063Bbd2Bd` |
| Owner at deployment | `0xBE637160D21975EF1e0270D32Bfc547c2EA8DcC3` |
| Deployer | `0x850dD0721B93D455b55bdf1324595fA1BD2B3ce7` |

## Pending Changes Not Yet Included in Mainnet

### Pending GitHub Main

None. `origin/main` currently points to the same commit recorded in the latest mainnet
deployment artifact.

### Local Pending

None. This working repository currently points to the same commit recorded in the latest
mainnet deployment artifact.

## Mainnet Deployments

### 2026-06-16 Bridge Mainnet Upgrade

Status: **Mainnet deployed**

Source commit: `e18854c8a228b5ab3e4e308c7f7404e15caf465d`

Artifact: `deployment/chain-id-1/bridge/20260616T171250Z/bridge.1.json`

Upgrade plan artifact: `deployment/chain-id-1/bridge-upgrade-plans/20260616T153400Z/bridge.1.json`

Drive artifact folder: `https://drive.google.com/drive/folders/1Ex9ZJJRP4e4SwkfL6I7IpwF5nuS_kmm7`

Safe execution:

- Upgrade batch transaction:
  `0x718f9d2acb51b4074245eca4c3a6ee6bf625b857148127739c5836467272b6e1`
- Join Toll refund schedule follow-up transaction:
  `0xfb6e3c2d341fc36fee6097fd1387ced2fd8a34dd21fef111b4eb0c0d0a5834eb`
- Safe transaction hashes:
  - Upgrade batch:
    `0xe5fdebfcf64fa07cae1024385f6674d5d3da1216da61c2c8caa5c162081d66b2`
  - Schedule follow-up:
    `0x11ea8fc85784f942d9ffdebfbbfd7232c1370c7ec763352d3b1d27514a79ae64`

Included bridge changes:

- Upgraded the UUPS bridge stack on Ethereum mainnet while preserving the existing
  `BridgeCore`, `DAppManager`, and `L1TokenVault` proxy addresses.
- Replaced the implementation contracts and standalone support contracts:
  - `DAppManager` implementation:
    `0xB04F5137707aC1747aA3a92110B8cd084Db8f7F0`
  - `BridgeCore` implementation:
    `0xB1815dF9382449F48E2c26cAd75a07a51E3d72Fa`
  - `L1TokenVault` implementation:
    `0xfF78b4395E4e37E4d107c4CCC98380A51bD0FebF`
  - `ChannelDeployer`:
    `0x30f4AF8263fAC1E46f2795D44A5eb894D02658ff`
  - `Groth16Verifier`:
    `0x5618176233C03f9693BBF3E90d8881729B2bEB55`
  - `TokamakVerifier`:
    `0x9fDBDFDfD5CFbd38348FE709296E2E1063Bbd2Bd`
- Added the Safe-based mainnet upgrade plan flow. The deployment EOA prepares implementation and
  support contracts, while owner-only proxy and bridge administration calls are executed by the
  bridge owner Safe.
- Centralized DApp function metadata hashing in `DAppFunctionMetadataHasher` so registration-time
  leaves and execution-time function proof verification share the same domain constants and field
  order.
- Refactored repeated `ChannelManager` access checks while preserving public ABI, custom errors,
  and storage layout.
- Centralized bridge and DApp Drive upload orchestration in a shared upload helper.
- Updated the default Join Toll refund policy for future channels from
  `6 hours -> 75%`, `24 hours -> 50%`, `3 days -> 25%`, and later `0%` to
  `24 hours -> 0%`, `3 days -> 25%`, `7 days -> 50%`, and later `75%`.
- Updated Join Toll refund schedule validation so configured refund percentages must stay flat or
  increase as participation time increases.
- Updated `L1TokenVault.exitChannel(...)` so future exits transfer the refundable portion to the
  exiting user and transfer the non-refundable portion to
  `0x000000000000000000000000000000000000dEaD`.
- Added leader-only channel operation abandonment through
  `L1TokenVault.abandonChannelOperation(channelId)`.
- Added public abandonment timestamps through `channelOperationAbandonedAt(channelId)` and the
  `ChannelOperationAbandoned(channelId, leader, abandonedAt)` event.
- Rejects future joins and channel deposits for abandoned channels while leaving withdrawals,
  exits, and channel transaction execution available.

Verification:

- `DAppManager`, `BridgeCore`, and `L1TokenVault` EIP-1967 implementation slots matched the final
  artifact after the Safe upgrade batch executed.
- `BridgeCore.channelDeployer()`, `BridgeCore.grothVerifier()`,
  `BridgeCore.tokamakVerifier()`, and `DAppManager.bridgeCore()` matched the final artifact.
- `BridgeCore.defaultJoinTollRefundCutoff*` and `BridgeCore.defaultJoinTollRefundBps*` were
  verified after the follow-up Safe transaction:
  - `24 hours -> 0%`
  - `3 days -> 25%`
  - `7 days -> 50%`
  - later `75%`
- The final schedule satisfies the new increasing-cutoff and non-decreasing-refund validation
  rule used by future `ChannelManager` deployments.
- Existing `the-great-first-channel` state remained readable after the upgrade and schedule update.
- New implementation and support contract source entries were verified on Etherscan.
- Existing proxy source entries were already verified on Etherscan.
- Etherscan proxy links were verified against the new implementations.

Operational notes:

- Existing channel managers were not redeployed. Their immutable per-channel refund policy remains
  unchanged.
- The new Join Toll refund defaults apply to channels created after the schedule update.
- The abandonment policy is enforced through the shared upgraded `L1TokenVault` path, so existing
  channels use the new join and deposit restrictions once a channel operation is abandoned.

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

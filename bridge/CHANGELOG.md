# Bridge Changelog

This changelog records bridge-contract and bridge-deployment changes against Ethereum
mainnet deployments. It has two jobs:

- identify which repository changes exist after the latest mainnet deployment but are not
  yet included in a mainnet bridge implementation
- record which source commit, contract addresses, verifier versions, and policy changes were
  included in each mainnet deployment

The deployment artifact is the source of truth for deployed code. For mainnet, the current
artifact is `deployment/chain-id-1/bridge/20260504T001437Z/bridge.1.json`.

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
| Deployment timestamp | `20260504T001437Z` |
| Deployment artifact | `deployment/chain-id-1/bridge/20260504T001437Z/bridge.1.json` |
| Deployed source commit | `caecf7679d17ad9855580390edc9da469bbafb81` |
| `origin/main` at changelog update | `caecf7679d17ad9855580390edc9da469bbafb81` |
| GitHub-main changes pending mainnet deployment | None at the time this entry was written |
| Merkle tree depth | `36` |
| Groth16 compatible backend version | `0.2` |
| Tokamak compatible backend version | `2.1` |

### Mainnet Addresses

| Component | Address |
| --- | --- |
| `BridgeCore` proxy | `0x992E2Ae206620d811832a8F697c526c4f95974b6` |
| `BridgeCore` implementation | `0x0eC8DeEb01e7a7b43818DFfA670F0460cf292Dae` |
| `DAppManager` proxy | `0x88Ab290a9dc0a169240EBC282Ec1F7C8524645aA` |
| `DAppManager` implementation | `0xe9DDe46d97149E59b1919Af533d41fAedefca33F` |
| `L1TokenVault` proxy | `0xf127Aef661c815ad46c5159146078f6F1E9f5F61` |
| `L1TokenVault` implementation | `0xfDA73D59AB5Ab8d3f681384225Cf350Bb7b6Ba92` |
| `ChannelDeployer` | `0xE9B3d20e5925DEB506B5F5cCA94F753B6A34Af7C` |
| `Groth16Verifier` | `0xC1523baF508B5d45663Cb69fc0cA7F35e82101eB` |
| `TokamakVerifier` | `0xfC0BaCc0628BafAcB7Ce52fde21680caAA3cC9E1` |
| Owner at deployment | `0x850dD0721B93D455b55bdf1324595fA1BD2B3ce7` |
| Deployer | `0x850dD0721B93D455b55bdf1324595fA1BD2B3ce7` |

## Pending Changes Not Yet Included in Mainnet

### Pending GitHub Main

None. `origin/main` currently points to the same commit recorded in the latest mainnet
deployment artifact.

### Local Pending

These commits are ahead of the deployed source commit in the local repository. They are not
included in the current mainnet bridge deployment. Once pushed to GitHub, they should move to
the pending-GitHub section until a new mainnet deployment artifact records them.

#### Requires Bridge Mainnet Upgrade

| Commit | Change | Deployment impact |
| --- | --- | --- |
| `a21b23d` | Validate `ChannelManager` verifier compatible backend version strings against the `DAppManager` snapshot during `BridgeCore.createChannel`. | Requires a `BridgeCore` UUPS implementation upgrade to affect future channel creation. No storage layout change. |

#### No Bridge Deployment Required

| Commit | Change |
| --- | --- |
| `07423d2` | Add recovery hints to private-state CLI errors. |
| `f71ef15` | Unify private-state CLI JSON output behind `--json`. |
| `a4fad24` | Make private-state `doctor` human-readable by default. |
| `ddd58e1` | Add private-state CLI `guide` command. |
| `a98a44d` | Remove account import `--force`. |
| `57993b7` | Remove stale exit-channel `--force`. |
| `9e2dad7` | Clarify recover-wallet secret requirements. |
| `4071268` | Require wallet secret path for channel joins. |
| `911291f` | Relax imported source secret file permission checks while keeping canonical secrets protected. |
| `c920004` | Add interactive private-state CLI uninstall. |
| `ee85a1d` | Normalize private-state CLI command names. |
| `d3d181c` | Persist private-state CLI RPC URLs. |
| `cce13e9` | Simplify private-state wallet secret creation. |
| `df056a9` | Restrict private-state CLI secret sources. |
| `b43f63f` | Add local secret sources for private-state CLI. |
| `30f8354` | Add private-state channel lookup command. |
| `da62bab` | Add workspace recovery log checkpointing. |

## Mainnet Deployments

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

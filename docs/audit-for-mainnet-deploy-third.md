# Mainnet Deployment Security Audit - Third Pass

Date: 2026-05-02
Reviewed commit: `6751ad2`
Branch: `bridge-mainnet-audit-second`

Scope: only the `ChannelDeployer` split introduced by `6751ad2`. This pass does not re-audit the
full bridge, DAM/CBV policy, private-state DApp logic, gas documentation, or npm audit findings
except where the new split touches them.

## Change Summary

The latest change moves `ChannelManager` deployment mechanics out of `BridgeCore` and into the new
`ChannelDeployer` contract.

`BridgeCore` still owns the channel-creation policy decision:

- Channel ID uniqueness.
- Bound bridge token vault requirement.
- Non-zero leader.
- Bridge Merkle tree configuration check.
- Maximum managed-storage count check.
- Expected DApp metadata digest check.
- Channel registry write.
- `ChannelCreated` event emission.

`ChannelDeployer` now performs the deployment mechanics:

- Reads managed storage addresses from `DAppManager`.
- Reads registered function references from `DAppManager`.
- Builds the zero-filled initial root vector.
- Deploys `ChannelManager`.
- Returns the deployed manager address to `BridgeCore`.

The split solved the deploy-blocking `BridgeCore` size pressure:

| Contract | Runtime Size | Runtime Margin |
| --- | ---: | ---: |
| `BridgeCore` | `8,822 bytes` | `15,754 bytes` |
| `ChannelDeployer` | `16,062 bytes` | `8,514 bytes` |
| `ChannelManager` | `9,749 bytes` | `14,827 bytes` |
| `DAppManager` | `14,122 bytes` | `10,454 bytes` |

Before the split, `BridgeCore` had only `911 bytes` of runtime margin after the temporary getter
removal. The root contract now has enough bytecode room for future UUPS hardening.

## Findings

1. Medium: `BridgeCore` now trusts a mutable external deployer to return the channel manager that
   becomes canonical for a channel.

   Status: open for explicit operator acceptance or pre-mainnet hardening.

   `BridgeCore.createChannel(...)` still validates the DApp metadata digest, managed-storage count,
   leader, bridge token vault, and Merkle tree configuration. However, the actual `ChannelManager`
   deployment is delegated to `channelDeployer.deployChannelManager(...)`. `BridgeCore` then casts
   the returned address to `ChannelManager`, calls `bindBridgeTokenVault(...)`, reads
   `aPubBlockHash()`, stores that address in `_channels[channelId]`, and emits `ChannelCreated`.

   The deployment script deploys the expected `ChannelDeployer`, and `BridgeCore.initialize(...)`
   plus `setChannelDeployer(...)` reject zero addresses and EOAs. That prevents a trivial invalid
   address, but it does not prove that the deployer address is the audited implementation or that
   the returned manager has the exact expected immutable snapshot.

   Attack or failure model:

   - If the owner accidentally or maliciously sets `channelDeployer` to an incompatible contract,
     future `createChannel(...)` calls can revert or register a bad manager.
   - If the wrong deployer returns a contract that implements the expected selectors but does not
     preserve `ChannelManager` semantics, the channel can become permanently bound to a bad
     execution boundary.
   - This does not let an arbitrary user mutate an existing channel because `createChannel(...)` and
     `setChannelDeployer(...)` remain owner-only. The risk is an owner/governance/deployment-path
     risk for future channels.

   Recommended hardening:

   - Add post-deployment invariants in `BridgeCore.createChannel(...)` before writing `_channels`.
     At minimum, check the returned manager's `bridgeCore()`, `channelId()`, `dappId()`,
     `leader()`, `dappMetadataDigestSchema()`, `dappMetadataDigest()`, `grothVerifier()`,
     `tokamakVerifier()`, and `channelTokenVaultTreeIndex()`.
   - Consider checking `channelManagerAddress.code.length != 0` before interacting with it.
   - Record the audited `ChannelDeployer` source commit and address in deployment metadata and make
     the operator verify it before channel creation.

   UUPS upgradeability classification: fixable for future channels by upgrading `BridgeCore` or by
   setting a corrected `ChannelDeployer`. Not fixable for a channel already created with a bad
   registered manager because `ChannelManager` policy is intentionally immutable and the channel
   registry entry represents the user's accepted channel boundary.

2. Medium: the `BridgeCore` storage layout changed relative to pre-split deployments.

   Status: acceptable for the stated first-mainnet-deployment assumption, unsafe for upgrading a
   pre-split `BridgeCore` proxy without a migration-aware implementation.

   The change adds `ChannelDeployer public channelDeployer` between existing `dAppManager` and
   `grothVerifier` storage declarations. This is safe for a first deployment of the current
   implementation because the proxy storage is initialized from zero using the new layout. It is not
   storage-layout compatible with an already deployed pre-split `BridgeCore` proxy.

   Impact if applied to an old proxy:

   - The old `grothVerifier` storage slot would be interpreted as `channelDeployer`.
   - The old `tokamakVerifier` slot would be interpreted as `grothVerifier`.
   - Later fields would shift, corrupting bridge configuration.

   The current launch assumption is that mainnet has not yet been deployed. Under that assumption,
   this is not a mainnet deployment blocker as long as `redeploy-proxy` is truly the first mainnet
   bridge deployment. It is still relevant for Sepolia/local upgrades and for any unexpected mainnet
   artifact discovered before launch.

   Recommended hardening:

   - If pre-split deployments must be upgraded, add an explicit migration-compatible implementation
     or move the new field to an append-only storage slot before using `UpgradeBridgeStack`.
   - For mainnet, keep the Google Drive deployment-history gate in force and refuse upgrade mode if
     no verified current-layout proxy exists.
   - Add a storage-layout diff check to CI before any future UUPS upgrade.

   UUPS upgradeability classification: not safely fixable after a corrupted upgrade transaction has
   executed, except by a carefully designed recovery upgrade if ownership and enough critical state
   remain recoverable. Preventable before mainnet by first-deploying the current layout or by using
   an append-only layout before upgrading old proxies.

3. Low: `ChannelDeployer` is permissionless and can deploy orphan `ChannelManager` contracts.

   Status: accepted operational risk if all tools treat `BridgeCore` as the only authoritative
   channel registry.

   Anyone can call `ChannelDeployer.deployChannelManager(...)` directly with arbitrary parameters.
   That can create `ChannelManager` contracts that are not registered in `BridgeCore`. These orphan
   managers do not receive bridge custody authority through `L1TokenVault`, because `L1TokenVault`
   resolves channels through `BridgeCore.getChannelManager(channelId)`. If a caller passes the real
   `BridgeCore` address as the `bridgeCore` constructor argument, the orphan manager still cannot be
   bound to the bridge token vault unless the real `BridgeCore` calls `bindBridgeTokenVault(...)`.

   The direct protocol risk is low. The operational risk is phishing or indexer confusion if a UI,
   explorer, or script treats `ChannelManager` deployment events or contract existence as channel
   authority instead of checking the `BridgeCore` registry.

   Recommended hardening:

   - Make all user-facing tools and indexers resolve channels only from `BridgeCore.getChannel(...)`
     or `BridgeCore.getChannelManager(...)`.
   - Optionally restrict `ChannelDeployer` with an immutable authorized `BridgeCore` if orphan
     channel deployment noise becomes unacceptable.

   UUPS upgradeability classification: fixable for future deployments by replacing the deployer and
   upgrading `BridgeCore` if needed. Already deployed orphan managers are harmless if ignored by
   tooling, but they cannot be deleted from chain history.

4. Low: deployment artifacts and ABI manifests now include a new contract address.

   Status: resolved by scripts and E2E.

   `DeployBridgeStack.s.sol`, `UpgradeBridgeStack.s.sol`, and
   `generate-bridge-abi-manifest.mjs` now include `channelDeployer`. The private-state CLI E2E
   passed after this change, which confirms that existing CLI channel creation still works with the
   new artifact shape.

   Residual operational requirement: mainnet deployment review must include the `channelDeployer`
   address and source commit together with the existing proxy, verifier, and vault addresses.

   UUPS upgradeability classification: artifact omissions are operationally fixable before users
   rely on the deployment metadata. They do not change already-created channel semantics.

## Non-Findings

### BridgeCore Remains The Policy Root

The split does not move DApp metadata digest policy, channel ID uniqueness, managed-storage count
limit, bridge token vault binding requirement, or channel registry ownership out of `BridgeCore`.
This preserves `BridgeCore` as the canonical policy and registry root rather than turning
`ChannelDeployer` into the policy owner.

### Channel Policy Immutability Is Preserved

`ChannelManager` is still deployed once per channel and remains non-upgradeable. Existing channels
still do not follow later `BridgeCore`, `DAppManager`, verifier, or deployer changes.

### L1TokenVault Channel Resolution Is Unchanged

`L1TokenVault` still resolves channel managers through `IChannelRegistry.getChannelManager(...)`,
with `BridgeCore` as the registry. It does not trust `ChannelDeployer` directly.

### DAM/CBV Digest Semantics Are Unchanged

The split does not change how `DAppManager` computes or stores metadata digests, verifier snapshots,
or compatible backend versions. `BridgeCore.createChannel(...)` still requires
`expectedDAppMetadataDigest`.

## Verification Performed

- `forge test --root bridge`
  - Passed 65 tests.
- `forge build --root bridge --sizes`
  - Passed.
  - `BridgeCore`: `8,822 bytes`, margin `15,754 bytes`.
  - `ChannelDeployer`: `16,062 bytes`, margin `8,514 bytes`.
- `forge fmt --root bridge --check`
  - Passed after formatting generated verifier files that the E2E deployment flow rewrote.
- `node --check bridge/scripts/deploy-bridge.mjs`
  - Passed.
- `node --check bridge/scripts/generate-bridge-abi-manifest.mjs`
  - Passed.
- `git diff --check`
  - Passed before this document was added.
- Private-state CLI E2E with local private-state CLI tarball and `@tokamak-zk-evm/cli@2.0.16`
  passed after the split.
  - Covered bridge deployment, DApp registration, channel creation through `ChannelDeployer`, three
    participant joins, bridge/channel deposits, mint, transfer, redeem, channel withdrawal, exit,
    and bridge withdrawal.

## Deployment Decision

Do not broadcast mainnet until the operator explicitly accepts or mitigates Findings 1 and 2.

For the stated first-mainnet-deployment assumption, the storage-layout issue is not a blocker if the
remote deployment history confirms that no previous mainnet bridge proxy exists and the deployment
uses the current implementation as the first proxy implementation.

The stronger pre-mainnet posture is to add `BridgeCore` post-deployment invariant checks for the
returned `ChannelManager`. The split created enough `BridgeCore` bytecode margin to add those checks
without reintroducing the original size problem. If the operator accepts owner-only deployer trust
instead, channel creation must be treated as an explicit commitment to the audited
`ChannelDeployer` address and source commit.

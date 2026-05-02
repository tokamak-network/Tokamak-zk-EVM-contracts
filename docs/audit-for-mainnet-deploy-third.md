# Mainnet Deployment Security Audit - Third Pass

Date: 2026-05-02
Reviewed base commit: `a932504`
Branch: `bridge-mainnet-audit-second`

Scope: only the `ChannelDeployer` split, the follow-up thin-factory hardening, the
`BridgeAdminManager` removal, and the later function metadata root/proof update. This pass does not
re-audit the full bridge, DAM/CBV policy, private-state DApp logic, gas documentation, or npm audit
findings except where these changes touch them.

## Change Summary

The latest change keeps `ChannelManager` deployment mechanics out of `BridgeCore`, but narrows
`ChannelDeployer` into a thin factory.

`BridgeCore` still enforces the channel-creation policy:

- Channel ID uniqueness.
- Bound bridge token vault requirement.
- Channel leader is fixed to the channel creator (`msg.sender`).
- Maximum managed-storage count check.
- Expected DApp metadata digest check.
- Channel registry write.
- `ChannelCreated` event emission.

`ChannelDeployer` now performs only the external deployment step:

- Deploys `ChannelManager`.
- Returns the deployed manager address to `BridgeCore`.

`ChannelManager` now performs its own initialization from `DAppManager`:

- Reads managed storage addresses from `DAppManager`.
- Checks the managed-storage count against the `BridgeCore`-validated count.
- Builds the zero-filled initial root vector.
- Stores the registered DApp function root passed by `BridgeCore`.

Function metadata is no longer deep-copied into every `ChannelManager`. `DAppManager` computes a
Merkle root over the registered function metadata at DApp registration/update time. `BridgeCore`
passes that root into the channel constructor, validates that the returned manager exposes the same
root, and channel execution requires calldata-supplied function metadata plus a Merkle proof against
the channel's immutable root.

`BridgeCore` now validates the returned manager before binding the bridge token vault or writing the
channel registry:

- `code.length`.
- `bridgeCore`.
- `channelId`.
- `dappId`.
- `leader`.
- `channelTokenVaultTreeIndex`.
- DApp metadata digest schema and digest.
- DApp function root.
- Groth16 verifier address.
- Tokamak verifier address.
- Initial join fee.
- Join-fee refund schedule.

The follow-up cleanup removes `BridgeAdminManager`. The bridge no longer stores a mutable or
separately administered Merkle-tree depth. Tree-depth dependent logic uses the generated
`TokamakEnvironment` constants directly in the contracts that actually need them, primarily
`ChannelManager`.

The split solved the deploy-blocking `BridgeCore` size pressure:

| Contract | Runtime Size | Runtime Margin |
| --- | ---: | ---: |
| `BridgeCore` | `10,437 bytes` | `14,139 bytes` |
| `ChannelDeployer` | `15,003 bytes` | `9,573 bytes` |
| `ChannelManager` | `10,957 bytes` | `13,619 bytes` |
| `DAppManager` | `12,294 bytes` | `12,282 bytes` |

Before the split, `BridgeCore` had only `911 bytes` of runtime margin after the temporary getter
removal. The root contract still has enough bytecode room after the returned-manager invariant
checks. After the function metadata root/proof update and the permissionless channel-creation
change, `BridgeCore.createChannel` measured 2,731,347 gas in the current Forge gas report, down from
the earlier 3,884,651 gas deep-copy design. The follow-up cleanup removed the old on-chain DApp
function metadata lookup layer from `DAppManager`; function metadata is now validated during
registration/update, committed through `functionRoot`, and published through the registration
manifest used by the CLI.

## Findings

1. Low: `BridgeCore` still depends on the configured deployer returning a contract with correct
   `ChannelManager` semantics, but the metadata/snapshot compatibility risk has been mitigated.

   Status: mitigated by this change; residual bytecode-identity risk remains operational.

   `BridgeCore.createChannel(...)` still validates the DApp metadata digest, managed-storage count,
   caller-derived leader, and bridge token vault. The actual `ChannelManager` deployment is still
   delegated to `channelDeployer.deployChannelManager(...)`, but the deployer no longer assembles
   managed-storage arrays, function references, or the initial root vector.
   `ChannelManager` reads those values from `DAppManager` itself.

   After deployment, `BridgeCore` now verifies that the returned contract has code and that its
   externally visible snapshot matches the channel policy that `BridgeCore` just approved:
   `bridgeCore`, `channelId`, `dappId`, `leader`, `channelTokenVaultTreeIndex`,
   `dappMetadataDigestSchema`, `dappMetadataDigest`, `functionRoot`, `grothVerifier`,
   `tokamakVerifier`, `joinFee`, and the join-fee refund schedule.

   This mitigates the main compatibility failure modes:

   - If the owner accidentally or maliciously sets `channelDeployer` to an incompatible contract,
     future `createChannel(...)` calls should revert before the bad manager is bound or registered
     unless that contract faithfully exposes the expected snapshot.
   - If a deployer passes the wrong DApp, verifier, channel ID, caller-derived leader, digest, fee,
     or refund schedule into the manager constructor, `BridgeCore` rejects the returned manager.
   - Because `ChannelManager` reads DApp storage metadata directly from `DAppManager` and stores the
     function root approved by `BridgeCore`, the deployer can no longer tamper with those values
     while still using the audited `ChannelManager`.

   Residual risk:

   - The invariant checks do not prove full bytecode identity. A malicious contract could mimic the
     checked getters and still implement unsafe channel-execution semantics. This remains an
     owner/deployment-path risk because only the bridge owner can set `channelDeployer`.

   Recommended operating control:

   - Record the audited `ChannelDeployer` source commit and address in deployment metadata and make
     the operator verify it before enabling public channel creation.
   - Treat a `channelDeployer` change as a privileged deployment event requiring the same review
     level as a `BridgeCore` upgrade.

   UUPS upgradeability classification: the invariant checks are now implemented for future
   channels. The residual bytecode-identity risk is fixable for future channels by setting a
   corrected deployer or upgrading `BridgeCore`; it is not fixable for a channel already created
   with a bad registered manager because `ChannelManager` policy is intentionally immutable.

2. Medium: the `BridgeCore` storage layout changed relative to earlier local/pre-mainnet
   implementations.

   Status: acceptable for the stated first-mainnet-deployment assumption, unsafe for upgrading a
   pre-split `BridgeCore` proxy without a migration-aware implementation.

   The changes remove `BridgeAdminManager public adminManager` and add
   `ChannelDeployer public channelDeployer` before the verifier fields. This is safe for a first
   deployment of the current implementation because the proxy storage is initialized from zero using
   the new layout. It is not storage-layout compatible with an already deployed older `BridgeCore`
   proxy.

   Impact if applied to an old proxy:

   - A proxy initialized with an older layout would interpret the existing slots under the new field
     order.
   - Verifier, deployer, vault, and refund-schedule fields could be read from the wrong slots.
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

4. Low: deployment artifacts and ABI manifests changed shape.

   Status: resolved by scripts and E2E.

   `DeployBridgeStack.s.sol`, `UpgradeBridgeStack.s.sol`, and
   `generate-bridge-abi-manifest.mjs` now include `channelDeployer` and no longer include
   `bridgeAdminManager`. The private-state CLI E2E passed after this change, which confirms that
   existing CLI channel creation still works with the new artifact shape.

   Residual operational requirement: mainnet deployment review must include the `channelDeployer`
   address and source commit together with the existing proxy, verifier, and vault addresses.

   UUPS upgradeability classification: artifact omissions are operationally fixable before users
   rely on the deployment metadata. They do not change already-created channel semantics.

5. Informational: function metadata now moves through calldata during execution, but is root-bound.

   Status: no unresolved security finding from this update.

   `ChannelManager.executeChannelTransaction(...)` now accepts a `FunctionMetadataProof` containing
   function metadata and Merkle siblings. The manager hashes the metadata on-chain and verifies the
   proof against the immutable `functionRoot` stored at channel creation. It then checks that:

   - the proved metadata preprocess hash equals the hash of the submitted Tokamak preprocess points;
   - the entry contract and function selector decoded from `aPubUser` match the proved metadata;
   - event-log decoding metadata is taken from the proved metadata, not from uncommitted calldata.

   This preserves the intended channel policy immutability without per-channel function metadata
   storage. A malformed CLI manifest or wrong proof causes execution to revert; it does not let an
   executor choose an unregistered function or alternate event-log layout.

   Residual operational requirement: registration manifests must preserve the function metadata and
   Merkle proofs generated at DApp registration/update time. Losing the manifest does not compromise
   funds, but it can make user execution unavailable until the proof material is reconstructed from
   the registered metadata artifacts.

   UUPS upgradeability classification: the root-bound verification is active for newly created
   channels. Existing channels created before this update keep their old execution ABI and cannot be
   retrofitted without creating new channels.

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

### DAM/CBV Digest Semantics Are Preserved

The split does not change the DAM/CBV channel commitment rule: channel creation still freezes the
registered DApp digest and verifier snapshot. The function metadata update changes the internal
function commitment from per-channel deep copies to an immutable channel function root, but not the
policy that channels bind to the DApp metadata selected at creation.
or compatible backend versions. `BridgeCore.createChannel(...)` still requires
`expectedDAppMetadataDigest`.

## Verification Performed

- `forge test --root bridge`
  - Passed 64 tests.
  - Includes `testCreateChannelRejectsIncompatibleDeployerReturn`, which verifies that
    `BridgeCore` rejects a deployer-returned manager with a mismatched immutable snapshot.
- `forge build --root bridge --sizes`
  - Passed.
  - `BridgeCore`: `10,437 bytes`, margin `14,139 bytes`.
  - `ChannelDeployer`: `15,003 bytes`, margin `9,573 bytes`.
  - `ChannelManager`: `10,957 bytes`, margin `13,619 bytes`.
  - `DAppManager`: `12,294 bytes`, margin `12,282 bytes`.
- `forge fmt --root bridge --check`
  - Passed.
- `node --check bridge/scripts/deploy-bridge.mjs`
  - Passed.
- `node --check bridge/scripts/generate-bridge-abi-manifest.mjs`
  - Passed.
- `node --check bridge/scripts/admin-add-dapp.mjs`
  - Passed.
- `node --check packages/apps/private-state/scripts/e2e/run-bridge-private-state-cli-e2e.mjs`
  - Passed.
- `node --check packages/apps/private-state/cli/private-state-bridge-cli.mjs`
  - Passed.
- Private-state CLI E2E with local private-state CLI tarball and `@tokamak-zk-evm/cli@2.0.16`
  passed after the DAppManager function metadata lookup cleanup.
  - Covered bridge deployment, DApp registration, channel creation through `ChannelDeployer`, three
    participant joins, bridge/channel deposits, mint, transfer, redeem, channel withdrawal, exit,
    and bridge withdrawal.
- `forge test --root bridge --gas-report`
  - Passed after the permissionless channel-creation change.
  - Current-worktree `BridgeCore.createChannel` successful full-path gas: `2,731,347`.
- Private-state CLI E2E was intentionally not rerun for the permissionless channel-creation change.

## Deployment Decision

Do not broadcast mainnet until the operator explicitly accepts Finding 2 under the first-mainnet
deployment assumption and records the audited `ChannelDeployer` address/source commit in deployment
metadata.

For the stated first-mainnet-deployment assumption, the storage-layout issue is not a blocker if the
remote deployment history confirms that no previous mainnet bridge proxy exists and the deployment
uses the current implementation as the first proxy implementation.

Finding 1's compatibility hardening has been implemented. The remaining deployer risk is the normal
privileged-deployment risk that the operator must verify the actual deployed `ChannelDeployer`
implementation, not just the manager snapshot it returns.

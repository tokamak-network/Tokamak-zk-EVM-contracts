# Mainnet Deployment Security Audit - Third Pass

Date: 2026-05-02
Reviewed code through: `73f214f` (`Make channel creation permissionless`)
Branch: `bridge-mainnet-audit-second`

Scope: bridge contracts, bridge deployment scripts, DApp registration scripts, and the private-state
CLI changes introduced after the second-pass audit. This pass focuses on the `ChannelDeployer`
split, the returned-manager hardening, removal of stale function metadata storage, function-root
proof execution, gas-driven simplification work, and restoration of permissionless channel
creation. It does not re-audit the private-state DApp arithmetic or note logic except where the
bridge changes interact with it.

## Findings

No new unresolved practical mainnet finding was identified in this pass.

The review did identify several risks during development, but they are either resolved in the
current code, accepted design/operational constraints already documented in the first two audit
passes, or non-findings under the current protocol model. The resolved items and review evidence are
listed below so a third-party reviewer can check the implementation path.

## Resolved Issues And Evidence

1. Resolved: `BridgeCore` bytecode-size pressure from direct channel deployment.

   Original issue: before the split, `BridgeCore` was close to the EIP-170 runtime bytecode limit.
   Keeping channel construction, channel policy, and root registry logic in one UUPS implementation
   left too little margin for mainnet hardening.

   Resolution:

   - `6751ad2` split channel deployment into `bridge/src/ChannelDeployer.sol`.
   - `ab5e69b` hardened the split by making `ChannelDeployer` a thin factory and having
     `BridgeCore` validate the returned manager before registry write.
   - `f6ae5b3` removed the redundant `BridgeAdminManager` and its mutable tree-depth plumbing.

   Current-code evidence:

   - `bridge/src/BridgeCore.sol::createChannel(...)` still owns channel ID uniqueness, canonical
     asset selection, bridge token vault requirement, DApp metadata digest check, verifier snapshot
     retrieval, returned-manager validation, vault binding, registry write, and `ChannelCreated`
     emission.
   - `bridge/src/ChannelDeployer.sol::deployChannelManager(...)` only deploys `ChannelManager` and
     returns its address. It does not own channel policy.
   - `bridge/src/ChannelManager.sol` reads managed storage addresses from `DAppManager` during
     construction, validates the count passed by `BridgeCore`, builds the initial root vector, and
     stores the channel's immutable DApp metadata digest and function root.

   Verification evidence:

   - `forge build --root bridge --sizes` after the split reported `BridgeCore` runtime size
     `10,437 bytes`, leaving `14,139 bytes` of runtime margin.
   - `forge test --root bridge` passed after the split and later hardening.

2. Resolved: channel deployment could have accepted an incompatible returned manager.

   Original issue: once deployment was delegated to `ChannelDeployer`, a misconfigured deployer
   could return a manager whose constructor inputs did not match the policy `BridgeCore` had just
   approved. That would be a practical channel-creation risk if the mismatch were not detected
   before the manager was bound and registered.

   Resolution:

   - `BridgeCore` now validates the returned `ChannelManager` before calling
     `bindBridgeTokenVault(...)` and before writing `_channels[channelId]`.
   - The validation checks that the returned address has code and that the returned manager exposes
     the expected `bridgeCore`, `channelId`, `dappId`, `leader`, channel-token-vault tree index,
     DApp metadata digest schema, DApp metadata digest, function root, Groth16 verifier, Tokamak
     verifier, join fee, and refund schedule.

   Current-code evidence:

   - `bridge/src/BridgeCore.sol::_validateChannelManager(...)` performs the returned-manager
     snapshot checks.
   - `bridge/src/BridgeCore.sol::createChannel(...)` calls `_validateChannelManager(...)` before
     binding the bridge token vault and before writing the channel registry.
   - `bridge/test/BridgeFlow.t.sol::testCreateChannelRejectsIncompatibleDeployerReturn` covers the
     rejection path.

   Residual classification:

   - The checks do not prove bytecode identity, but this is not a separate practical mainnet
     finding under the current owner model. Only the bridge owner can set `channelDeployer`, and the
     deployment process must still record and review the deployed `ChannelDeployer` address and
     source commit. This is the same class of privileged deployment review required for verifier and
     UUPS implementation addresses.

3. Resolved: per-channel function metadata deep copies made `createChannel` unnecessarily expensive.

   Original issue: channel creation deep-copied DApp function metadata into every new
   `ChannelManager`. This increased `createChannel` gas and bytecode/data movement without adding a
   stronger channel policy commitment.

   Resolution:

   - `eb7fd30` replaced per-channel function metadata deep copies with an immutable channel
     `functionRoot`.
   - `352494c` removed stale DApp function metadata storage/getters after the root/proof path made
     them unnecessary.

   Current-code evidence:

   - `bridge/src/DAppManager.sol` validates function metadata at registration/update time, hashes
     each function, computes a Merkle root, and stores that root in `DAppInfo.functionRoot`.
   - `bridge/src/BridgeCore.sol::createChannel(...)` passes `dAppInfo.functionRoot` into the channel
     constructor and validates that the returned manager exposes the same root.
   - `bridge/src/ChannelManager.sol::executeChannelTransaction(...)` accepts
     `BridgeStructs.FunctionMetadataProof`, hashes the submitted metadata, verifies the Merkle proof
     against the channel's immutable `functionRoot`, and only then uses the metadata for preprocess
     hash, entry-contract, selector, root-vector offset, and observed-log layout checks.
   - `packages/apps/private-state/cli/private-state-bridge-cli.mjs` now supplies function metadata
     and Merkle proof material from the DApp registration manifest when executing channel
     transactions.

   Security result:

   - The executor cannot select an unregistered function or alternate observed-log layout merely by
     changing calldata. Unproved metadata reverts with `InvalidFunctionMetadataProof`.
   - Losing the registration manifest can affect availability until proof material is reconstructed,
     but it does not authorize an invalid function.

   Gas result:

   - `bridge/docs/gas-assessment.md` records the current measured `BridgeCore.createChannel`
     successful full-path gas as `2,731,347`, down from the earlier deep-copy design measurement of
     `3,884,651`.

4. Resolved: channel creation had drifted into an owner-call classification.

   Original issue: during refactoring and gas documentation, `createChannel` was treated as an
   owner/operator call. That contradicted the original protocol design: anyone should be able to
   create a channel, and the channel creator becomes that channel's leader.

   Resolution:

   - `73f214f` removed the externally supplied `leader` parameter and uses `msg.sender` as the
     channel leader.
   - `createChannel(...)` remains open to any caller while retaining the DApp metadata digest
     preflight, returned-manager validation, channel ID uniqueness, and bridge token vault
     requirement.
   - The private-state CLI now calls `createChannel(channelId, dappId, joinFee, metadataDigest)`.

   Current-code evidence:

   - `bridge/src/BridgeCore.sol::createChannel(...)` sets `address leader = msg.sender`.
   - `bridge/test/BridgeFlow.t.sol::testCreateChannelUsesCallerAsLeader` covers the intended
     behavior.
   - `bridge/docs/gas-assessment.md` classifies `BridgeCore.createChannel` under user calls.

   Non-finding note:

   - Permissionless channel creation means a caller can register a desirable channel name first by
     creating the derived channel ID first. This is not treated as an attack in this protocol model;
     channel names are first-come assets, and users can inspect the actual `BridgeCore` channel
     registry before joining.

5. Resolved: stale DApp function metadata storage remained after the function-root update.

   Original issue: after moving execution to calldata-supplied function metadata proven against a
   root, keeping function metadata arrays in `DAppManager` was redundant and could confuse future
   maintenance.

   Resolution:

   - `352494c` removed stale DApp function metadata storage/getters and the related registration
     manifest fields.
   - Function metadata remains validated at registration/update time and committed through
     `functionRoot`; execution proof material is distributed in the registration manifest and
     checked by the CLI.

   Current-code evidence:

   - `bridge/src/DAppManager.sol` stores managed storage metadata needed by channel construction,
     DApp metadata digest, verifier snapshot, and `functionRoot`; it no longer stores per-function
     metadata for later on-chain lookup.
   - `bridge/scripts/admin-add-dapp.mjs` computes function proofs locally, verifies that the
     on-chain `functionRoot` matches the locally computed root, and writes proof material into the
     registration manifest.

## Rechecked Prior Findings

### First-Pass Finding 1: Non-Zero Channel Exit

Status: resolved and still valid after the third-pass changes.

Evidence:

- `ChannelManager.unregisterChannelTokenVaultIdentity(...)` rejects exit when
  `registration.isZeroBalance` is false.
- `observeChannelTokenVaultStorageWrite(...)` updates the flag from Groth-backed channel-vault
  storage writes using the observed storage key, not the transaction caller.
- `executeChannelTransaction(...)` updates the flag from proof-backed
  `LiquidBalanceStorageWriteObserved(address,bytes32)` logs by decoding the L2 address and value
  from the observed log data.
- Function-root proofs do not weaken this guard because the observed-event layout must be proven
  against the channel's immutable `functionRoot`.

UUPS classification: future exits can be protected by upgrade, but any balance already orphaned or
stolen before the guard would not be reliably recoverable. The guard must remain in the first
mainnet deployment.

### Second-Pass Finding 1: Stale DApp Metadata At Channel Creation

Status: resolved and still valid after the third-pass changes.

Evidence:

- `DAppManager.registerDApp(...)` and `updateDAppMetadata(...)` compute a metadata digest and
  function root.
- `BridgeCore.createChannel(...)` requires the expected digest and rejects mismatch before channel
  deployment.
- `ChannelManager` stores the digest and function root captured at creation.
- The CLI checks the local manifest digest/schema/root against on-chain `DAppInfo` before creating a
  channel.

UUPS classification: future channel creation can be protected by upgrade, but a channel already
created against an explicitly wrong current digest remains immutable and requires migration.

### Second-Pass Finding 2: Mainnet Redeploy-Proxy Safety

Status: resolved for the repository deployment path.

Evidence:

- `bridge/scripts/deploy-bridge.mjs` checks the shared Google Drive deployment-history folder before
  allowing mainnet `redeploy-proxy`.
- The script fails closed if the Drive lookup cannot be configured or performed.
- The script also requires a clean deployment-relevant worktree and a `HEAD` commit contained in
  `origin/main`.

UUPS classification: this is a pre-deployment operational gate. A split proxy deployment already
used by users cannot be repaired into a single state history by UUPS upgrade.

### Second-Pass Finding 3: Immediate Owner Metadata/Verifier Updates

Status: accepted operational risk.

Evidence:

- Owner-controlled verifier and DApp metadata updates affect future DApp snapshots and future
  channels.
- Existing channels remain immutable and do not follow later owner updates.
- The CLI prints the digest, function root, verifier addresses, and compatible backend versions
  before channel creation and first join so users can review the policy they are accepting.

Classification: this is not a practical open protocol finding under the current single-operator
owner model. It remains an operational governance assumption.

## Non-Findings

### ChannelDeployer Can Be Called Directly

`ChannelDeployer.deployChannelManager(...)` is permissionless, so anyone can deploy orphan
`ChannelManager` contracts. This is not a protocol finding because custody and channel authority
come from `BridgeCore.getChannel(...)` / `getChannelManager(...)`, and `L1TokenVault` resolves
channels through `BridgeCore`, not through deployer events or arbitrary manager addresses.

Operational requirement: UIs, indexers, and scripts must treat `BridgeCore` as the only
authoritative channel registry.

### BridgeCore Storage Layout Changed Before First Mainnet Deployment

The split changed `BridgeCore` storage relative to older local/Sepolia pre-split implementations.
That would matter for upgrading an old proxy. It is not a mainnet finding under the stated launch
assumption that no mainnet bridge proxy exists yet and that mainnet will use the current
implementation as the first proxy implementation.

Operational requirement: if a historical mainnet proxy is discovered in the Drive deployment
history before launch, do not deploy this implementation as a blind upgrade. Use a
migration-compatible implementation or first-deployment flow only after the existing state is
understood.

### Function Metadata In Calldata

Moving function metadata to calldata is not a trust downgrade because `ChannelManager` verifies the
metadata against the channel's immutable `functionRoot` before using it. The calldata proof path is
an availability and tooling concern, not an authorization gap.

### Verifier Call Gas Dominates `executeChannelTransaction`

Current CLI E2E receipt measurements place `executeChannelTransaction` around
`827,621-861,608` gas. Unit traces with the verifier mocked show the bridge-side wrapper logic in
the low tens of thousands of gas for the tested paths. This is useful for optimization planning but
does not create a security finding.

## Verification Performed

The following verification was performed during the implementation series covered by this pass:

- `forge test --root bridge`
  - Passed after the channel-deployer split and again after the permissionless channel-creation
    change.
  - Current suite size after the latest commit: 65 tests.
- `forge test --root bridge --gas-report`
  - Passed after the permissionless channel-creation change.
  - Current measured `BridgeCore.createChannel` successful full-path gas: `2,731,347`.
- `forge build --root bridge --sizes`
  - Passed after the latest covered commit.
  - `BridgeCore`: `10,437 bytes`, margin `14,139 bytes`.
  - `ChannelDeployer`: `15,003 bytes`, margin `9,573 bytes`.
  - `ChannelManager`: `10,957 bytes`, margin `13,619 bytes`.
  - `DAppManager`: `12,294 bytes`, margin `12,282 bytes`.
- `forge fmt --root bridge --check`
  - Passed.
- `git diff --check`
  - Passed during the latest implementation verification.
- `node --check packages/apps/private-state/cli/private-state-bridge-cli.mjs`
  - Passed after the permissionless channel-creation update.
- Private-state CLI E2E with a locally packed CLI tarball and `@tokamak-zk-evm/cli@2.0.16`
  passed earlier in this branch after the function metadata proof and stale lookup cleanup.
  It covered bridge deployment, DApp registration, channel creation, participant joins,
  bridge/channel deposits, mint, transfer, redeem, channel withdrawal, exit, and bridge withdrawal.
  It was intentionally not rerun for the later permissionless channel-creation-only change.

## Deployment Decision

From this third-pass review, no new practical unresolved mainnet security finding blocks deployment.

Required mainnet launch controls remain:

- Use the repository deployment path so the Google Drive deployment-history, clean worktree, and
  remote-source gates run.
- Record and review the deployed `ChannelDeployer`, verifier, proxy, vault, and DApp registration
  addresses in deployment metadata.
- Treat `BridgeCore` as the only authoritative channel registry in all user-facing tools.
- Require users and operators to review the DApp metadata digest, function root, verifier snapshot,
  and compatible backend versions before creating or joining a channel.

The non-upgradeable boundary remains the same: once a channel is created, its verifier bindings,
DApp metadata digest, function root, compatible backend versions, storage vector, `aPubBlockHash`,
and refund policy are final for that channel.

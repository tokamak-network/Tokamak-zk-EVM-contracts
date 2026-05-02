# Mainnet Deployment Security Audit

Date: 2026-05-02
Reviewed through: `73f214f` (`Make channel creation permissionless`)
Branch: `bridge-mainnet-audit-second`

This document consolidates the first, second, and third mainnet deployment audit passes. The earlier
pass-specific documents were merged into this single checklist so reviewers can inspect the current
security state without reconciling obsolete intermediate findings.

## System Overview

The system is a bridge plus private-state DApp framework for moving canonical L1 assets into
channel-scoped private-state applications. Users join channels, deposit into channel vault
accounting, execute private-state DApp transitions off-chain, and submit proof-backed public outputs
to L1 contracts.

The main policy choices are:

- Root bridge components are UUPS-upgradeable for future protocol maintenance.
- Each channel is intentionally immutable after creation. A channel's verifier snapshot, DApp
  metadata digest, function root, compatible backend versions, managed storage vector,
  `aPubBlockHash`, and refund policy are fixed for that channel.
- DApp metadata and verifier snapshots can be updated for future channels, but existing channels do
  not follow later updates.
- Channel creation is permissionless. The caller of `BridgeCore.createChannel(...)` becomes that
  channel's leader.
- A policy mistake in an already-created channel is handled by deprecating that channel and creating
  or joining a new one, not by mutating the existing channel in place.

The current contract structure is:

- `BridgeCore`: UUPS policy root and canonical channel registry. It owns verifier pointers,
  channel creation policy, deployment metadata digest checks, and the channel registry.
- `DAppManager`: UUPS DApp registration registry. It stores immutable `dappId`/`labelHash`,
  replaceable future-channel runtime metadata, metadata digest, function root, and verifier
  snapshots.
- `L1TokenVault`: UUPS canonical asset custody and channel join/deposit/withdraw/exit entrypoint.
  It resolves channel managers through `BridgeCore`.
- `ChannelDeployer`: thin factory that deploys `ChannelManager`.
- `ChannelManager`: non-upgradeable per-channel policy and state contract.
- `PrivateStateController` and `L2AccountingVault`: non-upgradeable DApp contracts with
  deployment-time wiring and no owner role.

Component communication is intentionally narrow:

- `DAppManager` snapshots the current bridge verifier addresses and compatible backend versions when
  a DApp is registered or updated.
- `BridgeCore.createChannel(...)` requires an expected DApp metadata digest, retrieves the current
  DApp snapshot from `DAppManager`, asks `ChannelDeployer` to deploy a manager, validates the
  returned manager snapshot, binds the bridge token vault, and writes the canonical registry entry.
- `L1TokenVault` never trusts arbitrary `ChannelManager` addresses. It resolves managers through
  `BridgeCore.getChannelManager(...)`.
- `ChannelManager.executeChannelTransaction(...)` verifies calldata-supplied function metadata
  against the channel's immutable `functionRoot`, calls the Tokamak verifier, processes
  proof-backed observed logs, and updates the channel root vector hash.
- The private-state CLI reads deployment and DApp registration manifests, prints immutable channel
  policy snapshots, checks DApp digest/schema/root values against chain state, and passes the
  expected digest into channel creation.

Mainnet assumptions:

- The reviewed deployment is the first mainnet bridge deployment. If any historical mainnet proxy
  is found, the storage-layout and deployment-mode assumptions must be re-reviewed before broadcast.
- Mainnet deployment uses `bridge/scripts/deploy-bridge.mjs`, not direct ad hoc `forge script`
  commands.
- Google Drive deployment history is the shared source of truth for detecting existing mainnet
  bridge deployment snapshots.
- The bridge owner is a trusted single-operator governance path for mainnet launch.
- Tokamak zk-L2 proofs make observed public outputs, including emitted log data, binding and
  non-forgeable.
- Users and channel creators are expected to inspect the displayed channel policy snapshot before
  signing channel creation or join transactions.

## Checklist Summary

| ID | Checklist Item | Importance | Status |
| --- | --- | --- | --- |
| C1 | Non-zero channel-token-vault exit | Critical | Resolved |
| C2 | Mainnet deployment mode and source integrity | High | Resolved |
| C3 | Stale DApp metadata at channel creation | High | Resolved |
| C4 | DApp metadata/verifier owner update risk | Medium | Accepted with operational controls |
| C5 | Malformed DApp metadata through raw owner calls | Low | Resolved |
| C6 | BridgeCore size pressure from channel deployment | Low | Resolved |
| C7 | Incompatible manager returned by ChannelDeployer | Low | Resolved |
| C8 | Per-channel function metadata deep copy | Low | Resolved |
| C9 | Channel creation permission model drift | Low | Resolved |
| C10 | Privileged bridge owner custody authority | Critical | Accepted trust assumption |
| C11 | Channel registration slot exhaustion | High | Mitigated by economic cost |
| C12 | Exact-transfer canonical asset dependency | Medium | Accepted external dependency |
| C13 | Finite storage leaf projection collisions | Medium | Mitigated by collision-probability reduction |

## Resolved Checklist

### C1. Non-Zero Channel-Token-Vault Exit

Importance: Critical.

Root cause: `exitChannel` originally unregistered a channel-token-vault identity without an
on-chain check that the registered L2 accounting balance was zero. A CLI warning existed, but direct
contract calls could bypass CLI policy.

Attack enabled: a user could exit while their channel-token-vault leaf still held value. The same
key, leaf index, and L2 address binding could later be registered by another L1 address, allowing a
valid withdraw proof against the abandoned non-zero leaf and transferring the orphaned balance.

Resolution:

- Channel-token-vault registrations now store `isZeroBalance`.
- `ChannelManager.unregisterChannelTokenVaultIdentity(...)` rejects exit unless
  `isZeroBalance == true`.
- Groth-backed deposit/withdraw paths update the flag through
  `ChannelManager.observeChannelTokenVaultStorageWrite(...)`.
- Tokamak-backed DApp execution updates the flag from proof-backed
  `LiquidBalanceStorageWriteObserved(address,bytes32)` raw logs.
- The owner whose flag is updated is derived from the observed storage key or event-decoded L2
  address, not from the transaction caller.

Evidence:

- Commit: `4c66d2e8f2998cd38ac394205f680dc7052c71a5`.
- Code: `bridge/src/BridgeStructs.sol`, `bridge/src/ChannelManager.sol`,
  `bridge/src/L1TokenVault.sol`, `packages/apps/private-state/src/L2AccountingVault.sol`.
- Regression coverage: `bridge/test/BridgeFlow.t.sol` covers non-zero exit rejection, zero-balance
  restoration after withdraw, and Tokamak observed-log flag updates.

Upgradeability note: this must be present before mainnet channels are opened. A later UUPS upgrade
could block future unsafe exits, but it could not reliably recover balances already orphaned or
stolen before the guard existed.

### C2. Mainnet Deployment Mode And Source Integrity

Importance: High.

Root cause: mainnet deployment safety rules originally lived in operational discipline rather than
hard script checks. A missing local deployment directory also could not prove that no mainnet proxy
existed elsewhere.

Attack or failure enabled: an operator could accidentally run `redeploy-proxy` on mainnet and split
bridge state into a new root address set, or deploy from a commit that users and auditors cannot
resolve on remote `main`.

Resolution:

- Mainnet deployment runs hard gates in `bridge/scripts/deploy-bridge.mjs`.
- Deployment-relevant dirty worktrees are rejected.
- Local `HEAD` must be contained in `origin/main`.
- Mainnet `redeploy-proxy` checks the shared Google Drive deployment-history folder. If any
  `chain-id-1/bridge/<timestamp>/bridge.1.json` snapshot exists, redeploy is refused and the
  operator must use upgrade mode.
- Drive lookup failures fail closed.

Evidence:

- Commits: `7547fd957c675676d4cf72854deb0bcdbe1cab0a`,
  `073009a` (`Gate mainnet redeploys on Drive deployment history`).
- Code: `bridge/scripts/deploy-bridge.mjs`.
- Drive root: `12HuHeR8vCWfkeGdjTAFKhv0FU-AG4aUJ`, overridable with
  `BRIDGE_DEPLOYMENT_DRIVE_FOLDER_ID`.

Upgradeability note: this is a pre-deployment operational gate. UUPS cannot merge two already-used
proxy state histories.

### C3. Stale DApp Metadata At Channel Creation

Importance: High.

Root cause: after DApp metadata became updateable for future channels, checking only the DApp label
was no longer enough. A DApp ID can preserve the same label while replacing storage metadata,
function metadata, preprocess hashes, event-log layouts, verifier addresses, and compatible backend
versions for future channels.

Attack or failure enabled: a channel creator using a stale manifest could unintentionally create a
channel against newer on-chain DApp policy while believing they were joining the older policy.
Because channel policy is immutable, that mistake would not be repairable in place.

Resolution:

- `DAppManager.registerDApp(...)` and `updateDAppMetadata(...)` compute a metadata digest using
  `DAPP_METADATA_DIGEST_SCHEMA`.
- The digest commits to `dappId`, immutable `labelHash`, channel-token-vault storage index, storage
  metadata root, function root, and verifier snapshot hash.
- `BridgeCore.createChannel(...)` requires `expectedDAppMetadataDigest` and reverts on mismatch.
- The private-state CLI compares manifest digest/schema/function-root values against on-chain
  `DAppInfo` before creating a channel and passes the expected digest into `createChannel(...)`.

Evidence:

- Commits: `8f6d3bc` (`Mark metadata digest channel gate resolved`), `eb7fd30`
  (`Use function root proofs for channel execution`).
- Code: `bridge/src/DAppManager.sol`, `bridge/src/BridgeCore.sol`,
  `packages/apps/private-state/cli/private-state-bridge-cli.mjs`.
- Test: `bridge/test/BridgeFlow.t.sol::testChannelCreationRejectsStaleDAppMetadataDigest`.

Upgradeability note: future channels are protected. A channel deliberately created against the wrong
current digest remains immutable and must be migrated.

### C4. DApp Metadata And Verifier Owner Update Risk

Importance: Medium.

Root cause: `BridgeCore.setGrothVerifier(...)`, `BridgeCore.setTokamakVerifier(...)`, and
`DAppManager.updateDAppMetadata(...)` are owner actions that affect future DApp snapshots and future
channels without an on-chain delay or second approval step.

Attack or failure enabled: an owner mistake or owner-key compromise can publish bad future channel
policy inputs. Users who create or join a channel against that bad current snapshot become bound to
an immutable bad channel.

Resolution and accepted control:

- Existing channels do not follow later owner updates, preserving channel-user consent.
- The CLI prints the immutable channel policy snapshot before channel creation and first join:
  DApp metadata digest, digest schema, function root, verifier addresses, and compatible backend
  versions.
- The accepted operational response to a bad future snapshot is public notice, deprecating affected
  channels, publishing corrected metadata/verifiers, and creating or joining new channels.

Evidence:

- Commit: `52815b645431490a663892bacfbef3cdd1396702`.
- Code: `packages/apps/private-state/cli/private-state-bridge-cli.mjs`.
- Docs: bridge and private-state CLI README warnings describe immutable channel policy.

Upgradeability note: future governance can be strengthened by UUPS upgrade, timelocks, or ownership
transfer. Already-created bad channels remain migration events.

### C5. Malformed DApp Metadata Through Raw Owner Calls

Importance: Low.

Root cause: the DApp admin script validates deployed artifacts and layout consistency, but direct
owner calls to `registerDApp(...)` or `updateDAppMetadata(...)` previously had weaker structural
checks.

Attack or failure enabled: a raw owner call could register zero addresses, non-contract storage
addresses, non-contract entry contracts, or zero label/preprocess values. Such metadata could create
channels that are unusable or permanently bound to wrong policy.

Resolution:

- `registerDApp(...)` rejects zero `labelHash`.
- Shared metadata storage rejects empty storage/function lists, zero storage addresses,
  non-contract storage addresses, duplicate storage addresses, missing/multiple channel-token-vault
  storage entries, zero function entry contracts, non-contract function entry contracts, zero
  preprocess hashes, duplicate function keys, duplicate preprocess hashes, and event topic counts
  above four.

Evidence:

- Commit: `5eba9ac` (`Harden DApp metadata registration validation`).
- Code: `bridge/src/DAppManager.sol`.
- Tests: regression coverage was added in `bridge/test/BridgeFlow.t.sol`.

Upgradeability note: fixed before mainnet for future registrations and updates.

### C6. BridgeCore Size Pressure From Channel Deployment

Importance: Low.

Root cause: deploying `ChannelManager` directly from `BridgeCore` kept too much deployment logic in
the root UUPS implementation and reduced bytecode margin for future hardening.

Failure enabled: the root contract could approach or exceed the EIP-170 bytecode limit, blocking
deployment or discouraging needed safety checks.

Resolution:

- `ChannelDeployer` was introduced as a thin factory.
- `BridgeCore` remains the channel policy and registry root.
- `BridgeAdminManager` and its redundant mutable tree-depth plumbing were removed.

Evidence:

- Commits: `6751ad2`, `ab5e69b`, `f6ae5b3`.
- Code: `bridge/src/BridgeCore.sol`, `bridge/src/ChannelDeployer.sol`,
  `bridge/src/ChannelManager.sol`.
- Size check after the covered changes: `BridgeCore` runtime size `10,437 bytes`, margin
  `14,139 bytes`.

Upgradeability note: resolved before mainnet deployment.

### C7. Incompatible Manager Returned By ChannelDeployer

Importance: Low.

Root cause: after moving deployment to `ChannelDeployer`, `BridgeCore` needed to prove that the
returned manager matched the policy it had just approved before binding custody authority.

Attack or failure enabled: a misconfigured or malicious deployer could return a manager with wrong
channel ID, DApp ID, leader, digest, verifier, fee, or refund schedule. If accepted, the canonical
registry would point at a bad channel manager.

Resolution:

- `BridgeCore.createChannel(...)` validates the returned manager before vault binding and registry
  write.
- The validation checks code existence and snapshot fields: `bridgeCore`, `channelId`, `dappId`,
  `leader`, channel-token-vault tree index, metadata digest schema, metadata digest, function root,
  verifier addresses, join toll, and refund schedule.

Evidence:

- Commit: `ab5e69b`.
- Code: `bridge/src/BridgeCore.sol::_validateChannelManager(...)`.
- Test: `bridge/test/BridgeFlow.t.sol::testCreateChannelRejectsIncompatibleDeployerReturn`.

Residual note: the checks do not prove bytecode identity. This is accepted as normal privileged
deployment review: the owner must record and review the deployed `ChannelDeployer` address and
source commit, just as with verifier and UUPS implementation addresses.

### C8. Per-Channel Function Metadata Deep Copy

Importance: Low.

Root cause: each channel previously deep-copied DApp function metadata into its `ChannelManager`.
That made `createChannel` expensive without adding a stronger policy commitment.

Failure enabled: this was primarily a cost and maintainability problem. Expensive channel creation
could discourage channel creation and make the policy snapshot harder to reason about.

Resolution:

- `DAppManager` validates function metadata at registration/update time and computes a Merkle
  `functionRoot`.
- `ChannelManager` stores the immutable `functionRoot`.
- `executeChannelTransaction(...)` accepts function metadata plus Merkle siblings, hashes the
  metadata, verifies it against `functionRoot`, and only then trusts preprocess hashes, entry
  contracts, function selectors, root-vector offsets, and observed-event layouts.
- Stale on-chain DApp function metadata storage was removed.

Evidence:

- Commits: `eb7fd30`, `352494c`.
- Code: `bridge/src/DAppManager.sol`, `bridge/src/ChannelManager.sol`,
  `bridge/scripts/admin-add-dapp.mjs`,
  `packages/apps/private-state/cli/private-state-bridge-cli.mjs`.
- Gas documentation: `bridge/docs/gas-assessment.md` records current `createChannel` full-path gas
  as `2,731,347`, down from the earlier `3,884,651` deep-copy design measurement.

Security note: calldata-supplied function metadata is not trusted unless it proves against the
channel root. Losing manifest proof material affects availability, not authorization.

### C9. Channel Creation Permission Model Drift

Importance: Low.

Root cause: during refactoring and gas documentation, channel creation drifted into an owner/operator
classification even though the intended design was permissionless channel creation.

Failure enabled: owner-only channel creation would centralize channel availability and contradict
the project policy that anyone can create a channel and become its leader.

Resolution:

- `BridgeCore.createChannel(...)` is permissionless.
- The `leader` parameter was removed.
- `leader` is now `msg.sender`.
- The CLI calls `createChannel(channelId, dappId, joinToll, metadataDigest)`.

Evidence:

- Commit: `73f214f`.
- Code: `bridge/src/BridgeCore.sol`, `packages/apps/private-state/cli/private-state-bridge-cli.mjs`.
- Test: `bridge/test/BridgeFlow.t.sol::testCreateChannelUsesCallerAsLeader`.
- Gas documentation classifies `BridgeCore.createChannel` as a user call.

Non-finding: a caller can create a desirable channel name first. This is expected first-come channel
name ownership, not a protocol attack. Users should resolve actual channels from `BridgeCore`, not
from names alone.

### C10. Privileged Bridge Owner Custody Authority

Importance: Critical.

Status: accepted trust assumption.

Root cause: the root bridge stack is intentionally UUPS-upgradeable and owner-controlled.
`BridgeCore`, `DAppManager`, and `L1TokenVault` still authorize upgrades through `onlyOwner`.
`BridgeCore` also lets the owner set future default Groth16 and Tokamak verifier addresses.

Attack or failure enabled: a malicious or compromised owner can deploy an implementation that
bypasses proof checks, freezes deposits or withdrawals, changes channel registry behavior, changes
future verifier defaults, or transfers custody out of the vault. This is not an unprivileged
exploit path; it is the core governance trust assumption for this launch model.

Current control:

- Channels snapshot verifier bindings and DApp metadata at creation, so verifier default changes do
  not rewrite already-created channels.
- The CLI displays immutable channel policy snapshots before channel creation and join.
- Mainnet deployment metadata must record source commits, implementation addresses, verifier
  addresses, `ChannelDeployer`, vault, and DApp registration addresses.
- The bridge owner trust assumption is accepted under the current single-operator launch model.

Evidence:

- Code: `bridge/src/BridgeCore.sol`, `bridge/src/DAppManager.sol`,
  `bridge/src/L1TokenVault.sol`.
- Code: `packages/apps/private-state/cli/private-state-bridge-cli.mjs` prints immutable policy
  snapshot values before channel creation and first join.
- Related commits: `99bc739` (`Allow DApp metadata verifier snapshots to update`) and
  `52815b6` (`Warn users about immutable channel policy`).

Maintenance note: future governance can move ownership to a timelock or multisig, separate pause
authority from upgrade authority, or freeze custody-critical upgrades after a maturation period. An
already-executed malicious owner upgrade cannot be treated as recoverable by ordinary UUPS policy.

### C11. Channel Registration Slot Exhaustion

Importance: High.

Status: mitigated by economic cost.

Root cause: channel-token-vault registration reserves a finite channel leaf index. In the earlier
free-registration design, an attacker could repeatedly join with many L1/L2 identities and consume
registration slots while paying only gas.

Attack or failure enabled: a channel could be denied to new users by exhausting available leaf
indices. This is primarily a liveness attack, but it can strand user workflow because users cannot
complete the L1-to-channel path for a saturated channel.

Mitigation:

- Joining a channel is now a paid action through `L1TokenVault.joinChannel(...)`.
- The channel creator chooses the initial join toll at `createChannel(...)`.
- `ChannelManager` records `joinTollPaid` and `joinedAt` per registration.
- Exit is allowed only after the channel-token-vault balance is zero.
- Exit refunds a time-decayed fraction of the paid join toll and frees the reserved L1, L2, storage
  key, and leaf-index bindings only after unregistering succeeds.
- The bridge tracks join tolls in `_tollTreasuryBalance`; the only current outflow path is decayed
  exit refund.

Evidence:

- Code: `bridge/src/L1TokenVault.sol::joinChannel(...)` charges the channel join toll and records it
  in treasury accounting.
- Code: `bridge/src/L1TokenVault.sol::exitChannel(...)` queries the refund quote, unregisters the
  user, and pays only the decayed refund.
- Code: `bridge/src/ChannelManager.sol::registerChannelTokenVaultIdentity(...)` records
  `joinTollPaid` and `joinedAt`.
- Code: `bridge/src/ChannelManager.sol::getExitTollRefundQuote(...)` computes the refund from the
  recorded toll paid at join time.
- Code: `bridge/src/ChannelManager.sol::setJoinToll(...)` lets the channel leader price future joins.

Residual risk: this changes registration exhaustion from a gas-only sybil griefing primitive into
an economic denial-of-service attack. A sufficiently funded attacker can still buy all available
slots, and a channel leader can raise the future join toll. Users should treat join-toll policy as
part of the channel policy they inspect before joining.

### C12. Exact-Transfer Canonical Asset Dependency

Importance: Medium.

Status: accepted external dependency.

Root cause: the bridge is designed around a canonical ERC-20 that behaves as an exact-transfer
token. Mainnet `BridgeCore.canonicalAsset()` hard-codes Tokamak Network Token for Ethereum mainnet.

Attack or failure enabled: if the canonical token pauses transfers, blacklists participants,
introduces transfer fees, rebases, or otherwise changes observed transfer deltas, deposits, joins,
claims, or refunds can revert. This is an external availability and governance dependency, not a
bridge-internal theft primitive.

Current guard:

- `L1TokenVault` checks observed token balance deltas for `fund(...)`, `joinChannel(...)`,
  `exitChannel(...)` refunds, and `claimToWallet(...)`.
- Fee-on-transfer or otherwise non-exact behavior reverts with `UnsupportedAssetTransferBehavior`.
- The canonical token's transfer behavior and governance are accepted as an explicit bridge trust
  assumption.

Evidence:

- Code: `bridge/src/BridgeCore.sol::canonicalAsset()`.
- Code: `bridge/src/L1TokenVault.sol::fund(...)`, `joinChannel(...)`, `exitChannel(...)`, and
  `claimToWallet(...)`.

Operational note: user-facing docs must not present the bridge as token-agnostic. The bridge is
safe only under the accepted exact-transfer behavior of the configured canonical asset.

### C13. Finite Storage Leaf Projection Collisions

Importance: Medium.

Status: mitigated by collision-probability reduction.

Root cause: managed storage keys are projected into a finite Merkle leaf domain. For any finite
depth below a full 256-bit key path, distinct storage keys can map to the same leaf index. This is a
bridge/state-manager storage abstraction property rather than a normal EVM mapping property.

Failure enabled: a valid DApp transition can be denied if unrelated storage keys collide in the
finite leaf domain. The impact is not direct asset theft, but an availability and usability failure:
an otherwise valid storage write can become impossible because another key already occupies the same
finite leaf.

Mitigation:

- The generated environment currently uses `MT_DEPTH = 30`, which increases the managed storage
  leaf domain to `N = 2^30`.
- Increasing tree depth reduces random leaf-collision probability exponentially in the depth.
- The CLI observes and tracks storage keys, commitments, and nullifiers so users can reconcile
  local state against bridge state. This helps detection and local accounting, but it does not
  mathematically eliminate collisions.

Collision probability model:

Let `d` be the Merkle tree depth, `N = 2^d` be the finite leaf domain size, and `t` be the channel
operating period. The relevant operational question is not only whether a fixed set of `k` keys
contains a collision after the fact. A live channel accumulates storage keys over time, so each new
storage key has a growing chance of hitting an already-occupied finite leaf.

Assume new storage keys that attempt to occupy a leaf index arrive as a Poisson process with rate
`\lambda`. If `t` is measured in minutes, the expected number of arrived storage keys is:

$$
\mu(t) = \lambda t
$$

Under the standard Poissonized occupancy model, each of the `N` leaves independently receives a
Poisson count with mean `\mu(t)/N`. No collision has occurred by time `t` exactly when every leaf
has received either zero or one arrival:

$$
\Pr[\text{no collision by } t]
= \left(e^{-\mu(t)/N}\left(1+\frac{\mu(t)}{N}\right)\right)^N
= e^{-\mu(t)}\left(1+\frac{\mu(t)}{2^d}\right)^{2^d}
$$

Therefore the channel-lifespan collision probability is:

$$
\Pr[\text{at least one collision by } t]
= 1 - e^{-\mu(t)}\left(1+\frac{\mu(t)}{2^d}\right)^{2^d}
$$

For `\mu(t) \ll 2^d`, this is approximated by the birthday exponent:

$$
\Pr[\text{at least one collision by } t]
\approx 1 - \exp\left(-\frac{\mu(t)^2}{2\cdot 2^d}\right)
$$

The graph below assumes one new storage key attempts to occupy a leaf index per minute on average, so
`\lambda = 1/minute` and `\mu(t) = 1440t` when `t` is measured in days. The current `d = 30`
setting gives a domain of `1,073,741,824` leaves. Under this assumption, the collision probability
for `d = 30` crosses roughly 50% after about 26.8 days and roughly 90% after about 48.8 days. This
is why finite leaf projection creates a channel-lifespan capacity limit rather than a one-time
static-set risk. The graph uses a logarithmic probability axis so low-probability early-lifespan
regions remain visible.

![General channel lifespan leaf collision probability by operating period and depth](../bridge/docs/assets/general_leaf_collision_probability_lifespan_days_lambda1m_d12_36_step6.svg)

Evidence:

- Code: `bridge/src/generated/TokamakEnvironment.sol` sets `MT_DEPTH = 30` and derives
  `MAX_MT_LEAVES`.
- Code: `bridge/src/ChannelManager.sol::_deriveLeafIndexFromStorageKey(...)` maps a storage key
  into the finite leaf domain.
- Code: `packages/apps/private-state/src/PrivateStateController.sol` emits observed storage keys
  for commitment and nullifier writes.
- Code: `packages/apps/private-state/cli/private-state-bridge-cli.mjs` derives and tracks
  commitment/nullifier storage keys and reconciles note state from snapshots.

Operational note: do not describe the dense finite-leaf storage projection as collision-free. If
future deployments reduce tree depth, materially increase managed storage-key volume, or target
channels with long expected operating lifetimes, this item must be re-reviewed as a capacity and
usability risk.

## Additional Checks

No new unresolved practical mainnet finding was identified after the third-pass changes.

The following were reviewed and classified as non-findings under the current model:

- Direct calls to `ChannelDeployer` can create orphan managers, but custody and channel authority
  come only from `BridgeCore.getChannel(...)` / `getChannelManager(...)`.
- `BridgeCore` storage layout changed relative to older pre-split deployments. This is acceptable
  only under the first-mainnet-deployment assumption. If a historical mainnet proxy is found, do not
  perform a blind upgrade.
- `executeChannelTransaction` gas is dominated by the Tokamak verifier call and proof calldata.
  Current CLI E2E receipts are about `827,621-861,608` gas; unit traces with the verifier mocked
  show bridge-side wrapper logic in the low tens of thousands of gas for tested paths. This is an
  optimization topic, not a security blocker.
- The private-state DApp has no owner role and keeps `PrivateStateController` and
  `L2AccountingVault` deployment-wired. Existing channel-bound DApp policy is intentionally fixed.
- The zk-L2 privacy model assumes Tokamak proof soundness and proof-backed public outputs. The
  bridge observes balance-write events for exit safety; these public outputs must not be marketed as
  hiding channel-vault participation or balance-write visibility.

## Verification Performed

Verification was performed across the implementation series covered by this audit:

- `forge test --root bridge`
  - Passed after the channel-deployer split and again after permissionless channel creation.
  - Latest covered suite size: 65 tests.
- `forge test --root bridge --gas-report`
  - Passed after permissionless channel creation.
  - Current measured `BridgeCore.createChannel` successful full-path gas: `2,731,347`.
- `forge build --root bridge --sizes`
  - Passed after the latest covered commit.
  - `BridgeCore`: `10,437 bytes`, margin `14,139 bytes`.
  - `ChannelDeployer`: `15,003 bytes`, margin `9,573 bytes`.
  - `ChannelManager`: `10,957 bytes`, margin `13,619 bytes`.
  - `DAppManager`: `12,294 bytes`, margin `12,282 bytes`.
- `forge fmt --root bridge --check`
  - Passed during the covered implementation series.
- `node --check bridge/scripts/deploy-bridge.mjs`
  - Passed after deployment-gate updates.
- `node --check bridge/scripts/admin-add-dapp.mjs`
  - Passed during the covered implementation series.
- `node --check packages/apps/private-state/cli/private-state-bridge-cli.mjs`
  - Passed after metadata-digest and permissionless channel-creation updates.
- Private-state CLI E2E with a locally packed CLI tarball and `@tokamak-zk-evm/cli@2.0.16`
  passed earlier in this branch after the function metadata proof and stale lookup cleanup. It
  covered bridge deployment, DApp registration, channel creation, joins, deposits, mint, transfer,
  redeem, channel withdrawal, exit, and bridge withdrawal. It was intentionally not rerun for the
  later permissionless-channel-creation-only change.
- Static successful-path checks passed `L2AccountingVault.creditLiquidBalance(...)` and
  `debitLiquidBalance(...)`, and passed mint/transfer functions in `PrivateStateController` before
  the checker stopped on inline assembly in redeem functions. Manual review kept the redeem family
  classified as one intended successful path per fixed-arity entrypoint.

## Deployment And Maintenance Guidance

### After Mainnet Deployment: UUPS Maintenance

- Use UUPS upgrades for root bridge maintenance, future verifier management, future DApp metadata
  policy, deployment tooling hardening, and future governance improvements.
- Do not assume a UUPS upgrade can fix an already-created channel's policy. Channel policy is
  intentionally immutable.
- Treat verifier replacement, `DAppManager` upgrade, `BridgeCore` upgrade, `L1TokenVault` upgrade,
  and `ChannelDeployer` replacement as privileged deployment events requiring source commit,
  address, artifact, and deployment metadata review.
- Keep the Google Drive deployment-history gate and remote-source gate enabled for every mainnet
  deployment.
- If a historical mainnet proxy snapshot appears, stop and re-review storage layout before any
  upgrade.

### Adding A New DApp Or Updating DApp Metadata

- Use the repository DApp registration tooling, not raw contract calls, unless the raw calldata has
  been independently reviewed.
- Verify deployed DApp bytecode, storage layout, function selectors, preprocess hashes,
  event-log layout, verifier snapshot, compatible backend versions, and generated function proofs.
- Remember that `dappId` and `labelHash` are immutable identity fields, while runtime metadata and
  verifier snapshots are replaceable only for future channels.
- Publish the DApp metadata digest, digest schema, function root, verifier addresses, and compatible
  backend versions so channel creators can compare them before creating channels.

### Channel Creator Checklist

- Resolve the DApp through `DAppManager` and compare the displayed digest, schema, function root,
  verifier addresses, and compatible backend versions against reviewed deployment metadata.
- Understand that channel creation is a final policy commitment for that channel.
- Use `BridgeCore.createChannel(...)` or the CLI path that passes the expected metadata digest.
- Treat channel names as first-come identifiers; verify the final `channelId` and registered
  manager through `BridgeCore`, not through a display name alone.

### User Checklist Before Joining A Channel

- Resolve the channel only from `BridgeCore.getChannel(...)` or `getChannelManager(...)`.
- Review the CLI's immutable policy warning before signing.
- Compare the channel's DApp metadata digest, function root, verifier snapshot, compatible backend
  versions, and channel manager address against the channel announcement.
- If a policy bug is later announced, exit only after reaching zero channel-vault balance and move
  to a corrected channel.

## Deployment Decision

All audit checklist items are resolved or accepted with explicit operational controls. No practical
unresolved mainnet finding remains in the reviewed code through `73f214f`.

Mainnet readiness still depends on executing the documented operational controls: deploy through the
repository script path, preserve remote deployment history, record all deployed addresses and source
commits, and require operators, channel creators, and users to inspect immutable channel policy
snapshots before using a channel.

# Mainnet Deployment Security Audit - Second Pass

Date: 2026-05-01
Reviewed commit: `99bc73964040c818884014e9140a0696bb90aa0e`
Branch: `bridge-mainnet-audit-second`

Scope: bridge contracts, private-state DApp contracts, DApp metadata and compatible-backend-version snapshot flow, deployment and DApp registration scripts, private-state CLI channel-creation trust boundary, and mainnet deployment readiness.

This pass focuses on the bridge update that changed DApp artifact/metadata and compatible backend version management:

- `DAppManager.registerDApp(...)` stores immutable `dappId` and `labelHash`, stores replaceable DApp runtime metadata, and snapshots the current BridgeCore verifier addresses and compatible backend versions.
- `DAppManager.updateDAppMetadata(...)` can replace storages/functions on mainnet for an existing `dappId`, while preserving `labelHash`, and snapshots the current BridgeCore verifier addresses and compatible backend versions again.
- `BridgeCore.createChannel(...)` reads the DApp verifier snapshot from `DAppManager` and passes it into a newly deployed `ChannelManager`.
- `ChannelManager` stores the verifier addresses and compatible backend version strings captured at channel creation. Existing channels do not follow later BridgeCore or DAppManager updates.

## Findings

1. High: `create-channel` only verifies `labelHash` before committing to mutable DApp metadata that has become channel-immutable.

   Status: open.

   The new DApp policy intentionally allows `DAppManager.updateDAppMetadata(...)` on mainnet. That means a DApp ID can keep the same immutable `labelHash` while its storages, functions, preprocess hashes, observed-event layouts, verifier addresses, and compatible backend versions are replaced for future channels.

   The private-state CLI's `create-channel` path resolves the DApp ID with `resolveDAppIdByLabel(...)`. That helper reads the local DApp registration manifest and checks only that the on-chain `DAppInfo` exists and that its `labelHash` matches `keccak256("private-state")`. It does not query and compare the full on-chain `DAppManager` metadata through `getManagedStorageAddresses`, `getRegisteredFunctions`, `getFunctionMetadata`, `getFunctionEventLogs`, and `getDAppVerifierSnapshot` before sending `BridgeCore.createChannel(...)`.

   This was less dangerous when DApp metadata was permanently fixed at registration. After this update, `labelHash` is no longer enough to prove that the DApp ID currently points at the same metadata bundle the local operator intends to freeze into a new channel.

   Impact: an operator can create a mainnet channel against stale, unintended, or maliciously replaced DApp metadata while the label still matches. Once created, that `ChannelManager` has no upgrade path and keeps the captured metadata and verifier snapshot. A later `DAppManager.updateDAppMetadata(...)`, `BridgeCore.setGrothVerifier(...)`, `BridgeCore.setTokamakVerifier(...)`, or UUPS upgrade only affects future channels. The affected channel must be abandoned or migrated.

   UUPS upgradeability classification: not repairable in place for already-created channels. Future prevention is possible through CLI/script changes and possibly through UUPS changes to add stronger metadata attestation APIs, but a bad channel snapshot is intentionally immutable.

   Required pre-mainnet action: before mainnet channel creation, add a hard preflight to the `create-channel` path that compares the on-chain DApp metadata and verifier snapshot against the exact local DApp registration manifest and installed backend versions. The comparison should fail before `createChannel` is sent if any storage address, function selector, preprocess hash, instance layout, event-log metadata, verifier address, or compatible backend version differs.

2. High: missing local mainnet deployment metadata can still make `redeploy-proxy` unsafe if a mainnet proxy exists outside this checkout.

   Status: open operational blocker unless this is the first mainnet bridge deployment.

   `bridge/scripts/deploy-bridge.mjs` rejects `redeploy-proxy` on mainnet only when a local `deployment/chain-id-1/bridge/<timestamp>/bridge.1.json` snapshot exists. This checkout currently has no local `deployment/chain-id-1` bridge metadata. Therefore the script cannot prove whether no bridge proxy exists on mainnet, or whether the local repository is missing historical mainnet metadata.

   Impact: if any mainnet bridge proxy has already been deployed outside the local metadata set, a mistaken `redeploy-proxy` would create a second root bridge state. UUPS upgrades cannot merge two proxy state histories after users or channels begin using both address sets.

   UUPS upgradeability classification: not repairable by UUPS after a split deployment is used. UUPS can upgrade one proxy's implementation, but it cannot merge state held in different proxy addresses or reconcile channels/users that interacted with different roots.

   Required pre-mainnet action: before any mainnet broadcast, explicitly prove that this is the first mainnet bridge deployment, or reconstruct/import the existing mainnet deployment metadata and use `--mode upgrade`. Do not rely only on absence of local `deployment/chain-id-1` files.

3. Medium: the reviewed commit is not contained in `origin/main`, so the current checkout is not deployment-ready under the repository's own mainnet source-integrity rule.

   Status: open deployment blocker for this exact checkout.

   `git merge-base --is-ancestor HEAD origin/main` returned non-zero for reviewed commit `99bc73964040c818884014e9140a0696bb90aa0e`. The mainnet deployment script requires the exact local `HEAD` to be contained in `origin/main` before it will continue.

   Impact: source links in deployment metadata would not be stable for users and auditors if this exact commit were deployed before it is pushed/merged to remote main. The current deployment tooling should block this condition, so the immediate risk is operational rather than an on-chain bug.

   UUPS upgradeability classification: not a UUPS issue. Fix by merging/pushing the exact deployment commit to `origin/main` before mainnet deployment.

4. Medium: DApp metadata and verifier updates are immediate owner actions with no on-chain delay or second approval step.

   Status: accepted trust-boundary risk unless governance is strengthened before mainnet.

   `BridgeCore.setGrothVerifier(...)`, `BridgeCore.setTokamakVerifier(...)`, and `DAppManager.updateDAppMetadata(...)` are all owner-only and take effect for the next DApp metadata snapshot or next channel creation without an on-chain timelock, proposal delay, or two-party acceptance. This is consistent with the current UUPS owner trust model, but the new metadata update policy makes the owner path more operationally sensitive: an accidental or compromised owner action can create bad future channel snapshots while preserving the same DApp label.

   Existing channels remain protected from later policy mutation, which is the intended channel-consent model. The tradeoff is that every future channel created after a bad owner action can become permanently bound to the bad snapshot.

   UUPS upgradeability classification: partially upgradeable for future operations. Ownership can be transferred and UUPS implementations can add stronger governance, timelocks, or staged updates. They cannot repair channels already created with a bad snapshot.

   Required pre-mainnet action: deploy with `BRIDGE_OWNER` set to the intended mainnet governance account, preferably a multisig or timelock-controlled account. Treat any EOA owner as a launch blocker unless explicitly accepted. Publish the exact verifier and DApp metadata snapshot that governance intends to make available for first mainnet channels.

5. Low: direct owner calls to `registerDApp` or `updateDAppMetadata` can still register structurally bad metadata that the admin script would normally filter out.

   Status: open defense-in-depth issue.

   The contract validates duplicate storage addresses, duplicate functions, duplicate preprocess hashes, non-empty storage/function lists, event topic count, and exactly one channel-token-vault storage. It does not reject a zero `storageAddr`, a zero `entryContract`, a zero `labelHash`, or non-contract target addresses. The `admin-add-dapp.mjs` flow derives metadata from deployed artifacts and checks target deployment/storage-layout consistency, so the normal path is much safer than raw contract calls. However, the on-chain API itself still trusts the owner to avoid malformed metadata.

   Impact: a malformed DApp registration/update can break future channel creation or create channels whose execution policy is unusable. As with Finding 1, already-created channels cannot be repaired in place.

   UUPS upgradeability classification: fixable for future registrations/updates through a DAppManager UUPS implementation that adds stricter metadata validation. Existing bad channels remain immutable and require migration.

   Recommended action: add on-chain defense-in-depth checks for zero addresses and, where appropriate, code existence for storage and entry contracts. Keep the admin script as the canonical registration path even after contract-level checks are added.

## Prior Findings Rechecked

### Non-zero Balance Exit Guard

The previous critical `exitChannel` issue remains resolved in the reviewed code. `ChannelManager.unregisterChannelTokenVaultIdentity(...)` rejects exit when `registration.isZeroBalance` is false. The flag is initialized to true at registration and updated by both supported proof-backed balance-write observation paths:

- Groth-backed `L1TokenVault.depositToChannelVault(...)` and `withdrawFromChannelVault(...)` call `ChannelManager.observeChannelTokenVaultStorageWrite(...)` with the observed channel-token-vault storage address, key, and updated value.
- Tokamak-backed `ChannelManager.executeChannelTransaction(...)` detects raw logs whose topic is `LiquidBalanceStorageWriteObserved(address,bytes32)`, decodes the L2 address and value from log data, and resolves the owner from the decoded L2 address.

The owner is derived from the observed storage key or event-decoded L2 address, not from the L1 transaction caller.

Upgradeability classification: the guard is present before mainnet. If this guard were missing after users joined mainnet channels, later UUPS upgrades could prevent future exits but could not reliably recover balances already orphaned or stolen through a prior non-zero exit.

### Immutable Channel Policy

The immutable `ChannelManager` policy remains intentional. Each channel captures DApp metadata, verifier addresses, compatible backend versions, managed storage vector, function metadata, join-fee refund schedule, and `aPubBlockHash` at creation time. This protects existing users from unilateral policy changes, but it means channel-level mistakes are migration events, not UUPS patch events.

Upgradeability classification: root bridge components are UUPS-upgradeable for future channels and future root behavior. Deployed `ChannelManager` instances are not UUPS-upgradeable by design.

### DApp Implementation Immutability

`PrivateStateController` and `L2AccountingVault` remain immutable app contracts with deployment-time wiring and no owner role. A new DApp deployment plus `DAppManager.updateDAppMetadata(...)` can affect future channels for the same `dappId`, but existing channels keep their captured metadata and storage vector.

Upgradeability classification: future DApp metadata can be updated; existing channel-bound DApp policy cannot be changed in place.

## Other Security Checks

### zk-L2 Privacy Assumption

The private-state DApp continues to follow the zk-L2 model: raw user transaction contents are private to the caller, while L1 observers see proof-backed public outputs and accepted state transitions. The bridge does not add L1 calldata-hiding logic, which is appropriate for this execution model.

The bridge now intentionally observes `LiquidBalanceStorageWriteObserved(address,bytes32)` logs to maintain the exit-safety flag. This event exposes the L2 address and written balance value as part of proof-backed public output. That exposure is consistent with the current channel-vault registration model, which already emits L1/L2/channel-token-vault identity bindings at join time. It should not be described to users as hiding L1 participation or channel-vault balance changes.

### Bridge-Managed Custody

The custody split remains structurally sound. L1 canonical asset custody lives in `L1TokenVault`. The private-state DApp keeps L2 accounting state only. Users cannot directly call the L2 accounting vault because `L2AccountingVault.creditLiquidBalance(...)` and `debitLiquidBalance(...)` are restricted to the immutable `PrivateStateController`.

### L2 Accounting Bounds

`L2AccountingVault.creditLiquidBalance(...)` rejects zero addresses, zero amounts, current or incoming values at or above the BLS12-381 scalar field order, and additions that would exceed `field order - 1`. `debitLiquidBalance(...)` rejects zero addresses, zero amounts, and insufficient balances. The bridge-side Groth path also rejects L2 current and updated values at or above the BLS12-381 scalar field modulus.

### DApp Entrypoint Shape

The private-state DApp still uses fixed-arity entrypoints for mint, transfer, and redeem rather than a generic branchy dispatcher. The successful-path checker passed all mint and transfer functions and both L2 accounting functions. It stopped on inline assembly in `redeemNotes1`, which is a parser limitation. Manual review of the redeem family shows one intended successful path per entrypoint: reject zero receiver, prepare each spendable input note, consume each nullifier, sum values, and credit the receiver's L2 accounting balance.

### Function Bytecode and Placement Discipline

The DApp keeps hot user-facing functions mostly fixed-shape and unrolled. Helper calls for commitments, nullifiers, encrypted-note salts, and mapping storage keys appear to support correctness and placement discipline rather than optional success modes. No new DApp bytecode or placement regression was introduced by the bridge DAM/CBV update.

### Storage Layout and Split

The DApp continues to split note/nullifier state and liquid accounting state across `PrivateStateController` and `L2AccountingVault`. That split remains appropriate because the accounting balance domain and note/nullifier domains have different mutation patterns.

### Admin and Ownership

The private-state DApp has no owner role. The bridge root contracts remain owner-controlled UUPS proxies. Mainnet safety depends on the owner account and the operational process around verifier rotation, DApp metadata updates, bridge upgrades, and channel creation.

### DApp Registration Artifacts

`admin-add-dapp.mjs` now uses `updateDAppMetadata(...)` instead of deleting and re-registering an existing DApp ID. It also refuses to update when the existing on-chain `labelHash` differs from the local manifest label. This matches the new policy that `dappId` and `labelHash` are immutable while the rest of DAM and CBV are replaceable for future channels.

### Synthesizer Compatibility Deliverables

The repository still has Synthesizer example inputs under `packages/apps/private-state/examples/synthesizer/privateState/`, but no per-function scripts under `packages/apps/private-state/scripts/synthesizer-compat-test`. Mainnet registration should rely on freshly regenerated artifacts for the exact deployed DApp contracts and exact backend versions, not on stale example outputs.

## Verification Performed

- `forge test --root bridge`
  - Passed 57 tests across BridgeFlow, Groth16Verifier, and TokamakVerifier.
- `node --check bridge/scripts/deploy-bridge.mjs`
  - Passed syntax check.
- `node --check bridge/scripts/admin-add-dapp.mjs`
  - Passed syntax check.
- `python3 .codex/skills/app-dapp-zk-l2/scripts/check_unique_success_paths.py packages/apps/private-state/src/L2AccountingVault.sol --contract L2AccountingVault`
  - Passed `creditLiquidBalance` and `debitLiquidBalance`.
- `python3 .codex/skills/app-dapp-zk-l2/scripts/check_unique_success_paths.py packages/apps/private-state/src/PrivateStateController.sol --contract PrivateStateController`
  - Passed mint and transfer functions before stopping on inline assembly in `redeemNotes1`.
- Local private-state CLI E2E was run against the same reviewed commit with a locally packed CLI tarball before this document was written.
  - Passed the full bridge/private-state flow, including deployment, DApp registration/update path, channel creation, join/deposit, mint, transfer, redeem, withdraw, exit, and bridge withdrawal.

## Deployment Decision

Do not treat the current checkout as ready for mainnet broadcast yet.

The reviewed Solidity and bridge tests pass, and no new critical protocol bug was found in the DAM/CBV snapshot implementation. However, mainnet launch should wait until the open deployment/tooling findings are closed or explicitly accepted:

- Add a pre-`createChannel` DAM/CBV comparison in the CLI or an equivalent operational gate.
- Prove that no previous mainnet bridge proxy exists, or import/reconstruct mainnet metadata and use upgrade mode.
- Merge/push the exact deployment commit to `origin/main`.
- Confirm the bridge owner is the intended mainnet governance account.

The most important non-upgradeable boundary is unchanged: once a channel is created, its verifier bindings, DApp metadata, compatible backend versions, storage vector, and function layout are final for that channel.

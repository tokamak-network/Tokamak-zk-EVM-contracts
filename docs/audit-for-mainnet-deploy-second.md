# Mainnet Deployment Security Audit - Second Pass

Date: 2026-05-01
Reviewed code through: `10e9278`
Gas-cost documentation updated through: `aacb524`
Branch: `bridge-mainnet-audit-second`

Scope: bridge contracts, private-state DApp contracts, DApp metadata and compatible-backend-version snapshot flow, deployment and DApp registration scripts, private-state CLI channel-creation trust boundary, mainnet gas-cost documentation, and mainnet deployment readiness.

This pass focuses on the bridge update that changed DApp artifact/metadata and compatible backend version management:

- `DAppManager.registerDApp(...)` stores immutable `dappId` and `labelHash`, stores replaceable DApp runtime metadata, and snapshots the current BridgeCore verifier addresses and compatible backend versions.
- `DAppManager.updateDAppMetadata(...)` can replace storages/functions on mainnet for an existing `dappId`, while preserving `labelHash`, and snapshots the current BridgeCore verifier addresses and compatible backend versions again.
- `DAppManager.registerDApp(...)` and `updateDAppMetadata(...)` compute a metadata digest over the immutable DApp identity, current runtime metadata roots, and verifier snapshot.
- `BridgeCore.createChannel(...)` requires the caller to provide the expected DApp metadata digest, rejects stale or unexpected digests, reads the DApp verifier snapshot from `DAppManager`, and passes the captured snapshot into a newly deployed `ChannelManager`.
- `ChannelManager` stores the verifier addresses and compatible backend version strings captured at channel creation. Existing channels do not follow later BridgeCore or DAppManager updates.

## Findings

1. High: `create-channel` only verified `labelHash` before committing to mutable DApp metadata that has become channel-immutable.

   Status: resolved before mainnet.

   The new DApp policy intentionally allows `DAppManager.updateDAppMetadata(...)` on mainnet. That means a DApp ID can keep the same immutable `labelHash` while its storages, functions, preprocess hashes, observed-event layouts, verifier addresses, and compatible backend versions are replaced for future channels.

   Original issue: the private-state CLI's `create-channel` path resolved the DApp ID with `resolveDAppIdByLabel(...)` and only checked that the on-chain `DAppInfo` existed and that its `labelHash` matched `keccak256("private-state")`. That was no longer enough once DApp metadata became replaceable for future channels.

   Resolution: `DAppManager` now computes and stores `metadataDigest` with schema `DAPP_METADATA_DIGEST_SCHEMA` on both `registerDApp(...)` and `updateDAppMetadata(...)`. The digest commits to the DApp ID, immutable `labelHash`, channel-token-vault storage index, storage metadata root, function metadata root, and verifier snapshot hash. The function metadata root covers entry contracts, selectors, preprocess hashes, instance layout offsets, and event-log metadata. The verifier snapshot hash covers Groth16 verifier address/version and Tokamak verifier address/version.

   `BridgeCore.createChannel(...)` now takes `expectedDAppMetadataDigest` and reverts with `DAppMetadataDigestMismatch` if the current on-chain digest differs. The private-state CLI reads `registration.metadataDigest` and `registration.metadataDigestSchema` from the local DApp registration manifest, verifies that the on-chain `DAppInfo` has the same digest and schema, and passes that digest into `createChannel(...)`. This closes the stale-label channel-creation path for the normal CLI flow and for direct owner calls that use an independently reviewed expected digest.

   Impact after resolution: a DApp metadata update that preserves the same label cannot silently affect a channel creation that is using a stale manifest digest; the transaction fails before a channel is deployed. A bad channel snapshot remains non-repairable if an owner intentionally or negligently approves the wrong digest, but that is now an explicit operator/governance failure rather than an implicit label-only mismatch.

   UUPS upgradeability classification: prevention is implemented before mainnet. If a channel is still created with an explicitly wrong but current digest, that individual channel remains intentionally immutable and cannot be repaired in place by a later UUPS upgrade.

   Verification: `forge test --root bridge --match-test testChannelCreationRejectsStaleDAppMetadataDigest` passed. `node --check packages/apps/private-state/cli/private-state-bridge-cli.mjs` passed.

2. High: missing local mainnet deployment metadata could make `redeploy-proxy` unsafe if a mainnet proxy exists outside this checkout.

   Status: resolved before mainnet by moving the `redeploy-proxy` existence check to Google Drive deployment history.

   Original issue: `bridge/scripts/deploy-bridge.mjs` rejected `redeploy-proxy` on mainnet only when a local `deployment/chain-id-1/bridge/<timestamp>/bridge.1.json` snapshot existed. This checkout currently has no local `deployment/chain-id-1` bridge metadata, so local files alone could not prove whether no bridge proxy exists on mainnet or whether this checkout was missing historical mainnet metadata.

   Resolution: mainnet `redeploy-proxy` now checks the Google Drive deployment-history folder before deployment. The configured default folder is `https://drive.google.com/drive/folders/12HuHeR8vCWfkeGdjTAFKhv0FU-AG4aUJ`, with `BRIDGE_DEPLOYMENT_DRIVE_FOLDER_ID` available as an explicit override. The bridge artifact upload script uses the same folder source. The deploy script looks for Drive snapshots under `chain-id-1/bridge/<timestamp>/bridge.1.json`. If any snapshot exists, it refuses `redeploy-proxy` and instructs the operator to use `--mode upgrade`. If the Drive path has no bridge snapshots, it treats that as the first mainnet bridge deployment. If the Drive lookup cannot be performed, the script fails rather than falling back to local metadata.

   The user-provided current launch assumption is that mainnet has not been deployed yet, so the expected Drive state before first deployment is no `chain-id-1/bridge` bridge snapshot.

   Impact after resolution: the deployment script no longer treats absence of local `deployment/chain-id-1` files as proof of first deployment. A split root bridge state can still occur if an operator bypasses the script or uses the wrong Drive folder, but the repository mainnet deployment path now gates the dangerous mode on the shared remote deployment record.

   UUPS upgradeability classification: prevention is implemented before mainnet. If a split deployment were still created outside this gate and used by users, UUPS could not merge the two proxy state histories.

3. Medium: DApp metadata and verifier updates are immediate owner actions with no on-chain delay or second approval step.

   Status: accepted operational risk with CLI and documentation mitigation.

   `BridgeCore.setGrothVerifier(...)`, `BridgeCore.setTokamakVerifier(...)`, and `DAppManager.updateDAppMetadata(...)` are all owner-only and take effect for the next DApp metadata snapshot or next channel creation without an on-chain timelock, proposal delay, or two-party acceptance. This is consistent with the current UUPS owner trust model, but the new metadata update policy makes the owner path more operationally sensitive: an accidental or compromised owner action can create bad future channel snapshots while preserving the same DApp label.

   Existing channels remain protected from later policy mutation, which is the intended channel-consent model. The tradeoff is that every future channel created after a bad owner action can become permanently bound to the bad snapshot.

   Operator decision: this risk is accepted as an operational governance risk for mainnet. The intended owner model is still a single operator-controlled key path, whether that key is held directly or behind a multisig. If a bad snapshot is published and a user creates or joins a channel before the mistake is noticed, the intended mitigation is public notice, deprecating the affected channel, publishing corrected DApp metadata or verifier bindings, and having users create or join a new channel. Users can always create a fresh channel with the corrected snapshot.

   UUPS upgradeability classification: partially upgradeable for future operations. Ownership can be transferred and UUPS implementations can add stronger governance, timelocks, or staged updates. They cannot repair channels already created with a bad snapshot.

   Mitigation implemented before mainnet: the private-state CLI prints the DApp metadata digest, digest schema, Groth16 verifier address, Groth16 compatible backend version, Tokamak verifier address, and Tokamak compatible backend version before `create-channel` and before a first `join-channel` registration. The CLI and DApp protocol documentation now warn users and operators that signing means accepting that exact immutable channel policy. If any displayed value is unexpected or unreviewed, the user should not create or join the channel.

4. Low: direct owner calls to `registerDApp` or `updateDAppMetadata` can still register structurally bad metadata that the admin script would normally filter out.

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

### Mainnet Gas-Cost Documentation

`bridge/docs/gas-prices.md` has been added as an operational mainnet-readiness document. It records measured gas usage for owner/operator calls and user calls, separates actual CLI E2E receipt measurements from Forge gas-report measurements, and converts measured gas usage to USD using ETH/USD 2,267.90.

The call cost tables intentionally use the six-month historical `Typical effective gas price` baselines from the embedded Ethereum mainnet fee-history chart rather than the single timestamped MetaMask fee tiers:

- `Typical effective gas price` Block p50: 0.106 gwei.
- `Typical effective gas price` Block p90: 0.886 gwei.

The historical distribution covers 1,295,600 Ethereum mainnet blocks from 2025-11-01 to 2026-05-01, using `eth_feeHistory` reward percentiles 10, 50, and 90. The SVG chart focuses both graphs on the 0-3 gwei display window. Raw RPC response chunks are stored as `bridge/docs/assets/ethereum-gas-fee-history-2025-11-01-to-2026-05-01.eth-fee-history.raw.jsonl.gz`, so the chart and summary can be reproduced from repository-local source data.

This is not a protocol security issue, but it is relevant for launch readiness: users and operators can now see expected transaction costs under historical Block p50 and Block p90 typical-fee assumptions. The document should not be treated as a gas-price guarantee; it is a historical distribution and timestamped conversion snapshot.

## Verification Performed

- `forge test --root bridge`
  - Passed 58 tests across BridgeFlow, Groth16Verifier, and TokamakVerifier.
- `node --check bridge/scripts/deploy-bridge.mjs`
  - Passed syntax check after the mainnet Google Drive deployment-history check was added.
- `node --check scripts/drive/lib/google-drive-upload.mjs`
  - Passed syntax check after adding read-only Drive folder listing exports.
- `node --check bridge/scripts/upload-bridge-artifacts.mjs`
  - Passed syntax check after aligning bridge artifact upload with the bridge deployment Drive folder.
- `node --check bridge/scripts/admin-add-dapp.mjs`
  - Passed syntax check.
- `node --check packages/apps/private-state/cli/private-state-bridge-cli.mjs`
  - Passed syntax check after the `create-channel` metadata-digest preflight was added.
- `forge test --root bridge --match-test testChannelCreationRejectsStaleDAppMetadataDigest`
  - Passed the stale-DApp-metadata rejection test for `BridgeCore.createChannel(...)`.
- `python3 .codex/skills/app-dapp-zk-l2/scripts/check_unique_success_paths.py packages/apps/private-state/src/L2AccountingVault.sol --contract L2AccountingVault`
  - Passed `creditLiquidBalance` and `debitLiquidBalance`.
- `python3 .codex/skills/app-dapp-zk-l2/scripts/check_unique_success_paths.py packages/apps/private-state/src/PrivateStateController.sol --contract PrivateStateController`
  - Passed mint and transfer functions before stopping on inline assembly in `redeemNotes1`.
- Local private-state CLI E2E was run during this audit pass with a locally packed CLI tarball before the later gas-documentation updates.
  - Passed the full bridge/private-state flow, including deployment, DApp registration/update path, channel creation, join/deposit, mint, transfer, redeem, withdraw, exit, and bridge withdrawal.
- `bridge/docs/gas-prices.md` was updated after the security review with measured call gas, historical Ethereum mainnet fee distribution, and USD conversions.
  - Raw `eth_feeHistory` data was stored as gzip JSONL under `bridge/docs/assets`.
  - `gzip -t bridge/docs/assets/ethereum-gas-fee-history-2025-11-01-to-2026-05-01.eth-fee-history.raw.jsonl.gz` passed.
  - `xmllint --noout bridge/docs/assets/ethereum-gas-fee-distribution-2025-11-01-to-2026-05-01.svg` passed.
  - `git diff --check` passed for the gas-price documentation updates.

## Deployment Decision

Do not treat the current checkout as ready for mainnet broadcast yet.

The reviewed Solidity and bridge tests pass, and no new critical protocol bug was found in the DAM/CBV snapshot implementation. Finding 1 is resolved by the DApp metadata digest preflight and `BridgeCore.createChannel(...)` digest check. Finding 2 is resolved by checking Google Drive deployment history before allowing mainnet `redeploy-proxy`. However, mainnet launch should wait until the remaining governance assumptions are closed or explicitly accepted:

- Confirm the bridge owner is the intended mainnet governance account.

Gas-cost documentation is now available in `bridge/docs/gas-prices.md`; it improves operator/user cost visibility but does not close the remaining launch conditions above.

The most important non-upgradeable boundary is unchanged: once a channel is created, its verifier bindings, DApp metadata, compatible backend versions, storage vector, and function layout are final for that channel.

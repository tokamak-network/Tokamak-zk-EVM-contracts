# Mainnet Deployment Security Audit

Date: 2026-04-30
Reviewed commit: `d43fabaafa9a7ac67ebf22e1e2495e45bdc69bf8`
Current resolution recheck: 2026-05-02, through `73f214f` (`Make channel creation permissionless`)
Resolution update commits:

- `4c66d2e8f2998cd38ac394205f680dc7052c71a5`
- `7547fd957c675676d4cf72854deb0bcdbe1cab0a`
- `52815b645431490a663892bacfbef3cdd1396702`
- `eb7fd30` (`Use function root proofs for channel execution`)
- `352494c` (`Remove stale DApp function metadata storage`)
- `73f214f` (`Make channel creation permissionless`)

Scope: bridge contracts, private-state DApp contracts, deployment scripts, registration flow, CLI trust boundaries, and deployment metadata gates relevant to mainnet deployment.

## Findings

1. Critical: `exitChannel` can release an occupied channel-token-vault slot while the L2 accounting balance is still non-zero.

   Status: resolved in `4c66d2e8f2998cd38ac394205f680dc7052c71a5`.

   `L1TokenVault.exitChannel(...)` unregisters the caller through `ChannelManager.unregisterChannelTokenVaultIdentity(...)` without verifying that the registered `channelTokenVaultKey` currently has a zero balance in the accepted channel root. After unregistering, the same `channelTokenVaultKey`, leaf index, and L2 address binding become available for registration by another L1 address. A new registrant can then submit a valid withdraw proof against the existing non-zero leaf value and move the orphaned channel balance into their own L1 available balance.

   At the original review commit, the repository had a test that accepted this behavior: `bridge/test/BridgeFlow.t.sol::testExitChannelAllowsNonZeroChannelBalance`. The CLI had a zero-balance guard for `exit-channel`, but that guard was local UX logic and could be bypassed with `--force`; it was not an on-chain security boundary.

   Resolution details: channel-token-vault registrations now include an `isZeroBalance` flag initialized to `true` when the identity is registered. `ChannelManager.unregisterChannelTokenVaultIdentity(...)` rejects exit with `ChannelTokenVaultBalanceNotZero` unless the flag is true. The flag is updated from proof-backed observed storage writes, not from the transaction caller.

   The Groth16 deposit and withdraw path updates the flag before emitting `L1TokenVault.StorageWriteObserved(address,uint256,uint256)`. `L1TokenVault` passes the same `storageAddr`, `storageKey`, and `value` to `ChannelManager.observeChannelTokenVaultStorageWrite(...)`; `ChannelManager` validates that `storageAddr` is the registered channel-token-vault storage address, resolves the owner from the observed `storageKey`, and sets `isZeroBalance` from `value == 0`.

   The Tokamak zk-L2 DApp execution path updates the same flag when `executeChannelTransaction` processes a raw observed log whose topic is `LiquidBalanceStorageWriteObserved(address,bytes32)`. `ChannelManager` decodes the L2 address and written value from the log data, resolves the registered owner from the decoded L2 address, and sets `isZeroBalance` from `value == 0`. The owner is therefore derived from event contents in both supported observation paths; the transaction caller is not used to select the owner.

   Unknown or inconsistent observed writes now fail closed. The StorageWriteObserved path rejects an unexpected storage address or unregistered storage key. The LiquidBalanceStorageWriteObserved path rejects malformed event data or an unregistered L2 address. This is appropriate because these writes are part of proof-backed bridge state transitions; accepting an unregistered observed owner would make the exit-safety flag ambiguous.

   Upgradeability classification: this issue was fixable before mainnet deployment by changing the first deployed UUPS implementation set. Already executed non-zero exits, key reuse, or stolen balances would not have been reliably recoverable by a later upgrade, so this fix must be present before any mainnet channel is opened.

   Mainnet recommendation: resolved for the reviewed implementation update. Before deployment, keep the new regression coverage in the release gate and verify that deployed bytecode contains the `isZeroBalance` registration field, both observed-write update paths, and the `ChannelTokenVaultBalanceNotZero` exit guard.

   Current-code evidence:

   - `bridge/src/BridgeStructs.sol` defines `ChannelTokenVaultRegistration.isZeroBalance`.
   - `bridge/src/ChannelManager.sol` initializes the flag to `true` in `registerChannelTokenVaultIdentity(...)`, rejects exit in `unregisterChannelTokenVaultIdentity(...)` when the flag is false, updates the flag from `observeChannelTokenVaultStorageWrite(...)`, and updates it from proof-backed `LiquidBalanceStorageWriteObserved(address,bytes32)` raw logs during `executeChannelTransaction(...)`.
   - `bridge/src/L1TokenVault.sol` routes Groth-backed `depositToChannelVault(...)` and `withdrawFromChannelVault(...)` storage observations into `ChannelManager.observeChannelTokenVaultStorageWrite(...)`.
   - `packages/apps/private-state/src/L2AccountingVault.sol` emits `LiquidBalanceStorageWriteObserved(address,bytes32)` on liquid-balance writes, which is the event consumed by the Tokamak execution path.
   - Regression coverage was added in `bridge/test/BridgeFlow.t.sol` by commit `4c66d2e8f2998cd38ac394205f680dc7052c71a5`, including non-zero exit rejection and observed-write flag updates.

2. High: mainnet deployment safety policies are not enforced inside the deployment script.

   Status: resolved in `7547fd957c675676d4cf72854deb0bcdbe1cab0a`.

   The deployment discipline requires that mainnet use `upgrade` mode once a proxy exists, that exact local `HEAD` already be present on remote `main`, and that deployment-relevant Solidity changes be compared against the previous deployment metadata. These rules currently live in operational instructions, not as hard checks in `bridge/scripts/deploy-bridge.mjs`.

   A mistaken `redeploy-proxy` on mainnet can create new root bridge addresses and split state from existing deployments. A deployment from a commit that is not on remote `main` can also produce metadata whose source links are not resolvable by users or auditors.

   Resolution details: `bridge/scripts/deploy-bridge.mjs` now runs mainnet-only hard gates before broadcasting. If local mainnet bridge deployment metadata already exists, `--mode redeploy-proxy` is rejected and the operator is directed to use `--mode upgrade`. The script also blocks mainnet deployment from a dirty deployment-relevant worktree, including bridge Solidity sources, generated verifier Solidity, bridge deployment scripts, deployment metadata helpers, artifact upload helpers, and Groth16 deployment helpers.

   The script fetches `origin/main` and requires the exact local `HEAD` commit to be contained in that remote branch before mainnet deployment can continue. When previous bridge deployment metadata exists, the script reads `.sourceCode.repository.commit`, verifies that commit is locally resolvable, and compares it to current `HEAD` over `bridge/src/**/*.sol`. If no bridge Solidity source changed, the script refuses to deploy a new mainnet bridge implementation.

   Upgradeability classification: this issue was fixed at the deployment tooling layer before mainnet deployment. If a mainnet proxy redeployment had already happened and users or channels started using the wrong address set, normal UUPS upgrades would not merge the split state histories.

   Mainnet recommendation: resolved for the bridge deployment entrypoint. Keep mainnet bridge deployment routed through `node bridge/scripts/deploy-bridge.mjs`; bypassing it with direct `forge script` commands would bypass these operational hard gates.

   Current-code evidence:

   - `bridge/scripts/deploy-bridge.mjs` keeps the deployment-relevant dirty-worktree gate for mainnet bridge Solidity, deployment scripts, Drive helpers, deployment metadata helpers, and Groth16 helper code.
   - The same script fetches `origin/main` and refuses mainnet deployment unless local `HEAD` is contained in remote `main`.
   - Commit `073009a` moved mainnet `redeploy-proxy` detection from local files to the shared Google Drive deployment-history folder, so absence of local `deployment/chain-id-1` files is no longer treated as proof of first deployment.
   - The configured mainnet Drive folder is `12HuHeR8vCWfkeGdjTAFKhv0FU-AG4aUJ`, with `BRIDGE_DEPLOYMENT_DRIVE_FOLDER_ID` available as an explicit override.

3. Accepted design constraint: deployed `ChannelManager` instances intentionally freeze channel policy at channel creation.

   Status: accepted immutable-channel-policy tradeoff. Mitigation implemented in `52815b645431490a663892bacfbef3cdd1396702` through user/operator disclosure in CLI and README documentation.

   `BridgeCore`, `DAppManager`, and `L1TokenVault` are UUPS-upgradeable. Per-channel `ChannelManager` instances are regular contracts created by `BridgeCore.createChannel(...)`. Each `ChannelManager` stores immutable verifier addresses, immutable channel metadata, a fixed managed-storage vector, an immutable DApp function root, and fixed refund schedule parameters.

   Updating `BridgeCore.setGrothVerifier(...)`, `BridgeCore.setTokamakVerifier(...)`, or DApp registration metadata only affects future channel creation. Existing channels keep their originally captured verifier and function metadata.

   Design rationale: this immutability is intentional. A channel's verifier bindings, DApp execution grammar, managed storage vector, and refund schedule are part of the operating policy users implicitly accept when they join that channel. Changing those policy fields in place during active channel use, without renewed user consent, is not acceptable under the intended channel model.

   Tradeoff: the design prevents unilateral policy changes for existing channel users, but it also means bugs in an already deployed channel's verifier binding, function layout, managed storage vector, refund schedule, or accepted execution grammar require channel migration. They are not repairable in place by upgrading `BridgeCore`.

   Mitigation: channel creation and channel joining must warn operators and users that they are committing to an immutable channel policy. The CLI and README now describe that the expected response to a later policy or metadata bug is creating or joining a new channel, not mutating the existing channel.

   Mainnet recommendation: accepted with explicit disclosure. Create mainnet channels only after verifier versions, Groth16 setup artifacts, `aPubUser` offsets, function selectors, and managed storage addresses have been independently checked against the exact DApp deployment, and make sure users see the immutable-policy warning before joining.

   Current-code evidence:

   - `bridge/src/BridgeCore.sol` creates a new `ChannelManager` for each channel and stores the returned manager in the channel registry. Channel creation is permissionless as of `73f214f`; the caller becomes the channel leader.
   - `BridgeCore.createChannel(...)` requires an `expectedDAppMetadataDigest`, snapshots the current registered DApp verifier data, passes the DApp metadata digest and function root into the channel, validates the returned manager snapshot, and then binds the bridge token vault.
   - `bridge/src/ChannelManager.sol` stores channel policy fields as constructor-set immutables or creation-time state, including verifier addresses, compatible backend versions, DApp metadata digest, function root, managed storage vector, `aPubBlockHash`, and refund schedule.
   - `packages/apps/private-state/cli/private-state-bridge-cli.mjs` prints the immutable channel policy warning, DApp metadata digest, digest schema, function root, verifier addresses, and compatible backend versions before channel creation and first channel join.

4. Accepted design constraint: channel-bound private-state DApp implementations are intentionally fixed.

   Status: accepted immutable-channel/DApp-binding tradeoff. This follows the same policy rationale as Finding 3.

   `PrivateStateController` and `L2AccountingVault` use immutable deployment-time wiring and expose no owner or admin upgrade path. In addition, once a channel is created against registered DApp metadata, the channel keeps the DApp implementation and execution metadata it captured at creation time. This is intentional: the DApp implementation is part of the channel operating policy that users accept when they join.

   Design rationale: changing the DApp implementation for an active channel would change the channel's behavior after users already joined under the original rules. That would be a unilateral policy change unless every affected user explicitly consents. The current design therefore favors immutable channel/DApp binding over in-place patchability.

   Tradeoff: a new DApp instance can be deployed and registered under a new or replacement DApp ID, and new channels can use that registration. Existing channels bound to the old DApp implementation remain bound to it. Contract-level bugs in the DApp instance used by an existing channel require channel migration or a new channel generation; they are not repaired by replacing the DApp implementation in place.

   Mitigation: treat DApp deployment, registration, and channel creation as one final policy package for each channel generation. User-facing warnings added for Finding 3 also cover this point because they state that joining a channel accepts the channel's DApp metadata and fixed execution policy.

   Mainnet recommendation: accepted with explicit disclosure. Do not register the DApp or create mainnet channels until the exact deployed bytecode, callable ABI set, storage-layout manifest, Synthesizer registration artifacts, and channel-captured DApp metadata match the intended function set.

   Current-code evidence:

   - `packages/apps/private-state/src/PrivateStateController.sol` and `packages/apps/private-state/src/L2AccountingVault.sol` do not expose owner upgrade hooks.
   - `DAppManager.updateDAppMetadata(...)` can update the registration for future channels, but existing channels keep the DApp metadata digest, verifier snapshot, function root, and managed storage vector captured at creation.
   - The function-root proof design added in `eb7fd30` changes how function metadata is supplied at execution time, but not the policy commitment: `ChannelManager.executeChannelTransaction(...)` accepts calldata function metadata only after proving it against the channel's immutable `functionRoot`.

## Other Security Checks

### zk-L2 Privacy Assumption

The private-state DApp assumes the Tokamak zk-L2 model where user transaction contents are private to the caller and L1 observers see proofs plus resulting state transitions. The contracts do not add L1 mempool calldata-hiding logic, which is appropriate under this execution model. The DApp documentation correctly states that the contracts themselves do not provide note-ownership privacy without the surrounding proving-based L2 execution environment.

### Bridge-Managed Custody

The custody model is structurally correct: canonical asset custody remains in the L1 bridge vault, while the private-state DApp keeps L2 accounting balances, note commitments, and nullifiers. `L2AccountingVault` is accounting-only and can be mutated only by its immutable controller. Users do not directly move canonical assets inside the L2 DApp contracts.

### L2 Accounting Bounds

`L2AccountingVault.creditLiquidBalance(...)` rejects zero amounts, rejects zero accounts, and prevents balances from reaching or exceeding the BLS12-381 scalar field order. `debitLiquidBalance(...)` rejects zero amounts, rejects zero accounts, and prevents native underflow by checking available balance before subtraction.

### User-Facing Symbolic Paths

The static successful-path checker passed these private-state functions:

- `mintNotes1` through `mintNotes6`
- `transferNotes1To1`
- `transferNotes1To2`
- `transferNotes1To3`
- `transferNotes2To1`
- `transferNotes2To2`
- `transferNotes3To1`
- `transferNotes3To2`
- `transferNotes4To1`
- `L2AccountingVault.creditLiquidBalance`
- `L2AccountingVault.debitLiquidBalance`

The checker could not parse the `redeemNotes1` through `redeemNotes4` functions because their zero-address receiver guard is implemented in inline assembly. Manual review indicates those redeem functions still have one successful path: validate non-zero receiver, prepare spendable notes, consume nullifiers, sum value, and credit liquid balance.

### Function Bytecode and Placement Discipline

The private-state user-facing functions use fixed-arity entrypoints rather than a generic multi-mode dispatcher. The mint, transfer, and redeem families are mostly unrolled, which fits the fixed-circuit and placement-discipline requirements better than dynamic loops. Some functions still use helper calls for commitment, nullifier, encrypted-note salt, and storage-key derivation; those helpers appear to serve shared correctness and size/placement goals rather than optional feature branching.

### Storage Layout and Address Split

The private-state DApp separates liquid accounting state from note/nullifier state across `L2AccountingVault` and `PrivateStateController`. This split is appropriate because accounting balances and note state grow differently and have different mutation semantics.

### Admin and Ownership

The private-state DApp has no contract-level owner role. The controller-to-vault relationship is immutable and deployment-bound. Bridge administration remains owner-controlled through UUPS-upgradeable bridge components, so the bridge owner key or governance process is a mainnet-critical trust boundary.

### CLI and Local Command Surface

The private-state CLI exists under `packages/apps/private-state/cli` and supports bridge-coupled workflows. The DApp Makefile exposes local anvil, test, E2E, and public-network deployment commands. The CLI's `exit-channel` zero-balance check is useful for user safety but must not be treated as sufficient because direct contract calls can bypass it.

After the resolution of Finding 1, the CLI guard is defense-in-depth rather than the primary security boundary. The on-chain exit path now independently rejects non-zero channel vault balances based on proof-backed observed storage writes.

### Synthesizer Compatibility Deliverables

The repository contains Synthesizer example inputs under `packages/apps/private-state/examples/synthesizer/privateState/`. No files were found under `packages/apps/private-state/scripts/synthesizer-compat-test`, so the stricter per-function compatibility-script deliverable is not present in the expected script directory. Mainnet registration should rely only on freshly regenerated artifacts from the exact deployed contracts and should not treat stale examples as sufficient.

### Deployment Source Integrity

The current local `HEAD` was checked after `git fetch --prune origin main` and is contained in `origin/main`:

- `d43fabaafa9a7ac67ebf22e1e2495e45bdc69bf8`

There is no local `deployment/chain-id-1` mainnet deployment directory. Therefore local metadata cannot prove whether a mainnet bridge proxy already exists. If a proxy already exists on mainnet, only `upgrade` mode should be used.

Latest Sepolia bridge and private-state deployment metadata both record previous source commit `6648d5f452196fb72c729f24cc1118b6fab3203c`. Comparing that commit to the reviewed `HEAD` showed no deployment-relevant Solidity diff under:

- `bridge/src/**/*.sol`
- `packages/apps/private-state/src/**/*.sol`

This means a forced redeployment would need an explicit operational reason; it is not justified by changed contract source alone.

### Canonical Asset

`BridgeCore.canonicalAsset()` hard-codes Tokamak Network Token for Ethereum mainnet as `0x2be5e8c109e2197D077D13A82dAead6a9b3433C5`. This matches the Tokamak Network token contract address shown by CoinGecko on 2026-04-30. The bridge assumes exact-transfer ERC-20 behavior; token pausing, blacklisting, fee-on-transfer behavior, or governance changes in the canonical token remain external trust and availability risks.

## Verification Performed

- `forge test --root bridge --match-path test/BridgeFlow.t.sol`
  - Passed 50 tests after the Finding 1 resolution.
  - Includes regression coverage for rejecting non-zero channel exit, restoring exit eligibility after a full withdraw, and updating `isZeroBalance` from the Tokamak observed `LiquidBalanceStorageWriteObserved` raw-log path.
- `node --check bridge/scripts/deploy-bridge.mjs`
  - Passed after the Finding 2 deployment-gate update.
- `python3 .codex/skills/app-dapp-zk-l2/scripts/check_unique_success_paths.py packages/apps/private-state/src/PrivateStateController.sol --contract PrivateStateController`
  - Passed mint and transfer functions before stopping on inline assembly in `redeemNotes1`.
- `python3 .codex/skills/app-dapp-zk-l2/scripts/check_unique_success_paths.py packages/apps/private-state/src/L2AccountingVault.sol --contract L2AccountingVault`
  - Passed `creditLiquidBalance` and `debitLiquidBalance`.
- `forge test --root bridge --match-path test/BridgeFlow.t.sol --match-test 'testExitChannelAllowsNonZeroChannelBalance|testGrothWithdrawAndClaimToWallet|testExitChannelRefundsAccordingToTimeBucketAndClearsRegistration'`
  - Passed 3 tests.
- `npm run test:bridge:unit -- --match-test 'testExitChannelAllowsNonZeroChannelBalance|testGrothWithdrawAndClaimToWallet|testExitChannelRefundsAccordingToTimeBucketAndClearsRegistration'`
  - Passed 3 tests.
- `forge test --match-path test/private-state/PrivateStateController.t.sol`
  - Failed at global compilation because `test/verifier/Verifier.t.sol` still calls `new TokamakVerifier()` without the constructor argument now required by `TokamakVerifier`.
- `make -C packages/apps/private-state test`
  - Failed for the same global compilation issue.

## Deployment Decision

Findings 1 and 2 have been resolved by the `isZeroBalance` on-chain exit guard and the mainnet deployment-script hard gates. Findings 3 and 4 are accepted immutable-policy tradeoffs with CLI and README disclosure. They raise the cost of mistakes: channel creation, DApp registration, verifier selection, and deployed DApp bytecode must be treated as final for each channel generation.

# Mainnet Deployment Security Audit

Date: 2026-04-30
Reviewed commit: `d43fabaafa9a7ac67ebf22e1e2495e45bdc69bf8`
Scope: bridge contracts, private-state DApp contracts, deployment scripts, registration flow, CLI trust boundaries, and deployment metadata gates relevant to mainnet deployment.

## Findings

1. Critical: `exitChannel` could release an occupied channel-token-vault slot while the L2 accounting balance was still non-zero.

   `L1TokenVault.exitChannel(...)` previously unregistered the caller through `ChannelManager.unregisterChannelTokenVaultIdentity(...)` without verifying that the registered `channelTokenVaultKey` currently had a zero balance in the accepted channel root. After unregistering, the same `channelTokenVaultKey`, leaf index, and L2 address binding became available for registration by another L1 address. A new registrant could then submit a valid withdraw proof against the existing non-zero leaf value and move the orphaned channel balance into their own L1 available balance.

   The CLI zero-balance guard for `exit-channel` was useful local UX logic, but it was not a sufficient security boundary because direct contract calls and `--force` could bypass it.

   Mitigation implemented in this branch: `ChannelManager` now stores `isChannelTokenVaultBalanceZero` in each channel-token-vault registration. The flag starts as `true` at registration, is updated by L1 Groth deposit/withdraw paths through the already-public L1 caller and derived zero-balance boolean, is updated by `executeChannelTransaction(...)` when it observes a proof-backed `LiquidBalanceStorageWriteObserved(address,bytes32)` event from the L2 accounting vault, and is checked before unregistering a channel-token-vault identity. A non-zero flag now makes `exitChannel(...)` revert through `ChannelManager.ChannelTokenVaultBalanceNotZero`.

   This approach intentionally avoids an exit-specific Groth proof and does not restore an on-chain leaf cache. It relies instead on the Tokamak zk-EVM guarantee that observed event logs are part of the verified public output. If an off-chain executor tampers with the log data, the resulting on-chain proof is not valid, so the bridge may safely decode the observed `LiquidBalanceStorageWriteObserved(address,bytes32)` event to update the flag.

   Privacy note: the flag intentionally exposes only the minimum on-chain state needed for this exit rule: whether the registered L2 accounting balance is currently zero. No additional balance-transition event is emitted for the flag itself. The L1 Groth deposit/withdraw path does not pass the L2 address, channel-token-vault key, or exact updated balance into `ChannelManager`; it passes the L1 caller and the zero-balance boolean needed for exit enforcement. The proof-backed DApp execution path does not reveal more than the already accepted `LiquidBalanceStorageWriteObserved(address,bytes32)` public output from which the flag is derived. To keep the flag complete, the bridge rejects non-zero observed liquid-balance writes for unregistered L2 addresses instead of silently accepting balance state that no registration flag can track.

   Upgradeability classification: this issue is fixable for future exits by upgrading the UUPS `L1TokenVault` implementation and deploying new `ChannelManager` instances that include the flag check. Already executed non-zero exits, key reuse, or stolen balances are not reliably recoverable by a later upgrade.

   Mainnet recommendation: for the planned first mainnet proxy deployment, deploy only with the on-chain zero-balance flag mitigation and its tests included. This audit assumes there are no existing mainnet channels, so no channel migration is in scope.

2. High: mainnet deployment safety policies are not enforced inside the deployment script.

   The deployment discipline requires that mainnet use `upgrade` mode once a proxy exists, that exact local `HEAD` already be present on remote `main`, and that deployment-relevant Solidity changes be compared against the previous deployment metadata. These rules currently live in operational instructions, not as hard checks in `bridge/scripts/deploy-bridge.mjs`.

   A mistaken `redeploy-proxy` on mainnet can create new root bridge addresses and split state from existing deployments. A deployment from a commit that is not on remote `main` can also produce metadata whose source links are not resolvable by users or auditors.

   Upgradeability classification: script-level guards can be added before deployment. If a mainnet proxy redeployment has already happened and users or channels start using the wrong address set, normal UUPS upgrades cannot merge the two state histories.

   Mainnet recommendation: add script-enforced mainnet guards before deployment, including remote-main source integrity, dirty-worktree blocking for deployment-relevant files, previous-deployment Solidity diff checks, and a hard refusal of `redeploy-proxy` when mainnet proxy metadata exists.

3. High: deployed `ChannelManager` instances are not upgradeable and freeze verifier and DApp execution metadata at channel creation.

   `BridgeCore`, `DAppManager`, `BridgeAdminManager`, and `L1TokenVault` are UUPS-upgradeable. Per-channel `ChannelManager` instances are regular contracts created by `BridgeCore.createChannel(...)`. Each `ChannelManager` stores immutable verifier addresses, immutable channel metadata, a fixed managed-storage vector, fixed function metadata copied from `DAppManager`, and fixed refund schedule parameters.

   Updating `BridgeCore.setGrothVerifier(...)`, `BridgeCore.setTokamakVerifier(...)`, or DApp registration metadata only affects future channel creation. Existing channels keep their originally captured verifier and function metadata.

   Upgradeability classification: framework-level bugs can often be fixed for future channels through UUPS upgrades and new channel creation. Bugs in an already deployed channel's verifier binding, function layout, managed storage vector, or accepted execution grammar require channel migration; they are not repairable in place by upgrading `BridgeCore`.

   Mainnet recommendation: treat channel creation as a final commitment. Create mainnet channels only after verifier versions, Groth16 setup artifacts, `aPubUser` offsets, function selectors, and managed storage addresses have been independently checked against the exact DApp deployment.

4. Medium: private-state DApp contracts are intentionally non-upgradeable.

   `PrivateStateController` and `L2AccountingVault` use immutable deployment-time wiring and expose no owner or admin upgrade path. This is consistent with the current DApp design, but it means any contract-level bug in the DApp instance registered to a mainnet channel cannot be patched in place.

   Upgradeability classification: a new DApp instance can be deployed and registered under a new or replacement DApp ID, and new channels can use that registration. Existing channels bound to the old contracts remain bound to the old contracts.

   Mainnet recommendation: treat DApp deployment and registration as final for each channel generation. Do not register the DApp on mainnet until its exact deployed bytecode, callable ABI set, storage-layout manifest, and Synthesizer registration artifacts match the intended function set.

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

### Proof-Backed Log Accounting

`L2AccountingVault` emits `LiquidBalanceStorageWriteObserved(address,bytes32)` after liquid-balance credits and debits. `ChannelManager.executeChannelTransaction(...)` decodes this event only after Tokamak proof verification and uses it to synchronize the registered channel-token-vault zero-balance flag. The trust assumption is that Tokamak zk-EVM binds emitted logs into the verified public output; malformed or tampered logs cannot be accepted without a valid proof.

The bridge ignores zero-value events for unregistered L2 addresses, but rejects non-zero observed liquid-balance writes when the L2 address has no channel-token-vault registration. This preserves the invariant that any non-zero liquid balance capable of later exiting has a tracked zero-balance flag. For registered channel identities, multiple observed writes in a single accepted transaction are applied in order, so the final observed write determines the exit eligibility flag. No dedicated flag-update event is emitted, which avoids adding another L1-indexed activity signal beyond the proof-backed public output.

### Synthesizer Compatibility Deliverables

The repository contains Synthesizer example inputs under `packages/apps/private-state/examples/synthesizer/privateState/`. No files were found under `packages/apps/private-state/scripts/synthesizer-compat-test`, so the stricter per-function compatibility-script deliverable is not present in the expected script directory. Mainnet registration should rely only on freshly regenerated artifacts from the exact deployed contracts and should not treat stale examples as sufficient.

### Deployment Source Integrity

The current local `HEAD` was checked after `git fetch --prune origin main` and is contained in `origin/main`:

- `d43fabaafa9a7ac67ebf22e1e2495e45bdc69bf8`

This review assumes the mainnet launch is the first proxy deployment and that there are no existing mainnet bridge channels. There is no local `deployment/chain-id-1` mainnet deployment directory for an existing proxy address set. If that assumption changes before launch, the deployment decision must be revisited before executing the script.

Latest Sepolia bridge and private-state deployment metadata both record previous source commit `6648d5f452196fb72c729f24cc1118b6fab3203c`. Comparing that commit to the reviewed `HEAD` showed no deployment-relevant Solidity diff under:

- `bridge/src/**/*.sol`
- `packages/apps/private-state/src/**/*.sol`

This means a forced redeployment would need an explicit operational reason; it is not justified by changed contract source alone.

### Canonical Asset

`BridgeCore.canonicalAsset()` hard-codes Tokamak Network Token for Ethereum mainnet as `0x2be5e8c109e2197D077D13A82dAead6a9b3433C5`. This matches the Tokamak Network token contract address shown by CoinGecko on 2026-04-30. The bridge assumes exact-transfer ERC-20 behavior; token pausing, blacklisting, fee-on-transfer behavior, or governance changes in the canonical token remain external trust and availability risks.

## Verification Performed

- `python3 .codex/skills/app-dapp-zk-l2/scripts/check_unique_success_paths.py packages/apps/private-state/src/PrivateStateController.sol --contract PrivateStateController`
  - Passed mint and transfer functions before stopping on inline assembly in `redeemNotes1`.
- `python3 .codex/skills/app-dapp-zk-l2/scripts/check_unique_success_paths.py packages/apps/private-state/src/L2AccountingVault.sol --contract L2AccountingVault`
  - Passed `creditLiquidBalance` and `debitLiquidBalance`.
- `forge test --root bridge --match-path test/BridgeFlow.t.sol --match-test 'testChannelReturnsRegisteredTokenVaultIdentityForUser|testGrothDepositUpdatesVaultStateAndRootVector|testExitChannelRejectsNonZeroChannelBalance|testGrothWithdrawAndClaimToWallet|testFullWithdrawRestoresZeroBalanceExitEligibility|testTokamakObservedLiquidBalanceWriteUpdatesZeroBalanceFlag|testTokamakObservedLiquidBalanceWriteRejectsUnregisteredNonzeroBalance|testTokamakVerificationEmitsObservedEventTopicZeroCorrectly'`
  - Passed 8 tests.
- `forge test --root bridge --match-path test/BridgeFlow.t.sol`
  - Passed 50 tests.
- `forge test --match-path test/private-state/PrivateStateController.t.sol`
  - Failed at global compilation because `test/verifier/Verifier.t.sol` still calls `new TokamakVerifier()` without the constructor argument now required by `TokamakVerifier`.
- `make -C packages/apps/private-state test`
  - Failed for the same global compilation issue.

## Deployment Decision

Under the first mainnet proxy deployment assumption, mainnet deployment should proceed only after the zero-balance flag mitigation for Finding 1 and the deployment-script gates in Finding 2 are included in the deployment branch. Findings 3 and 4 are design constraints rather than immediate code defects, but they raise the cost of mistakes: channel creation, DApp registration, verifier selection, and deployed DApp bytecode must be treated as final for each channel generation.

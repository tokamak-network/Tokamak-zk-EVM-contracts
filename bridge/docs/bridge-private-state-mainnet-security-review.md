# Bridge and Private-State Mainnet Security Review

Date: 2026-04-10

## 1. Scope

This document reviews the current implementation that would be used to deploy:

- the L1 bridge stack under `bridge/src`
- the `private-state` DApp under `apps/private-state/src`

The review is focused on two threat classes:

- malicious use that can manipulate funds
- malicious use or operational abuse that can deny service or strand user funds

This is a current-implementation review, not an abstract protocol proof.

## 2. Review Inputs

Reviewed code and artifacts:

- `bridge/src/BridgeCore.sol`
- `bridge/src/L1TokenVault.sol`
- `bridge/src/ChannelManager.sol`
- `bridge/src/DAppManager.sol`
- `bridge/src/BridgeAdminManager.sol`
- `apps/private-state/src/PrivateStateController.sol`
- `apps/private-state/src/L2AccountingVault.sol`
- `apps/private-state/cli/private-state-bridge-cli.mjs`
- `bridge/scripts/DeployBridgeStack.s.sol`
- `bridge/deployments/bridge.11155111.json`
- `bridge/deployments/dapp-registration.11155111.json`
- `test/private-state/PrivateStateController.t.sol`
- `bridge/test/BridgeFlow.t.sol`

Verification performed:

- `forge test` in `bridge/`: passed `40/40`
- unique-success-path checker on `PrivateStateController`: all mint and transfer entrypoints passed; the checker failed to parse the redeem family because of inline assembly, so redeem entrypoints were reviewed manually

Verification limitation:

- the repository root Foundry configuration still compiles legacy broken tests under `test/bridge`, so `make test` for `apps/private-state` currently fails before it can isolate the private-state suite

## 3. Executive Conclusion

The current system is **not ready for open mainnet deployment as-is**.

I did not find an unprivileged direct-drain path in the current bridge or DApp logic under the following assumptions:

- the Groth16 verifier is sound
- the Tokamak verifier is sound
- the registered DApp metadata is correct
- the owner key is honest and uncompromised

However, the current implementation still has several deployment-blocking risks:

1. A privileged owner can replace verifiers or upgrade core contracts and thereby steal or freeze all funds.
2. Channel registration is permissionless and bounded by only `4096` reserved token-vault leaf indices, which allows channel-join denial of service through registration exhaustion.

The shared L1 vault still increases incident blast radius, but this review treats that as an architectural observation rather than a standalone present-code finding.

Mainnet deployment is reasonable only after those items are explicitly addressed or the launch is intentionally constrained to a trusted pilot with strict user caps and trusted operators.

## 4. Security Properties That Hold in the Current Code

### 4.1 L1 custody is not directly writable by the DApp

The `private-state` DApp cannot move canonical ERC-20 custody on its own. Canonical token movement is restricted to:

- `fund(...)`
- `claimToWallet(...)`
- Groth-backed `deposit(...)`
- Groth-backed `withdraw(...)`

See `bridge/src/L1TokenVault.sol`.

### 4.2 The L2 accounting vault is controller-only and field-bounded

`L2AccountingVault` has:

- immutable controller binding
- no user-facing transfer, deposit, or withdraw entrypoint
- BLS12-381 scalar-field overflow checks on credits
- underflow protection on debits

See `apps/private-state/src/L2AccountingVault.sol`.

### 4.3 Note lifecycle functions preserve ownership and value

`PrivateStateController` enforces:

- input note ownership by `msg.sender`
- exact input/output value conservation for transfer paths
- one-time nullifier usage
- one-time commitment creation
- credit back to liquid balance only through redeem paths

See `apps/private-state/src/PrivateStateController.sol`.

### 4.4 The bridge rejects unsupported token transfer behavior

The L1 vault explicitly rejects fee-on-transfer style token deltas in both ingress and egress paths.

That protects accounting soundness for the assumed canonical token model.

## 5. Findings

### Finding 1: Privileged owner can forge, freeze, or rewrite custody

Severity: Critical

Relevant code:

- `bridge/src/BridgeCore.sol:89-106`
- `bridge/src/BridgeCore.sol:208`
- `bridge/src/L1TokenVault.sol:200`
- `bridge/src/DAppManager.sol:384`
- `bridge/src/BridgeAdminManager.sol:38`
- `bridge/scripts/DeployBridgeStack.s.sol:35-90`
- `bridge/deployments/bridge.11155111.json:12-18`

Why it matters:

- `BridgeCore` owner can replace the Groth16 verifier.
- `BridgeCore` owner can replace the Tokamak verifier.
- every major bridge contract is UUPS-upgradeable under owner control.
- the Sepolia deployment artifact shows a single EOA as both `deployer` and `owner`.

Fund-manipulation impact:

- a malicious verifier can accept forged root transitions
- a malicious upgrade can bypass proof checks entirely
- a malicious vault upgrade can transfer assets out of custody
- a malicious DAppManager or BridgeCore upgrade can rewrite channel metadata or registry behavior

Service-disruption impact:

- the same powers can freeze deposits, withdrawals, claims, or channel execution
- users have no trust-minimized escape hatch if the owner key is compromised

Mainnet consequence:

- user funds are currently only as safe as the owner key
- this is incompatible with an open mainnet launch unless governance is intentionally centralized and fully disclosed

Required before mainnet:

- move bridge ownership to a well-audited multisig before user funds arrive
- separate emergency pause authority from upgrade authority
- stop using one globally mutable verifier pointer for all existing channels
- snapshot the current Groth16 verifier and Tokamak verifier into each channel at channel-creation time, and make those channel-scoped verifier addresses immutable for the lifetime of that channel
- if a verifier bug is discovered after channel creation, do not upgrade that channel's verifier in place; instead, pause or deprecate the affected channel, deploy a fresh channel that snapshots the newer verifier, and migrate users explicitly
- treat `BridgeCore.setGrothVerifier(...)` and `BridgeCore.setTokamakVerifier(...)` as defaults for future channels only, not as retroactive rewrites of already-open channels
- if any verifier-default update remains owner-controlled, add a timelock or staged activation process for new-channel deployments that rely on the new verifier
- publish an explicit policy for when verifier rotation or upgrades are allowed
- strongly consider freezing custody-critical upgrades after a maturation period, even if future-channel verifier defaults remain configurable

### Finding 2: Channel registration is sybil-exhaustible through leaf-index reservation

Severity: High

Relevant code:

- `bridge/src/ChannelManager.sol:222-272`
- `apps/private-state/cli/private-state-bridge-cli.mjs:1052-1113`
- `bridge/src/ChannelManager.sol:71`
- `bridge/src/ChannelManager.sol:245-266`

Why it matters:

`registerChannelTokenVaultIdentity(...)` accepts caller-supplied:

- `l2Address`
- `channelTokenVaultKey`
- `leafIndex`
- `noteReceivePubKey`

The bridge only checks local consistency:

- one registration per L1 address
- one registration per L2 address
- one registration per storage key
- one registration per leaf index
- `leafIndex == storageKey % 4096`

The critical point for denial of service is that registration reserves the `leafIndex` immediately, before any bridge deposit happens. The function records the reservation in `_channelTokenVaultLeafOwners`, so `join-channel` alone can consume one of the `4096` admissible registration indices for that channel.

Attack scenarios:

1. Leaf-index reservation exhaustion
   - the channel token-vault tree admits only `4096` registration indices
   - an attacker can create many L1 accounts and call `join-channel` repeatedly
   - each successful registration reserves one `leafIndex` even if the attacker never deposits into the channel
   - once enough indices are reserved, new legitimate users cannot register for that channel at all

2. Channel griefing without capital commitment
   - the attacker does not need to fund the bridge vault first
   - the attacker does not need to move value into L2
   - the attacker only pays registration gas, so the cost to deny channel access is much lower than the cost imposed on honest users

Fund-manipulation impact:

- this is primarily a liveness attack, not a clean theft primitive
- however, it can strand funds in the shared bridge vault because users cannot complete the L1-to-channel transition

Service-disruption impact:

- joining a channel can be denied at scale
- an otherwise healthy channel can become closed to new participants
- operators may need to create and migrate users to a fresh channel even though the old channel's proof logic remains sound

Required before mainnet:

- replace the current gas-only `join-channel` path with an atomic `join-and-deposit` flow that:
  - charges a fixed non-refundable join fee
  - creates the channel registration
  - verifies a `deposit` proof with `currentUserValue == 0`
  - requires `updatedUserValue` to be at least a configured minimum bootstrap balance for that channel
- add an atomic `withdraw-and-exit` flow that:
  - verifies a `withdraw` proof with `updatedUserValue == 0`
  - requires the registration to have recorded at least one prior channel transaction activity
  - deletes the registration and frees the reserved `leafIndex` only after the zero-balance exit succeeds
- extend the per-user registration state with a `hasExecutedChannelTx` flag and, under the current non-relayed assumption, set that flag on successful `executeChannelTransaction(...)` calls for `msg.sender`
- update the CLI and user guidance so `join-channel` becomes a proof-backed paid entry action rather than a free reservation call

Expected mitigation strength:

- this materially improves the current finding because leaf exhaustion is no longer a gas-only sybil attack
- exhausting all `4096` indices would require, per occupied slot:
  - one non-refundable join fee
  - one bootstrap deposit of at least the configured minimum, locked in channel balance until exit
  - one successful proof-backed entry transaction
- an attacker who wants to recycle capital instead of leaving slots permanently occupied would also need at least one additional channel transaction per account before `withdraw-and-exit` can release the locked balance
- the attack therefore becomes an economic denial of service rather than a near-free registration griefing primitive
- this is still not a complete fix:
  - a sufficiently well-funded attacker can still fill all slots
  - the minimum bootstrap deposit is capital lock, not permanent loss
  - the fixed join fee is the main non-recoverable deterrent
  - honest users must also pay the same entry cost

### Finding 3: Exact-transfer token behavior is a hard external dependency

Severity: Medium

Relevant code:

- `bridge/src/L1TokenVault.sol:78-89`
- `bridge/src/L1TokenVault.sol:122-139`

Why it matters:

The bridge requires the canonical asset to behave like an exact-transfer ERC-20.

If the token ever:

- pauses transfers
- blacklists the vault or users
- adds fees
- rebases in a way that changes observed deltas

then `fund(...)` and `claimToWallet(...)` can revert.

Fund-manipulation impact:

- this does not create a new theft primitive inside the bridge
- it does create an external trust dependency that can make exits unavailable

Service-disruption impact:

- deposits can fail
- claims can fail
- users can remain solvent on paper but unable to move assets out of the shared vault

Required before mainnet:

- verify the canonical mainnet asset contract behavior and governance model explicitly
- publish this dependency in the operator and user risk disclosures

## 6. Additional Observations

### 6.1 `leader` is not an execution gate

`ChannelManager` stores a `leader`, but `executeChannelTransaction(...)` is permissionless.

That is good for liveness, but it means:

- any party can relay a valid proof
- no security property should assume that only the stored leader can sequence channel execution

### 6.2 No direct user path exists into `L2AccountingVault`

This is a positive property.

The current app respects bridge-managed custody:

- users do not call the L2 accounting vault directly
- only the immutable controller can mutate liquid balances

### 6.3 Mint and transfer entrypoints satisfy the single-success-path check

The static checker passed all mint and transfer entrypoints.

The redeem family could not be parsed by the checker because of inline assembly around the zero-address guard, but manual review indicates the redeem functions also follow a single success path:

- zero-address receiver guard
- fixed-arity note preparation
- nullifier consumption
- one credit into `L2AccountingVault`

### 6.4 Shared vault custody increases incident blast radius

This review did not identify a direct present bug that lets one channel steal another channel's funds solely because all channels share one `bridgeTokenVault`.

The current implementation still binds Groth and Tokamak acceptance to channel-specific registrations, roots, and metadata, so pooled custody is not treated here as an independent exploit primitive.

It remains worth disclosing as an architectural observation:

- if some other proof-acceptance or accounting bug is discovered later, losses would hit one global custody pool rather than a naturally isolated per-channel vault
- incident response on the shared vault would still affect every channel together

That is weaker than a standalone finding, but it is still relevant for rollout sizing, TVL caps, and migration planning.

## 7. Mainnet Readiness Verdict

### Must fix before open mainnet

- privileged owner can rotate verifiers and upgrade core contracts
- channel registration can be sybil-exhausted through leaf-index reservation

### Strongly recommended before meaningful TVL

- reduce the blast radius of the shared vault architecture
- add emergency pause and incident-response controls
- document exact supported note shapes per deployment
- verify the canonical token's transfer and governance behavior

### Acceptable in the current code

- unprivileged users cannot directly mutate L1 custody without proofs
- app note transfers preserve value and ownership constraints
- liquid accounting mutations are controller-only and BLS-field-bounded

## 8. Bottom Line

If the question is whether the current bridge and `private-state` DApp are ready for unrestricted Ethereum mainnet usage with real user funds, the answer is **no**.

If the launch is intentionally limited to a trusted pilot, then the minimum acceptable posture is:

- multisig-controlled ownership from day one
- strict user-count and TVL caps
- explicit disclosure that channel join can currently be griefed
- pre-created channels only after verifying the exact registered function set that users need

Without those controls, the present design leaves both custody integrity and service availability too exposed for a permissionless mainnet deployment.

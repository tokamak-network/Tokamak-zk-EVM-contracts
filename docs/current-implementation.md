# Current Bridge Implementation vs `docs/spec.md`

## Scope

- Spec baseline: `docs/spec.md`
- Implementation baseline:
  - `src/BridgeCore.sol`
  - `src/BridgeDepositManager.sol`
  - `src/BridgeProofManager.sol`
  - `src/BridgeWithdrawManager.sol`
  - `src/BridgeAdminManager.sol`

This document lists:
1. Spec-defined requirements that are currently not satisfied by the implementation.
2. Features implemented in the bridge contracts but not defined in `docs/spec.md`.

## Spec-Defined Requirements Not Satisfied

1. Missing bridge-manager relation getters from the spec model.
- Not implemented as callable interfaces: `getFcnStorages(f)`, `getUserSlots(s)`, `getFcnCfg(f)`.
- Current code stores function configs in `TargetContract.registeredFunctions` and slot definitions in `TargetContract.userStorageSlots`, but does not expose the spec's relation-level getter surface.

2. Missing per-function storage-address relation model (`S_M`) and its existence invariant.
- The spec requires each function signature to map to at least one storage address.
- Current implementation registers functions (`functionSignature`, `instancesHash`, preprocess arrays) but has no explicit `function -> storage addresses` mapping.

3. Missing channel projected getters required in the Channel section.
- Not implemented as callable interfaces: `getAppFcnStorages`, `getAppPreAllocKeys`, `getAppUserSlots`, `getAppFcnCfg`.

4. Missing key relation getter required by the Channel section.
- Spec requires `getAppUserStorageKey(user, storageAddr)`.
- Current implementation exposes `getL2MptKey(channelId, participant, slotIndex)`; this is indexed by slot index, not by the spec's `storageAddr` domain.

5. Missing validated-value getter required by the Channel section.
- Spec requires `getAppValidatedStorageValue(storageAddr, appUserStorageKey)`.
- Current implementation exposes `getValidatedUserSlotValue(channelId, participant, slotIndex)` and does not implement the spec getter keyed by `(storageAddr, appUserStorageKey)`.

6. Missing pre-allocated value getter required by the Channel section.
- Spec requires `getAppPreAllocValue(storageAddr, preAllocKey)`.
- Current implementation exposes `getPreAllocatedLeaf(targetContract, key)`; it is target-contract scoped rather than `(storageAddr, key)` scoped.

7. Missing state-indexed root relation (`R`) and corresponding getter.
- Spec requires `stateIndex`, `StateIndices`, and `getVerifiedStateRoot(storageAddr, stateIndex)`.
- Current implementation keeps the current root vector and its hash in storage and emits accepted root-vector updates through events, but it does not maintain an indexed on-chain root-history relation.

8. Missing required setter functions and signatures from the spec.
- Spec defines `updateSingleStorage(...) -> bool` and `updateAllStorages(...) -> bool`.
- No contract in `src/` implements these setter names or signatures.

9. Setter-gated update semantics in the spec are not realized via spec API shape.
- The spec constrains value/root transitions through `updateSingleStorage` or `updateAllStorages`.
- Current implementation uses a different lifecycle API:
  - `initializeChannelState(...)`
  - `submitProofAndSignature(...)`
  - `updateValidatedUserStorage(...)`

10. Missing Bridge Core lifted getters from the spec relation layer.
- Not implemented as callable interfaces:
  - `getChannelFcnStorages(c, f)`
  - `getChannelPreAllocKeys(c, s)`
  - `getChannelUserSlots(c, s)`
  - `getChannelFcnCfg(c, f)`
  - `getChannelUserStorageKey(c, u, s)`
  - `getChannelValidatedStorageValue(c, s, k)`
  - `getChannelPreAllocValue(c, s, k)`
  - `getChannelVerifiedStateRoot(c, s, t)`
- Closest implemented getter is `getChannelParticipants(channelId)` for user listing.

11. Core access-domain constraints from the spec are not strictly enforced as described.
- Spec requires user-scoped getter domains to include membership witness `(c, u)`.
- Current getters such as `getValidatedUserSlotValue` and `getL2MptKey` do not enforce this domain rule and can return default values for non-members.

12. Missing explicit spec variables for Merkle-level parameters.
- Spec defines `nMerkleTreeLevels` as a bridge-manager variable.
- Current implementation validates tree sizes procedurally (16/32/64/128 leaf variants) without exposing all parameters in the same spec form.

## Implemented Features Not Defined in `spec.md`

1. Modular manager architecture split by responsibility.
- `BridgeCore`, `BridgeDepositManager`, `BridgeProofManager`, `BridgeWithdrawManager`, `BridgeAdminManager`.

2. UUPS upgradeability and implementation-slot introspection.
- `UUPSUpgradeable`, `_authorizeUpgrade`, and `getImplementation()` in each manager/core contract.

3. ERC20 deposit custody flow.
- `depositToken(...)` checks allowance/balance, transfers tokens to deposit manager custody, and updates deposited slot values.

4. ERC20 withdrawal flow after channel cleanup or timeout.
- `withdraw(...)` in `BridgeWithdrawManager` and transfer-out through `BridgeDepositManager.transferForWithdrawal(...)`.

5. Channel timeout policy.
- Fixed `CHANNEL_TIMEOUT = 7 days` and timeout checks through `isChannelTimedOut(...)`.

6. Optional FROST threshold-signature mode.
- Channel-level switch (`enableFrostSignature`), group public key registration, signer derivation, and signature verification via `IZecFrost`.

7. Block-info commitment and proof binding.
- Computes/stores `blockInfosHash` at initialization and checks it against proof public inputs during proof submission.

8. Chained multi-proof submission flow with bounded proof count.
- `submitProofAndSignature(...)` supports 1-5 proofs and enforces state-root chain continuity.

9. Groth16 verifier specialization by tree size.
- Separate verifier contracts for 16/32/64/128 leaves selected at runtime.

10. On-chain slot loading via staticcall during channel initialization.
- `UserStorageSlot.isLoadedOnChain` controls whether values are loaded from deposits or fetched from target contract getter calls.

11. Participant whitelisting and leader-centric channel opening.
- `openChannel(...)` includes whitelist setup and leader auto-whitelisting.

12. Channel cleanup and explicit channel deletion after finalization.
- `cleanupChannel(...)` deletes channel data and mapping residues for participants/slots.

13. Admin convenience function for TON pre-allocated leaf.
- `setupTonTransferPreAllocatedLeaf(...)`.

14. Utility helpers not defined by spec.
- `generateChannelId(...)`, `getBalanceSlotIndex(...)`, `getBalanceSlotOffset(...)`, and manager-address update functions.

15. Additional event surface for operational observability.
- Channel open/delete, public-key set, proof verification, deposit/withdraw, pre-allocated leaf updates, and related administrative events.

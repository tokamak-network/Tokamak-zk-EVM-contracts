# Private State zk-note DApp

This application implements the lifecycle of a zk-note style payment system for the Tokamak Network Token entirely with smart contracts and without zero-knowledge circuits.

## Scope

The target deployment model is a proving-based L2 where raw transaction calldata is not exposed to L1 observers or other L2 users. Canonical asset custody remains on L1. The L2 DApp keeps accounting balances only and assumes a bridge verifier on L1 accepts state-root transitions backed by proofs. What remains from the zk-note model is the state machine:

- L1 bridge custody is the source of truth for the Tokamak Network Token.
- Bridge-coupled accounting deposits increase an L2 accounting balance.
- Accounting balances can be converted into spendable notes.
- Spending a note proves ownership at the contract layer, marks the old note as spent, derives a nullifier, and creates replacement output notes.
- Notes can be redeemed back into liquid accounting balances inside the L2 accounting vault.
- Bridge-coupled accounting withdrawals decrease the L2 accounting balance.

## Contract Layout

- `L2AccountingVault.sol`: Stores per-account L2 accounting balances only. It does not custody real tokens.
- `PrivateNoteRegistry.sol`: Stores note commitments only.
- `PrivateNullifierRegistry.sol`: Stores nullifier usage and is the single source of truth for spent status.
- `PrivateStateController.sol`: User-facing entrypoint that reconstructs commitments and nullifiers from transaction calldata and applies bridge-coupled accounting transitions.

## Ownership Proof Without Circuits

Real Zcash or zkDai systems prove note ownership inside a circuit by showing knowledge of secret note material. This implementation replaces that proof with contract-side verification:

- The spender submits the full note plaintext in calldata.
- The controller recomputes the note commitment from that plaintext and checks that the commitment exists on-chain.
- The plaintext includes a visible `owner` address.
- The note owner must spend directly by calling the controller.
This preserves spend authorization semantics. Privacy assumptions depend on the surrounding L2 transaction visibility model rather than on the contracts themselves.

## Owner Roles

This DApp uses two different notions of ownership:

- `note owner`: the address embedded in a note plaintext that is allowed to spend that note
- `contract owner`: the `Ownable` administrator of `L2AccountingVault`, `PrivateNoteRegistry`, and `PrivateNullifierRegistry`

The two roles are intentionally separate. A note owner controls note spending through the controller entrypoints. A contract owner does not gain direct authority over user notes, commitments, nullifiers, or L2 accounting balances.

In the current design, the contract owner has a narrow bootstrap role only:

- call `bindController()` once on each storage contract
- transfer or renounce ownership of those storage contracts later if desired

After controller binding is complete, the contract owner cannot:

- spend a user's note
- register commitments directly
- mark nullifiers as used directly
- credit or debit user accounting balances directly

Those state changes remain restricted to the bound controller. As a result, the contract owner is best understood as an initialization and administration role, not as an operator with direct user-fund control.

## Nullifier Model

The controller computes a deterministic nullifier from the submitted note plaintext and the nullifier store domain. The canonical Tokamak Network Token asset identifier is fixed at deployment time and remains part of the derived hashes even though callers do not pass it explicitly. The note store itself only keeps commitment existence.

- `value`
- `owner`
- `salt`

Once a note is consumed, the nullifier store records the nullifier and rejects any later attempt to reuse it.

The design intentionally avoids storing note plaintext or duplicate spent flags on-chain. The nullifier store is the only spend-state authority.

## End-to-End Flow

1. Lock or release the canonical asset through the L1 bridge custody flow.
2. Apply the matching L2 accounting transition with `bridgeDeposit` or `bridgeWithdraw`.
3. Call `mintNotes1`, `mintNotes2`, or `mintNotes3` to lock part of the liquid balance into one, two, or three note commitments.
4. Call one of `transferNotes4`, `transferNotes6`, or `transferNotes8` with exactly 3 output notes.
5. Call one of `redeemNotes4`, `redeemNotes6`, or `redeemNotes8` to convert fixed batches of notes back into liquid balances.

## Fixed-Arity Entry Points

The current bridge-coupled accounting API exposes two fixed-purpose user-facing functions:

- `bridgeDeposit`: increase the caller's L2 accounting balance after the matching L1 bridge deposit proof
- `bridgeWithdraw`: decrease the caller's L2 accounting balance before the matching L1 bridge withdrawal settlement

The current mint API exposes three fixed-arity user-facing functions:

- `mintNotes1`: 1 output note
- `mintNotes2`: 2 output notes
- `mintNotes3`: 3 output notes

The current transfer API exposes three fixed-arity user-facing functions:

- `transferNotes4`: 4 input notes, 3 output notes
- `transferNotes6`: 6 input notes, 3 output notes
- `transferNotes8`: 8 input notes, 3 output notes

The current redeem API exposes three fixed-arity user-facing functions:

- `redeemNotes4`: 4 input notes
- `redeemNotes6`: 6 input notes
- `redeemNotes8`: 8 input notes

These fixed entrypoints are intended to make the final user-facing state transitions more circuit-friendly under the repository's zk-L2 design constraints.

## Deployment Inputs

Sepolia deployment requires four concrete inputs:

- the deployer private key
- the Sepolia RPC URL
- the Sepolia chain ID
- the canonical TON asset address used as `canonicalAsset`

The repository now includes:

- `apps/private-state/script/deploy/DeployPrivateState.s.sol`
- `apps/private-state/script/deploy/deploy-private-state.sh`
- `apps/.env.template`

The deploy script deploys `L2AccountingVault`, `PrivateNoteRegistry`, `PrivateNullifierRegistry`, and `PrivateStateController`, binds the controller to the three storage contracts, and optionally transfers ownership of those storage contracts to `PRIVATE_STATE_OWNER`.

private-state deployment parameters must be stored in `apps/.env`, not in the repository-root bridge deployment `.env`.

The private-state deploy flow uses shared app deployment variables for the signer and target network:

- `APPS_DEPLOYER_PRIVATE_KEY`
- `APPS_RPC_URL`
- `APPS_CHAIN_ID`
- `APPS_ETHERSCAN_API_KEY` when block explorer verification is needed

It uses namespaced variables only for private-state-specific values:

- `PRIVATE_STATE_CANONICAL_ASSET`
- `PRIVATE_STATE_OWNER`

private-state deployment parameters must be stored in `apps/.env`, not in the repository-root bridge deployment `.env`.

The private-state deploy flow uses shared app deployment variables for the signer and target network:

- `APPS_DEPLOYER_PRIVATE_KEY`
- `APPS_RPC_URL`
- `APPS_CHAIN_ID`
- `APPS_ETHERSCAN_API_KEY` when block explorer verification is needed

It uses namespaced variables only for private-state-specific values:

- `PRIVATE_STATE_CANONICAL_ASSET`
- `PRIVATE_STATE_OWNER`

private-state deployment parameters must be stored in `apps/.env`, not in the repository-root bridge deployment `.env`.

The private-state deploy flow uses shared app deployment variables for the signer and target network:

- `APPS_DEPLOYER_PRIVATE_KEY`
- `APPS_RPC_URL`
- `APPS_CHAIN_ID`
- `APPS_ETHERSCAN_API_KEY` when block explorer verification is needed

It uses namespaced variables only for private-state-specific values:

- `PRIVATE_STATE_CANONICAL_ASSET`
- `PRIVATE_STATE_OWNER`

## Security Tradeoffs

Because note validity is still checked directly in contract code:

- The system still relies on cross-contract invariants between the controller, accounting vault, note registry, and nullifier registry.
- The bridge-coupled accounting entrypoints model proof-backed L1 bridge settlement rather than standalone L2 token custody.
- Privacy depends on the surrounding L2 execution model, not solely on these contracts.
- The current `bridgeDeposit` and `bridgeWithdraw` functions remain direct user entrypoints. As a result, the deployed contract set does not by itself enforce the stricter architecture where only L1 bridge proof settlement may mutate L2 accounting balances.

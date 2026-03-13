# Private State zk-note DApp

This application implements the lifecycle of a zk-note style payment system for the Tokamak Network Token entirely with smart contracts and without zero-knowledge circuits.

## Scope

The target deployment model is a proving-based L2 where raw transaction calldata is not exposed to L1 observers or other L2 users. What remains from the zk-note model is the state machine:

- Tokamak Network Token deposits move assets into an application vault.
- Deposited balances can be converted into spendable notes.
- Spending a note proves ownership at the contract layer, marks the old note as spent, derives a nullifier, and creates replacement output notes.
- Notes can be redeemed back into liquid token balances inside the vault.
- Liquid balances can be withdrawn as Tokamak Network Token balances.

## Contract Layout

- `TokenVault.sol`: Custodies the Tokamak Network Token and tracks each account's liquid balance inside the DApp.
- `PrivateNoteRegistry.sol`: Stores note commitments only.
- `PrivateNullifierRegistry.sol`: Stores nullifier usage and is the single source of truth for spent status.
- `PrivateStateController.sol`: User-facing entrypoint that reconstructs commitments and nullifiers from transaction calldata.

## Ownership Proof Without Circuits

Real Zcash or zkDai systems prove note ownership inside a circuit by showing knowledge of secret note material. This implementation replaces that proof with contract-side verification:

- The spender submits the full note plaintext in calldata.
- The controller recomputes the note commitment from that plaintext and checks that the commitment exists on-chain.
- The plaintext includes a visible `owner` address.
- The note owner must spend directly by calling the controller.
This preserves spend authorization semantics. Privacy assumptions depend on the surrounding L2 transaction visibility model rather than on the contracts themselves.

## Nullifier Model

The controller computes a deterministic nullifier from the submitted note plaintext and the nullifier store domain. The Tokamak Network Token address is fixed at deployment time and remains part of the derived hashes even though callers do not pass it explicitly. The note store itself only keeps commitment existence.

- `value`
- `owner`
- `salt`

Once a note is consumed, the nullifier store records the nullifier and rejects any later attempt to reuse it.

The design intentionally avoids storing note plaintext or duplicate spent flags on-chain. The nullifier store is the only spend-state authority.

## End-to-End Flow

1. Approve the vault to transfer the Tokamak Network Token.
2. Call `depositToken` or `depositTokenFor` on the controller.
3. Call `mintNotes1`, `mintNotes2`, or `mintNotes3` to lock part of the liquid balance into one, two, or three note commitments.
4. Call one of `transferNotes4`, `transferNotes6`, or `transferNotes8` with exactly 3 output notes.
5. Call one of `redeemNotes4`, `redeemNotes6`, or `redeemNotes8` to convert fixed batches of notes back into liquid balances.
6. Call `withdrawToken` to receive the Tokamak Network Token.

## Fixed-Arity Entry Points

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

## Security Tradeoffs

Because note validity is still checked directly in contract code:

- The system still relies on cross-contract invariants between the controller, vault, note registry, and nullifier registry.
- Privacy depends on the surrounding L2 execution model, not solely on these contracts.

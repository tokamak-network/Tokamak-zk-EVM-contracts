# Private State zk-note DApp

This application implements the lifecycle of a zk-note style payment system for the Tokamak Network Token entirely with smart contracts and without zero-knowledge circuits.

## Scope

The goal is not privacy. The contracts intentionally expose note owners, note values, note salts, and the nullifier derivation inputs in transaction calldata. What remains from the zk-note model is the state machine:

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

Real Zcash or zkDai systems prove note ownership inside a circuit by showing knowledge of secret note material. This implementation replaces that privacy-preserving proof with transparent contract-side verification:

- The spender submits the full note plaintext in calldata.
- The controller recomputes the note commitment from that plaintext and checks that the commitment exists on-chain.
- The plaintext includes a visible `owner` address.
- The owner can spend directly by calling the controller.
- A relayer can spend on behalf of the owner when it submits an ECDSA signature over a controller-defined authorization hash.

This preserves spend authorization semantics, but it does not preserve anonymity or hidden amounts.

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
3. Call `mintNote` to lock part of the liquid balance into a commitment.
4. Call `transferNotes` with the input note plaintext in calldata to consume notes and issue new output commitments.
5. Call `redeemNotes` with the input note plaintext in calldata to convert notes back into liquid balances.
6. Call `withdrawToken` to receive the Tokamak Network Token.

## Security Tradeoffs

Because there is no circuit:

- Note plaintext is public in calldata.
- Note ownership is public.
- Note values are public.
- Nullifier inputs are public.
- The system offers double-spend protection and note accounting, but not privacy.
- Tokamak Network Token balances, note commitments, and nullifier usage live at different addresses, so controller trust and cross-contract invariants remain security-critical.

That tradeoff is deliberate for this DApp and should not be confused with the privacy guarantees of production zk-note systems.

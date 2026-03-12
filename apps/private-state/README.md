# Private State zk-note DApp

This application implements the lifecycle of a zk-note style payment system entirely with smart contracts and without zero-knowledge circuits.

## Scope

The goal is not privacy. The contracts intentionally expose note owners, note values, note salts, and the nullifier derivation inputs on-chain. What remains from the zk-note model is the state machine:

- ERC-20 deposits move assets into an application vault.
- Deposited balances can be converted into spendable notes.
- Spending a note proves ownership at the contract layer, marks the old note as spent, derives a nullifier, and creates replacement output notes.
- Notes can be redeemed back into liquid token balances inside the vault.
- Liquid balances can be withdrawn as ERC-20 tokens.

## Contract Layout

- `TokenVault.sol`: Custodies ERC-20 balances and tracks each account's liquid balance inside the DApp.
- `PrivateNoteRegistry.sol`: Stores note commitments and immutable note metadata.
- `PrivateNullifierRegistry.sol`: Stores nullifier usage and is the single source of truth for spent status.
- `PrivateStateController.sol`: User-facing entrypoint for deposit, note minting, note transfer, note redemption, and withdrawal.

## Ownership Proof Without Circuits

Real Zcash or zkDai systems prove note ownership inside a circuit by showing knowledge of secret note material. This implementation replaces that privacy-preserving proof with transparent contract-side verification:

- A note has a visible `owner` address.
- The owner can spend directly by calling the controller.
- A relayer can spend on behalf of the owner when it submits an ECDSA signature over a controller-defined authorization hash.

This preserves spend authorization semantics, but it does not preserve anonymity or hidden amounts.

## Nullifier Model

The note store computes a deterministic nullifier from:

- `noteId`
- `commitment`
- `owner`
- `nullifierNonce`

Once a note is consumed, the nullifier store records the nullifier and rejects any later attempt to reuse it.

The design intentionally avoids storing both `note.spent` and `nullifierUsed` in different contracts. The nullifier store is the only spend-state authority.

## End-to-End Flow

1. Approve the vault to transfer an ERC-20 token.
2. Call `depositToken` or `depositTokenFor` on the controller.
3. Call `mintNote` to lock part of the liquid balance into a note.
4. Call `transferNotes` to consume notes and issue new output notes.
5. Call `redeemNotes` to convert notes back into liquid balances.
6. Call `withdrawToken` to receive the ERC-20 token.

## Security Tradeoffs

Because there is no circuit:

- Note ownership is public.
- Note values are public.
- Nullifier inputs are public.
- The system offers double-spend protection and note accounting, but not privacy.
- Token balances, note metadata, and nullifier usage now live at different addresses, so controller trust and cross-contract invariants remain security-critical.

That tradeoff is deliberate for this DApp and should not be confused with the privacy guarantees of production zk-note systems.

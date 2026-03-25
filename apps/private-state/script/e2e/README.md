# Private-State Bridge E2E

`run-bridge-private-state-e2e.mjs` executes a genesis-based end-to-end scenario that combines:

- L1 ERC-20 funding into the bridge vault
- Groth-backed L1 -> L2 accounting deposits
- Tokamak proof-backed private-state mint / transfer / redeem steps
- Groth-backed L2 -> L1 withdrawal
- Final ERC-20 claim on L1

## Scenario

The harness uses three participants:

1. `A`, `B`, and `C` each fund the shared `bridgeTokenVault` and deposit `3` tokens into the channel `channelTokenVault` accounting tree.
2. `A`, `B`, and `C` each call `mintNotes1`.
3. `A` calls `transferNotes1To2` and splits its `3`-token note into:
   - `1` token to `B`
   - `2` tokens to `C`
4. `B` calls `transferNotes2To1` and transfers:
   - its own `3`-token note
   - the `1`-token note received from `A`
   into one `4`-token note for `C`.
5. `C` redeems all notes. With the current Tokamak setup capacity, the harness realizes that as three `redeemNotes1` calls over:
   - the `2`-token note received directly from `A`
   - the `4`-token note received from `B`
   - its own minted `3`-token note
6. `C` withdraws `9` tokens from the channel `channelTokenVault` accounting tree back into the shared `bridgeTokenVault` and then claims the ERC-20 balance on L1.

## Run

```bash
node apps/private-state/script/e2e/run-bridge-private-state-e2e.mjs
```

Optional installation step:

```bash
node apps/private-state/script/e2e/run-bridge-private-state-e2e.mjs \
  --install-arg <ALCHEMY_API_KEY|ALCHEMY_RPC_URL>
```

Optional flag:

- `--keep-anvil`: leave the local anvil process running after success

## Outputs

The harness writes step-by-step artifacts under:

`apps/private-state/script/e2e/output/private-state-bridge-genesis`

That directory contains:

- bridge deployment artifacts
- Groth prover inputs and generated proofs
- per-step Tokamak CLI bundles and extracted proof ZIP files
- a final summary JSON

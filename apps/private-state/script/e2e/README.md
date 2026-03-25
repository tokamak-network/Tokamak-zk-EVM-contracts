# Private-State Bridge E2E

`run-bridge-private-state-e2e.mjs` executes a genesis-based end-to-end scenario that combines:

- L1 ERC-20 funding into the bridge vault
- Groth-backed L1 -> L2 accounting deposits
- Tokamak proof-backed private-state mint / transfer / redeem steps
- Groth-backed L2 -> L1 withdrawal
- Final ERC-20 claim on L1

`run-bridge-private-state-cli-e2e.mjs` executes the same participant scenario through command-line entrypoints.
It keeps bridge deployment, DApp registration, and canonical-asset minting in existing helper commands because the
current private-state CLI intentionally starts at user-facing bridge and note flows rather than admin bootstrap flows.

## Scenario

The harness uses three participants:

1. `A`, `B`, and `C` each fund the shared `bridgeTokenVault` and deposit `3` tokens into the channel `channelTokenVault` accounting tree.
2. `A`, `B`, and `C` each call `mintNotes1`.
3. `A` calls `transferNotes1To2` and splits its `3`-token note into:
   - `1` token to `B`
   - `2` tokens to `C`
   The CLI harness verifies that `transfer-notes` writes those output notes into the deterministic recipient wallet
   inbox files for `B` and `C`.
4. `B` calls `transferNotes2To1` and transfers:
   - its own `3`-token note
   - the `1`-token note received from `A`
   into one `4`-token note for `C`.
   The CLI harness verifies that `B` absorbs its own inbox before spending and that `C` receives the new note in its
   wallet inbox before redeeming it.
5. `C` redeems all notes. With the current Tokamak setup capacity, the harness realizes that as three `redeemNotes1` calls over:
   - the `2`-token note received directly from `A`
   - the `4`-token note received from `B`
   - its own minted `3`-token note
6. `C` withdraws `9` tokens from the channel `channelTokenVault` accounting tree back into the shared `bridgeTokenVault` and then claims the ERC-20 balance on L1.

## Run

```bash
node apps/private-state/script/e2e/run-bridge-private-state-e2e.mjs
node apps/private-state/script/e2e/run-bridge-private-state-cli-e2e.mjs
```

Optional flag:

- `--keep-anvil`: leave the local anvil process running after success

## Outputs

The harness writes step-by-step artifacts under:

`apps/private-state/script/e2e/output/private-state-bridge-genesis`

The CLI-driven harness writes its summary under:

`apps/private-state/script/e2e/output/private-state-bridge-cli`

That directory contains:

- bridge deployment artifacts
- Groth prover inputs and generated proofs
- per-step Tokamak CLI bundles and extracted proof ZIP files
- a final summary JSON

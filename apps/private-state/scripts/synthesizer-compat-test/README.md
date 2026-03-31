# Private-State Synthesizer Compatibility Tests

These scripts check that each private-state user-facing function stays Synthesizer-compatible when sampled inputs vary.

Method:

1. Use the Synthesizer CLI entrypoint at `submodules/Tokamak-zk-EVM/packages/frontend/synthesizer/src/interface/cli/index.ts`.
2. Hold `block_info.json` and `contract_codes.json` fixed from the first generated case.
3. Regenerate `previous_state_snapshot.json` and transaction RLP across randomized samples.
4. Run the CLI for each variant.
5. Assert that:
   - `outputs/instance.json -> a_pub_function`
   - `outputs/permutation.json`
   remain identical across all tested variants for the same function.

The main compatibility scripts randomize:

- `fromAccount`
- `toAccount` or note owner / receiver assignments
- transfer self-target cases
- real pre-state registered-key sparsity

Transfer samples also vary a salt label so self-target transfers do not reuse the same note commitments.

Separate `*-block-nonce.ts` scripts perform a distinct compatibility pass where block info is varied independently of the main pre-state randomness. Transaction nonce is intentionally kept fixed because changing it under the same pre-state makes the transaction invalid at the VM validation layer instead of producing a meaningful compatibility comparison.

Registered pre-state keys follow a from-side rule:

- required: consumed from-side keys such as the sender liquid-balance slot in mint or consumed note-commitment slots in transfer and redeem
- optional: to-side keys such as receiver-side vault balances or output-side storage touched later in the transaction

Generated test inputs are stored under:

- `apps/private-state/scripts/synthesizer-compat-test/generated/<function-name>/fixed`
- `apps/private-state/scripts/synthesizer-compat-test/generated/<function-name>/from-account-<index>`

Each `fromAccount` directory keeps the generated `config.json`, `previous_state_snapshot.json`, and `transaction_rlp.txt` used by the test run. The `generated/` directory is intentionally gitignored.

Usage:

```bash
npx tsx apps/private-state/scripts/synthesizer-compat-test/mintNotes1.ts
npx tsx apps/private-state/scripts/synthesizer-compat-test/transferNotes1To2.ts --skip-bootstrap
npx tsx apps/private-state/scripts/synthesizer-compat-test/redeemNotes1.ts --skip-bootstrap
npx tsx apps/private-state/scripts/synthesizer-compat-test/transferNotes1To2-block-nonce.ts --skip-bootstrap
```

Optional flags:

- `--skip-bootstrap`
- `--from-accounts 0,1,2,3`
- `--samples 6`
- `--seed private-state-synth-compat`

`--skip-bootstrap` is useful when running multiple scripts against the same freshly bootstrapped anvil instance.

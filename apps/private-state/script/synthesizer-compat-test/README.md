# Private-State Synthesizer Compatibility Tests

These scripts check that each private-state user-facing function stays Synthesizer-compatible when private inputs vary.

Method:

1. Use the Synthesizer CLI entrypoint at `submodules/Tokamak-zk-EVM/packages/frontend/synthesizer/src/interface/cli/index.ts`.
2. Hold `block_info.json` and `contract_codes.json` fixed from the first generated case.
3. Regenerate `previous_state_snapshot.json` and transaction RLP across multiple `fromAccount` variants.
4. Run the CLI for each variant.
5. Assert that:
   - `outputs/instance.json -> a_pub_function`
   - `outputs/permutation.json`
   remain identical across all tested variants for the same function.

Generated test inputs are stored under:

- `apps/private-state/script/synthesizer-compat-test/generated/<function-name>/fixed`
- `apps/private-state/script/synthesizer-compat-test/generated/<function-name>/from-account-<index>`

Each `fromAccount` directory keeps the generated `config.json`, `previous_state_snapshot.json`, and `transaction_rlp.txt` used by the test run. The `generated/` directory is intentionally gitignored.

Usage:

```bash
npx tsx apps/private-state/script/synthesizer-compat-test/mintNotes1.ts
npx tsx apps/private-state/script/synthesizer-compat-test/transferNotes1To2.ts --skip-bootstrap
npx tsx apps/private-state/script/synthesizer-compat-test/redeemNotes1.ts --skip-bootstrap
```

Optional flags:

- `--skip-bootstrap`
- `--from-accounts 0,1,2,3`

`--skip-bootstrap` is useful when running multiple scripts against the same freshly bootstrapped anvil instance.

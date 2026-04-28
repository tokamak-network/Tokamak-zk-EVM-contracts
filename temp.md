# Private-State CLI UX Notes

These issues came up while using the private-state CLI on a Lambda Cloud GPU instance.

1. `private-state-cli --install --docker` appeared to complete, but the CLI was not actually ready for proof-backed commands. `deposit-channel` later failed with a missing Groth16 metadata file. The install command should provision all runtime prerequisites.

2. `private-state-cli --doctor` did not initially expose the missing Groth16 runtime before a user reached `deposit-channel`. A preflight command should clearly report whether deposit, mint, transfer, and redeem commands are ready to run.

3. Wallet names are generated automatically by `join-channel`, but later commands require users to pass those exact names through `--wallet`. Users naturally think in terms of account labels such as `ADDR6`, not `cuda-0x...` wallet names.

4. There is no convenient wallet discovery command. Users had to inspect `~/tokamak-private-channels/workspace/<network>/<channel>/wallets/` manually. A `list-wallets --network <name> --channel-name <name>` command would make this visible.

5. Environment-variable-based workflows are only partially supported. `--private-key "$ADDR6"` works, but deriving the matching wallet name from that key required ad hoc Node commands. Options such as `--private-key-env ADDR6` or `--account-env ADDR6` would reduce mistakes.

6. Some error messages are technically accurate but do not tell the user what to do next. For example, `Missing Groth16 metadata` should point to the recovery command, such as `private-state-cli --install --docker`.

7. Private key handling is risky in remote GPU instances. The CLI accepts raw private keys on the command line, which can leave shell history or process-list traces. Safer flows could include `--private-key-env`, interactive hidden input, or encrypted local key import.

8. The CLI does not guide the normal workflow. Users must already know the sequence: `create-channel`, `deposit-bridge`, `join-channel`, `deposit-channel`, `mint-notes`, `transfer-notes`, `redeem-notes`, and withdrawal commands. A `status`, `next-step`, or `check-ready` command would reduce operational mistakes.

9. Amount tracking is manual. After `deposit-bridge --amount 10`, users need to remember that value for `deposit-channel --amount 10`. A `deposit-channel --all` option would better match the intent to move the full bridge-vault balance into the channel.

10. GPU/Docker readiness is not obvious from the CLI workflow. Users had to manually run `nvidia-smi` and `docker run --gpus all ... nvidia-smi`. `--doctor` should make Docker mode and GPU visibility explicit when CUDA-backed Tokamak CLI execution is expected.

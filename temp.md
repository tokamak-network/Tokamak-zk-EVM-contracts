# Private-State CLI UX Review

## Scope

This note records the current UX findings for the `private-state-cli`. The review looked at the command surface, help output, README guidance, argument validation, error handling, workspace behavior, and the Sepolia flow exercised through the CLI.

## Findings

### 1. High: secrets are first-class CLI arguments

Several commands require raw secrets directly in argv:

- `create-channel --private-key <HEX>`
- `deposit-bridge --private-key <HEX>`
- `join-channel --private-key <HEX> --password <PASSWORD>`
- `recover-wallet --private-key <HEX> --password <PASSWORD>`
- `withdraw-bridge --private-key <HEX>`
- wallet commands such as `mint-notes`, `transfer-notes`, `redeem-notes`, `deposit-channel`, `withdraw-channel`, and `exit-channel` require `--password <PASSWORD>`.

This is poor security UX because shell history, terminal scrollback, process inspection, copied commands, and agent logs can expose private keys or wallet passwords.

Recommended improvement:

- Add `--private-key-env <ENV_NAME>`.
- Add `--private-key-file <PATH>`.
- Add `--password-env <ENV_NAME>`.
- Add `--password-file <PATH>`.
- Add an interactive hidden password prompt for local terminal use.
- Keep raw `--private-key` and `--password` only as explicit unsafe or development paths, with a warning in help text.

### 2. Medium: help output is a command catalog, not a guided workflow

The `--help` output lists commands, but it does not explain the user's current state or the next safe action. The README gives a common command sequence, but it is still a list of command names rather than a state-aware flow.

This matters because the CLI is stateful. A user may be in one of several states:

- runtime is not installed
- no channel workspace exists
- channel exists but the user has not joined
- user joined but has no bridge balance
- user has bridge balance but no channel balance
- user has channel balance but no notes
- user has notes and can transfer
- recipient needs to recover received notes
- user needs to redeem, withdraw, or exit

Recommended improvement:

- Add a `status` or `guide` command.
- The command should inspect installed artifacts, local workspaces, wallet metadata, bridge balance, channel balance, notes, and channel registration.
- It should print the next safe command rather than requiring the user to infer it from the full command list.

### 3. Medium: `--doctor` is machine-friendly but not human-friendly

Resolution:

- Implemented `doctor` as a human-readable summary by default.
- Added `doctor --json` for the full machine-readable report.
- Generalized `--json` as the CLI-wide machine-readable output switch.
- Updated CLI help, the browser assistant command builder, and README guidance.

`doctor` previously emitted a large JSON object by default. This was useful for automation, but difficult for a human operator. It could also be confusing when `ok: true` appeared together with verbose Docker or GPU probe failures that were irrelevant because Docker/GPU mode was not requested.

Recommended improvement:

- Make the default output a concise human-readable table.
- Show only pass, fail, and relevant warning rows.
- Include exact installed versions and compatible backend versions.
- Keep the full JSON report behind `--json`.

### 4. Medium: long proof-backed commands need explicit progress phases

Resolution:

- Added progress phases for `deposit-channel`, `withdraw-channel`, `mint-notes`, `transfer-notes`, and `redeem-notes`.
- The phase sequence is `loading`, `proving`, `submitting`, `persisting`, and `done`.
- Commands print human-readable output by default.
- `--json` is now the CLI-wide machine-readable output switch; e2e uses `--json` when it needs structured results.

Proof-backed commands can take tens of seconds or minutes:

- `deposit-channel`
- `withdraw-channel`
- `mint-notes`
- `transfer-notes`
- `redeem-notes`

Internally these commands load workspace state, run Groth16 or Tokamak proof generation, submit an on-chain transaction, wait for a receipt, and update local wallet/workspace state. A user currently sees limited phase-level progress, so a long-running command can look stuck.

Recommended improvement:

- Emit durable progress phases by default.
- Keep the phase set small enough to be readable during normal CLI use.

### 5. Medium-Low: common errors need recovery actions

The current validation errors are generally correct, but many do not tell the user how to recover.

Examples:

- An invalid wallet name reports that the CLI cannot derive the channel name from the wallet, but does not suggest `list-local-wallets`.
- Missing Sepolia RPC configuration should point users to `--rpc-url <URL>` or
  `~/tokamak-private-channels/secrets/<network>/.env` with `RPC_URL=<URL>`.
- Wrong wallet password reports a decrypt failure, but does not tell the user whether `recover-wallet` can help or whether the password is unrecoverable.

Recommended improvement:

- Add actionable `Try:` lines for common failures.
- Examples:
  - `Try: private-state-cli list-local-wallets --network <NETWORK>`
  - `Try: private-state-cli recover-wallet --channel-name <CHANNEL> ...`
  - `If the wallet password is lost, the local L2 key cannot be recovered from the encrypted wallet file.`

## Existing UX Strengths

- The immutable channel policy warning is explicit before channel creation and first channel registration.
- `list-local-wallets` gives useful local wallet metadata and helps users avoid filesystem inspection.
- Wallet flows can auto-recover missing or stale channel workspace data.
- CLI-wide `--json` output is useful for automation and e2e harnesses.
- The CLI checks proof backend compatibility against the channel's immutable verifier snapshot before proof-backed execution.

## Recommended Priority

1. Remove routine secret exposure from argv by adding env/file/prompt inputs.
2. Add a state-aware `status` or `guide` command.
3. Make `--doctor` human-readable by default and move full detail behind `--json`.
4. Add durable progress phases for long proof-backed commands.
5. Improve common error messages with recovery actions.

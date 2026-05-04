# Private-State CLI UX Review

## Scope

This note records the current UX review for `private-state-cli` after the recent
secret-handling, command-shape, guide, JSON-output, progress, and recovery-hint changes.
The review checked the CLI help output, README command flow, current argument validation,
representative command output, and the earlier UX findings that were tracked in this file.

## Current UX Status

Most previously identified issues are resolved:

- Raw `--private-key` and `--password` arguments have been removed from routine user flows.
- L1 signing now uses named local accounts created by `account import`.
- Wallet commands use wallet-local canonical secret files instead of explicit password arguments.
- Commands use non-dash command names such as `install`, `doctor`, and `guide`.
- `doctor` is human-readable by default and keeps the full machine-readable report behind
  `--json`.
- Long proof-backed commands print the durable phase sequence:
  `loading`, `proving`, `submitting`, `persisting`, and `done`.
- Common errors now keep the root error first and append actionable `Try:` recovery hints.
- `guide` exists and can inspect local state, deployment artifacts, network RPC configuration,
  channel workspaces, accounts, wallets, balances, and notes when enough selectors are provided.

## Open Findings

### 1. Medium-Low: package version and changelog do not yet reflect the UX surface change

The private-state CLI package version is still `0.1.9`, while the local code now contains a
large user-facing change set after the deployed/published baseline:

- command normalization
- local account secret flow
- wallet secret source-file flow
- RPC URL persistence
- `guide`
- `get-channel`
- `uninstall`
- global `--json`
- human-readable `doctor`
- progress phases
- error recovery hints

Why this matters:

- Consumers need a package version that clearly signals the changed command contract.
- The package changelog currently lists some changes under `Unreleased`, but it does not yet
  summarize the full UX migration as a release-ready entry.

Recommended improvement:

- Bump the private-state CLI package version before publishing the new UX.
- Convert the CLI changelog `Unreleased` section into a dated version section.
- Include all command-contract changes in that entry so package consumers know what changed.

## Resolved Historical Findings

### A. Wallet secret source file creation was underspecified

Status: Resolved.

`join-channel` requires `--wallet-secret-path <PATH>`, but help text did not tell a user how
to create a source wallet-secret file. It only said the option imports an existing source file.

Why this mattered:

- A new user cannot join a channel until they create this source file.
- The CLI intentionally removed raw password arguments and interactive wallet initialization, so
  the non-interactive source-file path must be obvious.
- This CLI is intended to be usable by LLM agents, and agents need a precise command recipe.

Resolution:

- Added a `Wallet Secret Source File` section to the CLI README.
- Added the same source-file recipe to `private-state-cli --help`.
- Documented that the source file is arbitrary high-entropy secret text read once by
  `join-channel`.
- Added the concrete command recipe:

```bash
openssl rand -hex 32 > ./wallet-secret.txt
private-state-cli join-channel --channel-name <CHANNEL> --network sepolia --account <ACCOUNT> --wallet-secret-path ./wallet-secret.txt
```

- Clarified that the import source file does not need `0600`, while the canonical wallet-local
  secret written by the CLI remains protected.

### B. `guide` default output was too close to raw JSON

Status: Resolved.

`guide` should be the primary state-aware UX command, but its default human-readable output
previously printed large `Checks` and `State` objects as inline JSON before the more useful
`Next Safe Action` section. This made the command look like a diagnostic dump instead of a
workflow guide.

Why this mattered:

- Users and LLM agents run `guide` when they do not know the next safe action.
- The most important information is the next command, the reason, and a small set of blocking
  checks.
- Full local state is useful for automation and debugging, but it should live behind `--json`.

Resolution:

- Added a `guide`-specific human output formatter.
- Default `guide` output now shows selected network/channel/account/wallet, concise check rows,
  `Next Safe Action`, `Why`, and candidate commands.
- The full `state` object remains available through `guide --json`.

### C. Invalid wallet selectors made `guide` fail instead of guiding

Status: Resolved.

Running `guide --network <NAME> --wallet <BAD_NAME>` previously failed before emitting a guide
result when the wallet name did not match the deterministic `<channelName>-<l1Address>` shape.
The global error formatter appended useful `Try:` lines, but this was inconsistent with the
purpose of `guide`.

Why this mattered:

- `guide` should absorb incomplete or invalid local selectors and report them as checks.
- A hard failure made the command feel like a normal validator rather than a recovery assistant.

Resolution:

- `guide` now catches malformed wallet selector errors during local-state inspection.
- The error is emitted as a `wallet selector` check with `error` status.
- When a network is selected, the next safe action becomes
  `list-local-wallets --network <NETWORK>`.
- Unexpected internal failures can still surface as hard command failures.

### D. Secrets as first-class CLI arguments

Status: Resolved.

The earlier CLI required raw `--private-key` and `--password` values in command arguments. That
exposed secrets through shell history, terminal scrollback, process lists, copied commands, and
agent logs.

Resolution:

- Routine L1 signing commands now use `--account`.
- `account import --private-key-file` imports a source private key into a protected canonical
  local account secret.
- Wallet commands no longer accept explicit password arguments.
- `join-channel` imports a wallet secret source file into the protected wallet-local canonical
  secret.
- Canonical CLI secret files remain protected with POSIX `0600` or Windows ACL repair and
  inspection where possible.

### E. Help output as only a command catalog

Status: Resolved.

Resolution:

- Added `guide`.
- Updated README command flow.
- Added actionable recovery hints to common errors.

### F. `doctor` was machine-friendly but not human-friendly

Status: Resolved.

Resolution:

- `doctor` prints a concise human-readable table by default.
- `doctor --json` prints the full machine-readable report.
- CLI-wide `--json` is now the structured-output switch.

### G. Long proof-backed commands lacked durable progress phases

Status: Resolved.

Resolution:

- `deposit-channel`, `withdraw-channel`, `mint-notes`, `transfer-notes`, and `redeem-notes`
  print `loading`, `proving`, `submitting`, `persisting`, and `done`.
- In `--json` mode, progress goes to stderr and the final JSON result stays on stdout.

### H. Common errors lacked recovery actions

Status: Resolved enough for current UX.

Resolution:

- Added centralized error formatting with `Try:` hints for common failures.
- Covered missing RPC configuration, unknown or malformed wallet selectors, missing wallet
  default secret files, wallet decrypt failures, missing account secrets, missing deployment
  artifacts, missing channel registrations, and missing channel selectors.

## Recommended Priority

1. Bump the private-state CLI package version and finalize its changelog before publishing.

# Private-State / Tonnel Release Readiness Plan

This file tracks only the current release-readiness state. Historical execution logs, obsolete draft Terms text, and
completed runbooks have been removed from this working plan.

## Current Scope

The current release-readiness work covers:

- Tonnel and the Private-State DApp user-facing Terms and Privacy Notice.
- Private-State CLI install-time Terms acceptance.
- Human-readable and JSON-mode CLI guidance.
- Mainnet bridge governance and Channel-scoped observer metadata.
- Public documentation consistency for ordinary users, legal or compliance reviewers, and User-Controlled AI Agents.

## Current Decisions

- Provider: Jehyuk Jang.
- Provider public privacy and notice contact: `cjhyuck213@gmail.com`.
- Provider stated jurisdiction: Singapore.
- Provider residential address: not published.
- Tokamak Network PTE. LTD.: separate software contributor/licensor where applicable, not the Provider under the current
  Terms.
- Governing law and forum: Singapore, subject to non-waivable user rights under applicable law.
- Arbitration and class-action waiver: not included.
- Liability cap: no nominal monetary cap; use liability exclusions to the maximum extent permitted by applicable law
  with non-waivable liability carveouts.
- Terms acceptance: explicit browser-based human acceptance for install and renewed acceptance. User-Controlled AI Agents
  and automation must not accept Terms for the user.
- `--acknowledge-action-impact`: removed from command policy. Install-time Terms acceptance replaces per-command legal
  acknowledgement flags.
- Sensitive/destructive flows: `uninstall`, secret-bearing exports, and plaintext note or evidence exports require
  interactive human confirmation.
- Real-funds commands: print concise warning summaries in human and JSON modes.
- Bridge root owner: Safe multisig `0xBE637160D21975EF1e0270D32Bfc547c2EA8DcC3`, 2-of-3 threshold, no timelock.
- Channel observer URL policy: observer URLs are Channel-scoped and must be read from on-chain Channel metadata by CLI
  and monitoring tools, not hardcoded as Tonnel-wide defaults.
- Terms audience: ordinary non-developer users and judicial or regulatory readers. Terms must provide only legally
  necessary information; implementation and operation details belong in README, CLI help, observer docs, and Monitoring
  Packet docs.

## Completed

### Terms and Privacy Documents

- Public Terms were minimized for ordinary users and judicial or regulatory readers.
- Packaged CLI Terms asset matches the public Terms.
- Terms version is `2026-06-12`.
- Terms no longer include specific Channel observer URLs, specific Channel names, burn addresses, Solidity getter names,
  CLI command names, Monitoring Packet details, runtime/artifact details, repository details, or other excessive
  implementation and operation details.
- Terms still preserve the legal disclosures needed for Service scope, Self-Custody, no recovery method, public Ethereum
  mainnet records, privacy limits, prohibited use, third-party services, no professional advice, risk disclosures, no
  warranties, liability limitation, indemnity, renewed acceptance, governing law, venue, and notices.
- Privacy Notice exists at `docs/dapps/private-state/privacy-notice.md`.
- CLI README references the Privacy Notice. `tonnel.io` publication is deferred.

### CLI Install and Guidance

- Install opens a local browser Terms page by default.
- Browser Terms page renders the packaged Markdown Terms as styled HTML.
- Browser Terms acceptance does not require TTY, allowing a User-Controlled AI Agent to run install while the user clicks
  acceptance in the browser.
- `install --read-only --include-local-artifacts` discovers all local `deployment/chain-id-*` artifacts for the selected
  DApp and records the final installed artifact source once per chain. Local artifacts override Drive artifacts for the
  same chain during local release-readiness checks.
- `install --json` does not install, does not accept Terms, and reports that browser-based human acceptance is required.
- Human install output has a concise final summary instead of JSON blobs.
- Human install output reports step counts and elapsed time after Terms acceptance.
- Generic human-mode result fallback renders nested objects and arrays as readable text instead of raw JSON.
- Successful managed runtime installation subprocesses are quiet; failure diagnostics retain captured stdout/stderr.
- `help guide --json` points User-Controlled AI Agents to `agents.md` and Terms references instead of embedding full
  legal text.

### Bridge Governance

- Root bridge proxy ownership was migrated from a single EOA to the Safe multisig.
- `BridgeCore`, `DAppManager`, and `L1TokenVault` owners are the Safe multisig.
- Current public monitoring artifacts disclose the Safe owner, 2-of-3 threshold, and no-timelock status.
- Old single-EOA owner posture is no longer the current governance state.

### Bridge and Observer Model

- Bridge upgrade adding Channel-scoped observer URL registry was executed.
- The Great First Channel observer URL registration was completed on-chain.
- CLI no longer uses a Tonnel-level hardcoded observer URL for `help observer`.
- `help observer` requires network and Channel selectors and reads the selected Channel observer URL from on-chain
  Channel metadata.
- Stale installed read-only ABI now produces a clear reinstall-required error instead of an internal TypeError.
- Monitoring Packet generation includes Channel observer URL data read from on-chain state.
- Local read-only deployment artifacts were refreshed from the repository-local deployment artifacts. Mainnet now uses
  local bridge artifacts from `deployment/chain-id-1/bridge/20260611T091000Z`.
- Human `help observer --network mainnet --channel-name the-great-first-channel` prints
  `https://observer.tonnel.io` from on-chain Channel metadata.
- JSON `help observer --network mainnet --channel-name the-great-first-channel --json` returns the same URL with source
  `on-chain channel metadata`.
- JSON `help observer` for an unknown mainnet Channel returns a structured `UNKNOWN_CHANNEL` error.
- The external observer implementation was reported complete by its developer:
  - new bridge event ABI support,
  - Channel operation status display,
  - Join Toll burn-address transfer semantics display,
  - production smoke verification,
  - lint/test/build pass.

## Remaining Work

### 1. Final Public-Document Consistency Review

Run a final review after the Terms minimization and local artifact refresh.

Check:

- Terms still cover every relevant `checklist.md` item.
- Terms, Privacy Notice, CLI README, human `help guide`, `help guide --json`, `agents.md`, observer docs, and Monitoring
  Packet docs do not conflict.
- Public documents do not expose unnecessary implementation or operation detail in ordinary-user Terms.
- Technical details removed from Terms remain available where needed in README, CLI help, observer docs, and Monitoring
  Packet docs.
- Human-facing wording is appropriate for ordinary users and legal or compliance reviewers.
- JSON-mode and agent-facing guidance remains useful for User-Controlled AI Agents without handling secrets or accepting
  Terms for users.

### 2. Final Release Readiness Verification

After the document consistency review:

- Run CLI agent-guidance tests.
- Run relevant command smoke checks for `install --json`, human help, JSON help, and `help observer`.
- Run public Terms / packaged Terms consistency check.
- Run whitespace checks.
- Commit all resulting changes.

## Deferred, Not Current Blockers

- Far-future counsel review of governing law, forum, consumer-law carveouts, sanctions wording, limitation of liability,
  arbitration/class-action strategy, and privacy notice sufficiency.
- Future publication of Privacy Notice on `tonnel.io`.
- Any future timelock, guardian, emergency council, pause mechanism, or governance redesign.
- Any future named restricted-jurisdiction or named sanctions-list policy.

## Next Recommended Order

1. Run final public-document consistency review.
2. Run final release-readiness verification.

# Private-State CLI Install-Time Terms Plan

## Goal

Move private-state CLI terms acknowledgement from per-command action-impact flags to an install-time, interactive terms
acceptance flow.

The new flow should reduce repeated user friction while preserving the checklist goals:

- explain that TON remains a transparent L1 asset,
- explain that private-state channels are opt-in DApp state, not an exchange deposit network,
- disclose what is public and what is private,
- prohibit illegal use,
- warn about secret-loss and self-custody risk,
- state channel operator and developer limitations,
- make AI agents explain required warnings before guiding users.

This plan does not treat the text below as legal advice or a final legal agreement. Final production wording should be
reviewed by counsel.

## Checklist Review Conclusion

The repository `checklist.md` does not clearly require per-command acknowledgement. It requires consistent public
messaging and user-facing disclosures about:

- transparent L1 entry and exit,
- opt-in private-state DApp usage,
- public monitoring surfaces,
- internal note-transfer privacy limits,
- illegal-use prohibition,
- no operator possession of user secrets,
- user responsibility for selective disclosure and secret preservation.

Therefore, replacing command-level acknowledgement with one interactive install-time terms acceptance does not clearly
violate `checklist.md`, provided the install-time terms include these disclosures and the AI guidance path still makes
users aware of them.

## Human Install Strategy

`private-state-cli install` should become an interactive command.

### Required behavior

1. Before installing artifacts or runtimes, print the current terms text.
2. Require the user to confirm acceptance in the terminal.
3. Do not accept terms through a silent default, environment variable, config file preseed, or AI-provided answer.
4. After acceptance, persist a local terms acceptance record.
5. Continue installation only after the local acceptance record is written.
6. If the terminal is non-interactive, stop and tell the user to run `private-state-cli install` directly in an
   interactive terminal.

### Confirmation phrase

Use an exact phrase so accidental enter/yes does not count:

```text
I AGREE TO THE PRIVATE-STATE CLI TERMS
```

### Acceptance record

Store a local record under the private-state CLI data root, for example:

```text
~/tokamak-private-channels/terms/private-state-cli-terms.json
```

Suggested fields:

- `termsVersion`
- `termsHash`
- `acceptedAt`
- `cliVersion`
- `acceptedCommand`
- `humanConfirmationRequired: true`

The terms hash should change whenever the terms text materially changes. If the installed CLI sees a missing or outdated
terms record, `install` should show the current terms again and require acceptance again.

## JSON / AI Agent Strategy

`--json` mode is for the user's AI agent, not for replacing the user's informed consent.

### Purpose of JSON mode

JSON mode should provide machine-readable state and instruction references so an AI agent can help the user complete the
minimum safe next action without asking for secrets or forcing the user to understand private-state internals first.

### Install behavior in JSON mode

`private-state-cli install --json` should not silently accept terms or perform install when terms are missing.

Instead, it should return a structured result that tells the agent:

- terms acceptance is required,
- the user must run interactive `private-state-cli install` directly,
- the agent must explain the required warnings, prohibitions, and disclaimers before asking the user to continue,
- the agent must not type the confirmation phrase for the user,
- the agent must not ask for secrets or provider dashboard access.

Suggested JSON shape:

```json
{
  "ok": false,
  "action": "install",
  "requiresTermsAcceptance": true,
  "terms": {
    "source": "private-state-cli install",
    "version": "<TERMS_VERSION>",
    "hash": "<TERMS_HASH>",
    "interactiveCommand": "private-state-cli install"
  },
  "agentGuidance": {
    "source": "agents.md",
    "refs": ["<TERMS_GUIDANCE_REF>"]
  },
  "nextSafeAction": "Ask the user to run private-state-cli install in an interactive terminal after explaining the terms."
}
```

The exact JSON field names can follow existing CLI conventions, but the semantic requirements above should remain.

### AI agent obligations

When JSON output says terms acceptance is required, the agent must explain:

- transparent L1 bridge entry and exit,
- private-state note privacy limits,
- illegal-use prohibition,
- user self-custody and secret-loss responsibility,
- channel operator limitations,
- developer/operator disclaimers,
- that accepting terms is the user's action and cannot be completed by the AI.

The agent should then ask the user to run:

```bash
private-state-cli install
```

The agent should not append any acceptance flag and should not simulate terminal confirmation.

## Terms Content Draft

The install-time terms should cover the following sections.

### 1. Product boundary

- TON remains a transparent L1 asset.
- Tokamak Private App Channels do not change TON L1 transfer rules.
- The private-state DApp is an opt-in application channel used after the user moves assets to a self-custody L1 wallet.
- The channel is not an exchange deposit or withdrawal network.
- Private-state notes are channel-local application state, not a separate exchange-depositable asset.

### 2. Public and private information

The terms should disclose that the following can be public or observable:

- L1 bridge deposits and withdrawals,
- channel creation,
- channel join and L1/L2 registration events,
- note-receive public key registration,
- channel accounting updates,
- note commitments, nullifiers, encrypted note-delivery events, accepted transitions, and root updates,
- L1 transaction sender, gas payer, transaction hash, timing, and amounts where applicable.

The terms should also disclose that public observers generally cannot reconstruct the internal note sender-recipient
relationship, note plaintext, or note provenance by default.

### 3. Illegal-use prohibition

The user must agree not to use the CLI, private-state DApp, bridge, channel, or note system for:

- money laundering,
- terrorist financing,
- sanctions evasion,
- regulatory evasion,
- illegal gambling,
- fraud,
- criminal-proceeds concealment,
- market manipulation,
- exchange monitoring evasion,
- any unlawful purpose in the user's jurisdiction.

### 4. Self-custody and secret responsibility

The terms should state:

- users control their own Ethereum accounts and wallet secrets,
- developers and channel operators do not hold user private keys, wallet secrets, seed phrases, viewing keys, or spending
  keys,
- lost secrets may prevent note discovery, note use, wallet recovery, or selective disclosure,
- the CLI cannot recover lost secrets,
- users should preserve private-key source files, wallet-secret source files, backups, and evidence files safely.

### 5. Channel policy and operator limitations

The terms should state:

- joining a channel means accepting that channel's policy snapshot,
- channel terms can include join tolls, refund schedules, operator roles, or recovery-source expectations,
- channel operators may provide registered recovery sources or public metadata, but they do not guarantee recovery of
  user secrets,
- channel operators cannot make private notes visible to public observers unless the protocol or user-selected
  disclosure flow exposes the relevant data,
- users should inspect channel policy before joining.

### 6. Developer and operator disclaimers

The terms should state:

- software is provided without a guarantee of profit, availability, uninterrupted operation, regulatory treatment, or
  exchange support,
- developers and operators do not provide legal, tax, accounting, compliance, or investment advice through the CLI,
- users are responsible for determining whether their use is lawful,
- users are responsible for transaction fees, failed transactions, incorrect parameters, wrong-network use, and lost
  secrets,
- developers and operators are not responsible for third-party RPC providers, wallets, exchanges, explorers, or channel
  operators outside their control.

### 7. Monitoring, evidence, and selective disclosure

The terms should state:

- L1 and public channel events may be monitored by exchanges, analytics providers, regulators, or other observers,
- users may need to preserve local evidence if they later need to explain source of funds or transaction history,
- selective disclosure depends on the data the user preserved and the features actually implemented,
- the system should not be described as hiding exchange-facing TON transfer records.

### 8. Updates to terms

The terms should state:

- future CLI versions may update terms,
- material terms changes require renewed acceptance,
- continued use after renewed acceptance means the user agrees to the updated terms.

## Implementation Plan

### Phase 1: Terms source and rendering

1. Add a canonical terms text source shipped with the CLI package.
2. Add a terms version and deterministic hash.
3. Add a renderer for human terminal output.
4. Add a compact terms summary for JSON mode.

### Phase 2: Acceptance persistence

1. Add helpers for reading and writing the local terms acceptance record.
2. Include `termsVersion`, `termsHash`, `acceptedAt`, and `cliVersion`.
3. Treat missing, malformed, or stale records as not accepted.
4. Do not store secrets in the acceptance record.

### Phase 3: Interactive install gate

1. At the start of `private-state-cli install`, check terms acceptance.
2. If missing or stale, print terms and ask for the exact confirmation phrase.
3. If accepted, write the acceptance record and continue install.
4. If rejected or mismatched, stop before installing.
5. If non-interactive, fail with a clear message telling the user to run interactive install.

### Phase 4: JSON / AI agent flow

1. In `install --json`, return structured terms-required output instead of prompting.
2. Add `agentGuidance` refs for terms explanation and consent boundaries.
3. Update `agents.md` so agents must explain warnings, prohibitions, and disclaimers before directing the user to
   interactive install.
4. Explicitly forbid agents from accepting terms for the user.

### Phase 5: Command acknowledgement cleanup

1. Remove `--acknowledge-action-impact` requirements from transaction-sending commands only after install-time terms are
   enforced.
2. Keep concise non-blocking action-impact summaries where useful, especially for transaction-sending commands.
3. Keep separate handling for high-risk exports such as full note plaintext evidence unless terms replacement is
   explicitly approved for that flow.
4. Update command registry, help text, README examples, and agent recipes.

### Phase 6: Tests

Add tests for:

- interactive install refuses to continue on mismatched confirmation,
- interactive install writes the acceptance record on exact confirmation,
- stale terms hash requires renewed acceptance,
- non-interactive install fails clearly when terms are missing,
- `install --json` returns structured terms-required output,
- transaction commands no longer require `--acknowledge-action-impact` only after accepted terms are present,
- README and `agents.md` explain the JSON-mode agent obligation.

Tests should avoid live RPC and should not require private keys or wallet secrets.

## Open Decisions

- Final legal wording and governing-law language.
- Whether `install --json` should use `ok: false` or `ok: true` with `requiresTermsAcceptance: true`.
- Whether full note plaintext export keeps a separate acknowledgement even after install-time terms.
- Whether uninstall should remove the terms acceptance record.
- Whether package upgrades should always require renewed acceptance or only when the terms hash changes.

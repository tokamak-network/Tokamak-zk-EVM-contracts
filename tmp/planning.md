# Private-State CLI Guide and Agent Instruction Plan

## Current Implementation Status

This document is now a status-tracking plan. The implementation has started, but the full plan is not complete.
Keep this file until every item in "Started but incomplete" and "Not started" is resolved or intentionally removed from
scope.

### Completed

- Retired `cli-assistant.html`; the implementation does not restore or replace it.
- Kept `help guide` as the single state-aware guidance command; no `help onboard` command was added.
- Added `agentGuidance` to `help guide --json` with `source: "agents.md"`, a symbolic `step`, and `refs`.
- Removed human-only guide prose fields such as `why`, `privacyTip`, and `mirrorTip` from `help guide --json` output.
- Previously added `Agent Guidance` source and refs to the human-readable `help guide` output, then removed them from
  the human renderer when the target was narrowed to non-specialist people.
- Added `secret create-private-key-source --output ./ethereum-private-key.txt`.
- Added `secret create-wallet-secret-source --output ./wallet-secret.txt`.
- Added explicit opt-in random wallet secret creation with `secret create-wallet-secret-source --random`.
- Implemented masked terminal input with `*` display for typed secret helpers.
- Implemented helper file safety: no secret printing, restrictive file permissions where supported, no overwrite by default,
  and clear non-interactive terminal failure.
- Made wallet secret setup default to user-entered secret text instead of random generation.
- Updated missing-RPC guide output to recommend `set rpc --network mainnet --rpc-url <URL> --provider ankr` for ordinary
  users without a provider preference.
- Preserved the rule that the CLI has no default RPC URL.
- Reoriented user-facing setup examples toward mainnet for ordinary users and Sepolia only for explicit test/developer
  use.
- Reworked `agents.md` toward indexed, action-first guidance and Ethereum wallet/account/address language.
- Aligned this plan's proposed `agents.md` index structure with the implemented indexed recipe structure used by
  `help guide --json`.
- Aligned this plan's `help guide --json` reference mapping with the implemented runtime `agentGuidance.refs` mapping.
- Rewrote `agents.md` indexed items with explicit recipe fields: `Goal`, `When to use`, `Minimal user actions`,
  `AI may ask`, `AI must not ask`, `Command template`, `Success check`, `Failure recovery`, and
  `Optional explanation`.
- Completed recipe-field coverage for the private-key source/account-import path, wallet-secret/channel-join path, and
  RPC setup path, including unlisted-provider scan-limit guidance.
- Restored indexed `agents.md` operating recipes for fee/cost questions, JSON stdout/stderr handling, CLI `Try:` hint
  priority, stale proof recovery, and `UnexpectedCurrentRootVector()` handling.
- Started reworking human `help guide` output for non-specialist users by removing AI refs, global privacy tips, and
  global mirror tips, then adding plain next-step guidance per guide step.
- Reworked human `help guide` output into the action-first structure from the audit plan: `Current status`,
  `Next step`, `Run this command`, and `After it succeeds`, with one primary `private-state-cli ...` command and no
  default `Checks`, `Candidate Commands`, or AI-only JSON guidance.
- Updated the README `LLM Agent Guidance` section to direct agents through `help guide --json`,
  `agentGuidance.source`, `agentGuidance.refs`, and the referenced `agents.md` recipes.
- Updated CLI help text, README setup examples, and changelog entries for the new helper commands and guide direction.
- Added focused tests for no-network guide refs, missing-RPC guide refs, random wallet-secret helper behavior, overwrite
  refusal, and non-TTY private-key helper failure.
- Added an isolated test fixture strategy for post-RPC guide states: tests create `rpc-config.env` directly under a
  temporary HOME instead of reading local user RPC settings or running `set rpc`.
- Added a `help guide --json` test for deployment artifacts missing after RPC is already configured.
- Added a read-only artifacts fixture and `help guide --json` test for account secret missing after RPC and artifacts
  are already available.
- Added a `help guide --json` test for wallet missing before `channel join` using a deterministic wallet selector and
  the isolated RPC/artifacts fixtures.
- Manually verified the private-key helper in a pseudo-terminal for `*` masking, no secret transcript leak, output file
  creation, and `0600` file mode on macOS.

### Started but incomplete

- The test suite checks some guide refs and helper safety behavior, but it does not cover the full guide-state matrix
  listed in Phase 6.
- The tests verify that emitted refs exist in `agents.md` for covered guide states, but they do not verify the full recipe
  field contract.
- Helper command tests cover random wallet-secret behavior and non-TTY private-key failure; typed private-key masking was
  manually verified but is not automated in the test script, and typed wallet-secret masking is not automated.
- Human `help guide` has the action-first layout, but the latest audit still found non-specialist wording gaps in RPC,
  recovery, funding, note-use, and acknowledgement explanations.
- Human `help guide` still needs follow-up refinement for the private-key import path: after creating the source file and
  importing the account, the human flow should also show the `account get-l1-address` verification step.
- Human `help guide` explains `*` masking for private-key source creation, but not for wallet-secret source creation.
- Human `help guide` still presents channel creation as a primary command when the selected channel does not exist; it
  needs a stronger channel-creator gate so ordinary joiners do not create channels accidentally.

### Not started

- Add `help guide --json` tests for existing channel workspace missing.
- Add `help guide --json` tests for existing wallet with missing channel registration.
- Add `help guide --json` tests for acknowledgement-required next actions.
- Add documentation/structure tests that every first-time setup ref includes the required recipe fields.
- Add documentation/structure tests that the account-import recipe includes an `account get-l1-address` success check.
- Add documentation/structure tests that the wallet-secret/channel-join recipe defaults to user-entered secret creation
  and keeps random generation as explicit opt-in.
- Add documentation/structure tests that the RPC recipe recommends Ankr and includes the `set rpc --provider ankr`
  command template.
- Add documentation/structure tests that recipe `AI must not ask` lists include private keys, wallet secrets, seed
  phrases, provider passwords, and provider dashboard access where relevant.
- Automate typed masked-input tests for `secret create-private-key-source`.
- Automate typed masked-input tests for `secret create-wallet-secret-source`.
- Add tests for the fee/cost question flow indexed `agents.md` instructions.
- Add tests for stale proof and `UnexpectedCurrentRootVector()` indexed `agents.md` instructions.
- Rewrite the human RPC guide wording to avoid specialist-first terms such as `RPC endpoint`, `recovery`, and
  `log scanning`; explain it as an Ethereum connection URL and only mention the fast history-check reason for Ankr.
- Add the `account get-l1-address` verification command to the human private-key/account-import follow-up flow.
- Add `*` masking wording to the human wallet-secret source guide.
- Rework the human channel-create guide so the first action is confirming the user is the channel creator; only then
  show channel creation as the command to run.
- Reword human recovery guidance to avoid leading with `workspace mirror`, `RPC logs`, or `local workspace`; frame it as
  restoring this computer's channel data with a fast registered source or a slower rebuild.
- Reword human funding, channel funding, minting, note use, and exit guidance around the plain money flow:
  public deposit -> channel balance -> private notes -> transfer/redeem -> exit only after channel balance is zero.

## Human Help Guide Audit and Remediation Plan

### Target user

Human `help guide` is for non-developer, non-specialist end users. It is not for AI agents, scripts, protocol
developers, channel operators, or people already familiar with private-state internals. The output should help a person
understand:

- what is currently missing,
- what they should do next,
- why that action is needed,
- the exact command to copy,
- what value they must replace, if any,
- what should happen after the command succeeds.

### Current problems found

1. The output still uses diagnostic structure first. Sections such as `Checks` expose internal terms before the user sees
   a practical explanation.
2. The check lines are not translated for non-specialists. Terms such as `local private-state workspace`,
   `deployment artifacts`, `Chain Id`, `MISSING_RPC_URL`, `workspace`, `mirror`, and `RPC logs` appear without enough
   context or should be hidden unless the situation needs them.
3. Commands are not always complete copy-paste commands. Human output currently prints command bodies such as
   `set rpc ...` instead of `private-state-cli set rpc ...`.
4. `Candidate Commands` can duplicate the main command or present alternatives without explaining when to use them.
   That is confusing for a person who wants one next action.
5. The closing `Use --json only when an AI or script needs the full state.` is not relevant to a human setup guide and
   should be removed from ordinary human output.
6. Some next-step explanations still rely on specialist terms such as `RPC endpoint`, `log scanning`, `workspace
   mirror`, `channel balance`, `unused private notes`, `note IDs`, and `action-impact warning` without plain-language
   framing.
7. The private-key step does not yet fully explain the human risk and flow: the key controls the Ethereum wallet, the
   user should type it only into the terminal prompt, the helper creates `./ethereum-private-key.txt`, and the next
   command imports that file.
8. The wallet-secret step does not yet explain the human purpose clearly enough: it creates a recoverable secret file
   for the channel wallet, should normally be user-entered, and should be preserved before joining.
9. Channel creation and channel join guidance assumes the user understands channel policy, join toll, and
   acknowledgement language. It needs to explain those as concrete consequences.
10. Recovery guidance exposes `workspace mirror` and `RPC logs` too early. It should say whether there is a faster
    recovery source or a slower rebuild path, then show the command.
11. Funding, channel funding, minting, transfer, and exit guidance uses domain terms without enough sequencing context.
    It should explain the money flow in plain language: bridge deposit -> channel balance -> private notes -> transfer or
    redeem.
12. The current renderer treats all steps with one generic layout. Some steps need different layouts: setup steps need
    "What you need", "What to do", and "After this"; warning steps need "Before you run this"; recovery steps need
    "Fast path" versus "Slow path".

### Remediation principles

- Keep `Selectors` as-is because it is already part of the current output and the user explicitly asked not to rename it.
- Remove AI-only or script-only text from human output.
- Hide or translate internal diagnostics in human output. Preserve full details in `--json`.
- Show exactly one primary copyable command for the next action.
- Prefix human commands with `private-state-cli`.
- Show alternatives only when the user must choose, and explain the choice in plain language.
- Use placeholders only for values the user must replace, and state what each placeholder means.
- Explain "why" only as much as needed to make the next action safe.
- Do not introduce mirror, tx submitter, proof, workspace, or note internals unless the current state requires them.
- Keep acknowledgement guidance concrete: "this may send a public Ethereum transaction or accept channel terms; read the
  warning shown by the CLI before continuing."

### Output structure to implement

Replace the current human guide body after `Selectors` with:

```text
Current status
- <plain-language status line>

Next step
<two or three plain-language sentences>

Run this command
private-state-cli ...

After it succeeds
<one short follow-up sentence or command>
```

Do not show `Candidate Commands` by default. If alternatives are required, use:

```text
If this does not match your situation
- <alternative and when to use it>
```

### Situation-specific guidance requirements

- `select-network`: explain mainnet for real use and Sepolia/anvil only for test/developer use. Show
  `private-state-cli help guide --network mainnet`.
- `configure-rpc`: say the CLI needs an Ethereum connection URL. Say Ankr is recommended, not default, because its free
  plan is fast for this CLI's history/recovery checks. Ask the user to create or choose an endpoint and copy only the
  endpoint URL.
- `install-runtime`: explain that required local CLI files are missing. Show `private-state-cli install`, then tell the
  user to run `private-state-cli help doctor`.
- `create-private-key-source-and-import-account`: explain that the Ethereum private key controls the wallet and must be
  typed only into the terminal prompt. Show the helper command first. Show the account import command as "After it
  succeeds", not as a mixed inline sentence.
- `create-wallet-secret-source-and-join-channel`: explain that the file is for the channel wallet and may be needed for
  future recovery. Default to user-entered password/passphrase. Mention random only as an explicit alternative.
- `create-channel`: explain that only the channel creator should run it and that the action fixes channel terms and may
  require a join toll. Do not assume ordinary users should create channels.
- `recover-channel-workspace`: explain "this computer needs a local copy of channel data". If mirror is available, call
  it a faster registered recovery source. If not, call RPC rebuild a slower fallback.
- `join-channel-with-existing-wallet-secret-source`: explain the wallet is not registered for the channel yet and that
  joining may send a public Ethereum transaction.
- `fund-bridge`: explain this is the first public deposit step and does not create private notes.
- `fund-channel`: explain funds are in the bridge but not yet available inside the channel wallet.
- `mint-notes`: explain minting converts channel balance into private notes that can be transferred or redeemed.
- `use-notes`: explain the user must inspect available notes first and can only transfer or redeem notes that exist.
- `exit-channel`: explain exit only when the channel wallet has no remaining channel balance.
- `discover-wallet-name`: explain that the command lists saved local wallet names and the user should choose one from
  the output.
- `collect-selectors`: ask only for known public values; do not imply they are saved defaults or registry values.

### Test plan

- Add human-output snapshot or assertion tests for at least:
  - no network selected,
  - missing RPC,
  - missing account secret,
  - missing wallet before join,
  - mirror recovery,
  - RPC rebuild recovery,
  - bridge funding,
  - note use readiness.
- Assert human output does not contain AI-only terms: `Agent Guidance`, `Refs`, `--json only when an AI`, `JSONL`,
  `MISSING_RPC_URL`, or raw internal error codes.
- Assert primary human commands include the `private-state-cli` prefix.
- Assert irrelevant global tips are absent.
- Assert Ankr text says "recommended" and "not a default".
- Assert private-key and wallet-secret human guidance never tells users to paste secrets into chat or messages.

## Scope

This plan tracks the user-experience improvement direction and the remaining implementation work.
The CLI assistant HTML is retired and must not be part of the plan.
No new `help onboard` command should be introduced unless a future requirement proves that `help guide` cannot reasonably cover the onboarding use case.

The primary entrypoint for user-facing AI guidance should be:

```bash
private-state-cli help guide --json
```

The purpose is to let a user's AI read structured guide output first, then follow indexed references into `agents.md` for detailed operating rules.

## Design Goals

1. Keep `help guide` as the single state-aware guidance command.
2. Categorize `agents.md` into stable numbered sections that AI agents can cite and follow.
3. Add stable item identifiers to each actionable instruction in `agents.md`.
4. Extend `help guide --json` planning output so each recommended action references only the relevant `agents.md` item identifiers.
5. Do not hardcode human guidance text in `help guide --json`; the JSON output must carry indexes, not guidance prose.
6. Keep human-readable `help guide` allowed to print concise hardcoded guidance text derived from the same guide step mapping.
7. Make `agents.md` optimize for minimal user knowledge and minimal user action during setup.
8. Treat concept definitions as secondary help that the AI provides only when the user asks or appears confused.
9. Preserve safe secret-handling boundaries: the AI must not ask for raw private keys, wallet secrets, seed phrases, provider passwords, or dashboard credentials.

## Proposed `agents.md` Index Structure

Each indexed item that participates in first-time setup should be written as an action recipe, not as a loose rule.
The item should be short enough for an AI agent to follow quickly, but concrete enough that the AI can move the user to
the next command without asking the user to understand private-state internals first.

Required recipe fields for setup-related items:

- `Goal`: the user-visible setup outcome.
- `When to use`: the guide state or user situation that activates the item.
- `Minimal user actions`: the fewest actions the user must take outside the CLI.
- `AI may ask`: only the values the AI needs to assemble the next safe command, such as a local file path or endpoint URL.
- `AI must not ask`: secrets or credentials that must not be pasted into chat.
- `Command template`: one copyable command or the smallest possible command sequence.
- `Success check`: the follow-up command or output field that confirms the step is complete.
- `Failure recovery`: the first corrective action when the command fails.
- `Optional explanation`: a short concept explanation used only when the user asks what the thing is or appears confused.

### A. Operating Rules

- `A.1` Action-first setup: move the user to the next safe setup action with minimal required knowledge and use ordinary user language such as "Ethereum account" or "Ethereum address".
- `A.2` Secret handling: keep private keys, wallet secrets, seed phrases, and provider credentials local to the user's terminal and filesystem.
- `A.3` JSON guidance contract: treat `help guide --json` as a routing layer from current CLI state to indexed `agents.md` recipes.

### B. Secret Source Recipes

- `B.1` Create a private key source file with the short masked-input helper and default path `./ethereum-private-key.txt`.
- `B.2` Import the Ethereum account alias from the private key source file.
- `B.3` Verify the imported Ethereum address with `account get-l1-address`.
- `B.4` Create a wallet secret source file with the short masked-input helper and default path `./wallet-secret.txt`.
- `B.5` Use random wallet secret generation only as an explicit opt-in path.
- `B.6` Remind the user to preserve the wallet secret source without revealing it.
- `B.7` Join a channel with the prepared wallet secret source only after policy and action-impact review.

### C. RPC Setup Recipes

- `C.1` Confirm the target network, using mainnet for ordinary users unless they explicitly choose test/developer use.
- `C.2` Recommend Ankr for users without an existing provider preference without treating it as a default RPC.
- `C.3` Ask only for the endpoint URL and never for provider credentials or dashboard access.
- `C.4` Configure RPC with `set rpc --network <NETWORK> --rpc-url <URL> --provider ankr` for the recommended path.
- `C.5` Recover from missing RPC or unlisted-provider setup by using Ankr, another built-in provider, or documented scan limits.

### D. Guided Setup Flow

- `D.1` Select network and public selectors.
- `D.2` Install and verify runtime artifacts with `install` and `help doctor`.
- `D.3` Configure RPC before commands that read or write chain state.
- `D.4` Prepare and import the Ethereum account.
- `D.5` Prepare and preserve the wallet secret source.
- `D.6` Inspect or create channel metadata.
- `D.7` Recover channel workspace, preferring mirror recovery before genesis replay.
- `D.8` Join channel only after acknowledgement and policy review.
- `D.9` Discover wallet names with `wallet list`.
- `D.10` Fund the bridge when the joined wallet needs bridge liquidity.
- `D.11` Fund the channel after bridge balance exists.
- `D.12` Mint spendable private notes after channel balance exists.
- `D.13` Use existing notes only after inspecting available notes.
- `D.14` Exit channel only when balances and state allow it.

### E. Acknowledgements and Policy

- `E.1` Explain action-impact acknowledgement before adding `--acknowledge-action-impact`.
- `E.2` Confirm immutable channel policy and join/create impact before `channel create` or `channel join`.

### F. Recovery Rules

- `F.1` Prefer workspace mirror recovery before RPC genesis replay.
- `F.2` Triage slow recovery through RPC provider scan limits.
- `F.3` Warn before explicit RPC genesis replay.
- `F.4` Use CLI recovery hints first.
- `F.5` Recover stale proof failures by refreshing state and rerunning the original intended command unchanged.
- `F.6` Treat `UnexpectedCurrentRootVector()` as stale root/proof state, not as a command-shape bug.

### G. Note Workflow Rules

- `G.1` Explain that bridge funding is public and does not create private notes by itself.
- `G.2` Explain that channel funding is separate from bridge funding.
- `G.3` Mint notes only after channel balance exists.
- `G.4` Transfer or redeem only existing notes after inspecting note IDs.
- `G.5` Explain optional `--tx-submitter <ACCOUNT>` without changing note ownership semantics.
- `G.6` Check exit safety before channel exit.

### H. Discovery Commands

- `H.1` Prefer CLI state discovery over filesystem inspection.
- `H.2` Parse JSON mode correctly: stdout is the final result and stderr JSONL is progress, warning, or info.
- `H.3` Answer fee and cost questions through `help transaction-fees --json`.
- `H.4` Recover command failures by following CLI hints, `help guide --json`, and indexed recipes before inventing alternate workflows.

### I. Plain-Language Explanations

- `I.1` Explain private key source files only when useful for the next action.
- `I.2` Explain account nicknames only when the user needs to choose or use one.
- `I.3` Explain wallet secret source files only when useful for setup or recovery.
- `I.4` Explain RPC URLs only when needed for setup or troubleshooting.

## Required Setup Recipes

These recipes are the concrete content that should appear under the indexed `agents.md` items.
They are included here to make the plan testable against the original user feedback.

### Recipe: Account Import From a Private Key File

Relevant refs: `B.1`, `B.2`, `B.3`, `D.4`, `I.2`, `I.4`.

Goal: create a local CLI account alias without exposing the raw Ethereum wallet private key to the AI.

Minimal user actions:

1. Choose an account alias, or accept the alias proposed by the AI.
2. Export or reveal the Ethereum wallet private key in the user's wallet software, without pasting it into chat.
3. Run one short CLI helper command that prompts for the private key, displays each typed character as `*`, and writes it to a default local file.
4. Run the `account import` command that uses the default file path.

AI may ask:

- target network
- desired account alias
- whether the user wants to use the default private key source-file path or an existing custom path

AI must not ask:

- private key contents
- seed phrase
- wallet password
- screenshots showing secrets

Preferred local file creation command:

```bash
private-state-cli secret create-private-key-source --output ./ethereum-private-key.txt
```

The AI should use `./ethereum-private-key.txt` as the default path in the next command.
The helper should implement masked input internally so the user sees `*` characters while typing.
If masked input cannot be supported in the current terminal, the helper should fail with a clear local-only fallback instruction rather than asking the user to paste the key into chat.

Command template:

```bash
private-state-cli account import --account <ACCOUNT> --network <NETWORK> --private-key-file ./ethereum-private-key.txt
```

Success check:

```bash
private-state-cli account get-l1-address --account <ACCOUNT> --network <NETWORK> --json
```

Failure recovery:

- If the source file is missing, ask the user to rerun the local helper command or provide an existing local path.
- If the account already exists, do not overwrite it; use `account get-l1-address` to confirm whether it is the intended account.
- If the private key is invalid, ask the user to re-export or re-enter the private key locally using the masked-input command without pasting the key into chat.

Optional explanation:

- Explain what a private key source file is only if the user asks or appears confused.

### Recipe: Wallet Secret File and Channel Join

Relevant refs: `B.4`, `B.5`, `B.7`, `D.5`, `D.7`, `D.8`, `E.1`, `E.2`, `I.2`, `I.4`.

Goal: create a wallet secret source file and join the channel without exposing the wallet secret to the AI.

Default minimal user actions:

1. Choose a strong password or passphrase that the user can store and recover.
2. Run one short CLI helper command that prompts for it, displays each typed character as `*`, and writes it to the default local wallet secret file.
3. Back up the wallet secret source file or password/passphrase before joining.
4. Use the default wallet secret file path for `channel join`, unless the user already has a custom existing path.
5. Review the channel policy and action-impact warning.
6. Explicitly confirm before the AI includes `--acknowledge-action-impact` in an executed command.

Preferred local file creation command:

```bash
private-state-cli secret create-wallet-secret-source --output ./wallet-secret.txt
```

Random generation alternative:

```bash
private-state-cli secret create-wallet-secret-source --output ./wallet-secret.txt --random
```

Use the random generation alternative only when the user explicitly asks for a random wallet secret.
The random path should use the same helper so overwrite protection, file permissions, and output handling stay consistent with the password/passphrase path.

AI may ask:

- channel name
- network
- account alias
- whether the user wants to use the default wallet secret source-file path or an existing custom path
- whether the user explicitly confirms the action-impact acknowledgement

AI must not ask:

- wallet secret contents
- Ethereum wallet private key contents
- seed phrase
- password/passphrase contents

Command template:

```bash
private-state-cli channel join --channel-name <CHANNEL> --network <NETWORK> --account <ACCOUNT> --wallet-secret-path ./wallet-secret.txt --acknowledge-action-impact
```

Success check:

```bash
private-state-cli wallet list --network <NETWORK> --channel-name <CHANNEL> --json
```

Then inspect the created wallet when the wallet name is known:

```bash
private-state-cli wallet get-meta --wallet <WALLET> --network <NETWORK> --json
```

Failure recovery:

- If channel workspace is missing, run `help guide --json` and follow the referenced workspace recovery refs.
- If the wallet secret path is missing, ask the user to rerun the local helper command or provide an existing local path.
- If acknowledgement is missing, explain the human action-impact warning and ask for explicit confirmation.
- If registration already exists, switch to wallet recovery or normal wallet commands instead of joining again.

Optional explanation:

- Explain what the wallet secret source file controls only if the user asks or appears confused, or when loss of the file affects recovery.

### Recipe: Ankr RPC Setup

Relevant refs: `C.1`, `C.2`, `C.3`, `C.4`, `C.5`, `C.6`, `C.7`, `C.8`, `I.2`, `I.4`.

Goal: configure the per-network RPC endpoint required by bridge-facing and wallet commands.

Default minimal user actions:

1. Choose the network, usually `mainnet` for ordinary end users unless the user explicitly asks for testnet, development, or rehearsal.
2. Recommend Ankr unless the user already has a provider, paid endpoint, organization policy, or self-hosted node.
3. In Ankr, create or select an endpoint for the chosen network.
4. Copy only the endpoint URL.
5. Give the AI only the endpoint URL and selected network.

AI may ask:

- target network
- endpoint URL
- whether the user must use a non-Ankr provider

AI must not ask:

- provider dashboard password
- provider API dashboard access
- seed phrase
- private key
- wallet secret

Command template for the recommended Ankr path:

```bash
private-state-cli set rpc --network <NETWORK> --rpc-url <URL> --provider ankr
```

Command template for an unlisted provider:

```bash
private-state-cli set rpc --network <NETWORK> --rpc-url <URL> --log-requests-per-second <N> --block-range-cap <N>
```

Success check:

```bash
private-state-cli help guide --network <NETWORK> --json
```

The network RPC check should no longer be missing.

Failure recovery:

- If chain ID validation fails, ask the user to create or select an endpoint for the requested network.
- If the provider is unsupported, use Ankr or collect the provider's documented `eth_getLogs` rate and block-range limits.
- If recovery later feels slow, consider switching to Ankr or improving the saved scan limits.

Optional explanation:

- Explain what an RPC URL is only if the user asks or appears confused.

## Proposed `help guide --json` Reference Shape

The existing guide result should keep `nextSafeAction`, `checks`, `state`, and `candidateCommands`.
Human `help guide` may keep `why`, privacy tips, and mirror tips.
JSON `help guide --json` must omit human guidance prose such as `why`, `privacyTip`, and `mirrorTip`.
Add a compact reference block for AI agents.
This block must not include hardcoded guidance prose.
Every detailed instruction that the user's AI needs must be represented by an `agents.md` index number.
The block should identify the reference source directly, without adding a schema version.

```json
{
  "action": "guide",
  "nextSafeAction": "secret create-private-key-source --output ./ethereum-private-key.txt",
  "candidateCommands": [
    "account import --account alice --network mainnet --private-key-file ./ethereum-private-key.txt",
    "account get-l1-address --account alice --network mainnet"
  ],
  "agentGuidance": {
    "source": "agents.md",
    "step": "create-private-key-source-and-import-account",
    "refs": ["B.1", "B.2", "B.3", "D.4", "I.1"]
  }
}
```

In JSON mode, do not add fields such as `summary`, `plainLanguageExplanation`, `userMustPrepare`,
`doNotAskUserFor`, or `safetyNotes`, because those are guidance content rather than indexes.
If a future machine-readable field is needed, it must be a stable symbolic state, boolean, or identifier, not prose.

The same pattern should apply to the major first-time setup states:

- Missing network selector: refs `A.1`, `D.1`.
- Unsupported network selector: refs `A.1`, `D.1`.
- Malformed wallet selector: refs `D.9`, `H.1`.
- Missing RPC config: refs `C.1`, `C.2`, `C.3`, `C.4`, `D.3`.
- Missing deployment artifacts: refs `D.2`.
- Missing account secret: refs `B.1`, `B.2`, `B.3`, `D.4`, `I.1`.
- Channel does not exist and may need creation: refs `D.6`, `E.1`, `E.2`.
- Missing channel workspace with registered mirror: refs `D.7`, `F.1`, `F.2`.
- Missing channel workspace without registered mirror: refs `D.7`, `F.1`, `F.3`.
- Missing wallet before channel join: refs `B.4`, `B.5`, `B.6`, `B.7`, `D.5`, `D.8`, `E.1`, `E.2`.
- Existing wallet with missing channel registration: refs `B.7`, `D.8`, `E.1`, `E.2`.
- Missing bridge, channel, and unused-note funds: refs `D.10`, `E.1`, `G.1`.
- Bridge funded but channel balance missing: refs `D.11`, `E.1`, `G.2`.
- Channel balance available but unused notes missing: refs `D.12`, `E.1`, `G.3`, `G.5`.
- Transfer or note use readiness: refs `D.13`, `E.1`, `G.4`, `G.5`.
- Channel exit readiness: refs `D.14`, `G.6`.
- More selectors needed: refs `A.1`, `D.1`, `H.1`.

## Implementation Phases

### Phase 1: Reorganize `agents.md`

Rewrite `agents.md` into the indexed categories above while preserving existing operating rules.
Each item should be short, stable, and directly referenceable.
The items should prioritize operational assistance: how the AI helps the user obtain, prepare, and configure each required input with minimal knowledge and minimal action.
Concept definitions should be secondary clarification items, not the main onboarding path.
Setup-related items must follow the recipe contract above and cover the three required setup recipes.
Avoid changing CLI behavior in this phase.

### Phase 2: Add Reference Mapping to `help guide --json`

Introduce an internal mapping from guide next-action step to `agents.md` item identifiers.
Return the mapping in an `agentGuidance` object.
The JSON output must not include hardcoded guidance sentences.

Human `help guide` output may include hardcoded guidance text because it is the user-facing, human-readable mode.
It may also include a short reference line such as:

```text
Agent guidance refs: B.1, B.2, D.4, D.5
```

The detailed text should remain in `agents.md`.

### Phase 3: Add Short Masked-Input Secret Helpers

Add local-only helper commands so user-facing setup does not depend on long shell snippets:

```bash
private-state-cli secret create-private-key-source --output ./ethereum-private-key.txt
private-state-cli secret create-wallet-secret-source --output ./wallet-secret.txt
```

Requirements:

- Prompt in the terminal and display each typed character as `*`.
- Support `create-wallet-secret-source --random` as an explicit opt-in path that does not prompt for a password/passphrase.
- Write the resulting file with restrictive permissions where the platform supports them.
- Refuse to print the secret back to stdout or stderr.
- Refuse to overwrite an existing output file unless a future explicit overwrite option is designed.
- Fail clearly if the terminal cannot support masked input.
- Keep these helpers local-only; they must not import, derive, register, or submit transactions by themselves.

### Phase 4: Strengthen Human Guide Text

For each major onboarding step, add concise hardcoded explanation only to the human `help guide` renderer.
The explanation should be action-first:

- For private key setup, default to the short CLI masked-input helper that writes `./ethereum-private-key.txt`, then run `account import` with that path; only ask for a file path when the user already has an existing source file.
- For wallet secret setup, default to the short CLI masked-input helper that writes `./wallet-secret.txt`, plus a backup reminder before `channel join`; only ask for a file path when the user already has an existing source file, and only suggest random generation if the user explicitly asks for a random wallet secret.
- For RPC setup, encourage Ankr for users without an existing provider preference because its free plan is expected to be much faster for this CLI's log-scanning workload; then guide the user to copy the endpoint URL and run `set rpc --provider ankr`. Only define RPC if the user asks.

Do not add explanation text to `help guide --json`.
The JSON output should remain a routing layer from current CLI state to `agents.md` indexes.

### Phase 5: Update Documentation

Update the CLI README's LLM Agent Guidance section to tell AI agents to start with:

```bash
private-state-cli help guide --json
```

Then read the referenced `agents.md` items for details.

### Phase 6: Tests

Add focused tests for `help guide --json` output:

- No network selected.
- RPC config missing.
- Deployment artifacts missing.
- Account secret missing.
- Existing channel workspace missing.
- Wallet missing before `channel join`.
- Existing wallet with missing channel registration.
- Acknowledgement-required next action.

Each test should assert that `agentGuidance.source` is `agents.md` and the expected `agentGuidance.refs` are present and stable.
Each test should also assert that `agentGuidance` does not include guidance prose fields such as `summary`,
`plainLanguageExplanation`, `userMustPrepare`, `doNotAskUserFor`, or `safetyNotes`.

Add documentation/structure tests for `agents.md`:

- Every ref emitted by `help guide --json` exists in `agents.md`.
- First-time setup refs include the required recipe fields.
- The account-import recipe includes a success check through `account get-l1-address`.
- The wallet-secret/channel-join recipe defaults to user-entered password/passphrase file creation and keeps random generation as an opt-in helper mode.
- The RPC setup recipe recommends Ankr and includes the `set rpc --provider ankr` command template.
- The recipes include explicit `AI must not ask` lists for private keys, wallet secrets, seed phrases, provider passwords, and dashboard access where relevant.

Add helper command tests:

- The private-key source helper masks typed input with `*` and writes `./ethereum-private-key.txt` when requested.
- The wallet-secret source helper masks typed input with `*` and writes `./wallet-secret.txt` when requested.
- The wallet-secret source helper supports `--random` only as an explicit opt-in mode and still applies file-safety behavior.
- Neither helper prints the secret value.
- Existing output files are not overwritten by default.

## Explicit Non-Goals

- Do not restore or replace `cli-assistant.html`.
- Do not add `help onboard` while `help guide` can serve as the single guide entrypoint.
- Do not make the CLI ask for raw private keys, wallet secrets, seed phrases, or provider credentials.
- Do not hardcode guidance prose in `help guide --json`; only `agents.md` item references are allowed there.
- Do not make first-time setup guidance primarily conceptual; it must be action-first and minimize user effort.
- Do not default wallet secret setup to random generation; use random generation only when the user asks for it.
- Do not hide setup failures behind fallback behavior.
- Do not change transaction-sending behavior as part of the guide reference work.

## Plan Review Against User Feedback

Original feedback:

1. Saving a private key file and then running `account import` is difficult.
2. Saving a wallet secret file and then running `channel join` is difficult.
3. Configuring RPC is difficult.

Expected improvement after implementing this plan:

- `help guide --json` gives the user's AI a state-specific route into `agents.md` instead of relying on generic CLI knowledge.
- `agents.md` no longer only explains concepts; it contains concrete recipes that tell the AI exactly how to help the user obtain, prepare, and configure each required input.
- The private-key recipe minimizes user knowledge by asking only for an alias and making the user run a short masked-input helper command that creates the default source file locally, never by asking for key contents, and by immediately verifying the import with `account get-l1-address`.
- The wallet-secret recipe minimizes loss risk by defaulting to a user-entered strong password/passphrase saved locally, backing it up before join, and using random generation only on explicit request.
- The channel-join recipe ties the wallet secret file, policy review, join toll impact, and acknowledgement confirmation into one guided sequence.
- The RPC recipe minimizes provider choice by recommending Ankr, asking only for the final endpoint URL, and giving one `set rpc --provider ankr` command.
- Human `help guide` can print concise action-first guidance for users who run the command directly.

Residual risks:

- The plan assumes the user's AI can access the package-shipped `agents.md` after seeing `agentGuidance.source: "agents.md"`.
- The plan automates local secret-file creation through CLI helpers, but does not automate provider UI interactions or wallet export flows.
- Exact wallet software export steps differ by wallet, so `agents.md` should avoid pretending one wallet-specific export path works everywhere.
- The user still needs to handle sensitive local files correctly; the plan reduces but cannot eliminate that responsibility.

Conclusion:

With the recipe contract and the three required setup recipes, the plan should materially reduce the difficulty reported by AI-assisted users.
It is stronger than an index-only plan because it forces each referenced `agents.md` item to contain the actual minimal-action procedure, command template, success check, and failure recovery needed to complete setup.

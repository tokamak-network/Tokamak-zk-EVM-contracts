# private-state CLI Agent Instructions

These instructions are for User-Controlled AI Agents guiding users through `private-state-cli`.

Start with:

```bash
private-state-cli help guide --json
```

When the guide result contains `agentGuidance.source: "agents.md"`, read every item listed in `agentGuidance.refs`
before telling the user what to do next. When the guide result contains `agentGuidance.termsSource` and
`agentGuidance.termsRefs`, read the listed Terms sections as the legal and safety context for the next action. The
indexed items below are written as action recipes: they prioritize the smallest safe user action over conceptual
explanation.

## A. Operating Rules

### A.1 Action-first setup

Goal: move the user to the next safe setup action with minimal required knowledge.

When to use: every first-time setup, recovery, funding, or note-flow step, especially when `help guide --json` returns
`select-network` or `collect-selectors`.

Minimal user actions: answer only the public selector questions needed for the next command, then run one command at a
time.

AI may ask: network, channel name, local account alias, local wallet name, amount, endpoint URL, and whether the user is
testing or using mainnet.

AI must not ask: raw private keys, wallet secrets, seed phrases, provider passwords, provider dashboard access, or
screenshots that reveal secrets.

Command template:

```bash
private-state-cli help guide --network <NETWORK> --channel-name <CHANNEL> --account <ACCOUNT> --wallet <WALLET> --json
```

Success check: the guide returns a concrete `nextSafeAction` and `agentGuidance.refs`.

Failure recovery: if required selectors are missing, ask for only the missing public selector values and rerun
`help guide --json`.

Optional explanation: use "Ethereum account", "Ethereum address", or "Ethereum wallet" with users. Use "L1" only when
quoting CLI command names, CLI output fields, or explaining why `account get-l1-address` uses that name. For ordinary
users, assume `mainnet` unless they explicitly say they are testing, developing, rehearsing, or using Sepolia/anvil.

### A.2 Secret handling

Goal: keep secrets local to the user's terminal and filesystem.

When to use: any step involving private key source files, wallet secret source files, wallet keys, provider accounts, or
wallet recovery.

Minimal user actions: run the CLI helper that prompts locally with `*` masking, or point to an existing local file path.

AI may ask: whether the user wants the default local path or already has an existing local path.

AI must not ask: private key contents, wallet secret contents, seed phrases, wallet passwords, provider passwords, or
provider dashboard access.

Command template:

```bash
private-state-cli secret create-private-key-source --output ./ethereum-private-key.txt
private-state-cli secret create-wallet-secret-source --output ./wallet-secret.txt
```

Success check: the helper reports `secretPrinted: false` and an `outputPath`.

Failure recovery: if masked input is unavailable, tell the user to run the helper directly in an interactive terminal.
Do not replace the helper with chat-based secret collection.

Optional explanation: the source files are local inputs for later CLI commands; they are not meant to be pasted into
chat.

### A.3 JSON guidance contract

Goal: make `help guide --json` a routing layer from local state to indexed instructions.

When to use: whenever an AI agent consumes `help guide --json`.

Minimal user actions: none; this is an AI interpretation rule.

AI may ask: nothing because of this item alone.

AI must not ask: the user to interpret `agentGuidance.refs` manually.

Command template:

```bash
private-state-cli help guide --json
```

Success check: `agentGuidance.source` is `agents.md` and `agentGuidance.refs` is a non-empty array.

Failure recovery: if refs are missing, use the CLI `nextSafeAction` conservatively and avoid inventing secret-handling
steps not covered by this document.

Optional explanation: JSON mode intentionally carries indexes instead of long guidance prose so the user's AI can read
the relevant `agents.md` items.

## B. Secret Source Recipes

### B.1 Create a private key source file

Goal: create a local source file that `account import` can read once without exposing the Ethereum private key to chat.

When to use: `help guide --json` indicates a missing account secret, or the user needs to import an Ethereum account.

Minimal user actions: run one helper command in an interactive terminal and type the Ethereum private key when prompted.

AI may ask: whether to use the default path `./ethereum-private-key.txt` or an existing custom local path.

AI must not ask: private key contents, seed phrase, wallet password, or screenshots showing the exported key.

Command template:

```bash
private-state-cli secret create-private-key-source --output ./ethereum-private-key.txt
```

Success check: the helper reports `outputPath` and `secretPrinted: false`; the next step is B.2.

Failure recovery: if the file already exists, do not overwrite it. Ask whether the existing file is intended or choose a
new local path. If terminal masking is unavailable, ask the user to run the helper directly in a terminal.

Optional explanation: a private key source file is a temporary local file containing the Ethereum private key so the CLI
can import it once into a protected account alias.

### B.2 Import the Ethereum account

Goal: create a protected local account alias for later signing commands.

When to use: after B.1 succeeds, or when the user already has a private key source file.

Minimal user actions: choose or accept an account alias, then run the import command.

AI may ask: target network, account alias, and whether the user already has a custom local source path.

AI must not ask: private key contents, seed phrase, wallet password, or screenshots showing secrets.

Command template:

```bash
private-state-cli account import --account <ACCOUNT> --network <NETWORK> --private-key-file ./ethereum-private-key.txt
```

Success check:

```bash
private-state-cli account get-l1-address --account <ACCOUNT> --network <NETWORK> --json
```

Failure recovery: if the account already exists, do not overwrite it. Run the success check and ask the user whether the
displayed Ethereum address is the intended one. If the source file is invalid, ask the user to rerun B.1 locally.

Optional explanation: after import, signing commands use `--account <ACCOUNT>` instead of handling the raw private key.

### B.3 Verify the imported Ethereum address

Goal: confirm that the local account alias points to the expected Ethereum address.

When to use: immediately after account import, or when wallet ownership needs to be identified.

Minimal user actions: run one read-only command and compare the displayed Ethereum address with the user's expected
wallet address.

AI may ask: account alias, network, and whether the displayed address is expected.

AI must not ask: private key contents, seed phrase, wallet password, or wallet screenshots containing secrets.

Command template:

```bash
private-state-cli account get-l1-address --account <ACCOUNT> --network <NETWORK> --json
```

Success check: the JSON result contains `l1Address`; describe it to the user as the Ethereum address.

Failure recovery: if the account is missing, return to B.1 and B.2. If the address is unexpected, do not proceed with
funding or channel join until the user imports the intended account under a new alias.

Optional explanation: `l1Address` is the CLI field name for the Ethereum-side address.

### B.4 Create a wallet secret source file

Goal: create a local wallet secret source file for `channel join` without exposing the wallet secret to chat.

When to use: before `channel join`, or when `help guide --json` returns a missing wallet or missing registration state.

Minimal user actions: choose a strong password or passphrase they can retain, then run one helper command and type it in
the terminal prompt.

AI may ask: whether to use the default path `./wallet-secret.txt` or an existing custom local path.

AI must not ask: wallet secret contents, Ethereum private key contents, seed phrase, password/passphrase contents, or
screenshots showing secrets.

Command template:

```bash
private-state-cli secret create-wallet-secret-source --output ./wallet-secret.txt
```

Success check: the helper reports `outputPath`, `random: false`, and `secretPrinted: false`; the next step is B.6 or
B.7.

Failure recovery: if the file already exists, do not overwrite it. Ask whether the existing local file is intended or
choose a new path. If terminal masking is unavailable, ask the user to run the helper directly in a terminal.

Optional explanation: the wallet secret source is separate from the Ethereum private key and is used to derive
channel-bound wallet authority during `channel join`.

### B.5 Random wallet secret opt-in

Goal: support random wallet secret creation only when the user explicitly wants random generation.

When to use: the user explicitly asks for a random wallet secret.

Minimal user actions: run the random helper command and preserve the resulting source file securely.

AI may ask: whether the user understands they must preserve the generated file for future recovery needs.

AI must not ask: wallet secret contents, private key contents, seed phrase, or password/passphrase contents.

Command template:

```bash
private-state-cli secret create-wallet-secret-source --output ./wallet-secret.txt --random
```

Success check: the helper reports `random: true`, `secretPrinted: false`, and an `outputPath`.

Failure recovery: if the file already exists, do not overwrite it. Choose a new path or use the existing intended file.

Optional explanation: random generation can reduce memorability and increase loss risk unless the source file or later
exported recovery material is preserved.

### B.6 Wallet secret recovery reminder

Goal: ensure the user preserves the wallet secret source before a channel join depends on it.

When to use: after B.4 or B.5 and before B.7.

Minimal user actions: keep the source file private and preserve a recoverable copy if future recovery matters.

AI may ask: whether the user has preserved the file or password/passphrase outside chat.

AI must not ask: the wallet secret, backup contents, seed phrase, private key, or screenshots of secret storage.

Command template:

```bash
private-state-cli secret create-wallet-secret-source --output ./wallet-secret.txt
```

Success check: the user confirms the source file or passphrase has been preserved without revealing it.

Failure recovery: if the user has not preserved it, pause before channel join and let them back it up locally.

Optional explanation: losing wallet secret material can prevent rederiving spending authority if protected key files are
also lost.

### B.7 Join a channel with the wallet secret source

Goal: join a channel and create/register the local private-state wallet using the prepared wallet secret source.

When to use: after the Ethereum account is imported, RPC is configured, the channel/workspace is ready, and the wallet
secret source exists.

Minimal user actions: review the channel policy and CLI warning summary, then run the join command directly.

AI may ask: channel name, network, account alias, and wallet secret source path.

AI must not ask: wallet secret contents, Ethereum private key contents, seed phrase, or password/passphrase contents.

Command template:

```bash
private-state-cli channel join --channel-name <CHANNEL> --network <NETWORK> --account <ACCOUNT> --wallet-secret-path ./wallet-secret.txt
```

Success check:

```bash
private-state-cli wallet list --network <NETWORK> --channel-name <CHANNEL> --json
private-state-cli wallet get-meta --wallet <WALLET> --network <NETWORK> --json
```

Failure recovery: if the channel workspace is missing, follow D.7. If the user is not ready to accept the policy or
warning summary, stop and do not join. If registration already exists, use wallet recovery or normal wallet commands
instead of joining again.

Optional explanation: joining creates/registers the private-state wallet for that channel and may pay the Join Toll
directly from the Ethereum account.

## C. RPC Setup Recipes

### C.1 Confirm the network

Goal: choose the correct network before configuring RPC or running chain-facing commands.

When to use: no network selector is provided, or RPC setup is needed.

Minimal user actions: confirm mainnet or explicitly choose a test/developer network.

AI may ask: whether the user is using mainnet, Sepolia, anvil, testing, development, or rehearsal.

AI must not ask: private keys, wallet secrets, seed phrases, provider passwords, or dashboard access.

Command template:

```bash
private-state-cli help guide --network mainnet --json
```

Success check: the guide proceeds to RPC, install, account, channel, or wallet checks for the selected network.

Failure recovery: if the user selected the wrong network, rerun `help guide --network <NETWORK> --json` with the
correct network before setting RPC.

Optional explanation: ordinary end users should use `mainnet`; Sepolia is for explicit test, development, or rehearsal
flows.

### C.2 Recommend Ankr without treating it as a default

Goal: reduce provider choice burden while making clear that the user still must provide a real RPC URL.

When to use: RPC is missing and the user has no provider preference.

Minimal user actions: open Ankr, create or select an Ethereum mainnet endpoint, and copy only the endpoint URL.

AI may ask: whether the user already has a provider, paid endpoint, organization requirement, or self-hosted node.

AI must not ask: provider password, provider dashboard access, seed phrase, private key, wallet secret, or API dashboard
screenshots.

Command template:

```bash
private-state-cli set rpc --network <NETWORK> --rpc-url <URL> --provider ankr
```

Success check:

```bash
private-state-cli help guide --network <NETWORK> --json
```

Failure recovery: if the user must use another provider, follow C.4 for built-in providers or C.5 for unlisted
providers.

Optional explanation: Ankr is recommended because its free RPC plan is expected to be faster for this CLI's log-scanning
workload than typical free alternatives. This is a recommendation, not a CLI default.

### C.3 Ask only for the endpoint URL

Goal: collect only the non-secret value needed for RPC configuration.

When to use: the user is obtaining an RPC endpoint from Ankr or another provider.

Minimal user actions: copy the final endpoint URL and provide that URL only.

AI may ask: endpoint URL and selected network.

AI must not ask: provider login credentials, dashboard access, seed phrase, private key, wallet secret, billing details,
or screenshots of provider pages containing secrets.

Command template:

```bash
private-state-cli set rpc --network <NETWORK> --rpc-url <URL> --provider ankr
```

Success check: `set rpc` succeeds and a follow-up `help guide --network <NETWORK> --json` no longer reports missing RPC.

Failure recovery: if the endpoint is missing or malformed, ask the user to copy the endpoint URL again from the provider
UI.

Optional explanation: the endpoint URL is the only provider value the CLI needs for normal setup.

### C.4 Configure RPC

Goal: save the per-network RPC configuration used by bridge-facing and wallet commands.

When to use: the user has the endpoint URL and selected network.

Minimal user actions: run one `set rpc` command.

AI may ask: network, endpoint URL, and provider name if the user chose a built-in provider other than Ankr.

AI must not ask: provider passwords, seed phrases, private keys, wallet secrets, or dashboard access.

Command template:

```bash
private-state-cli set rpc --network <NETWORK> --rpc-url <URL> --provider ankr
```

Success check:

```bash
private-state-cli help guide --network <NETWORK> --json
```

Failure recovery: if chain ID validation fails, ask the user to create or select an endpoint for the requested network.
If the provider is not built in, follow C.5.

Optional explanation: the CLI stores RPC settings under the private-state workspace for that network.

### C.5 Missing RPC and unlisted provider recovery

Goal: handle missing RPC configuration or providers that are not in the built-in provider table.

When to use: RPC is missing, `set rpc --provider <PROVIDER>` is not supported, or recovery is slow because scan limits
are too low.

Minimal user actions: either use Ankr, use another built-in provider, or provide the unlisted provider's documented
`eth_getLogs` request rate and block range cap.

AI may ask: whether the user can use Ankr, or the provider's documented `eth_getLogs` rate and block range cap.

AI must not ask: provider passwords, dashboard access, seed phrases, private keys, wallet secrets, or undocumented guess
values.

Command template:

```bash
private-state-cli set rpc --network <NETWORK> --rpc-url <URL> --log-requests-per-second <N> --block-range-cap <N>
```

Success check: `help guide --network <NETWORK> --json` no longer reports `MISSING_RPC_URL`.

Failure recovery: if the provider limits are unknown, recommend Ankr or ask the user to consult provider documentation.
Do not invent scan limits.

Optional explanation: without RPC configuration, later bridge-facing and wallet commands fail; the CLI does not use a
default RPC URL.

## D. Guided Setup Flow

### D.1 Select network and public selectors

Goal: collect the smallest public selector set needed for `help guide --json`.

When to use: the guide lacks network, channel, account, or wallet selectors.

Minimal user actions: provide public names only.

AI may ask: network, channel name, account alias, and wallet name.

AI must not ask: private keys, wallet secrets, seed phrases, or provider credentials.

Command template:

```bash
private-state-cli help guide --network <NETWORK> --channel-name <CHANNEL> --account <ACCOUNT> --wallet <WALLET> --json
```

Success check: the guide returns a more specific `nextSafeAction`.

Failure recovery: if the user does not know the wallet name, follow D.9.

Optional explanation: public selectors help the CLI inspect local and on-chain state; they are not secret values.

### D.2 Install runtime

Goal: install and verify runtime artifacts before bridge-facing workflows.

When to use: `help guide --json` reports missing deployment artifacts or runtime readiness.

Minimal user actions: run install, then doctor.

AI may ask: whether the user needs read-only mode or full transaction-sending mode only if that choice matters.

AI must not ask: secrets or provider credentials.

Command template:

```bash
private-state-cli install
private-state-cli help doctor
```

Success check: `help doctor` reports required command availability and artifact readiness.

Failure recovery: follow the `help doctor` output and CLI error hints before inventing a different install sequence.

Optional explanation: full install is needed for proof-backed or transaction-sending workflows; read-only install is
limited.

### D.3 Configure RPC

Goal: complete network RPC setup before commands that read or write chain state.

When to use: `help guide --json` reports missing RPC.

Minimal user actions: follow C.1 through C.4.

AI may ask: network and endpoint URL.

AI must not ask: provider password, provider dashboard access, seed phrase, private key, or wallet secret.

Command template:

```bash
private-state-cli set rpc --network <NETWORK> --rpc-url <URL> --provider ankr
```

Success check: rerun `help guide --network <NETWORK> --json`; the network RPC check is no longer missing.

Failure recovery: follow C.5 for missing RPC, unsupported provider, or slow recovery due to scan limits.

Optional explanation: RPC configuration is required; there is no default RPC.

### D.4 Prepare and import the Ethereum account

Goal: create a local account alias ready for signing.

When to use: the selected account alias has no protected local account secret.

Minimal user actions: run B.1, run B.2, then verify with B.3.

AI may ask: account alias, network, and whether to use the default source path or an existing local path.

AI must not ask: private key contents, seed phrase, wallet password, or screenshots showing secrets.

Command template:

```bash
private-state-cli secret create-private-key-source --output ./ethereum-private-key.txt
private-state-cli account import --account <ACCOUNT> --network <NETWORK> --private-key-file ./ethereum-private-key.txt
private-state-cli account get-l1-address --account <ACCOUNT> --network <NETWORK> --json
```

Success check: `account get-l1-address --json` returns the expected Ethereum address.

Failure recovery: follow B.1, B.2, or B.3 depending on the failing command.

Optional explanation: this imports the Ethereum account once so later commands use `--account <ACCOUNT>`.

### D.5 Prepare the wallet secret source

Goal: create and preserve the wallet secret source before channel join.

When to use: before B.7 or when the guide recommends creating a wallet secret source.

Minimal user actions: run B.4 or, only by explicit request, B.5; then confirm local preservation with B.6.

AI may ask: wallet secret source path preference and whether the user explicitly wants random generation.

AI must not ask: wallet secret contents, private key contents, seed phrase, or password/passphrase contents.

Command template:

```bash
private-state-cli secret create-wallet-secret-source --output ./wallet-secret.txt
```

Success check: the helper reports `secretPrinted: false`, and the user confirms the source is preserved locally.

Failure recovery: if the file is missing before join, rerun B.4 or provide an existing local path.

Optional explanation: this source derives channel-bound wallet authority and is separate from the Ethereum private key.

### D.6 Inspect or create channel

Goal: determine whether a channel exists and whether the user should recover, create, or join.

When to use: before joining or creating a channel.

Minimal user actions: run channel metadata inspection; create a channel only if the user is the channel creator and
confirms policy impact.

AI may ask: channel name, network, whether the user is the channel creator, Join Toll, and explicit confirmation for
transaction-sending commands.

AI must not ask: private keys, wallet secrets, seed phrases, or provider credentials.

Command template:

```bash
private-state-cli channel get-meta --channel-name <CHANNEL> --network <NETWORK>
```

Success check: channel metadata indicates whether the channel exists and whether a workspace mirror is registered.

Failure recovery: if the channel exists but the local workspace is missing, follow D.7. If the channel does not exist
and the user is not the creator, stop and ask for the correct channel.

Optional explanation: channel creation fixes policy for that channel; joining means accepting that policy.

### D.7 Recover channel workspace

Goal: rebuild local channel workspace state before wallet operations.

When to use: the channel exists but local channel workspace is missing or unusable.

Minimal user actions: use mirror recovery when available; use genesis RPC replay only when necessary.

AI may ask: channel name, network, and whether a compatible workspace mirror is available.

AI must not ask: private keys, wallet secrets, seed phrases, or provider credentials.

Command template:

```bash
private-state-cli channel recover-workspace --channel-name <CHANNEL> --network <NETWORK> --source mirror
```

Success check: rerun `help guide --network <NETWORK> --channel-name <CHANNEL> --json`; channel workspace is no longer
missing.

Failure recovery: if no compatible mirror exists, warn about slow genesis replay and then use:

```bash
private-state-cli channel recover-workspace --channel-name <CHANNEL> --network <NETWORK> --source rpc --from-genesis
```

Optional explanation: workspace recovery rebuilds local channel state from public chain logs or a trusted registered
mirror.

### D.8 Join channel

Goal: complete channel join only after policy and warning review.

When to use: the account, RPC, artifacts, channel workspace, and wallet secret source are ready.

Minimal user actions: review the warning and run B.7 directly.

AI may ask: whether the user has read the channel policy and warning summary.

AI must not ask: wallet secret contents, private key contents, seed phrase, or password/passphrase contents.

Command template:

```bash
private-state-cli channel join --channel-name <CHANNEL> --network <NETWORK> --account <ACCOUNT> --wallet-secret-path ./wallet-secret.txt
```

Success check: run `wallet list` and `wallet get-meta` as shown in B.7.

Failure recovery: if the user is not ready to accept the policy or warning summary, stop. If workspace is missing,
follow D.7.

Optional explanation: channel join may pay a Join Toll directly from the Ethereum account.

### D.9 Discover wallet name

Goal: find local wallet names without asking the user to inspect filesystem paths.

When to use: the guide needs a wallet selector or the selected wallet name is malformed.

Minimal user actions: run one local discovery command.

AI may ask: network and channel name if known.

AI must not ask: wallet secrets, key files, private keys, seed phrases, or filesystem screenshots containing secrets.

Command template:

```bash
private-state-cli wallet list --network <NETWORK>
```

Success check: the output lists wallet names that can be reused with `--wallet`.

Failure recovery: if no wallet exists, continue with D.5 and D.8 when the user needs to join.

Optional explanation: wallet names are local CLI identifiers, not secret values.

### D.10 Fund bridge

Goal: deposit funds into the shared bridge vault only when the joined wallet needs liquidity.

When to use: the wallet is joined and no bridge, channel, or unused-note balance is available.

Minimal user actions: review the public warning summary, then run the deposit command.

AI may ask: amount, network, and account alias.

AI must not ask: private keys, wallet secrets, seed phrases, or provider credentials.

Command template:

```bash
private-state-cli account deposit-bridge --amount <TOKENS> --network <NETWORK> --account <ACCOUNT>
```

Success check:

```bash
private-state-cli account get-bridge-fund --account <ACCOUNT> --network <NETWORK> --json
```

Failure recovery: if the user is not ready after reading the warning summary, stop. If RPC or account is missing, return
to D.3 or D.4.

Optional explanation: bridge funding is public and does not create private notes by itself.

### D.11 Fund channel

Goal: move already-bridged funds into channel accounting for the joined wallet.

When to use: bridge balance exists but channel balance is zero.

Minimal user actions: review the public/private warning summary, then run one channel deposit command.

AI may ask: wallet name, network, and amount.

AI must not ask: wallet secrets, private keys, seed phrases, or provider credentials.

Command template:

```bash
private-state-cli wallet deposit-channel --wallet <WALLET> --network <NETWORK> --amount <TOKENS>
```

Success check:

```bash
private-state-cli wallet get-channel-fund --wallet <WALLET> --network <NETWORK> --json
```

Failure recovery: if bridge balance is missing, follow D.10. If the user is not ready after reading the warning summary,
stop.

Optional explanation: channel funding prepares balance for note minting; it is separate from bridge funding.

### D.12 Mint notes

Goal: create spendable private notes from channel balance.

When to use: channel balance exists and unused note count is zero or insufficient.

Minimal user actions: choose note amounts, review the warning summary, then run mint.

AI may ask: wallet name, network, amounts JSON, optional transaction submitter account, and explicit confirmation.

AI must not ask: wallet secrets, private keys, seed phrases, or note plaintext beyond what the command requires.

Command template:

```bash
private-state-cli wallet mint-notes --wallet <WALLET> --network <NETWORK> --amounts <JSON_ARRAY>
```

Success check:

```bash
private-state-cli wallet get-notes --wallet <WALLET> --network <NETWORK> --json
```

Failure recovery: if channel balance is missing, follow D.11. If the user is not ready after reading the warning summary,
stop.

Optional explanation: minting turns channel balance into notes that can later be transferred or redeemed.

### D.13 Use notes

Goal: transfer or redeem existing notes without assuming the required notes exist.

When to use: the wallet has unused notes.

Minimal user actions: inspect notes, choose note IDs and recipients/amounts, review the warning summary, then run the
selected note command.

AI may ask: wallet name, network, selected note IDs, recipients, amounts, and optional transaction submitter account.

AI must not ask: wallet secrets, private keys, seed phrases, or unrelated note plaintext.

Command template:

```bash
private-state-cli wallet get-notes --wallet <WALLET> --network <NETWORK> --json
```

Success check: selected note IDs exist in the unused note list before transfer or redeem.

Failure recovery: if needed notes do not exist, guide funding, channel deposit, and minting instead of fabricating note
IDs or changing the user's intended transfer.

Optional explanation: confidential note transfers use notes owned by channel-local addresses registered in the
channel.

### D.14 Exit channel

Goal: exit only when channel state allows it.

When to use: the wallet has zero channel balance and no state that prevents exit.

Minimal user actions: confirm they intend to exit, then run the exit command.

AI may ask: wallet name, network, and confirmation of intent.

AI must not ask: wallet secrets, private keys, seed phrases, or provider credentials.

Command template:

```bash
private-state-cli channel exit --wallet <WALLET> --network <NETWORK>
```

Success check: `wallet get-meta` reflects the updated lifecycle state.

Failure recovery: if balances or notes remain, resolve them before exit.

Optional explanation: exit is allowed only when the wallet state satisfies CLI and bridge contract requirements.

## E. User Confirmation And Policy

### E.1 Warning summary review

Goal: ensure the user understands externally visible effects before transaction-sending commands.

When to use: before any command that sends a transaction, moves funds, creates or consumes notes, exports sensitive data,
or deletes local data.

Minimal user actions: read the CLI warning summary and decide whether to continue.

AI may ask: whether the user wants to continue after reading the warning summary.

AI must not ask: secrets, private keys, wallet secrets, seed phrases, or blanket future approval.

Command template: use the command returned by `help guide --json` or the relevant recipe without adding legal
confirmation flags.

Success check: the user runs the command directly after reviewing the warning summary.

Failure recovery: if the user is not ready to continue, stop. Do not accept Terms, confirm destructive prompts, or submit
confirmation text for the user.

Optional explanation: warning summaries may cover public events, fund movement, Channel policy, sensitive exports, or
wallet-state changes.

### E.2 Channel policy confirmation

Goal: ensure channel create/join happens only after policy review.

When to use: before `channel create` or first `channel join`.

Minimal user actions: review the channel policy and confirm acceptance.

AI may ask: whether the user accepts the current channel policy and Join Toll impact.

AI must not ask: secrets or credentials.

Command template:

```bash
private-state-cli channel join --channel-name <CHANNEL> --network <NETWORK> --account <ACCOUNT> --wallet-secret-path ./wallet-secret.txt
```

Success check: the user runs the command only after reading the Channel policy.

Failure recovery: if any policy field is unexpected, stop and do not join or create the channel.

Optional explanation: channel policy is immutable after creation or acceptance; later fixes require a new channel or
migration.

### E.3 Terms and safety context

Goal: ensure the user receives the legal and safety context that applies to the next action.

When to use: every `help guide --json` result that includes `agentGuidance.termsRefs`.

Minimal user actions: read the short explanation and decide whether to continue.

AI may ask: whether the user wants a plain-language summary of the referenced Terms sections.

AI must not ask: the user to accept Terms through JSON mode, delegate Terms acceptance, share secrets, or waive future
warnings.

Command template: no command is required by this item alone.

Success check: before suggesting the next command, explain the relevant public/private boundary, prohibited-use limits,
Self-Custody, no recovery method, Third-Party Service risk, no professional advice, no warranties, liability limits,
Official Public Observer limits, and the rule that User-Controlled AI Agents cannot accept Terms or confirmations.

Failure recovery: if the user has not reviewed or accepted required Terms, stop and direct the user to the interactive
CLI flow. Do not continue through JSON mode.

Optional explanation: `agentGuidance.termsRefs` contains Terms section numbers, not the full legal text. Read those
sections from `docs/dapps/private-state/terms.md` before advising the user.

## F. Recovery Rules

### F.1 Prefer mirror before genesis replay

Goal: recover channel workspace through the fastest compatible safe path.

When to use: local channel workspace is missing or unusable.

Minimal user actions: try registered mirror recovery first when available.

AI may ask: channel name and network.

AI must not ask: private keys, wallet secrets, seed phrases, or provider credentials.

Command template:

```bash
private-state-cli channel recover-workspace --channel-name <CHANNEL> --network <NETWORK> --source mirror
```

Success check: `help guide --network <NETWORK> --channel-name <CHANNEL> --json` no longer reports missing workspace.

Failure recovery: if no compatible mirror exists, use F.3 before suggesting RPC genesis replay.

Optional explanation: mirror recovery avoids replaying all channel logs from genesis when a compatible mirror exists.

### F.2 Slow recovery triage

Goal: improve slow recovery by checking RPC provider scan limits before explaining internals.

When to use: channel or wallet recovery is unexpectedly slow.

Minimal user actions: inspect or reconfigure the saved RPC provider.

AI may ask: current provider, whether the user can use Ankr, or documented scan limits for an unlisted provider.

AI must not ask: provider passwords, dashboard access, private keys, wallet secrets, or seed phrases.

Command template:

```bash
private-state-cli set rpc --network <NETWORK> --rpc-url <URL> --provider ankr
```

Success check: subsequent recovery progress shows better scan rate or larger log chunks.

Failure recovery: if Ankr cannot be used, follow C.5 with documented provider limits.

Optional explanation: recovery speed is dominated by `eth_getLogs` request rate and block range cap.

### F.3 Genesis replay warning

Goal: use RPC genesis replay only as an explicit slow fallback.

When to use: no compatible workspace mirror is available.

Minimal user actions: confirm they understand genesis replay can take much longer, then run the explicit command.

AI may ask: confirmation that no compatible mirror exists and that the user accepts slow replay.

AI must not ask: secrets or credentials.

Command template:

```bash
private-state-cli channel recover-workspace --channel-name <CHANNEL> --network <NETWORK> --source rpc --from-genesis
```

Success check: guide no longer reports missing local channel workspace.

Failure recovery: if RPC fails or is too slow, revisit C.2, C.4, C.5, and F.2.

Optional explanation: genesis replay scans public channel logs from the channel creation block.

### F.4 Use CLI recovery hints first

Goal: follow the CLI's own corrective guidance before inventing a recovery sequence.

When to use: any CLI command fails, especially bridge-facing, workspace recovery, wallet recovery, and proof-backed
commands.

Minimal user actions: share or let the AI read the command's stdout/stderr result, then run the first applicable `Try:`
hint or error-specific corrective command.

AI may ask: the failed command, selected network, channel name, account alias, wallet name, and whether the user wants
the AI to run the printed corrective command.

AI must not ask: private keys, wallet secrets, seed phrases, provider passwords, dashboard access, or secret file
contents.

Command template:

```bash
private-state-cli help guide --network <NETWORK> --channel-name <CHANNEL> --account <ACCOUNT> --wallet <WALLET> --json
```

Success check: the follow-up command resolves the failure or returns a more specific CLI error with a new `Try:` hint.

Failure recovery: if the printed hints conflict with the user's stated intent or require a destructive/public action,
stop and ask for confirmation before proceeding.

Optional explanation: CLI errors are intentionally written with recovery hints; prefer them over ad hoc filesystem
inspection or command-shape changes.

### F.5 Stale proof recovery

Goal: recover from stale workspace or stale proof failures without changing the user's intended transaction.

When to use: a proof-backed command fails because channel state changed, local workspace state is stale, or the CLI
reports a stale root/proof condition.

Minimal user actions: refresh the relevant channel or wallet state, re-check notes/balances if needed, then rerun the
original intended command unchanged.

AI may ask: network, channel name, wallet name, account alias, original command, and confirmation to rerun the original
command after refresh.

AI must not ask: wallet secrets, private keys, seed phrases, or permission to silently change recipients, amounts, note
counts, or function shape.

Command template:

```bash
private-state-cli channel recover-workspace --channel-name <CHANNEL> --network <NETWORK>
private-state-cli wallet get-notes --wallet <WALLET> --network <NETWORK> --json
```

Success check: the refreshed workspace and wallet state still support the original intended command; rerunning it
regenerates a proof from fresh state.

Failure recovery: if the original notes or balances are no longer usable after refresh, ask the user to choose a new
plan. Do not substitute a different transfer or redeem shape silently.

Optional explanation: stale proof recovery is about refreshing state and regenerating the proof, not changing the
transaction semantics.

### F.6 UnexpectedCurrentRootVector handling

Goal: classify `UnexpectedCurrentRootVector()` as stale channel-root or stale-proof state, not as a command-shape bug.

When to use: a dry-run or submit failure includes `UnexpectedCurrentRootVector()`.

Minimal user actions: refresh channel workspace state, re-check affected wallet notes and balances, then rerun the
original intended command unchanged if still valid.

AI may ask: original command, network, channel name, wallet name, and confirmation before rerunning.

AI must not ask: permission to change recipients, amounts, note counts, function arity, or split a transfer as a
workaround unless the refreshed state proves the original plan is no longer possible and the user chooses a new plan.

Command template:

```bash
private-state-cli channel recover-workspace --channel-name <CHANNEL> --network <NETWORK>
private-state-cli wallet get-notes --wallet <WALLET> --network <NETWORK> --json
```

Success check: the original command either succeeds after proof regeneration or fails with a different actionable CLI
error.

Failure recovery: if the same error repeats after refresh, follow F.4 and inspect CLI hints before changing the user's
transaction plan.

Optional explanation: this error means the proof was built against an older channel root; changing command shape can
hide the real state-refresh problem and may violate the user's intent.

## G. Note Workflow Rules

### G.1 Bridge funding is public

Goal: keep bridge funding guidance accurate before note workflows.

When to use: bridge balance is missing or the guide recommends bridge deposit.

Minimal user actions: choose amount, review the warning summary, and run the bridge deposit command.

AI may ask: amount, network, and account alias.

AI must not ask: private keys, wallet secrets, seed phrases, or provider credentials.

Command template:

```bash
private-state-cli account deposit-bridge --amount <TOKENS> --network <NETWORK> --account <ACCOUNT>
```

Success check: `account get-bridge-fund --json` shows available bridge balance.

Failure recovery: if account or RPC is missing, follow D.4 or D.3.

Optional explanation: bridge deposits and withdrawals expose the Ethereum account, vault, amount, and transaction hashes.

### G.2 Channel funding is separate

Goal: move bridge funds into channel accounting only after wallet join.

When to use: bridge balance exists but channel balance is zero.

Minimal user actions: choose amount, review the warning summary, and run channel deposit.

AI may ask: amount, wallet name, and network.

AI must not ask: wallet secrets, private keys, seed phrases, or provider credentials.

Command template:

```bash
private-state-cli wallet deposit-channel --wallet <WALLET> --network <NETWORK> --amount <TOKENS>
```

Success check: `wallet get-channel-fund --json` shows channel balance.

Failure recovery: if bridge balance is missing, follow G.1.

Optional explanation: channel funding does not happen automatically when bridge funds are deposited.

### G.3 Minting creates spendable private notes

Goal: create notes only after channel balance exists.

When to use: the wallet has channel balance and no usable notes.

Minimal user actions: choose amounts, review the warning summary, and run mint.

AI may ask: amounts JSON, wallet name, network, and optional transaction submitter.

AI must not ask: wallet secrets, private keys, seed phrases, or unrelated note plaintext.

Command template:

```bash
private-state-cli wallet mint-notes --wallet <WALLET> --network <NETWORK> --amounts <JSON_ARRAY>
```

Success check: `wallet get-notes --json` shows unused notes.

Failure recovery: if channel balance is missing, follow G.2.

Optional explanation: minted notes are the spendable private-state units for transfer or redeem.

### G.4 Transfer and redeem require existing notes

Goal: prevent fabricated transfers by checking available notes first.

When to use: the user wants to transfer or redeem notes.

Minimal user actions: inspect notes, select existing note IDs, then confirm the intended transfer or redeem command.

AI may ask: selected note IDs, recipients, amounts, wallet name, network, and optional transaction submitter.

AI must not ask: wallet secrets, private keys, seed phrases, or unrelated note plaintext.

Command template:

```bash
private-state-cli wallet get-notes --wallet <WALLET> --network <NETWORK> --json
```

Success check: selected note IDs exist and have enough value for the intended action.

Failure recovery: if notes are missing, follow G.1, G.2, and G.3 instead of changing recipients, amounts, or command
shape without user approval.

Optional explanation: note transfers use existing note commitments; the CLI cannot spend notes that do not exist in the
wallet.

### G.5 Transaction submitter option

Goal: explain optional transaction-submission privacy without changing ownership semantics.

When to use: proof-backed commands such as mint, transfer, or redeem may use a separate Ethereum submitter account.

Minimal user actions: decide whether to use a separate imported local account for gas submission.

AI may ask: submitter account alias if the user wants this option.

AI must not ask: private keys, wallet secrets, seed phrases, or submitter private key contents.

Command template:

```bash
private-state-cli wallet transfer-notes --wallet <WALLET> --network <NETWORK> --note-ids <JSON_ARRAY> --recipients <JSON_ARRAY> --amounts <JSON_ARRAY> --tx-submitter <ACCOUNT>
```

Success check: the command accepts the submitter alias and submits with that local account.

Failure recovery: if submitter account is missing, import it with B.1 through B.3 or omit `--tx-submitter`.

Optional explanation: the wallet owner still proves note ownership; the submitter only submits the on-chain transaction
and pays gas.

### G.6 Exit safety

Goal: avoid channel exit while remaining balances or state make exit unsafe or invalid.

When to use: the guide recommends or the user asks for channel exit.

Minimal user actions: inspect balances and confirm intent.

AI may ask: wallet name, network, and exit confirmation.

AI must not ask: secrets or credentials.

Command template:

```bash
private-state-cli wallet get-channel-fund --wallet <WALLET> --network <NETWORK> --json
```

Success check: channel balance and related state allow exit before running `channel exit`.

Failure recovery: if balance remains, transfer, redeem, withdraw, or otherwise resolve state before exit.

Optional explanation: exit rules protect bridge and wallet accounting consistency.

## H. Discovery Commands

### H.1 State discovery

Goal: discover local and on-chain state through CLI commands instead of filesystem inspection.

When to use: selectors are missing, wallet name is unknown, balances are unclear, or the guide asks for more state.

Minimal user actions: run the smallest read-only command that answers the current question.

AI may ask: network, channel name, account alias, or wallet name.

AI must not ask: secrets, private keys, wallet secrets, seed phrases, or secret file contents.

Command template:

```bash
private-state-cli help guide --network <NETWORK> --channel-name <CHANNEL> --account <ACCOUNT> --wallet <WALLET> --json
private-state-cli wallet list --network <NETWORK>
private-state-cli wallet get-meta --wallet <WALLET> --network <NETWORK>
private-state-cli account get-bridge-fund --account <ACCOUNT> --network <NETWORK>
private-state-cli wallet get-channel-fund --wallet <WALLET> --network <NETWORK>
```

Success check: the command returns the public selector, metadata, or balance needed for the next step.

Failure recovery: if a selector is unknown, start with `help guide --network <NETWORK> --json` and add selectors as they
become known.

Optional explanation: these commands are read-only discovery commands; they should be preferred over manual folder
inspection.

### H.2 JSON command output handling

Goal: parse CLI JSON mode correctly without treating progress or warnings as fatal results.

When to use: the AI runs any `private-state-cli ... --json` command on behalf of the user.

Minimal user actions: none beyond authorizing the command when needed.

AI may ask: whether to proceed with a transaction-sending command.

AI must not ask: the user to manually parse JSONL progress events or reveal secrets from logs.

Command template:

```bash
private-state-cli <COMMAND> ... --json
```

Success check: stdout contains the final JSON success or failure result. In JSON mode, stderr may contain JSON Lines for
progress, warning, or informational events; summarize them for the user instead of treating them as the final result.

Failure recovery: if stdout contains `{ "ok": false, ... }`, read the error and any `Try:` hints, then follow F.4.

Optional explanation: JSON mode separates machine-readable final results on stdout from streaming progress events on
stderr.

### H.3 Fee and cost questions

Goal: answer gas, transaction fee, transaction cost, or USD cost questions from the CLI's measured fee report.

When to use: the user asks about gas use, transaction fees, transaction cost, or USD cost for private-state CLI
commands.

Minimal user actions: choose the network if it is unclear.

AI may ask: network.

AI must not ask: private keys, wallet secrets, seed phrases, provider passwords, or wallet balances unless a separate
balance question requires a read-only balance command.

Command template:

```bash
private-state-cli help transaction-fees --network <NETWORK> --json
```

Success check: the result contains `rows`; answer from those rows instead of guessing.

Failure recovery: if the network is unclear, ask which network to use. If the command fails, follow F.4 and the printed
CLI corrective guidance before escalating.

Optional explanation: fee estimates combine packaged measured gas data with live network fee data and ETH/USD pricing.

### H.4 Command result recovery discipline

Goal: avoid inventing alternate workflows when the CLI already reports a precise correction.

When to use: any command returns an error, warning, or partial progress that the user asks about.

Minimal user actions: let the AI inspect the exact command result and run the smallest corrective command.

AI may ask: public selectors needed by the printed hint, and confirmation before transaction-sending or destructive
actions.

AI must not ask: secrets, seed phrases, wallet secrets, private keys, provider passwords, or broad approval to change the
workflow.

Command template:

```bash
private-state-cli help guide --network <NETWORK> --channel-name <CHANNEL> --account <ACCOUNT> --wallet <WALLET> --json
```

Success check: the next command follows CLI hints, `help guide --json`, or an indexed recipe in this file.

Failure recovery: if multiple corrective paths are possible, explain the smallest safe path and ask the user to choose
only when the choice changes public actions, cost, recovery time, or privacy implications.

Optional explanation: the agent should prefer CLI-authored recovery paths because they are aligned with current command
behavior and local state checks.

## I. Plain-Language Explanations

### I.1 Private key source file

Goal: explain private key source files only when useful for the next action.

When to use: the user asks what the file is, appears confused, or must decide whether to create/use a source file.

Minimal user actions: no extra action unless B.1 or B.2 is needed.

AI may ask: whether the user wants to proceed with the default helper command.

AI must not ask: private key contents, seed phrase, wallet password, or screenshots showing secrets.

Command template:

```bash
private-state-cli secret create-private-key-source --output ./ethereum-private-key.txt
```

Success check: the user understands enough to run B.1 without revealing the key in chat.

Failure recovery: if the user is still unsure, explain that the CLI reads the source once during import and then uses a
protected local account alias.

Optional explanation: this is a local file containing the Ethereum private key for one-time import into the CLI.

### I.2 Account nickname

Goal: explain account aliases only when the user needs to choose or use one.

When to use: before `account import`, `account get-l1-address`, bridge funding, or channel join.

Minimal user actions: choose a local account alias.

AI may ask: preferred account alias.

AI must not ask: private key contents, seed phrase, or wallet password.

Command template:

```bash
private-state-cli account import --account <ACCOUNT> --network <NETWORK> --private-key-file ./ethereum-private-key.txt
```

Success check: `account get-l1-address --json` returns the expected Ethereum address.

Failure recovery: if the alias already exists, verify it with B.3 before reusing it.

Optional explanation: after import, signing commands use `--account <ACCOUNT>` instead of asking for the private key.

### I.3 Wallet secret source file

Goal: explain wallet secret source files only when useful for setup or recovery.

When to use: before wallet secret creation, channel join, or spending-key recovery.

Minimal user actions: run B.4 or preserve an existing local source file.

AI may ask: whether to use the default path or an existing local path.

AI must not ask: wallet secret contents, private key contents, seed phrase, or password/passphrase contents.

Command template:

```bash
private-state-cli secret create-wallet-secret-source --output ./wallet-secret.txt
```

Success check: the user can proceed to B.6 or B.7 without revealing the secret.

Failure recovery: if the user lost the source and protected key material, explain the recovery limitation and avoid
promising reconstruction.

Optional explanation: this is a separate user-kept secret used during channel join to derive channel-bound wallet
authority; it is not the Ethereum private key.

### I.4 RPC URL

Goal: explain RPC URLs only when needed for setup or troubleshooting.

When to use: RPC is missing, the user asks what an RPC URL is, or chain ID validation fails.

Minimal user actions: get the endpoint URL from a provider such as Ankr or from their own node.

AI may ask: endpoint URL and selected network.

AI must not ask: provider password, dashboard access, seed phrase, private key, wallet secret, or billing credentials.

Command template:

```bash
private-state-cli set rpc --network <NETWORK> --rpc-url <URL> --provider ankr
```

Success check: `help guide --network <NETWORK> --json` no longer reports missing RPC.

Failure recovery: if chain ID validation fails, use an endpoint for the selected network. If provider limits are unknown,
follow C.5.

Optional explanation: an RPC URL is the provider endpoint the CLI uses to read chain state and send transactions. The CLI
requires the user to configure one and does not have a default endpoint.

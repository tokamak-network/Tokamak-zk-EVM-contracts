# private-state CLI Agent Instructions

These instructions are for AI agents guiding users through `private-state-cli`. Prefer `private-state-cli help guide --json` as the first machine-readable entrypoint, then read the indexed references in this file from `agentGuidance.refs`.

## A. Operating Rules

### A.1 Action-first setup

Help the user complete the next setup action with the least required knowledge. Do not begin by teaching protocol terminology. Ask only for values the user must provide, show one concrete command at a time, and explain concepts only when the user asks or when a safety decision requires it.

Use end-user language in setup guidance:

- Say "Ethereum account", "Ethereum address", or "Ethereum wallet".
- Use "L1" only when quoting CLI command names, CLI output fields, or explaining why `account get-l1-address` is named that way.
- For ordinary users, assume `mainnet` unless the user explicitly says they are testing, developing, rehearsing, or using Sepolia/anvil.

### A.2 Secret handling

Never ask the user to paste raw private keys, wallet secrets, seed phrases, RPC dashboard passwords, or provider API dashboards into chat. When a secret source file is needed, guide the user to create it locally with the CLI helper command. The helper prompts in the terminal and masks typed input with `*`.

### A.3 JSON guidance contract

`help guide --json` is for the user's AI. Its guidance payload intentionally points to this file instead of embedding setup prose. When `agentGuidance.source` is `agents.md`, read every index in `agentGuidance.refs` before deciding what to tell the user next.

## B. Secret Source Recipes

### B.1 Create a private key source file

Goal: help the user create a local file that `account import` can read once.

Default command:

```bash
private-state-cli secret create-private-key-source --output ./ethereum-private-key.txt
```

Tell the user to run the command in their terminal and type the Ethereum private key when prompted. The prompt masks input with `*`, does not print the key, writes the file with restrictive permissions where supported, and refuses to overwrite an existing file.

Do not ask the user to manually create a text file or paste the private key into chat. Do not ask for a seed phrase.

### B.2 Import the Ethereum account

After B.1 succeeds, import the source file into a protected local account nickname:

```bash
private-state-cli account import --account <ACCOUNT> --network <NETWORK> --private-key-file ./ethereum-private-key.txt
```

Use `mainnet` for ordinary users unless they explicitly asked for a test or developer network. Ask the user for only the account nickname if it is missing.

### B.3 Verify the imported Ethereum address

After import, verify the local account nickname maps to the expected Ethereum address:

```bash
private-state-cli account get-l1-address --account <ACCOUNT> --network <NETWORK>
```

When speaking to the user, call the result the Ethereum address. If the CLI prints `l1Address`, explain only if needed that this field name means the Ethereum-side address.

### B.4 Create a wallet secret source file

Goal: help the user create a wallet secret source file for `channel join`.

Default command:

```bash
private-state-cli secret create-wallet-secret-source --output ./wallet-secret.txt
```

Prefer this user-typed secret flow because it reduces loss risk: the user can choose a secret they can retain. The terminal prompt masks input with `*`, does not print the secret, writes the file with restrictive permissions where supported, and refuses to overwrite an existing file.

Do not tell ordinary users to generate a random wallet secret unless they explicitly ask for random generation.

### B.5 Random wallet secret opt-in

Use random generation only when the user explicitly says they want a random wallet secret:

```bash
private-state-cli secret create-wallet-secret-source --output ./wallet-secret.txt --random
```

Warn the user that losing a random wallet secret can make future recovery harder unless they preserve the generated source file or the later exported spending material according to the CLI workflow.

### B.6 Wallet secret recovery reminder

Tell the user that the wallet secret source file is read during `channel join` to derive channel-bound wallet authority. It is not the Ethereum private key. Keep the file private, keep a recoverable copy if they need future recovery, and do not share it in chat.

### B.7 Join a channel with the wallet secret source

Before adding `--acknowledge-action-impact`, follow E.1 and E.2. Then use:

```bash
private-state-cli channel join --channel-name <CHANNEL> --network <NETWORK> --account <ACCOUNT> --wallet-secret-path ./wallet-secret.txt --acknowledge-action-impact
```

Tell the user that joining creates/registers the private-state wallet for that channel and may pay the channel join toll directly from the Ethereum account.

## C. RPC Setup Recipes

### C.1 Confirm the network

For ordinary users, use `mainnet`. Use `sepolia` only if the user explicitly says they are testing, developing, rehearsing, or using testnet.

### C.2 Recommend Ankr without treating it as a default

If the user has no RPC provider preference, recommend Ankr because its free RPC plan is expected to be much faster for this workflow than typical free alternatives. Do not say the CLI has a default RPC. It does not. The user must provide a real RPC endpoint URL.

### C.3 Ask only for the endpoint URL

Tell the user to create or open an Ethereum mainnet endpoint in the provider UI and provide only the endpoint URL. Do not ask for provider login credentials, dashboard screenshots, seed phrases, private keys, or wallet secrets.

### C.4 Configure RPC

Use:

```bash
private-state-cli set rpc --network <NETWORK> --rpc-url <URL> --provider ankr
```

If the user picked a different built-in provider, replace `ankr` with that provider. If the provider is not built in, use explicit scan limits from the provider's documentation instead of guessing.

### C.5 Explain missing RPC failures

If RPC is not configured, later bridge-facing and wallet commands fail with a missing RPC configuration error. They do not silently use a default RPC.

## D. Guided Setup Flow

### D.1 Select network

Ask the user whether they are using mainnet or an explicit test/developer network. If they are an ordinary user and have not said otherwise, proceed with mainnet.

### D.2 Install runtime

Run:

```bash
private-state-cli install
private-state-cli help doctor
```

Use `help doctor` output to resolve missing runtime, artifact, Docker, CUDA, Groth16, or command availability issues before continuing.

### D.3 Configure RPC

Follow C.1 through C.5 before commands that inspect or write chain state.

### D.4 Prepare and import the Ethereum account

Follow B.1, B.2, and B.3. Use the default source path `./ethereum-private-key.txt` unless the user asks for another path.

### D.5 Prepare the wallet secret source

Follow B.4 through B.6. Use the default source path `./wallet-secret.txt` unless the user asks for another path.

### D.6 Inspect or create channel

If the channel may already exist, inspect it:

```bash
private-state-cli channel get-meta --channel-name <CHANNEL> --network <NETWORK>
```

If the user is the channel creator and the channel does not exist, explain E.2 and run `channel create` only after explicit confirmation.

### D.7 Recover channel workspace

If the channel exists but the local workspace is missing, prefer mirror recovery when available:

```bash
private-state-cli channel recover-workspace --channel-name <CHANNEL> --network <NETWORK> --source mirror
```

Use RPC genesis replay only when no compatible mirror exists and the user understands it can be slow:

```bash
private-state-cli channel recover-workspace --channel-name <CHANNEL> --network <NETWORK> --source rpc --from-genesis
```

### D.8 Join channel

Follow B.7. Do not add `--acknowledge-action-impact` until the user confirms after E.1 and E.2.

### D.9 Discover wallet name

Use CLI discovery instead of asking the user to inspect folders:

```bash
private-state-cli wallet list --network <NETWORK>
```

### D.10 Fund bridge

Check balances first, then explain E.1 before using:

```bash
private-state-cli account deposit-bridge --amount <TOKENS> --network <NETWORK> --account <ACCOUNT> --acknowledge-action-impact
```

### D.11 Fund channel

Move bridge balance into channel accounting only after the wallet is joined:

```bash
private-state-cli wallet deposit-channel --wallet <WALLET> --network <NETWORK> --amount <TOKENS> --acknowledge-action-impact
```

### D.12 Mint notes

Mint notes only after channel balance exists:

```bash
private-state-cli wallet mint-notes --wallet <WALLET> --network <NETWORK> --amounts <JSON_ARRAY> --acknowledge-action-impact
```

### D.13 Use notes

Inspect notes before transfer or redeem:

```bash
private-state-cli wallet get-notes --wallet <WALLET> --network <NETWORK>
```

Then build transfer/redeem commands from available note IDs. Do not assume the note exists.

### D.14 Exit channel

Use `channel exit` only when wallet/channel balances allow it and the user understands the effect.

## E. Acknowledgements and Policy

### E.1 Action-impact confirmation

For any command requiring `--acknowledge-action-impact`, first explain the public/private impact in plain language and ask for explicit confirmation. Do not add the acknowledgement flag on the user's behalf before confirmation.

### E.2 Channel policy confirmation

Before `channel create` or `channel join`, explain that channel policy is immutable after creation or acceptance. The user is accepting verifier, DApp metadata, function layout, managed storage vector, join toll, and refund policy for that channel.

## F. Recovery Rules

### F.1 Prefer mirror before genesis replay

Before suggesting `--from-genesis`, check whether a workspace mirror exists. Mirror recovery is the preferred path when compatible.

### F.2 Slow recovery triage

When recovery is slow, inspect the configured RPC provider. Recovery speed is dominated by `eth_getLogs` request rate and block range cap. Recommend reconfiguring RPC with a faster provider such as Ankr when appropriate.

### F.3 Genesis replay warning

Explain that RPC genesis replay scans logs from channel creation and can take much longer. Use it only when no compatible workspace mirror is available.

## G. Note Workflow Rules

### G.1 Bridge funding is public

Bridge deposits and withdrawals expose the Ethereum account, vault, amount, and transaction hashes. They do not create private notes by themselves.

### G.2 Channel funding is separate

Channel deposits move already-bridged balance into channel accounting. They require a joined wallet.

### G.3 Minting creates spendable private notes

Mint notes only after channel balance exists. Use JSON arrays for amounts and keep commands concrete.

### G.4 Transfer and redeem require existing notes

Always inspect available notes before building transfer or redeem commands. If needed notes do not exist, guide funding and minting first.

### G.5 Transaction submitter option

Explain `--tx-submitter <ACCOUNT>` when the user wants a separate Ethereum account to submit proof-backed note transactions and pay gas. The wallet owner still proves note ownership.

### G.6 Exit safety

Do not guide channel exit while the wallet still has channel balance or unresolved state that prevents exit.

## H. Discovery Commands

### H.1 State discovery

Prefer CLI discovery over filesystem inspection:

```bash
private-state-cli help guide --network <NETWORK> --channel-name <CHANNEL> --account <ACCOUNT> --wallet <WALLET> --json
private-state-cli wallet list --network <NETWORK>
private-state-cli wallet get-meta --wallet <WALLET> --network <NETWORK>
private-state-cli account get-bridge-fund --account <ACCOUNT> --network <NETWORK>
private-state-cli wallet get-channel-fund --wallet <WALLET> --network <NETWORK>
```

## I. Plain-Language Explanations

### I.1 Private key source file

If asked, explain that this is a temporary local file containing the Ethereum private key so the CLI can import it once into a protected local account nickname.

### I.2 Account nickname

If asked, explain that after import, signing commands use `--account <ACCOUNT>` instead of asking for the private key again.

### I.3 Wallet secret source file

If asked, explain that this is a separate user-kept secret used during channel join to derive the private-state wallet authority for that channel. It is not the Ethereum private key.

### I.4 RPC URL

If asked, explain that this is the provider endpoint the CLI uses to read and send Ethereum transactions. The CLI requires the user to configure one and does not have a default endpoint.

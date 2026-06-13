# Private-State CLI Browser Wallet Manual Verification

## Audience

This checklist is for repository developers and release reviewers who verify the private-state CLI browser-wallet path
before shipping or enabling it for users. It assumes the verifier controls the browser wallet accounts and performs all
wallet approvals personally.

## Scope

The goal is to verify that browser-wallet mode can exercise the L1 authority paths without the CLI reading, importing,
or storing the user's raw L1 private key. The checklist also verifies that local L2 spending and viewing keys remain the
authority for private-state note operations.

This checklist must not be executed by an AI agent that clicks wallet-extension approval UI. The CLI may open a local
signing relay page, but the verifier must inspect and approve or reject each wallet request directly in the wallet
extension UI. The localhost page is not an approval UI and must not present a CLI-controlled approval button.

## Automated Preflight Log

- Date: 2026-06-13
- Repository path: `/Users/jehyuk/repo/Tokamak-zk-EVM-contracts`
- Command: `npm run test:agent-guidance`
- Result: passed
- Browser application scan: `/Applications/Google Chrome.app` detected
- Second MetaMask-capable browser: not detected in `/Applications`
- Follow-up command: `npm run test:agent-guidance`
- Follow-up result: passed on 2026-06-13
- Browser-wallet transaction diagnostic implementation check: `npm run test:agent-guidance`
- Browser-wallet transaction diagnostic result: passed on 2026-06-14
- Non-interactive browser-wallet check:
  `HOME=$(mktemp -d) node packages/apps/private-state/cli/private-state-bridge-cli.mjs account get-l1-address --network mainnet --json`
- Non-interactive result: exited with status `1` and reported that browser-wallet signing requires interactive human
  approval and cannot run in `--json` mode.
- Temporary HOME file check: file count remained `0`, so the non-interactive browser-wallet failure did not write a
  local account key or any other file.
- Sepolia RPC configuration: completed on 2026-06-13 with a local Alchemy RPC URL stored under the CLI workspace.
- Full artifact installation: completed on 2026-06-13 after human Terms acceptance in the browser.

The browser scan only confirms an installed browser application. It does not prove that MetaMask or another compatible
EIP-1193 provider is installed, unlocked, funded, or connected to the intended network.

The automated checks above do not replace manual wallet approval. They only prove that the test suite covers the
browser-wallet callback protocol and that the CLI refuses browser-wallet signing in non-interactive JSON mode without
writing files.

## Preconditions

- Install the current private-state CLI build from this working tree or run it directly from `packages/apps/private-state/cli`.
- Configure RPC for the target network with `private-state-cli set rpc`.
- Install private-state runtime artifacts with `private-state-cli install` for transaction-sending commands.
- Use a newly created test channel and test funds unless production release verification explicitly requires mainnet.
- Install MetaMask or an equivalent EIP-1193 provider in each browser under test.
- Prepare at least two browser wallet accounts:
  - the expected wallet owner account
  - a different account for wrong-account failure testing
- Prepare a wallet secret source file with `private-state-cli secret create-wallet-secret-source`.
- Before running a destructive or funds-moving command, record the starting balances and wallet workspace path.

When Sepolia is used for release verification, create a fresh channel for this checklist instead of relying on an
already deployed channel whose original `channelName` may be unavailable. The bridge stores `channelId` on-chain, but
the CLI derives that value from `keccak256(utf8(channelName))`; without the original channel name, commands such as
`channel join` cannot target the channel by name.

## Browser Coverage

Run the success and failure checks in at least two MetaMask-capable browsers when available.

| Browser | Provider | Result | Notes |
| --- | --- | --- | --- |
| Google Chrome | MetaMask-compatible provider | Partially passed | Account address discovery passed with user-controlled wallet approval. Transaction, key-derivation, and failure-path checks are still not run. |
| Second browser | MetaMask-compatible provider | Not run | No second browser application was detected during automated preflight. |

## Success Path Checks

### Account Address Discovery

Command:

```bash
private-state-cli account get-l1-address --network <NETWORK>
```

Expected result:

- The CLI opens or prints a localhost signing URL.
- The browser relay page automatically requests account connection through the wallet.
- The command prints the selected browser wallet address.
- No local account private-key file is created.

Manual result on 2026-06-13:

- Result: passed in Google Chrome with a MetaMask-compatible provider.
- Command run from the repository checkout:
  `node packages/apps/private-state/cli/private-state-bridge-cli.mjs account get-l1-address --network mainnet`
- The CLI opened `http://127.0.0.1:<ephemeral-port>/sign?...` and printed the signing URL.
- The browser wallet account connection was approved by the human verifier, not by automation.
- The CLI returned the selected browser wallet address, redacted here as `0x90dFe9...362f`.
- The command output did not contain a private-key field and did not submit a transaction.

### Create A New Test Channel Without `--account`

Use this step before `channel join` when no verified named test channel already exists. Choose a unique channel name
that includes the date and a short verifier-controlled suffix, for example `browser-wallet-test-20260613-a1b2`.

Command:

```bash
private-state-cli channel create \
  --channel-name <NEW_TEST_CHANNEL> \
  --join-toll 0 \
  --network sepolia
```

Expected wallet requests:

1. account connection
2. chain check
3. network switch when the browser wallet is not already on Sepolia
4. `createChannel` transaction

Expected result:

- The browser wallet submits the `createChannel` transaction.
- The selected browser account becomes the channel leader.
- The CLI creates or refreshes the local workspace for `<NEW_TEST_CHANNEL>`.
- The command output records the channel id, channel manager, Join Toll, and policy snapshot.
- No local L1 private-key file is created.

Use `--join-toll 0` for the default release-verification path so that later `channel join` can verify key derivation and
join submission without requiring a Join Toll token approval. If the Join Toll approval path must also be verified, run a
separate test channel with a small nonzero Join Toll and record the extra approval request explicitly.

Manual result on 2026-06-13:

- Result: failed closed before transaction submission before automatic network switching was added.
- Test channel name: `browser-wallet-test-20260613-c2fc`.
- The first attempt failed before browser-wallet approval because the full installation prerequisites were missing.
- After full installation, the CLI opened the browser-wallet connection page and the human verifier approved account
  connection.
- The next browser-wallet request checked `eth_chainId`; it returned chain `1` while the selected CLI network required
  chain `11155111`.
- The CLI failed with `Browser wallet chain 1 does not match selected network chain 11155111.`
- No `createChannel` transaction was submitted.
- The Sepolia workspace contained only `rpc-config.env`; no new channel workspace was created.
- No Sepolia local account secret directory was created.

Manual retry result on 2026-06-13 after automatic network switching was added:

- Result: failed closed at the transaction submission approval step.
- Test channel name: `browser-wallet-test-20260613-c2fc`.
- The CLI requested account connection, `eth_chainId`, `wallet_switchEthereumChain`, and a rechecked `eth_chainId`.
- The browser wallet switched from chain `1` to Sepolia chain `11155111`, and the command continued to the policy
  warning and `createChannel` transaction request.
- The `createChannel` transaction was not submitted because the browser wallet returned
  `The requested account and/or method has not been authorized by the user.`
- The Sepolia workspace still contained only `rpc-config.env`; no new channel workspace was created.
- No Sepolia local account secret directory was created.

Manual retry result on 2026-06-13 after removing the localhost approval button:

- Result: failed before transaction submission because the per-request browser bridge used different localhost ports for
  account connection and transaction submission.
- Test channel name: `browser-wallet-test-20260613-relay2`.
- The relay page loaded and reported provider request start for account connection, network check, and send transaction.
- The browser wallet returned `The requested account and/or method has not been authorized by the user.` at
  `eth_sendTransaction`.
- Diagnosis: browser wallet permissions are origin-scoped, so approving `eth_requestAccounts` on one localhost port does
  not authorize `eth_sendTransaction` from another localhost port.
- No `createChannel` transaction was submitted.
- The Sepolia workspace still contained only `rpc-config.env`; no new channel workspace was created.
- No Sepolia local account secret directory was created.

Manual retry result on 2026-06-13 after switching the browser bridge to one localhost origin per CLI command:

- Result: reached the transaction-signature prompt and failed closed after the human verifier rejected the transaction
  signature in the browser wallet UI.
- Test channel name: `browser-wallet-test-20260613-relay3`.
- The CLI reused the same localhost port for account connection, network check, and send transaction. Each request used
  a different request id under the same session token.
- The relay page loaded and reported provider request start for each browser-wallet request.
- The command continued past account connection and network check, printed the immutable channel policy warning, and
  requested the `createChannel` transaction.
- The `createChannel` transaction was not submitted because the browser wallet returned
  `MetaMask Tx Signature: User denied transaction signature.`
- The Sepolia workspace still contained only `rpc-config.env`; no new channel workspace was created.
- No Sepolia local account secret directory was created.

Manual retry results on 2026-06-14:

- Result: still blocked at browser-wallet `eth_sendTransaction` authorization.
- Test channel names: `browser-wallet-test-20260614-a1` through `browser-wallet-test-20260614-a6`.
- The CLI reached account connection, network check, policy warning, connected-account checks, and send transaction
  relay requests on the same localhost origin.
- Additional implementation hardening tried during these attempts:
  - transaction submission now checks `eth_accounts` before `eth_sendTransaction`
  - unauthorized transaction submission triggers one `wallet_requestPermissions` account-permission refresh, then one
    retry
  - connected-account checks require the first active browser account to match the transaction sender
  - the browser bridge now keeps one persistent relay page open and feeds later requests through `/request`
  - the relay page performs an immediate `eth_requestAccounts` preflight in the same browser function before
    `eth_sendTransaction`
- Despite those changes, the browser wallet still returned `Unauthorized.` for `eth_sendTransaction`.
- Follow-up cleanup removed the extra `eth_accounts`, `wallet_requestPermissions`, retry, and transaction preflight
  prompts because they did not resolve the failure and made the user approval sequence harder to understand. The
  persistent relay page and same-origin browser session remain.
- Follow-up implementation added structured `eth_sendTransaction` failure diagnostics without retrying, switching
  accounts, or requesting extra wallet permissions. The next manual retry should record the diagnostic output.
- No `createChannel` transaction was submitted.
- The Sepolia workspace still contained only `rpc-config.env`; no new channel workspace was created.
- No Sepolia local account secret directory was created.
- Next manual check should inspect the browser wallet connected-sites state for the localhost origin, reset that
  connection if needed, and retry `channel create` with the persistent relay page open.

### Channel Join Without `--account`

Command:

```bash
private-state-cli channel join \
  --channel-name <NEW_TEST_CHANNEL> \
  --network sepolia \
  --wallet-secret-path ./wallet-secret.txt
```

Expected wallet requests:

1. account connection
2. chain check
3. EIP-191 message signature for L2 spending-key derivation
4. EIP-712 typed-data signature for note-receive viewing-key derivation
5. Join Toll token approval when the Join Toll is nonzero
6. `joinChannel` transaction

Expected local result:

- The wallet workspace is created for `<NEW_TEST_CHANNEL>-<BROWSER_WALLET_ADDRESS>`.
- The wallet metadata records the selected L1 address and derived L2 address.
- L2 spending and viewing key files are written under the existing wallet-key model.
- No raw L1 private-key file is written.

### Account Bridge Deposit Without `--account`

Command:

```bash
private-state-cli account deposit-bridge \
  --amount <TOKENS> \
  --network <NETWORK>
```

Expected result:

- The browser wallet submits the token approval when needed.
- The browser wallet submits the bridge `fund` transaction.
- The CLI does not force a nonce override in browser-wallet mode.
- The shared bridge vault balance increases for the selected browser wallet account.

### Wallet Deposit And Withdraw Channel

Commands:

```bash
private-state-cli wallet deposit-channel \
  --wallet <WALLET> \
  --network <NETWORK> \
  --amount <TOKENS>

private-state-cli wallet withdraw-channel \
  --wallet <WALLET> \
  --network <NETWORK> \
  --amount <TOKENS>
```

Expected result:

- If no local L1 owner key exists, the CLI requests browser-wallet owner approval.
- The selected browser account must match the wallet `l1Address`.
- The L2 accounting proof still uses the local wallet spending key.
- The L1 transaction is submitted through the browser wallet.

### Note Commands With Browser Submitter

Commands:

```bash
private-state-cli wallet mint-notes \
  --wallet <WALLET> \
  --network <NETWORK> \
  --amounts '["<TOKENS>"]' \
  --tx-submitter

private-state-cli wallet transfer-notes \
  --wallet <WALLET> \
  --network <NETWORK> \
  --note-ids '<JSON_ARRAY>' \
  --recipients '<JSON_ARRAY>' \
  --amounts '<JSON_ARRAY>' \
  --tx-submitter

private-state-cli wallet redeem-notes \
  --wallet <WALLET> \
  --network <NETWORK> \
  --note-ids '<JSON_ARRAY>' \
  --tx-submitter
```

Expected result:

- The wallet spending key signs the Tokamak L2 transaction snapshot locally.
- The browser wallet submits only the L1 `executeChannelTransaction`.
- The result records `txSubmitterSource` as browser wallet submission.
- No local L1 private key is imported or written.

### Channel Exit

Command:

```bash
private-state-cli channel exit \
  --wallet <WALLET> \
  --network <NETWORK>
```

Expected result:

- The command first validates that channel fund is zero using stored wallet identity.
- The browser wallet owner approval is requested once before transaction submission.
- The selected browser wallet address must match the wallet `l1Address`.
- The wallet epoch is marked exited after the accepted transaction.

## Failure Path Checks

### Wrong Chain

Procedure:

1. Select a browser wallet network that does not match `--network`.
2. Run a browser-wallet command that has a provider, such as `channel create` or `account get-bridge-fund`.

Expected result:

- The CLI detects the wrong browser wallet chain before transaction submission.
- The CLI requests `wallet_switchEthereumChain` for the selected CLI network.
- If the user approves the switch and the rechecked `eth_chainId` matches, the command continues.
- If the user rejects the switch, the wallet does not support the target chain, or the rechecked chain still does not
  match, the CLI fails before transaction submission.
- The CLI does not retry with a local private key.

Manual result on 2026-06-13:

- Result: passed for the pre-switch fail-closed behavior.
- Triggering command: `channel create --channel-name browser-wallet-test-20260613-c2fc --join-toll 0 --network sepolia`.
- The browser wallet was connected to chain `1`, while the CLI selected Sepolia chain `11155111`.
- The CLI failed before transaction submission and did not fall back to a local private key.

Manual retry result on 2026-06-13:

- Result: passed for the automatic switch path.
- Triggering command: `channel create --channel-name browser-wallet-test-20260613-c2fc --join-toll 0 --network sepolia`.
- The CLI requested `wallet_switchEthereumChain`, rechecked `eth_chainId`, and continued after the wallet reported
  Sepolia chain `11155111`.
- The later transaction request failed closed because the browser wallet did not authorize the requested account or
  method.
- The CLI did not fall back to a local private key.

### Wrong Account

Procedure:

1. Use an existing wallet workspace.
2. Select a browser wallet account that is not the wallet `l1Address`.
3. Run `wallet deposit-channel`, `wallet withdraw-channel`, or `channel exit`.

Expected result:

- The CLI fails before transaction submission.
- The error identifies the selected address and the required wallet owner address.
- The CLI does not retry with another account or local private key.

### User Rejection

Procedure:

1. Start any browser-wallet command.
2. Reject the wallet request in the browser wallet.

Expected result:

- The CLI fails closed.
- The error reports that the browser wallet request failed.
- No transaction is submitted.

### No Provider

Procedure:

1. Open the printed localhost signing URL in a browser without MetaMask or an equivalent provider.
2. Wait for the relay page to start the wallet provider request.

Expected result:

- The browser page reports that no MetaMask-compatible provider was found.
- The CLI fails closed.

### Closed Browser Or Timeout

Procedure:

1. Start a browser-wallet command.
2. Close the browser page or leave it unanswered until the timeout.

Expected result:

- The CLI exits with a timeout error.
- The CLI does not retry with a local private key.

## Local File Checks

After browser-wallet commands, inspect the private-state CLI home directory.

Expected result:

- Wallet spending and viewing keys may exist under the existing wallet-key storage rules.
- No new local account private-key file exists unless the verifier explicitly ran `account import`.
- Operation artifacts do not contain raw L1 private keys.
- Evidence exports, if created, still exclude `.key` files and account private keys.

## Completion Criteria

Manual verification is complete only when:

- At least one browser-wallet success path has been verified in a MetaMask-capable browser.
- Wrong-chain, wrong-account, user-rejection, no-provider, and timeout paths have been checked or explicitly marked not
  available with a reason.
- The existing local-account path has been checked for one L1 transaction command.
- The verifier confirms that browser-wallet commands did not write a raw L1 private-key file.

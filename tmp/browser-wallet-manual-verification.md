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
- Browser-wallet relay shutdown implementation check: `npm run test:agent-guidance`
- Browser-wallet relay shutdown implementation result: passed on 2026-06-14
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
| Google Chrome | MetaMask-compatible provider | Partially passed | Account address discovery and browser-wallet `channel create` transaction submission passed with user-controlled wallet approval. Key-derivation and later note-operation checks are still not run. |
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

Manual relay shutdown retry on 2026-06-14:

- Result: passed in Google Chrome with a MetaMask-compatible provider.
- Command run from the repository checkout:
  `node packages/apps/private-state/cli/private-state-bridge-cli.mjs account get-l1-address --network sepolia`.
- The browser wallet account connection was approved by the human verifier, not by automation.
- The CLI returned the selected browser wallet address as `0x094Ac5364EE8b6Db0e5b1E1C588be8617Fd499A1`.
- The command exited naturally with code `0` after printing the result, confirming that the browser-wallet relay shutdown
  path no longer leaves the CLI process alive for this success case.

Manual relay completion UX retry on 2026-06-14:

- Result: terminal path passed; browser final-state visual inspection was not available from the automation environment.
- Command run from the repository checkout:
  `node packages/apps/private-state/cli/private-state-bridge-cli.mjs account get-l1-address --network sepolia`.
- The browser wallet account connection was approved by the human verifier, not by automation.
- The CLI returned the selected browser wallet address as `0x094Ac5364EE8b6Db0e5b1E1C588be8617Fd499A1`.
- The command exited naturally with code `0` after printing the result.
- The implementation now returns a `{ "done": true }` completion response to the relay page before closing the
  localhost server and treats stale post-close polling failures as an ended CLI session. A human verifier should confirm
  that the relay page shows `Command finished. You can return to the terminal.` or `The CLI session has ended. You can
  close this page.` instead of raw `Failed to fetch`.

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

Manual diagnostic retry result on 2026-06-14:

- Result: failed closed at `eth_sendTransaction` with structured diagnostics.
- Test channel name: `browser-wallet-test-20260614-diagnostic-a1`.
- Wallet error message: `Unauthorized.`
- Wallet error code: `-32006`.
- Wallet error data: `{"httpStatus":401,"cause":null}`.
- Provider diagnostic: `provider.isMetaMask: true`.
- Account diagnostic: `eth_accounts` returned the same selected browser account as `transaction.from` and
  `signerAddress`, redacted here as `0x90dFe9...362f`.
- Chain diagnostic: `eth_chainId: 0xaa36a7`, matching Sepolia.
- Transaction diagnostic: `to: 0x1995B1cDe4e0a3F77bDeC297824504CdAc9a838E`, `value: null`,
  `dataByteLength: 132`.
- Interpretation: this result weakens the wrong-account and wrong-chain hypotheses. The strongest remaining hypothesis
  is that the MetaMask Sepolia RPC/backend used by the browser wallet is returning HTTP 401 when submitting the
  transaction.
- No `createChannel` transaction was submitted.
- The Sepolia workspace still contained only `rpc-config.env`; no new channel workspace was created.
- No Sepolia local account secret directory was created.
- Next manual check should inspect the MetaMask Sepolia network RPC configuration and verify that the browser wallet can
  submit a normal Sepolia transaction through that network before retrying private-state `channel create`.

Manual MetaMask Sepolia self-transaction diagnostic on 2026-06-14:

- Result: failed before transaction submission with the same browser-wallet error.
- Diagnostic action: opened a local one-off page that requested the connected MetaMask account and attempted a 0 ETH
  Sepolia self transaction from the selected account to the same account.
- Wallet error message: `Unauthorized.`
- Wallet error code: `-32006`.
- Wallet error data: `{"httpStatus":401,"cause":null}`.
- Interpretation: a plain MetaMask Sepolia transaction fails before any private-state calldata or contract target is
  involved. This makes the private-state `createChannel` payload and contract target unlikely to be the root cause.
  The strongest current hypothesis is that the MetaMask Sepolia RPC/backend configuration is unauthorized or otherwise
  not usable for transaction submission.
- No private-state `createChannel` transaction was submitted.
- The Sepolia workspace still contained only `rpc-config.env`; no new channel workspace was created.
- No Sepolia local account secret directory was created.
- Next manual step: fix or replace the Sepolia RPC configured inside MetaMask, then verify a normal Sepolia transaction
  succeeds before retrying private-state `channel create`.

Manual MetaMask Sepolia RPC repair attempt on 2026-06-14:

- Result: failed with the same browser-wallet error after proposing a public Sepolia RPC through MetaMask.
- Public RPC candidate checked from the CLI host: `https://ethereum-sepolia-rpc.publicnode.com`.
- CLI-side RPC check result for the public candidate: `eth_chainId` returned `11155111` and `eth_blockNumber` succeeded.
- Browser action: opened a local one-off page that called `wallet_addEthereumChain` with the public Sepolia RPC,
  `wallet_switchEthereumChain` for Sepolia, and then attempted a 0 ETH Sepolia self transaction.
- Wallet error message: `Unauthorized.`
- Wallet error code: `-32006`.
- Wallet error data: `{"httpStatus":401,"cause":null}`.
- Interpretation: proposing a public Sepolia RPC through `wallet_addEthereumChain` did not fix transaction submission.
  The most likely explanations are that MetaMask did not replace the existing Sepolia RPC configuration, or that the
  active Sepolia network endpoint used by MetaMask is still unauthorized. The next step requires manual MetaMask network
  settings inspection/editing rather than another CLI retry.

Manual retry result on 2026-06-14 after MetaMask network recovery:

- Result: failed closed after the human verifier rejected the `createChannel` transaction signature in MetaMask.
- Test channel name: `browser-wallet-test-20260614-recovered-a1`.
- Command run from the repository checkout:
  `node packages/apps/private-state/cli/private-state-bridge-cli.mjs channel create --channel-name browser-wallet-test-20260614-recovered-a1 --join-toll 0 --network sepolia`.
- The CLI reached account connection, network check, immutable policy review, and `eth_sendTransaction` from the same
  localhost relay origin.
- Wallet error message: `MetaMask Tx Signature: User denied transaction signature.`
- Wallet error code: `4001`.
- Wallet error data: `{"location":"confirmation","cause":null}`.
- Provider diagnostic: `provider.isMetaMask: true`.
- Account diagnostic: `eth_accounts` returned the same selected browser account as `transaction.from` and
  `signerAddress`, redacted here as `0x90dFe9...362f`.
- Chain diagnostic: `eth_chainId: 0xaa36a7`, matching Sepolia.
- Transaction diagnostic: `to: 0x1995B1cDe4e0a3F77bDeC297824504CdAc9a838E`, `value: null`,
  `dataByteLength: 132`.
- Interpretation: this retry confirms that the previous MetaMask `-32006` / HTTP 401 network failure was not reproduced
  after the verifier restored MetaMask. The browser-wallet path now reaches the wallet transaction confirmation UI, and
  the remaining result is a normal user-rejection failure path rather than a wallet backend authorization failure.
- No `createChannel` transaction was submitted.
- No workspace for `browser-wallet-test-20260614-recovered-a1` was found under the Sepolia private-state workspace.
- No Sepolia local account secret directory was found.
- Follow-up implementation check: after the wallet rejection, the CLI process remained alive until interrupted. The
  browser-wallet relay should shut down and let the command exit after terminal failure reporting.

Manual funded retry result on 2026-06-14 after Sepolia gas top-up:

- Result: passed. The browser wallet submitted `createChannel`, the transaction was mined successfully, and the CLI
  recovered the new channel workspace.
- Test channel name: `browser-wallet-test-20260614-funded-a1`.
- Command run from the repository checkout:
  `node packages/apps/private-state/cli/private-state-bridge-cli.mjs channel create --channel-name browser-wallet-test-20260614-funded-a1 --join-toll 0 --network sepolia`.
- The CLI reached account connection, network check, immutable policy review, and `eth_sendTransaction` from the same
  localhost relay origin.
- Channel id: `63166577588146897076769483836298559099274750786491139304148899339480295544043`.
- Leader: `0x094Ac5364EE8b6Db0e5b1E1C588be8617Fd499A1`.
- Manager: `0xF344b292D807116cF95dceA7c797CB3892e77beD`.
- Bridge Token Vault: `0xac95B08BBB7726ea71Eb9b055BEF8e9383d470eC`.
- Transaction hash: `0x969356b099a09d994369ed03a9f94b0946977507b07036447e306a51642c2d1a`.
- Transaction URL:
  `https://sepolia.etherscan.io/tx/0x969356b099a09d994369ed03a9f94b0946977507b07036447e306a51642c2d1a`.
- Block number: `11055070`.
- Gas used: `2739072`.
- Transaction status: `1`.
- Workspace path:
  `/Users/jehyuk/tokamak-private-channels/workspace/sepolia/browser-wallet-test-20260614-funded-a1`.
- Workspace file check found `channel/workspace.json`, `channel/current/block_info.json`,
  `channel/current/contract_codes.json`, `channel/current/state_snapshot.json`, and
  `channel/current/state_snapshot.normalized.json`.
- No Sepolia local account secret directory was found after the command, so the browser-wallet `channel create` path did
  not write a local L1 private key file.
- Follow-up implementation check: after the successful result was printed, the CLI process remained alive until
  interrupted. The browser-wallet relay should shut down and let the command exit after success reporting.

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

Manual result on 2026-06-14:

- Result: passed. The browser wallet completed account connection, chain check, EIP-191 message signing, EIP-712
  typed-data signing, and the final `joinChannel` transaction without `--account`.
- Test channel name: `browser-wallet-test-20260614-funded-a1`.
- Wallet secret source path:
  `/Users/jehyuk/tokamak-private-channels/manual-verification/browser-wallet-test-20260614-funded-a1-wallet-secret.txt`.
- Wallet secret source mode: random test source generated by
  `secret create-wallet-secret-source --random`; the secret value was not printed or recorded.
- Command run from the repository checkout:
  `node packages/apps/private-state/cli/private-state-bridge-cli.mjs channel join --channel-name browser-wallet-test-20260614-funded-a1 --network sepolia --wallet-secret-path /Users/jehyuk/tokamak-private-channels/manual-verification/browser-wallet-test-20260614-funded-a1-wallet-secret.txt`.
- Join Toll was `0`, so no token approval transaction was requested.
- Wallet name: `browser-wallet-test-20260614-funded-a1-0x094Ac5364EE8b6Db0e5b1E1C588be8617Fd499A1`.
- L1 address: `0x094Ac5364EE8b6Db0e5b1E1C588be8617Fd499A1`.
- L2 address: `0x50A7857Ad460D3e303a196Cf673dac5de3dA6078`.
- L2 storage key: `0x6961e46ebce90db685608b63573b365b981e8e0b7ff432e7fed3d1ba9e37eef1`.
- Leaf index: `45604138737`.
- Epoch id: `join-0x49e67519a09cb33578431d100bc79f808df958a0da439c0e642854283c25e503-615`.
- Join transaction hash: `0x49e67519a09cb33578431d100bc79f808df958a0da439c0e642854283c25e503`.
- Join transaction URL:
  `https://sepolia.etherscan.io/tx/0x49e67519a09cb33578431d100bc79f808df958a0da439c0e642854283c25e503`.
- Block number: `11055122`.
- Gas used: `296905`.
- Transaction status: `1`.
- Workspace file check found wallet notes metadata, wallet spending-key metadata, wallet viewing-key metadata, and the
  wallet index under the Sepolia channel workspace.
- Secret file check found L2 `spending.key` and `viewing.key` under the Sepolia wallet-key directory.
- No Sepolia local account secret directory was found after the command, so the browser-wallet `channel join` path did
  not write a local L1 private key file.
- The command exited naturally with code `0` after printing the result.

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

Manual result on 2026-06-14:

- Result: passed. The browser wallet submitted both the ERC-20 approval and bridge `fund` transaction without
  `--account`.
- Command run from the repository checkout:
  `node packages/apps/private-state/cli/private-state-bridge-cli.mjs account deposit-bridge --amount 0.001 --network sepolia`.
- L1 address: `0x094Ac5364EE8b6Db0e5b1E1C588be8617Fd499A1`.
- Canonical asset: `0xa30fe40285B8f5c0457DbC3B7C8A280373c40044`.
- Bridge Token Vault: `0xac95B08BBB7726ea71Eb9b055BEF8e9383d470eC`.
- Amount: `0.001`.
- Approval transaction hash: `0x15f66b038ca17a16052eecf4237bd2d7037845c9999e8e50655409efce2a278d`.
- Approval transaction URL:
  `https://sepolia.etherscan.io/tx/0x15f66b038ca17a16052eecf4237bd2d7037845c9999e8e50655409efce2a278d`.
- Fund transaction hash: `0x8e5a6d5ac483877736374d8537225de8741c47f077a15120c3f7652882ce4ab1`.
- Fund transaction URL:
  `https://sepolia.etherscan.io/tx/0x8e5a6d5ac483877736374d8537225de8741c47f077a15120c3f7652882ce4ab1`.
- Approval gas used: `46320`.
- Fund gas used: `77951`.
- Available bridge balance after the command: `0.001`.
- Token balance after the command: `2330.999`.
- ERC-20 allowance after the command: `0.0`.
- No Sepolia local account secret directory was found after the command, so the browser-wallet `account deposit-bridge`
  path did not write a local L1 private key file.
- The command exited naturally with code `0` after printing the result.
- Follow-up implementation check: after the approval transaction completed, the persistent relay page did not pick up the
  next `fund` request until the same Signing URL was opened again. The same-origin relay model still works, but the
  relay page should reliably continue polling across sequential transaction requests without requiring a manual reopen.

Manual relay long-poll retry on 2026-06-14:

- Result: partially passed. The relay page picked up the second sequential `fund` request automatically after the
  approval transaction, but the wallet did not return a confirmation response for the `fund` transaction before the CLI
  wallet-request timeout.
- Implementation change under test: `/request` now long-polls while no request is pending and is woken when the CLI
  creates the next browser-wallet request.
- Command run from the repository checkout:
  `node packages/apps/private-state/cli/private-state-bridge-cli.mjs account deposit-bridge --amount 0.0001 --network sepolia`.
- Approval transaction hash: `0xd7d1e411cf323ade0897849224eadd7ef789d32a6cfe0db6d9d897b5ce5c0f7b`.
- The CLI printed the second `Browser wallet approval required: send transaction.` message without requiring the Signing
  URL to be reopened, and no relay-page pickup reminder was printed for that second request.
- The command failed closed at the `fund` transaction with:
  `Timed out waiting for browser wallet send transaction.`
- Post-check token balance: `2330.999`.
- Post-check ERC-20 allowance: `0.0001`.
- Post-check available bridge balance: `0.001`.
- Interpretation: the original relay continuity issue was not reproduced, but the `fund` confirmation was not completed
  in the wallet UI. The on-chain state matches one submitted approval and no submitted fund transaction.
- No Sepolia local account secret directory was found after the command.

Manual allowance reuse retry on 2026-06-14:

- Result: passed. The CLI detected the existing `0.0001` allowance, skipped a duplicate approval, and submitted only the
  bridge `fund` transaction through the browser wallet.
- Implementation change under test: `account deposit-bridge` now checks ERC-20 allowance and skips approval when the
  current allowance already covers the requested amount.
- Pre-check note: the previously timed-out `fund` transaction was later reflected on-chain before this retry, raising
  available bridge balance to `0.0011` and reducing allowance to `0.0`. An intermediate retry created a fresh `0.0001`
  allowance before the fund-only verification path consumed it.
- Command run from the repository checkout:
  `node packages/apps/private-state/cli/private-state-bridge-cli.mjs account deposit-bridge --amount 0.0001 --network sepolia`.
- CLI result fields: `Approve Skipped: true`, `Allowance Before: 100000000000000`, `Approve Receipt: none`.
- Fund transaction hash: `0xd46096eec05496c68915db22f145069c7130d0ec1ae55568f898b07e0abe5d1a`.
- Fund transaction URL:
  `https://sepolia.etherscan.io/tx/0xd46096eec05496c68915db22f145069c7130d0ec1ae55568f898b07e0abe5d1a`.
- Fund gas used: `60839`.
- Post-check token balance: `2330.9988`.
- Post-check ERC-20 allowance: `0.0`.
- Post-check available bridge balance: `0.0012`.
- No Sepolia local account secret directory was found after the command.
- The command exited naturally with code `0` after printing the result.

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

Manual deposit-channel result on 2026-06-14:

- Result: passed. The CLI used the browser wallet for L1 authority without a local Sepolia L1 private key, generated the
  L2 accounting proof locally with the wallet spending key, submitted the L1 channel deposit transaction through the
  browser wallet, persisted the operation, and exited naturally with code `0`.
- Test channel name: `browser-wallet-test-20260614-funded-a1`.
- Wallet name: `browser-wallet-test-20260614-funded-a1-0x094Ac5364EE8b6Db0e5b1E1C588be8617Fd499A1`.
- Command run from the repository checkout:
  `node packages/apps/private-state/cli/private-state-bridge-cli.mjs wallet deposit-channel --wallet browser-wallet-test-20260614-funded-a1-0x094Ac5364EE8b6Db0e5b1E1C588be8617Fd499A1 --network sepolia --amount 0.0001`.
- Pre-check channel deposit: `0.0`.
- Amount: `0.0001`.
- Amount base units: `100000000000000`.
- L1 address: `0x094Ac5364EE8b6Db0e5b1E1C588be8617Fd499A1`.
- L2 address: `0x50A7857Ad460D3e303a196Cf673dac5de3dA6078`.
- Current root vector:
  `0x32fe7eab871c48cbc0c5c1b6444be3d71bfba4056511b49dd0ceb179c8807bc6`,
  `0x32fe7eab871c48cbc0c5c1b6444be3d71bfba4056511b49dd0ceb179c8807bc6`.
- Updated root: `0x221ae45575931b5d5915675dca6207def3870db1e4b8e0e168c7c1f2a8cdcf3f`.
- Transaction hash: `0xe76836c1f22ed3a013cc978308c060784be0fff541f6841db9dcb83b4077f45c`.
- Transaction URL:
  `https://sepolia.etherscan.io/tx/0xe76836c1f22ed3a013cc978308c060784be0fff541f6841db9dcb83b4077f45c`.
- Block number: `11055974`.
- Gas used: `341284`.
- Transaction status: `1`.
- Operation directory:
  `/Users/jehyuk/tokamak-private-channels/workspace/sepolia/browser-wallet-test-20260614-funded-a1/wallets/browser-wallet-test-20260614-funded-a1-0x094ac5364ee8b6db0e5b1e1c588be8617fd499a1/epochs/join-0x49e67519a09cb33578431d100bc79f808df958a0da439c0e642854283c25e503-615/operations/20260614T043151Z-wallet-deposit-channel-094ac536`.
- Operation file check found `input.json`, `state_snapshot.json`, `state_snapshot.normalized.json`, and the encrypted
  `wallet deposit-channel-receipt.json`.
- Post-check channel deposit: `0.0001`.
- No Sepolia local account secret directory or local L1 private-key file was found after the command.

Manual withdraw-channel rejection check on 2026-06-15:

- Result: failed closed at browser-wallet account connection after the human verifier rejected the request.
- Command run from the repository checkout:
  `node packages/apps/private-state/cli/private-state-bridge-cli.mjs wallet withdraw-channel --wallet browser-wallet-test-20260614-funded-a1-0x094Ac5364EE8b6Db0e5b1E1C588be8617Fd499A1 --network sepolia --amount 0.00005`.
- Failure message:
  `Browser wallet connect failed: User rejected the request. Wallet error code: 4001 Wallet error data: {"cause":"rejectAllApprovals"}`.
- Post-check channel deposit: unchanged at `0.0001`.
- No Sepolia local L1 private-key file was found after the rejected request.

Manual withdraw-channel retry result on 2026-06-15:

- Result: passed. The CLI used the browser wallet for L1 owner authority without a local Sepolia L1 private key,
  generated the L2 accounting proof locally with the wallet spending key, submitted the L1 channel withdrawal
  transaction through the browser wallet, persisted the operation, and exited naturally with code `0`.
- Test channel name: `browser-wallet-test-20260614-funded-a1`.
- Wallet name: `browser-wallet-test-20260614-funded-a1-0x094Ac5364EE8b6Db0e5b1E1C588be8617Fd499A1`.
- Command run from the repository checkout:
  `node packages/apps/private-state/cli/private-state-bridge-cli.mjs wallet withdraw-channel --wallet browser-wallet-test-20260614-funded-a1-0x094Ac5364EE8b6Db0e5b1E1C588be8617Fd499A1 --network sepolia --amount 0.00005`.
- Pre-check channel deposit: `0.0001`.
- Amount input: `0.00005`.
- Amount base units: `50000000000000`.
- L1 address: `0x094Ac5364EE8b6Db0e5b1E1C588be8617Fd499A1`.
- L2 address: `0x50A7857Ad460D3e303a196Cf673dac5de3dA6078`.
- Current root vector:
  `0x4c20d7050177bc381f133368bca01bc81b4a8ed46f709449402d1b6df8cff0d5`,
  `0x221ae45575931b5d5915675dca6207def3870db1e4b8e0e168c7c1f2a8cdcf3f`.
- Updated root: `0x44ed405561cfe2a389e3082ff310562f09c9a3dcc9320f9824360577c2a727f0`.
- Transaction hash: `0x81c44108f2b3c6e0e576fc0e195cac1bbdee5598a47481b85e2fde0f4e31e5c5`.
- Transaction URL:
  `https://sepolia.etherscan.io/tx/0x81c44108f2b3c6e0e576fc0e195cac1bbdee5598a47481b85e2fde0f4e31e5c5`.
- Block number: `11065460`.
- Gas used: `343234`.
- Transaction status: `1`.
- Operation directory:
  `/Users/jehyuk/tokamak-private-channels/workspace/sepolia/browser-wallet-test-20260614-funded-a1/wallets/browser-wallet-test-20260614-funded-a1-0x094ac5364ee8b6db0e5b1e1c588be8617fd499a1/epochs/join-0x49e67519a09cb33578431d100bc79f808df958a0da439c0e642854283c25e503-615/operations/20260615T121756Z-wallet-withdraw-channel-094ac536`.
- Operation file check found `input.json`, `state_snapshot.json`, `state_snapshot.normalized.json`, and
  `wallet withdraw-channel-receipt.json`.
- Post-check channel deposit: `0.00005`.
- `wallet get-notes` post-check was not run to completion because the wallet note recovery index was 9179 blocks behind
  and exceeded the 7200-block automatic pre-command budget. This is a wallet recovery freshness issue, not a withdrawal
  failure.
- No Sepolia local L1 private-key file was found after the command.
- UX observation: the final send-transaction request was picked up without the relay pickup reminder or reopening the
  Signing URL. This supports the tightened relay polling fix.

Manual final withdraw-channel result on 2026-06-15:

- Result: passed. The CLI used the browser wallet for L1 owner authority without a local Sepolia L1 private key,
  generated the L2 accounting proof locally with the wallet spending key, submitted the final channel withdrawal
  transaction through the browser wallet, persisted the operation, and exited naturally with code `0`.
- Command run from the repository checkout:
  `node packages/apps/private-state/cli/private-state-bridge-cli.mjs wallet withdraw-channel --wallet browser-wallet-test-20260614-funded-a1-0x094Ac5364EE8b6Db0e5b1E1C588be8617Fd499A1 --network sepolia --amount 0.00005`.
- Pre-check channel deposit: `0.00005`.
- Amount input: `0.00005`.
- Amount base units: `50000000000000`.
- Current root vector:
  `0x4c20d7050177bc381f133368bca01bc81b4a8ed46f709449402d1b6df8cff0d5`,
  `0x44ed405561cfe2a389e3082ff310562f09c9a3dcc9320f9824360577c2a727f0`.
- Updated root: `0x32fe7eab871c48cbc0c5c1b6444be3d71bfba4056511b49dd0ceb179c8807bc6`.
- Transaction hash: `0x73b69b6c0ef6037ca7760f0f4280408ce7d860d9c5c5bc89d65855276bfdc754`.
- Transaction URL:
  `https://sepolia.etherscan.io/tx/0x73b69b6c0ef6037ca7760f0f4280408ce7d860d9c5c5bc89d65855276bfdc754`.
- Block number: `11065596`.
- Gas used: `363340`.
- Transaction status: `1`.
- Operation directory:
  `/Users/jehyuk/tokamak-private-channels/workspace/sepolia/browser-wallet-test-20260614-funded-a1/wallets/browser-wallet-test-20260614-funded-a1-0x094ac5364ee8b6db0e5b1e1c588be8617fd499a1/epochs/join-0x49e67519a09cb33578431d100bc79f808df958a0da439c0e642854283c25e503-615/operations/20260615T123943Z-wallet-withdraw-channel-094ac536`.
- Post-check channel deposit: `0.0`.
- No Sepolia local L1 private-key file was found after the command.
- UX observation: the final send-transaction request again completed without the relay pickup reminder or Signing URL
  reopen. The wallet took several minutes to return the approved transaction result, but the relay did not lose the
  request.

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

Manual mint-notes result on 2026-06-14:

- Result: passed. The CLI used the local wallet spending key for the L2 note transaction and proof, used the browser
  wallet only for the final L1 `executeChannelTransaction` submission, created one unused private note, recovered the
  wallet note state from logs, and exited naturally with code `0`.
- Test channel name: `browser-wallet-test-20260614-funded-a1`.
- Wallet name: `browser-wallet-test-20260614-funded-a1-0x094Ac5364EE8b6Db0e5b1E1C588be8617Fd499A1`.
- Command run from the repository checkout:
  `node packages/apps/private-state/cli/private-state-bridge-cli.mjs wallet mint-notes --wallet browser-wallet-test-20260614-funded-a1-0x094Ac5364EE8b6Db0e5b1E1C588be8617Fd499A1 --network sepolia --amounts '["0.00005"]' --tx-submitter`.
- Pre-check channel deposit: `0.0001`.
- Pre-check notes: no unused or spent notes.
- Amount input: `0.00005`.
- Amount base units: `50000000000000`.
- L1 submitter: `0x094Ac5364EE8b6Db0e5b1E1C588be8617Fd499A1`.
- L1 wallet owner: `0x094Ac5364EE8b6Db0e5b1E1C588be8617Fd499A1`.
- Tx submitter source: `browser-wallet`.
- Tx submitter account: `none`.
- Underlying method: `mintNotes1`.
- Nonce: `0`.
- Output note commitment: `0x50e8fe93a985bf4af5946862840288748107d6bbb70e63016f1464dc6c18dade`.
- Output note nullifier: `0x0a3cafa476ab5a83656cfcf79f7ff450aaf3b3f1fcbccc4dc11b38344156ac37`.
- Transaction hash: `0x200163ab5d109893b345500604755531ce17df52fcf59bfc0fbd2edf0e97460f`.
- Transaction URL:
  `https://sepolia.etherscan.io/tx/0x200163ab5d109893b345500604755531ce17df52fcf59bfc0fbd2edf0e97460f`.
- Block number: `11056014`.
- Gas used: `850270`.
- Transaction status: `1`.
- Updated roots:
  `0x6ea7cb3874314bf549cea10cf3d5f87f6ef668d07a7d8095db97cfce9590e4c7`,
  `0x44ed405561cfe2a389e3082ff310562f09c9a3dcc9320f9824360577c2a727f0`.
- Operation directory:
  `/Users/jehyuk/tokamak-private-channels/workspace/sepolia/browser-wallet-test-20260614-funded-a1/wallets/browser-wallet-test-20260614-funded-a1-0x094ac5364ee8b6db0e5b1e1c588be8617fd499a1/epochs/join-0x49e67519a09cb33578431d100bc79f808df958a0da439c0e642854283c25e503-615/operations/20260614T043834Z-wallet-mint-notes-50a7857a`.
- Operation file check found `transaction.json`, `bridge-submit-receipt.json`, `state_snapshot.json`,
  `state_snapshot.normalized.json`, `wallet mint-notes.zip`, and Tokamak proof logs.
- Post-check channel deposit: `0.00005`.
- Post-check notes: one unused note with value `0.00005`, bridge commitment present, bridge nullifier unused, and wallet
  status matching bridge state.
- No Sepolia local account secret directory or local L1 private-key file was found after the command.
- UX observation: at the final send-transaction request, the relay page did not pick up the request within the reminder
  window and the CLI reopened the same Signing URL automatically. The command still completed after the wallet approval,
  but transfer/redeem verification should watch whether this reminder repeats.

Manual transfer-notes result on 2026-06-14:

- Result: passed. The CLI spent the existing private note with the local wallet spending key, proved a 1-to-1
  self-transfer, used the browser wallet only for the final L1 `executeChannelTransaction` submission, recovered the
  spent and new note state from logs, and exited naturally with code `0`.
- Test channel name: `browser-wallet-test-20260614-funded-a1`.
- Wallet name: `browser-wallet-test-20260614-funded-a1-0x094Ac5364EE8b6Db0e5b1E1C588be8617Fd499A1`.
- Command run from the repository checkout:
  `node packages/apps/private-state/cli/private-state-bridge-cli.mjs wallet transfer-notes --wallet browser-wallet-test-20260614-funded-a1-0x094Ac5364EE8b6Db0e5b1E1C588be8617Fd499A1 --network sepolia --note-ids '["0x50e8fe93a985bf4af5946862840288748107d6bbb70e63016f1464dc6c18dade"]' --recipients '["0x50A7857Ad460D3e303a196Cf673dac5de3dA6078"]' --amounts '["0.00005"]' --tx-submitter`.
- Pre-check unused note commitment: `0x50e8fe93a985bf4af5946862840288748107d6bbb70e63016f1464dc6c18dade`.
- Pre-check unused note nullifier: `0x0a3cafa476ab5a83656cfcf79f7ff450aaf3b3f1fcbccc4dc11b38344156ac37`.
- Pre-check channel deposit: `0.00005`.
- Transfer shape: `1->1`.
- Recipient: `0x50A7857Ad460D3e303a196Cf673dac5de3dA6078`.
- Amount input: `0.00005`.
- Amount base units: `50000000000000`.
- L1 submitter: `0x094Ac5364EE8b6Db0e5b1E1C588be8617Fd499A1`.
- L1 wallet owner: `0x094Ac5364EE8b6Db0e5b1E1C588be8617Fd499A1`.
- Tx submitter source: `browser-wallet`.
- Tx submitter account: `none`.
- Underlying method: `transferNotes1To1`.
- Nonce: `1`.
- Output note commitment: `0x0e0abed1eda5134edf38edddc8aee13fbb068cb3da751d883621819ab152dc6d`.
- Output note nullifier: `0x3ddffcf994dc54bfad8c17952cf3f71003bab877ac508bf96f98dbab599641f5`.
- Transaction hash: `0xee51231d4e918a96b7f9c4bedcbd0e4600086f284de84e6e67a4b4853adb9caf`.
- Transaction URL:
  `https://sepolia.etherscan.io/tx/0xee51231d4e918a96b7f9c4bedcbd0e4600086f284de84e6e67a4b4853adb9caf`.
- Block number: `11056049`.
- Gas used: `842428`.
- Transaction status: `1`.
- Updated roots:
  `0x68a2764866ed58b464972867afdde9dce4476a80349bbca9820f3a0ddf64d8eb`,
  `0x44ed405561cfe2a389e3082ff310562f09c9a3dcc9320f9824360577c2a727f0`.
- Operation directory:
  `/Users/jehyuk/tokamak-private-channels/workspace/sepolia/browser-wallet-test-20260614-funded-a1/wallets/browser-wallet-test-20260614-funded-a1-0x094ac5364ee8b6db0e5b1e1c588be8617fd499a1/epochs/join-0x49e67519a09cb33578431d100bc79f808df958a0da439c0e642854283c25e503-615/operations/20260614T044509Z-wallet-transfer-notes-50a7857a`.
- Operation file check found `transaction.json`, `bridge-submit-receipt.json`, `state_snapshot.json`,
  `state_snapshot.normalized.json`, `wallet transfer-notes.zip`, and Tokamak proof logs.
- Post-check unused note: one note with value `0.00005`, commitment
  `0x0e0abed1eda5134edf38edddc8aee13fbb068cb3da751d883621819ab152dc6d`, bridge commitment present, bridge nullifier
  unused, and wallet status matching bridge state.
- Post-check spent note: the input commitment
  `0x50e8fe93a985bf4af5946862840288748107d6bbb70e63016f1464dc6c18dade` is marked spent, its bridge nullifier is used,
  and wallet status matches bridge state.
- Post-check channel deposit: `0.00005`.
- No Sepolia local account secret directory or local L1 private-key file was found after the command.
- UX observation: the final send-transaction request again triggered the relay page pickup reminder and auto-reopened
  the same Signing URL before wallet approval completed. The command still completed after the wallet approval. This
  repeated reminder is now a concrete UX issue to investigate before or alongside redeem verification.

Relay pickup follow-up on 2026-06-14:

- Diagnosis: the relay page treated any `/request` fetch failure as an ended CLI session. During long-running proof
  work, a transient fetch failure could stop the page's polling loop before the final `eth_sendTransaction` request was
  created, forcing the CLI to reopen the same Signing URL.
- Implementation change under test: the relay page now retries short-lived `/request` fetch failures, displays
  `Waiting for the CLI relay to respond...`, and only shows the ended-session message after repeated failures persist
  for more than 60 seconds, long enough to avoid treating short proof-time relay interruptions as command completion.
- Next check: `wallet redeem-notes --tx-submitter` should confirm whether the final send-transaction request is picked
  up without the relay pickup reminder.

Manual redeem-notes retry after relay pickup fix on 2026-06-14:

- Result: failed closed at wallet response timeout. The final send-transaction relay pickup reminder did not reappear,
  which supports the relay retry fix, but the browser wallet did not return a send-transaction result to the CLI before
  the 10-minute wallet-request timeout.
- Command run from the repository checkout:
  `node packages/apps/private-state/cli/private-state-bridge-cli.mjs wallet redeem-notes --wallet browser-wallet-test-20260614-funded-a1-0x094Ac5364EE8b6Db0e5b1E1C588be8617Fd499A1 --network sepolia --note-ids '["0x0e0abed1eda5134edf38edddc8aee13fbb068cb3da751d883621819ab152dc6d"]' --tx-submitter`.
- Pre-check redeem target note commitment: `0x0e0abed1eda5134edf38edddc8aee13fbb068cb3da751d883621819ab152dc6d`.
- Pre-check redeem target note nullifier: `0x3ddffcf994dc54bfad8c17952cf3f71003bab877ac508bf96f98dbab599641f5`.
- Pre-check channel deposit: `0.00005`.
- Failure message:
  `wallet redeem-notes transaction submission failed. ... Provider error: Timed out waiting for browser wallet send transaction.`
- Operation directory:
  `/Users/jehyuk/tokamak-private-channels/workspace/sepolia/browser-wallet-test-20260614-funded-a1/wallets/browser-wallet-test-20260614-funded-a1-0x094ac5364ee8b6db0e5b1e1c588be8617fd499a1/epochs/join-0x49e67519a09cb33578431d100bc79f808df958a0da439c0e642854283c25e503-615/operations/20260614T050815Z-wallet-redeem-notes-50a7857a`.
- Operation file check found pre-submission artifacts including `transaction.json`, `previous_state_snapshot.json`,
  `wallet redeem-notes.zip`, and Tokamak proof logs; no bridge submission receipt was written.
- Post-check notes: unchanged. The redeem target note remains unused with bridge commitment present, bridge nullifier
  unused, and wallet status matching bridge state.
- Post-check channel deposit: unchanged at `0.00005`.
- No Sepolia local account secret directory or local L1 private-key file was found after the command.
- Next check: retry redeem with the wallet confirmation UI visible. If the verifier approved the wallet transaction
  during this failed run, investigate why the page/provider did not return the result to `/result`; otherwise treat this
  run as an unapproved wallet request timeout rather than a CLI submission failure.

Manual redeem-notes retry with visible wallet response on 2026-06-14:

- Result: failed closed before transaction submission because the browser wallet account did not have enough Sepolia ETH
  to cover the wallet-selected gas cost. This run confirms that the wallet/provider result returned to the CLI, so the
  previous timeout should be treated separately from this gas-funds failure.
- Command run from the repository checkout:
  `node packages/apps/private-state/cli/private-state-bridge-cli.mjs wallet redeem-notes --wallet browser-wallet-test-20260614-funded-a1-0x094Ac5364EE8b6Db0e5b1E1C588be8617Fd499A1 --network sepolia --note-ids '["0x0e0abed1eda5134edf38edddc8aee13fbb068cb3da751d883621819ab152dc6d"]' --tx-submitter`.
- Failure message:
  `Browser wallet send transaction failed: RPC submit: insufficient funds for gas * price + value: have 28522933657669279 want 39659405480142168`.
- Wallet error code: `-32603`.
- Browser wallet diagnostics:
  `provider.isMetaMask: true`, `eth_accounts: ["0x094ac5364ee8b6db0e5b1e1c588be8617fd499a1"]`,
  `eth_chainId: 0xaa36a7`, `transaction.from: 0x094Ac5364EE8b6Db0e5b1E1C588be8617Fd499A1`,
  `transaction.to: 0xF344b292D807116cF95dceA7c797CB3892e77beD`, `transaction.dataByteLength: 8132`,
  `signerAddress: 0x094Ac5364EE8b6Db0e5b1E1C588be8617Fd499A1`.
- Operation directory:
  `/Users/jehyuk/tokamak-private-channels/workspace/sepolia/browser-wallet-test-20260614-funded-a1/wallets/browser-wallet-test-20260614-funded-a1-0x094ac5364ee8b6db0e5b1e1c588be8617fd499a1/epochs/join-0x49e67519a09cb33578431d100bc79f808df958a0da439c0e642854283c25e503-615/operations/20260614T052835Z-wallet-redeem-notes-50a7857a`.
- Operation file check found pre-submission artifacts including `transaction.json`, `previous_state_snapshot.json`,
  `wallet redeem-notes.zip`, and Tokamak proof logs; no bridge submission receipt was written.
- Post-check notes: unchanged. The redeem target note remains unused with bridge commitment present, bridge nullifier
  unused, and wallet status matching bridge state.
- Post-check channel deposit: unchanged at `0.00005`.
- No Sepolia local account secret directory or local L1 private-key file was found after the command.
- UX observation: the final send-transaction relay pickup reminder reappeared and the CLI reopened the same Signing URL
  before receiving the wallet gas-funds failure. The short fetch retry change did not fully eliminate this reminder.
- Next check: top up Sepolia ETH for the browser wallet account, then retry redeem. Separately investigate why the relay
  page still misses the final send-transaction request during redeem.

Manual redeem-notes funded retry on 2026-06-14:

- Result: passed. After topping up Sepolia ETH, the CLI redeemed the remaining private note with the local wallet
  spending key, used the browser wallet only for the final L1 `executeChannelTransaction` submission, recovered the
  spent note and channel accounting state from logs, and exited naturally with code `0`.
- Command run from the repository checkout:
  `node packages/apps/private-state/cli/private-state-bridge-cli.mjs wallet redeem-notes --wallet browser-wallet-test-20260614-funded-a1-0x094Ac5364EE8b6Db0e5b1E1C588be8617Fd499A1 --network sepolia --note-ids '["0x0e0abed1eda5134edf38edddc8aee13fbb068cb3da751d883621819ab152dc6d"]' --tx-submitter`.
- Pre-check browser wallet balance: `0.128313599027843561` Sepolia ETH.
- Pre-check redeem target note commitment: `0x0e0abed1eda5134edf38edddc8aee13fbb068cb3da751d883621819ab152dc6d`.
- Pre-check redeem target note nullifier: `0x3ddffcf994dc54bfad8c17952cf3f71003bab877ac508bf96f98dbab599641f5`.
- Pre-check channel deposit: `0.00005`.
- L1 submitter: `0x094Ac5364EE8b6Db0e5b1E1C588be8617Fd499A1`.
- L1 wallet owner: `0x094Ac5364EE8b6Db0e5b1E1C588be8617Fd499A1`.
- Tx submitter source: `browser-wallet`.
- Tx submitter account: `none`.
- Underlying method: `redeemNotes1`.
- Nonce: `2`.
- Redeemed amount: `0.00005`.
- Transaction hash: `0xc3031a06d2b4a7a31802b79a92e4e534e97da19462e7a696c75327c4e0081281`.
- Transaction URL:
  `https://sepolia.etherscan.io/tx/0xc3031a06d2b4a7a31802b79a92e4e534e97da19462e7a696c75327c4e0081281`.
- Block number: `11056303`.
- Gas used: `837649`.
- Transaction status: `1`.
- Updated roots:
  `0x4c20d7050177bc381f133368bca01bc81b4a8ed46f709449402d1b6df8cff0d5`,
  `0x221ae45575931b5d5915675dca6207def3870db1e4b8e0e168c7c1f2a8cdcf3f`.
- Operation directory:
  `/Users/jehyuk/tokamak-private-channels/workspace/sepolia/browser-wallet-test-20260614-funded-a1/wallets/browser-wallet-test-20260614-funded-a1-0x094ac5364ee8b6db0e5b1e1c588be8617fd499a1/epochs/join-0x49e67519a09cb33578431d100bc79f808df958a0da439c0e642854283c25e503-615/operations/20260614T053819Z-wallet-redeem-notes-50a7857a`.
- Operation file check found `transaction.json`, `bridge-submit-receipt.json`, `state_snapshot.json`,
  `state_snapshot.normalized.json`, `wallet redeem-notes.zip`, and Tokamak proof logs.
- Post-check notes: no unused notes remain. The redeemed note is marked spent, bridge commitment present, bridge
  nullifier used, and wallet status matching bridge state.
- Post-check channel deposit: `0.0001`.
- No Sepolia local account secret directory or local L1 private-key file was found after the command.
- UX observation: the final send-transaction relay pickup reminder still appeared, and the CLI reopened the same Signing
  URL before the wallet approval completed. The browser-wallet note-command flow works end to end, but the relay pickup
  issue remains unresolved.

Relay pickup follow-up after funded redeem on 2026-06-15:

- Diagnosis refinement: repeated `/request` fetch failures should not be treated as implicit command completion. During
  long proof work, that inference can stop the relay loop before the final transaction request exists.
- Implementation change under test: the relay page now treats only an explicit `{ "done": true }` response as terminal.
  `/request` fetch failures and 30-second request timeouts keep the page alive and polling. After 60 seconds of repeated
  failures, the page displays a non-raw diagnostic message but continues polling.
- Follow-up result: `wallet withdraw-channel` picked up the final send-transaction request without the relay pickup
  reminder or Signing URL reopen. Continue watching this behavior on `channel exit`, but the previously observed
  reminder is no longer reproduced by the latest browser-wallet transaction command.

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

Manual channel-exit result on 2026-06-15:

- Result: passed. After the channel balance reached zero, the CLI used the browser wallet for L1 owner authority,
  submitted the exit transaction, marked the local wallet epoch as exited, and exited naturally with code `0`.
- Command run from the repository checkout:
  `node packages/apps/private-state/cli/private-state-bridge-cli.mjs channel exit --wallet browser-wallet-test-20260614-funded-a1-0x094Ac5364EE8b6Db0e5b1E1C588be8617Fd499A1 --network sepolia`.
- Pre-check channel deposit: `0.0`.
- L1 address: `0x094Ac5364EE8b6Db0e5b1E1C588be8617Fd499A1`.
- Current user value: `0`.
- Refund amount: `0.0`.
- Refund bps: `2500`.
- Transaction hash: `0x1f4a6112de01f4af79227a91ab5bb1cbcded20e2f5e0762d5482cf6a42d75dce`.
- Transaction URL:
  `https://sepolia.etherscan.io/tx/0x1f4a6112de01f4af79227a91ab5bb1cbcded20e2f5e0762d5482cf6a42d75dce`.
- Block number: `11065602`.
- Gas used: `92741`.
- Transaction status: `1`.
- Epoch id: `join-0x49e67519a09cb33578431d100bc79f808df958a0da439c0e642854283c25e503-615`.
- Post-check wallet lifecycle status: `exited`.
- Post-check on-chain registration: `Registration Exists: false`.
- Archived wallet directory:
  `/Users/jehyuk/tokamak-private-channels/workspace/sepolia/browser-wallet-test-20260614-funded-a1/wallets/browser-wallet-test-20260614-funded-a1-0x094ac5364ee8b6db0e5b1e1c588be8617fd499a1/epochs/join-0x49e67519a09cb33578431d100bc79f808df958a0da439c0e642854283c25e503-615`.
- No Sepolia local L1 private-key file was found after the command.
- UX observation: the exit send-transaction request completed without the relay pickup reminder or Signing URL reopen.

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

Manual wrong-account result on 2026-06-15:

- Result: passed. The CLI failed immediately after browser-wallet account selection and before any transaction
  submission request.
- Setup: a fresh active zero-balance test epoch was created with a random wallet secret source for the existing
  `browser-wallet-test-20260614-funded-a1` channel.
- Setup join transaction hash: `0x9f65cded587c31fbadcde5083cd072b250042a7dbce8e846360fcb0b250cbcfb`.
- Setup epoch id: `join-0x9f65cded587c31fbadcde5083cd072b250042a7dbce8e846360fcb0b250cbcfb-143`.
- Setup L2 address: `0xe80cBc4Ba0928Bf2742503b79255cA42175250B5`.
- Triggering command:
  `node packages/apps/private-state/cli/private-state-bridge-cli.mjs channel exit --wallet browser-wallet-test-20260614-funded-a1-0x094Ac5364EE8b6Db0e5b1E1C588be8617Fd499A1 --network sepolia`.
- Browser wallet selected address: `0x3C5515f88A2b7403549Ec87AcC747D446Cdb698a`.
- Required wallet owner address: `0x094Ac5364EE8b6Db0e5b1E1C588be8617Fd499A1`.
- Failure message:
  `Browser wallet selected 0x3C5515f88A2b7403549Ec87AcC747D446Cdb698a, but this command requires 0x094Ac5364EE8b6Db0e5b1E1C588be8617Fd499A1.`
- No transaction hash was produced for the wrong-account attempt.
- No Sepolia local L1 private-key file was found after the failed attempt.
- Cleanup: after switching back to the required owner account, the same epoch exited successfully with transaction
  `0x4afd1e36c7866aa2b295f47dfa0ee8f7ad399729f29ea15dbb68e6fc8f5a2c93`.
- Cleanup block number: `11065667`.
- Cleanup gas used: `92671`.
- Post-cleanup wallet lifecycle status: `exited`.
- Post-cleanup on-chain registration: `Registration Exists: false`.
- No Sepolia local L1 private-key file was found after cleanup.

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

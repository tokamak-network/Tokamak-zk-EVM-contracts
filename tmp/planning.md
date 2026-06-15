# Private-State CLI Browser Wallet Signing Plan

## Audience

This plan is for repository developers and reviewers who will implement and verify a private-state CLI execution path
that does not require direct CLI access to the user's L1 Ethereum private key.

## Goal

Add a browser-wallet execution path to the private-state CLI while preserving the current local private-key execution
path. The public command syntax should stay small: commands use a local account when the user supplies an account alias,
and otherwise request the required L1 authority from a browser wallet. In the browser-wallet path, the CLI must never
read, import, persist, or derive from the user's raw L1 private key. Every L1 account signature, typed-data signature,
and Ethereum transaction submission must be approved by the user through a browser wallet.

The browser scope is any browser that can run the MetaMask extension or an equivalent EIP-1193 provider compatible with
MetaMask request methods. The implementation must not assume Chrome specifically.

L2 spending keys and viewing keys remain in scope for local CLI use. The browser-wallet path may derive, store, import,
export, and use those keys under the existing wallet key rules because they are not the user's L1 private key.

## Non-Goals

- Do not remove the existing local private-key execution path.
- Do not redesign private-state contracts, bridge contracts, proof formats, or channel policy.
- Do not add browser automation that clicks wallet-extension UI for the user.
- Do not treat browser-wallet failure as permission to silently fall back to a local L1 private key.
- Do not make MetaMask sign Tokamak L2 transactions directly. Tokamak L2 transaction signing continues to use the L2
  spending key.

## Core Design

Introduce an L1 signer abstraction with two concrete implementations:

- `local-account` signer: the current `ethers.Wallet` path backed by a protected local account private key.
- `browser-wallet` signer: a signer backed by a local browser session that exposes an EIP-1193 provider.

The browser-wallet signer must support:

- address discovery through `eth_requestAccounts` or an equivalent wallet connection method
- chain validation through `eth_chainId`
- chain switching through `wallet_switchEthereumChain` followed by `eth_chainId` revalidation when the wallet is on a
  known wrong chain, or clear user-facing failure when the user rejects the switch or the wallet still reports the wrong
  chain
- EIP-191 message signing through `personal_sign`
- EIP-712 signing through `eth_signTypedData_v4`
- Ethereum transaction submission through `eth_sendTransaction`

The CLI should launch a local signing relay page served from `127.0.0.1` on an ephemeral port. The page must not act as
a trusted approval UI and must not ask the user to click a CLI-provided approval button. Instead, it should immediately
send the EIP-1193 provider request from the browser context and return the provider result to the CLI over a localhost
callback channel. The only approval or rejection button the user should click is the MetaMask-compatible wallet UI.
This is more stable than controlling extension UI while keeping the user approval surface inside the wallet itself.
Sequential wallet requests in a single CLI command must reuse one localhost origin because browser-wallet account
permissions are origin-scoped. The request id may change per approval, but the host, port, and session token should
remain stable for that command. The preferred browser bridge shape is one persistent relay page that polls the CLI for
the next request and performs all provider calls from the same browser JavaScript context.

## Browser Relay UX Copy

The browser relay page is user-facing and must not expose developer-oriented labels such as `role` and `action` as the
primary explanation. Those labels are useful internal state, but they are not enough for an ordinary user to understand
why MetaMask opened, what the requested approval does, or what changes if the user approves it.

Replace the current role/action presentation with a plain-language request explanation model. For every browser-wallet
request, the CLI should send the relay page a sanitized user-facing summary with these fields:

- `title`: a short human title, for example `Connect your wallet`, `Switch network`, `Create channel`, `Join channel`,
  `Sign channel wallet key`, `Sign note viewing key`, `Submit private note transaction`, or `Exit channel`.
- `whatThisDoes`: one or two sentences explaining what the MetaMask request will do in ordinary language.
- `approvalEffect`: the concrete consequence of approval, such as connecting the selected account to this CLI session,
  switching MetaMask to Sepolia, deriving the channel-bound L2 spending key from a signature, deriving the note viewing
  key from typed data, sending a public Ethereum transaction, changing channel balance, creating or spending private
  notes, or marking the wallet epoch exited.
- `publicDisclosure`: what becomes public on Ethereum when the request submits a transaction. This should be omitted or
  explicitly say `No Ethereum transaction is sent by this request` for connect, network, and signature-only requests.
- `privacyEffect`: what private-state data is or is not revealed by the request. This must stay consistent with the
  command warning summary.
- `accountRequirement`: the expected account when the command requires a specific owner, channel leader, or submitter.
- `networkRequirement`: the selected network and chain id when relevant.
- `safeToReject`: a short statement that rejecting cancels or stops the CLI command and does not authorize a fallback
  local private key path.

The copy must be calm, friendly, and short. The relay page should help the user recognize the MetaMask request, not make
the request feel more dangerous than it is. Avoid legalistic, alarmist, or developer-heavy language in the browser UI.
Prefer simple wording such as `MetaMask will ask which account to use`, `This signs a message so the CLI can set up your
channel wallet`, or `This sends the transaction you reviewed in the terminal`. Avoid browser-page phrasing such as
`irreversible public disclosure`, `authority delegation`, `cryptographic commitment`, `accepted transition surface`, or
`regulatory risk`. Those details belong in terminal warning summaries, docs, or diagnostics, not in the per-request
browser relay copy. If a request has a real consequence, state it plainly and briefly without amplifying fear.

The relay page should still make clear that it is not an approval surface: it should say that the user must approve or
reject only in MetaMask. The relay page should not duplicate MetaMask buttons, should not ask the user to trust the
localhost page instead of MetaMask, and should not hide that the actual wallet request is controlled by the extension UI.

The request explanations must be specific to the command and request type:

- `eth_requestAccounts`: explain that the CLI is asking MetaMask which account the user wants to use for this command,
  and that no transaction or signature is sent by connecting.
- `eth_chainId`: explain that the CLI is checking that MetaMask is on the same network selected in the terminal.
- `wallet_switchEthereumChain`: explain which network MetaMask will switch to and that no channel state changes merely
  from switching networks.
- `personal_sign` during `channel join`: explain that approval signs a deterministic message used locally to derive the
  channel-bound L2 spending key; it does not send an Ethereum transaction, but the derived key can authorize future
  private note actions.
- `eth_signTypedData_v4` during `channel join` or recovery: explain that approval signs typed data used locally to
  derive or recover note viewing authority; it does not send an Ethereum transaction, but the derived viewing key can
  read notes addressed to the wallet when the required local state is available.
- `eth_sendTransaction`: explain the exact command-level effect. Examples include creating a channel, joining a channel,
  depositing bridge funds, withdrawing bridge funds, moving balance into or out of a channel, submitting a private note
  state transition, or exiting a channel. The page should show the public account, channel name, amount when available,
  and transaction target summary, but must not show raw calldata, proof artifacts, wallet secrets, L2 private keys,
  viewing keys, note plaintext, or full note secret material.

The implementation should reuse the existing warning-summary source of truth where possible, but the relay copy must be
shorter and contextual to the single pending MetaMask request. Terminal warning summaries remain the comprehensive
pre-command disclosure. Browser relay summaries are per-request explanations that help the user connect the MetaMask
popup to the CLI command they just ran.

## Command Surface

Do not add a new public browser-wallet option. Extend the existing account-selection grammar instead:

- `--account <ACCOUNT>`: use the existing local account secret path.
- no `--account`: use the browser wallet for commands that need L1 account authority.
- `--tx-submitter <ACCOUNT>`: use the existing local submitter account for note command L1 submission.
- `--tx-submitter` with no value: use the browser wallet as the note command L1 submitter.
- no `--tx-submitter`: preserve the existing default owner-submitter behavior, but if the wallet owner L1 key is not
  available locally, request the owner authority from the browser wallet and require the selected address to match the
  wallet owner.

This model keeps the local-account path explicit and makes browser-wallet mode the default only when the user does not
provide a local account selector. It also keeps `--tx-submitter` focused on the same role it already has: choosing the
L1 account that submits `executeChannelTransaction`.

The user selects the concrete browser account through the wallet UI. The CLI validates the selected address against the
command context when a specific address is required, such as a deterministic wallet owner address or an on-chain channel
leader. The CLI should print the localhost signing URL so the user can open it in any MetaMask-capable browser if the
default browser is not the one they want. Browser launch behavior and approval timeout should be implementation
defaults, not public command options.

## Command Feasibility

### Read-Only Commands

Read-only commands do not need L1 private-key access. Where they currently require `--account` only to identify an
address, omitting `--account` should connect the browser wallet and use the selected account address without importing a
local secret.

Affected commands include:

- `account get-l1-address`
- `account get-bridge-fund`
- `channel get-meta`
- `channel recover-workspace`
- `wallet get-meta`
- `wallet get-channel-fund`
- `wallet get-notes`
- help and diagnostic commands that inspect local account state

### L1 Transaction Commands

These commands can use the browser-wallet signer for transaction submission:

- `account deposit-bridge`
- `account withdraw-bridge`
- `channel create`
- `channel set-workspace-mirror`
- `channel abandon-operation`
- `channel join`
- `channel exit`
- `wallet deposit-channel`
- `wallet withdraw-channel`

For `account deposit-bridge`, the browser-wallet path must preserve the two-transaction sequence when approval is
needed: token `approve`, then bridge `fund`. Nonce management should rely on wallet/provider transaction submission
instead of manually assigning nonces unless a concrete sequencing issue requires explicit nonces.

### L2 Note Commands

These commands still use the local L2 spending key for Tokamak L2 transaction signing and proof generation:

- `wallet mint-notes`
- `wallet transfer-notes`
- `wallet redeem-notes`

The browser-wallet signer is only responsible for the final L1 submission of `executeChannelTransaction` when the user
passes `--tx-submitter` without a value, or when the command needs the wallet owner as submitter and no matching local
owner key exists. The CLI must keep the existing requirement that the wallet has spending capability, because the L2
transaction snapshot is signed with `l2PrivateKey` before proof generation.

### Key Derivation Commands

`channel join` and `wallet recover-workspace` need browser signatures when local L1 private-key access is not available.

For `channel join`, the browser-wallet path must:

1. connect the browser wallet and verify the selected chain and address
2. request the deterministic EIP-191 message signature used to derive the channel-bound L2 spending key
3. request the EIP-712 typed-data signature used to derive the note-receive viewing key
4. submit any Join Toll approval through the browser wallet
5. submit `joinChannel` through the browser wallet
6. persist wallet metadata plus L2 spending/viewing key files under the existing wallet-key model

For `wallet recover-workspace`, the browser-wallet path must:

1. connect and verify the selected browser wallet account
2. derive the viewing key from the fixed EIP-712 typed-data signature
3. derive the spending key only when `--wallet-secret-path` is supplied and the on-chain registration is active
4. reject recovery when the derived keys do not match the registered channel-local address, storage key, or note-receive
   public key

## Current `eth_sendTransaction` Investigation

The repeated Sepolia `channel create` failures at `eth_sendTransaction` must not be treated as solved by retrying the
command or by adding more wallet-permission prompts. The current evidence only proves that the command reaches
transaction submission and that the browser wallet returns `Unauthorized.`. It does not yet prove which input or wallet
state causes that provider error.

The leading hypothesis is that the browser wallet does not consider the transaction `from` account to be authorized for
the localhost origin at the moment `eth_sendTransaction` runs. Other plausible causes remain open:

- the injected provider is not the intended MetaMask provider
- the browser wallet connected-sites state for the localhost origin is stale or inconsistent
- the wallet active account differs from the account returned by the initial `eth_requestAccounts`
- the transaction payload shape includes a field that the wallet rejects for this request
- the persistent relay page or localhost origin model triggers provider-specific authorization behavior

The first diagnostic retry on 2026-06-14 narrowed the failure. The browser provider reported `isMetaMask: true`, the
wallet account matched `transaction.from`, and `eth_chainId` matched Sepolia. The wallet error was `Unauthorized.` with
code `-32006` and data `{"httpStatus":401,"cause":null}`. This weakens the wrong-provider, wrong-account, and
wrong-chain hypotheses. Before changing CLI behavior again, inspect the MetaMask Sepolia network RPC/backend
configuration because the browser wallet appears to be receiving an HTTP 401 while submitting the transaction.

A follow-up 0 ETH MetaMask Sepolia self-transaction diagnostic failed with the same `-32006` / HTTP 401 error before any
private-state calldata or contract target was involved. This makes the private-state transaction payload unlikely to be
the root cause. The next blocker is external to the CLI: the MetaMask Sepolia RPC/backend configuration must be fixed or
replaced, and a normal Sepolia transaction should succeed from MetaMask before retrying private-state `channel create`.

A later attempt to propose `https://ethereum-sepolia-rpc.publicnode.com` through `wallet_addEthereumChain` also failed
with the same `-32006` / HTTP 401 error on a 0 ETH self transaction. The public RPC itself responded correctly to
CLI-side `eth_chainId` and `eth_blockNumber` checks, so the likely issue is that MetaMask did not replace the active
Sepolia RPC endpoint or is still using an unauthorized endpoint. The next step is manual MetaMask network settings
inspection/editing; do not keep trying private-state transactions until a plain MetaMask Sepolia transaction succeeds.

After the verifier restored MetaMask and topped up Sepolia gas on 2026-06-14, browser-wallet `channel create` succeeded
for `browser-wallet-test-20260614-funded-a1`. The command used the browser wallet without `--account`, submitted
transaction `0x969356b099a09d994369ed03a9f94b0946977507b07036447e306a51642c2d1a`, and created the channel workspace
without writing a Sepolia local L1 private-key directory. The earlier `-32006` / HTTP 401 wallet backend failure is no
longer the active blocker. A follow-up implementation change closes the browser-wallet relay at command completion, and
`account get-l1-address --network sepolia` was manually verified to exit with code `0` after browser-wallet approval.
The follow-up `channel join` without `--account` also succeeded against that Sepolia test channel, including browser
message signing, typed-data signing, `joinChannel` submission, wallet workspace creation, local L2 spending/viewing key
storage, no local L1 private-key file creation, and natural process exit. The browser-wallet `account deposit-bridge`
path also succeeded without `--account` for `0.001` Sepolia canonical tokens, including approval, bridge funding,
available bridge balance increase, no local L1 private-key file creation, and natural process exit. However, the
persistent relay page did not automatically pick up the second sequential transaction request after approval; reopening
the same Signing URL allowed the bridge `fund` request to continue. A follow-up implementation changed `/request` to
long-poll and wake when the CLI creates the next browser-wallet request. The retry showed that the second sequential
`fund` request was picked up without reopening the Signing URL, but the wallet did not return a confirmation response
before timeout; only the approval transaction was submitted, leaving `0.0001` allowance and no additional bridge fund.
The timed-out `fund` transaction was later reflected on-chain, and a follow-up change made `account deposit-bridge`
reuse sufficient existing allowance instead of forcing a duplicate approval. The allowance-reuse retry skipped approval,
submitted only the bridge `fund` transaction, increased available bridge balance to `0.0012`, left no Sepolia local L1
private-key file, and exited naturally. The follow-up `wallet deposit-channel` verification for the joined wallet also
passed without a local Sepolia L1 private key: the CLI generated the L2 accounting proof locally, submitted transaction
`0xe76836c1f22ed3a013cc978308c060784be0fff541f6841db9dcb83b4077f45c` through the browser wallet, increased channel
deposit from `0.0` to `0.0001`, and exited naturally. The first note-command verification also passed: `wallet
mint-notes --tx-submitter` generated the L2 note proof locally, submitted transaction
`0x200163ab5d109893b345500604755531ce17df52fcf59bfc0fbd2edf0e97460f` through the browser wallet with
`txSubmitterSource: browser-wallet`, created one unused `0.00005` note, reduced channel deposit to `0.00005`, wrote no
local Sepolia L1 private key, and exited naturally. One UX observation remains: the mint command's final
send-transaction request triggered the relay page pickup reminder and auto-reopened the same Signing URL before the
wallet approval completed. The follow-up `wallet transfer-notes --tx-submitter` self-transfer also passed: the CLI
spent the minted note, created a new unused `0.00005` note, submitted transaction
`0xee51231d4e918a96b7f9c4bedcbd0e4600086f284de84e6e67a4b4853adb9caf` through the browser wallet with
`txSubmitterSource: browser-wallet`, wrote no local Sepolia L1 private key, and exited naturally. The relay pickup
reminder repeated on the final send-transaction request and the CLI again auto-reopened the same Signing URL before
wallet approval completed. The next active manual verification target is `wallet redeem-notes --tx-submitter`, but the
repeated relay pickup reminder is now a concrete UX issue to investigate before or alongside redeem verification.

The first relay pickup investigation found a likely CLI-side cause. The browser signing page treated any `/request`
fetch failure as an ended CLI session. During long-running proof work, a transient relay read failure can therefore stop
the existing relay page before the final `eth_sendTransaction` request exists; the CLI then has to reopen the same
Signing URL to recover. The relay page now keeps polling after short-lived `/request` fetch failures and shows
`Waiting for the CLI relay to respond...`; it only converts repeated fetch failures into an ended-session message after
they persist for more than 60 seconds, which is long enough to avoid treating short proof-time relay interruptions as
command completion. The next `wallet redeem-notes --tx-submitter` manual verification should confirm that the final
send-transaction request is picked up without the relay pickup reminder.

The first `wallet redeem-notes --tx-submitter` attempt after that relay retry change failed closed at wallet response
timeout. The final send-transaction relay pickup reminder did not reappear, which supports the relay retry fix, but the
browser wallet did not return a send-transaction result to the CLI before the 10-minute wallet-request timeout. The
redeem target note remains unused, the channel deposit remains `0.00005`, no bridge submission receipt was written, and
no local Sepolia L1 private key was created. The next active target remains redeem verification: retry
`wallet redeem-notes --tx-submitter` with the wallet confirmation UI visible. If the verifier approved the wallet
transaction during the failed run, investigate why the page/provider did not return the result to `/result`; otherwise
treat the run as an unapproved wallet request timeout.

The visible-wallet redeem retry returned a browser-wallet provider error instead of timing out: Sepolia ETH was
insufficient for the wallet-selected gas cost (`have 28522933657669279 want 39659405480142168`). The transaction was not
submitted, no bridge submission receipt was written, the redeem target note remains unused, channel deposit remains
`0.00005`, and no local Sepolia L1 private key was created. The final send-transaction relay pickup reminder reappeared
before the gas-funds failure was returned, so the short fetch retry change did not fully eliminate that UX issue. The
next active target is to top up the browser wallet account's Sepolia ETH, retry `wallet redeem-notes --tx-submitter`,
and separately continue investigating why the relay page still misses the final send-transaction request during redeem.

After topping up Sepolia ETH, `wallet redeem-notes --tx-submitter` passed. The CLI redeemed the remaining `0.00005`
note, submitted transaction `0xc3031a06d2b4a7a31802b79a92e4e534e97da19462e7a696c75327c4e0081281` through the browser
wallet with `txSubmitterSource: browser-wallet`, marked the note spent, increased channel deposit back to `0.0001`,
wrote no local Sepolia L1 private key, and exited naturally. This completes browser-wallet verification for
`wallet mint-notes`, `wallet transfer-notes`, and `wallet redeem-notes`. However, the final send-transaction relay
pickup reminder still appeared during redeem, so the relay page final-request pickup issue remains unresolved. The next
active target is to investigate and fix that relay pickup UX issue before continuing to `wallet withdraw-channel` and
`channel exit`.

The relay pickup fix has been tightened. The previous short fetch retry still allowed the browser page to infer session
completion from repeated `/request` fetch failures. That is too aggressive during long proof work because it can stop
the relay loop before the final transaction request exists. The page now treats only the explicit `{ done: true }`
completion response as a terminal condition. Transient `/request` failures and 30-second request timeouts keep the page
alive and polling; after 60 seconds of repeated failures the page shows a non-raw diagnostic message but still continues
polling. The next browser-wallet transaction command should verify that the final send-transaction request is picked up
without the relay pickup reminder.

The follow-up `wallet withdraw-channel` verification on 2026-06-15 passed after an initial human-rejected account
connection failed closed with MetaMask code `4001`. The first successful retry moved `0.00005` from channel balance back
to the shared bridge vault, submitted transaction `0x81c44108f2b3c6e0e576fc0e195cac1bbdee5598a47481b85e2fde0f4e31e5c5`
through the browser wallet, reduced channel deposit from `0.0001` to `0.00005`, wrote no local Sepolia L1 private-key
file, and exited naturally. A post-check `wallet get-notes` attempt was blocked by the wallet note recovery index
exceeding the 7200-block automatic pre-command budget, which is a workspace freshness issue rather than a withdrawal
failure. A second successful retry submitted transaction
`0x73b69b6c0ef6037ca7760f0f4280408ce7d860d9c5c5bc89d65855276bfdc754` through the browser wallet and reduced channel
deposit from `0.00005` to zero. Both successful withdraw runs picked up the final send-transaction request without the
relay pickup reminder or Signing URL reopen.

The browser-wallet `channel exit` verification also passed on 2026-06-15 after the channel balance reached zero. The
CLI submitted transaction `0x1f4a6112de01f4af79227a91ab5bb1cbcded20e2f5e0762d5482cf6a42d75dce` through the browser
wallet, received status `1`, marked the local wallet epoch as `exited`, confirmed that the on-chain registration no
longer exists, wrote no local Sepolia L1 private-key file, and exited naturally. The exit send-transaction request also
completed without the relay pickup reminder or Signing URL reopen. This completes the main browser-wallet success-path
verification set for `channel join`, `wallet deposit-channel`, `wallet mint-notes`, `wallet transfer-notes`,
`wallet redeem-notes`, `wallet withdraw-channel`, and `channel exit` without importing an L1 private key. Remaining
release checks should focus on the still-unverified documented failure paths, a representative local-account regression
path, and any second MetaMask-capable browser coverage that is available. The wrong-account failure path passed on
2026-06-15: `channel exit` failed before transaction submission when MetaMask selected
`0x3C5515f88A2b7403549Ec87AcC747D446Cdb698a` but the wallet required
`0x094Ac5364EE8b6Db0e5b1E1C588be8617Fd499A1`. The temporary active epoch created for that check was then exited with
transaction `0x4afd1e36c7866aa2b295f47dfa0ee8f7ad399729f29ea15dbb68e6fc8f5a2c93`, leaving no active registration and no
local Sepolia L1 private-key file.

The browser relay completion UX has an implementation path. A stale relay page could previously show `Failed to fetch`
after the CLI command had already completed and closed its localhost server, making a successful terminal command look
like a wallet or transaction failure. The relay session now has a closing state, wakes pending `/request` long-polls
before shutdown, returns an explicit completion response with `{ done: true }`, lets the page stop its polling loop, and
shows `Command finished. You can return to the terminal.`. If an old page still sees a network failure after the server
has already closed, the page treats it as an ended CLI session and shows a non-alarming stale-session message instead of
surfacing raw `Failed to fetch`. Active wallet request failures remain distinct from post-completion stale-page
failures. The terminal side of that check passed on 2026-06-14 with
`account get-l1-address --network sepolia`, returning `0x094Ac5364EE8b6Db0e5b1E1C588be8617Fd499A1` and exiting with
code `0`; direct browser final-state visual inspection still needs a human verifier because the automation environment
could not read the Chrome window state.

The CLI should continue to preserve structured diagnostic data from browser-wallet failures without exposing secrets or
raw proof data. At minimum, an `eth_sendTransaction` failure should report or record:

- wallet error `code`, `message`, and sanitized `data`
- whether the injected provider reported `isMetaMask`
- the `eth_accounts` result immediately before the failed request
- the `eth_chainId` result immediately before the failed request
- the transaction `from`, `to`, `value`, and `data` byte length, but not full calldata unless a later explicit debug mode
  is approved
- the signer address selected from the initial browser-wallet connection

This diagnostic path is not a fallback and must not retry, switch accounts, or request extra wallet permissions. It is
only for distinguishing wallet permission state, provider selection, wrong account, wrong chain, and payload-shape
failures.

## Implementation Steps

1. Add signer-mode parsing.
   - Do not add a new browser-wallet option.
   - Treat missing `--account` as browser-backed L1 account authority for commands that need an L1 account.
   - Treat `--tx-submitter <ACCOUNT>` as the existing local submitter path.
   - Treat `--tx-submitter` with no value as browser-backed L1 submitter authority for note commands.
   - Keep no `--tx-submitter` as owner-submitter mode, with browser-wallet fallback only when the local wallet owner L1
     key is absent.

2. Build the browser signing bridge.
   - Add a small localhost HTTP server that serves a static signing page.
   - Add request IDs, one-shot approval sessions, CSRF-resistant random session tokens, and strict localhost-only binding.
   - Keep one browser-wallet bridge server and localhost origin alive across sequential requests in a single CLI command,
     while using per-request IDs to prevent stale page responses from satisfying a later request.
   - Keep one relay page open for the command and let it poll the CLI for the next request, so account connection,
     network checks, signatures, and transaction submission run from one browser JavaScript context.
   - Add a structured request/response protocol for address, chain, message signing, typed-data signing, and transaction
     submission.
   - Request `wallet_switchEthereumChain` when `eth_chainId` does not match the selected network, then re-run
     `eth_chainId` and fail closed if the wallet still does not match.
   - Do not send RPC URLs or API keys to the browser through `wallet_addEthereumChain`; unsupported chains should fail
     with an explicit instruction instead of leaking local RPC configuration.
   - Remove local approval buttons from the signing page. The page should start the wallet provider request on load and
     show only relay status, so the user's click target is the wallet extension UI, not CLI-provided UI.
   - Report relay page load and provider-request-start status back to the CLI so browser launch, provider injection, and
     wallet-response failures are distinguishable.
   - Replace the developer-oriented relay page `Role: ... Action: ...` text with the user-facing request explanation
     model described in "Browser Relay UX Copy". Keep role/action fields internal for diagnostics if useful, but do not
     use them as the primary browser UI copy.
   - Generate request explanations from command context and sanitized warning-summary data. Transaction requests should
     explain the command effect and public consequence; signature requests should explain local key derivation or
     recovery effects; account and network requests should explain that no Ethereum transaction is sent by that request.
   - Do not add extra account-permission prompts around signatures or transaction submission. After the initial wallet
     connection, forward the requested signature or transaction to the wallet and fail clearly on `Unauthorized`, wrong
     account, rejection, or malformed wallet responses.
   - Preserve structured failure diagnostics for `eth_sendTransaction` before running more Sepolia transaction retries.
   - Ensure the page supports any injected EIP-1193 provider compatible with MetaMask methods.
   - Print the signing page URL whenever the CLI opens a browser so the user can manually open the same URL in a
     different MetaMask-capable browser if needed.

3. Add a `BrowserWalletSigner` adapter.
   - Expose `address`, `provider`, `signMessage`, `signTypedData`, and `sendTransaction`-compatible behavior needed by
     current handlers.
   - Provide a transaction preflight path that can still use `staticCall` with the read provider before submitting via
     the browser wallet.
   - Convert populated contract transactions into `eth_sendTransaction` payloads with `from`, `to`, `data`, `value`,
     and chain-compatible fee fields.

4. Split contract transaction construction from submission.
   - Refactor `contractTxCall` and `dryRunThenSubmitTransaction` so dry-run uses a provider or contract runner that does
     not need a local private key.
   - Keep current local-account behavior intact.
   - Add browser-wallet submission without requiring `ethers.Wallet`.

5. Update account and channel commands.
   - Replace direct `requireL1Signer` calls with signer-mode resolution.
   - Update `channel join` to use browser message and typed-data signatures for L2 key derivation.
   - Keep user-facing warnings before each browser approval request.

6. Update wallet and note commands.
   - Allow wallet owner identity to be represented by address-only L1 account data when local L1 secret is absent.
   - Preserve local L2 spending/viewing key requirements.
   - Use value-less `--tx-submitter` as browser-wallet submitter support for `executeChannelTransaction`.
   - When no `--tx-submitter` is provided and no local wallet owner L1 key exists, use browser-wallet owner submission
     only after verifying the selected browser address equals the wallet owner address.
   - Update operation artifact sealing so browser-wallet commands use the existing L2 spending or viewing key where
     available, not a local L1 private key.

7. Update documentation and command help.
   - Document that browser-wallet mode avoids CLI access to the raw L1 private key.
   - Document that L2 spending and viewing keys are still used locally.
   - Document supported browser scope as MetaMask-capable browsers, not Chrome-only.
   - Explain every browser approval request shown during `channel join`.

8. Add tests.
   - Unit-test signer-mode validation, missing `--account` handling, and value-less `--tx-submitter` handling.
   - Unit-test transaction payload conversion for browser submission.
   - Unit-test key derivation using mocked browser signatures.
   - Add command-level tests with a mocked browser signing bridge for each L1 transaction command.
   - Add note-command tests proving that L2 spending key use remains local while L1 submission can use a browser
     submitter.

9. Add manual verification.
   - Do not continue repeated `channel create` transaction attempts until `eth_sendTransaction` failure diagnostics are
     available and recorded.
   - After diagnostics are recorded, verify the browser wallet's Sepolia RPC/backend configuration before retrying
     private-state transaction submission.
   - Do not retry private-state `channel create` until a normal MetaMask Sepolia transaction succeeds through the same
     browser wallet network configuration.
   - Verify with MetaMask on at least two supported browsers when available.
   - On Sepolia, create a fresh named test channel with browser-wallet `channel create` before `channel join` when no
     existing named test channel is available.
   - Verify wrong-chain, wrong-account, rejection, timeout, and closed-browser failure paths.
   - Verify that no browser-wallet command writes an L1 private key file.
   - Verify that the existing local-account path still works.
   - Use `tmp/browser-wallet-manual-verification.md` to record browser coverage, success paths, failure paths, and local
     file checks before release.

## Security Requirements

- Bind the local signing server to `127.0.0.1` only.
- Use a fresh random session token for each browser approval session.
- Use an internal approval timeout with a clear error message. Do not expose timeout tuning as a public CLI option unless
  a production incident proves the default is wrong.
- Never expose wallet secrets, L2 spending keys, viewing keys, note plaintext, or proof artifacts to the browser page
  unless a later explicit design requires it.
- Show the exact signing purpose before requesting browser approval.
- Do not present a localhost approval button. The localhost page is a request relay only; user approval must happen in
  the wallet extension UI.
- Fail closed on user rejection, timeout, wrong address, wrong chain, provider absence, or malformed wallet response.
- When a wrong browser-wallet chain is detected, request a user-approved wallet chain switch once, then fail closed if
  the user rejects the switch, the wallet does not support the target chain, or the rechecked chain still differs.
- Do not silently retry with a different account or with a local private key.
- Do not store browser wallet signatures except where existing wallet recovery or audit data already requires storing
  derived public metadata.

## Compatibility Requirements

- Existing local-account commands must keep their current behavior.
- Existing wallet key import/export and backup semantics must remain unchanged.
- Existing channel workspace and wallet workspace layouts should change only when browser-wallet metadata needs to be
  recorded.
- Existing proof generation must remain compatible with Tokamak L2 transaction semantics.
- Contract entrypoints and successful symbolic paths are not changed by this plan.
- Bridge-managed custody remains unchanged because browser-wallet mode changes only the L1 signing surface.

## Open Design Checks

- Decide whether browser-wallet connection metadata should be cached, or whether every command should reconnect.
- Decide whether the CLI should support WalletConnect later. This plan does not require it because the current request
  is scoped to browser wallets with MetaMask-compatible providers.
- Decide whether browser transaction submission should populate EIP-1559 fee fields itself or delegate fee selection to
  the wallet. The first implementation should prefer wallet fee selection unless a target network requires otherwise.
- Recheck after implementation whether the no-new-option command grammar remains sufficient. Do not add address, browser
  path, timeout, or browser-wallet selector variants unless a concrete production requirement cannot be met by existing
  selectors plus wallet UI.

## Definition of Done

- Every command that currently needs a local L1 private key has a browser-wallet path or a documented reason why it does
  not need one.
- The CLI can complete `channel join`, `wallet deposit-channel`, `wallet mint-notes`, `wallet transfer-notes`,
  `wallet redeem-notes`, `wallet withdraw-channel`, and `channel exit` without importing an L1 private key.
- L2 spending and viewing keys continue to work under the existing local key rules.
- Browser-wallet mode works with MetaMask-capable browsers and contains no Chrome-specific assumptions.
- Browser-wallet mode exposes no new public CLI option.
- Commands that omit `--account` use browser-wallet L1 account authority where an L1 account is required.
- Note commands that pass `--tx-submitter` without a value use browser-wallet L1 submitter authority.
- Browser-wallet failures are explicit and do not fall back to hidden local-key behavior.
- Tests cover signer selection, browser request handling, transaction submission payloads, and L2 key derivation from
  mocked browser signatures.

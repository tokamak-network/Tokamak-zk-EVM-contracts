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
- chain switching or clear user-facing failure when the wallet is on the wrong chain
- EIP-191 message signing through `personal_sign`
- EIP-712 signing through `eth_signTypedData_v4`
- Ethereum transaction submission through `eth_sendTransaction`

The CLI should launch a local signing page served from `127.0.0.1` on an ephemeral port. The page connects to the browser
wallet, displays the request being approved, sends provider requests from the browser context, and returns the result to
the CLI over a localhost callback channel. This is more stable than controlling extension UI and keeps the user approval
surface inside the wallet.

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
   - Add a structured request/response protocol for address, chain, message signing, typed-data signing, and transaction
     submission.
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
   - Verify with MetaMask on at least two supported browsers when available.
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
- Fail closed on user rejection, timeout, wrong address, wrong chain, provider absence, or malformed wallet response.
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

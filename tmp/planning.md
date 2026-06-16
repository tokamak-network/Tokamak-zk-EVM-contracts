# Repository Source and Public Documentation Review

## Scope

This review covers repository-owned tracked source code and public documentation.
It excludes Git submodules, vendored third-party source, generated artifacts, build
outputs, binary fixtures, deployment broadcasts, private environment files, untracked
files, and local-only ignored notes.

`checklist.md` is not treated as public documentation. It was tracked even though
`.gitignore` already contained `checklist.md`; it has now been removed from the Git
index so a fresh remote clone will not receive it. The local file remains ignored.

## User Constraints Applied

- Do not convert intentionally optimized inline assembly into high-level Solidity.
- Do not include `packages/apps/private-state/cli/lib/runtime.mjs` module splitting in
  this review because it will be handled later in stages.
- Do not include Circom circuit edits unless a constraint-count reduction is certain.
- For documentation and implementation mismatches, update the documentation to match
  the implementation.
- Public documentation must not contain drafting instructions, writing guidance,
  editing plans, or other editorial traces.

## Audience Map Used For Review

- Root README and public docs index: broad public entrypoints for users, developers,
  auditors, operators, and external reviewers. They should stay short and route readers
  to the right depth.
- White paper: technically literate external reviewers, auditors, protocol developers,
  operators, and policy reviewers. Detailed reasoning is acceptable, but it should not
  read like a work plan.
- Bridge developer docs and package docs: developers and operators. Detailed mechanics,
  command references, and implementation notes are appropriate.
- Private-state background, contract, constraint, security, and workflow docs:
  integrators, auditors, advanced users, and operators. Technical detail is appropriate,
  but user-facing sections should avoid unnecessary internal terminology.
- Terms and Privacy Notice: ordinary users plus legal, compliance, exchange, and
  investigator readers. They should be plain, accurate, and avoid unnecessary
  implementation internals.
- Monitoring Packet and evidence-scope docs: exchanges, compliance teams, investigators,
  auditors, and users preparing selective disclosure. They should be precise and
  professional, with minimal developer-only detail.
- CLI README and agent instructions: CLI users, operators, and user-controlled AI agents.
  Procedural detail is appropriate when it directly supports safe command execution.

## Source Code Findings

### Private-State DApp Contracts

- `packages/apps/private-state/src/PrivateStateController.sol` contains an unused
  internal helper, `_prepareOutputNote(...)`. Repository-wide references only point to
  its definition, while active mint and transfer paths use `_prepareMintOutput(...)` or
  `_prepareTransferOutput(...)`.
- `packages/common/src/network-config.mjs` exposes `base-*`, `arb-*`, and `op-*`
  entries through `APP_NETWORKS`, and
  `packages/apps/private-state/scripts/deploy/deploy-private-state.mjs` accepts any
  `resolveAppNetwork(...)` name. The public private-state deployment surface documents
  only `anvil`, `sepolia`, and `mainnet`, so unsupported app networks are reachable
  through source code.

### Bridge Contracts

- `bridge/src/DAppManager.sol` and `bridge/src/ChannelManager.sol` independently
  implement the same DApp function metadata hash domains and `_hashFunctionMetadata(...)`
  procedure. `DAppManager` uses it to derive registered function leaves and roots, while
  `ChannelManager` uses a local copy to verify execution-time function metadata proofs.
  This repeated protocol logic must remain byte-identical across registration and
  execution.
- `bridge/src/ChannelManager.sol` keeps the access-check logic inline in the
  `onlyBridgeCore`, `onlyBridgeTokenVault`, and `onlyLeader` modifiers. Foundry flags
  these as repeated modifier bodies that can increase deployed bytecode when reused
  across functions.

### Deployment And Upload Scripts

- `scripts/drive/lib/google-drive-upload.mjs` exports `createTimestampLabel(...)`, but
  repo-owned callers import the same helper from
  `scripts/deployment/lib/deployment-layout.mjs`. The Drive helper copy has the same
  implementation and no repo-owned import, so it is a duplicated unused export.
- `bridge/scripts/upload-bridge-artifacts.mjs` and
  `bridge/scripts/upload-dapp-artifacts.mjs` repeat the same Drive upload orchestration:
  parse timestamp/preflight/receipt flags, resolve Drive config, preflight the exclusive
  folder, create the folder, upload relative-path files, update the artifact index, write
  a receipt, and print the same Drive summary. The artifact collection differs, but the
  orchestration is duplicated across both scripts.

### Package Manifests

- The root `package.json` declares `"fs": "^0.0.1-security"` even though repo-owned
  source uses Node's built-in filesystem module through `node:fs` or the built-in `fs`
  specifier.
- The root `package.json` declares `@tokamak-zk-evm/synthesizer-node`, but repo-owned
  source references only the manifest and README entries. Current synthesis flows invoke
  `tokamak-cli --synthesize`; they do not import or resolve this package directly.
- The root `package.json` declares `msgpackr`, but repo-owned source references only
  the manifest and lockfile entries.
- The root `package.json` declares `js-sha3`, but repo-owned source references only the
  manifest and lockfile entries.

## Public Documentation Findings

### Implementation Mismatches

- `bridge/README.md` states that `DAppManager.deleteDApp(...)` is available only on
  Sepolia and that mainnet and every non-Sepolia network reject it. The implementation in
  `bridge/src/DAppManager.sol` allows deletion on Sepolia (`11155111`) and local Anvil
  (`31337`), and `docs/bridge/gas-assessment.md` already says "Sepolia/local only".
- `bridge/docs/dev/current-implementation.md` says DApp registration consumes selected
  example groups such as `privateStateMint`, `privateStateTransfer`, and
  `privateStateRedeem`. The active private-state registration materializer and public
  README examples use `mintNotes`, `transferNotes`, and `redeemNotes`.
- `docs/dapps/private-state/contract-spec.md` documents `NoteValueEncrypted` as the
  controller event model but omits `StorageKeyObserved` from
  `PrivateStateController.sol` and `LiquidBalanceStorageWriteObserved` from
  `L2AccountingVault.sol`. These events are used by tests, CLI recovery, bridge
  observation, and the monitoring packet generator.
- `docs/dapps/private-state/workflow.md` says `wallet redeem-notes` chooses the fixed
  redeem arity from the selected note count and submits the matching `redeemNotesN`
  call. The current CLI allows exactly one selected note for `wallet redeem-notes`.
- `packages/apps/private-state/cli/assets/service-terms.md` links to
  `privacy-notice.md`, but no such file exists beside the packaged Terms asset. The
  canonical notice lives at `docs/dapps/private-state/privacy-notice.md`.
- `README.md` says bridge deployment and DApp registration consume
  `@tokamak-zk-evm/synthesizer-node`, but repo-owned source does not import, resolve, or
  execute that package directly. Current registration flows invoke synthesis through
  `tokamak-cli --synthesize`.
- `packages/apps/private-state/README.md` says `channel recover-workspace` accepts
  `--source mirror` to recover from a registered workspace mirror "before falling back to
  a full RPC genesis rebuild". The CLI guidance and runtime fail closed instead of
  automatically falling back; users must explicitly run
  `--source rpc --from-genesis` only when no compatible mirror is available.

### Audience And Expression Issues

- `docs/dapps/private-state/privacy-notice.md` is aimed at ordinary users and legal or
  compliance readers, but it includes highly specific operational internals such as
  Vercel plan settings, AWS region details, EBS volume size, encryption state, systemd
  journal size, and raw RPC file counts. Those details are too implementation-specific
  for a privacy notice and should be reduced to user-relevant data categories,
  retention facts, and third-party service boundaries.
- `docs/dapps/private-state/index.md` contains a "How should this DApp be positioned?"
  section that tells writers which positioning terms to use. That is editorial guidance,
  not end-user or integrator documentation.
- `docs/dapps/private-state/background-theory.md` and
  `docs/dapps/private-state/security-model.md` include phrasing such as "should be
  described", "should be presented", and "Documentation and external communication
  should not imply". These are public-document writing instructions and should be
  rewritten as factual product or protocol statements.
- `docs/audit/monitoring/Monitoring-Packet.md`,
  `docs/audit/monitoring/data/User-Controlled-Evidence-Scope.md`,
  `packages/apps/private-state/cli/README.md`, and
  `packages/apps/private-state/cli/investigator/README.md` use the phrase
  "ASCII-art linkage report". The evidence and monitoring audience includes exchanges,
  compliance teams, investigators, auditors, and users preparing formal disclosure, so
  that phrase is too informal. A neutral phrase such as "plain-text linkage report" is
  more appropriate.
- The public documentation set does not consistently label the target audience at each
  document entrypoint. `docs/index.md` and `docs/dapps/private-state/index.md` provide
  reading order, but they do not clearly separate ordinary-user, legal/compliance,
  auditor, operator, AI-agent, and developer reading paths. This makes some highly
  technical material look like required reading for non-expert users.

## Non-Public Documentation Hygiene

- `checklist.md` was tracked despite being local/internal material and ignored by
  `.gitignore`. It has been removed from the Git index in this pass. The next commit must
  include that deletion so remote clones do not receive it.
- `tmp/browser-wallet-manual-verification.md` is tracked and therefore included in fresh
  remote clones even though it is a release-verification working log. It contains local
  machine paths, browser availability notes, Sepolia wallet addresses, transaction-level
  manual retry history, hypotheses, and unfinished follow-up notes. That material is not
  appropriate as public product, legal, compliance, developer, or operator documentation in
  its current form.

## Behavior-Preserving Fix Plan

The fixes must preserve the current contract, CLI, deployment-script, and document routing
behavior unless a later request explicitly authorizes a behavior change. Documentation mismatches
are resolved by updating documentation to match the implementation, not by changing implementation
behavior.

### 1. Remove Non-Public Local Notes From The Remote Clone Surface

- Keep the already-completed `checklist.md` Git-index removal.
- Keep `checklist.md` ignored in `.gitignore`.
- Remove `tmp/browser-wallet-manual-verification.md` from the tracked remote-clone surface, or move a
  sanitized release-verification template to a public documentation path if that template is still
  needed.
- Behavior preservation check:
  - No runtime, deployment, package, ABI, storage, or CLI command file is changed.
  - `git ls-files checklist.md tmp/browser-wallet-manual-verification.md` must return no tracked
    local working-log path after the cleanup.
  - `git check-ignore -v checklist.md` must continue to report the ignore rule.

### 2. Make Public Documentation Match Current Implementation

- Change `bridge/README.md` to say `DAppManager.deleteDApp(...)` is Sepolia/local only.
- Change `bridge/docs/dev/current-implementation.md` group names to `mintNotes`,
  `transferNotes`, and `redeemNotes`.
- Expand `docs/dapps/private-state/contract-spec.md` event documentation to include
  `StorageKeyObserved` and `LiquidBalanceStorageWriteObserved`, with their public monitoring role.
- Change `docs/dapps/private-state/workflow.md` to state that the current CLI user-facing
  `wallet redeem-notes` flow supports one selected note, even though Solidity exposes multiple
  redeem arities.
- Fix the packaged service Terms privacy-notice reference so npm package readers can reach the
  canonical Privacy Notice.
- Remove `@tokamak-zk-evm/synthesizer-node` from the root README dependency narrative unless a
  direct repo-owned consumption path is added later.
- Reword the private-state README workspace-mirror recovery section so mirror recovery and explicit
  RPC genesis recovery are separate user actions, matching CLI behavior.
- Document the broader accepted private-state deployment network names if the source continues to
  accept `APP_NETWORKS`; do not add deploy-script rejection for `base-*`, `arb-*`, or `op-*` in this
  pass.
- Behavior preservation check:
  - Only documentation and packaged documentation assets are changed.
  - No CLI argument parsing, network selection, recovery fallback, Terms acceptance, contract event,
    or deployment-script behavior is changed.
  - Local Markdown links still resolve.

### 3. Rewrite Audience-Inappropriate Public Documentation

- Replace editorial guidance in the private-state index, background theory, and security model with
  factual statements suitable for their readers.
- Simplify the Privacy Notice by replacing infrastructure inspection details with plain data
  categories, user impact, third-party service boundaries, and retention summaries.
- Replace "ASCII-art linkage report" with "plain-text linkage report" across evidence,
  monitoring, CLI, and investigator documentation.
- Add explicit audience labels or reading paths in `docs/index.md` and
  `docs/dapps/private-state/index.md` so ordinary users, legal/compliance readers, auditors,
  operators, developers, and user-controlled AI agents are routed to the correct depth.
- Behavior preservation check:
  - Text changes must not rename CLI commands, options, JSON fields, contract events, contract
    methods, npm package names, or public URLs unless the referenced implementation already uses the
    replacement.
  - Legal/user-facing simplification must preserve the current risk allocation, self-custody
    boundary, no-master-viewing-key statement, and third-party service boundary.
  - The packaged Terms asset and canonical Terms stay text-aligned except for path-context link
    differences that are required by packaging.

### 4. Clean Source Code Only Where No Runtime Path Changes

- Remove the unused `_prepareOutputNote(...)` helper from `PrivateStateController.sol`.
- Remove or de-export the unused duplicate `createTimestampLabel(...)` helper from
  `scripts/drive/lib/google-drive-upload.mjs`; keep the canonical helper in
  `scripts/deployment/lib/deployment-layout.mjs`.
- Remove unused root dependencies `fs`, `@tokamak-zk-evm/synthesizer-node`, `msgpackr`, and
  `js-sha3` from the root manifest and lockfile only after confirming no repo-owned source imports,
  resolves, or executes them directly.
- Do not convert optimized inline assembly to high-level Solidity.
- Do not change Circom circuits unless a constraint-count reduction is certain and separately
  approved for a circuit pass.
- Behavior preservation check:
  - `forge build` and focused private-state contract tests must pass.
  - Public ABI, storage layout, event signatures, revert selectors, command names, command options,
    and generated deployment artifact schema must remain unchanged.
  - Package cleanup must pass package smoke tests and must not remove dependencies required by
    workspace packages through their own manifests.
  - If removing a root direct dependency changes the resolved version of a package that repo-owned
    source actually uses, keep the dependency in place or split that package-resolution change into a
    separately reviewed dependency-maintenance pass.

### 5. Add Drift Guards Instead Of Protocol Refactors

- For duplicated DApp function metadata hashing in `DAppManager` and `ChannelManager`, prefer an
  equivalence guard over a runtime refactor in this pass.
- Add tests or a deterministic comparison fixture that proves registration-time function leaves and
  execution-time function proof verification use the same domain constants and field order.
- Do not move the hashing into a shared Solidity library unless a later implementation pass proves:
  - the same inputs produce the same hashes before and after the refactor,
  - all existing bridge tests pass,
  - public ABI and storage layout remain unchanged,
  - gas or bytecode impact is reviewed, and
  - the refactor does not change failure modes.
- Behavior preservation check:
  - The first safe correction is test coverage or static verification only.
  - Any future code refactor must be treated as a separate behavior-preservation review, not as an
    automatic part of this documentation/source cleanup plan.

### 6. Defer Optional Refactors Unless They Can Be Proven Behavior-Neutral

- `ChannelManager` modifier wrapping can be considered only if bytecode-size benefit is measured and
  access-control behavior, custom errors, revert locations relevant to tests, ABI, and storage layout
  remain unchanged.
- Shared Drive upload orchestration can be considered only if bridge and DApp upload scripts keep
  the same CLI flags, validation errors, preflight behavior, folder paths, upload file lists, receipt
  JSON fields, artifact-index updates, and console summaries.
- Behavior preservation check:
  - If exact behavior cannot be asserted from tests or golden fixtures, leave the duplicated code in
    place and document the duplication as accepted until a dedicated refactor pass.

### 7. Final Verification Gate

- Run local Markdown link existence checks for tracked public docs.
- Run `git diff --check`.
- Run focused Solidity and Node/package tests for touched files.
- Confirm `checklist.md` remains ignored and untracked.
- Confirm no runtime behavior changes by reviewing the final diff against this checklist before
  committing.

## Behavior Preservation Self-Check

First review result: the original plan was not behavior-preserving because it considered rejecting
currently accepted private-state deployment network names. The plan was revised to update
documentation to match the current `APP_NETWORKS` acceptance behavior instead.

Second review result: the original plan could have changed protocol code by consolidating
duplicated DApp function metadata hashing. The plan was revised to add equivalence guards first and
to require a separate behavior-preservation review before any runtime refactor.

Third review result: the original plan could have changed script behavior by extracting shared
Drive upload orchestration without specifying exact compatibility requirements. The plan was revised
to defer that refactor unless golden behavior for flags, errors, folder paths, receipts, artifact
index updates, and console output is preserved.

Final self-check result: the revised plan preserves existing behavior by default. Required fixes are
documentation alignment, removal of non-public tracked notes, unused-code removal, unused direct
dependency cleanup, and drift-guard tests. Any item that might change runtime behavior is either
converted into documentation that matches current implementation, constrained by explicit
behavior-preservation gates, or deferred to a separately approved refactor pass.

# Developer Notes

This note is for developers who need to deploy or operate the bridge, deploy or register a DApp,
operate channels, or build a bridge-coupled DApp. It is a handoff checklist, not a protocol
specification and not a zero-knowledge proof tutorial.

For detailed background, use the linked documents and code locations instead of duplicating that
content here.

## 1. Purpose And Audience

Use this document when you are responsible for one of these tasks:

- deploying or upgrading the bridge
- deploying and registering a DApp
- operating a channel, observer, or workspace mirror
- changing bridge-coupled DApp contracts or CLI behavior
- checking artifacts, runtime compatibility, release notes, or incident response steps

The expected reader is a general blockchain developer who understands Solidity deployment and
operations, but is not assumed to be a zero-knowledge proof expert.

## 2. Bridge Deployment And Administration

Before bridge deployment or upgrade:

- Use [bridge/scripts/deploy-bridge.mjs](./bridge/scripts/deploy-bridge.mjs). Do not use ad hoc
  `forge script` broadcasts for production bridge state.
- Keep bridge deployment variables in the root `.env` based on [`.env.example`](./.env.example).
  Keep app deployment variables in [packages/apps/.env](./packages/apps/.env.template).
- Before mainnet work, check source commit availability, dirty state, deployment mode, and Google
  Drive deployment history.
- Treat `upgrade` mode as Safe upgrade preparation when the bridge owner is a Safe. The generated
  Safe Transaction Builder JSON is not final deployed bridge state until the Safe executes it.
- After a Safe batch executes, regenerate final deployment artifacts from on-chain state before
  publishing artifacts or updating monitoring material.
- Preserve owner-only call records, Safe transaction artifacts, transaction hashes, artifact upload
  receipts, and source verification evidence.

Detailed deployment modes, Safe flow, and environment variables are documented in
[bridge/README.md](./bridge/README.md). Source-integrity and artifact-upload checks are implemented
in [bridge/scripts/deploy-bridge.mjs](./bridge/scripts/deploy-bridge.mjs) and
[bridge/scripts/upload-bridge-artifacts.mjs](./bridge/scripts/upload-bridge-artifacts.mjs).

## 3. DApp Deployment And Registration

Before registering a DApp:

- Confirm the DApp deployment manifest, storage layout, callable ABIs, source snapshot, chain ID,
  RPC endpoint, canonical asset address, and artifact folder all refer to the same deployment.
- Register DApp metadata with [bridge/scripts/admin-add-dapp.mjs](./bridge/scripts/admin-add-dapp.mjs).
- After registration, verify the metadata digest, digest schema, function root, verifier snapshot,
  managed storage vector, and channel-token-vault storage index.
- Remember that a Solidity function is usable in a channel only when it is registered, provable with
  the active proving stack, and supported by the user-facing CLI or application.

App deployment details are in
[packages/apps/private-state/README.md](./packages/apps/private-state/README.md). Current DApp
registration behavior, including private-state storage-role inference, is implemented in
[bridge/scripts/admin-add-dapp.mjs](./bridge/scripts/admin-add-dapp.mjs) and summarized in
[bridge/docs/dev/current-implementation.md](./bridge/docs/dev/current-implementation.md).

Several malformed registration cases are already rejected by code. See
[bridge/src/DAppManager.sol](./bridge/src/DAppManager.sol) and
[bridge/src/BridgeCore.sol](./bridge/src/BridgeCore.sol) before turning those checks into manual
runbook steps.

## 4. DApp Development Compatibility

ABI compatibility is not enough for bridge compatibility.

For every user-executable function shape, varying user inputs must preserve the registered
Tokamak zk-EVM Synthesizer and preprocess structure:

- `synthesizer/output/instance_description.json` must keep the expected `a_pub_user_description`
  layout.
- `preprocess/output/preprocess.json` must produce the expected preprocess input hash.
- `synthesizer/output/instance.json` must keep the expected public input shape and `a_pub_block`
  compatibility.
- managed storage vector order, storage-write descriptors, event-log descriptors, offsets, and
  ordering must remain compatible with the registered channel policy.

Runtime values such as roots, balances, note values, storage values, and user inputs can change per
execution. The public input structure and metadata layout are the parts that must remain stable for
the registered function policy.

When changing a DApp:

- Treat Synthesizer example groups as registration inputs, not disposable tests.
- Re-check managed storage count and root-vector shape before adding storage contracts.
- Re-check what public outputs and emitted logs disclose, because observer and monitoring services
  can only respect the privacy boundary actually exposed by the DApp.
- Treat a changed function shape as a future-channel compatibility change unless you have proven it
  remains compatible with the existing registered metadata.

Detailed bridge coupling is described in
[docs/dapps/private-state/workflow.md](./docs/dapps/private-state/workflow.md). Function metadata
extraction is implemented in [bridge/scripts/admin-add-dapp.mjs](./bridge/scripts/admin-add-dapp.mjs).

## 5. Channel Operation, Observer, And Mirror

Before creating or joining a channel:

- Review the immutable policy: DApp digest, function root, verifier snapshot, managed storage vector,
  Join Toll, refund policy, workspace mirror, and observer URL when present.
- Do not confuse Join Toll with bridge deposits. Join Toll is paid directly from the Ethereum wallet
  during channel join; bridge deposits fund channel accounting.
- Remember that later DApp metadata, verifier, or proving-capacity updates do not modify existing
  channel policy.

For channel operation:

- The channel leader can update the channel observer URL and workspace mirror URL.
- The channel leader is not a custody authority, key holder, viewing authority, or note plaintext
  recovery authority by virtue of that role.
- Channel operation abandonment blocks new joins and new channel deposits only. It does not block
  existing note activity, redemption, channel withdrawal, channel exit, or bridge withdrawal.

Observer and mirror responsibilities:

- The observer is a channel-scoped public monitoring surface, not a wallet, key manager, custody
  system, or disclosure authority.
- The workspace mirror is an availability aid for channel-state recovery, not custody or viewing
  authority.
- Register observer URLs through `BridgeCore.setChannelObserver(...)` when a channel has an official
  public observer.
- Register mirror URLs through `BridgeCore.setChannelWorkspaceMirror(...)` when a channel provider
  operates a mirror.
- Verify observer and mirror health against indexed public events, not just URL availability.

Channel flow is described in
[packages/apps/private-state/README.md](./packages/apps/private-state/README.md). Observer and
Monitoring Packet material is in
[docs/audit/monitoring/Monitoring-Packet.md](./docs/audit/monitoring/Monitoring-Packet.md). The
workspace mirror protocol is in
[docs/dapps/private-state/channel-workspace-mirror-protocol.md](./docs/dapps/private-state/channel-workspace-mirror-protocol.md).
Observer and mirror permissions are implemented in
[bridge/src/BridgeCore.sol](./bridge/src/BridgeCore.sol).

## 6. Artifacts, Runtime, And Recovery

Operational consistency matters more than any single local file.

Check that these surfaces point to the same source state and chain:

- Git commit and remote source
- bridge deployment artifact
- DApp deployment artifact
- DApp registration artifact
- ABI manifest
- storage layout
- Groth16 files
- generated verifier sources
- Google Drive artifact folder

Runtime compatibility checks:

- Keep Tokamak CLI/runtime packages, `tokamak-l2js`, generated Tokamak verifier sources, Groth16
  CRS, generated Groth16 verifier, and private-state CLI proof runtime compatible.
- Do not hide verifier, CRS, Merkle-depth, preprocess, or backend-version mismatches behind fallback
  logic. They should fail loudly before users create or join channels.

Recovery and indexing checks:

- RPC provider quality and `eth_getLogs` limits affect channel recovery, note recovery, observer
  indexing, workspace mirrors, and monitoring.
- Check event indexing completeness for root-vector observations, storage-write observations,
  channel metadata events, channel registration events, and DApp-propagated events.
- Prefer configured recovery indexes and mirrors for normal operation. Use genesis replay only when
  the operator intentionally accepts the RPC cost and delay.

Artifact publication rules are summarized in the README section
[Deployment And Registration Artifacts](./README.md#deployment-and-registration-artifacts). Groth16
version rules are in [packages/groth16/docs/version-rules.md](./packages/groth16/docs/version-rules.md).

## 7. Secrets, Releases, And Incidents

Keep authority boundaries explicit:

- Ethereum private keys, wallet secret source files, spending keys, viewing keys, and wallet backups
  are different authority classes.
- A wallet backup is not a spending key or viewing key.
- Do not ask users to submit wallet secret source files, spending keys, viewing keys, seed phrases,
  or raw private keys for observer, mirror, monitoring, or support workflows.

When user-visible behavior changes:

- Check README updates, CLI help or warning text, changelog entries, package versions, release notes,
  and public documentation links.
- For publishable package changes, follow [RELEASING.md](./RELEASING.md).

Incident response rule:

- For bad DApp metadata, wrong verifier bindings, stale artifacts, broken observer or mirror state,
  incompatible runtime artifacts, or bad channel policy, do not silently mutate an existing channel
  as if users had accepted the new policy.
- Announce the affected channel, stop unsafe onboarding, publish corrected metadata or artifacts for
  future channels, and plan a new channel or migration path.
- Keep evidence from owner calls, Safe execution, transaction hashes, artifact uploads, observer or
  mirror updates, and monitoring regeneration.

The security and key model is documented in
[docs/dapps/private-state/security-model.md](./docs/dapps/private-state/security-model.md).

## 8. Minimum Verification

Use these as the minimum local checks before handing over bridge, DApp, CLI, artifact, or workflow
changes:

```bash
npm run test:bridge:unit
npm run test:private-state:cli-e2e
```

For private-state contract or CLI work:

```bash
cd packages/apps/private-state
make test
make e2e-bridge-cli
```

When deployed ChannelManager source verification matters, use
[bridge/scripts/verify-channel-managers.mjs](./bridge/scripts/verify-channel-managers.mjs).

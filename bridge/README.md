# Bridge Workspace

This folder contains a standalone bridge-contract implementation. Start with:

- `bridge/docs/spec.md`
- `bridge/docs/zk-l2-bridge-whitepaper.md`
- `bridge/docs/current-implementation.md`

The existing bridge implementation under the repository `src` directory was intentionally not referenced or reused.

## Scope

This workspace focuses on the current design documented in the notes:

- immediate Tokamak-zkp verification
- one shared bridgeTokenVault on L1
- bridge-managed DApp metadata
- per-channel `aPubBlockHash` verification context
- globally unique channelTokenVault keys
- per-channel non-collision of derived channelTokenVault leaf indices
- stable root-entry addresses through UUPS proxies

## Mocked Areas

The documents do not specify enough operational detail to implement every production path safely. The following areas are therefore still simplified on purpose:

- final proposal-pool and token-economics behavior

Tokamak proof verification is no longer mocked. The bridge now calls the real verifier under `bridge/src/verifiers/`, binds the user-supplied transaction instance to fields extracted from `aPubUser`, and checks the channel-scoped `aPubBlockHash` together with the DApp-managed preprocess-input hash and per-function storage-write metadata. The channel manager no longer stores the full current root vector on-chain; it stores only `currentRootVectorHash`. The full updated root vector is emitted as `CurrentRootVectorObserved` after every proof-backed state transition so off-chain indexers can reconstruct the post-state that produced the new hash. After a successful verification, `executeChannelTransaction` emits `StorageWriteObserved` for every decoded `aPubUser` storage write, and the Groth-backed `deposit` and `withdraw` paths emit the same event format for their `channelTokenVault` writes. Under the latest synthesizer format, those events now expose the storage key rather than the derived tree index. The bridge still derives the `channelTokenVault` leaf index internally from that storage key when it updates the local leaf cache. A Tokamak proof that changes the `channelTokenVault` root without a matching `channelTokenVault` storage write is rejected.

Groth proof verification is also no longer mocked. The bridge expects raw Groth16 proof coordinates and forwards them into the generated `updateTree` verifier under `bridge/src/generated/`. Under the current circuit model, each `channelTokenVault` leaf is the raw stored balance value rather than a key-value hash.

## Security-Critical Assumptions

The current bridge implementation hardens a few assumptions that must remain true in production:

- The Groth `channelTokenVault` circuit and the bridge both assume a fixed Merkle-tree depth of `12`. The admin manager rejects other depths.
- Channel creation derives the channel-scoped `aPubBlockHash` from the channel-creation block context on-chain, so Tokamak proof submissions cannot silently skip block-context binding.
- DApp registration requires a nonzero `preprocessInputHash`, and each function also carries fixed `aPubUser` layout metadata derived from the synthesizer `instance_description.json`. All functions in a DApp share one managed storage-address vector, so the root-vector length and the `channelTokenVault` tree index are fixed at channel creation. The bridge stores and later caches the per-function entry-contract, selector, current-root, and updated-root offsets, plus storage-write descriptors that identify the target storage through the DApp-wide managed storage-address index and record the `aPubUser` word offset at which the corresponding storage key appears. Under the current synthesizer format, every storage write still contributes four `aPubUser` words: storage-key lower/upper and storage-write lower/upper.
- The shared `bridgeTokenVault` is hard-wired to the chain's canonical Tokamak Network Token address through `BridgeCore.canonicalAsset()`. The bridge therefore explicitly relies on Tokamak Network Token continuing to behave as an exact-transfer ERC-20 for bridge purposes. Fee-on-transfer behavior, transfer blacklisting, transfer pausing, or other balance-mutating transfer semantics would break bridge availability.
- This repository currently adopts that dependency as an explicit trust assumption rather than trying to abstract over arbitrary ERC-20 behavior. Operators and user-facing risk disclosures should state clearly that bridge ingress and egress depend on the present and future transfer semantics and governance controls of Tokamak Network Token.

Important operational context:

- the qap-compiler and its subcircuit library expose a bounded proving capacity at any given release
- a deployed channel is therefore expected to register only the function families that fit within that currently supported proving surface
- omitted function families should not automatically be interpreted as accidental metadata incompleteness; they may be an intentional consequence of the current proving-capacity bound
- channels are treated as one-shot deployments with a fixed execution grammar for their lifetime
- if a later compiler or subcircuit-library release expands the admissible function surface, the intended workflow is to create new channels with the expanded function set rather than mutate existing channels in place

This channel immutability is intentional policy, not an accidental upgradeability gap. The channel's verifier bindings, DApp execution metadata, function layout, managed storage vector, and refund schedule are part of the operating policy users accept when they join. They should not be changed in place during active channel use without renewed user consent. The tradeoff is that a policy-level bug in an existing channel normally requires creating a new channel or migrating users rather than mutating that channel.

Reviewers and operators should evaluate a channel against the function family it intentionally declares at creation time, not against every function family that might become supportable in a future proving release.

## Deployment

The standalone bridge workspace now includes a Foundry deployment script:

- `bridge/scripts/DeployBridgeStack.s.sol`
- `bridge/scripts/UpgradeBridgeStack.s.sol`

On the first proxy-based deployment it creates:

- `DAppManager` proxy and implementation
- `Groth16Verifier`
- `TokamakVerifier`
- `BridgeCore` proxy and implementation
- optionally `MockERC20`

After that initial migration, the helper script upgrades the existing proxies in place instead of creating new root-entry addresses. In other words:

- first proxy deployment: root bridge addresses change once, because the legacy non-proxy deployment cannot be converted in place
- later upgrades: `DAppManager`, `BridgeCore`, and `L1TokenVault` keep the same proxy addresses while only their implementations are redeployed

Required environment variables:

- `BRIDGE_DEPLOYER_PRIVATE_KEY`
- `BRIDGE_NETWORK`
- `BRIDGE_ALCHEMY_API_KEY` for `sepolia` or `mainnet`

Optional environment variables:

- `BRIDGE_RPC_URL_OVERRIDE`
- `BRIDGE_DEPLOY_MODE` with `upgrade` or `redeploy-proxy`
- `BRIDGE_GROTH_SOURCE` with `trusted` or `mpc`
- `BRIDGE_OWNER`
- `BRIDGE_DEPLOY_MOCK_ASSET`
- `BRIDGE_MOCK_ASSET_NAME`
- `BRIDGE_MOCK_ASSET_SYMBOL`
- `BRIDGE_OUTPUT_PATH`
- `BRIDGE_REFLECTION_MANIFEST_PATH` to override the bridge ZK manifest output path
- `BRIDGE_SKIP_TOKAMAK_INSTALL=1`
- `BRIDGE_SKIP_TOKAMAK_VERIFIER_REFRESH=1`
- `BRIDGE_SKIP_GROTH_REFRESH=1`

The repository root now includes `.env.example` for bridge deployment. Copy it to `.env`,
fill in the bridge variables, and use the helper script:

```bash
cp .env.example .env
$EDITOR .env

node bridge/scripts/deploy-bridge.mjs
```

Or select the deployment mode explicitly:

```bash
node bridge/scripts/deploy-bridge.mjs --mode upgrade
node bridge/scripts/deploy-bridge.mjs --mode redeploy-proxy
```

The helper derives the correct Alchemy RPC URL from:

- `BRIDGE_NETWORK=sepolia` -> `https://eth-sepolia.g.alchemy.com/v2/<key>`
- `BRIDGE_NETWORK=mainnet` -> `https://eth-mainnet.g.alchemy.com/v2/<key>`

If you need a non-Alchemy endpoint, set `BRIDGE_RPC_URL_OVERRIDE`.

The helper reads the locally installed `tokamak-l2js` package and its exported
`MT_DEPTH` before broadcasting deployment. The helper refreshes the
Tokamak verifier parameters from `setupParams.json`, regenerates the Groth16
`updateTree` verifier, and writes the bridge ZK manifest directly from
`bridge/scripts/deploy-bridge.mjs`. The installed `MT_DEPTH` value is recorded
in deployment metadata through the generated `TokamakEnvironment` constants.

The Groth16 refresh source is selected explicitly through `BRIDGE_GROTH_SOURCE`.
When unset, the bridge helper defaults to `mpc` for every supported network.

Both `trusted` and `mpc` install the selected CRS into the fixed Groth16 runtime workspace
(`~/tokamak-private-channels/groth16`) before the bridge verifier is regenerated. `trusted`
generates a local snarkjs trusted setup in that workspace. `mpc` downloads the latest public
Groth16 MPC archive.

The bridge implementation validates the locally installed `tokamak-l2js`
`MT_DEPTH` before deployment so it fails rather than silently deploying a
mismatched bridge configuration.

The helper now has two explicit modes:

- `upgrade`: redeploy implementations only and upgrade the existing proxies in place
- `redeploy-proxy`: redeploy fresh proxies and fresh implementations, replacing the network-scoped deployment artifact

`upgrade` never creates or replaces proxies. If the network-scoped deployment artifact is missing or is not proxy-based,
the command fails and you must run `redeploy-proxy` intentionally.

The script writes one timestamped deployment artifact per chain under `deployment/` by default:

- `deployment/chain-id-<chain-id>/bridge/<timestamp>/bridge.<chain-id>.json`

It also generates one ABI manifest per network from the current Foundry build artifacts:

- `deployment/chain-id-<chain-id>/bridge/<timestamp>/bridge-abi-manifest.<chain-id>.json`

The deployment JSON is post-processed to include `chainId` and `abiManifestPath` so downstream tooling can resolve the correct bridge ABI set without hardcoded function signatures.

## Bridge administration

To add a new DApp metadata bundle to an already deployed bridge, use:

- `bridge/scripts/deploy-and-add-dapp.mjs`
- `bridge/scripts/admin-add-dapp.mjs`

`deploy-and-add-dapp.mjs`:

- deploys the private-state app to the selected app network first
- then invokes `admin-add-dapp.mjs` to register the already deployed app on the bridge

`admin-add-dapp.mjs`:

- assumes the private-state app is already deployed
- writes chain-scoped DApp registration snapshots under `deployment/chain-id-<chain-id>/dapps/private-state/<timestamp>/`
- reads the selected example-group inputs from `packages/apps/private-state/examples/synthesizer/privateState/`
- runs the installed `@tokamak-zk-evm/cli` runtime without passing RPC or Alchemy arguments
- synthesizes and preprocesses the selected example group
- derives function metadata from `instance.json` and `instance_description.json`
- calls `DAppManager.registerDApp(...)` for a new DApp ID, or `DAppManager.updateDAppMetadata(...)` with `--replace-existing`

Current constraint:

- `DAppManager.deleteDApp(...)` is available only on Sepolia
- DApp deletion ignores active channel count, so channel managers can outlive their parent DApp registration
- mainnet and every non-Sepolia network reject `deleteDApp(...)` outright
- `DAppManager.updateDAppMetadata(...)` is available on mainnet, but keeps the existing `dappId` and `labelHash`
- channels keep the DApp metadata and verifier snapshot that existed at channel creation time

Example usage:

```bash
node bridge/scripts/deploy-and-add-dapp.mjs \
  --group mintNotes \
  --group transferNotes \
  --group redeemNotes \
  --dapp-id 1
```

If the app must be deployed to a different network before registration, select it explicitly:

```bash
node bridge/scripts/deploy-and-add-dapp.mjs \
  --group mintNotes \
  --group transferNotes \
  --group redeemNotes \
  --dapp-id 1 \
  --app-network sepolia
```

Relevant options:

- `deploy-and-add-dapp.mjs` accepts `--app-network <name>`, `--app-env-file <path>`, and `--app-rpc-url <url>` for the deployment step
- `admin-add-dapp.mjs` accepts `--app-network <name>` to choose which already-deployed app manifests should be used
- `admin-add-dapp.mjs` accepts `--app-deployment-path <path>` and `--storage-layout-path <path>` to override those manifests explicitly

When `--app-network` is omitted, both scripts default to `APPS_NETWORK`, then `BRIDGE_NETWORK`, and finally the bridge chain name when it is known.

If the private-state app is already deployed and only registration is needed, use:

```bash
node bridge/scripts/admin-add-dapp.mjs \
  --group mintNotes \
  --group transferNotes \
  --group redeemNotes \
  --dapp-id 1 \
  --app-network sepolia
```

## User safety note

For bridge-coupled private-state channels, users should treat `join-channel` as the activation step for all later channel activity.

Operators and user-facing documentation should instruct users not to:

- deposit channel funds
- send notes to the channel L2 identity
- expect incoming note delivery
- attempt wallet recovery from channel activity

until the `join-channel` transaction has been confirmed on-chain and the registration receipt has been checked successfully.

Until that confirmation exists, the user's channel registration is not final and later channel actions can be mis-targeted or fail against incomplete channel identity state.

Users should also treat `join-channel` as acceptance of the channel's immutable operating policy. Before joining, users should be shown the channel's verifier bindings, DApp execution metadata, function layout, managed storage vector, and refund policy at a level appropriate for the interface. If a later policy-level issue is found, the expected mitigation is a new channel or migration flow, not in-place mutation of the joined channel.

After a successful bridge deployment, the bridge-owned Groth16 deployment mirror is refreshed under:

- `deployment/chain-id-<chain-id>/bridge/<timestamp>/groth16.<chain-id>.latest.json`
- `deployment/chain-id-<chain-id>/bridge/<timestamp>/groth16/circuit_final.zkey`
- `deployment/chain-id-<chain-id>/bridge/<timestamp>/groth16/metadata.json`
- `deployment/chain-id-<chain-id>/bridge/<timestamp>/groth16/verification_key.json`
- `deployment/chain-id-<chain-id>/bridge/<timestamp>/groth16/zkey_provenance.json` when the selected source provides it

When `BRIDGE_GROTH_SOURCE=mpc`, bridge refresh downloads the latest public Groth16 MPC archive from the Groth16 CRS Drive folder before regenerating the verifier. When `BRIDGE_GROTH_SOURCE=trusted`, bridge refresh generates a local trusted setup in the Groth16 runtime workspace before regenerating the verifier.

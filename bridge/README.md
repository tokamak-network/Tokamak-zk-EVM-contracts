# Bridge Workspace

This folder contains a standalone bridge-contract implementation derived only from:

- `docs/zk-l2-bridge-design-notes.md`
- `docs/spec.md`

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

Tokamak proof verification is no longer mocked. The bridge now calls the real verifier under `tokamak-zkp/`, binds the user-supplied transaction instance to fields extracted from `aPubUser`, and checks the channel-scoped `aPubBlockHash` together with the DApp-managed preprocess-input hash and per-function storage-write metadata. The channel manager no longer stores the full current root vector on-chain; it stores only `currentRootVectorHash`. The full updated root vector is emitted as `CurrentRootVectorObserved` after every proof-backed state transition so off-chain indexers can reconstruct the post-state that produced the new hash. After a successful verification, `executeChannelTransaction` emits `StorageWriteObserved` for every decoded `aPubUser` storage write, and the Groth-backed `deposit` and `withdraw` paths emit the same event format for their `channelTokenVault` writes. Under the latest synthesizer format, those events now expose the storage key rather than the derived tree index. The bridge still derives the `channelTokenVault` leaf index internally from that storage key when it updates the local leaf cache. A Tokamak proof that changes the `channelTokenVault` root without a matching `channelTokenVault` storage write is rejected.

Groth proof verification is also no longer mocked. The bridge expects raw Groth16 proof coordinates and forwards them into the generated `updateTree` verifier under `groth16/verifier/`. Under the current circuit model, each `channelTokenVault` leaf is the raw stored balance value rather than a key-value hash.

## Security-Critical Assumptions

The current bridge implementation hardens a few assumptions that must remain true in production:

- The Groth `channelTokenVault` circuit and the bridge both assume a fixed Merkle-tree depth of `12`. The admin manager rejects other depths.
- Channel creation derives the channel-scoped `aPubBlockHash` from the channel-creation block context on-chain, so Tokamak proof submissions cannot silently skip block-context binding.
- DApp registration requires a nonzero `preprocessInputHash`, and each function also carries fixed `aPubUser` layout metadata derived from the synthesizer `instance_description.json`. All functions in a DApp share one managed storage-address vector, so the root-vector length and the `channelTokenVault` tree index are fixed at channel creation. The bridge stores and later caches the per-function entry-contract, selector, current-root, and updated-root offsets, plus storage-write descriptors that identify the target storage through the DApp-wide managed storage-address index and record the `aPubUser` word offset at which the corresponding storage key appears. Under the current synthesizer format, every storage write still contributes four `aPubUser` words: storage-key lower/upper and storage-write lower/upper.
- The shared `bridgeTokenVault` assumes an exact-transfer ERC-20. Fee-on-transfer or other balance-mutating token behaviors are rejected because they can break custody accounting.

## Deployment

The standalone bridge workspace now includes a Foundry deployment script:

- `bridge/script/DeployBridgeStack.s.sol`
- `bridge/script/UpgradeBridgeStack.s.sol`

On the first proxy-based deployment it creates:

- `BridgeAdminManager` proxy and implementation
- `DAppManager` proxy and implementation
- `Groth16Verifier`
- `TokamakVerifier`
- `BridgeCore` proxy and implementation
- optionally `MockERC20`

After that initial migration, the helper script upgrades the existing proxies in place instead of creating new root-entry addresses. In other words:

- first proxy deployment: root bridge addresses change once, because the legacy non-proxy deployment cannot be converted in place
- later upgrades: `BridgeAdminManager`, `DAppManager`, and `BridgeCore` keep the same proxy addresses while only their implementations are redeployed

Required environment variables:

- `BRIDGE_DEPLOYER_PRIVATE_KEY`
- `BRIDGE_NETWORK`
- `BRIDGE_ALCHEMY_API_KEY` for `sepolia` or `mainnet`

Optional environment variables:

- `BRIDGE_RPC_URL_OVERRIDE`
- `BRIDGE_DEPLOY_MODE` with `upgrade` or `redeploy-proxy`
- `BRIDGE_OWNER`
- `BRIDGE_DEPLOY_MOCK_ASSET`
- `BRIDGE_MOCK_ASSET_NAME`
- `BRIDGE_MOCK_ASSET_SYMBOL`
- `BRIDGE_OUTPUT_PATH`
- `BRIDGE_REFLECTION_MANIFEST_PATH`
- `BRIDGE_SKIP_SUBMODULE_UPDATE=1`
- `BRIDGE_SKIP_TOKAMAK_INSTALL=1`
- `BRIDGE_SKIP_TOKAMAK_VERIFIER_REFRESH=1`
- `BRIDGE_SKIP_GROTH_REFRESH=1`

The repository root now includes `.env.example` for bridge deployment. Copy it to `.env`,
fill in the bridge variables, and use the helper script:

```bash
cp .env.example .env
$EDITOR .env

bash bridge/script/deploy-bridge.sh
```

Or select the deployment mode explicitly:

```bash
bash bridge/script/deploy-bridge.sh --mode upgrade
bash bridge/script/deploy-bridge.sh --mode redeploy-proxy
```

The helper derives the correct Alchemy RPC URL from:

- `BRIDGE_NETWORK=sepolia` -> `https://eth-sepolia.g.alchemy.com/v2/<key>`
- `BRIDGE_NETWORK=mainnet` -> `https://eth-mainnet.g.alchemy.com/v2/<key>`

If you need a non-Alchemy endpoint, set `BRIDGE_RPC_URL_OVERRIDE`.

The helper also resolves the latest published `tokamak-l2js` package and reads
its exported `MT_DEPTH` before broadcasting deployment. Internally it now runs
`script/zk/reflect-submodule-updates.mjs`, which also refreshes the Tokamak
verifier parameters from `setupParams.json` and regenerates the Groth16
`updateTree` artifacts before deployment. The reflected `MT_DEPTH` value is
forwarded into `DeployBridgeStack.s.sol` as `BRIDGE_MERKLE_TREE_LEVELS`.

The current bridge implementation is still intentionally hard-bound to depth
`12` for soundness. If the latest `tokamak-l2js` publishes a different
`MT_DEPTH`, deployment will fail rather than silently deploying a mismatched
bridge configuration.

The helper now has two explicit modes:

- `upgrade`: redeploy implementations only and upgrade the existing proxies in place
- `redeploy-proxy`: redeploy fresh proxies and fresh implementations, replacing the network-scoped deployment artifact

`upgrade` never creates or replaces proxies. If the network-scoped deployment artifact is missing or is not proxy-based,
the command fails and you must run `redeploy-proxy` intentionally.

The script writes one deployment artifact per network under `bridge/deployments/` by default:

- `bridge/deployments/bridge.<chain-id>.json`

It also generates one ABI manifest per network from the current Foundry build artifacts:

- `bridge/deployments/bridge-abi-manifest.<chain-id>.json`

The deployment JSON is post-processed to include `chainId` and `abiManifestPath` so downstream tooling can resolve the correct bridge ABI set without hardcoded function signatures.

## Bridge administration

To add a new DApp metadata bundle to an already deployed bridge, use:

- `bridge/script/admin-add-dapp.mjs`

This script:

- optionally updates `submodules/Tokamak-zk-EVM` to the latest `origin/dev`
- runs `tokamak-cli --install` without passing RPC or Alchemy arguments
- synthesizes and preprocesses the selected example group
- derives function metadata from `instance.json` and `instance_description.json`
- calls `DAppManager.registerDApp(...)` on the deployed bridge

Current constraint:

- DApp deletion is allowed only while `DAppManager.dAppDeletionEnabled()` remains true
- deleting a DApp with one or more active channels is intentionally rejected, because channel managers cache function metadata at channel-creation time
- after the owner calls `disableDAppDeletionForever()`, DApp registration becomes add-only again

Example usage:

```bash
node bridge/script/admin-add-dapp.mjs \
  --group privateStateMint \
  --dapp-id 1
```

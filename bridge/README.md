# Bridge Workspace

This folder contains a standalone bridge-contract implementation derived only from:

- `docs/zk-l2-bridge-design-notes.md`
- `docs/spec.md`

The existing bridge implementation under the repository `src` directory was intentionally not referenced or reused.

## Scope

This workspace focuses on the current design documented in the notes:

- immediate Tokamak-zkp verification
- per-channel L1 token vaults
- bridge-managed DApp metadata
- per-channel `aPubBlockHash` verification context
- globally unique L2 token-vault keys
- per-channel non-collision of derived token-vault leaf indices

## Mocked Areas

The documents do not specify enough operational detail to implement every production path safely. The following areas are therefore still simplified on purpose:

- final proposal-pool and token-economics behavior

Tokamak proof verification is no longer mocked. The bridge now calls the real verifier under `tokamak-zkp/`, binds the user-supplied transaction instance to fields extracted from `aPubUser`, and checks the channel-scoped `aPubBlockHash` together with the DApp-managed preprocess-input hash and per-function storage-write metadata. After a successful verification, `executeChannelTransaction` emits a storage-write event only when a decoded `aPubUser` write targets the channel's L2 token-vault storage. It is also intentionally forbidden from directly overwriting the token-vault root entry in `_currentRootVector`; that root can change only through the same internal vault-update path used by Groth-backed deposit and withdraw flows, and a Tokamak proof that changes the token-vault root without a matching token-vault storage write is rejected.

Groth proof verification is also no longer mocked. The bridge expects raw Groth16 proof coordinates and forwards them into the generated `updateTree` verifier under `groth16/verifier/`. Under the current circuit model, each token-vault leaf is the raw stored balance value rather than a key-value hash.

## Security-Critical Assumptions

The current bridge implementation hardens a few assumptions that must remain true in production:

- The Groth token-vault circuit and the bridge both assume a fixed Merkle-tree depth of `12`. The admin manager rejects other depths.
- Channel creation requires a nonzero `aPubBlockHash`, so Tokamak proof submissions cannot silently skip block-context binding.
- DApp registration requires a nonzero `preprocessInputHash`, and each function also carries fixed `aPubUser` layout metadata derived from the synthesizer `instance_description.json`. The bridge stores and later caches the per-function entry-contract, selector, current-root, and updated-root offsets, plus storage-write descriptors that identify the target storage through the function-local `storageAddrs` index and record the `aPubUser` word offset at which the corresponding tree index appears. Under the current synthesizer format, every storage write still contributes four `aPubUser` words: tree-index lower/upper and storage-write lower/upper.
- The L1 token vault assumes an exact-transfer ERC-20. Fee-on-transfer or other balance-mutating token behaviors are rejected because they can break custody accounting.

## Deployment

The standalone bridge workspace now includes a Foundry deployment script:

- `bridge/script/DeployBridgeStack.s.sol`

It deploys:

- `BridgeAdminManager`
- `DAppManager`
- `Groth16Verifier`
- `TokamakVerifier`
- `BridgeCore`
- optionally `MockERC20`

Required environment variables:

- `BRIDGE_DEPLOYER_PRIVATE_KEY`
- `BRIDGE_NETWORK`
- `BRIDGE_ALCHEMY_API_KEY` for `sepolia` or `mainnet`

Optional environment variables:

- `BRIDGE_RPC_URL_OVERRIDE`
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

The script writes a deployment artifact under `bridge/deployments/` by default.

It also generates an ABI manifest from the current Foundry build artifacts:

- `bridge/deployments/bridge-abi-manifest.latest.json`
- `bridge/deployments/bridge-abi-manifest.<chain-id>.latest.json`

The deployment JSON is post-processed to include `chainId` and `abiManifestPath` so downstream tooling can resolve the correct bridge ABI set without hardcoded function signatures.

## Bridge administration

To add a new DApp metadata bundle to an already deployed bridge, use:

- `bridge/script/admin-add-dapp.mjs`

This script:

- optionally updates `submodules/Tokamak-zk-EVM` to the latest `origin/dev`
- runs `tokamak-cli --install`
- synthesizes and preprocesses the selected example group
- derives function metadata from `instance.json` and `instance_description.json`
- calls `DAppManager.registerDApp(...)` on the deployed bridge

Current constraint:

- existing DApp metadata is add-only
- modifying an already registered DApp is intentionally rejected, because channel managers cache function metadata at channel-creation time

Example usage:

```bash
node bridge/script/admin-add-dapp.mjs \
  --group privateStateMint \
  --dapp-id 1
```

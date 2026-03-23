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

Tokamak proof verification is no longer mocked. The bridge now calls the real verifier under `tokamak-zkp/`, binds the user-supplied transaction instance to fields extracted from `aPubUser`, and checks the channel-scoped `aPubBlockHash` together with the DApp-managed preprocess-input hash.

Groth proof verification is also no longer mocked. The bridge expects raw Groth16 proof coordinates and forwards them into the generated `updateTree` verifier under `groth16/verifier/`. Under the current circuit model, each token-vault leaf is the raw stored balance value rather than a key-value hash.

## Security-Critical Assumptions

The current bridge implementation hardens a few assumptions that must remain true in production:

- The Groth token-vault circuit and the bridge both assume a fixed Merkle-tree depth of `12`. The admin manager rejects other depths.
- Channel creation requires a nonzero `aPubBlockHash`, so Tokamak proof submissions cannot silently skip block-context binding.
- DApp registration requires a nonzero `preprocessInputHash`, so Tokamak proof submissions cannot silently skip preprocess binding.
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
- `BRIDGE_MERKLE_TREE_LEVELS`
- `BRIDGE_DEPLOY_MOCK_ASSET`
- `BRIDGE_MOCK_ASSET_NAME`
- `BRIDGE_MOCK_ASSET_SYMBOL`
- `BRIDGE_OUTPUT_PATH`

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

The script writes a deployment artifact under `bridge/deployments/` by default.

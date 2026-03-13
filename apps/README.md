# Apps Workspace

This directory hosts app-level DApps that follow the repository's zk-L2 assumptions.

## Shared Environment

All app deployments and local app test environments use `apps/.env`.

Shared variables:

- `APPS_DEPLOYER_PRIVATE_KEY`
- `APPS_NETWORK`
- `APPS_ALCHEMY_API_KEY`
- `APPS_ETHERSCAN_API_KEY`

Public-network deployment scripts derive their RPC URLs and chain IDs from `APPS_ALCHEMY_API_KEY` and
`APPS_NETWORK`. For `APPS_NETWORK=anvil`, local scripts default to `http://127.0.0.1:8545`.

`APPS_RPC_URL_OVERRIDE` remains available as an advanced option when a DApp must target a nonstandard local or custom
RPC endpoint.

## Local anvil Convention

Each DApp may provide local anvil helpers under `apps/<dapp>/script/anvil`.

Recommended responsibilities:

- start or stop a local anvil instance
- deploy any mock canonical assets required by the DApp
- bootstrap the DApp contracts onto anvil
- write local deployment manifests and callable ABI files under `apps/<dapp>/deploy`

The private-state DApp follows this convention today and should be used as the reference implementation for future
app local-chain workflows.

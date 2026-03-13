# Apps Workspace

This directory hosts app-level DApps that follow the repository's zk-L2 assumptions.

## Shared Environment

All app deployments and local app test environments use `apps/.env`.

Shared variables:

- `APPS_DEPLOYER_PRIVATE_KEY`
- `APPS_NETWORK`
- `APPS_ALCHEMY_API_KEY`
- `APPS_ETHERSCAN_API_KEY`
- `APPS_RPC_URL_OVERRIDE`

Use `APPS_RPC_URL_OVERRIDE` for local development chains such as anvil. Public-network deployment scripts may derive
their RPC URLs and chain IDs from `APPS_ALCHEMY_API_KEY` and `APPS_NETWORK`, but local anvil flows need an explicit
RPC URL.

## Local anvil Convention

Each DApp may provide local anvil helpers under `apps/<dapp>/script/anvil`.

Recommended responsibilities:

- start or stop a local anvil instance
- deploy any mock canonical assets required by the DApp
- bootstrap the DApp contracts onto anvil
- write local deployment manifests and callable ABI files under `apps/<dapp>/deploy`

The private-state DApp follows this convention today and should be used as the reference implementation for future
app local-chain workflows.

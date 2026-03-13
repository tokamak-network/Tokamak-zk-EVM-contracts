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

## CLI Convention

Each DApp under `apps/` should also provide an operator CLI under `apps/<dapp>/cli`.

Because MetaMask integration requires a browser EIP-1193 provider, this CLI should normally be implemented as a small
static web app rather than as a pure shell command.

Recommended structure:

- `apps/<dapp>/cli/index.html`
- `apps/<dapp>/cli/main.js`
- `apps/<dapp>/cli/style.css`
- `apps/<dapp>/cli/serve.sh`
- `apps/<dapp>/cli/functions/index.json`
- `apps/<dapp>/cli/functions/<function-name>/calldata.json`

The CLI should:

- accept a target network selection
- optionally connect to MetaMask
- resolve deployed contract addresses from `apps/<dapp>/deploy/deployment.<chain-id>.latest.json`
- load callable ABIs from `apps/<dapp>/deploy/*.callable-abi.json`
- read each function template from `cli/functions/<function-name>/calldata.json`
- generate calldata and support `eth_call` or `eth_sendTransaction` as appropriate

## CLI Convention

Each DApp under `apps/` should also provide an operator CLI under `apps/<dapp>/cli`.

Because MetaMask integration requires a browser EIP-1193 provider, this CLI should normally be implemented as a small
static web app rather than as a pure shell command.

Recommended structure:

- `apps/<dapp>/cli/index.html`
- `apps/<dapp>/cli/main.js`
- `apps/<dapp>/cli/style.css`
- `apps/<dapp>/cli/serve.sh`
- `apps/<dapp>/cli/functions/index.json`
- `apps/<dapp>/cli/functions/<function-name>/calldata.json`

The CLI should:

- accept a target network selection
- optionally connect to MetaMask
- resolve deployed contract addresses from `apps/<dapp>/deploy/deployment.<chain-id>.latest.json`
- load callable ABIs from `apps/<dapp>/deploy/*.callable-abi.json`
- read each function template from `cli/functions/<function-name>/calldata.json`
- generate calldata and support `eth_call` or `eth_sendTransaction` as appropriate

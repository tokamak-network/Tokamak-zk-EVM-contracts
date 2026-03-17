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

`APPS_ANVIL_DEPLOYER_PRIVATE_KEY` is an optional local override for anvil workflows. If it is unset, DApp-local
anvil bootstrap scripts should fall back to the default funded anvil account instead of reusing a public-network
deployer key that may have no local balance.

## Local anvil Convention

Each DApp may provide local anvil helpers under `apps/<dapp>/script/anvil`.

Recommended responsibilities:

- start or stop a local anvil instance
- bootstrap the DApp contracts onto anvil
- write local deployment manifests and callable ABI files under `apps/<dapp>/deploy`

The private-state DApp follows this convention today and should be used as the reference implementation for future
app local-chain workflows.

## Shortcut Command Convention

Each DApp should expose concise operator commands inside the DApp folder itself.

Preferred shape:

- `apps/<dapp>/Makefile`

Recommended targets:

- `make anvil-start`
- `make anvil-bootstrap`
- `make anvil-stop`
- `make test`
- `make deploy-sepolia`
- `make deploy-mainnet`
- `make cli-list`

If a deployment target needs a different network than the one stored in `apps/.env`, prefer creating a temporary
app-local env override inside the command wrapper instead of asking the operator to rewrite `apps/.env`.

## CLI Convention

Each DApp under `apps/` should also provide an operator CLI under `apps/<dapp>/cli`.

Recommended structure:

- `apps/<dapp>/cli/<dapp>-cli.mjs`
- `apps/<dapp>/cli/README.md`
- `apps/<dapp>/cli/functions/index.json`
- `apps/<dapp>/cli/functions/<function-name>/calldata.json`

The CLI should:

- accept a target network selection restricted to `mainnet`, `sepolia`, or `anvil`
- optionally accept a wallet private key for signed transactions
- resolve deployed contract addresses from `apps/<dapp>/deploy/deployment.<chain-id>.latest.json`
- load callable ABIs from `apps/<dapp>/deploy/*.callable-abi.json`
- read each function template from `cli/functions/<function-name>/calldata.json`
- generate calldata and support `eth_call` or signed transaction submission as appropriate

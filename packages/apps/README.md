# Apps Workspace

This directory hosts app-level DApps that follow the repository's zk-L2 assumptions.

## Shared Environment

All app deployments and local app test environments use `packages/apps/.env`.

Shared variables:

- `APPS_DEPLOYER_PRIVATE_KEY`
- `APPS_ETHERSCAN_API_KEY`

Public-network deployment scripts require both `--network <sepolia|mainnet>`
and an explicit `--rpc-url <URL>` argument. For `--network anvil`, local scripts
default to `http://127.0.0.1:8545`.

`APPS_RPC_URL_OVERRIDE` remains available only for local anvil helper scripts
that need to target a nonstandard local RPC endpoint.

`APPS_ANVIL_DEPLOYER_PRIVATE_KEY` is an optional local override for anvil workflows. If it is unset, DApp-local
anvil bootstrap scripts should fall back to the default funded anvil account instead of reusing a public-network
deployer key that may have no local balance.

## Local anvil Convention

Each DApp may provide local anvil helpers under `packages/apps/<dapp>/scripts/anvil`.

Recommended responsibilities:

- start or stop a local anvil instance
- bootstrap the DApp contracts onto anvil
- write local deployment manifests and callable ABI files under `packages/apps/<dapp>/deploy`

The private-state DApp follows this convention today and should be used as the reference implementation for future
app local-chain workflows.

## Shortcut Command Convention

Each DApp should expose concise operator commands inside the DApp folder itself.

Preferred shape:

- `packages/apps/<dapp>/Makefile`

Recommended targets:

- `make anvil-start`
- `make anvil-bootstrap`
- `make anvil-stop`
- `make test`
- `make deploy-sepolia`
- `make deploy-mainnet`
- `make cli-bridge-help`

If a deployment target needs a different network than the one stored in `packages/apps/.env`, prefer creating a temporary
app-local env override inside the command wrapper instead of asking the operator to rewrite `packages/apps/.env`.

## CLI Convention

Each DApp under `packages/apps/` should also provide an operator CLI under `packages/apps/<dapp>/cli`.

Recommended structure:

- `packages/apps/<dapp>/cli/<dapp>-cli.mjs`
- `packages/apps/<dapp>/cli/README.md`

The CLI should:

- accept a target network selection restricted to `mainnet`, `sepolia`, or `anvil`
- optionally accept a wallet private key for signed transactions
- resolve deployed contract addresses from `packages/apps/<dapp>/deploy/deployment.<chain-id>.latest.json`
- load callable ABIs from `packages/apps/<dapp>/deploy/*.callable-abi.json`
- expose direct operator commands instead of maintaining a separate function-template layer
- generate calldata and support `eth_call` or signed transaction submission as appropriate

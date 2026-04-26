# Tokamak Private App Channels

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Foundry](https://img.shields.io/badge/Foundry-Enabled-green.svg)](https://getfoundry.sh/)
[![Node.js](https://img.shields.io/badge/Node.js-Required-blue.svg)](https://nodejs.org/)

This repository hosts the current Tokamak Private App Channels worktree.

The active bridge implementation lives under [bridge/](./bridge/). It treats each channel as a dedicated validity-proven execution domain for one registered DApp, while Ethereum remains the canonical layer for custody, proof verification, and settlement. The repository also contains app-level integrations under [apps/](./apps/) and consumes the reusable Tokamak zk-EVM proving stack through published npm packages.

## What Is In This Repository

- [bridge/](./bridge/): the current bridge workspace, including contracts, deployment scripts, tests, and bridge documentation
- [apps/](./apps/): bridge-coupled DApps that follow the repository's zk-L2 assumptions
- [apps/private-state/](./apps/private-state/): the current reference DApp for private note-based channel activity
- [bridge/src/generated/](./bridge/src/generated/): generated verifier sources and verifier-key data used by bridge workflows
- [groth16/](./groth16/): generated Groth16 verifier artifacts used by the bridge token-vault path
- [scripts/](./scripts/): shared repository scripts for artifact handling and current workflow support
- [test/](./test/): root-level Foundry tests and fixtures that remain useful for verifier and legacy coverage

## Where To Start

- Bridge overview: [bridge/README.md](./bridge/README.md)
- Bridge white paper: [bridge/docs/zk-l2-bridge-whitepaper.md](./bridge/docs/zk-l2-bridge-whitepaper.md)
- Bridge spec: [bridge/docs/spec.md](./bridge/docs/spec.md)
- Verifier notes: [bridge/docs/verifier-spec.md](./bridge/docs/verifier-spec.md)
- App workspace guide: [apps/README.md](./apps/README.md)
- Private-state DApp guide: [apps/private-state/README.md](./apps/private-state/README.md)

## Repository Model

At a high level, the repository is organized around three layers:

- Ethereum-facing bridge contracts: the shared settlement and custody surface under [bridge/](./bridge/)
- DApp-specific channel integrations: application contracts, app-local deployment manifests, and user-facing tooling under [apps/](./apps/)
- Shared proving substrate: published Tokamak zk-EVM npm packages and bridge-owned verifier sources under [bridge/src/](./bridge/src/)

The current bridge is not described here as a generic rollup shell. It is a bridge for dedicated app channels with:

- one shared L1 token vault for canonical asset custody
- one `ChannelManager` per channel
- bridge-managed DApp metadata for admissible storage and function surfaces
- Tokamak proof verification for general channel execution
- Groth16 verification for channel-token-vault accounting updates

## Prerequisites

Install the tools used by the current workflows:

- Foundry
- Node.js 18 or newer
- Git submodule support

Typical setup:

```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup

git clone --recurse-submodules https://github.com/tokamak-network/Tokamak-zk-EVM-contracts.git
cd Tokamak-zk-EVM-contracts

npm install
git submodule update --init --recursive
```

Bridge deployment helpers read [`.env.example`](./.env.example). App deployments use [apps/.env.template](./apps/.env.template) as the template for [apps/.env](./apps/.env).

## Common Commands

### Bridge unit tests

```bash
npm run test:bridge:unit
```

This runs the Foundry suite under [bridge/test/](./bridge/test/), including [bridge/test/BridgeFlow.t.sol](./bridge/test/BridgeFlow.t.sol).

### Private-state CLI end-to-end flow

```bash
npm run test:private-state:cli-e2e
```

This exercises the bridge-coupled private-state CLI flow driven by [apps/private-state/scripts/e2e/run-bridge-private-state-cli-e2e.mjs](./apps/private-state/scripts/e2e/run-bridge-private-state-cli-e2e.mjs).

### Private-state local workflow

```bash
cd apps/private-state
make help
make anvil-start
make anvil-bootstrap
make test
make e2e-bridge
make e2e-bridge-cli
```

### Bridge deployment

```bash
cp .env.example .env
$EDITOR .env

bash bridge/scripts/deploy-bridge.sh
```

For an already deployed bridge stack, deploy-and-register the private-state DApp with:

```bash
node bridge/scripts/deploy-and-add-dapp.mjs --group mintNotes --dapp-id 1
```

If the app is already deployed and only registration is needed, use:

```bash
node bridge/scripts/admin-add-dapp.mjs --group mintNotes --dapp-id 1
```

Bridge deployment owns the canonical mirrored Groth16 artifacts under
`bridge/deployments/groth16/<chain-id>/`, and DApp registration mirrors the
prover/CLI-consumed subset into `apps/private-state/deploy/groth16/<chain-id>/`.

See [bridge/README.md](./bridge/README.md) for deployment modes, environment variables, and bridge registration details.

## Current Directory Guide

### [bridge/](./bridge/)

The standalone bridge workspace contains:

- current bridge contracts under [bridge/src/](./bridge/src/)
- bridge-specific tests under [bridge/test/](./bridge/test/)
- deployment and admin scripts under [bridge/scripts/](./bridge/scripts/)
- current bridge documents under [bridge/docs/](./bridge/docs/)

This is the main place to look for the current bridge implementation.

### [apps/private-state/](./apps/private-state/)

The private-state DApp is the reference app integration for the bridge. It contains:

- DApp contracts under [apps/private-state/src/](./apps/private-state/src/)
- bridge-coupled CLI tooling under [apps/private-state/cli/](./apps/private-state/cli/)
- app deployment artifacts under [apps/private-state/deploy/](./apps/private-state/deploy/)
- protocol and security documents under [apps/private-state/docs/](./apps/private-state/docs/)

### Tokamak Verifier Artifacts

Tokamak verifier Solidity sources are owned by the bridge under
[bridge/src/verifiers/](./bridge/src/verifiers/) and [bridge/src/generated/](./bridge/src/generated/).
Bridge tests keep Tokamak proof fixtures under [bridge/test/fixtures/](./bridge/test/fixtures/).

### Bridge ZK Workflow

Bridge deployment and DApp registration consume `@tokamak-zk-evm/cli`,
`@tokamak-zk-evm/subcircuit-library`, `@tokamak-zk-evm/synthesizer-node`, `tokamak-l2js`, and
the repository Groth16 package from npm-linked packages. Current implementation details live in
[bridge/docs/current-implementation.md](./bridge/docs/current-implementation.md).

## Notes On Scope

Some root-level scripts and tests remain from earlier bridge iterations. They are still useful for verifier coverage, artifact generation, and historical deployment context, but they are not the primary place to understand the current bridge architecture. For current bridge behavior, start with [bridge/](./bridge/).

## License

Repository source files use MIT SPDX identifiers.

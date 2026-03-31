# Tokamak Private App Channels

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Foundry](https://img.shields.io/badge/Foundry-Enabled-green.svg)](https://getfoundry.sh/)
[![Node.js](https://img.shields.io/badge/Node.js-Required-blue.svg)](https://nodejs.org/)

This repository hosts the current Tokamak Private App Channels worktree.

The active bridge implementation lives under [bridge/](./bridge/). It treats each channel as a dedicated validity-proven execution domain for one registered DApp, while Ethereum remains the canonical layer for custody, proof verification, and settlement. The repository also contains app-level integrations under [apps/](./apps/) and the reusable Tokamak zk-EVM proving stack under [submodules/Tokamak-zk-EVM](./submodules/Tokamak-zk-EVM).

## What Is In This Repository

- [bridge/](./bridge/): the current bridge workspace, including contracts, deployment scripts, tests, and bridge documentation
- [apps/](./apps/): bridge-coupled DApps that follow the repository's zk-L2 assumptions
- [apps/private-state/](./apps/private-state/): the current reference DApp for private note-based channel activity
- [tokamak-zkp/](./tokamak-zkp/): the Tokamak verifier contract and verification-key artifacts used by bridge workflows
- [submodules/Tokamak-zk-EVM](./submodules/Tokamak-zk-EVM): the shared zk-EVM execution and proving toolchain
- [groth16/](./groth16/): generated Groth16 verifier artifacts used by the bridge token-vault path
- [script/](./script/): shared repository scripts, including zk-artifact reflection helpers and older deployment utilities
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
- Shared proving substrate: the Tokamak zk-EVM toolchain and reflected verifier artifacts under [submodules/](./submodules/) and [tokamak-zkp/](./tokamak-zkp/)

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

This exercises the bridge-coupled private-state CLI flow driven by [apps/private-state/script/e2e/run-bridge-private-state-cli-e2e.mjs](./apps/private-state/script/e2e/run-bridge-private-state-cli-e2e.mjs).

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

bash bridge/script/deploy-bridge.sh
```

For an already deployed bridge stack, DApp metadata registration is handled by:

```bash
node bridge/script/admin-add-dapp.mjs --group mintNotes --dapp-id 1
```

See [bridge/README.md](./bridge/README.md) for deployment modes, environment variables, and bridge registration details.

## Current Directory Guide

### [bridge/](./bridge/)

The standalone bridge workspace contains:

- current bridge contracts under [bridge/src/](./bridge/src/)
- bridge-specific tests under [bridge/test/](./bridge/test/)
- deployment and admin scripts under [bridge/script/](./bridge/script/)
- current bridge documents under [bridge/docs/](./bridge/docs/)

This is the main place to look for the current bridge implementation.

### [apps/private-state/](./apps/private-state/)

The private-state DApp is the reference app integration for the bridge. It contains:

- DApp contracts under [apps/private-state/src/](./apps/private-state/src/)
- bridge-coupled CLI tooling under [apps/private-state/cli/](./apps/private-state/cli/)
- app deployment artifacts under [apps/private-state/deploy/](./apps/private-state/deploy/)
- protocol and security documents under [apps/private-state/docs/](./apps/private-state/docs/)

### [submodules/Tokamak-zk-EVM](./submodules/Tokamak-zk-EVM)

This submodule provides the reusable zk-EVM execution and proving pipeline that bridge-coupled DApps build on. The repository-level reflection helper in [script/zk/](./script/zk/) keeps bridge-facing verifier and deployment artifacts aligned with the submodule outputs.

### [tokamak-zkp/](./tokamak-zkp/)

This folder contains the checked-in Tokamak verifier contract and verification-key artifacts that the bridge workspace imports during proof verification.

## Notes On Scope

Some root-level scripts and tests remain from earlier bridge iterations. They are still useful for verifier coverage, artifact generation, and historical deployment context, but they are not the primary place to understand the current bridge architecture. For current bridge behavior, start with [bridge/](./bridge/).

## License

Repository source files use MIT SPDX identifiers.

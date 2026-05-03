# Tokamak Private App Channels

[![License: MIT OR Apache-2.0](https://img.shields.io/badge/License-MIT%20OR%20Apache--2.0-blue.svg)](./LICENSE)
[![Foundry](https://img.shields.io/badge/Foundry-Enabled-green.svg)](https://getfoundry.sh/)
[![Node.js](https://img.shields.io/badge/Node.js-Required-blue.svg)](https://nodejs.org/)

This repository hosts the current Tokamak Private App Channels worktree.

The active bridge implementation lives under [bridge/](./bridge/). It treats each channel as a dedicated validity-proven execution domain for one registered DApp, while Ethereum remains the canonical layer for custody, proof verification, and settlement. The repository also contains app-level integrations under [packages/apps/](./packages/apps/) and consumes the reusable Tokamak zk-EVM proving stack through published npm packages.

## Quick Answers

### What are Tokamak Private App Channels?

Tokamak Private App Channels are Ethereum-settled, validity-proven execution domains for bridge-coupled DApps. Each
channel is created for one registered DApp, keeps its own channel state commitment, and advances only when Ethereum
accepts the required proof-backed transition.

### What does the bridge verify on-chain?

The bridge verifies Tokamak proofs for general channel execution and Groth16 proofs for channel-token-vault accounting
updates. It also checks DApp metadata, function metadata commitments, verifier compatibility snapshots, and channel
state commitments before accepting a transition.

### What is the private-state DApp?

The private-state DApp is the current reference DApp in this repository. It lets users move canonical Tokamak Network
Token value into channel-local accounting, mint private notes, transfer notes, redeem notes, and withdraw liquid
channel balance back through the bridge.

### What remains trusted or operationally assumed?

The current model assumes sound Tokamak and Groth16 verifiers, correct DApp metadata, an honest bridge owner for
upgradeable root contracts, exact-transfer behavior of the canonical token, and user review of immutable channel policy
before channel creation or joining.

## What Is In This Repository

- [bridge/](./bridge/): the current bridge workspace, including contracts, deployment scripts, tests, and bridge documentation
- [packages/apps/](./packages/apps/): bridge-coupled DApps that follow the repository's zk-L2 assumptions
- [packages/apps/private-state/](./packages/apps/private-state/): the current reference DApp for private note-based channel activity
- [bridge/src/generated/](./bridge/src/generated/): generated verifier sources and verifier-key data used by bridge workflows
- [packages/groth16/](./packages/groth16/): generated Groth16 verifier artifacts used by the bridge token-vault path
- [scripts/](./scripts/): shared repository scripts for artifact handling and current workflow support
- [test/](./test/): root-level Foundry tests and fixtures that remain useful for verifier and legacy coverage

## Where To Start

- Bridge overview: [bridge/README.md](./bridge/README.md)
- Bridge white paper: [bridge/docs/zk-l2-bridge-whitepaper.md](./bridge/docs/zk-l2-bridge-whitepaper.md)
- Bridge spec: [bridge/docs/spec.md](./bridge/docs/spec.md)
- Verifier notes: [bridge/docs/verifier-spec.md](./bridge/docs/verifier-spec.md)
- App workspace guide: [packages/apps/README.md](./packages/apps/README.md)
- Private-state DApp guide: [packages/apps/private-state/README.md](./packages/apps/private-state/README.md)
- AI/search summary: [llms.txt](./llms.txt)
- Release process: [RELEASING.md](./RELEASING.md)
- Changelog: [CHANGELOG.md](./CHANGELOG.md)

## Deployment And Registration Artifacts

Bridge deployment artifacts and DApp registration artifacts are published to Google Drive:

https://drive.google.com/drive/folders/12HuHeR8vCWfkeGdjTAFKhv0FU-AG4aUJ

GitHub is not the artifact store for deployment or DApp registration results. This repository
keeps the source code, deployment scripts, and artifact upload tooling; generated deployment
metadata, registration manifests, ABI snapshots, CRS snapshots, and source snapshots should be
looked up through the Google Drive artifact index and uploaded folders.

## Repository Model

At a high level, the repository is organized around three layers:

- Ethereum-facing bridge contracts: the shared settlement and custody surface under [bridge/](./bridge/)
- DApp-specific channel integrations: application contracts, app-local deployment manifests, and user-facing tooling under [packages/apps/](./packages/apps/)
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

Bridge deployment helpers read [`.env.example`](./.env.example). App deployments use [packages/apps/.env.template](./packages/apps/.env.template) as the template for [packages/apps/.env](./packages/apps/.env).

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

This exercises the bridge-coupled private-state CLI flow driven by [packages/apps/private-state/scripts/e2e/run-bridge-private-state-cli-e2e.mjs](./packages/apps/private-state/scripts/e2e/run-bridge-private-state-cli-e2e.mjs).

### Private-state local workflow

```bash
cd packages/apps/private-state
make help
make anvil-start
make anvil-bootstrap
make test
make e2e-bridge-cli
```

### Bridge deployment

```bash
cp .env.example .env
$EDITOR .env

node bridge/scripts/deploy-bridge.mjs
```

For an already deployed bridge stack, deploy-and-register the private-state DApp with:

```bash
node bridge/scripts/deploy-and-add-dapp.mjs \
  --group mintNotes \
  --group transferNotes \
  --group redeemNotes \
  --dapp-id 1
```

If the app is already deployed and only registration is needed, use:

```bash
node bridge/scripts/admin-add-dapp.mjs \
  --group mintNotes \
  --group transferNotes \
  --group redeemNotes \
  --dapp-id 1
```

Bridge deployment publishes the chain-scoped Groth16 deployment snapshot to the Google Drive
artifact store. The npm CLI installs the proof-consuming subset into
`~/tokamak-private-channels/dapps/private-state/chain-id-<chainId>/` and uses the fixed Groth16
runtime workspace under `~/tokamak-private-channels/groth16/` for proof generation.

See [bridge/README.md](./bridge/README.md) for deployment modes, environment variables, and bridge registration details.

## Current Directory Guide

### [bridge/](./bridge/)

The standalone bridge workspace contains:

- current bridge contracts under [bridge/src/](./bridge/src/)
- bridge-specific tests under [bridge/test/](./bridge/test/)
- deployment and admin scripts under [bridge/scripts/](./bridge/scripts/)
- current bridge documents under [bridge/docs/](./bridge/docs/)

This is the main place to look for the current bridge implementation.

### [packages/apps/private-state/](./packages/apps/private-state/)

The private-state DApp is the reference app integration for the bridge. It contains:

- DApp contracts under [packages/apps/private-state/src/](./packages/apps/private-state/src/)
- bridge-coupled CLI tooling under [packages/apps/private-state/cli/](./packages/apps/private-state/cli/)
- app deployment and registration scripts that publish artifacts to Google Drive
- protocol and security documents under [packages/apps/private-state/docs/](./packages/apps/private-state/docs/)

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

Repository source files are licensed under either MIT or Apache-2.0, at your option.
See [LICENSE](./LICENSE), [LICENSE-MIT](./LICENSE-MIT), and
[LICENSE-APACHE](./LICENSE-APACHE).

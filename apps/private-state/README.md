# Private State zk-note DApp

This application implements the lifecycle of a zk-note style payment system for the Tokamak Network Token entirely with smart contracts and without zero-knowledge circuits.

## Scope

The target deployment model is a proving-based L2 where raw transaction calldata is not exposed to L1 observers or other L2 users. Canonical asset custody remains on L1. The L2 DApp keeps accounting balances only and assumes a bridge verifier on L1 accepts state-root transitions backed by proofs. What remains from the zk-note model is the state machine:

- L1 bridge custody is the source of truth for the Tokamak Network Token.
- Bridge-coupled accounting deposits increase an L2 accounting balance.
- Accounting balances can be converted into spendable notes.
- Spending a note proves ownership at the contract layer, marks the old note as spent, derives a nullifier, and creates replacement output notes.
- Notes can be redeemed back into liquid accounting balances inside the L2 accounting vault.
- Bridge-coupled accounting withdrawals decrease the L2 accounting balance.

## Contract Layout

- `L2AccountingVault.sol`: Stores per-account L2 accounting balances only. It does not custody real tokens.
- `PrivateStateController.sol`: User-facing entrypoint that reconstructs commitments and nullifiers from transaction calldata, stores note commitment existence, stores nullifier usage, and applies bridge-coupled accounting transitions.

## Ownership Proof Without Circuits

Real Zcash or zkDai systems prove note ownership inside a circuit by showing knowledge of secret note material. This implementation replaces that proof with contract-side verification:

- The spender submits the full note plaintext in calldata.
- The controller recomputes the note commitment from that plaintext and checks that the commitment exists on-chain.
- The plaintext includes a visible `owner` address.
- The note owner must spend directly by calling the controller.
This preserves spend authorization semantics. Privacy assumptions depend on the surrounding L2 transaction visibility model rather than on the contracts themselves.

## Owner Roles

This DApp now has only one ownership concept at the contract layer:

- `note owner`: the address embedded in a note plaintext that is allowed to spend that note

There is no storage-contract `owner` role anymore. `L2AccountingVault` and the controller wiring are fixed at deployment time and do not expose an administrative rebinding path.

As a result:

- note spending authority still belongs to the note owner through controller entrypoints
- controller-owned note state does not expose an administrative rebinding path
- accounting-vault trust is fixed at deployment time rather than managed post-deployment

This removes an administrative attack surface, but it also means a controller deployment mistake or controller bug
cannot be repaired through an owner action.

## Nullifier Model

The controller computes a deterministic nullifier from the submitted note plaintext and stores both note commitment existence and nullifier usage internally.

- `value`
- `owner`
- `salt`

Once a note is consumed, the controller records the nullifier and rejects any later attempt to reuse it.

The design intentionally avoids storing note plaintext or duplicate spent flags on-chain. The controller is the only spend-state authority for note/nullifier state.

## End-to-End Flow

1. Fund the sender's L2 liquid balance through the bridge-controlled accounting path before minting or transferring notes.
2. Call `mintNotes1`, `mintNotes2`, `mintNotes3`, `mintNotes4`, `mintNotes5`, or `mintNotes6` to lock part of the liquid balance into one, two, three, four, five, or six note commitments.
3. Call one of the fixed-arity `transferNotes<N>To<M>` entrypoints with `N` input notes and `M` output notes.
4. Call one of `redeemNotes1`, `redeemNotes2`, `redeemNotes3`, or `redeemNotes4` to convert fixed batches of notes back into liquid balances.

## Fixed-Arity Entry Points

The current mint API exposes six fixed-arity user-facing functions:

- `mintNotes1`: 1 output note
- `mintNotes2`: 2 output notes
- `mintNotes3`: 3 output notes
- `mintNotes4`: 4 output notes
- `mintNotes5`: 5 output notes
- `mintNotes6`: 6 output notes

The current transfer API exposes the following fixed-arity family:

- `transferNotes1To1`, `transferNotes1To2`, `transferNotes1To3`
- `transferNotes2To1`, `transferNotes2To2`
- `transferNotes3To1`, `transferNotes3To2`
- `transferNotes4To1`

The current redeem API exposes four fixed-arity user-facing functions:

- `redeemNotes1`: 1 input note
- `redeemNotes2`: 2 input notes
- `redeemNotes3`: 3 input notes
- `redeemNotes4`: 4 input notes

These fixed entrypoints are intended to make the final user-facing state transitions more circuit-friendly under the repository's zk-L2 design constraints.

## Deployment Inputs

Sepolia deployment requires three concrete inputs:

- the deployer private key
- the target network name
- the Alchemy API key used to derive the Sepolia RPC URL

The repository now includes:

- `apps/private-state/Makefile`
- `apps/private-state/script/deploy/DeployPrivateState.s.sol`
- `apps/private-state/script/deploy/deploy-private-state.sh`
- `apps/private-state/script/deploy/write-deploy-artifacts.sh`
- `apps/.env.template`

The deploy script uses a deployment factory and deterministic address prediction:

1. predict the future controller address
2. predict the three storage contract addresses from CREATE2 salts and the predicted controller address
3. deploy the controller first using the predicted storage addresses
4. deploy the three storage contracts with the predicted controller address embedded in their constructor

There is no `bindController()` step and no storage-contract owner. The controller relationship is fixed at deployment time.

private-state deployment parameters must be stored in `apps/.env`, not in the repository-root bridge deployment `.env`.

The private-state deploy flow uses shared app deployment variables for the signer and target network:

- `APPS_DEPLOYER_PRIVATE_KEY`
- `APPS_NETWORK`
- `APPS_ALCHEMY_API_KEY`
- `APPS_ETHERSCAN_API_KEY` when block explorer verification is needed

For `APPS_NETWORK=anvil`, the deploy scripts default to `http://127.0.0.1:8545`. `APPS_RPC_URL_OVERRIDE` is only an
advanced option for nonstandard local or custom RPC endpoints.

There is no `PRIVATE_STATE_OWNER` parameter.

Every successful deployment also writes DApp-local JSON artifacts into `apps/private-state/deploy`:

- `deployment.<chain-id>.<timestamp>.json`: the deployed addresses and deployment metadata for that run
- `deployment.<chain-id>.latest.json`: the latest deployment manifest for that chain
- `storage-layout.<chain-id>.<timestamp>.json`: the deployed-contract storage layouts for that run
- `storage-layout.<chain-id>.latest.json`: the latest deployed-contract storage-layout manifest for that chain
- `PrivateStateController.callable-abi.json`
- `L2AccountingVault.callable-abi.json`

The ABI files intentionally contain only the user-facing or tester-facing callable functions for each contract rather
than the full contract ABI.

The storage-layout manifest is the canonical app-local source for contract slot metadata. Example and replay generators
must read this file and derive any statically known `preAllocatedKeys` from the actual deployed storage layout rather
than hardcoding default keys.

## Shortcut Commands

The DApp folder exposes concise local commands through `apps/private-state/Makefile`.

Examples:

```bash
cd apps/private-state
make help
make anvil-start
make anvil-bootstrap
make test
make deploy-sepolia
make deploy-mainnet
make cli-list
```

The deployment shortcuts do not require editing `apps/.env` just to switch networks. They create a temporary env file,
override `APPS_NETWORK` for the requested target, and then call the existing deployment script.

## CLI

private-state now exposes the bridge-coupled operator CLI under
`apps/private-state/cli/private-state-bridge-cli.mjs`.

The CLI:

- selects a target network through `--network` or `apps/.env`, restricted to `mainnet`, `sepolia`, or `anvil`
- loads bridge deployment data and the bridge ABI manifest generated at bridge deployment time
- reads default function templates from `apps/private-state/cli/functions/<function-name>/calldata.json`
- manages per-channel workspaces and the latest `state_snapshot.json`
- generates Groth and Tokamak proofs
- submits bridge transactions for `deposit`, `withdraw`, `claim`, and DApp function execution

Examples:

```bash
cd apps/private-state
make cli-list
node apps/private-state/cli/private-state-bridge-cli.mjs list-functions
node apps/private-state/cli/private-state-bridge-cli.mjs show-template mintNotes1
node apps/private-state/cli/private-state-bridge-cli.mjs workspace-init --workspace demo --network anvil --channel-name demo-channel --bridge-deployment bridge/deployments/bridge-latest.json
node apps/private-state/cli/private-state-bridge-cli.mjs bridge-send mintNotes1 --workspace demo --network anvil --private-key <hex> --l2-key-signature "participant-a"
```

The function-folder rule is based on function names. Because several contracts expose duplicate low-signal getters such
as `controller()`, those duplicates are intentionally omitted from the CLI function-folder set to avoid path
collisions.

## Local anvil Workflow

For fast local iteration, private-state now includes an anvil bootstrap flow:

- `apps/private-state/Makefile`
- `apps/private-state/script/anvil/start-anvil.sh`
- `apps/private-state/script/anvil/bootstrap-private-state-anvil.sh`
- `apps/private-state/script/anvil/stop-anvil.sh`
- `apps/private-state/script/anvil/write-anvil-artifacts.sh`

Recommended `apps/.env` values for anvil:

- `APPS_NETWORK=anvil`
- `APPS_ANVIL_DEPLOYER_PRIVATE_KEY=<optional custom anvil account private key>`

If `APPS_ANVIL_DEPLOYER_PRIVATE_KEY` is unset, `make anvil-bootstrap` falls back to the default funded anvil account.
This prevents local bootstrap from accidentally reusing a Sepolia or mainnet deployer key that has no balance on the
local chain.

The bootstrap flow:

1. starts from a reachable anvil RPC
2. deploys private-state
3. writes local manifests and callable ABI files into `apps/private-state/deploy`

The shortest local workflow is:

```bash
cd apps/private-state
make anvil-start
make anvil-bootstrap
make test
make anvil-stop
```

The anvil bootstrap also writes:

- `anvil-bootstrap.latest.json`

These local anvil artifacts are ignored by git because they are expected to change frequently.

## Security Tradeoffs

Because note validity is still checked directly in contract code:

- The system still relies on cross-contract invariants between the controller and the accounting vault.
- The mock bridge entrypoints model proof-backed L1 bridge settlement during development rather than standalone L2 token custody.
- Privacy depends on the surrounding L2 execution model, not solely on these contracts.
- The user-facing controller no longer exposes direct liquid-balance mutation entrypoints. Balance setup is expected to come from a bridge-controlled accounting path or test-only controller-authorized setup.

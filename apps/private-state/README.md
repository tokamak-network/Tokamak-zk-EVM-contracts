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
- `PrivateNoteRegistry.sol`: Stores note commitments only.
- `PrivateNullifierRegistry.sol`: Stores nullifier usage and is the single source of truth for spent status.
- `PrivateStateController.sol`: User-facing entrypoint that reconstructs commitments and nullifiers from transaction calldata and applies bridge-coupled accounting transitions.

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

There is no storage-contract `owner` role anymore. `L2AccountingVault`, `PrivateNoteRegistry`, and
`PrivateNullifierRegistry` each receive the controller address in their constructor and keep it as an immutable value.

As a result:

- note spending authority still belongs to the note owner through controller entrypoints
- storage contracts do not expose an administrative rebinding path
- controller trust is fixed at deployment time rather than managed post-deployment

This removes an administrative attack surface, but it also means a controller deployment mistake or controller bug
cannot be repaired through an owner action.

## Nullifier Model

The controller computes a deterministic nullifier from the submitted note plaintext and the nullifier store domain. The canonical Tokamak Network Token asset identifier is fixed at deployment time and remains part of the derived hashes even though callers do not pass it explicitly. The note store itself only keeps commitment existence.

- `value`
- `owner`
- `salt`

Once a note is consumed, the nullifier store records the nullifier and rejects any later attempt to reuse it.

The design intentionally avoids storing note plaintext or duplicate spent flags on-chain. The nullifier store is the only spend-state authority.

## End-to-End Flow

1. Lock or release the canonical asset through the L1 bridge custody flow.
2. Apply the matching L2 accounting transition with `bridgeDeposit` or `bridgeWithdraw`.
3. Call `mintNotes1`, `mintNotes2`, or `mintNotes3` to lock part of the liquid balance into one, two, or three note commitments.
4. Call one of `transferNotes4`, `transferNotes6`, or `transferNotes8` with exactly 3 output notes.
5. Call one of `redeemNotes4`, `redeemNotes6`, or `redeemNotes8` to convert fixed batches of notes back into liquid balances.

## Fixed-Arity Entry Points

The current bridge-coupled accounting API exposes two fixed-purpose user-facing functions:

- `bridgeDeposit`: increase the caller's L2 accounting balance after the matching L1 bridge deposit proof
- `bridgeWithdraw`: decrease the caller's L2 accounting balance before the matching L1 bridge withdrawal settlement

The current mint API exposes three fixed-arity user-facing functions:

- `mintNotes1`: 1 output note
- `mintNotes2`: 2 output notes
- `mintNotes3`: 3 output notes

The current transfer API exposes three fixed-arity user-facing functions:

- `transferNotes4`: 4 input notes, 3 output notes
- `transferNotes6`: 6 input notes, 3 output notes
- `transferNotes8`: 8 input notes, 3 output notes

The current redeem API exposes three fixed-arity user-facing functions:

- `redeemNotes4`: 4 input notes
- `redeemNotes6`: 6 input notes
- `redeemNotes8`: 8 input notes

These fixed entrypoints are intended to make the final user-facing state transitions more circuit-friendly under the repository's zk-L2 design constraints.

## Deployment Inputs

Sepolia deployment requires four concrete inputs:

- the deployer private key
- the target network name
- the Alchemy API key used to derive the Sepolia RPC URL
- the canonical TON asset address used as `canonicalAsset`

The repository now includes:

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
- `APPS_RPC_URL_OVERRIDE` for local development chains such as anvil
- `APPS_ETHERSCAN_API_KEY` when block explorer verification is needed

It uses a namespaced variable only for the private-state-specific value:

- `PRIVATE_STATE_CANONICAL_ASSET`
- `PRIVATE_STATE_TESTING_BALANCE_SETTER`

There is no `PRIVATE_STATE_OWNER` parameter.

When `PRIVATE_STATE_TESTING_BALANCE_SETTER` is the zero address, the L2 accounting vault disables the test-only
balance override function. If a non-zero address is configured, that address may call the vault test hook to set an
account balance to an arbitrary value. This is useful for public test deployments and unsafe for production custody.

Every successful deployment also writes DApp-local JSON artifacts into `apps/private-state/deploy`:

- `deployment.<chain-id>.<timestamp>.json`: the deployed addresses and deployment metadata for that run
- `deployment.<chain-id>.latest.json`: the latest deployment manifest for that chain
- `PrivateStateController.callable-abi.json`
- `L2AccountingVault.callable-abi.json`
- `PrivateNoteRegistry.callable-abi.json`
- `PrivateNullifierRegistry.callable-abi.json`

The ABI files intentionally contain only the user-facing or tester-facing callable functions for each contract rather
than the full contract ABI.

## Local anvil Workflow

For fast local iteration, private-state now includes an anvil bootstrap flow:

- `apps/private-state/script/anvil/start-anvil.sh`
- `apps/private-state/script/anvil/bootstrap-private-state-anvil.sh`
- `apps/private-state/script/anvil/stop-anvil.sh`
- `apps/private-state/script/anvil/DeployMockTokamakNetworkToken.s.sol`
- `apps/private-state/script/anvil/write-anvil-artifacts.sh`

Recommended `apps/.env` values for anvil:

- `APPS_NETWORK=anvil`
- `APPS_RPC_URL_OVERRIDE=http://127.0.0.1:8545`
- `APPS_DEPLOYER_PRIVATE_KEY=<anvil account private key>`
- `PRIVATE_STATE_TESTING_BALANCE_SETTER=<tester address or zero address>`

The bootstrap flow:

1. starts from a reachable anvil RPC
2. deploys `MockTokamakNetworkToken`
3. uses that mock token as `PRIVATE_STATE_CANONICAL_ASSET`
4. deploys private-state
5. writes local manifests and callable ABI files into `apps/private-state/deploy`

The anvil bootstrap also writes:

- `anvil-bootstrap.latest.json`
- `MockTokamakNetworkToken.callable-abi.json`

These local anvil artifacts are ignored by git because they are expected to change frequently.

## Security Tradeoffs

Because note validity is still checked directly in contract code:

- The system still relies on cross-contract invariants between the controller, accounting vault, note registry, and nullifier registry.
- The bridge-coupled accounting entrypoints model proof-backed L1 bridge settlement rather than standalone L2 token custody.
- Privacy depends on the surrounding L2 execution model, not solely on these contracts.
- The current `bridgeDeposit` and `bridgeWithdraw` functions remain direct user entrypoints. As a result, the deployed contract set does not by itself enforce the stricter architecture where only L1 bridge proof settlement may mutate L2 accounting balances.

# CLI to DApp Protocol

## 1. CLI Role

The private-state CLI is not a thin transaction sender. It is an off-chain protocol participant that:

- derives channel-specific identities
- manages encrypted wallet state
- reconstructs snapshots
- assembles Tokamak proof inputs
- generates proofs locally
- submits bridge-coupled transactions

## 2. Command Families

The normal command flow is:

1. `create-channel`
2. `join-channel`
3. `deposit-bridge`
4. `deposit-channel`
5. `mint-notes`
6. `transfer-notes`
7. `get-my-notes`
8. `redeem-notes`
9. `withdraw-channel`
10. `withdraw-bridge`

The CLI assistant simply builds these command lines; it does not execute them directly.

## 3. Workspace and Wallet Artifacts

The CLI stores local state in two layers:

- channel workspace
- per-user encrypted wallet

The channel workspace contains:

- current state snapshot
- block info
- managed contract codes
- deployment/storage-layout manifest paths
- channel metadata

The wallet contains:

- encrypted L1 and L2 key material
- note-receive registration metadata
- tracked notes
- last scanned encrypted-note event block
- wallet-local operation history

## 4. Proof Input Bundle Shape

Before proof generation, the CLI materializes a transaction bundle containing:

- `previous_state_snapshot.json`
- `transaction.json` or transaction RLP input
- `block_info.json`
- `contract_codes.json`

These inputs must match the registered function metadata for the active DApp and channel.

## 5. Snapshot Rules

For private-state, the snapshot must contain the full managed storage vector:

- controller storage
- L2 accounting vault storage

The CLI reconstructs this from real channel state rather than from a synthetic example.

## 6. Mint Output Construction

For `mint-notes`, the CLI:

1. parses the amount vector
2. chooses `mintNotesN` from the vector length
3. derives encrypted self-mint outputs for the wallet owner
4. encrypts those outputs to the wallet's note-receive public key
5. sends the fixed-arity calldata to the DApp controller through the bridge execution path

The contract then derives note salts from the encrypted payloads.

## 7. Transfer Output Construction

For `transfer-notes`, the CLI:

1. resolves recipient note-receive public keys from channel registration by recipient L2 address
2. encrypts each output value to the recipient's registered note-receive key
3. builds fixed-arity `TransferOutput` calldata
4. submits the proof-backed bridge transaction

The sender does not send plaintext note payloads to the recipient through sidecar inbox files anymore.

## 8. Redeem Construction

For `redeem-notes`, the CLI:

1. chooses the fixed redeem arity from the selected note count
2. reconstructs plaintext notes from wallet state
3. submits the matching `redeemNotesN` call

Redemption converts notes back into liquid accounting balance rather than directly into L1 custody.

## 9. Event Recovery Protocol

The CLI scans bridge-propagated Ethereum logs for encrypted note events.

Recovery flow:

1. fetch `NoteValueEncrypted` logs that belong to the channel execution stream
2. inspect the ciphertext scheme marker
3. decrypt with the note-receive private key
4. reconstruct note plaintext as:
   - owner = wallet L2 address
   - value = decrypted value
   - salt = hash(encrypted payload)
5. recompute commitment and nullifier
6. confirm current bridge/controller state before classifying the note as `unused` or `spent`

## 10. CLI Security-Critical Inputs

The CLI relies on:

- wallet password
- channel name
- L1 private key
- bridge deployment manifests
- app deployment and storage-layout manifests
- bridge ABI manifest

If any of these are stale or mismatched, valid proofs can still be rejected because the bridge metadata model is strict.

## 11. Registered vs Supported Shapes

The CLI may know how to build more Solidity entrypoints than the currently registered DApp allows on a network.

The effective support set is the intersection of:

- Solidity support
- bridge DApp registration support
- available proof-generation capacity
- CLI-exposed UX support

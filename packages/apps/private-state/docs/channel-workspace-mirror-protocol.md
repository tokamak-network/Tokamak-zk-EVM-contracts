# Channel Workspace Mirror Protocol

Channel workspace mirrors are optional bootstrap caches operated by channel leaders. They reduce the
cost of joining or recovering an old channel by serving a leader-signed checkpoint and, when the user
already has a local workspace, only the delta from the local recovery index to that checkpoint. The
mirror is not a source of consensus. The CLI still validates mirror data against on-chain channel
metadata and uses RPC replay from the mirror checkpoint to the latest block when the checkpoint is
not already current.

## On-Chain Registry

`BridgeCore` stores one mirror base URL per channel:

- `setChannelWorkspaceMirror(uint256 channelId, string uri)`
- `getChannelWorkspaceMirror(uint256 channelId)`

Only the channel leader recorded in `BridgeCore.getChannel(channelId).leader` can set or update the
URL. An empty URL clears the mirror. The URI is limited to 2048 bytes.

## Client Selection

`channel recover-workspace` supports these sources:

- `--source rpc`: use only RPC log recovery. This is the default when `--source` is omitted.
- `--source mirror`: require the registered mirror, validate its signed checkpoint manifest, then
  download only the required checkpoint or delta bundle.

`--from-genesis` intentionally rebuilds from channel genesis and is only valid when paired with
explicit `--source rpc`.

## URL Layout

The registered URL is a server base URL. For a channel on `chainId` and `channelId`, the CLI fetches:

```text
GET <base>/.well-known/tokamak-private-state/channel-workspace/<chainId>/<channelId>/manifest.json
```

If the registered URL ends in `.json`, the CLI treats it as the manifest URL directly. This allows a
channel leader to publish a single static manifest path instead of the well-known directory layout.
The protocol version is carried only by manifest and bundle metadata, not by the URL path.

## Manifest

The manifest is UTF-8 JSON:

```json
{
  "protocolVersion": 2,
  "chainId": 1,
  "channelId": "9300182250917983789525974997190401499154408837858857556147320880169742109284",
  "channelName": "example-channel",
  "bridgeCore": "0x992E2Ae206620d811832a8F697c526c4f95974b6",
  "channelManager": "0x...",
  "bridgeTokenVault": "0x...",
  "leader": "0x...",
  "checkpoint": {
    "recoveryLastScannedBlock": 25018369,
    "recoveryRootVectorHash": "0x...",
    "workspaceHash": "0x...",
    "stateSnapshotHash": "0x...",
    "blockInfoHash": "0x...",
    "contractCodesHash": "0x...",
    "bundle": {
      "url": "checkpoint.zip",
      "sha256": "0123456789abcdef...",
      "sizeBytes": 123456
    }
  },
  "deltaBundles": [
    {
      "fromBlock": 25017000,
      "toBlock": 25018368,
      "url": "deltas/25017000-25018368.json",
      "sha256": "abcdef0123456789...",
      "sizeBytes": 23456
    }
  ],
  "validationCertificate": {
    "schema": "tokamak-private-state-workspace-mirror",
    "signer": "0x...",
    "signedAt": "2026-05-08T00:00:00Z",
    "canary": {
      "proofVerified": true,
      "description": "Checkpoint workspace was used to generate and verify the mirror operator's canary proof."
    },
    "signature": "0x..."
  },
  "createdAt": "2026-05-08T00:00:00Z",
  "minCliVersion": "1.2.0"
}
```

The `validationCertificate.signature` is an EIP-191 personal-signature over the canonical manifest
certificate payload with `validationCertificate.signature` omitted. The recovered signer must equal
the channel leader from `BridgeCore.getChannel(channelId).leader`.

All `*Hash` fields except bundle `sha256` values are `keccak256` hashes of the CLI's canonical JSON
encoding for the referenced object. Bundle `sha256` values are lowercase SHA-256 digests of the
downloaded bundle bytes. `sizeBytes` is required for every checkpoint and delta bundle descriptor;
clients use it as a hard download limit before verifying the bundle hash.

## Operator Publishing

The CLI can build the static mirror files for the registered mirror URL:

```bash
private-state-cli channel publish-workspace-mirror \
  --channel-name <CHANNEL> \
  --network mainnet \
  --account <LEADER_ACCOUNT> \
  --output ./mirror-public
```

The command does not upload to a remote server. It writes the static directory layout under
`--output`, and the channel leader deploys that directory to the registered HTTPS mirror host.
If the registered URL contains a base path or directly points to a `.json` manifest, the output path
mirrors that URL path so the generated files resolve at the same locations the CLI will fetch.
Before writing files, the command fetches only the registered mirror manifest and compares its
checkpoint with the local channel workspace. Publishing continues only when the local workspace is
current relative to on-chain state and its recovery index is ahead of the valid registered mirror
checkpoint. If the remote manifest is not found, the command treats this as the first publish.

When a valid previous mirror checkpoint exists, the command writes a delta bundle from the previous
mirror checkpoint to the local checkpoint and references it from the new manifest. Existing delta
files in the output directory are left in place unless overwritten.

If the existing remote manifest is unreadable or invalid, the operator can repair the mirror by
adding `--force`:

```bash
private-state-cli channel publish-workspace-mirror \
  --channel-name <CHANNEL> \
  --network mainnet \
  --account <LEADER_ACCOUNT> \
  --output ./mirror-public \
  --force
```

`--force` does not bypass leader authorization, local workspace freshness checks, or local recovery
index validation. It only tells the publisher not to trust the broken remote manifest as a delta
base. The command then writes a full checkpoint manifest without a new delta bundle and reports the
ignored remote manifest error in `ignoredRemoteCheckpoint`.

## Checkpoint Bundle

The checkpoint bundle is needed when the user has no usable local recovery index. It is a ZIP file
containing exactly these root-level JSON files:

- `workspace.json`
- `state_snapshot.json`
- `block_info.json`
- `contract_codes.json`

The bundle must not contain wallet backup metadata, wallet key files, account secrets, wallet
secret source files, note secrets, absolute paths, nested paths, or duplicate file names. The CLI
streams the download and displays progress with an estimated remaining time.

The CLI downloads the checkpoint bundle only after validating the manifest metadata and leader
signature. It enforces the declared `sizeBytes` during download. After download, the CLI verifies the
bundle SHA-256, exact size, every declared content hash, channel metadata, managed storage vector,
block info, contract code, and snapshot root vector.

## Delta Bundle

When a usable local recovery index exists and the mirror checkpoint is ahead of it, the CLI does not
download the checkpoint bundle. It selects a delta bundle whose `fromBlock` equals the local
`recoveryLastScannedBlock` and whose `toBlock + 1` equals the mirror checkpoint
`recoveryLastScannedBlock`.

The delta bundle is UTF-8 JSON:

```json
{
  "protocolVersion": 2,
  "chainId": 1,
  "channelId": "9300182250917983789525974997190401499154408837858857556147320880169742109284",
  "fromBlock": 25017000,
  "toBlock": 25018368,
  "baseRecoveryRootVectorHash": "0x...",
  "recoveryRootVectorHash": "0x...",
  "logs": [
    {
      "address": "0x...",
      "topics": ["0x..."],
      "data": "0x...",
      "blockNumber": 25017001,
      "transactionHash": "0x...",
      "transactionIndex": 1,
      "index": 12
    }
  ]
}
```

The `logs` array contains the same channel-manager and bridge-vault logs that RPC recovery would
consume. The CLI applies these logs to the local snapshot with the same transition logic used by RPC
recovery, verifies every emitted root vector transition, and rejects the delta unless the resulting
root vector hash equals the manifest checkpoint `recoveryRootVectorHash`.

## Required CLI Verification

Before downloading any checkpoint or delta bundle, the CLI verifies:

- manifest `chainId`, `channelId`, `bridgeCore`, `channelManager`, `bridgeTokenVault`, and
  `leader` match on-chain `BridgeCore.getChannel(channelId)`
- optional manifest `channelName` matches the requested channel name
- manifest `blockInfoHash` and `contractCodesHash` match local RPC-derived channel genesis data and
  current managed storage contract code
- `validationCertificate` is signed by the channel leader and states that the checkpoint workspace
  was used for canary proof generation and verification
- mirror `recoveryLastScannedBlock` is ahead of the local recovery index before any delta bundle is
  downloaded

After download, the CLI verifies:

- bundle SHA-256 and exact size match the manifest
- checkpoint bundle contains only the allowed root-level JSON files, if a checkpoint bundle is used
- checkpoint content hashes match the manifest, if a checkpoint bundle is used
- delta logs are in the declared block range and come only from the channel manager or bridge vault,
  if a delta bundle is used
- the resulting root vector hash equals the mirror checkpoint root

After these checks, the CLI uses the mirrored checkpoint only as a recovery index. It still replays
RPC logs from `recoveryLastScannedBlock` to the latest block and rejects the result unless the final
root vector hash equals `ChannelManager.currentRootVectorHash()`.

## Operational Guidance

A channel leader can publish the mirror as static files behind HTTPS. Updating the mirror is safe to
do periodically rather than continuously; a stale mirror still helps if it is newer than the user's
local recovery index because the CLI downloads only the matching delta bundle and replays any
remaining RPC delta. Mirror operators should publish delta bundles for common recent checkpoint
ranges and garbage-collect bundles that are no longer useful.

# Channel Workspace Mirror Protocol

Channel workspace mirrors are optional bootstrap caches operated by channel leaders. They reduce the
cost of joining or recovering an old channel by serving a recent channel workspace snapshot with a
usable recovery index. The mirror is not a source of consensus. The CLI must verify the downloaded
snapshot against on-chain channel metadata and then replay RPC logs from the mirrored recovery index
to the latest block.

## On-Chain Registry

`BridgeCore` stores one mirror base URL per channel:

- `setChannelWorkspaceMirror(uint256 channelId, string uri)`
- `getChannelWorkspaceMirror(uint256 channelId)`

Only the channel leader recorded in `BridgeCore.getChannel(channelId).leader` can set or update the
URL. An empty URL clears the mirror. The URI is limited to 2048 bytes.

## Client Selection

`channel recover-workspace` supports these sources:

- `--source rpc`: use only RPC log recovery. This is the default when `--source` is omitted.
- `--source mirror`: require the registered mirror, download its snapshot, verify it, then replay RPC
  logs from the mirror recovery index to the latest block.

`--from-genesis` intentionally rebuilds from channel genesis and is only valid when paired with
explicit `--source rpc`.

## URL Layout

The registered URL is a server base URL. For a channel on `chainId` and `channelId`, the CLI fetches:

```text
GET <base>/.well-known/tokamak-private-state/channel-workspace/v1/<chainId>/<channelId>/manifest.json
```

If the registered URL ends in `.json`, the CLI treats it as the manifest URL directly. This allows a
channel leader to publish a single static manifest path instead of the well-known directory layout.

## Manifest

The manifest is UTF-8 JSON:

```json
{
  "protocolVersion": 1,
  "chainId": 1,
  "channelId": "9300182250917983789525974997190401499154408837858857556147320880169742109284",
  "channelName": "example-channel",
  "bridgeCore": "0x992E2Ae206620d811832a8F697c526c4f95974b6",
  "channelManager": "0x...",
  "recoveryLastScannedBlock": 25018369,
  "recoveryRootVectorHash": "0x...",
  "archive": {
    "url": "workspace.zip",
    "sha256": "0123456789abcdef...",
    "sizeBytes": 123456
  },
  "createdAt": "2026-05-08T00:00:00Z",
  "minCliVersion": "1.2.0"
}
```

`archive.url` may be absolute or relative to the manifest URL. `archive.sha256` is the lowercase
SHA-256 digest of the ZIP bytes. `sizeBytes` is optional, but recommended.

## Archive

The ZIP archive must contain exactly these root-level JSON files:

- `workspace.json`
- `state_snapshot.json`
- `block_info.json`
- `contract_codes.json`

The archive must not contain wallet files, account secrets, wallet secrets, note secrets, absolute
paths, nested paths, or duplicate file names. The CLI rejects archives above 50 MiB.

`workspace.json` is the same channel workspace metadata shape stored locally by the CLI. Its
`recoveryLastScannedBlock` and `recoveryRootVectorHash` must match the manifest. `state_snapshot.json`
must hash to `recoveryRootVectorHash`.

## Required CLI Verification

Before accepting a mirror snapshot, the CLI verifies:

- manifest `chainId`, `channelId`, `bridgeCore`, and `channelManager` match on-chain
  `BridgeCore.getChannel(channelId)`
- optional manifest `channelName` matches the requested channel name
- archive SHA-256 and optional size match the manifest
- archive contains only the allowed root-level JSON files
- `workspace.json` bridge, channel, manager, vault, genesis block, and managed storage vector match
  on-chain channel metadata
- `block_info.json` matches the channel genesis block used by the channel `aPubBlockHash`
- `contract_codes.json` matches the current managed storage contract code fetched from RPC
- `state_snapshot.json` storage addresses match the channel managed storage vector
- snapshot root vector hash equals the mirrored recovery root vector hash

After these checks, the CLI uses the mirrored snapshot only as a recovery index. It still replays RPC
logs from `recoveryLastScannedBlock` to the latest block and rejects the result unless the final root
vector hash equals `ChannelManager.currentRootVectorHash()`.

## Operational Guidance

A channel leader can publish the mirror as static files behind HTTPS. Updating the mirror is safe to
do periodically rather than continuously; a stale mirror still helps if it is newer than channel
genesis because the CLI replays the remaining RPC delta. The mirror operator should regenerate the
archive after meaningful channel activity and keep old archives private or garbage-collected.

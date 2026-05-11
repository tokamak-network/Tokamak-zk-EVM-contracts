# Channel Workspace Mirror Server Handoff

This handoff is for a new LLM instance starting work in the separate
`channel-workspace-mirror` repository. The current repository already contains the bridge contracts,
the private-state CLI, and the client-side channel workspace mirror protocol. The new repository
should implement the reusable server/operator layer for serving mirror artifacts.

## Current State In This Repository

The private-state CLI already supports the client-side mirror workflow:

- `channel set-workspace-mirror` registers a mirror base URL on `BridgeCore`.
- `channel publish-workspace-mirror` builds static mirror files locally.
- `channel recover-workspace --source mirror` validates and consumes the mirror.

The mirror URL path no longer carries a version segment. The protocol version is metadata only.

Default fetch path:

```text
GET <base>/.well-known/tokamak-private-state/channel-workspace/<chainId>/<channelId>/manifest.json
```

If the registered URL ends with `.json`, the CLI treats it as the manifest URL directly.

Primary protocol documentation:

```text
packages/apps/private-state/docs/channel-workspace-mirror-protocol.md
```

Important CLI implementation file:

```text
packages/apps/private-state/cli/private-state-bridge-cli.mjs
```

Recent feature-branch commits relevant to mirror work:

- `ef7d080 Replace workspace mirror archives with signed deltas`
- `8d6ecc1 Add workspace mirror publishing command`
- `fc2ca86 Document channel workspace mirror server handoff`

At the time this handoff was updated, these commits lived on the
`feature/channel-workspace-mirror-recovery` branch and were not part of `main`.

## Server Repository Goal

The new `channel-workspace-mirror` repository should be a reusable bridge/channel-level mirror
server implementation. It must not be private-state-dapp-specific. The same codebase should support
multiple DApps and channels through configuration and deployment boundaries.

Recommended deployment model:

- One reusable code repository: `channel-workspace-mirror`
- Separate Vercel projects per channel, per operator group, or per DApp depending on isolation needs
- Optional Neon metadata database per deployment or per operator group
- Vercel Blob for large mirror artifact storage

The server should provide stable URLs matching the CLI protocol while storing large files in Blob.

## Responsibilities

The server repository should own:

- Vercel app/function implementation
- Vercel Blob upload and public read integration
- Neon schema and migrations for publish metadata
- Admin publish API or upload script
- Public mirror read routes
- Cleanup jobs for old checkpoints and deltas
- Deployment documentation for channel operators

It should not own:

- Smart contracts
- Channel workspace reconstruction logic
- Proof generation logic
- Mirror manifest signing logic already handled by the CLI
- DApp-specific protocol rules unless they become generic channel-workspace mirror extensions

## CLI Artifact Generation Contract

The operator first generates mirror artifacts with the private-state CLI:

```bash
private-state-cli channel recover-workspace \
  --channel-name <CHANNEL> \
  --network mainnet \
  --source rpc

private-state-cli channel set-workspace-mirror \
  --channel-name <CHANNEL> \
  --network mainnet \
  --account <LEADER_ACCOUNT> \
  --url https://<mirror-domain>

private-state-cli channel publish-workspace-mirror \
  --channel-name <CHANNEL> \
  --network mainnet \
  --account <LEADER_ACCOUNT> \
  --output ./mirror-public
```

`publish-workspace-mirror` writes files under the URL-compatible static path. Example:

```text
mirror-public/
  .well-known/
    tokamak-private-state/
      channel-workspace/
        1/
          <channelId>/
            manifest.json
            checkpoint.zip
            deltas/
              <fromBlock>-<toBlock>.json
```

If the registered mirror URL contains a base path or directly points to a `.json` manifest, the CLI
mirrors that path under `--output` so uploaded files resolve at the same locations clients fetch.

The server implementation can initially accept this directory as input. A later improvement can add
direct CLI upload support, but the first server version should work with the generated directory.

## Artifact Shapes

The manifest has this high-level shape:

```json
{
  "protocolVersion": 2,
  "chainId": 1,
  "channelId": "123",
  "channelName": "example",
  "bridgeCore": "0x...",
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
      "sha256": "...",
      "sizeBytes": 123456
    }
  },
  "deltaBundles": [
    {
      "fromBlock": 25017000,
      "toBlock": 25018368,
      "url": "deltas/25017000-25018368.json",
      "sha256": "...",
      "sizeBytes": 23456
    }
  ],
  "validationCertificate": {
    "schema": "tokamak-private-state-workspace-mirror",
    "signer": "0x...",
    "signedAt": "2026-05-08T00:00:00Z",
    "canary": {
      "proofVerified": true,
      "description": "..."
    },
    "signature": "0x..."
  },
  "createdAt": "2026-05-08T00:00:00Z",
  "minCliVersion": "1.2.0"
}
```

The server does not need to recompute cryptographic hashes for public reads. The CLI verifies
manifest signatures, bundle SHA-256 values, content hashes, channel metadata, and root transitions.
The server should still reject malformed uploads to reduce operator mistakes.

## Recommended Vercel/Blob Architecture

Use Vercel Blob for artifact storage and Vercel Functions for stable routes.

Public routes should satisfy these reads:

```text
GET /.well-known/tokamak-private-state/channel-workspace/<chainId>/<channelId>/manifest.json
GET /.well-known/tokamak-private-state/channel-workspace/<chainId>/<channelId>/checkpoint.zip
GET /.well-known/tokamak-private-state/channel-workspace/<chainId>/<channelId>/deltas/<from>-<to>.json
```

Implementation choices:

- Return Blob file bytes directly from a route handler, or
- Redirect to the public Blob URL if the CLI handles the redirect path cleanly.

Prefer preserving the stable protocol path on the mirror domain, even if the actual storage is Blob.

Suggested Blob object keys:

```text
.well-known/tokamak-private-state/channel-workspace/<chainId>/<channelId>/manifest.json
.well-known/tokamak-private-state/channel-workspace/<chainId>/<channelId>/checkpoint-<block>.zip
.well-known/tokamak-private-state/channel-workspace/<chainId>/<channelId>/checkpoint.zip
.well-known/tokamak-private-state/channel-workspace/<chainId>/<channelId>/deltas/<from>-<to>.json
```

`checkpoint.zip` may point to the latest checkpoint for compatibility with generated manifests. A
block-suffixed checkpoint can be retained for rollback or audit.

## Recommended Neon Schema

Neon is not required for serving files, but it is useful once checkpoints are updated frequently.

Start with a minimal schema:

```sql
create table mirror_publish_history (
  id bigserial primary key,
  chain_id bigint not null,
  channel_id text not null,
  channel_name text,
  checkpoint_block bigint not null,
  recovery_root_vector_hash text not null,
  manifest_path text not null,
  checkpoint_path text not null,
  checkpoint_sha256 text not null,
  checkpoint_size_bytes bigint not null,
  delta_bundles jsonb not null default '[]',
  leader text not null,
  published_at timestamptz not null default now()
);

create index mirror_publish_history_channel_checkpoint_idx
  on mirror_publish_history (chain_id, channel_id, checkpoint_block desc);
```

Optional tables for later:

- `channels`: registered channels managed by this deployment
- `blob_objects`: reference counts and cleanup status
- `admin_tokens`: hashed admin upload tokens if not using Vercel auth
- `publish_failures`: failed uploads and validation errors

## Admin Upload API

The first useful API can be intentionally small:

```text
POST /api/admin/publish
```

Expected input options:

- Multipart form containing the generated mirror-public files
- Or a tar/zip of the generated mirror-public directory
- Or a JSON manifest plus files uploaded one by one

Recommended first version:

- Accept a tar/zip archive of the generated directory
- Extract it safely
- Locate `manifest.json`
- Validate `protocolVersion === 2`
- Validate required fields and relative bundle URLs
- Validate all referenced files exist in the upload
- Validate SHA-256 and `sizeBytes` against uploaded files
- Upload files to Blob
- Insert a Neon publish history row
- Return the public manifest URL and checkpoint metadata

Safety rules:

- Reject absolute paths and `..` paths in uploaded archives
- Reject files outside `.well-known/tokamak-private-state/channel-workspace/`
- Limit upload size based on deployment policy, but do not impose a low cap that defeats old-channel recovery
- Require an admin secret or Vercel-authenticated operator session
- Never store channel leader private keys on the server

## Cleanup Policy

Do not delete aggressively. Users can have old local recovery indexes and may need older deltas.

Initial policy:

- Keep the latest 2 checkpoints per channel
- Keep all deltas whose `toBlock` reaches one of the retained checkpoints
- Keep at least 30 days of publish history
- Add a dry-run cleanup command before destructive deletion

Later policy:

- Track download counts
- Keep common checkpoint ranges longer
- Add channel-specific retention settings

## Environment Variables

Expected Vercel environment variables:

```text
BLOB_READ_WRITE_TOKEN=...
DATABASE_URL=...
MIRROR_ADMIN_TOKEN=...
NODE_ENV=production
```

Do not expose write tokens to client-side code. Server routes only.

## Suggested Repository Layout

```text
channel-workspace-mirror/
  app/
    .well-known/
      tokamak-private-state/
        channel-workspace/
          [chainId]/
            [channelId]/
              manifest.json/route.ts
              checkpoint.zip/route.ts
              deltas/
                [range]/route.ts
    api/
      admin/
        publish/route.ts
      health/route.ts
  lib/
    blob.ts
    db.ts
    manifest.ts
    paths.ts
    publish.ts
    safe-archive.ts
  migrations/
    001_init.sql
  scripts/
    upload-local.ts
    cleanup.ts
  README.md
  package.json
  vercel.json
```

If using the Next.js App Router, be careful with dots in `.well-known` paths. If route handling is
awkward, use `vercel.json` rewrites to route the protocol path into a simpler API handler.

## Acceptance Criteria For The First Server Version

The first server implementation is acceptable when:

- A generated `mirror-public` directory can be uploaded without manual path rewriting.
- The public manifest URL matches the CLI fetch URL exactly.
- The public checkpoint and delta URLs resolve relative to the manifest URL.
- The CLI command below succeeds against the deployed server:

```bash
private-state-cli channel recover-workspace \
  --channel-name <CHANNEL> \
  --network mainnet \
  --source mirror
```

- Upload rejects malformed manifests, bad SHA-256 values, missing referenced files, and unsafe paths.
- Neon records each successful publish.
- No server-side code requires or stores a channel leader private key.

## Important Open Decisions

The next LLM should resolve these before coding too far:

- Will the first upload path be a directory-upload script, multipart API, or archive API?
- Should public reads proxy Blob bytes or redirect to Blob URLs?
- Should one deployment serve exactly one channel, or should one deployment serve multiple channels?
- How should admin authentication work in the first version?
- What upload size policy is acceptable for old channel checkpoints?

Recommended choices for the first version:

- Archive upload API or local script upload, whichever is faster in the chosen framework
- Public read proxy or redirect, but keep stable protocol URLs on the mirror domain
- Multi-channel-capable server, deployed per operator group or per channel as needed
- `MIRROR_ADMIN_TOKEN` for the first version
- Configurable upload size limit with no small default cap

## Notes For The Next LLM

- Keep docs and code comments in English.
- Do not make the server DApp-specific. Avoid names like `private-state-mirror` in the new repo.
- Treat `private-state` as the first consumer, not the protocol boundary.
- The current CLI output is the source of truth for artifact layout.
- The server is not a consensus source. The CLI performs consensus-critical validation.
- Prefer simple operational correctness over a broad dashboard in the first version.

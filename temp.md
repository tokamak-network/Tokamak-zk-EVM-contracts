# BridgeCore Size And npm Audit Notes

Date: 2026-05-02

## BridgeCore Contract Size

### Original Problem

The private-state CLI e2e run with `@tokamak-zk-evm/cli@2.0.16` exposed a deploy-blocking
contract-size issue:

- `BridgeCore` runtime size before the temporary reduction: `24,849 bytes`
- EIP-170 runtime bytecode limit: `24,576 bytes`
- Excess: `273 bytes`

The immediate fix removed three non-essential pass-through getters from `BridgeCore`:

- `getChannelTokenVaultRegistration(uint256,address)`
- `getChannelTokenVaultRegistrationByL2Address(uint256,address)`
- `getNoteReceivePubKeyByL2Address(uint256,address)`

After that removal, `forge build --root bridge --sizes` reported:

- `BridgeCore` runtime size: `23,665 bytes`
- Remaining runtime margin: `911 bytes`

This is enough to deploy, but it is not a fundamental solution. A `911 byte` margin is too small for
a mainnet-facing UUPS implementation that is still under active security hardening.

### ChannelDeployer Split

The root cause was addressed by splitting channel deployment mechanics out of `BridgeCore` into
`ChannelDeployer`.

`BridgeCore` still owns the channel-creation policy decision:

- Channel ID uniqueness.
- Bound bridge token vault requirement.
- Non-zero leader.
- Bridge Merkle tree configuration check.
- Maximum managed storage count check.
- Expected DApp metadata digest check.
- Channel registry write.
- `ChannelCreated` event emission.

`ChannelDeployer` performs the deployment mechanics:

- Loads managed storage addresses from `DAppManager`.
- Loads registered function references from `DAppManager`.
- Builds the zero-filled initial root vector.
- Deploys `ChannelManager`.
- Returns the deployed manager address to `BridgeCore`.

`BridgeCore` then binds the channel token vault and records the channel deployment.

Current size after the split:

| Contract | Runtime Size | Runtime Margin |
| --- | ---: | ---: |
| `BridgeCore` | `8,822 bytes` | `15,754 bytes` |
| `ChannelDeployer` | `16,062 bytes` | `8,514 bytes` |

This leaves `BridgeCore` with enough bytecode margin for future UUPS hardening while preserving
`BridgeCore` as the canonical policy and registry root.

### Why The Current Shape Is Fragile

`BridgeCore` currently combines too many responsibilities:

- UUPS ownership and upgrade authorization.
- Verifier address management.
- Bridge token vault binding.
- Canonical asset selection.
- Default join-fee refund policy.
- DApp metadata digest checks during channel creation.
- Channel deployment.
- Channel registry storage and lookup.

Each additional defensive check, event, getter, metadata field, or policy snapshot consumes the same
implementation bytecode budget. The current emergency reduction removed view helpers, but the next
mainnet-hardening change can push the implementation back over the limit.

### Recommended Follow-Up

The first split is complete. The remaining recommendation is to make the size budget explicit in CI.
The target should be a `BridgeCore` implementation with at least `2 KB` to `3 KB` of runtime size
margin after all planned mainnet checks are included. The current margin is well above that target.

Recommended structure:

1. Keep `BridgeCore` as the upgradeable root registry and access-control coordinator.
   - Owns the proxy state that must remain stable.
   - Stores the minimal channel registry fields required by external integrations.
   - Exposes `getChannel` and `getChannelManager`.
   - Authorizes upgrades.

2. Keep channel deployment mechanics outside `BridgeCore`.
   - `ChannelDeployer` should remain an execution helper, not a policy owner.
   - `BridgeCore.createChannel` should continue to make the final policy decision and registry write.

3. Move mutable bridge policy/configuration into a dedicated manager when possible.
   - Verifier address management and join-fee refund schedule management are good candidates.
   - `BridgeCore` can keep pointers to these managers instead of embedding all policy mutation logic.

4. Avoid future pass-through getters on `BridgeCore`.
   - If data belongs to `ChannelManager`, clients should query `ChannelManager` directly after
     resolving it via `BridgeCore.getChannelManager(channelId)`.
   - This preserves the root contract byte budget for consensus-critical logic only.

5. Add a CI size budget.
   - Run `forge build --root bridge --sizes`.
   - Fail the build if `BridgeCore` runtime margin falls below a configured threshold, for example
     `2,048 bytes`.
   - Treat the threshold as a mainnet readiness gate, not a warning.

### Upgradeability Impact

Because mainnet deployment has not happened yet, the cleanest fix is to redesign the deployment
layout before the first proxy deployment. If the bridge were already deployed, the same direction
would still be possible through UUPS, but it would be constrained by the existing proxy storage
layout and would require a more careful migration-compatible implementation.

## npm Audit Findings

Current command:

```sh
npm audit --json
```

Current summary:

| Severity | Count |
| --- | ---: |
| Critical | 0 |
| High | 3 |
| Moderate | 10 |
| Total | 13 |

The 13 audit entries are mostly transitive tooling issues. They collapse into three practical
dependency chains:

1. `@tokamak-zk-evm/cli` / `@tokamak-zk-evm/synthesizer-node` pulls vulnerable `vitest`, `vite`,
   `vite-node`, `@vitest/*`, and `esbuild` versions.
2. `@google-cloud/local-auth` pulls `google-auth-library@9`, which pulls vulnerable
   `gaxios@6.7.1` and `uuid@9.0.1`.
3. `snarkjs@0.7.6` pulls `bfj`, `jsonpath`, and vulnerable `underscore`.

### Detailed Table

| Package | Severity | Direct? | Dependency Path | Reported Issue | Recommended Resolution |
| --- | --- | --- | --- | --- | --- |
| `@tokamak-zk-evm/cli` | Moderate | Yes | root dependency | Inherits `@tokamak-zk-evm/synthesizer-node` audit issues. | Do not downgrade to the npm suggested `1.0.4` fix. Instead publish or adopt a patched `2.x` CLI that depends on a patched `@tokamak-zk-evm/synthesizer-node`. |
| `@tokamak-zk-evm/synthesizer-node` | Moderate | Yes | root and CLI dependency | Pulls vulnerable `vitest` and `@vitest/coverage-v8` as installed dependencies. | Best fix: move test-only dependencies out of runtime dependencies. If they are required at runtime, update them beyond the vulnerable ranges and publish a patched `2.x` package. |
| `@vitest/coverage-v8` | Moderate | No | `@tokamak-zk-evm/synthesizer-node` -> `@vitest/coverage-v8` | Inherits vulnerable `vitest`. | Remove from runtime dependency graph or update beyond `<=2.2.0-beta.2`. |
| `vitest` | Moderate | No | `@tokamak-zk-evm/synthesizer-node` -> `vitest` | Depends on vulnerable `vite`, `vite-node`, and `@vitest/mocker`. | Remove from production install path or update outside the affected range. |
| `@vitest/mocker` | Moderate | No | `vitest` -> `@vitest/mocker` | Inherits vulnerable `vite`. | Update with `vitest`, or remove `vitest` from runtime dependencies. |
| `vite-node` | Moderate | No | `vitest` -> `vite-node` | Inherits vulnerable `vite`. | Update with `vitest`, or remove `vitest` from runtime dependencies. |
| `vite` | Moderate | No | `vitest` -> `vite` | Path traversal / optimized dependency source-map handling; also inherits `esbuild`. | Update to a patched `vite` version beyond `<=6.4.1`, then rerun CLI e2e. |
| `esbuild` | Moderate | No | `vite` -> `esbuild` | Development server request exposure issue. | Update through patched `vite` or force an override only after verifying synthesizer and CLI behavior. |
| `gaxios` | Moderate | No | `@google-cloud/local-auth` -> `google-auth-library@9.15.1` -> `gaxios@6.7.1` | Inherits vulnerable `uuid`. | Prefer upgrading or replacing `@google-cloud/local-auth` so it uses `google-auth-library@10` / `gaxios@7`. Avoid blind overrides until Google Drive auth flow is tested. |
| `uuid` | Moderate | No | `gaxios@6.7.1` -> `uuid@9.0.1` | Missing buffer bounds check in namespace UUID generation when `buf` is provided. | Resolve by upgrading the `gaxios` chain. If using overrides, test Google OAuth and Drive upload scripts. |
| `bfj` | High | No | `snarkjs@0.7.6` -> `bfj@7.1.0` | Inherits `jsonpath` / `underscore` issue. | Prefer upgrading `snarkjs` if a patched release exists. Otherwise test an npm override for `underscore` after running Groth16 setup/proof workflows. |
| `jsonpath` | High | No | `bfj` -> `jsonpath@1.3.0` | Inherits vulnerable `underscore`. | Resolve through `snarkjs` / `bfj` upgrade, or a carefully tested override. |
| `underscore` | High | No | `jsonpath` -> `underscore@1.13.6` | Unlimited recursion in `_.flatten` / `_.isEqual`, potential DoS. | Update beyond the vulnerable `<=1.13.7` range if compatible with `jsonpath`; verify `snarkjs` workflows. |

### Proposed Resolution Plan

1. Fix the Tokamak CLI dependency chain upstream.
   - Publish a patched `@tokamak-zk-evm/synthesizer-node@2.x`.
   - Remove `vitest` and coverage packages from production dependencies if they are test-only.
   - Otherwise update `vitest`, `vite`, `vite-node`, `@vitest/mocker`, `@vitest/coverage-v8`, and
     `esbuild` outside the vulnerable ranges.
   - Publish a patched `@tokamak-zk-evm/cli@2.x` that depends on the patched synthesizer package.
   - Rerun the private-state CLI e2e before accepting the patched package.

2. Fix the Google Drive auth dependency chain.
   - Replace or upgrade `@google-cloud/local-auth` so it no longer installs
     `google-auth-library@9.15.1` / `gaxios@6.7.1`.
   - Validate:
     - OAuth local login.
     - Google Drive folder listing.
     - Deployment metadata upload.
     - Existing token cache compatibility.

3. Fix the `snarkjs` dependency chain.
   - First try a patched `snarkjs` release if available.
   - If no patched release exists, test `npm overrides` for `underscore` beyond the vulnerable range.
   - Validate:
     - Groth16 setup scripts.
     - Proof generation.
     - Verifier export.
     - Existing e2e scripts that consume `snarkjs` artifacts.

4. Add an audit gate after the dependency fixes.
   - Do not use `npm audit fix --force` blindly because the current suggested fix for
     `@tokamak-zk-evm/cli` downgrades to `1.0.4`, which is incompatible with the current
     `2.0.16` target.
   - Add a CI job that runs `npm audit --omit=dev` or the repo's chosen install profile.
   - Document any accepted transitive tooling risk with an owner and expiration date.

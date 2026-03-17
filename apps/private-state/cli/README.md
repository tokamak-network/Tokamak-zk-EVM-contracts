# private-state CLI

This folder contains a terminal CLI for the private-state DApp.

## Structure

- `private-state-cli.mjs`: the CLI entrypoint
- `functions/index.json`: selectable function list
- `functions/<function-name>/calldata.json`: default calldata template for that function

Each `calldata.json` file follows this shape:

```json
{
  "description": "Human-readable note for the operator",
  "contractKey": "controller",
  "abiFile": "../deploy/PrivateStateController.callable-abi.json",
  "method": "mintNotes1",
  "mode": "send",
  "value": "0x0",
  "args": [[{"owner":"0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266","value":"1000000000000000000","salt":"0x1000000000000000000000000000000000000000000000000000000000000001"}]]
}
```

The CLI reads a function's `calldata.json`, optionally replaces `args` through `--args-file` or replaces the full
template through `--template-file`, resolves the deployed contract address from
`apps/private-state/deploy/deployment.<chain-id>.latest.json`, restricts network selection to `mainnet`, `sepolia`,
or `anvil`, and then either:

- generates calldata only
- performs `eth_call`
- submits a signed transaction using a provided private key

## Usage

```bash
node apps/private-state/cli/private-state-cli.mjs list
node apps/private-state/cli/private-state-cli.mjs show-template mintNotes1
node apps/private-state/cli/private-state-cli.mjs generate mintNotes1 --network sepolia
node apps/private-state/cli/private-state-cli.mjs send mintNotes1 --network anvil --private-key <hex>
```

## Function-folder naming

The requirement is to keep one folder per function name. That creates a collision risk when several contracts expose a
function with the same name. private-state already has repeated low-signal getters such as `controller()`. Those
duplicates are intentionally omitted from the function-folder set so the folder naming rule remains usable.

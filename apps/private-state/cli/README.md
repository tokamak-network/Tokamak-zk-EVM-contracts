# private-state CLI

This folder contains a browser-based CLI for the private-state DApp.

## Why it is browser-based

MetaMask exposes an EIP-1193 provider in the browser, not in a plain shell process. Because the CLI must optionally
connect to MetaMask and submit transactions, the practical implementation is a static web app that behaves like an
operator console.

## Structure

- `index.html`: the operator UI
- `main.js`: manifest loading, ABI loading, calldata generation, `eth_call`, and `eth_sendTransaction`
- `style.css`: presentation
- `serve.sh`: simple local static file server
- `functions/index.json`: selectable function list
- `functions/<function-name>/calldata.json`: default calldata template for that function

Each `calldata.json` file follows this shape:

```json
{
  "description": "Human-readable note for the operator",
  "contractKey": "controller",
  "abiFile": "../deploy/PrivateStateController.callable-abi.json",
  "method": "bridgeDeposit",
  "mode": "send",
  "value": "0x0",
  "args": ["1000000000000000000"]
}
```

The CLI reads the selected function's `calldata.json`, allows manual editing, encodes the calldata with the callable
ABI, resolves the deployed contract address from `apps/private-state/deploy/deployment.<chain-id>.latest.json`, and
then either:

- generates calldata only
- performs `eth_call`
- submits `eth_sendTransaction` through MetaMask

## Serving the CLI

Do not open the HTML file with `file://`. Use a local HTTP server instead.

```bash
bash apps/private-state/cli/serve.sh
```

Then open the printed URL in a browser with MetaMask installed.

## Function-folder naming

The requirement is to keep one folder per function name. That creates a collision risk when several contracts expose a
function with the same name. private-state already has repeated low-signal getters such as `controller()`. Those
duplicates are intentionally omitted from the function-folder set so the folder naming rule remains usable.

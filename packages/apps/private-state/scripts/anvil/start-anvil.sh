#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../.." && pwd)"
ENV_FILE="${APPS_ENV_FILE:-$PROJECT_ROOT/packages/apps/.env}"
DEPLOY_DIR="$PROJECT_ROOT/packages/apps/private-state/deploy"
PID_FILE="$DEPLOY_DIR/anvil.pid"
LOG_FILE="$DEPLOY_DIR/anvil.log"
source "$PROJECT_ROOT/packages/common/src/network-config.sh"

mkdir -p "$DEPLOY_DIR"

if [[ -f "$ENV_FILE" ]]; then
    set -a
    source "$ENV_FILE"
    set +a
fi

# The anvil wrapper must stay self-contained even when packages/apps/.env targets a public network.
RPC_URL="${APPS_RPC_URL_OVERRIDE:-http://127.0.0.1:8545}"
APPS_NETWORK="anvil"
resolve_app_network "$APPS_NETWORK"
CHAIN_ID="$APPS_CHAIN_ID"
MNEMONIC="${APPS_ANVIL_MNEMONIC:-test test test test test test test test test test test junk}"
HOST_PORT="${RPC_URL#http://}"
HOST_PORT="${HOST_PORT#https://}"
HOST_PORT="${HOST_PORT%%/*}"
HOST="${HOST_PORT%%:*}"
PORT="${HOST_PORT##*:}"

if [[ "$HOST" == "$PORT" ]]; then
    PORT="8545"
fi

if [[ -f "$PID_FILE" ]]; then
    EXISTING_PID="$(cat "$PID_FILE")"
    if kill -0 "$EXISTING_PID" 2>/dev/null; then
        echo "anvil is already running with PID $EXISTING_PID"
        exit 0
    fi
    rm -f "$PID_FILE"
fi

nohup anvil \
    --host "$HOST" \
    --port "$PORT" \
    --chain-id "$CHAIN_ID" \
    --mnemonic "$MNEMONIC" \
    >"$LOG_FILE" 2>&1 </dev/null &

ANVIL_PID=$!

for _ in $(seq 1 20); do
    if curl -sS \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' \
        "$RPC_URL" >/dev/null 2>&1; then
        RESOLVED_PID="$(pgrep -n -f "anvil.*--host $HOST.*--port $PORT" || true)"
        if [[ -n "$RESOLVED_PID" ]]; then
            ANVIL_PID="$RESOLVED_PID"
        fi
        echo "$ANVIL_PID" > "$PID_FILE"
        echo "Started anvil on $RPC_URL with PID $ANVIL_PID"
        echo "Log file: $LOG_FILE"
        exit 0
    fi
    sleep 1
done

echo "anvil did not start successfully. See $LOG_FILE" >&2
exit 1

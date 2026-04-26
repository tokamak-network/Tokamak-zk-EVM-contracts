#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../.." && pwd)"
PID_FILE="$PROJECT_ROOT/packages/apps/private-state/deploy/anvil.pid"
RESOLVED_PID=""

resolve_running_anvil_pid() {
    if [[ -f "$PID_FILE" ]]; then
        local recorded_pid
        recorded_pid="$(cat "$PID_FILE")"
        if kill -0 "$recorded_pid" 2>/dev/null; then
            printf '%s\n' "$recorded_pid"
            return 0
        fi
    fi

    pgrep -n -f 'anvil.*--port 8545' || true
}

RESOLVED_PID="$(resolve_running_anvil_pid)"

if [[ -z "$RESOLVED_PID" ]]; then
    echo "No anvil PID file found."
    exit 0
fi

if kill -0 "$RESOLVED_PID" 2>/dev/null; then
    kill "$RESOLVED_PID"
    echo "Stopped anvil PID $RESOLVED_PID"
else
    echo "anvil PID $RESOLVED_PID was not running"
fi

rm -f "$PID_FILE"

#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
PID_FILE="$PROJECT_ROOT/apps/private-state/deploy/anvil.pid"

if [[ ! -f "$PID_FILE" ]]; then
    echo "No anvil PID file found."
    exit 0
fi

ANVIL_PID="$(cat "$PID_FILE")"

if kill -0 "$ANVIL_PID" 2>/dev/null; then
    kill "$ANVIL_PID"
    echo "Stopped anvil PID $ANVIL_PID"
else
    echo "anvil PID $ANVIL_PID was not running"
fi

rm -f "$PID_FILE"

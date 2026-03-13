#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
CLI_ROOT="$PROJECT_ROOT/apps/private-state/cli"
PORT="${1:-4173}"

echo "Serving private-state CLI at http://127.0.0.1:${PORT}"
cd "$CLI_ROOT"
python3 -m http.server "$PORT"

#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  bash scripts/ci/run-with-memory-monitor.sh --log-dir <dir> -- <command> [args...]

Description:
  Runs a command while sampling host memory, cgroup memory, and top RSS processes.
  This script is intended for CI diagnostics and does not modify the command itself.
EOF
}

LOG_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --log-dir)
      LOG_DIR="${2:-}"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "$LOG_DIR" || $# -eq 0 ]]; then
  usage >&2
  exit 2
fi

mkdir -p "$LOG_DIR"

STDOUT_LOG="$LOG_DIR/command.stdout.log"
STDERR_LOG="$LOG_DIR/command.stderr.log"
SAMPLES_LOG="$LOG_DIR/system-memory-samples.log"
SUMMARY_LOG="$LOG_DIR/summary.log"

snapshot_system_state() {
  {
    echo "===== $(date -u +"%Y-%m-%dT%H:%M:%SZ") ====="
    echo "--- free -h"
    free -h || true
    echo
    echo "--- /proc/meminfo"
    grep -E '^(MemTotal|MemFree|MemAvailable|Buffers|Cached|SwapCached|SwapTotal|SwapFree|AnonPages|Mapped|Slab|SReclaimable|PageTables|KernelStack|Committed_AS):' /proc/meminfo || true
    echo
    echo "--- /proc/pressure/memory"
    cat /proc/pressure/memory || true
    echo
    echo "--- cgroup memory"
    for file in \
      /sys/fs/cgroup/memory.current \
      /sys/fs/cgroup/memory.max \
      /sys/fs/cgroup/memory.peak \
      /sys/fs/cgroup/memory.swap.current \
      /sys/fs/cgroup/memory.swap.max \
      /sys/fs/cgroup/memory.events
    do
      if [[ -f "$file" ]]; then
        echo "[$file]"
        cat "$file"
      fi
    done
    echo
    echo "--- top RSS processes"
    ps -eo pid,ppid,rss,vsz,%mem,%cpu,etime,comm,args --sort=-rss | head -n 40 || true
    echo
    echo "--- node/anvil/tokamak related processes"
    pgrep -af 'node|anvil|npm|tokamak-cli|tsx|forge|cast|cargo|rustc|bun|preprocess|prove|verify|trusted-setup' || true
    echo
  } >>"$SAMPLES_LOG"
}

echo "Command: $*" >"$SUMMARY_LOG"
echo "Started at: $(date -u +"%Y-%m-%dT%H:%M:%SZ")" >>"$SUMMARY_LOG"

snapshot_system_state

(
  while true; do
    snapshot_system_state
    sleep 2
  done
) &
MONITOR_PID=$!

cleanup() {
  if kill -0 "$MONITOR_PID" 2>/dev/null; then
    kill "$MONITOR_PID" 2>/dev/null || true
    wait "$MONITOR_PID" 2>/dev/null || true
  fi
}

trap cleanup EXIT

set +e
/usr/bin/time -v "$@" \
  > >(tee "$STDOUT_LOG") \
  2> >(tee "$STDERR_LOG" >&2)
COMMAND_RC=$?
set -e

snapshot_system_state

echo "Finished at: $(date -u +"%Y-%m-%dT%H:%M:%SZ")" >>"$SUMMARY_LOG"
echo "Exit code: $COMMAND_RC" >>"$SUMMARY_LOG"

exit "$COMMAND_RC"

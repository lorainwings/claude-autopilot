#!/usr/bin/env bash
# write-phase-progress.sh
# Lightweight sub-step progress tracker for crash recovery granularity.
# Called from main thread (synchronous Bash) at key checkpoints within each phase.
#
# Usage: write-phase-progress.sh <phase> <step> <status> [payload_json]
#   phase: 1-7
#   step: sub-step identifier (e.g. "research_dispatched", "gate_passed", "agent_complete")
#   status: "in_progress" | "complete" | "skipped"
#   payload_json: optional JSON with extra context
#
# Output: Atomic overwrite of {phase_results}/phase-{N}-progress.json
# Exit: Always 0 (informational, never blocks orchestration)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

PHASE="${1:-}"
STEP="${2:-}"
STATUS="${3:-in_progress}"
PAYLOAD_JSON="${4:-}"
[ -z "$PAYLOAD_JSON" ] && PAYLOAD_JSON='{}'

if [ -z "$PHASE" ] || [ -z "$STEP" ]; then
  echo "Usage: write-phase-progress.sh <phase> <step> <status> [payload_json]" >&2
  exit 0 # Never block
fi

# --- Find active change directory (unified resolution) ---
ACTIVE_CHANGE=$(resolve_active_change_dir) || exit 0
PHASE_RESULTS_DIR="$ACTIVE_CHANGE/context/phase-results"
mkdir -p "$PHASE_RESULTS_DIR" 2>/dev/null || true

PROGRESS_FILE="$PHASE_RESULTS_DIR/phase-${PHASE}-progress.json"

# --- Generate ISO-8601 timestamp ---
TIMESTAMP=$(python3 -c "from datetime import datetime,timezone; print(datetime.now(timezone.utc).isoformat())" 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%SZ")

# --- Atomic write via tmp + mv ---
PROGRESS_TMP="${PROGRESS_FILE}.tmp"

python3 -c "
import json, sys

progress = {
    'phase': int(sys.argv[1]),
    'step': sys.argv[2],
    'status': sys.argv[3],
    'timestamp': sys.argv[4],
}

# Merge payload
try:
    extra = json.loads(sys.argv[5]) if sys.argv[5] else {}
    if isinstance(extra, dict):
        progress['payload'] = extra
except (json.JSONDecodeError, ValueError):
    progress['payload'] = {}

with open(sys.argv[6], 'w') as f:
    json.dump(progress, f, ensure_ascii=False, indent=2)
" "$PHASE" "$STEP" "$STATUS" "$TIMESTAMP" "$PAYLOAD_JSON" "$PROGRESS_TMP" 2>/dev/null

if [ -f "$PROGRESS_TMP" ]; then
  mv "$PROGRESS_TMP" "$PROGRESS_FILE" 2>/dev/null || true
else
  echo "WARNING: write-phase-progress.sh failed to create progress file for phase $PHASE step $STEP" >&2
fi

exit 0

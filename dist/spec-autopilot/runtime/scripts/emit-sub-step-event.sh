#!/usr/bin/env bash
# emit-sub-step-event.sh — Phase 0-4 细粒度子步骤事件发射器
# 用法: emit-sub-step-event.sh <phase> <step_id> <step_label> [payload_json]
#
# 事件类型: sub_step
# payload: { step_id, step_label, step_index, total_steps, ...extra }
#
# Output: Appends one JSON line to logs/events.jsonl AND prints to stdout

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

PHASE="${1:-}"
STEP_ID="${2:-}"
STEP_LABEL="${3:-}"
PAYLOAD_JSON="${4:-}"
[ -z "$PAYLOAD_JSON" ] && PAYLOAD_JSON='{}'

if [ -z "$PHASE" ] || [ -z "$STEP_ID" ] || [ -z "$STEP_LABEL" ]; then
  echo "Usage: emit-sub-step-event.sh <phase> <step_id> <step_label> [payload_json]" >&2
  exit 1
fi

# Determine project root
PROJECT_ROOT="${PROJECT_ROOT_QUICK:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

# Guard: no active autopilot → silent exit
if ! has_active_autopilot "$PROJECT_ROOT"; then
  exit 0
fi

# Generate ISO-8601 timestamp
TIMESTAMP=$(python3 -c "from datetime import datetime,timezone; print(datetime.now(timezone.utc).isoformat())" 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%SZ")

# --- Resolve GUI context fields ---
LOCK_FILE="$PROJECT_ROOT/openspec/changes/.autopilot-active"

# change_name: env var > lock file > "unknown"
CHANGE_NAME="${AUTOPILOT_CHANGE_NAME:-}"
[ -z "$CHANGE_NAME" ] && CHANGE_NAME=$(read_lock_json_field "$LOCK_FILE" "change" "unknown")

# session_id: env var > lock file > timestamp fallback
SESSION_ID="${AUTOPILOT_SESSION_ID:-}"
[ -z "$SESSION_ID" ] && SESSION_ID=$(read_lock_json_field "$LOCK_FILE" "session_id" "")
[ -z "$SESSION_ID" ] && SESSION_ID=$(python3 -c "import time; print(int(time.time()*1000))" 2>/dev/null || date +%s)

# Resolve mode from env or default
MODE="${AUTOPILOT_MODE:-full}"

# phase_label: static mapping
PHASE_LABEL=$(get_phase_label "$PHASE")

# total_phases: mode-dependent
TOTAL_PHASES=$(get_total_phases "$MODE")

# sequence: auto-increment
SEQUENCE=$(next_event_sequence "$PROJECT_ROOT")

# Construct sub_step event JSON
EVENT_JSON=$(python3 -c "
import json, sys

event = {
    'type': 'sub_step',
    'phase': int(sys.argv[1]),
    'mode': sys.argv[2],
    'timestamp': sys.argv[3],
    'change_name': sys.argv[4],
    'session_id': sys.argv[5],
    'phase_label': sys.argv[6],
    'total_phases': int(sys.argv[7]),
    'sequence': int(sys.argv[8]),
    'payload': {
        'step_id': sys.argv[9],
        'step_label': sys.argv[10],
    }
}

# Merge optional extra payload
try:
    extra = json.loads(sys.argv[11]) if len(sys.argv) > 11 and sys.argv[11] else {}
    if isinstance(extra, dict):
        # Extract step_index / total_steps from extra if provided
        if 'step_index' in extra:
            event['payload']['step_index'] = extra.pop('step_index')
        if 'total_steps' in extra:
            event['payload']['total_steps'] = extra.pop('total_steps')
        # Merge remaining extra fields
        event['payload'].update(extra)
except (json.JSONDecodeError, ValueError):
    pass

print(json.dumps(event, ensure_ascii=False))
" "$PHASE" "$MODE" "$TIMESTAMP" "$CHANGE_NAME" "$SESSION_ID" "$PHASE_LABEL" "$TOTAL_PHASES" "$SEQUENCE" "$STEP_ID" "$STEP_LABEL" "$PAYLOAD_JSON" 2>/dev/null)

if [ -z "$EVENT_JSON" ]; then
  echo "ERROR: Failed to construct sub_step event JSON" >&2
  exit 1
fi

# Output to stdout (for CLI consumers)
echo "$EVENT_JSON"

# Append to events.jsonl log file
EVENTS_DIR="$PROJECT_ROOT/logs"
EVENTS_FILE="$EVENTS_DIR/events.jsonl"

mkdir -p "$EVENTS_DIR" 2>/dev/null || true
echo "$EVENT_JSON" >>"$EVENTS_FILE" 2>/dev/null || true

exit 0

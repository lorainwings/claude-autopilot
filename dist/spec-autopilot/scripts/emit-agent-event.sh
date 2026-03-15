#!/usr/bin/env bash
# emit-agent-event.sh
# Agent lifecycle event emitter — dispatched/completed events
# Usage:
#   emit-agent-event.sh <event_type> <phase> <mode> <agent_id> <agent_label> [payload_json]
#   event_type: agent_dispatch | agent_complete
#   phase: 0-7
#   mode: full | lite | minimal
#   agent_id: unique agent identifier (e.g. "phase2-openspec", "phase5-task-3-auth")
#   agent_label: human-readable label (e.g. "OpenSpec 生成")
#   payload_json: optional JSON with extra fields (background, status, summary, duration_ms)
#
# Output: Appends one JSON line to logs/events.jsonl AND prints to stdout

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

EVENT_TYPE="${1:-}"
PHASE="${2:-}"
MODE="${3:-full}"
AGENT_ID="${4:-}"
AGENT_LABEL="${5:-}"
PAYLOAD_JSON="${6:-}"
[ -z "$PAYLOAD_JSON" ] && PAYLOAD_JSON='{}'

if [ -z "$EVENT_TYPE" ] || [ -z "$PHASE" ] || [ -z "$AGENT_ID" ] || [ -z "$AGENT_LABEL" ]; then
  echo "Usage: emit-agent-event.sh <event_type> <phase> <mode> <agent_id> <agent_label> [payload_json]" >&2
  exit 1
fi

# Validate event_type
case "$EVENT_TYPE" in
  agent_dispatch|agent_complete) ;;
  *)
    echo "ERROR: Invalid event_type '$EVENT_TYPE'. Must be: agent_dispatch|agent_complete" >&2
    exit 1
    ;;
esac

# Generate ISO-8601 timestamp
TIMESTAMP=$(python3 -c "from datetime import datetime,timezone; print(datetime.now(timezone.utc).isoformat())" 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%SZ")

# Determine project root
PROJECT_ROOT="${PROJECT_ROOT_QUICK:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

# --- Resolve GUI context fields ---
LOCK_FILE="$PROJECT_ROOT/openspec/changes/.autopilot-active"

CHANGE_NAME="${AUTOPILOT_CHANGE_NAME:-}"
[ -z "$CHANGE_NAME" ] && CHANGE_NAME=$(read_lock_json_field "$LOCK_FILE" "change" "unknown")

SESSION_ID="${AUTOPILOT_SESSION_ID:-}"
[ -z "$SESSION_ID" ] && SESSION_ID=$(read_lock_json_field "$LOCK_FILE" "session_id" "")
[ -z "$SESSION_ID" ] && SESSION_ID=$(python3 -c "import time; print(int(time.time()*1000))" 2>/dev/null || date +%s)

PHASE_LABEL=$(get_phase_label "$PHASE")
TOTAL_PHASES=$(get_total_phases "$MODE")
SEQUENCE=$(next_event_sequence "$PROJECT_ROOT")

# Construct event JSON
EVENT_JSON=$(python3 -c "
import json, sys

event = {
    'type': sys.argv[1],
    'phase': int(sys.argv[2]),
    'mode': sys.argv[3],
    'timestamp': sys.argv[4],
    'change_name': sys.argv[5],
    'session_id': sys.argv[6],
    'phase_label': sys.argv[7],
    'total_phases': int(sys.argv[8]),
    'sequence': int(sys.argv[9]),
    'payload': {
        'agent_id': sys.argv[10],
        'agent_label': sys.argv[11],
    }
}

# Merge extra payload fields
try:
    extra = json.loads(sys.argv[12]) if len(sys.argv) > 12 and sys.argv[12] else {}
    if isinstance(extra, dict):
        event['payload'].update(extra)
except (json.JSONDecodeError, ValueError):
    pass

print(json.dumps(event, ensure_ascii=False))
" "$EVENT_TYPE" "$PHASE" "$MODE" "$TIMESTAMP" "$CHANGE_NAME" "$SESSION_ID" "$PHASE_LABEL" "$TOTAL_PHASES" "$SEQUENCE" "$AGENT_ID" "$AGENT_LABEL" "$PAYLOAD_JSON" 2>/dev/null)

if [ -z "$EVENT_JSON" ]; then
  echo "ERROR: Failed to construct event JSON" >&2
  exit 1
fi

# Output to stdout (for CLI consumers)
echo "$EVENT_JSON"

# Append to events.jsonl log file
EVENTS_DIR="$PROJECT_ROOT/logs"
EVENTS_FILE="$EVENTS_DIR/events.jsonl"

mkdir -p "$EVENTS_DIR" 2>/dev/null || true
echo "$EVENT_JSON" >> "$EVENTS_FILE" 2>/dev/null || true

exit 0

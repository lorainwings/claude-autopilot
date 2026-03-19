#!/usr/bin/env bash
# emit-phase-event.sh
# v5.0 Event Schema Upgrade — Phase 生命周期事件发射器
# Purpose: 在 Phase 开始/结束时输出结构化 JSON 事件到 events.jsonl
# Usage:
#   emit-phase-event.sh <event_type> <phase> <mode> [payload_json]
#   event_type: phase_start | phase_end | error | gate_decision_pending | gate_decision_received
#   phase: 0-7
#   mode: full | lite | minimal
#   payload_json: optional JSON string with status, duration_ms, artifacts, error_message
#
# v5.0 新增字段: change_name, session_id, phase_label, total_phases, sequence
# 从锁文件或环境变量 AUTOPILOT_CHANGE_NAME / AUTOPILOT_SESSION_ID 获取上下文
#
# Output: Appends one JSON line to logs/events.jsonl AND prints to stdout

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

EVENT_TYPE="${1:-}"
PHASE="${2:-}"
MODE="${3:-full}"
PAYLOAD_JSON="${4:-}"
[ -z "$PAYLOAD_JSON" ] && PAYLOAD_JSON='{}'

if [ -z "$EVENT_TYPE" ] || [ -z "$PHASE" ]; then
  echo "Usage: emit-phase-event.sh <event_type> <phase> <mode> [payload_json]" >&2
  exit 1
fi

# Validate event_type
case "$EVENT_TYPE" in
  phase_start | phase_end | error | gate_decision_pending | gate_decision_received) ;;
  *)
    echo "ERROR: Invalid event_type '$EVENT_TYPE'. Must be: phase_start|phase_end|error" >&2
    exit 1
    ;;
esac

# Generate ISO-8601 timestamp
TIMESTAMP=$(python3 -c "from datetime import datetime,timezone; print(datetime.now(timezone.utc).isoformat())" 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%SZ")

# Determine project root
PROJECT_ROOT="${PROJECT_ROOT_QUICK:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

# --- v5.0: Resolve GUI context fields ---
LOCK_FILE="$PROJECT_ROOT/openspec/changes/.autopilot-active"

# change_name: env var > lock file > "unknown"
CHANGE_NAME="${AUTOPILOT_CHANGE_NAME:-}"
[ -z "$CHANGE_NAME" ] && CHANGE_NAME=$(read_lock_json_field "$LOCK_FILE" "change" "unknown")

# session_id: env var > lock file > timestamp fallback
SESSION_ID="${AUTOPILOT_SESSION_ID:-}"
[ -z "$SESSION_ID" ] && SESSION_ID=$(read_lock_json_field "$LOCK_FILE" "session_id" "")
[ -z "$SESSION_ID" ] && SESSION_ID=$(python3 -c "import time; print(int(time.time()*1000))" 2>/dev/null || date +%s)

# phase_label: static mapping
PHASE_LABEL=$(get_phase_label "$PHASE")

# total_phases: mode-dependent
TOTAL_PHASES=$(get_total_phases "$MODE")

# sequence: auto-increment
SEQUENCE=$(next_event_sequence "$PROJECT_ROOT")

# Construct event JSON with v5.0 enhanced fields
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
    'payload': {}
}

# Parse optional payload
try:
    payload = json.loads(sys.argv[10]) if len(sys.argv) > 10 and sys.argv[10] else {}
    if isinstance(payload, dict):
        event['payload'] = payload
except (json.JSONDecodeError, ValueError):
    pass

print(json.dumps(event, ensure_ascii=False))
" "$EVENT_TYPE" "$PHASE" "$MODE" "$TIMESTAMP" "$CHANGE_NAME" "$SESSION_ID" "$PHASE_LABEL" "$TOTAL_PHASES" "$SEQUENCE" "$PAYLOAD_JSON" 2>/dev/null)

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
echo "$EVENT_JSON" >>"$EVENTS_FILE" 2>/dev/null || true

exit 0

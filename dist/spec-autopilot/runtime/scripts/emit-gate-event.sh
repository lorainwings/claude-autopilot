#!/usr/bin/env bash
# emit-gate-event.sh
# v5.0 Event Schema Upgrade — Gate 判定事件发射器
# Purpose: 在门禁通过/阻断时输出结构化 JSON 事件到 events.jsonl
# Usage:
#   emit-gate-event.sh <event_type> <phase> <mode> [payload_json]
#   event_type: gate_pass | gate_block | gate_step
#   phase: 0-7 (gate_pass/gate_block)
#   For gate_step: emit-gate-event.sh gate_step <phase> <step_index> <step_name> <step_result> [step_detail]
#   mode: full | lite | minimal
#   payload_json: optional JSON with gate_score, status, error_message
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
  echo "Usage: emit-gate-event.sh <event_type> <phase> <mode> [payload_json]" >&2
  exit 1
fi

# Validate event_type
case "$EVENT_TYPE" in
  gate_pass | gate_block | gate_step) ;;
  *)
    echo "ERROR: Invalid event_type '$EVENT_TYPE'. Must be: gate_pass|gate_block|gate_step" >&2
    exit 1
    ;;
esac

# --- gate_step mode: emit-gate-event.sh gate_step <phase> <step_index> <step_name> <step_result> [step_detail] ---
if [ "$EVENT_TYPE" = "gate_step" ]; then
  GATE_PHASE="${2:-0}"
  STEP_INDEX="${3:-}"
  STEP_NAME="${4:-}"
  STEP_RESULT="${5:-}"
  STEP_DETAIL="${6:-}"
  MODE="${AUTOPILOT_MODE:-full}"

  if [ -z "$STEP_INDEX" ] || [ -z "$STEP_NAME" ] || [ -z "$STEP_RESULT" ]; then
    echo "Usage: emit-gate-event.sh gate_step <phase> <step_index> <step_name> <step_result> [step_detail]" >&2
    echo "  Set AUTOPILOT_GATE_PHASE and AUTOPILOT_MODE env vars for context" >&2
    exit 1
  fi

  TIMESTAMP=$(python3 -c "from datetime import datetime,timezone; print(datetime.now(timezone.utc).isoformat())" 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%SZ")
  PROJECT_ROOT="${PROJECT_ROOT_QUICK:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
  LOCK_FILE="$PROJECT_ROOT/openspec/changes/.autopilot-active"

  CHANGE_NAME="${AUTOPILOT_CHANGE_NAME:-}"
  [ -z "$CHANGE_NAME" ] && CHANGE_NAME=$(read_lock_json_field "$LOCK_FILE" "change" "unknown")
  SESSION_ID="${AUTOPILOT_SESSION_ID:-}"
  [ -z "$SESSION_ID" ] && SESSION_ID=$(read_lock_json_field "$LOCK_FILE" "session_id" "")
  [ -z "$SESSION_ID" ] && SESSION_ID=$(python3 -c "import time; print(int(time.time()*1000))" 2>/dev/null || date +%s)

  PHASE_LABEL=$(get_phase_label "$GATE_PHASE")
  TOTAL_PHASES=$(get_total_phases "$MODE")
  SEQUENCE=$(next_event_sequence "$PROJECT_ROOT")

  EVENT_JSON=$(python3 -c "
import json, sys
event = {
    'type': 'gate_step',
    'phase': int(sys.argv[1]),
    'mode': sys.argv[2],
    'timestamp': sys.argv[3],
    'change_name': sys.argv[4],
    'session_id': sys.argv[5],
    'phase_label': sys.argv[6],
    'total_phases': int(sys.argv[7]),
    'sequence': int(sys.argv[8]),
    'payload': {
        'step_index': int(sys.argv[9]),
        'step_name': sys.argv[10],
        'step_result': sys.argv[11],
    }
}
if sys.argv[12]:
    event['payload']['step_detail'] = sys.argv[12]
print(json.dumps(event, ensure_ascii=False))
" "$GATE_PHASE" "$MODE" "$TIMESTAMP" "$CHANGE_NAME" "$SESSION_ID" "$PHASE_LABEL" "$TOTAL_PHASES" "$SEQUENCE" "$STEP_INDEX" "$STEP_NAME" "$STEP_RESULT" "$STEP_DETAIL" 2>/dev/null)

  if [ -z "$EVENT_JSON" ]; then
    echo "ERROR: Failed to construct gate_step event JSON" >&2
    exit 1
  fi

  echo "$EVENT_JSON"
  EVENTS_DIR="$PROJECT_ROOT/logs"
  EVENTS_FILE="$EVENTS_DIR/events.jsonl"
  mkdir -p "$EVENTS_DIR" 2>/dev/null || true
  echo "$EVENT_JSON" >>"$EVENTS_FILE" 2>/dev/null || true
  exit 0
fi

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
GATE_STEPS_JSON="${GATE_STEPS_JSON:-}"
EVENT_JSON=$(python3 -c "
import json, sys, os

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

# Merge optional steps array from env
steps_json = os.environ.get('GATE_STEPS_JSON', '')
if steps_json:
    try:
        steps = json.loads(steps_json)
        if isinstance(steps, list):
            event['payload']['steps'] = steps
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

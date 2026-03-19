#!/usr/bin/env bash
# emit-task-progress.sh
# v5.2 Phase 5 细粒度进度事件发射器
# Purpose: 在 Phase 5 每个 task 完成后发射 task_progress 事件到 events.jsonl
# Usage:
#   emit-task-progress.sh <task_name> <status> <task_index> <task_total> <mode> [tdd_step] [retry_count]
#   task_name: task 标识（如 "task-1-add-login"）
#   status: running | passed | failed | retrying
#   task_index: 当前 task 序号（1-based）
#   task_total: task 总数
#   mode: full | lite | minimal
#   tdd_step: (optional) red | green | refactor
#   retry_count: (optional) 重试次数
#
# Output: Appends one JSON line to logs/events.jsonl AND prints to stdout

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

TASK_NAME="${1:-}"
STATUS="${2:-}"
TASK_INDEX="${3:-}"
TASK_TOTAL="${4:-}"
MODE="${5:-full}"
TDD_STEP="${6:-}"
RETRY_COUNT="${7:-0}"

if [ -z "$TASK_NAME" ] || [ -z "$STATUS" ] || [ -z "$TASK_INDEX" ] || [ -z "$TASK_TOTAL" ]; then
  echo "Usage: emit-task-progress.sh <task_name> <status> <task_index> <task_total> <mode> [tdd_step] [retry_count]" >&2
  exit 1
fi

# Validate status
case "$STATUS" in
  running | passed | failed | retrying) ;;
  *)
    echo "ERROR: Invalid status '$STATUS'. Must be: running|passed|failed|retrying" >&2
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

PHASE_LABEL=$(get_phase_label "5")
TOTAL_PHASES=$(get_total_phases "$MODE")
SEQUENCE=$(next_event_sequence "$PROJECT_ROOT")

# Construct task_progress event JSON
EVENT_JSON=$(python3 -c "
import json, sys

event = {
    'type': 'task_progress',
    'phase': 5,
    'mode': sys.argv[1],
    'timestamp': sys.argv[2],
    'change_name': sys.argv[3],
    'session_id': sys.argv[4],
    'phase_label': sys.argv[5],
    'total_phases': int(sys.argv[6]),
    'sequence': int(sys.argv[7]),
    'payload': {
        'task_name': sys.argv[8],
        'status': sys.argv[9],
        'task_index': int(sys.argv[10]),
        'task_total': int(sys.argv[11]),
    }
}

# Optional TDD step
if sys.argv[12]:
    event['payload']['tdd_step'] = sys.argv[12]

# Optional retry count
retry = int(sys.argv[13]) if sys.argv[13] else 0
if retry > 0:
    event['payload']['retry_count'] = retry

print(json.dumps(event, ensure_ascii=False))
" "$MODE" "$TIMESTAMP" "$CHANGE_NAME" "$SESSION_ID" "$PHASE_LABEL" "$TOTAL_PHASES" "$SEQUENCE" "$TASK_NAME" "$STATUS" "$TASK_INDEX" "$TASK_TOTAL" "$TDD_STEP" "$RETRY_COUNT" 2>/dev/null)

if [ -z "$EVENT_JSON" ]; then
  echo "ERROR: Failed to construct task_progress event JSON" >&2
  exit 1
fi

# Output to stdout
echo "$EVENT_JSON"

# Append to events.jsonl
EVENTS_DIR="$PROJECT_ROOT/logs"
EVENTS_FILE="$EVENTS_DIR/events.jsonl"

mkdir -p "$EVENTS_DIR" 2>/dev/null || true
echo "$EVENT_JSON" >>"$EVENTS_FILE" 2>/dev/null || true

exit 0

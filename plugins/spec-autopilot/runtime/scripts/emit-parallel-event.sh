#!/usr/bin/env bash
# emit-parallel-event.sh
# 发射并行调度相关事件到 events.jsonl
# 支持六种事件类型:
#   parallel_plan / parallel_batch_start / parallel_batch_end
#   parallel_task_ready / parallel_task_blocked / parallel_fallback
#
# Usage:
#   emit-parallel-event.sh <project_root> <phase> <mode> <event_type> <payload_json>
#
# Args:
#   project_root: 项目根目录
#   phase: 阶段编号 (1-7)
#   mode: 执行模式 (full/lite/minimal)
#   event_type: 事件类型 (parallel_plan|parallel_batch_start|parallel_batch_end|parallel_task_ready|parallel_task_blocked|parallel_fallback)
#   payload_json: JSON 格式的事件载荷
#
# Output: JSON event on stdout + appended to logs/events.jsonl

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

PROJECT_ROOT="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
PHASE="${2:-5}"
MODE="${3:-full}"
EVENT_TYPE="${4:-parallel_plan}"
PAYLOAD_JSON="${5:-"{}"}"

# 校验事件类型
case "$EVENT_TYPE" in
  parallel_plan|parallel_batch_start|parallel_batch_end|parallel_task_ready|parallel_task_blocked|parallel_fallback) ;;
  *) echo "ERROR: 不支持的事件类型: $EVENT_TYPE (仅支持 parallel_plan/parallel_batch_start/parallel_batch_end/parallel_task_ready/parallel_task_blocked/parallel_fallback)" >&2; exit 1 ;;
esac

# 生成 ISO-8601 时间戳
TIMESTAMP=$(python3 -c "from datetime import datetime,timezone; print(datetime.now(timezone.utc).isoformat())" 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%SZ")

# 解析 GUI 上下文字段
LOCK_FILE="$PROJECT_ROOT/openspec/changes/.autopilot-active"

CHANGE_NAME="${AUTOPILOT_CHANGE_NAME:-}"
[ -z "$CHANGE_NAME" ] && CHANGE_NAME=$(read_lock_json_field "$LOCK_FILE" "change" "unknown")

SESSION_ID="${AUTOPILOT_SESSION_ID:-}"
[ -z "$SESSION_ID" ] && SESSION_ID=$(read_lock_json_field "$LOCK_FILE" "session_id" "")
[ -z "$SESSION_ID" ] && SESSION_ID=$(python3 -c "import time; print(int(time.time()*1000))" 2>/dev/null || date +%s)

PHASE_LABEL=$(get_phase_label "$PHASE")
TOTAL_PHASES=$(get_total_phases "$MODE")
SEQUENCE=$(next_event_sequence "$PROJECT_ROOT")

# 构造结构化事件 JSON
EVENT_JSON=$(python3 -c "
import json, sys

event_type = sys.argv[1]
phase = int(sys.argv[2])
mode = sys.argv[3]
timestamp = sys.argv[4]
change_name = sys.argv[5]
session_id = sys.argv[6]
phase_label = sys.argv[7]
total_phases = int(sys.argv[8])
sequence = int(sys.argv[9])
payload_str = sys.argv[10]

# 解析 payload
try:
    payload = json.loads(payload_str)
except (json.JSONDecodeError, ValueError):
    payload = {}

event = {
    'type': event_type,
    'phase': phase,
    'mode': mode,
    'timestamp': timestamp,
    'change_name': change_name,
    'session_id': session_id,
    'phase_label': phase_label,
    'total_phases': total_phases,
    'sequence': sequence,
    'payload': payload,
}

print(json.dumps(event, ensure_ascii=False))
" "$EVENT_TYPE" "$PHASE" "$MODE" "$TIMESTAMP" "$CHANGE_NAME" "$SESSION_ID" "$PHASE_LABEL" "$TOTAL_PHASES" "$SEQUENCE" "$PAYLOAD_JSON" 2>/dev/null)

if [ -z "$EVENT_JSON" ]; then
  echo "ERROR: 构造 $EVENT_TYPE 事件 JSON 失败" >&2
  exit 1
fi

# 输出到 stdout
echo "$EVENT_JSON"

# 追加到 events.jsonl
EVENTS_DIR="$PROJECT_ROOT/logs"
EVENTS_FILE="$EVENTS_DIR/events.jsonl"
mkdir -p "$EVENTS_DIR" 2>/dev/null || true
echo "$EVENT_JSON" >>"$EVENTS_FILE" 2>/dev/null || true

exit 0

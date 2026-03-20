#!/usr/bin/env bash
# emit-model-routing-event.sh
# 发射结构化模型路由证据事件到 events.jsonl
#
# Usage:
#   emit-model-routing-event.sh <project_root> <phase> <mode> <routing_json> [agent_id]
#
# Args:
#   project_root: 项目根目录
#   phase: 阶段编号 (1-7)
#   mode: 执行模式 (full/lite/minimal)
#   routing_json: resolve-model-routing.sh 的 JSON 输出
#   agent_id: 可选的 agent 标识符
#
# Output: JSON event on stdout + appended to logs/events.jsonl

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

PROJECT_ROOT="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
PHASE="${2:-0}"
MODE="${3:-full}"
ROUTING_JSON="${4:-{}}"
AGENT_ID="${5:-}"

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

phase = int(sys.argv[1])
mode = sys.argv[2]
timestamp = sys.argv[3]
change_name = sys.argv[4]
session_id = sys.argv[5]
phase_label = sys.argv[6]
total_phases = int(sys.argv[7])
sequence = int(sys.argv[8])
routing_json_str = sys.argv[9]
agent_id = sys.argv[10] if len(sys.argv) > 10 and sys.argv[10] else ''

# 解析路由结果
try:
    routing = json.loads(routing_json_str)
except (json.JSONDecodeError, ValueError):
    routing = {}

event = {
    'type': 'model_routing',
    'phase': phase,
    'mode': mode,
    'timestamp': timestamp,
    'change_name': change_name,
    'session_id': session_id,
    'phase_label': phase_label,
    'total_phases': total_phases,
    'sequence': sequence,
    'payload': {
        'selected_tier': routing.get('selected_tier', 'standard'),
        'selected_model': routing.get('selected_model', 'sonnet'),
        'selected_effort': routing.get('selected_effort', 'medium'),
        'routing_reason': routing.get('routing_reason', ''),
        'escalated_from': routing.get('escalated_from'),
        'fallback_applied': routing.get('fallback_applied', False),
    }
}

if agent_id:
    event['payload']['agent_id'] = agent_id

print(json.dumps(event, ensure_ascii=False))
" "$PHASE" "$MODE" "$TIMESTAMP" "$CHANGE_NAME" "$SESSION_ID" "$PHASE_LABEL" "$TOTAL_PHASES" "$SEQUENCE" "$ROUTING_JSON" "$AGENT_ID" 2>/dev/null)

if [ -z "$EVENT_JSON" ]; then
  echo "ERROR: 构造 model_routing 事件 JSON 失败" >&2
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

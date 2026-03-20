#!/usr/bin/env bash
# emit-model-routing-event.sh
# 发射结构化模型路由证据事件到 events.jsonl
# 支持三种事件类型: model_routing / model_effective / model_fallback (v5.4)
#
# Usage:
#   emit-model-routing-event.sh <project_root> <phase> <mode> <routing_json> [agent_id] [event_type]
#
# Args:
#   project_root: 项目根目录
#   phase: 阶段编号 (1-7)
#   mode: 执行模式 (full/lite/minimal)
#   routing_json: resolve-model-routing.sh 的 JSON 输出（或 model_effective/model_fallback payload）
#   agent_id: 可选的 agent 标识符
#   event_type: 可选，默认 "model_routing"，可为 "model_effective" 或 "model_fallback"
#
# Output: JSON event on stdout + appended to logs/events.jsonl

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

PROJECT_ROOT="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
PHASE="${2:-0}"
MODE="${3:-full}"
ROUTING_JSON="${4:-"{}"}"
AGENT_ID="${5:-}"
EVENT_TYPE="${6:-model_routing}"

# 校验事件类型
case "$EVENT_TYPE" in
  model_routing | model_effective | model_fallback) ;;
  *)
    echo "ERROR: 不支持的事件类型: $EVENT_TYPE (仅支持 model_routing/model_effective/model_fallback)" >&2
    exit 1
    ;;
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
routing_json_str = sys.argv[10]
agent_id = sys.argv[11] if len(sys.argv) > 11 and sys.argv[11] else ''

# 解析路由结果
try:
    routing = json.loads(routing_json_str)
except (json.JSONDecodeError, ValueError):
    routing = {}

# 根据事件类型构造不同的 payload
if event_type == 'model_routing':
    payload = {
        'selected_tier': routing.get('selected_tier', 'standard'),
        'selected_model': routing.get('selected_model', 'sonnet'),
        'selected_effort': routing.get('selected_effort', 'medium'),
        'routing_reason': routing.get('routing_reason', ''),
        'escalated_from': routing.get('escalated_from'),
        'fallback_applied': routing.get('fallback_applied', False),
        'fallback_model': routing.get('fallback_model'),
    }
elif event_type == 'model_effective':
    payload = {
        'effective_model': routing.get('effective_model', 'unknown'),
        'effective_tier': routing.get('effective_tier', 'unknown'),
        'inference_source': routing.get('inference_source', 'statusline'),
        'requested_model': routing.get('requested_model', ''),
        'match': routing.get('match', False),
    }
elif event_type == 'model_fallback':
    payload = {
        'requested_model': routing.get('requested_model', ''),
        'fallback_model': routing.get('fallback_model', 'sonnet'),
        'fallback_reason': routing.get('fallback_reason', ''),
    }
else:
    payload = routing

if agent_id:
    payload['agent_id'] = agent_id

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
" "$EVENT_TYPE" "$PHASE" "$MODE" "$TIMESTAMP" "$CHANGE_NAME" "$SESSION_ID" "$PHASE_LABEL" "$TOTAL_PHASES" "$SEQUENCE" "$ROUTING_JSON" "$AGENT_ID" 2>/dev/null)

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

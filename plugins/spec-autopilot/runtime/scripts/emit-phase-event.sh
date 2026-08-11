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

EVENTS_DIR="$PROJECT_ROOT/logs"
EVENTS_FILE="$EVENTS_DIR/events.jsonl"

# --- Idempotency guard for phase_start ---
# 恢复场景（"从断点继续"分支不截断 events.jsonl）下，Phase 0 bootstrap 会二次
# 发射 phase_start，使同一 phase 在事件流里出现多次，GUI 进度随之错乱。
# 判定键为 (session_id, type, phase)：同一会话同一 phase 只允许一条 phase_start。
if [ "$EVENT_TYPE" = "phase_start" ] && [ -f "$EVENTS_FILE" ]; then
  if _EF="$EVENTS_FILE" _SID="$SESSION_ID" _PH="$PHASE" python3 -c '
import json, os, sys
path, sid, phase = os.environ["_EF"], os.environ["_SID"], os.environ["_PH"]
try:
    phase_i = int(phase)
except ValueError:
    sys.exit(1)
try:
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                ev = json.loads(line)
            except ValueError:
                continue
            if (
                ev.get("type") == "phase_start"
                and ev.get("phase") == phase_i
                and str(ev.get("session_id", "")) == sid
            ):
                sys.exit(0)  # duplicate found
except OSError:
    pass
sys.exit(1)
' 2>/dev/null; then
    # 已存在同会话同 phase 的 phase_start —— 输出既有语义结果但不重复落盘
    echo "$EVENT_JSON"
    exit 0
  fi
fi

# Output to stdout (for CLI consumers)
echo "$EVENT_JSON"

# Append to events.jsonl log file
mkdir -p "$EVENTS_DIR" 2>/dev/null || true
echo "$EVENT_JSON" >>"$EVENTS_FILE" 2>/dev/null || true

# --- Dispatch sentinel (P7: persist the decision, not the capability) ---
# 门禁此前只认模型自己写进 prompt 的 `<!-- autopilot-phase:N -->` 标记；
# 模型漏写标记，L2 就整体静默失效。phase_start 是编排器进入每个 phase 的必经
# 调用，把 sentinel 写入挂在这里，使"本次派发应受审"成为确定性事实而非
# 依赖模型记得加注释。带 phase + session + 时间戳，供门禁做新鲜度判定。
if [ "$EVENT_TYPE" = "phase_start" ]; then
  SENTINEL_FILE="$PROJECT_ROOT/openspec/changes/.autopilot-dispatch-sentinel.json"
  if [ -d "$PROJECT_ROOT/openspec/changes" ]; then
    _SF="$SENTINEL_FILE" _PH="$PHASE" _MODE="$MODE" _SID="$SESSION_ID" _CN="$CHANGE_NAME" python3 -c '
import json, os, tempfile
from datetime import datetime, timezone
path = os.environ["_SF"]
data = {
    "phase": int(os.environ["_PH"]) if os.environ["_PH"].isdigit() else os.environ["_PH"],
    "mode": os.environ["_MODE"],
    "session_id": os.environ["_SID"],
    "change_name": os.environ["_CN"],
    "written_at": datetime.now(timezone.utc).isoformat(),
}
d = os.path.dirname(path)
fd, tmp = tempfile.mkstemp(dir=d, prefix=".sentinel-", suffix=".tmp")
try:
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False)
    os.replace(tmp, path)
except Exception:
    try:
        os.unlink(tmp)
    except OSError:
        pass
' 2>/dev/null || true
  fi
fi

exit 0

#!/usr/bin/env bash
# generate-dispatch-actual.sh
# Dispatch 后记录实际执行结果 — 对比 plan vs actual，输出 dispatch-actual.json。
#
# Usage:
#   generate-dispatch-actual.sh <project_root> <change_name> <actual_agent> \
#     <exit_status> [actual_artifacts_json] [actual_model] [duration_ms]
#
# Args:
#   project_root: 项目根目录
#   change_name: 变更名称 (openspec/changes/<change_name>)
#   actual_agent: 实际执行的 agent 名称
#   exit_status: agent 退出状态 ("ok" | "warning" | "blocked" | "failed")
#   actual_artifacts_json: JSON 数组，实际产出文件列表 (默认 "[]")
#   actual_model: 实际使用的模型 (默认 "unknown")
#   duration_ms: 执行耗时毫秒数 (默认 0)
#
# Output: dispatch-actual.json 路径 on stdout
# Side effect: 写入 openspec/changes/<change>/context/dispatch-actual.json

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

PROJECT_ROOT="${1:-$(resolve_project_root)}"
CHANGE_NAME="${2:-}"
ACTUAL_AGENT="${3:-}"
EXIT_STATUS="${4:-unknown}"
ACTUAL_ARTIFACTS="${5:-[]}"
ACTUAL_MODEL="${6:-unknown}"
DURATION_MS="${7:-0}"

# --- 参数校验 ---
if [ -z "$CHANGE_NAME" ]; then
  echo "ERROR: 缺少 change_name 参数" >&2
  exit 1
fi

if [ -z "$ACTUAL_AGENT" ]; then
  echo "ERROR: 缺少 actual_agent 参数" >&2
  exit 1
fi

CONTEXT_DIR="$PROJECT_ROOT/openspec/changes/$CHANGE_NAME/context"
mkdir -p "$CONTEXT_DIR" 2>/dev/null || true

OUTPUT_FILE="$CONTEXT_DIR/dispatch-actual.json"
PLAN_FILE="$CONTEXT_DIR/dispatch-plan.json"

# --- 记录实际结果并对比 plan (Python3) ---
python3 -c "
import json, sys, os
from datetime import datetime, timezone

project_root = sys.argv[1]
change_name = sys.argv[2]
actual_agent = sys.argv[3]
exit_status = sys.argv[4]
actual_artifacts_raw = sys.argv[5]
actual_model = sys.argv[6]
duration_ms = int(sys.argv[7])
output_file = sys.argv[8]
plan_file = sys.argv[9]

# 解析 JSON 参数
try:
    actual_artifacts = json.loads(actual_artifacts_raw)
except (json.JSONDecodeError, ValueError):
    actual_artifacts = []

# 读取 plan（如果存在）
plan = None
if os.path.isfile(plan_file):
    try:
        with open(plan_file) as f:
            plan = json.load(f)
    except (json.JSONDecodeError, ValueError, OSError):
        plan = None

# 对比 plan vs actual
diffs = []
if plan:
    # 对比 agent 名称
    if plan.get('resolved_agent') != actual_agent:
        diffs.append({
            'field': 'agent',
            'planned': plan.get('resolved_agent'),
            'actual': actual_agent,
        })
    # 对比模型路由
    planned_model = (plan.get('model_routing') or {}).get('selected_model')
    if planned_model and planned_model != actual_model and planned_model != 'auto':
        diffs.append({
            'field': 'model',
            'planned': planned_model,
            'actual': actual_model,
        })
    # 对比文件所有权
    planned_files = set((plan.get('ownership') or {}).get('owned_files', []))
    actual_files = set(actual_artifacts)
    out_of_scope = actual_files - planned_files if planned_files else set()
    if out_of_scope:
        diffs.append({
            'field': 'ownership',
            'planned_count': len(planned_files),
            'actual_count': len(actual_files),
            'out_of_scope': sorted(out_of_scope)[:10],
        })

# 构建 actual 记录
actual_record = {
    'actual_version': '1.0',
    'generated_at': datetime.now(timezone.utc).isoformat(),
    'change_name': change_name,
    'actual_agent': actual_agent,
    'exit_status': exit_status,
    'actual_artifacts': actual_artifacts,
    'actual_model': actual_model,
    'duration_ms': duration_ms,
    'plan_available': plan is not None,
    'diffs': diffs,
    'diff_count': len(diffs),
    'reconcile_status': 'ok' if len(diffs) == 0 else 'drift',
}

# 写入文件
with open(output_file, 'w') as f:
    json.dump(actual_record, f, ensure_ascii=False, indent=2)

# 输出文件路径
print(output_file)
" "$PROJECT_ROOT" "$CHANGE_NAME" "$ACTUAL_AGENT" "$EXIT_STATUS" \
  "$ACTUAL_ARTIFACTS" "$ACTUAL_MODEL" "$DURATION_MS" "$OUTPUT_FILE" "$PLAN_FILE"

exit $?

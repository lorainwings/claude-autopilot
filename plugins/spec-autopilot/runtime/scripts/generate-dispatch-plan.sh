#!/usr/bin/env bash
# generate-dispatch-plan.sh
# Dispatch 前生成 dispatch-plan.json — 记录请求的 agent、解析后的 agent、
# 优先级来源、文件所有权、验证器列表和模型路由信息。
#
# Usage:
#   generate-dispatch-plan.sh <project_root> <change_name> <requested_agent> \
#     [phase] [owned_files_json] [validators_json] [model_routing_json]
#
# Args:
#   project_root: 项目根目录
#   change_name: 变更名称 (openspec/changes/<change_name>)
#   requested_agent: 请求的 agent 名称
#   phase: 阶段编号 (默认 5)
#   owned_files_json: JSON 数组，拥有的文件列表 (默认 "[]")
#   validators_json: JSON 数组，需要运行的验证器 (默认 "[]")
#   model_routing_json: JSON 对象，模型路由信息 (默认 "{}")
#
# Output: dispatch-plan.json 路径 on stdout
# Side effect: 写入 openspec/changes/<change>/context/dispatch-plan.json

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

PROJECT_ROOT="${1:-$(resolve_project_root)}"
CHANGE_NAME="${2:-}"
REQUESTED_AGENT="${3:-}"
PHASE="${4:-5}"
OWNED_FILES="${5:-[]}"
VALIDATORS="${6:-[]}"
MODEL_ROUTING="${7:-{}}"

# --- 参数校验 ---
if [ -z "$CHANGE_NAME" ]; then
  echo "ERROR: 缺少 change_name 参数" >&2
  exit 1
fi

if [ -z "$REQUESTED_AGENT" ]; then
  echo "ERROR: 缺少 requested_agent 参数" >&2
  exit 1
fi

CONTEXT_DIR="$PROJECT_ROOT/openspec/changes/$CHANGE_NAME/context"
mkdir -p "$CONTEXT_DIR" 2>/dev/null || true

OUTPUT_FILE="$CONTEXT_DIR/dispatch-plan.json"

# --- Agent 解析与优先级计算 (Python3) ---
python3 -c "
import json, sys, os
from datetime import datetime, timezone

project_root = sys.argv[1]
change_name = sys.argv[2]
requested_agent = sys.argv[3]
phase = int(sys.argv[4])
owned_files_raw = sys.argv[5]
validators_raw = sys.argv[6]
model_routing_raw = sys.argv[7]
output_file = sys.argv[8]

# 解析 JSON 参数
try:
    owned_files = json.loads(owned_files_raw)
except (json.JSONDecodeError, ValueError):
    owned_files = []

try:
    validators = json.loads(validators_raw)
except (json.JSONDecodeError, ValueError):
    validators = []

try:
    model_routing = json.loads(model_routing_raw)
except (json.JSONDecodeError, ValueError):
    model_routing = {}


def resolve_agent(project_root, requested):
    \"\"\"解析 agent 名称，按优先级查找 .claude/agents 目录。\"\"\"
    # 优先级顺序: project > plugin > builtin
    search_paths = [
        ('project', os.path.join(project_root, '.claude', 'agents')),
        ('plugin', os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), 'agents')),
    ]

    resolved = requested
    priority_source = 'builtin'

    for source, agents_dir in search_paths:
        if not os.path.isdir(agents_dir):
            continue
        # 检查 <name>.md 或 <name>.yaml
        for ext in ['.md', '.yaml', '.yml']:
            agent_file = os.path.join(agents_dir, requested + ext)
            if os.path.isfile(agent_file):
                resolved = requested
                priority_source = source
                return resolved, priority_source, agent_file

    return resolved, priority_source, None


resolved_agent, priority_source, agent_file = resolve_agent(project_root, requested_agent)

# 构建 dispatch plan
plan = {
    'plan_version': '1.0',
    'generated_at': datetime.now(timezone.utc).isoformat(),
    'change_name': change_name,
    'phase': phase,
    'requested_agent': requested_agent,
    'resolved_agent': resolved_agent,
    'priority_source': priority_source,
    'agent_file': agent_file,
    'ownership': {
        'owned_files': owned_files,
        'total_owned': len(owned_files),
    },
    'validators': validators,
    'model_routing': model_routing,
}

# 写入文件
with open(output_file, 'w') as f:
    json.dump(plan, f, ensure_ascii=False, indent=2)

# 输出文件路径
print(output_file)
" "$PROJECT_ROOT" "$CHANGE_NAME" "$REQUESTED_AGENT" "$PHASE" \
  "$OWNED_FILES" "$VALIDATORS" "$MODEL_ROUTING" "$OUTPUT_FILE"

exit $?

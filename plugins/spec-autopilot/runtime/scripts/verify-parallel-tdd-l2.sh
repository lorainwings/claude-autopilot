#!/usr/bin/env bash
# verify-parallel-tdd-l2.sh — 并行 TDD per-task L2 验证
#
# 用法: verify-parallel-tdd-l2.sh --worktree-path <path> --test-command <cmd> --task-checkpoint <path>
#
# 在并行 TDD 模式下，对单个 domain agent 的 worktree 执行 L2 验证：
# 1. 读取 task checkpoint JSON 中的 tdd_cycle 字段
# 2. 验证每个 cycle: test_intent 非空、failing_signal.assertion_message 非空
# 3. 在 worktree 中执行 test_command，确认 GREEN (exit_code=0)
# 4. 输出 JSON: {"status":"ok|warn|blocked","per_task_l2":true,"cycles_verified":N,"failures":[]}
#
# 退出码: 0=ok/warn, 1=参数错误/blocked
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh
source "$SCRIPT_DIR/_common.sh"

# --- 参数解析 ---
WORKTREE_PATH=""
TEST_COMMAND=""
TASK_CHECKPOINT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --worktree-path)
      WORKTREE_PATH="$2"
      shift 2
      ;;
    --test-command)
      TEST_COMMAND="$2"
      shift 2
      ;;
    --task-checkpoint)
      TASK_CHECKPOINT="$2"
      shift 2
      ;;
    *)
      echo '{"status":"blocked","per_task_l2":false,"cycles_verified":0,"failures":["未知参数: '"$1"'"]}' >&2
      exit 1
      ;;
  esac
done

# --- 参数校验 ---
if [[ -z "$WORKTREE_PATH" || -z "$TEST_COMMAND" || -z "$TASK_CHECKPOINT" ]]; then
  echo '{"status":"blocked","per_task_l2":false,"cycles_verified":0,"failures":["缺少必需参数: --worktree-path, --test-command, --task-checkpoint"]}' >&2
  exit 1
fi

if [[ ! -d "$WORKTREE_PATH" ]]; then
  echo '{"status":"blocked","per_task_l2":false,"cycles_verified":0,"failures":["worktree 路径不存在: '"$WORKTREE_PATH"'"]}' >&2
  exit 1
fi

if [[ ! -f "$TASK_CHECKPOINT" ]]; then
  echo '{"status":"blocked","per_task_l2":false,"cycles_verified":0,"failures":["checkpoint 文件不存在: '"$TASK_CHECKPOINT"'"]}' >&2
  exit 1
fi

# --- 读取 tdd_cycle 数组 ---
TDD_CYCLES=$(python3 -c "
import json, sys
with open('$TASK_CHECKPOINT') as f:
    data = json.load(f)
cycles = data.get('tdd_cycle') or data.get('tdd_cycles') or []
if not isinstance(cycles, list):
    cycles = [cycles]
print(json.dumps(cycles))
" 2>/dev/null || echo "[]")

CYCLE_COUNT=$(python3 -c "import json; print(len(json.loads('$TDD_CYCLES')))" 2>/dev/null || echo "0")

if [[ "$CYCLE_COUNT" -eq 0 ]]; then
  echo '{"status":"warn","per_task_l2":false,"cycles_verified":0,"failures":["checkpoint 中无 tdd_cycle 数据"]}'
  exit 0
fi

# --- 验证每个 cycle 的 test_intent 和 failing_signal ---
FAILURES=$(python3 -c "
import json, sys
cycles = json.loads('$TDD_CYCLES')
failures = []
for i, c in enumerate(cycles):
    ti = c.get('test_intent', '') or ''
    fs = c.get('failing_signal') or {}
    am = fs.get('assertion_message', '') or '' if isinstance(fs, dict) else ''
    if not ti.strip():
        failures.append('cycle[%d]: test_intent 为空' % i)
    if not am.strip():
        failures.append('cycle[%d]: failing_signal.assertion_message 为空' % i)
print(json.dumps(failures))
" 2>/dev/null || echo "[]")

FAILURE_COUNT=$(python3 -c "import json; print(len(json.loads('$FAILURES')))" 2>/dev/null || echo "0")

# --- 在 worktree 中运行测试确认 GREEN ---
TEST_EXIT=0
(cd "$WORKTREE_PATH" && eval "$TEST_COMMAND") >/dev/null 2>&1 || TEST_EXIT=$?

if [[ "$TEST_EXIT" -ne 0 ]]; then
  # 测试失败 → blocked
  FAILURES=$(python3 -c "
import json
f = json.loads('$FAILURES')
f.append('worktree 测试执行失败 (exit_code=$TEST_EXIT)')
print(json.dumps(f))
" 2>/dev/null)
  FAILURE_COUNT=$(python3 -c "import json; print(len(json.loads('$FAILURES')))" 2>/dev/null || echo "1")
fi

# --- 生成结果 ---
if [[ "$TEST_EXIT" -ne 0 ]]; then
  STATUS="blocked"
  EXIT_CODE=1
elif [[ "$FAILURE_COUNT" -gt 0 ]]; then
  STATUS="warn"
  EXIT_CODE=0
else
  STATUS="ok"
  EXIT_CODE=0
fi

python3 -c "
import json
print(json.dumps({
    'status': '$STATUS',
    'per_task_l2': True,
    'cycles_verified': $CYCLE_COUNT,
    'failures': json.loads('$FAILURES')
}, ensure_ascii=False))
"

exit "$EXIT_CODE"

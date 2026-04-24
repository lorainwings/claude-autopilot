#!/usr/bin/env bash
# test_parallel_plan_generation.sh — Section 40: generate-parallel-plan.sh 并行计划生成
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../runtime/scripts" && pwd)"
source "$TEST_DIR/_test_helpers.sh"

PLAN_SCRIPT="$SCRIPT_DIR/generate-parallel-plan.sh"
EMIT_SCRIPT="$SCRIPT_DIR/emit-parallel-event.sh"

echo "--- 40. generate-parallel-plan.sh 并行计划生成 ---"

# 40a. 无依赖任务 → 单 batch 并行
echo '40a. 无依赖任务 → 单 batch 并行'
INPUT_A='[
  {"task_name":"task-1","affected_files":["a.ts"],"depends_on":[],"domain":"frontend"},
  {"task_name":"task-2","affected_files":["b.ts"],"depends_on":[],"domain":"backend"},
  {"task_name":"task-3","affected_files":["c.ts"],"depends_on":[],"domain":"frontend"}
]'
OUTPUT_A=$(echo "$INPUT_A" | bash "$PLAN_SCRIPT" 2>/dev/null)
exit_a=$?
assert_exit "40a. exit code" 0 "$exit_a"
# 验证单 batch
BATCH_COUNT_A=$(echo "$OUTPUT_A" | python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d.get('batches',[])))" 2>/dev/null)
assert_exit "40a. single batch" 1 "$BATCH_COUNT_A"
# 验证 can_parallel=True
CAN_PARALLEL_A=$(echo "$OUTPUT_A" | python3 -c "import json,sys; d=json.load(sys.stdin); print(str(d['batches'][0]['can_parallel']).lower())" 2>/dev/null)
assert_contains "40a. can_parallel=true" "$CAN_PARALLEL_A" "true"
# 验证 scheduler_decision
assert_json_field "40a. scheduler_decision=batch_parallel" "$OUTPUT_A" "scheduler_decision" "batch_parallel"
# 验证 fallback_to_serial=False
FALLBACK_A=$(echo "$OUTPUT_A" | python3 -c "import json,sys; d=json.load(sys.stdin); print(str(d['fallback_to_serial']).lower())" 2>/dev/null)
assert_contains "40a. fallback_to_serial=false" "$FALLBACK_A" "false"

# 40b. 有依赖链 → 多 batch 顺序
echo ""
echo '40b. 有依赖链 → 多 batch 顺序'
INPUT_B='[
  {"task_name":"task-1","affected_files":["a.ts"],"depends_on":[],"domain":"frontend"},
  {"task_name":"task-2","affected_files":["b.ts"],"depends_on":["task-1"],"domain":"backend"},
  {"task_name":"task-3","affected_files":["c.ts"],"depends_on":[],"domain":"frontend"}
]'
OUTPUT_B=$(echo "$INPUT_B" | bash "$PLAN_SCRIPT" 2>/dev/null)
exit_b=$?
assert_exit "40b. exit code" 0 "$exit_b"
BATCH_COUNT_B=$(echo "$OUTPUT_B" | python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d.get('batches',[])))" 2>/dev/null)
# task-1 和 task-3 在 batch 0, task-2 在 batch 1
assert_exit "40b. two batches" 2 "$BATCH_COUNT_B"
# batch 0 应该包含 task-1 和 task-3
BATCH0_TASKS=$(echo "$OUTPUT_B" | python3 -c "import json,sys; d=json.load(sys.stdin); print(','.join(sorted(d['batches'][0]['tasks'])))" 2>/dev/null)
assert_contains "40b. batch 0 has task-1" "$BATCH0_TASKS" "task-1"
assert_contains "40b. batch 0 has task-3" "$BATCH0_TASKS" "task-3"
# batch 1 应该只包含 task-2
BATCH1_TASKS=$(echo "$OUTPUT_B" | python3 -c "import json,sys; d=json.load(sys.stdin); print(','.join(d['batches'][1]['tasks']))" 2>/dev/null)
assert_contains "40b. batch 1 has task-2" "$BATCH1_TASKS" "task-2"

# 40c. 文件冲突 → 分入不同 batch
echo ""
echo '40c. 文件冲突 → 分入不同 batch'
INPUT_C='[
  {"task_name":"task-1","affected_files":["shared.ts","a.ts"],"depends_on":[],"domain":"frontend"},
  {"task_name":"task-2","affected_files":["shared.ts","b.ts"],"depends_on":[],"domain":"frontend"},
  {"task_name":"task-3","affected_files":["c.ts"],"depends_on":[],"domain":"backend"}
]'
OUTPUT_C=$(echo "$INPUT_C" | bash "$PLAN_SCRIPT" 2>/dev/null)
exit_c=$?
assert_exit "40c. exit code" 0 "$exit_c"
# task-1 和 task-2 共享 shared.ts → 不能同一 batch 并行
# 依赖图中 task-2 依赖 task-1（文件冲突隐式依赖）
BATCH_COUNT_C=$(echo "$OUTPUT_C" | python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d.get('batches',[])))" 2>/dev/null)
# 至少 2 个 batch (task-1+task-3 并行, task-2 后执行)
if [ "$BATCH_COUNT_C" -ge 2 ]; then
  green "  PASS: 40c. at least 2 batches for file conflict ($BATCH_COUNT_C)"
  PASS=$((PASS + 1))
else
  red "  FAIL: 40c. expected >= 2 batches, got $BATCH_COUNT_C"
  FAIL=$((FAIL + 1))
fi
# 验证 shared.ts 在依赖图中
DEP_GRAPH_HAS_SHARED=$(echo "$OUTPUT_C" | python3 -c "import json,sys; d=json.load(sys.stdin); g=d.get('dependency_graph',{}); print('yes' if any('task-1' in v for v in g.values()) else 'no')" 2>/dev/null)
assert_contains "40c. dependency_graph has file conflict dep" "$DEP_GRAPH_HAS_SHARED" "yes"

# 40d. 全依赖 → fallback_to_serial=true
echo ""
echo '40d. 全依赖 → fallback_to_serial=true'
INPUT_D='[
  {"task_name":"task-1","affected_files":["a.ts"],"depends_on":[],"domain":"frontend"},
  {"task_name":"task-2","affected_files":["b.ts"],"depends_on":["task-1"],"domain":"frontend"},
  {"task_name":"task-3","affected_files":["c.ts"],"depends_on":["task-2"],"domain":"frontend"}
]'
OUTPUT_D=$(echo "$INPUT_D" | bash "$PLAN_SCRIPT" 2>/dev/null)
exit_d=$?
assert_exit "40d. exit code" 0 "$exit_d"
FALLBACK_D=$(echo "$OUTPUT_D" | python3 -c "import json,sys; d=json.load(sys.stdin); print(str(d['fallback_to_serial']).lower())" 2>/dev/null)
assert_contains "40d. fallback_to_serial=true" "$FALLBACK_D" "true"
assert_json_field "40d. scheduler_decision=serial" "$OUTPUT_D" "scheduler_decision" "serial"
# fallback_reason 必须非空
FALLBACK_REASON_D=$(echo "$OUTPUT_D" | python3 -c "import json,sys; d=json.load(sys.stdin); r=d.get('fallback_reason',''); print('non_empty' if r else 'empty')" 2>/dev/null)
assert_contains "40d. fallback_reason is non-empty" "$FALLBACK_REASON_D" "non_empty"

# 40e. 单域项目可 batch 并行 (无文件冲突)
echo ""
echo '40e. 单域项目可 batch 并行'
INPUT_E='[
  {"task_name":"task-1","affected_files":["frontend/a.ts"],"depends_on":[],"domain":"frontend"},
  {"task_name":"task-2","affected_files":["frontend/b.ts"],"depends_on":[],"domain":"frontend"},
  {"task_name":"task-3","affected_files":["frontend/c.ts"],"depends_on":[],"domain":"frontend"}
]'
OUTPUT_E=$(echo "$INPUT_E" | bash "$PLAN_SCRIPT" 2>/dev/null)
exit_e=$?
assert_exit "40e. exit code" 0 "$exit_e"
# 所有在同一域但无文件冲突 → 单 batch 并行
BATCH_COUNT_E=$(echo "$OUTPUT_E" | python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d.get('batches',[])))" 2>/dev/null)
assert_exit "40e. single batch" 1 "$BATCH_COUNT_E"
CAN_PARALLEL_E=$(echo "$OUTPUT_E" | python3 -c "import json,sys; d=json.load(sys.stdin); print(str(d['batches'][0]['can_parallel']).lower())" 2>/dev/null)
assert_contains "40e. can_parallel=true (single domain, no conflicts)" "$CAN_PARALLEL_E" "true"
assert_json_field "40e. scheduler_decision=batch_parallel" "$OUTPUT_E" "scheduler_decision" "batch_parallel"

# 40f. emit-parallel-event.sh 基本功能
echo ""
echo '40f. emit-parallel-event.sh 基本功能'
EMIT_TEST_DIR=$(mktemp -d)
mkdir -p "$EMIT_TEST_DIR/logs"
mkdir -p "$EMIT_TEST_DIR/openspec/changes"
echo '{"change":"test","session_id":"s1"}' >"$EMIT_TEST_DIR/openspec/changes/.autopilot-active"

EMIT_OUTPUT=$(bash "$EMIT_SCRIPT" "$EMIT_TEST_DIR" 5 full parallel_plan '{"scheduler_decision":"batch_parallel","total_tasks":3}' 2>/dev/null)
exit_f=$?
assert_exit "40f. emit exit code" 0 "$exit_f"
assert_json_field "40f. event type" "$EMIT_OUTPUT" "type" "parallel_plan"
assert_contains "40f. payload has scheduler_decision" "$EMIT_OUTPUT" "batch_parallel"
# 验证写入 events.jsonl
assert_file_exists "40f. events.jsonl created" "$EMIT_TEST_DIR/logs/events.jsonl"

# 40g. emit-parallel-event.sh 拒绝无效事件类型
echo ""
echo '40g. emit-parallel-event.sh 拒绝无效事件类型'
EMIT_ERR=$(bash "$EMIT_SCRIPT" "$EMIT_TEST_DIR" 5 full invalid_type '{}' 2>&1)
exit_g=$?
assert_exit "40g. invalid event type exits 1" 1 "$exit_g"

# 40h. 空任务列表 → fallback
echo ""
echo '40h. 空任务列表 → fallback'
OUTPUT_H=$(echo '[]' | bash "$PLAN_SCRIPT" 2>/dev/null)
exit_h=$?
assert_exit "40h. exit code" 0 "$exit_h"
FALLBACK_H=$(echo "$OUTPUT_H" | python3 -c "import json,sys; d=json.load(sys.stdin); print(str(d['fallback_to_serial']).lower())" 2>/dev/null)
assert_contains "40h. empty list fallback" "$FALLBACK_H" "true"

# 清理
rm -rf "$EMIT_TEST_DIR"

echo ""
echo "--- Results: $PASS passed, $FAIL failed ---"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1

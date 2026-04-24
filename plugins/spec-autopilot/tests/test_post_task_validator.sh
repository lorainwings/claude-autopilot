#!/usr/bin/env bash
# test_post_task_validator.sh — Section 33: _post_task_validator.py unit tests
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../runtime/scripts" && pwd)"
source "$TEST_DIR/_test_helpers.sh"
source "$TEST_DIR/_fixtures.sh"

echo "--- 33. _post_task_validator.py tests ---"
setup_autopilot_fixture

VALIDATOR="$SCRIPT_DIR/_post_task_validator.py"
export SCRIPT_DIR

# Helper: run validator with given phase and output, return stdout
# Uses python3 to construct valid JSON (avoids shell quoting issues)
run_validator() {
  local phase="$1"
  local agent_output="$2"
  python3 -c "
import json, sys, subprocess
phase = int(sys.argv[1])
agent_output = sys.argv[2]
prompt = f'<!-- autopilot-phase:{phase} --> Do phase {phase} task'
data = {
    'tool_name': 'Task',
    'cwd': sys.argv[3],
    'tool_input': {'prompt': prompt},
    'tool_response': agent_output
}
proc = subprocess.run(
    [sys.executable, sys.argv[4]],
    input=json.dumps(data),
    capture_output=True, text=True, timeout=30
)
if proc.stdout.strip():
    print(proc.stdout.strip())
" "$phase" "$agent_output" "$REPO_ROOT" "$VALIDATOR" 2>/dev/null || true
}

# 33a. Valid Phase 2 envelope → no block output
result=$(run_validator 2 '{"status":"ok","summary":"Created OpenSpec","artifacts":["openspec/changes/test/proposal.md"],"alternatives":["Option A","Option B"]}')
if [ -z "$result" ] || ! grep -q '"block"' <<<"$result"; then
  green "  PASS: 33a. valid Phase 2 envelope → no block"
  PASS=$((PASS + 1))
else
  red "  FAIL: 33a. valid Phase 2 envelope got blocked (output='$result')"
  FAIL=$((FAIL + 1))
fi

# 33b. Missing status field → block
result=$(run_validator 2 '{"summary":"no status"}')
assert_contains "33b. missing status → block" "$result" "block"

# 33c. Invalid status value → block
result=$(run_validator 2 '{"status":"excellent","summary":"test"}')
assert_contains "33c. invalid status → block" "$result" "block"

# 33d. Empty output → block
result=$(run_validator 2 '')
assert_contains "33d. empty output → block" "$result" "block"

# 33e. Phase 4 warning → block (Phase 4 rejects warning)
result=$(run_validator 4 '{"status":"warning","summary":"tests okay","artifacts":["test.js"],"test_counts":{"unit":10},"sad_path_counts":{"unit":5},"dry_run_results":{"unit":0},"test_pyramid":{"unit_pct":100,"e2e_pct":0},"change_coverage":{"change_points":10,"tested_points":10,"coverage_pct":100,"untested_points":[]}}')
assert_contains "33e. Phase 4 warning → block" "$result" "block"

# 33f. Phase 4 missing phase-specific fields → block
result=$(run_validator 4 '{"status":"ok","summary":"tests done","artifacts":["test.js"]}')
assert_contains "33f. Phase 4 missing fields → block" "$result" "block"

# 33g. Anti-rationalization: heavy skip patterns → block
result=$(run_validator 5 '{"status":"ok","summary":"done","artifacts":["impl.ts"],"test_results_path":"tests/","tasks_completed":5,"zero_skip_check":{"passed":true}} Skipped this because it was deferred to a future sprint. Tests were skipped because not needed.')
assert_contains "33g. anti-rationalization heavy score → block" "$result" "block"

# 33h. Phase 5 zero_skip_check.passed=false → block
result=$(run_validator 5 '{"status":"ok","summary":"impl done","artifacts":["impl.ts"],"test_results_path":"tests/","tasks_completed":5,"zero_skip_check":{"passed":false}}')
assert_contains "33h. zero_skip_check false → block" "$result" "block"

# 33i. Phase 1 missing decisions → block
result=$(run_validator 1 '{"status":"ok","summary":"requirements done"}')
assert_contains "33i. Phase 1 missing decisions → block" "$result" "block"

# 33j. Phase 1 valid small complexity → no block
result=$(run_validator 1 '{"status":"ok","summary":"requirements done","complexity":"small","requirement_type":"feature","decisions":[{"point":"auth method","choice":"JWT"}]}')
if [ -z "$result" ] || ! grep -q '"block"' <<<"$result"; then
  green "  PASS: 33j. Phase 1 small complexity valid → no block"
  PASS=$((PASS + 1))
else
  red "  FAIL: 33j. Phase 1 small complexity (output='$result')"
  FAIL=$((FAIL + 1))
fi

# ────────────────────────────────────────
# Phase 6 advisory 路径白名单（post-task-validator.sh shell 层）
# 设计意图：Phase 6 路径 B/C (code review / quality scan) 无 autopilot-phase marker，
# 原先被 has_phase_marker 直接跳过，导致返回格式无 L2 校验。
# 新机制：prompt 引用 code-review.json / quality-scan.json 等 advisory 产物时，
# 强制轻量信封校验（status + summary + findings[]）。
# ────────────────────────────────────────
POST_HOOK="$SCRIPT_DIR/post-task-validator.sh"

# 33k. advisory 路径 缺 status → block
PAYLOAD_NO_STATUS='{"tool_name":"Task","cwd":"'"$REPO_ROOT"'","tool_input":{"prompt":"执行代码审查，输出 code-review.json"},"tool_response":"{\"summary\":\"done\",\"findings\":[]}"}'
result=$(echo "$PAYLOAD_NO_STATUS" | bash "$POST_HOOK" 2>/dev/null || true)
if echo "$result" | grep -qE '"decision":\s*"block"' && echo "$result" | grep -q 'status'; then
  green "  PASS: 33k. advisory 缺 status → block"
  PASS=$((PASS + 1))
else
  red "  FAIL: 33k. advisory 缺 status 未阻断，got: $result"
  FAIL=$((FAIL + 1))
fi

# 33l. advisory 路径 findings 非数组 → block
PAYLOAD_BAD_FINDINGS='{"tool_name":"Task","cwd":"'"$REPO_ROOT"'","tool_input":{"prompt":"执行 quality-scan.json"},"tool_response":"{\"status\":\"ok\",\"summary\":\"ok\",\"findings\":\"nope\"}"}'
result=$(echo "$PAYLOAD_BAD_FINDINGS" | bash "$POST_HOOK" 2>/dev/null || true)
if echo "$result" | grep -qE '"decision":\s*"block"' && echo "$result" | grep -q 'findings'; then
  green "  PASS: 33l. advisory findings 非数组 → block"
  PASS=$((PASS + 1))
else
  red "  FAIL: 33l. advisory bad findings 未阻断，got: $result"
  FAIL=$((FAIL + 1))
fi

# 33m. advisory 路径 happy path → 放行
PAYLOAD_OK='{"tool_name":"Task","cwd":"'"$REPO_ROOT"'","tool_input":{"prompt":"Code review 输出 code-review.json"},"tool_response":"{\"status\":\"ok\",\"summary\":\"0 blocking\",\"findings\":[]}"}'
result=$(echo "$PAYLOAD_OK" | bash "$POST_HOOK" 2>/dev/null || true)
if echo "$result" | grep -qE '"decision":\s*"block"'; then
  red "  FAIL: 33m. advisory happy path 被误阻断，got: $result"
  FAIL=$((FAIL + 1))
else
  green "  PASS: 33m. advisory happy path → 放行"
  PASS=$((PASS + 1))
fi

# 33n. 非 advisory 且无 phase marker → 维持原有 bypass（不阻断）
PAYLOAD_UNRELATED='{"tool_name":"Task","cwd":"'"$REPO_ROOT"'","tool_input":{"prompt":"做点普通工作"},"tool_response":"ok"}'
result=$(echo "$PAYLOAD_UNRELATED" | bash "$POST_HOOK" 2>/dev/null || true)
if echo "$result" | grep -qE '"decision":\s*"block"'; then
  red "  FAIL: 33n. unrelated task 被误阻断，got: $result"
  FAIL=$((FAIL + 1))
else
  green "  PASS: 33n. unrelated task 保持 bypass"
  PASS=$((PASS + 1))
fi

teardown_autopilot_fixture
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1
exit 0

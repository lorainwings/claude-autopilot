#!/usr/bin/env bash
# test_phase3_plan_required.sh — Phase 3 plan 必须非空黑盒验证
# Codex 评审步骤 6: 验证 Phase 3 无 plan 时 hook 阻断

set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../runtime/scripts" && pwd)"
source "$TEST_DIR/_test_helpers.sh"
source "$TEST_DIR/_fixtures.sh"

echo "=== Phase 3 Plan Required Tests ==="
echo ""
setup_autopilot_fixture

# --- Test 1: Phase 3 无 plan → 应阻断 ---
echo "1. Phase 3 无 plan → block"
exit_code=0
output=$(AUTOPILOT_PHASE_ID=3 echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:3 -->\nGenerate FF"},"tool_response":"Result: {\"status\":\"ok\",\"summary\":\"FF generated\",\"test_strategy\":\"unit + integration\"}"}' \
  | AUTOPILOT_PHASE_ID=3 bash "$SCRIPT_DIR/post-task-validator.sh" 2>/dev/null) || exit_code=$?
assert_exit "1a. Phase 3 无 plan exit 0" 0 $exit_code
assert_contains "1b. Phase 3 无 plan → block" "$output" "block"
assert_contains "1c. → mentions plan" "$output" "plan"

# --- Test 2: Phase 3 plan 为空字符串 → 应阻断 ---
echo ""
echo "2. Phase 3 plan 为空字符串 → block"
exit_code=0
output=$(AUTOPILOT_PHASE_ID=3 echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:3 -->\nGenerate FF"},"tool_response":"Result: {\"status\":\"ok\",\"summary\":\"FF generated\",\"plan\":\"\",\"test_strategy\":\"unit\"}"}' \
  | AUTOPILOT_PHASE_ID=3 bash "$SCRIPT_DIR/post-task-validator.sh" 2>/dev/null) || exit_code=$?
assert_exit "2a. Phase 3 空 plan exit 0" 0 $exit_code
assert_contains "2b. Phase 3 空 plan → block" "$output" "block"

# --- Test 3: Phase 3 plan 为空白字符串 → 应阻断 ---
echo ""
echo "3. Phase 3 plan 为空白字符串 → block"
exit_code=0
output=$(AUTOPILOT_PHASE_ID=3 echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:3 -->\nGenerate FF"},"tool_response":"Result: {\"status\":\"ok\",\"summary\":\"FF generated\",\"plan\":\"   \",\"test_strategy\":\"unit\"}"}' \
  | AUTOPILOT_PHASE_ID=3 bash "$SCRIPT_DIR/post-task-validator.sh" 2>/dev/null) || exit_code=$?
assert_exit "3a. Phase 3 空白 plan exit 0" 0 $exit_code
assert_contains "3b. Phase 3 空白 plan → block" "$output" "block"

# --- Test 4: Phase 3 缺少 test_strategy → 应阻断 ---
echo ""
echo "4. Phase 3 缺少 test_strategy → block"
exit_code=0
output=$(AUTOPILOT_PHASE_ID=3 echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:3 -->\nGenerate FF"},"tool_response":"Result: {\"status\":\"ok\",\"summary\":\"FF generated\",\"plan\":\"Build API endpoints\"}"}' \
  | AUTOPILOT_PHASE_ID=3 bash "$SCRIPT_DIR/post-task-validator.sh" 2>/dev/null) || exit_code=$?
assert_exit "4a. Phase 3 缺 test_strategy exit 0" 0 $exit_code
assert_contains "4b. Phase 3 缺 test_strategy → block" "$output" "block"
assert_contains "4c. → mentions test_strategy" "$output" "test_strategy"

# --- Test 5: Phase 3 有效 envelope → 应通过 ---
echo ""
echo "5. Phase 3 有效 envelope → pass"
exit_code=0
output=$(AUTOPILOT_PHASE_ID=3 echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:3 -->\nGenerate FF"},"tool_response":"Result: {\"status\":\"ok\",\"summary\":\"FF generated\",\"plan\":\"Build REST API with CRUD endpoints\",\"test_strategy\":\"unit + integration + e2e\"}"}' \
  | AUTOPILOT_PHASE_ID=3 bash "$SCRIPT_DIR/post-task-validator.sh" 2>/dev/null) || exit_code=$?
assert_exit "5a. Phase 3 有效 envelope exit 0" 0 $exit_code
assert_not_contains "5b. Phase 3 有效 → no block" "$output" "block"

# --- Test 6: Phase 3 env var 路径（无 marker）→ 仍应验证 ---
echo ""
echo "6. Phase 3 env var 路径（无 marker）→ 验证 plan"
exit_code=0
output=$(AUTOPILOT_PHASE_ID=3 echo '{"tool_name":"Task","tool_input":{"prompt":"Generate implementation plan"},"tool_response":"Result: {\"status\":\"ok\",\"summary\":\"Plan done\",\"test_strategy\":\"unit\"}"}' \
  | AUTOPILOT_PHASE_ID=3 bash "$SCRIPT_DIR/post-task-validator.sh" 2>/dev/null) || exit_code=$?
assert_exit "6a. Phase 3 env var exit 0" 0 $exit_code
assert_contains "6b. Phase 3 env var → block (no plan)" "$output" "block"

teardown_autopilot_fixture

echo ""
echo "=============================="
echo "Phase 3 Plan Required: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1
exit 0

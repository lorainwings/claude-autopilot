#!/usr/bin/env bash
# test_phase2_artifacts_required.sh — Phase 2 artifacts 必须非空黑盒验证
# Codex 评审步骤 6: 验证 Phase 2 无 artifacts 时 hook 阻断

set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../runtime/scripts" && pwd)"
source "$TEST_DIR/_test_helpers.sh"
source "$TEST_DIR/_fixtures.sh"

echo "=== Phase 2 Artifacts Required Tests ==="
echo ""
setup_autopilot_fixture

# --- Test 1: Phase 2 无 artifacts → 应阻断 ---
echo "1. Phase 2 无 artifacts → block"
exit_code=0
output=$(AUTOPILOT_PHASE_ID=2 echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:2 -->\nCreate OpenSpec"},"tool_response":"Result: {\"status\":\"ok\",\"summary\":\"Spec created\",\"alternatives\":[\"Option A\",\"Option B\"]}"}' |
  AUTOPILOT_PHASE_ID=2 bash "$SCRIPT_DIR/post-task-validator.sh" 2>/dev/null) || exit_code=$?
assert_exit "1a. Phase 2 无 artifacts exit 0" 0 $exit_code
assert_contains "1b. Phase 2 无 artifacts → block" "$output" "block"
assert_contains "1c. → mentions artifacts" "$output" "artifacts"

# --- Test 2: Phase 2 artifacts 为空数组 → 应阻断 ---
echo ""
echo "2. Phase 2 artifacts 为空数组 → block"
exit_code=0
output=$(AUTOPILOT_PHASE_ID=2 echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:2 -->\nCreate OpenSpec"},"tool_response":"Result: {\"status\":\"ok\",\"summary\":\"Spec created\",\"artifacts\":[],\"alternatives\":[\"A\"]}"}' |
  AUTOPILOT_PHASE_ID=2 bash "$SCRIPT_DIR/post-task-validator.sh" 2>/dev/null) || exit_code=$?
assert_exit "2a. Phase 2 空 artifacts exit 0" 0 $exit_code
assert_contains "2b. Phase 2 空 artifacts → block" "$output" "block"

# --- Test 3: Phase 2 缺少 alternatives → 应阻断（phase_required 检查） ---
echo ""
echo "3. Phase 2 缺少 alternatives → block"
exit_code=0
output=$(AUTOPILOT_PHASE_ID=2 echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:2 -->\nCreate OpenSpec"},"tool_response":"Result: {\"status\":\"ok\",\"summary\":\"Spec created\",\"artifacts\":[\"openspec/spec.md\"]}"}' |
  AUTOPILOT_PHASE_ID=2 bash "$SCRIPT_DIR/post-task-validator.sh" 2>/dev/null) || exit_code=$?
assert_exit "3a. Phase 2 缺 alternatives exit 0" 0 $exit_code
assert_contains "3b. Phase 2 缺 alternatives → block" "$output" "block"
assert_contains "3c. → mentions alternatives" "$output" "alternatives"

# --- Test 4: Phase 2 有效 envelope → 应通过 ---
echo ""
echo "4. Phase 2 有效 envelope → pass"
exit_code=0
output=$(AUTOPILOT_PHASE_ID=2 echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:2 -->\nCreate OpenSpec"},"tool_response":"Result: {\"status\":\"ok\",\"summary\":\"Spec created\",\"artifacts\":[\"openspec/spec.md\"],\"alternatives\":[\"Option A\",\"Option B\"]}"}' |
  AUTOPILOT_PHASE_ID=2 bash "$SCRIPT_DIR/post-task-validator.sh" 2>/dev/null) || exit_code=$?
assert_exit "4a. Phase 2 有效 envelope exit 0" 0 $exit_code
assert_not_contains "4b. Phase 2 有效 → no block" "$output" "block"

# --- Test 5: Phase 2 通过 env var（无 prompt marker）→ 仍应验证 ---
echo ""
echo "5. Phase 2 env var 路径（无 marker）→ 验证 artifacts"
exit_code=0
output=$(AUTOPILOT_PHASE_ID=2 echo '{"tool_name":"Task","tool_input":{"prompt":"Create spec document"},"tool_response":"Result: {\"status\":\"ok\",\"summary\":\"Spec created\",\"alternatives\":[\"A\"]}"}' |
  AUTOPILOT_PHASE_ID=2 bash "$SCRIPT_DIR/post-task-validator.sh" 2>/dev/null) || exit_code=$?
assert_exit "5a. Phase 2 env var 路径 exit 0" 0 $exit_code
assert_contains "5b. Phase 2 env var → block (no artifacts)" "$output" "block"

teardown_autopilot_fixture

echo ""
echo "=============================="
echo "Phase 2 Artifacts Required: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1
exit 0

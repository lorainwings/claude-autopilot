#!/usr/bin/env bash
# test_phase1_hard_gate.sh — Phase 1 hard gate 黑盒验证
# Codex 评审步骤 6: 验证 Phase 1 无 decisions 时 hook 阻断（不依赖 marker）
# 测试双路检测：prompt marker 路径 + env var 路径

set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../runtime/scripts" && pwd)"
source "$TEST_DIR/_test_helpers.sh"
source "$TEST_DIR/_fixtures.sh"

echo "=== Phase 1 Hard Gate Tests ==="
echo ""
setup_autopilot_fixture

# --- Test 1: Phase 1 无 decisions → 应阻断（env var 路径） ---
echo "1. Phase 1 无 decisions (env var 路径) → block"
exit_code=0
output=$(AUTOPILOT_PHASE_ID=1 echo '{"tool_name":"Task","tool_input":{"prompt":"Analyze requirements"},"tool_response":"Result: {\"status\":\"ok\",\"summary\":\"Requirements analyzed\",\"requirement_type\":\"feature\"}"}' \
  | AUTOPILOT_PHASE_ID=1 bash "$SCRIPT_DIR/post-task-validator.sh" 2>/dev/null) || exit_code=$?
assert_exit "1a. Phase 1 无 decisions exit 0" 0 $exit_code
assert_contains "1b. Phase 1 无 decisions → block" "$output" "block"
assert_contains "1c. Phase 1 → mentions decisions" "$output" "decisions"

# --- Test 2: Phase 1 无 decisions → 应阻断（prompt marker 路径） ---
echo ""
echo "2. Phase 1 无 decisions (prompt marker 路径) → block"
exit_code=0
output=$(echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:1 -->\nAnalyze requirements"},"tool_response":"Result: {\"status\":\"ok\",\"summary\":\"Requirements analyzed\",\"requirement_type\":\"feature\"}"}' \
  | bash "$SCRIPT_DIR/post-task-validator.sh" 2>/dev/null) || exit_code=$?
assert_exit "2a. Phase 1 无 decisions (marker) exit 0" 0 $exit_code
assert_contains "2b. Phase 1 无 decisions (marker) → block" "$output" "block"

# --- Test 3: Phase 1 有 decisions 但为空数组 → 应阻断 ---
echo ""
echo "3. Phase 1 decisions 为空数组 → block"
exit_code=0
output=$(AUTOPILOT_PHASE_ID=1 echo '{"tool_name":"Task","tool_input":{"prompt":"Analyze requirements"},"tool_response":"Result: {\"status\":\"ok\",\"summary\":\"Requirements analyzed\",\"requirement_type\":\"feature\",\"decisions\":[]}"}' \
  | AUTOPILOT_PHASE_ID=1 bash "$SCRIPT_DIR/post-task-validator.sh" 2>/dev/null) || exit_code=$?
assert_exit "3a. Phase 1 空 decisions exit 0" 0 $exit_code
assert_contains "3b. Phase 1 空 decisions → block" "$output" "block"

# --- Test 4: Phase 1 有有效 decisions → 应通过 ---
echo ""
echo "4. Phase 1 有效 decisions → pass"
exit_code=0
output=$(AUTOPILOT_PHASE_ID=1 echo '{"tool_name":"Task","tool_input":{"prompt":"Analyze requirements"},"tool_response":"Result: {\"status\":\"ok\",\"summary\":\"Requirements analyzed\",\"requirement_type\":\"feature\",\"decisions\":[{\"point\":\"Use REST API\",\"choice\":\"REST\",\"rationale\":\"simpler\",\"options\":[{\"label\":\"REST\",\"description\":\"RESTful API\",\"pros\":[\"simple\"],\"cons\":[\"no streaming\"],\"recommended\":true},{\"label\":\"gRPC\",\"description\":\"gRPC API\",\"pros\":[\"fast\"],\"cons\":[\"complex\"]}]}],\"complexity\":\"medium\"}"}' \
  | AUTOPILOT_PHASE_ID=1 bash "$SCRIPT_DIR/post-task-validator.sh" 2>/dev/null) || exit_code=$?
assert_exit "4a. Phase 1 有效 decisions exit 0" 0 $exit_code
assert_not_contains "4b. Phase 1 有效 decisions → no block" "$output" "block"

# --- Test 5: Phase 1 缺少 requirement_type → 应阻断 ---
echo ""
echo "5. Phase 1 缺少 requirement_type → block"
exit_code=0
output=$(AUTOPILOT_PHASE_ID=1 echo '{"tool_name":"Task","tool_input":{"prompt":"Analyze requirements"},"tool_response":"Result: {\"status\":\"ok\",\"summary\":\"Done\",\"decisions\":[{\"point\":\"x\",\"choice\":\"y\"}]}"}' \
  | AUTOPILOT_PHASE_ID=1 bash "$SCRIPT_DIR/post-task-validator.sh" 2>/dev/null) || exit_code=$?
assert_exit "5a. Phase 1 缺 requirement_type exit 0" 0 $exit_code
assert_contains "5b. Phase 1 缺 requirement_type → block" "$output" "block"
assert_contains "5c. → mentions requirement_type" "$output" "requirement_type"

# --- Test 6: 非 autopilot Task（无 marker 无 env var）→ 应跳过 ---
echo ""
echo "6. 非 autopilot Task → 跳过验证"
exit_code=0
output=$(unset AUTOPILOT_PHASE_ID; echo '{"tool_name":"Task","tool_input":{"prompt":"Search for TODOs"},"tool_response":"Found 10 TODOs"}' \
  | bash "$SCRIPT_DIR/post-task-validator.sh" 2>/dev/null) || exit_code=$?
assert_exit "6a. 非 autopilot Task exit 0" 0 $exit_code
assert_not_contains "6b. 非 autopilot → no block" "$output" "block"

teardown_autopilot_fixture

echo ""
echo "=============================="
echo "Phase 1 Hard Gate: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1
exit 0

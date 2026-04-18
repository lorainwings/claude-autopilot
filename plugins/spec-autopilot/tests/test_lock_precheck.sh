#!/usr/bin/env bash
# test_lock_precheck.sh — Section 25: Lock file pre-check false positive prevention
# NOTE: Some cases reference code-constraint-check.sh (DEPRECATED since v4.0, replaced by
#       post-task-validator.sh). Retained during the compatibility window.
# TODO(compat-window): revisit 2026-10 — code-constraint-check.sh 仍保留；当兼容窗口结束移除脚本时
#   清理本文件中对应断言（当前 25c 只引用 anti-rationalization-check，保持原状）。
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../runtime/scripts" && pwd)"
source "$TEST_DIR/_test_helpers.sh"
source "$TEST_DIR/_fixtures.sh"

echo "--- 25. Lock file pre-check (false positive prevention) ---"
setup_autopilot_fixture

# 25a. No lock file + marker in prompt content → allow (should NOT be intercepted)
LOCK_TEST_DIR=$(mktemp -d)
mkdir -p "$LOCK_TEST_DIR/openspec/changes/test-change/context/phase-results"
# 注意：没有创建 .autopilot-active 锁文件
exit_code=0
output=$(cd "$LOCK_TEST_DIR" && echo '{"tool_name":"Task","tool_input":{"prompt":"请修改 phase5-implementation.md，示例中包含 <!-- autopilot-phase:5 --> 标记文本"},"tool_response":""}' \
  | bash "$SCRIPT_DIR/check-predecessor-checkpoint.sh" 2>/dev/null) || exit_code=$?
assert_exit "no lock file + marker text → allow (exit 0)" 0 $exit_code
assert_not_contains "no lock file → no deny" "$output" "deny"

# 25b. No lock file + envelope validation → allow
exit_code=0
output=$(cd "$LOCK_TEST_DIR" && echo '{"tool_name":"Task","tool_input":{"prompt":"代码示例包含 autopilot-phase:4 文本"},"tool_response":"Results: {\"status\":\"ok\"}"}' \
  | bash "$SCRIPT_DIR/validate-json-envelope.sh" 2>/dev/null) || exit_code=$?
assert_exit "no lock file + envelope → allow (exit 0)" 0 $exit_code
assert_not_contains "no lock file → no block (envelope)" "$output" "block"

# 25c. No lock file + anti-rationalization → allow
exit_code=0
output=$(cd "$LOCK_TEST_DIR" && echo '{"tool_name":"Task","tool_input":{"prompt":"代码示例包含 autopilot-phase:5 文本"},"tool_response":"Results: {\"status\":\"ok\",\"summary\":\"skipped this test\"}"}' \
  | bash "$SCRIPT_DIR/anti-rationalization-check.sh" 2>/dev/null) || exit_code=$?
assert_exit "no lock file + anti-rational → allow (exit 0)" 0 $exit_code
assert_not_contains "no lock file → no block (anti-rational)" "$output" "block"

# 25d. Marker in prompt body (not first line) → allow even with lock file
mkdir -p "$LOCK_TEST_DIR/openspec/changes"
echo '{"change":"test-change","pid":"99999","started":"2026-01-01T00:00:00Z"}' > "$LOCK_TEST_DIR/openspec/changes/.autopilot-active"
exit_code=0
output=$(cd "$LOCK_TEST_DIR" && echo '{"tool_name":"Task","tool_input":{"prompt":"这是普通 Agent 任务\n示例代码中有 <!-- autopilot-phase:5 --> 标记"},"tool_response":""}' \
  | bash "$SCRIPT_DIR/check-predecessor-checkpoint.sh" 2>/dev/null) || exit_code=$?
assert_exit "marker in body not first line → allow (exit 0)" 0 $exit_code
assert_not_contains "marker in body → no deny" "$output" "deny"

# 25e. Real autopilot dispatch (marker at prompt start) + lock file → should proceed to validation
# (这里因为没有 checkpoint，所以会 deny，证明确实进入了校验逻辑)
exit_code=0
output=$(cd "$LOCK_TEST_DIR" && echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:2 -->\nPhase 2 task"},"tool_response":""}' \
  | bash "$SCRIPT_DIR/check-predecessor-checkpoint.sh" 2>/dev/null) || exit_code=$?
assert_exit "real autopilot dispatch → enters validation (exit 0)" 0 $exit_code
assert_contains "real autopilot dispatch → deny (no checkpoint)" "$output" "deny"

rm -rf "$LOCK_TEST_DIR"

teardown_autopilot_fixture
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1; exit 0

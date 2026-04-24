#!/usr/bin/env bash
# test_phase65_bypass.sh — Section 33: Phase 6.5 code review bypass
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../runtime/scripts" && pwd)"
source "$TEST_DIR/_test_helpers.sh"
source "$TEST_DIR/_fixtures.sh"

echo "--- 33. v3.2.2 Phase 6.5 code review bypass (no autopilot-phase marker) ---"
setup_autopilot_fixture

# 33a. Phase 6.5 prompt without autopilot-phase marker → validate-json-envelope skips
exit_code=0
output=$(echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- 代码审查 -->\nReview code changes"},"tool_response":"Review complete: no critical issues found."}' |
  bash "$SCRIPT_DIR/validate-json-envelope.sh" 2>/dev/null) || exit_code=$?
assert_exit "Phase 6.5 no autopilot-phase marker → exit 0 (skip)" 0 $exit_code
assert_not_contains "Phase 6.5 no marker → no block" "$output" "block"

# 33b. Phase 6.5 prompt with code review marker → check-predecessor-checkpoint skips
exit_code=0
output=$(echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- 代码审查 -->\nReview"},"cwd":"/tmp/test"}' |
  bash "$SCRIPT_DIR/check-predecessor-checkpoint.sh" 2>/dev/null) || exit_code=$?
assert_exit "Phase 6.5 no phase marker → predecessor check skips (exit 0)" 0 $exit_code
assert_not_contains "Phase 6.5 → no deny" "$output" "deny"

teardown_autopilot_fixture
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1
exit 0

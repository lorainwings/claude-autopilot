#!/usr/bin/env bash
# test_phase5_serial.sh — Section 43: Phase 5 serial task checkpoint compatibility
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../runtime/scripts" && pwd)"
source "$TEST_DIR/_test_helpers.sh"
source "$TEST_DIR/_fixtures.sh"

echo "--- 43. Phase 5 serial task checkpoint compatibility ---"
setup_autopilot_fixture

# 43a. Phase 5 envelope with tasks_completed field → no block
exit_code=0
output=$(echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:5 -->\nPhase 5"},"tool_response":"Done. {\"status\":\"ok\",\"summary\":\"All tasks implemented\",\"test_results_path\":\"tests/results.json\",\"tasks_completed\":8,\"zero_skip_check\":{\"passed\":true}}"}' \
  | bash "$SCRIPT_DIR/validate-json-envelope.sh" 2>/dev/null) || exit_code=$?
assert_exit "Phase 5 serial task complete → exit 0" 0 $exit_code
assert_not_contains "Phase 5 serial complete → no block" "$output" "block"

# 43b. Phase 5 envelope without iterations_used (removed field) → still valid
exit_code=0
output=$(echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:5 -->\nPhase 5"},"tool_response":"Done. {\"status\":\"ok\",\"summary\":\"8/8 tasks complete\",\"test_results_path\":\"test.json\",\"tasks_completed\":8,\"zero_skip_check\":{\"passed\":true}}"}' \
  | bash "$SCRIPT_DIR/validate-json-envelope.sh" 2>/dev/null) || exit_code=$?
assert_exit "Phase 5 no iterations_used → exit 0" 0 $exit_code
assert_not_contains "Phase 5 no iterations_used → no block" "$output" "block"

# 43c. PreCompact hook scans phase5-tasks/ directory
if grep -q 'phase5-tasks' "$SCRIPT_DIR/save-state-before-compact.sh"; then
  green "  PASS: PreCompact hook scans phase5-tasks/"
  PASS=$((PASS + 1))
else
  red "  FAIL: PreCompact hook missing phase5-tasks/ scan"
  FAIL=$((FAIL + 1))
fi

# 43d. PreCompact creates task progress in state
if grep -q 'task_number' "$SCRIPT_DIR/save-state-before-compact.sh"; then
  green "  PASS: PreCompact generates task progress in state"
  PASS=$((PASS + 1))
else
  red "  FAIL: PreCompact missing task progress generation"
  FAIL=$((FAIL + 1))
fi

teardown_autopilot_fixture
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1; exit 0

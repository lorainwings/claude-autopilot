#!/usr/bin/env bash
# test_anti_rationalization.sh — Section 22: anti-rationalization-check.sh
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../scripts" && pwd)"
source "$TEST_DIR/_test_helpers.sh"
source "$TEST_DIR/_fixtures.sh"

echo "--- 22. anti-rationalization-check.sh tests ---"
setup_autopilot_fixture

# 22a. Non-autopilot task → exit 0, no output
exit_code=0
output=$(echo '{"tool_name":"Task","tool_input":{"prompt":"Do something"},"tool_response":"Done"}' \
  | bash "$SCRIPT_DIR/anti-rationalization-check.sh" 2>/dev/null) || exit_code=$?
assert_exit "anti-rational: non-autopilot → allow" 0 $exit_code
assert_not_contains "anti-rational: non-autopilot → no block" "$output" "block"

# 22b. Phase 4 with rationalization pattern → block
exit_code=0
output=$(echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:4 -->\nDesign tests"},"tool_response":"Results: {\"status\":\"ok\",\"summary\":\"Done\",\"test_counts\":{\"unit\":10},\"dry_run_results\":{\"unit\":0},\"test_pyramid\":{\"unit_pct\":80},\"artifacts\":[\"test.py\"]} Note: Some tests were skipped because they are out of scope for this phase and not needed at this time."}' \
  | bash "$SCRIPT_DIR/anti-rationalization-check.sh" 2>/dev/null) || exit_code=$?
assert_exit "anti-rational: pattern detected → exit 0" 0 $exit_code
assert_contains "anti-rational: pattern detected → block" "$output" "block"
assert_contains "anti-rational: pattern mentions rationalization" "$output" "rationalization"

# 22c. Phase 4 with blocked status → no check (legitimate stop)
exit_code=0
output=$(echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:4 -->\nDesign tests"},"tool_response":"{\"status\":\"blocked\",\"summary\":\"Cannot proceed, out of scope\"}"}' \
  | bash "$SCRIPT_DIR/anti-rationalization-check.sh" 2>/dev/null) || exit_code=$?
assert_exit "anti-rational: blocked status → allow" 0 $exit_code
assert_not_contains "anti-rational: blocked status → no block" "$output" "block"

# 22d. Phase 2 (non-critical phase) → skip even with patterns
exit_code=0
output=$(echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:2 -->\nCreate openspec"},"tool_response":"{\"status\":\"ok\",\"summary\":\"Skipped this test because not needed\"}"}' \
  | bash "$SCRIPT_DIR/anti-rationalization-check.sh" 2>/dev/null) || exit_code=$?
assert_exit "anti-rational: phase 2 → skip" 0 $exit_code
assert_not_contains "anti-rational: phase 2 → no block" "$output" "block"

teardown_autopilot_fixture
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1; exit 0

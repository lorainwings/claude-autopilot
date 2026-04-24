#!/usr/bin/env bash
# test_anti_rationalization.sh — Section 22: anti-rationalization validation
# Production target: _post_task_validator.py Validator 2 (v4.0+)
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../runtime/scripts" && pwd)"
source "$TEST_DIR/_test_helpers.sh"
source "$TEST_DIR/_fixtures.sh"

echo "--- 22. anti-rationalization tests (_post_task_validator.py) ---"
setup_autopilot_fixture
export SCRIPT_DIR

# Helper: run validator with given JSON input
run_validator() {
  echo "$1" | python3 "$SCRIPT_DIR/_post_task_validator.py" 2>/dev/null
}

# 22a. Non-autopilot task → exit 0, no output
exit_code=0
output=$(run_validator '{"tool_name":"Task","tool_input":{"prompt":"Do something"},"tool_response":"Done"}') || exit_code=$?
assert_exit "anti-rational: non-autopilot → allow" 0 $exit_code
assert_not_contains "anti-rational: non-autopilot → no block" "$output" "block"

# 22b. Phase 5 with strong rationalization patterns → block
# Score: "skipped because" (3) + "out of scope" (2) + "not needed" (1) = 6 ≥ 5 threshold
exit_code=0
output=$(run_validator '{"tool_name":"Task","cwd":"'"$REPO_ROOT"'","tool_input":{"prompt":"<!-- autopilot-phase:5 -->\nImplement feature"},"tool_response":"Results: {\"status\":\"ok\",\"summary\":\"Done\",\"test_results_path\":\"tests/\",\"tasks_completed\":3,\"zero_skip_check\":{\"passed\":true},\"artifacts\":[\"src/auth.ts\"]} Note: Some tests were skipped because they are out of scope for this phase and not needed at this time."}') || exit_code=$?
assert_exit "anti-rational: pattern detected → exit 0" 0 $exit_code
assert_contains "anti-rational: pattern detected → block" "$output" "block"
assert_contains "anti-rational: block mentions rationalization" "$output" "rationalization"

# 22c. Phase 5 with blocked status → no anti-rationalization check (legitimate stop)
exit_code=0
output=$(run_validator '{"tool_name":"Task","cwd":"'"$REPO_ROOT"'","tool_input":{"prompt":"<!-- autopilot-phase:5 -->\nImplement feature"},"tool_response":"{\"status\":\"blocked\",\"summary\":\"Cannot proceed, out of scope\",\"test_results_path\":\"tests/\",\"tasks_completed\":0,\"zero_skip_check\":{\"passed\":false}}"}') || exit_code=$?
assert_exit "anti-rational: blocked status → allow" 0 $exit_code
assert_not_contains "anti-rational: blocked status → no block" "$output" "block"

# 22d. Phase 2 (non-critical phase for anti-rationalization) → skip patterns check
exit_code=0
output=$(run_validator '{"tool_name":"Task","cwd":"'"$REPO_ROOT"'","tool_input":{"prompt":"<!-- autopilot-phase:2 -->\nCreate openspec"},"tool_response":"{\"status\":\"ok\",\"summary\":\"Skipped this test because not needed\",\"artifacts\":[\"openspec/proposal.md\"],\"alternatives\":[\"Option A\",\"Option B\"]}"}') || exit_code=$?
assert_exit "anti-rational: phase 2 → skip" 0 $exit_code
assert_not_contains "anti-rational: phase 2 → no block" "$output" "block"

teardown_autopilot_fixture
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1
exit 0

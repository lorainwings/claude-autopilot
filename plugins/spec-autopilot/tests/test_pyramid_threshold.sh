#!/usr/bin/env bash
# test_pyramid_threshold.sh — Section 24: test_pyramid threshold tests
# Production target: _post_task_validator.py (v4.0+)
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../runtime/scripts" && pwd)"
source "$TEST_DIR/_test_helpers.sh"
source "$TEST_DIR/_fixtures.sh"

echo "--- 24. test_pyramid threshold tests (_post_task_validator.py) ---"
setup_autopilot_fixture
export SCRIPT_DIR

# Helper: run validator with given JSON input
run_validator() {
  echo "$1" | python3 "$SCRIPT_DIR/_post_task_validator.py" 2>/dev/null
}

# 24a. Valid pyramid → allow
exit_code=0
output=$(run_validator '{"tool_name":"Task","cwd":"'"$REPO_ROOT"'","tool_input":{"prompt":"<!-- autopilot-phase:4 -->\nPhase 4"},"tool_response":"Results: {\"status\":\"ok\",\"summary\":\"Tests designed\",\"test_counts\":{\"unit\":15,\"api\":5,\"e2e\":3,\"ui\":2},\"sad_path_counts\":{\"unit\":4,\"api\":2,\"e2e\":1,\"ui\":1},\"dry_run_results\":{\"unit\":0,\"api\":0,\"e2e\":0,\"ui\":0},\"test_pyramid\":{\"unit_pct\":60,\"e2e_pct\":20},\"change_coverage\":{\"change_points\":[\"X\"],\"tested_points\":[\"X\"],\"coverage_pct\":100,\"untested_points\":[]},\"artifacts\":[\"tests/unit.py\",\"tests/e2e.py\"]}"}') || exit_code=$?
assert_exit "pyramid: valid distribution → exit 0" 0 $exit_code
assert_not_contains "pyramid: valid distribution → no block" "$output" "block"

# 24b. Inverted pyramid (too few unit, too many e2e) → block
exit_code=0
output=$(run_validator '{"tool_name":"Task","cwd":"'"$REPO_ROOT"'","tool_input":{"prompt":"<!-- autopilot-phase:4 -->\nPhase 4"},"tool_response":"Results: {\"status\":\"ok\",\"summary\":\"Tests designed\",\"test_counts\":{\"unit\":2,\"api\":2,\"e2e\":8,\"ui\":3},\"sad_path_counts\":{\"unit\":1,\"api\":1,\"e2e\":2,\"ui\":1},\"dry_run_results\":{\"unit\":0},\"test_pyramid\":{\"unit_pct\":13,\"e2e_pct\":53},\"change_coverage\":{\"change_points\":[\"X\"],\"tested_points\":[\"X\"],\"coverage_pct\":100,\"untested_points\":[]},\"artifacts\":[\"tests/e2e.py\"]}"}') || exit_code=$?
assert_exit "pyramid: inverted → exit 0" 0 $exit_code
assert_contains "pyramid: inverted → block" "$output" "block"
assert_contains "pyramid: inverted → mentions floor" "$output" "floor"

# 24c. Too few total cases → block
exit_code=0
output=$(run_validator '{"tool_name":"Task","cwd":"'"$REPO_ROOT"'","tool_input":{"prompt":"<!-- autopilot-phase:4 -->\nPhase 4"},"tool_response":"Results: {\"status\":\"ok\",\"summary\":\"Tests\",\"test_counts\":{\"unit\":3,\"api\":2,\"e2e\":1,\"ui\":1},\"sad_path_counts\":{\"unit\":1,\"api\":1,\"e2e\":1,\"ui\":1},\"dry_run_results\":{\"unit\":0},\"test_pyramid\":{\"unit_pct\":43,\"e2e_pct\":14},\"change_coverage\":{\"change_points\":[\"X\"],\"tested_points\":[\"X\"],\"coverage_pct\":100,\"untested_points\":[]},\"artifacts\":[\"test.py\"]}"}') || exit_code=$?
assert_exit "pyramid: too few cases → exit 0" 0 $exit_code
assert_contains "pyramid: too few total → block" "$output" "block"
assert_contains "pyramid: too few total → mentions minimum" "$output" "minimum"

# 24d. Boundary: exactly at limits → allow
exit_code=0
output=$(run_validator '{"tool_name":"Task","cwd":"'"$REPO_ROOT"'","tool_input":{"prompt":"<!-- autopilot-phase:4 -->\nPhase 4"},"tool_response":"Results: {\"status\":\"ok\",\"summary\":\"Tests\",\"test_counts\":{\"unit\":5,\"api\":3,\"e2e\":1,\"ui\":1},\"sad_path_counts\":{\"unit\":2,\"api\":1,\"e2e\":1,\"ui\":1},\"dry_run_results\":{\"unit\":0},\"test_pyramid\":{\"unit_pct\":30,\"e2e_pct\":40},\"change_coverage\":{\"change_points\":[\"X\"],\"tested_points\":[\"X\"],\"coverage_pct\":100,\"untested_points\":[]},\"artifacts\":[\"test.py\"]}"}') || exit_code=$?
assert_exit "pyramid: boundary values → exit 0" 0 $exit_code
assert_not_contains "pyramid: boundary values → no block" "$output" "block"

teardown_autopilot_fixture
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1
exit 0

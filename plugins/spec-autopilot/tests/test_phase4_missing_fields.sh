#!/usr/bin/env bash
# test_phase4_missing_fields.sh — Section 32: Phase 4 missing required fields
# Production target: _post_task_validator.py (v4.0+)
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../runtime/scripts" && pwd)"
source "$TEST_DIR/_test_helpers.sh"
source "$TEST_DIR/_fixtures.sh"

echo "--- 32. Phase 4 missing individual required fields (_post_task_validator.py) ---"
setup_autopilot_fixture
export SCRIPT_DIR

# Helper: run validator with given JSON input
run_validator() {
  echo "$1" | python3 "$SCRIPT_DIR/_post_task_validator.py" 2>/dev/null
}

# 32a. Phase 4 missing test_pyramid → should block
# Include all other required fields: test_counts, sad_path_counts, dry_run_results, change_coverage
exit_code=0
output=$(run_validator '{"tool_name":"Task","cwd":"'"$REPO_ROOT"'","tool_input":{"prompt":"<!-- autopilot-phase:4 -->\nPhase 4"},"tool_response":"Result: {\"status\":\"ok\",\"summary\":\"Tests done\",\"artifacts\":[\"tests/unit.py\"],\"test_counts\":{\"unit\":10,\"api\":5,\"e2e\":3,\"ui\":2},\"sad_path_counts\":{\"unit\":2,\"api\":1,\"e2e\":1,\"ui\":1},\"dry_run_results\":{\"unit\":0,\"api\":0,\"e2e\":0,\"ui\":0},\"change_coverage\":{\"change_points\":[\"A\"],\"tested_points\":[\"A\"],\"coverage_pct\":100,\"untested_points\":[]}}"}') || exit_code=$?
assert_exit "Phase 4 missing test_pyramid → exit 0" 0 $exit_code
assert_contains "Phase 4 missing test_pyramid → block" "$output" "block"
assert_contains "Phase 4 missing test_pyramid → mentions field" "$output" "test_pyramid"

# 32b. Phase 4 missing dry_run_results → should block
exit_code=0
output=$(run_validator '{"tool_name":"Task","cwd":"'"$REPO_ROOT"'","tool_input":{"prompt":"<!-- autopilot-phase:4 -->\nPhase 4"},"tool_response":"Result: {\"status\":\"ok\",\"summary\":\"Tests done\",\"artifacts\":[\"tests/unit.py\"],\"test_counts\":{\"unit\":10,\"api\":5,\"e2e\":3,\"ui\":2},\"sad_path_counts\":{\"unit\":2,\"api\":1,\"e2e\":1,\"ui\":1},\"test_pyramid\":{\"unit_pct\":50,\"e2e_pct\":15},\"change_coverage\":{\"change_points\":[\"A\"],\"tested_points\":[\"A\"],\"coverage_pct\":100,\"untested_points\":[]}}"}') || exit_code=$?
assert_exit "Phase 4 missing dry_run_results → exit 0" 0 $exit_code
assert_contains "Phase 4 missing dry_run_results → block" "$output" "block"

# 32c. Phase 4 missing test_counts → should block
exit_code=0
output=$(run_validator '{"tool_name":"Task","cwd":"'"$REPO_ROOT"'","tool_input":{"prompt":"<!-- autopilot-phase:4 -->\nPhase 4"},"tool_response":"Result: {\"status\":\"ok\",\"summary\":\"Tests done\",\"artifacts\":[\"tests/unit.py\"],\"sad_path_counts\":{\"unit\":2,\"api\":1},\"dry_run_results\":{\"unit\":0},\"test_pyramid\":{\"unit_pct\":50,\"e2e_pct\":15},\"change_coverage\":{\"change_points\":[\"A\"],\"tested_points\":[\"A\"],\"coverage_pct\":100,\"untested_points\":[]}}"}') || exit_code=$?
assert_exit "Phase 4 missing test_counts → exit 0" 0 $exit_code
assert_contains "Phase 4 missing test_counts → block" "$output" "block"

# 32d. Phase 4 missing sad_path_counts → should block (v4.2 required field)
exit_code=0
output=$(run_validator '{"tool_name":"Task","cwd":"'"$REPO_ROOT"'","tool_input":{"prompt":"<!-- autopilot-phase:4 -->\nPhase 4"},"tool_response":"Result: {\"status\":\"ok\",\"summary\":\"Tests done\",\"artifacts\":[\"tests/unit.py\"],\"test_counts\":{\"unit\":10,\"api\":5,\"e2e\":3,\"ui\":2},\"dry_run_results\":{\"unit\":0,\"api\":0,\"e2e\":0,\"ui\":0},\"test_pyramid\":{\"unit_pct\":50,\"e2e_pct\":15},\"change_coverage\":{\"change_points\":[\"A\"],\"tested_points\":[\"A\"],\"coverage_pct\":100,\"untested_points\":[]}}"}') || exit_code=$?
assert_exit "Phase 4 missing sad_path_counts → exit 0" 0 $exit_code
assert_contains "Phase 4 missing sad_path_counts → block" "$output" "block"

teardown_autopilot_fixture
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1; exit 0

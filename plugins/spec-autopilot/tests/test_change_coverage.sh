#!/usr/bin/env bash
# test_change_coverage.sh — Section 40: Phase 4 change_coverage validation
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../scripts" && pwd)"
source "$TEST_DIR/_test_helpers.sh"
source "$TEST_DIR/_fixtures.sh"

echo "--- 40. Phase 4 change_coverage validation ---"
setup_autopilot_fixture

# 40a. Phase 4 with valid change_coverage → no block
exit_code=0
output=$(echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:4 -->\nPhase 4"},"tool_response":"Result: {\"status\":\"ok\",\"summary\":\"Tests created\",\"artifacts\":[\"tests/test_foo.py\"],\"test_counts\":{\"unit\":8,\"api\":5,\"e2e\":3,\"ui\":2},\"dry_run_results\":{\"unit\":0,\"api\":0,\"e2e\":0,\"ui\":0},\"test_pyramid\":{\"total\":18,\"unit_pct\":44,\"integration_pct\":28,\"e2e_pct\":28},\"change_coverage\":{\"change_points\":[\"POST /api/foo\",\"FooService.bar\"],\"tested_points\":[\"POST /api/foo\",\"FooService.bar\"],\"coverage_pct\":100,\"untested_points\":[]}}"}' \
  | bash "$SCRIPT_DIR/validate-json-envelope.sh" 2>/dev/null) || exit_code=$?
assert_exit "Phase 4 change_coverage 100% → exit 0" 0 $exit_code
assert_not_contains "Phase 4 change_coverage 100% → no block" "$output" "block"

# 40b. Phase 4 with low change_coverage → block
exit_code=0
output=$(echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:4 -->\nPhase 4"},"tool_response":"Result: {\"status\":\"ok\",\"summary\":\"Tests created\",\"artifacts\":[\"tests/test_foo.py\"],\"test_counts\":{\"unit\":8,\"api\":5,\"e2e\":3,\"ui\":2},\"dry_run_results\":{\"unit\":0,\"api\":0,\"e2e\":0,\"ui\":0},\"test_pyramid\":{\"total\":18,\"unit_pct\":44,\"integration_pct\":28,\"e2e_pct\":28},\"change_coverage\":{\"change_points\":[\"POST /api/foo\",\"FooService.bar\",\"ChatPanel.vue\"],\"tested_points\":[\"POST /api/foo\"],\"coverage_pct\":33,\"untested_points\":[\"FooService.bar\",\"ChatPanel.vue\"]}}"}' \
  | bash "$SCRIPT_DIR/validate-json-envelope.sh" 2>/dev/null) || exit_code=$?
assert_exit "Phase 4 change_coverage 33% → exit 0" 0 $exit_code
assert_contains "Phase 4 change_coverage 33% → block" "$output" "block"
assert_contains "Phase 4 change_coverage → mentions coverage" "$output" "change_coverage"

# 40c. Phase 4 missing change_coverage → block (required field)
exit_code=0
output=$(echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:4 -->\nPhase 4"},"tool_response":"Result: {\"status\":\"ok\",\"summary\":\"Tests created\",\"artifacts\":[\"tests/test_foo.py\"],\"test_counts\":{\"unit\":8,\"api\":5,\"e2e\":3,\"ui\":2},\"dry_run_results\":{\"unit\":0,\"api\":0,\"e2e\":0,\"ui\":0},\"test_pyramid\":{\"total\":18,\"unit_pct\":44,\"integration_pct\":28,\"e2e_pct\":28}}"}' \
  | bash "$SCRIPT_DIR/validate-json-envelope.sh" 2>/dev/null) || exit_code=$?
assert_exit "Phase 4 missing change_coverage → exit 0" 0 $exit_code
assert_contains "Phase 4 missing change_coverage → block" "$output" "block"
assert_contains "Phase 4 missing change_coverage → mentions field" "$output" "change_coverage"

# 40d. Phase 4 change_coverage at 80% boundary → no block
exit_code=0
output=$(echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:4 -->\nPhase 4"},"tool_response":"Result: {\"status\":\"ok\",\"summary\":\"Tests created\",\"artifacts\":[\"tests/test_foo.py\"],\"test_counts\":{\"unit\":8,\"api\":5,\"e2e\":3,\"ui\":2},\"dry_run_results\":{\"unit\":0,\"api\":0,\"e2e\":0,\"ui\":0},\"test_pyramid\":{\"total\":18,\"unit_pct\":44,\"integration_pct\":28,\"e2e_pct\":28},\"change_coverage\":{\"change_points\":[\"A\",\"B\",\"C\",\"D\",\"E\"],\"tested_points\":[\"A\",\"B\",\"C\",\"D\"],\"coverage_pct\":80,\"untested_points\":[\"E\"]}}"}' \
  | bash "$SCRIPT_DIR/validate-json-envelope.sh" 2>/dev/null) || exit_code=$?
assert_exit "Phase 4 change_coverage 80% boundary → exit 0" 0 $exit_code
assert_not_contains "Phase 4 change_coverage 80% boundary → no block" "$output" "block"

# 40e. Phase 4 empty change_coverage object → block (malformed)
exit_code=0
output=$(echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:4 -->\nPhase 4"},"tool_response":"Result: {\"status\":\"ok\",\"summary\":\"Tests\",\"artifacts\":[\"t.py\"],\"test_counts\":{\"unit\":10,\"api\":5,\"e2e\":3,\"ui\":2},\"dry_run_results\":{\"unit\":0,\"api\":0,\"e2e\":0,\"ui\":0},\"test_pyramid\":{\"total\":20,\"unit_pct\":50,\"integration_pct\":25,\"e2e_pct\":25},\"change_coverage\":{}}"}' \
  | bash "$SCRIPT_DIR/validate-json-envelope.sh" 2>/dev/null) || exit_code=$?
assert_exit "Phase 4 empty change_coverage → exit 0" 0 $exit_code
assert_contains "Phase 4 empty change_coverage → block" "$output" "block"
assert_contains "Phase 4 empty change_coverage → mentions malformed" "$output" "malformed"

teardown_autopilot_fixture
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1; exit 0

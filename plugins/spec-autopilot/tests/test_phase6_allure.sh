#!/usr/bin/env bash
# test_phase6_allure.sh — Section 17: Phase 6 envelope Allure fields
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../runtime/scripts" && pwd)"
source "$TEST_DIR/_test_helpers.sh"
source "$TEST_DIR/_fixtures.sh"

echo "--- 17. Phase 6 envelope validation (Allure fields) ---"
setup_autopilot_fixture

# 17a. Phase 6 with allure report_format → should pass
exit_code=0
output=$(echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:6 -->\nPhase 6"},"tool_response":"Report: {\"status\":\"ok\",\"summary\":\"All tests pass\",\"artifacts\":[\"allure-report/index.html\"],\"pass_rate\":98.5,\"report_path\":\"openspec/changes/test/testreport/allure-report/index.html\",\"report_format\":\"allure\",\"allure_results_dir\":\"allure-results\",\"suite_results\":[{\"suite\":\"unit\",\"total\":10,\"passed\":10,\"failed\":0,\"skipped\":0}]}"}' \
  | bash "$SCRIPT_DIR/validate-json-envelope.sh" 2>/dev/null) || exit_code=$?
assert_exit "Phase 6 allure format → exit 0" 0 $exit_code
assert_not_contains "Phase 6 allure format → no block" "$output" "block"

# 17b. Phase 6 with custom report_format → should also pass (format validation is Layer 3)
exit_code=0
output=$(echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:6 -->\nPhase 6"},"tool_response":"Report: {\"status\":\"ok\",\"summary\":\"All tests pass\",\"artifacts\":[\"reports/test-report.html\"],\"pass_rate\":95.0,\"report_path\":\"openspec/changes/test/testreport/test-report.html\",\"report_format\":\"custom\",\"suite_results\":[{\"suite\":\"unit\",\"total\":10,\"passed\":10,\"failed\":0,\"skipped\":0}]}"}' \
  | bash "$SCRIPT_DIR/validate-json-envelope.sh" 2>/dev/null) || exit_code=$?
assert_exit "Phase 6 custom format → exit 0" 0 $exit_code
assert_not_contains "Phase 6 custom format → no block" "$output" "block"

# 17c. Phase 6 missing report_format → should block (required phase-specific field)
exit_code=0
output=$(echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:6 -->\nPhase 6"},"tool_response":"Report: {\"status\":\"ok\",\"summary\":\"All tests pass\",\"artifacts\":[\"reports/final.html\"],\"pass_rate\":98.5,\"report_path\":\"reports/final.html\"}"}' \
  | bash "$SCRIPT_DIR/validate-json-envelope.sh" 2>/dev/null) || exit_code=$?
assert_exit "Phase 6 missing report_format → exit 0" 0 $exit_code
assert_contains "Phase 6 missing report_format → block" "$output" "block"

teardown_autopilot_fixture
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1; exit 0

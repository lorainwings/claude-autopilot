#!/usr/bin/env bash
# test_optional_fields.sh — Section 29: v3.2.0 optional fields compatibility
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../runtime/scripts" && pwd)"
source "$TEST_DIR/_test_helpers.sh"
source "$TEST_DIR/_fixtures.sh"

echo "--- 29. v3.2.0 optional fields compatibility ---"
setup_autopilot_fixture

# 29a. Phase 4 with optional test_traceability → should pass
exit_code=0
output=$(echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:4 -->\nPhase 4"},"tool_response":"Results: {\"status\":\"ok\",\"summary\":\"Tests designed with traceability\",\"artifacts\":[\"tests/unit.py\",\"tests/e2e.py\"],\"test_counts\":{\"unit\":10,\"api\":8,\"e2e\":5,\"ui\":5},\"dry_run_results\":{\"unit\":0,\"api\":0,\"e2e\":0,\"ui\":0},\"test_pyramid\":{\"unit_pct\":36,\"e2e_pct\":18},\"change_coverage\":{\"change_points\":[\"X\"],\"tested_points\":[\"X\"],\"coverage_pct\":100,\"untested_points\":[]},\"test_traceability\":[{\"test\":\"test_login\",\"requirement\":\"REQ-1.1\"}]}"}' \
  | bash "$SCRIPT_DIR/validate-json-envelope.sh" 2>/dev/null) || exit_code=$?
assert_exit "Phase 4 with test_traceability → exit 0" 0 $exit_code
assert_not_contains "Phase 4 with test_traceability → no block" "$output" "block"

# 29b. Phase 5 with optional parallel_metrics → should pass
exit_code=0
output=$(echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:5 -->\nPhase 5"},"tool_response":"Done. {\"status\":\"ok\",\"summary\":\"All tasks done\",\"test_results_path\":\"tests/results.json\",\"tasks_completed\":8,\"zero_skip_check\":{\"passed\":true},\"parallel_metrics\":{\"mode\":\"parallel\",\"total_agents\":4,\"successful_agents\":4,\"failed_agents\":0}}"}' \
  | bash "$SCRIPT_DIR/validate-json-envelope.sh" 2>/dev/null) || exit_code=$?
assert_exit "Phase 5 with parallel_metrics → exit 0" 0 $exit_code
assert_not_contains "Phase 5 with parallel_metrics → no block" "$output" "block"

# 29c. Phase 6 with anomaly_alerts + full suite_results → should pass
exit_code=0
output=$(echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:6 -->\nPhase 6"},"tool_response":"Report: {\"status\":\"ok\",\"summary\":\"Tests completed with anomalies\",\"artifacts\":[\"allure-report/index.html\"],\"pass_rate\":95.0,\"report_path\":\"allure-report/index.html\",\"report_format\":\"allure\",\"suite_results\":[{\"suite\":\"unit\",\"total\":10,\"passed\":10,\"failed\":0,\"skipped\":0}],\"anomaly_alerts\":[\"API test_create_user failed: expected 409 got 500\"],\"allure_results_dir\":\"allure-results/\"}"}' \
  | bash "$SCRIPT_DIR/validate-json-envelope.sh" 2>/dev/null) || exit_code=$?
assert_exit "Phase 6 with anomaly_alerts → exit 0" 0 $exit_code
assert_not_contains "Phase 6 with anomaly_alerts → no block" "$output" "block"

# 29d. Phase 6 with report_url → should pass
exit_code=0
output=$(echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:6 -->\nPhase 6"},"tool_response":"Report: {\"status\":\"ok\",\"summary\":\"All pass\",\"artifacts\":[\"allure-report/index.html\"],\"pass_rate\":100,\"report_path\":\"allure-report/index.html\",\"report_format\":\"allure\",\"suite_results\":[{\"suite\":\"unit\",\"total\":5,\"passed\":5}],\"report_url\":\"file:///path/to/report/index.html\"}"}' \
  | bash "$SCRIPT_DIR/validate-json-envelope.sh" 2>/dev/null) || exit_code=$?
assert_exit "Phase 6 with report_url → exit 0" 0 $exit_code
assert_not_contains "Phase 6 with report_url → no block" "$output" "block"

teardown_autopilot_fixture
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1; exit 0

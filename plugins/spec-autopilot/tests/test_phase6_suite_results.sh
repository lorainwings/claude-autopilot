#!/usr/bin/env bash
# test_phase6_suite_results.sh — Section 28: Phase 6 suite_results validation
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../runtime/scripts" && pwd)"
source "$TEST_DIR/_test_helpers.sh"
source "$TEST_DIR/_fixtures.sh"

echo "--- 28. Phase 6 suite_results validation (v3.2.0) ---"
setup_autopilot_fixture

# 28a. Phase 6 missing suite_results → should NOT block (recommended field since v3.2.1)
exit_code=0
output=$(echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:6 -->\nPhase 6"},"tool_response":"Report: {\"status\":\"ok\",\"summary\":\"All tests pass\",\"artifacts\":[\"reports/final.html\"],\"pass_rate\":98.5,\"report_path\":\"reports/final.html\",\"report_format\":\"html\"}"}' \
  | bash "$SCRIPT_DIR/validate-json-envelope.sh" 2>/dev/null) || exit_code=$?
assert_exit "Phase 6 missing suite_results → exit 0" 0 $exit_code
assert_not_contains "Phase 6 missing suite_results → no block (recommended)" "$output" "block"

# 28b. Phase 6 with empty suite_results array → should still pass (non-empty artifacts is sufficient)
exit_code=0
output=$(echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:6 -->\nPhase 6"},"tool_response":"Report: {\"status\":\"ok\",\"summary\":\"All tests pass\",\"artifacts\":[\"reports/final.html\"],\"pass_rate\":98.5,\"report_path\":\"reports/final.html\",\"report_format\":\"html\",\"suite_results\":[]}"}' \
  | bash "$SCRIPT_DIR/validate-json-envelope.sh" 2>/dev/null) || exit_code=$?
assert_exit "Phase 6 empty suite_results → exit 0" 0 $exit_code
assert_not_contains "Phase 6 empty suite_results → no block (field exists)" "$output" "block"

teardown_autopilot_fixture

# 28c. Phase 6 missing red_evidence / sample_failure_excerpt → should NOT block (recommended)
setup_autopilot_fixture
exit_code=0
output=$(echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:6 -->\nPhase 6"},"tool_response":"Report: {\"status\":\"ok\",\"summary\":\"All tests pass\",\"artifacts\":[\"reports/final.html\"],\"pass_rate\":98.5,\"report_path\":\"reports/final.html\",\"report_format\":\"html\",\"suite_results\":[{\"suite\":\"unit\",\"total\":10,\"passed\":10,\"failed\":0,\"skipped\":0}]}"}' \
  | bash "$SCRIPT_DIR/validate-json-envelope.sh" 2>/dev/null) || exit_code=$?
assert_exit "Phase 6 missing red_evidence → exit 0 (recommended)" 0 $exit_code
assert_not_contains "Phase 6 missing red_evidence → no block" "$output" "block"

# 28d. Phase 6 with red_evidence + sample_failure_excerpt → should pass
exit_code=0
output=$(echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:6 -->\nPhase 6"},"tool_response":"Report: {\"status\":\"ok\",\"summary\":\"Tests done\",\"artifacts\":[\"reports/final.html\"],\"pass_rate\":95.0,\"report_path\":\"reports/final.html\",\"report_format\":\"html\",\"suite_results\":[],\"red_evidence\":\"FAIL: login rejects expired token\",\"sample_failure_excerpt\":\"Expected 401 got 200\"}"}' \
  | bash "$SCRIPT_DIR/validate-json-envelope.sh" 2>/dev/null) || exit_code=$?
assert_exit "Phase 6 with red_evidence + sample_failure_excerpt → exit 0" 0 $exit_code
assert_not_contains "Phase 6 with evidence fields → no block" "$output" "block"

teardown_autopilot_fixture
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1; exit 0

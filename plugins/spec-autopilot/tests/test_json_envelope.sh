#!/usr/bin/env bash
# test_json_envelope.sh — Section 3: validate-json-envelope.sh
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../scripts" && pwd)"
source "$TEST_DIR/_test_helpers.sh"
source "$TEST_DIR/_fixtures.sh"

echo "--- 3. validate-json-envelope.sh ---"
setup_autopilot_fixture

# 3a. Empty stdin → exit 0
exit_code=0
echo "" | bash "$SCRIPT_DIR/validate-json-envelope.sh" >/dev/null 2>&1 || exit_code=$?
assert_exit "empty stdin → allow" 0 $exit_code

# 3b. Non-autopilot Task → exit 0
exit_code=0
echo '{"tool_name":"Task","tool_input":{"prompt":"Find APIs"},"tool_response":"Found 3 endpoints"}' \
  | bash "$SCRIPT_DIR/validate-json-envelope.sh" >/dev/null 2>&1 || exit_code=$?
assert_exit "no marker → skip" 0 $exit_code

# 3c. Autopilot Task with valid JSON envelope in tool_response → exit 0, no block
exit_code=0
output=$(echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:3 -->\nPhase 3"},"tool_response":"Done.\n```json\n{\"status\":\"ok\",\"summary\":\"All good\",\"artifacts\":[]}\n```"}' \
  | bash "$SCRIPT_DIR/validate-json-envelope.sh" 2>/dev/null) || exit_code=$?
assert_exit "valid envelope → exit 0" 0 $exit_code
assert_not_contains "valid envelope → no block decision" "$output" "decision"

# 3d. Autopilot Task with empty tool_response → decision:block
exit_code=0
output=$(echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:3 -->\nPhase 3"},"tool_response":""}' \
  | bash "$SCRIPT_DIR/validate-json-envelope.sh" 2>/dev/null) || exit_code=$?
assert_exit "empty response → exit 0" 0 $exit_code
assert_contains "empty response → block decision" "$output" "block"

# 3e. Autopilot Task with no JSON in response → decision:block
exit_code=0
output=$(echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:4 -->\nPhase 4"},"tool_response":"I completed the task successfully without any JSON."}' \
  | bash "$SCRIPT_DIR/validate-json-envelope.sh" 2>/dev/null) || exit_code=$?
assert_exit "no JSON in response → exit 0" 0 $exit_code
assert_contains "no JSON → block decision" "$output" "block"

# 3f. Verify tool_response field is used (NOT tool_result)
exit_code=0
output=$(echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:3 -->\nPhase 3"},"tool_result":"{\"status\":\"ok\",\"summary\":\"test\"}","tool_response":"no json here"}' \
  | bash "$SCRIPT_DIR/validate-json-envelope.sh" 2>/dev/null) || exit_code=$?
# tool_result has valid JSON but tool_response doesn't → should block (proving tool_response is used)
assert_contains "uses tool_response not tool_result" "$output" "block"

# 3g. Nested JSON object (Phase 4 with test_counts + test_pyramid) → should be extracted
exit_code=0
output=$(echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:4 -->\nPhase 4"},"tool_response":"Result: {\"status\":\"ok\",\"summary\":\"Tests designed\",\"artifacts\":[\"tests/unit.test.ts\",\"tests/api.py\"],\"test_counts\":{\"unit\":10,\"api\":8,\"e2e\":5,\"ui\":5},\"dry_run_results\":{\"unit\":0,\"api\":0,\"e2e\":0,\"ui\":0},\"test_pyramid\":{\"unit_pct\":36,\"e2e_pct\":18},\"change_coverage\":{\"change_points\":[\"A\"],\"tested_points\":[\"A\"],\"coverage_pct\":100,\"untested_points\":[]}}"}' \
  | bash "$SCRIPT_DIR/validate-json-envelope.sh" 2>/dev/null) || exit_code=$?
assert_exit "nested JSON → exit 0" 0 $exit_code
assert_not_contains "nested JSON → no block" "$output" "block"

# 3h. Phase 5 with zero_skip_check → should pass
exit_code=0
output=$(echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:5 -->\nPhase 5"},"tool_response":"Done. {\"status\":\"ok\",\"summary\":\"All tasks implemented\",\"test_results_path\":\"tests/results.json\",\"tasks_completed\":8,\"zero_skip_check\":{\"passed\":true},\"iterations_used\":12}"}' \
  | bash "$SCRIPT_DIR/validate-json-envelope.sh" 2>/dev/null) || exit_code=$?
assert_exit "Phase 5 with zero_skip_check → exit 0" 0 $exit_code
assert_not_contains "Phase 5 complete → no block" "$output" "block"

# 3i. Phase 5 missing zero_skip_check → should block
exit_code=0
output=$(echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:5 -->\nPhase 5"},"tool_response":"Done. {\"status\":\"ok\",\"summary\":\"All tasks implemented\",\"test_results_path\":\"tests/results.json\",\"tasks_completed\":8}"}' \
  | bash "$SCRIPT_DIR/validate-json-envelope.sh" 2>/dev/null) || exit_code=$?
assert_exit "Phase 5 missing zero_skip_check → exit 0" 0 $exit_code
assert_contains "Phase 5 missing field → block" "$output" "block"

# 3j. Phase 6 with required fields → should pass
exit_code=0
output=$(echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:6 -->\nPhase 6"},"tool_response":"Report: {\"status\":\"ok\",\"summary\":\"All tests pass\",\"artifacts\":[\"reports/final.html\",\"reports/results.json\"],\"pass_rate\":98.5,\"report_path\":\"reports/final.html\",\"report_format\":\"html\",\"suite_results\":[{\"suite\":\"unit\",\"total\":10,\"passed\":10,\"failed\":0,\"skipped\":0}]}"}' \
  | bash "$SCRIPT_DIR/validate-json-envelope.sh" 2>/dev/null) || exit_code=$?
assert_exit "Phase 6 complete → exit 0" 0 $exit_code
assert_not_contains "Phase 6 complete → no block" "$output" "block"

# 3k. Phase 4 warning → should block (any Phase 4 warning blocks; only "ok" or "blocked" accepted)
exit_code=0
output=$(echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:4 -->\nPhase 4"},"tool_response":"Result: {\"status\":\"warning\",\"summary\":\"Tests incomplete\",\"artifacts\":[\"tests/unit.test.ts\"],\"test_counts\":{\"unit\":3,\"api\":2,\"e2e\":1,\"ui\":0},\"dry_run_results\":{\"unit\":0,\"api\":0,\"e2e\":0,\"ui\":0}}"}' \
  | bash "$SCRIPT_DIR/validate-json-envelope.sh" 2>/dev/null) || exit_code=$?
assert_exit "Phase 4 warning → exit 0" 0 $exit_code
assert_contains "Phase 4 warning → block" "$output" "block"

# 3l. Phase 4 with empty artifacts → should block (M4 fix)
exit_code=0
output=$(echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:4 -->\nPhase 4"},"tool_response":"Result: {\"status\":\"ok\",\"summary\":\"Tests designed\",\"artifacts\":[],\"test_counts\":{\"unit\":10,\"api\":8,\"e2e\":5,\"ui\":5},\"dry_run_results\":{\"unit\":0,\"api\":0,\"e2e\":0,\"ui\":0}}"}' \
  | bash "$SCRIPT_DIR/validate-json-envelope.sh" 2>/dev/null) || exit_code=$?
assert_exit "Phase 4 empty artifacts → exit 0" 0 $exit_code
assert_contains "Phase 4 empty artifacts → block" "$output" "block"

# 3m. Phase 6 with empty artifacts → should block (M4 fix)
exit_code=0
output=$(echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:6 -->\nPhase 6"},"tool_response":"Report: {\"status\":\"ok\",\"summary\":\"All tests pass\",\"artifacts\":[],\"pass_rate\":98.5,\"report_path\":\"reports/final.html\"}"}' \
  | bash "$SCRIPT_DIR/validate-json-envelope.sh" 2>/dev/null) || exit_code=$?
assert_exit "Phase 6 empty artifacts → exit 0" 0 $exit_code
assert_contains "Phase 6 empty artifacts → block" "$output" "block"

# 3n. Lock file detection (C2 fix) — tested via predecessor hook
# (Lock file test requires filesystem setup, covered by integration tests)

teardown_autopilot_fixture
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1; exit 0

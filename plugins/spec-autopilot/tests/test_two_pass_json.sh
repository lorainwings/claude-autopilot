#!/usr/bin/env bash
# test_two_pass_json.sh — Section 27: Two-pass JSON extraction
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../runtime/scripts" && pwd)"
source "$TEST_DIR/_test_helpers.sh"
source "$TEST_DIR/_fixtures.sh"

echo "--- 27. Two-pass JSON extraction (v3.2.0 bug fix) ---"
setup_autopilot_fixture

# 27a. Response with multiple JSON objects: first has status but no summary → should extract the SECOND one
exit_code=0
output=$(echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:3 -->\nPhase 3"},"tool_response":"Skill executed successfully. Result: {\"status\":\"ok\"}\nNow here is the actual envelope:\n{\"status\":\"ok\",\"summary\":\"OpenSpec change created with all context files\",\"artifacts\":[\"openspec/changes/test/proposal.md\"]}"}' |
  bash "$SCRIPT_DIR/validate-json-envelope.sh" 2>/dev/null) || exit_code=$?
assert_exit "two-pass: prefers JSON with both status+summary → exit 0" 0 $exit_code
assert_not_contains "two-pass: correct envelope extracted → no block" "$output" "block"

# 27b. Response with only status-only JSON (no summary) → v3.3.0: summary is recommended not required, no block
exit_code=0
output=$(echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:3 -->\nPhase 3"},"tool_response":"Tool output: {\"status\":\"ok\",\"code\":200}"}' |
  bash "$SCRIPT_DIR/validate-json-envelope.sh" 2>/dev/null) || exit_code=$?
assert_exit "two-pass: fallback to status-only → exit 0" 0 $exit_code
assert_not_contains "two-pass: status-only no summary → no block (v3.3.0)" "$output" "block"

# 27c. Response with tool JSON (has status, no summary) followed by envelope in code block
exit_code=0
output=$(echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:5 -->\nPhase 5"},"tool_response":"Command result: {\"status\":\"success\",\"exit_code\":0}\nFinal result:\n```json\n{\"status\":\"ok\",\"summary\":\"All 8 tasks completed\",\"test_results_path\":\"tests/results.json\",\"tasks_completed\":8,\"zero_skip_check\":{\"passed\":true}}\n```"}' |
  bash "$SCRIPT_DIR/validate-json-envelope.sh" 2>/dev/null) || exit_code=$?
assert_exit "two-pass: tool output + code block envelope → exit 0" 0 $exit_code
assert_not_contains "two-pass: tool output + code block → no block" "$output" "block"

# 27d. Multiple JSON objects all with status+summary → first one wins
exit_code=0
output=$(echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:3 -->\nPhase 3"},"tool_response":"First: {\"status\":\"ok\",\"summary\":\"First envelope\"} Second: {\"status\":\"warning\",\"summary\":\"Second envelope\"}"}' |
  bash "$SCRIPT_DIR/validate-json-envelope.sh" 2>/dev/null) || exit_code=$?
assert_exit "two-pass: multiple full envelopes → exit 0" 0 $exit_code
assert_not_contains "two-pass: first full envelope wins → no block" "$output" "block"

teardown_autopilot_fixture
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1
exit 0

#!/usr/bin/env bash
# test_quality_scan_bypass.sh — Section 36: Quality scan prompt bypass
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../runtime/scripts" && pwd)"
source "$TEST_DIR/_test_helpers.sh"
source "$TEST_DIR/_fixtures.sh"

echo "--- 36. v3.2.2 Quality scan prompt bypass (no autopilot-phase marker) ---"
setup_autopilot_fixture

# 36a. Quality scan prompt → validate-json-envelope skips
exit_code=0
output=$(echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-quality-scan:security -->\nRun security scan"},"tool_response":"Scan complete."}' \
  | bash "$SCRIPT_DIR/validate-json-envelope.sh" 2>/dev/null) || exit_code=$?
assert_exit "Quality scan no autopilot-phase marker → exit 0 (skip)" 0 $exit_code
assert_not_contains "Quality scan → no block" "$output" "block"

# 36b. Quality scan prompt → check-predecessor-checkpoint skips
exit_code=0
output=$(echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-quality-scan:perf -->\nPerf audit"},"cwd":"/tmp"}' \
  | bash "$SCRIPT_DIR/check-predecessor-checkpoint.sh" 2>/dev/null) || exit_code=$?
assert_exit "Quality scan → predecessor check skips (exit 0)" 0 $exit_code

teardown_autopilot_fixture
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1; exit 0

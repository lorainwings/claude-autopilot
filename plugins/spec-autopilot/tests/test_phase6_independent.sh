#!/usr/bin/env bash
# test_phase6_independent.sh — Section 35: Phase 6 independent of Phase 6.5
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../runtime/scripts" && pwd)"
source "$TEST_DIR/_test_helpers.sh"
source "$TEST_DIR/_fixtures.sh"

echo "--- 35. v3.2.2 Phase 6 checkpoint independent of Phase 6.5 fields ---"
setup_autopilot_fixture

# 35a. Phase 6 envelope with pass_rate/report_path/report_format → valid (no findings/metrics needed)
exit_code=0
output=$(echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:6 -->\nPhase 6"},"tool_response":"Result: {\"status\":\"ok\",\"summary\":\"All tests pass\",\"artifacts\":[\"report.html\"],\"pass_rate\":100,\"report_path\":\"report.html\",\"report_format\":\"html\"}"}' \
  | bash "$SCRIPT_DIR/validate-json-envelope.sh" 2>/dev/null) || exit_code=$?
assert_exit "Phase 6 without findings/metrics → exit 0" 0 $exit_code
assert_not_contains "Phase 6 independent of 6.5 fields → no block" "$output" "block"

teardown_autopilot_fixture
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1; exit 0

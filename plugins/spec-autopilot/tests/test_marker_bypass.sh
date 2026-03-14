#!/usr/bin/env bash
# test_marker_bypass.sh — Section 8: Pure bash marker bypass
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../scripts" && pwd)"
source "$TEST_DIR/_test_helpers.sh"
source "$TEST_DIR/_fixtures.sh"

echo "--- 8. Pure bash marker bypass (P2 performance) ---"
setup_autopilot_fixture

# 8a. Non-autopilot Task bypasses without calling python3
# Verify no stdout output (no deny, no block) and exit 0
exit_code=0
output=$(echo '{"tool_name":"Task","tool_input":{"prompt":"Search for all TODO comments in the codebase","subagent_type":"Explore"}}' \
  | bash "$SCRIPT_DIR/check-predecessor-checkpoint.sh" 2>/dev/null) || exit_code=$?
assert_exit "non-autopilot bypass (predecessor) → exit 0" 0 $exit_code
assert_not_contains "non-autopilot bypass → no deny output" "$output" "deny"

exit_code=0
output=$(echo '{"tool_name":"Task","tool_input":{"prompt":"Search for all TODO comments in the codebase"},"tool_response":"Found 42 TODOs"}' \
  | bash "$SCRIPT_DIR/validate-json-envelope.sh" 2>/dev/null) || exit_code=$?
assert_exit "non-autopilot bypass (envelope) → exit 0" 0 $exit_code
assert_not_contains "non-autopilot bypass → no block output" "$output" "block"

teardown_autopilot_fixture
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1; exit 0

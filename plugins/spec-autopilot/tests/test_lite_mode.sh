#!/usr/bin/env bash
# test_lite_mode.sh — Section 38: Lite mode tri-path parallel compatibility
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../scripts" && pwd)"
source "$TEST_DIR/_test_helpers.sh"
source "$TEST_DIR/_fixtures.sh"

echo "--- 38. v3.2.2 Lite mode: Phase 6 tri-path parallel compatibility ---"
setup_autopilot_fixture

LITE_TEST_DIR=$(mktemp -d)
mkdir -p "$LITE_TEST_DIR/openspec/changes/test-lite/context/phase-results"
echo '{"change":"test-lite","mode":"lite"}' > "$LITE_TEST_DIR/openspec/changes/.autopilot-active"
echo '{"status":"ok","summary":"Impl done","zero_skip_check":{"passed":true},"tasks_completed":"3/3","test_results_path":"test-results.json"}' \
  > "$LITE_TEST_DIR/openspec/changes/test-lite/context/phase-results/phase-5-implement.json"

# 38a. Lite mode: Phase 5 → Phase 6 allowed
exit_code=0
output=$(echo "{\"tool_name\":\"Task\",\"tool_input\":{\"prompt\":\"<!-- autopilot-phase:6 -->\\nPhase 6\",\"subagent_type\":\"qa-expert\"},\"cwd\":\"$LITE_TEST_DIR\"}" \
  | bash "$SCRIPT_DIR/check-predecessor-checkpoint.sh" 2>/dev/null) || exit_code=$?
assert_exit "Lite: Phase 5 ok → Phase 6 allow (exit 0)" 0 $exit_code
assert_not_contains "Lite: Phase 6 no deny" "$output" "deny"

# 38b. Lite mode: Phase 6 ok → Phase 7 allowed
echo '{"status":"ok","summary":"Tests passed","pass_rate":95,"report_path":"r.html","report_format":"html"}' \
  > "$LITE_TEST_DIR/openspec/changes/test-lite/context/phase-results/phase-6-report.json"
exit_code=0
output=$(echo "{\"tool_name\":\"Task\",\"tool_input\":{\"prompt\":\"<!-- autopilot-phase:7 -->\\nPhase 7\",\"subagent_type\":\"general-purpose\"},\"cwd\":\"$LITE_TEST_DIR\"}" \
  | bash "$SCRIPT_DIR/check-predecessor-checkpoint.sh" 2>/dev/null) || exit_code=$?
assert_exit "Lite: Phase 6 ok → Phase 7 allow (exit 0)" 0 $exit_code
assert_not_contains "Lite: Phase 7 no deny" "$output" "deny"

rm -rf "$LITE_TEST_DIR"

teardown_autopilot_fixture
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1; exit 0

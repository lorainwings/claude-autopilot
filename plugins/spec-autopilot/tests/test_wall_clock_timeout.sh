#!/usr/bin/env bash
# test_wall_clock_timeout.sh — Section 23: Wall-clock timeout tests
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../runtime/scripts" && pwd)"
source "$TEST_DIR/_test_helpers.sh"
source "$TEST_DIR/_fixtures.sh"

echo "--- 23. Wall-clock timeout tests ---"
setup_autopilot_fixture

WALLCLOCK_TEST_DIR=$(mktemp -d)
mkdir -p "$WALLCLOCK_TEST_DIR/openspec/changes/test-change/context/phase-results"
echo '{"change":"test-change"}' >"$WALLCLOCK_TEST_DIR/openspec/changes/.autopilot-active"
echo '{"status":"ok"}' >"$WALLCLOCK_TEST_DIR/openspec/changes/test-change/context/phase-results/phase-4-testing.json"

# 23a. Fresh start (just created) → allow
date -u +"%Y-%m-%dT%H:%M:%SZ" >"$WALLCLOCK_TEST_DIR/openspec/changes/test-change/context/phase-results/phase5-start-time.txt"
# Need Phase 5 zero_skip_check for Phase 6 gate
echo '{"status":"ok","zero_skip_check":{"passed":true},"test_results_path":"test.json","tasks_completed":3}' >"$WALLCLOCK_TEST_DIR/openspec/changes/test-change/context/phase-results/phase-5-implement.json"
# Need all tasks checked
echo "- [x] Task 1" >"$WALLCLOCK_TEST_DIR/openspec/changes/test-change/tasks.md"
exit_code=0
output=$(echo "{\"tool_name\":\"Task\",\"tool_input\":{\"prompt\":\"<!-- autopilot-phase:6 -->\\nPhase 6\",\"subagent_type\":\"general-purpose\"},\"cwd\":\"$WALLCLOCK_TEST_DIR\"}" |
  bash "$SCRIPT_DIR/check-predecessor-checkpoint.sh" 2>/dev/null) || exit_code=$?
assert_exit "wall-clock: fresh start → allow" 0 $exit_code
assert_not_contains "wall-clock: fresh start → no deny" "$output" "deny"

# 23b. Expired (3 hours ago) → deny
expired_time=$(python3 -c "
from datetime import datetime, timezone, timedelta
t = datetime.now(timezone.utc) - timedelta(hours=3)
print(t.strftime('%Y-%m-%dT%H:%M:%SZ'))
" 2>/dev/null)
echo "$expired_time" >"$WALLCLOCK_TEST_DIR/openspec/changes/test-change/context/phase-results/phase5-start-time.txt"
exit_code=0
output=$(echo "{\"tool_name\":\"Task\",\"tool_input\":{\"prompt\":\"<!-- autopilot-phase:6 -->\\nPhase 6\",\"subagent_type\":\"general-purpose\"},\"cwd\":\"$WALLCLOCK_TEST_DIR\"}" |
  bash "$SCRIPT_DIR/check-predecessor-checkpoint.sh" 2>/dev/null) || exit_code=$?
assert_exit "wall-clock: expired → exit 0" 0 $exit_code
assert_contains "wall-clock: expired → deny with timeout" "$output" "wall-clock timeout"

# 23c. No start file → allow (Phase 5 not started yet)
rm -f "$WALLCLOCK_TEST_DIR/openspec/changes/test-change/context/phase-results/phase5-start-time.txt"
exit_code=0
output=$(echo "{\"tool_name\":\"Task\",\"tool_input\":{\"prompt\":\"<!-- autopilot-phase:6 -->\\nPhase 6\",\"subagent_type\":\"general-purpose\"},\"cwd\":\"$WALLCLOCK_TEST_DIR\"}" |
  bash "$SCRIPT_DIR/check-predecessor-checkpoint.sh" 2>/dev/null) || exit_code=$?
assert_exit "wall-clock: no start file → allow" 0 $exit_code
assert_not_contains "wall-clock: no start file → no deny" "$output" "wall-clock"

rm -rf "$WALLCLOCK_TEST_DIR"

teardown_autopilot_fixture
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1
exit 0

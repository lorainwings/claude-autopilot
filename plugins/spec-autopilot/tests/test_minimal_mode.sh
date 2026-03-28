#!/usr/bin/env bash
# test_minimal_mode.sh — Section 37: Minimal mode Phase 7 without Phase 6 + auto-continue
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../runtime/scripts" && pwd)"
source "$TEST_DIR/_test_helpers.sh"
source "$TEST_DIR/_fixtures.sh"

echo "--- 37. v3.2.2 Minimal mode: Phase 7 without Phase 6 + auto-continue ---"
setup_autopilot_fixture

MIN_TEST_DIR=$(mktemp -d)
mkdir -p "$MIN_TEST_DIR/openspec/changes/test-min/context/phase-results"
echo '{"change":"test-min","mode":"minimal"}' > "$MIN_TEST_DIR/openspec/changes/.autopilot-active"

# 37a. Minimal mode: Phase 5 ok → Phase 7 allowed (skips Phase 6)
echo '{"status":"ok","summary":"Impl done","zero_skip_check":{"passed":true},"tasks_completed":"3/3","test_results_path":"test-results.json"}' \
  > "$MIN_TEST_DIR/openspec/changes/test-min/context/phase-results/phase-5-implement.json"
exit_code=0
output=$(echo "{\"tool_name\":\"Task\",\"tool_input\":{\"prompt\":\"<!-- autopilot-phase:7 -->\\nPhase 7\",\"subagent_type\":\"general-purpose\"},\"cwd\":\"$MIN_TEST_DIR\"}" \
  | bash "$SCRIPT_DIR/check-predecessor-checkpoint.sh" 2>/dev/null) || exit_code=$?
assert_exit "Minimal: Phase 5 ok → Phase 7 allow (exit 0)" 0 $exit_code
assert_not_contains "Minimal: Phase 7 no deny" "$output" "deny"

# 37b. Minimal mode: Phase 6 dispatch → should be denied
exit_code=0
output=$(echo "{\"tool_name\":\"Task\",\"tool_input\":{\"prompt\":\"<!-- autopilot-phase:6 -->\\nPhase 6\",\"subagent_type\":\"qa-expert\"},\"cwd\":\"$MIN_TEST_DIR\"}" \
  | bash "$SCRIPT_DIR/check-predecessor-checkpoint.sh" 2>/dev/null) || exit_code=$?
assert_exit "Minimal: Phase 6 dispatch → exit 0" 0 $exit_code
assert_contains "Minimal: Phase 6 dispatch → deny" "$output" "deny"

rm -rf "$MIN_TEST_DIR"

# --- 37c-37e. Minimal mode: auto-continue after Phase 1 ---
echo "  37c-37e. Minimal mode auto-continue after requirement packet"
MIN_AC_DIR=$(mktemp -d)
mkdir -p "$MIN_AC_DIR/openspec/changes/test-min-ac/context/phase-results"
echo '{"change":"test-min-ac","mode":"minimal"}' > "$MIN_AC_DIR/openspec/changes/.autopilot-active"
echo '{"status":"ok","summary":"Requirements confirmed"}' \
  > "$MIN_AC_DIR/openspec/changes/test-min-ac/context/phase-results/phase-1-requirements.json"

# 37c. Minimal mode: Phase 1 ok → Phase 5 可直接推进
exit_code=0
output=$(echo "{\"tool_name\":\"Task\",\"tool_input\":{\"prompt\":\"<!-- autopilot-phase:5 -->\\nPhase 5\"},\"cwd\":\"$MIN_AC_DIR\"}" \
  | bash "$SCRIPT_DIR/check-predecessor-checkpoint.sh" 2>/dev/null) || exit_code=$?
assert_exit "37c: Minimal auto-continue: Phase 1 ok → Phase 5 (exit 0)" 0 $exit_code
assert_not_contains "37d: Minimal auto-continue: no deny for Phase 5" "$output" "deny"

# 37e. Minimal mode: 不能跳到 Phase 3（minimal 跳过 Phase 3）
exit_code=0
output=$(echo "{\"tool_name\":\"Task\",\"tool_input\":{\"prompt\":\"<!-- autopilot-phase:3 -->\\nPhase 3\"},\"cwd\":\"$MIN_AC_DIR\"}" \
  | bash "$SCRIPT_DIR/check-predecessor-checkpoint.sh" 2>/dev/null) || exit_code=$?
assert_exit "37e: Minimal: Phase 3 dispatch → exit 0" 0 $exit_code
assert_contains "37e: Minimal: Phase 3 dispatch → deny (skipped)" "$output" "deny"

rm -rf "$MIN_AC_DIR"

teardown_autopilot_fixture
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1; exit 0

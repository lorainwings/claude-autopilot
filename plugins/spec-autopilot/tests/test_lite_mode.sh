#!/usr/bin/env bash
# test_lite_mode.sh — Section 38: Lite mode tri-path parallel compatibility + auto-continue
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../runtime/scripts" && pwd)"
source "$TEST_DIR/_test_helpers.sh"
source "$TEST_DIR/_fixtures.sh"

echo "--- 38. v3.2.2 Lite mode: Phase 6 tri-path parallel compatibility + auto-continue ---"
setup_autopilot_fixture

LITE_TEST_DIR=$(mktemp -d)
mkdir -p "$LITE_TEST_DIR/openspec/changes/test-lite/context/phase-results"
echo '{"change":"test-lite","mode":"lite"}' > "$LITE_TEST_DIR/openspec/changes/.autopilot-active"
echo '{"status":"ok","summary":"Impl done","zero_skip_check":{"passed":true},"tasks_completed":"3/3","test_results_path":"test-results.json"}' \
  > "$LITE_TEST_DIR/openspec/changes/test-lite/context/phase-results/phase-5-implement.json"
# Task file required by fail-closed Phase 6 gate
echo "- [x] task 1" > "$LITE_TEST_DIR/openspec/changes/test-lite/context/phase5-task-breakdown.md"

# 38a. Lite mode: Phase 5 → Phase 6 allowed
exit_code=0
output=$(echo "{\"tool_name\":\"Task\",\"tool_input\":{\"prompt\":\"<!-- autopilot-phase:6 -->\\nPhase 6\",\"subagent_type\":\"general-purpose\"},\"cwd\":\"$LITE_TEST_DIR\"}" \
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

# --- 38c-38e. Lite mode: auto-continue after Phase 1 ---
echo "  38c-38e. Lite mode auto-continue after requirement packet"
LITE_AC_DIR=$(mktemp -d)
mkdir -p "$LITE_AC_DIR/openspec/changes/test-lite-ac/context/phase-results"
echo '{"change":"test-lite-ac","mode":"lite"}' > "$LITE_AC_DIR/openspec/changes/.autopilot-active"
echo '{"status":"ok","summary":"Requirements confirmed"}' \
  > "$LITE_AC_DIR/openspec/changes/test-lite-ac/context/phase-results/phase-1-requirements.json"

# 38c. Lite mode: Phase 1 ok → Phase 5 可直接推进（跳过 2/3/4）
exit_code=0
output=$(echo "{\"tool_name\":\"Task\",\"tool_input\":{\"prompt\":\"<!-- autopilot-phase:5 -->\\nPhase 5\"},\"cwd\":\"$LITE_AC_DIR\"}" \
  | bash "$SCRIPT_DIR/check-predecessor-checkpoint.sh" 2>/dev/null) || exit_code=$?
assert_exit "38c: Lite auto-continue: Phase 1 ok → Phase 5 (exit 0)" 0 $exit_code
assert_not_contains "38d: Lite auto-continue: no deny for Phase 5" "$output" "deny"

# 38e. Lite mode: 不能跳到 Phase 2（lite 跳过 Phase 2）
exit_code=0
output=$(echo "{\"tool_name\":\"Task\",\"tool_input\":{\"prompt\":\"<!-- autopilot-phase:2 -->\\nPhase 2\"},\"cwd\":\"$LITE_AC_DIR\"}" \
  | bash "$SCRIPT_DIR/check-predecessor-checkpoint.sh" 2>/dev/null) || exit_code=$?
assert_exit "38e: Lite: Phase 2 dispatch → exit 0" 0 $exit_code
assert_contains "38e: Lite: Phase 2 dispatch → deny (skipped)" "$output" "deny"

rm -rf "$LITE_AC_DIR"

teardown_autopilot_fixture
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1; exit 0

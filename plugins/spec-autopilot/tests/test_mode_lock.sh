#!/usr/bin/env bash
# test_mode_lock.sh — Section 47: Mode lock file + predecessor checkpoint gate
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../runtime/scripts" && pwd)"
source "$TEST_DIR/_test_helpers.sh"
source "$TEST_DIR/_fixtures.sh"

echo "--- 47. Mode lock file + predecessor checkpoint gate ---"
setup_autopilot_fixture

# 47a. mode="full" + Phase 6 dispatch with Phase 5 checkpoint → allow
TMPDIR_47a=$(mktemp -d)
mkdir -p "$TMPDIR_47a/openspec/changes/test-47a/context/phase-results"
echo '{"change":"test-47a","mode":"full"}' > "$TMPDIR_47a/openspec/changes/.autopilot-active"
echo '{"status":"ok","summary":"Impl done","zero_skip_check":{"passed":true},"tasks_completed":"5/5","test_results_path":"r.json"}' \
  > "$TMPDIR_47a/openspec/changes/test-47a/context/phase-results/phase-5-implement.json"
# Task file required by fail-closed Phase 6 gate
echo "- [x] task 1" > "$TMPDIR_47a/openspec/changes/test-47a/tasks.md"
exit_code=0
OUT47a=$(echo "{\"tool_name\":\"Task\",\"tool_input\":{\"prompt\":\"<!-- autopilot-phase:6 -->\\nPhase 6\",\"subagent_type\":\"general-purpose\"},\"cwd\":\"$TMPDIR_47a\"}" \
  | bash "$SCRIPT_DIR/check-predecessor-checkpoint.sh" 2>/dev/null) || exit_code=$?
assert_exit "47a: full Phase 6 with Phase 5 ok → exit 0" 0 $exit_code
assert_not_contains "47a: full Phase 6 → no deny" "$OUT47a" "deny"
rm -rf "$TMPDIR_47a"

# 47b. mode="lite" + Phase 6 dispatch with Phase 5 checkpoint → allow
TMPDIR_47b=$(mktemp -d)
mkdir -p "$TMPDIR_47b/openspec/changes/test-47b/context/phase-results"
echo '{"change":"test-47b","mode":"lite"}' > "$TMPDIR_47b/openspec/changes/.autopilot-active"
echo '{"status":"ok","summary":"Impl done","zero_skip_check":{"passed":true},"tasks_completed":"5/5","test_results_path":"r.json"}' \
  > "$TMPDIR_47b/openspec/changes/test-47b/context/phase-results/phase-5-implement.json"
# Task file required by fail-closed Phase 6 gate
mkdir -p "$TMPDIR_47b/openspec/changes/test-47b/context"
echo "- [x] task 1" > "$TMPDIR_47b/openspec/changes/test-47b/context/phase5-task-breakdown.md"
exit_code=0
OUT47b=$(echo "{\"tool_name\":\"Task\",\"tool_input\":{\"prompt\":\"<!-- autopilot-phase:6 -->\\nPhase 6\",\"subagent_type\":\"general-purpose\"},\"cwd\":\"$TMPDIR_47b\"}" \
  | bash "$SCRIPT_DIR/check-predecessor-checkpoint.sh" 2>/dev/null) || exit_code=$?
assert_exit "47b: lite Phase 6 with Phase 5 ok → exit 0" 0 $exit_code
assert_not_contains "47b: lite Phase 6 → no deny" "$OUT47b" "deny"
rm -rf "$TMPDIR_47b"

# 47c. mode="minimal" + Phase 6 dispatch → deny (minimal skips Phase 6)
TMPDIR_47c=$(mktemp -d)
mkdir -p "$TMPDIR_47c/openspec/changes/test-47c/context/phase-results"
echo '{"change":"test-47c","mode":"minimal"}' > "$TMPDIR_47c/openspec/changes/.autopilot-active"
echo '{"status":"ok","summary":"Impl done","zero_skip_check":{"passed":true},"tasks_completed":"3/3","test_results_path":"r.json"}' \
  > "$TMPDIR_47c/openspec/changes/test-47c/context/phase-results/phase-5-implement.json"
exit_code=0
OUT47c=$(echo "{\"tool_name\":\"Task\",\"tool_input\":{\"prompt\":\"<!-- autopilot-phase:6 -->\\nPhase 6\",\"subagent_type\":\"general-purpose\"},\"cwd\":\"$TMPDIR_47c\"}" \
  | bash "$SCRIPT_DIR/check-predecessor-checkpoint.sh" 2>/dev/null) || exit_code=$?
assert_exit "47c: minimal Phase 6 → exit 0" 0 $exit_code
assert_contains "47c: minimal Phase 6 → deny" "$OUT47c" "deny"
rm -rf "$TMPDIR_47c"

# 47d. mode="full" + Phase 2 dispatch with Phase 1 checkpoint → allow
TMPDIR_47d=$(mktemp -d)
mkdir -p "$TMPDIR_47d/openspec/changes/test-47d/context/phase-results"
echo '{"change":"test-47d","mode":"full"}' > "$TMPDIR_47d/openspec/changes/.autopilot-active"
echo '{"status":"ok","summary":"Requirements analyzed"}' \
  > "$TMPDIR_47d/openspec/changes/test-47d/context/phase-results/phase-1-requirements.json"
exit_code=0
OUT47d=$(echo "{\"tool_name\":\"Task\",\"tool_input\":{\"prompt\":\"<!-- autopilot-phase:2 -->\\nPhase 2\",\"subagent_type\":\"general-purpose\"},\"cwd\":\"$TMPDIR_47d\"}" \
  | bash "$SCRIPT_DIR/check-predecessor-checkpoint.sh" 2>/dev/null) || exit_code=$?
assert_exit "47d: full Phase 2 with Phase 1 ok → exit 0" 0 $exit_code
assert_not_contains "47d: full Phase 2 → no deny" "$OUT47d" "deny"
rm -rf "$TMPDIR_47d"

# 47e. mode="lite" + Phase 2 dispatch → deny (lite skips Phase 2)
TMPDIR_47e=$(mktemp -d)
mkdir -p "$TMPDIR_47e/openspec/changes/test-47e/context/phase-results"
echo '{"change":"test-47e","mode":"lite"}' > "$TMPDIR_47e/openspec/changes/.autopilot-active"
echo '{"status":"ok","summary":"Requirements analyzed"}' \
  > "$TMPDIR_47e/openspec/changes/test-47e/context/phase-results/phase-1-requirements.json"
exit_code=0
OUT47e=$(echo "{\"tool_name\":\"Task\",\"tool_input\":{\"prompt\":\"<!-- autopilot-phase:2 -->\\nPhase 2\",\"subagent_type\":\"general-purpose\"},\"cwd\":\"$TMPDIR_47e\"}" \
  | bash "$SCRIPT_DIR/check-predecessor-checkpoint.sh" 2>/dev/null) || exit_code=$?
assert_exit "47e: lite Phase 2 → exit 0" 0 $exit_code
assert_contains "47e: lite Phase 2 → deny" "$OUT47e" "deny"
rm -rf "$TMPDIR_47e"

# 47f. mode="minimal" + Phase 7 dispatch with Phase 5 checkpoint → allow
TMPDIR_47f=$(mktemp -d)
mkdir -p "$TMPDIR_47f/openspec/changes/test-47f/context/phase-results"
echo '{"change":"test-47f","mode":"minimal"}' > "$TMPDIR_47f/openspec/changes/.autopilot-active"
echo '{"status":"ok","summary":"Impl done","zero_skip_check":{"passed":true},"tasks_completed":"3/3","test_results_path":"r.json"}' \
  > "$TMPDIR_47f/openspec/changes/test-47f/context/phase-results/phase-5-implement.json"
exit_code=0
OUT47f=$(echo "{\"tool_name\":\"Task\",\"tool_input\":{\"prompt\":\"<!-- autopilot-phase:7 -->\\nPhase 7\",\"subagent_type\":\"general-purpose\"},\"cwd\":\"$TMPDIR_47f\"}" \
  | bash "$SCRIPT_DIR/check-predecessor-checkpoint.sh" 2>/dev/null) || exit_code=$?
assert_exit "47f: minimal Phase 7 with Phase 5 ok → exit 0" 0 $exit_code
assert_not_contains "47f: minimal Phase 7 → no deny" "$OUT47f" "deny"
rm -rf "$TMPDIR_47f"

teardown_autopilot_fixture
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1; exit 0

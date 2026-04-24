#!/usr/bin/env bash
# test_allure_preview_fallback.sh — Phase 7 Step 2.5 Allure preview multi-path fallback
# TEST_LAYER: behavior
# Production targets:
#   - emit-report-ready-event.sh (multi-path allure discovery)
#   - autopilot-phase7-archive/SKILL.md Step 2.5.0 (allure generate fallback)
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../runtime/scripts" && pwd)"
source "$TEST_DIR/_test_helpers.sh"
source "$TEST_DIR/_fixtures.sh"

echo "--- Allure preview multi-path fallback ---"
setup_autopilot_fixture

TMPDIR_TEST=$(mktemp -d)
trap 'rm -rf "$TMPDIR_TEST"' EXIT

EMIT_SCRIPT="$SCRIPT_DIR/emit-report-ready-event.sh"

# ── emit-report-ready-event.sh multi-path discovery tests ──

# Helper: create minimal change structure for emit-report-ready-event.sh
setup_change_dir() {
  local base="$1"
  local change_name="$2"
  mkdir -p "$base/openspec/changes/$change_name/context/phase-results"
  mkdir -p "$base/openspec/changes/$change_name/reports"
  mkdir -p "$base/openspec/changes/$change_name/logs"
  mkdir -p "$base/logs"
}

# 1a. allure-results/ at project root → discovered
setup_change_dir "$TMPDIR_TEST/proj1" "test-feat"
mkdir -p "$TMPDIR_TEST/proj1/allure-results"
echo '{}' >"$TMPDIR_TEST/proj1/allure-results/result1.json"
# Write Phase 6 checkpoint without allure_results_dir (simulating gap)
echo '{"report_format":"allure","report_path":"allure-report/index.html","pass_rate":95,"suite_results":[]}' \
  >"$TMPDIR_TEST/proj1/openspec/changes/test-feat/context/phase-results/phase-6-report.json"

exit_code=0
output=$(cd "$TMPDIR_TEST/proj1" && bash "$EMIT_SCRIPT" "openspec/changes" "test-feat" "full" "sess-1" 2>/dev/null) || exit_code=$?
assert_exit "1a. project root allure-results → exit 0" 0 $exit_code
# Check events.jsonl was written with allure_results_dir
if [ -f "$TMPDIR_TEST/proj1/logs/events.jsonl" ]; then
  event_payload=$(tail -1 "$TMPDIR_TEST/proj1/logs/events.jsonl")
  assert_contains "1a. event has allure_results_dir" "$event_payload" "allure-results"
  assert_contains "1a. report_format is allure" "$event_payload" '"report_format":"allure"'
else
  red "  FAIL: 1a. events.jsonl not created"
  FAIL=$((FAIL + 1))
fi

# 1b. allure-results/ at change level reports/ → discovered
setup_change_dir "$TMPDIR_TEST/proj2" "test-feat"
mkdir -p "$TMPDIR_TEST/proj2/openspec/changes/test-feat/reports/allure-results"
echo '{}' >"$TMPDIR_TEST/proj2/openspec/changes/test-feat/reports/allure-results/result1.json"
echo '{"report_format":"custom","report_path":"test-report.html","pass_rate":90,"suite_results":[]}' \
  >"$TMPDIR_TEST/proj2/openspec/changes/test-feat/context/phase-results/phase-6-report.json"

exit_code=0
output=$(cd "$TMPDIR_TEST/proj2" && bash "$EMIT_SCRIPT" "openspec/changes" "test-feat" "full" "sess-2" 2>/dev/null) || exit_code=$?
assert_exit "1b. change-level allure-results → exit 0" 0 $exit_code
if [ -f "$TMPDIR_TEST/proj2/logs/events.jsonl" ]; then
  event_payload=$(tail -1 "$TMPDIR_TEST/proj2/logs/events.jsonl")
  assert_contains "1b. event has allure_results_dir" "$event_payload" "allure-results"
  assert_contains "1b. format overridden to allure" "$event_payload" '"report_format":"allure"'
else
  red "  FAIL: 1b. events.jsonl not created"
  FAIL=$((FAIL + 1))
fi

# 1c. allure_results_dir in checkpoint → highest priority
setup_change_dir "$TMPDIR_TEST/proj3" "test-feat"
mkdir -p "$TMPDIR_TEST/proj3/custom-allure-output"
echo '{}' >"$TMPDIR_TEST/proj3/custom-allure-output/result1.json"
echo '{"report_format":"allure","report_path":"allure-report/index.html","pass_rate":100,"suite_results":[],"allure_results_dir":"'"$TMPDIR_TEST/proj3/custom-allure-output"'"}' \
  >"$TMPDIR_TEST/proj3/openspec/changes/test-feat/context/phase-results/phase-6-report.json"

exit_code=0
output=$(cd "$TMPDIR_TEST/proj3" && bash "$EMIT_SCRIPT" "openspec/changes" "test-feat" "full" "sess-3" 2>/dev/null) || exit_code=$?
assert_exit "1c. checkpoint allure_results_dir → exit 0" 0 $exit_code
if [ -f "$TMPDIR_TEST/proj3/logs/events.jsonl" ]; then
  event_payload=$(tail -1 "$TMPDIR_TEST/proj3/logs/events.jsonl")
  assert_contains "1c. event has custom allure path" "$event_payload" "custom-allure-output"
else
  red "  FAIL: 1c. events.jsonl not created"
  FAIL=$((FAIL + 1))
fi

# 1d. no allure-results anywhere → format stays as checkpoint value
setup_change_dir "$TMPDIR_TEST/proj4" "test-feat"
echo '{"report_format":"custom","report_path":"test-report.html","pass_rate":85,"suite_results":[]}' \
  >"$TMPDIR_TEST/proj4/openspec/changes/test-feat/context/phase-results/phase-6-report.json"

exit_code=0
output=$(cd "$TMPDIR_TEST/proj4" && bash "$EMIT_SCRIPT" "openspec/changes" "test-feat" "full" "sess-4" 2>/dev/null) || exit_code=$?
assert_exit "1d. no allure anywhere → exit 0" 0 $exit_code
if [ -f "$TMPDIR_TEST/proj4/logs/events.jsonl" ]; then
  event_payload=$(tail -1 "$TMPDIR_TEST/proj4/logs/events.jsonl")
  assert_contains "1d. format is custom" "$event_payload" '"report_format":"custom"'
else
  red "  FAIL: 1d. events.jsonl not created"
  FAIL=$((FAIL + 1))
fi

# 1e. allure-preview.json exists → allure_preview_url propagated
setup_change_dir "$TMPDIR_TEST/proj5" "test-feat"
echo '{"report_format":"allure","report_path":"allure-report/index.html","pass_rate":98,"suite_results":[]}' \
  >"$TMPDIR_TEST/proj5/openspec/changes/test-feat/context/phase-results/phase-6-report.json"
echo '{"url":"http://localhost:4040","pid":12345,"port":4040}' \
  >"$TMPDIR_TEST/proj5/openspec/changes/test-feat/context/allure-preview.json"
mkdir -p "$TMPDIR_TEST/proj5/allure-results"
echo '{}' >"$TMPDIR_TEST/proj5/allure-results/result1.json"

exit_code=0
output=$(cd "$TMPDIR_TEST/proj5" && bash "$EMIT_SCRIPT" "openspec/changes" "test-feat" "full" "sess-5" 2>/dev/null) || exit_code=$?
assert_exit "1e. allure-preview.json → exit 0" 0 $exit_code
if [ -f "$TMPDIR_TEST/proj5/logs/events.jsonl" ]; then
  event_payload=$(tail -1 "$TMPDIR_TEST/proj5/logs/events.jsonl")
  assert_contains "1e. preview URL propagated" "$event_payload" "http://localhost:4040"
else
  red "  FAIL: 1e. events.jsonl not created"
  FAIL=$((FAIL + 1))
fi

# 1f. minimal mode → format forced to none
setup_change_dir "$TMPDIR_TEST/proj6" "test-feat"
echo '{"report_format":"allure","report_path":"allure-report/index.html","pass_rate":100,"suite_results":[]}' \
  >"$TMPDIR_TEST/proj6/openspec/changes/test-feat/context/phase-results/phase-6-report.json"

exit_code=0
output=$(cd "$TMPDIR_TEST/proj6" && bash "$EMIT_SCRIPT" "openspec/changes" "test-feat" "minimal" "sess-6" 2>/dev/null) || exit_code=$?
assert_exit "1f. minimal mode → exit 0" 0 $exit_code
if [ -f "$TMPDIR_TEST/proj6/logs/events.jsonl" ]; then
  event_payload=$(tail -1 "$TMPDIR_TEST/proj6/logs/events.jsonl")
  assert_contains "1f. format forced to none" "$event_payload" '"report_format":"none"'
else
  red "  FAIL: 1f. events.jsonl not created"
  FAIL=$((FAIL + 1))
fi

# 1g. NEGATIVE: stale checkpoint allure_results_dir + real change-level allure-results → fallback wins
# Regression test: checkpoint writes a non-existent path, but real allure-results exist at change level.
# Before fix: script trusts stale path, outputs allure_results_dir=stale-dir, format stays custom.
# After fix: stale path fails -d check, fallback discovers reports/allure-results/.
setup_change_dir "$TMPDIR_TEST/proj7" "test-feat"
mkdir -p "$TMPDIR_TEST/proj7/openspec/changes/test-feat/reports/allure-results"
echo '{}' >"$TMPDIR_TEST/proj7/openspec/changes/test-feat/reports/allure-results/result1.json"
# Checkpoint points to non-existent stale directory
echo '{"report_format":"custom","report_path":"test-report.html","pass_rate":90,"suite_results":[],"allure_results_dir":"/tmp/stale-nonexistent-dir-12345"}' \
  >"$TMPDIR_TEST/proj7/openspec/changes/test-feat/context/phase-results/phase-6-report.json"

exit_code=0
output=$(cd "$TMPDIR_TEST/proj7" && bash "$EMIT_SCRIPT" "openspec/changes" "test-feat" "full" "sess-7" 2>/dev/null) || exit_code=$?
assert_exit "1g. stale checkpoint + real change-level → exit 0" 0 $exit_code
if [ -f "$TMPDIR_TEST/proj7/logs/events.jsonl" ]; then
  event_payload=$(tail -1 "$TMPDIR_TEST/proj7/logs/events.jsonl")
  # Must NOT contain the stale path
  assert_not_contains "1g. stale path not used" "$event_payload" "stale-nonexistent-dir"
  # Must discover the real change-level allure-results
  assert_contains "1g. fallback found allure-results" "$event_payload" "allure-results"
  # Format must be overridden to allure (not stay as custom)
  assert_contains "1g. format overridden to allure" "$event_payload" '"report_format":"allure"'
else
  red "  FAIL: 1g. events.jsonl not created"
  FAIL=$((FAIL + 1))
fi

# 1h. NEGATIVE: stale checkpoint allure_results_dir + real project-root allure-results → fallback wins
setup_change_dir "$TMPDIR_TEST/proj8" "test-feat"
mkdir -p "$TMPDIR_TEST/proj8/allure-results"
echo '{}' >"$TMPDIR_TEST/proj8/allure-results/result1.json"
echo '{"report_format":"custom","report_path":"test-report.html","pass_rate":85,"suite_results":[],"allure_results_dir":"nonexistent-allure-dir"}' \
  >"$TMPDIR_TEST/proj8/openspec/changes/test-feat/context/phase-results/phase-6-report.json"

exit_code=0
output=$(cd "$TMPDIR_TEST/proj8" && bash "$EMIT_SCRIPT" "openspec/changes" "test-feat" "full" "sess-8" 2>/dev/null) || exit_code=$?
assert_exit "1h. stale checkpoint + real project-root → exit 0" 0 $exit_code
if [ -f "$TMPDIR_TEST/proj8/logs/events.jsonl" ]; then
  event_payload=$(tail -1 "$TMPDIR_TEST/proj8/logs/events.jsonl")
  assert_not_contains "1h. stale path not used" "$event_payload" "nonexistent-allure-dir"
  assert_contains "1h. fallback found allure-results" "$event_payload" "allure-results"
  assert_contains "1h. format overridden to allure" "$event_payload" '"report_format":"allure"'
else
  red "  FAIL: 1h. events.jsonl not created"
  FAIL=$((FAIL + 1))
fi

teardown_autopilot_fixture
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1
exit 0

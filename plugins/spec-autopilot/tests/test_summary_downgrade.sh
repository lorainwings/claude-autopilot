#!/usr/bin/env bash
# test_summary_downgrade.sh — Section 46: v3.3.1 summary field downgrade
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../scripts" && pwd)"
source "$TEST_DIR/_test_helpers.sh"
source "$TEST_DIR/_fixtures.sh"

echo "--- 46. v3.3.1 summary field downgrade (required → recommended) ---"
setup_autopilot_fixture

TMPDIR_46=$(mktemp -d)
mkdir -p "$TMPDIR_46/openspec/changes/test-v331/context/phase-results"
echo '{"change":"test-v331","mode":"full"}' > "$TMPDIR_46/openspec/changes/.autopilot-active"

# 46a. Phase 5 envelope has status but NO summary → no block (new v3.3.1 behavior)
OUT46a=$(echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:5 -->\nPhase 5"},"tool_response":"Done. {\"status\":\"ok\",\"test_results_path\":\"tests/results.json\",\"tasks_completed\":\"5/5\",\"zero_skip_check\":{\"passed\":true}}","cwd":"'"$TMPDIR_46"'"}' \
  | bash "$SCRIPT_DIR/validate-json-envelope.sh" 2>/dev/null)
RC46a=$?
assert_exit "46a: Phase 5 status no summary → exit 0" 0 "$RC46a"
assert_not_contains "46a: Phase 5 status no summary → no block" "$OUT46a" "block"

# 46b. Phase 3 envelope has status + summary → no block (regression)
OUT46b=$(echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:3 -->\nPhase 3"},"tool_response":"Done.\n{\"status\":\"ok\",\"summary\":\"Design complete\",\"artifacts\":[]}","cwd":"'"$TMPDIR_46"'"}' \
  | bash "$SCRIPT_DIR/validate-json-envelope.sh" 2>/dev/null)
RC46b=$?
assert_exit "46b: Phase 3 status+summary → exit 0" 0 "$RC46b"
assert_not_contains "46b: Phase 3 status+summary → no block" "$OUT46b" "block"

# 46c. Phase 5 envelope has NO status → block
OUT46c=$(echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:5 -->\nPhase 5"},"tool_response":"Done. {\"summary\":\"All tasks done\",\"test_results_path\":\"tests/r.json\",\"tasks_completed\":\"5/5\",\"zero_skip_check\":{\"passed\":true}}","cwd":"'"$TMPDIR_46"'"}' \
  | bash "$SCRIPT_DIR/validate-json-envelope.sh" 2>/dev/null)
RC46c=$?
assert_exit "46c: Phase 5 no status → exit 0" 0 "$RC46c"
assert_contains "46c: Phase 5 no status → block" "$OUT46c" "block"

# 46d. Phase 5 envelope has invalid status value → block
OUT46d=$(echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:5 -->\nPhase 5"},"tool_response":"Done. {\"status\":\"done\",\"summary\":\"All tasks done\",\"test_results_path\":\"tests/r.json\",\"tasks_completed\":\"5/5\",\"zero_skip_check\":{\"passed\":true}}","cwd":"'"$TMPDIR_46"'"}' \
  | bash "$SCRIPT_DIR/validate-json-envelope.sh" 2>/dev/null)
RC46d=$?
assert_exit "46d: Phase 5 invalid status → exit 0" 0 "$RC46d"
assert_contains "46d: Phase 5 invalid status → block" "$OUT46d" "block"

# 46e. Phase 5 minimal envelope: only status:"ok" + required phase fields → no block
OUT46e=$(echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:5 -->\nPhase 5"},"tool_response":"{\"status\":\"ok\",\"test_results_path\":\"tests/results.json\",\"tasks_completed\":\"3/3\",\"zero_skip_check\":{\"passed\":true}}","cwd":"'"$TMPDIR_46"'"}' \
  | bash "$SCRIPT_DIR/validate-json-envelope.sh" 2>/dev/null)
RC46e=$?
assert_exit "46e: Phase 5 minimal envelope → exit 0" 0 "$RC46e"
assert_not_contains "46e: Phase 5 minimal envelope → no block" "$OUT46e" "block"

rm -rf "$TMPDIR_46"

teardown_autopilot_fixture
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1; exit 0

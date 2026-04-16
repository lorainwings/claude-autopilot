#!/usr/bin/env bash
# test_sub_step_events.sh — Tests for sub_step event system, gate_step, and sequence bug fixes
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../runtime/scripts" && pwd)"
source "$TEST_DIR/_test_helpers.sh"
source "$TEST_DIR/_fixtures.sh"

echo "=== sub_step event system tests ==="

# --- Setup ---
setup_autopilot_fixture
TMP_DIR=$(mktemp -d)
trap 'teardown_autopilot_fixture; rm -rf "$TMP_DIR"' EXIT

# Ensure logs dir and sequence file exist for the repo root
mkdir -p "$REPO_ROOT/logs"
# Save and reset sequence counter for deterministic tests
SEQ_BACKUP=""
if [ -f "$REPO_ROOT/logs/.event_sequence" ]; then
  SEQ_BACKUP=$(cat "$REPO_ROOT/logs/.event_sequence")
fi
echo "100" > "$REPO_ROOT/logs/.event_sequence"

# Clean events.jsonl for test isolation
EVENTS_FILE="$REPO_ROOT/logs/events.jsonl"
: > "$EVENTS_FILE"

echo "--- 1. sub_step event normal write ---"
OUTPUT=$(bash "$SCRIPT_DIR/emit-sub-step-event.sh" 0 "env-check" "Environment Check" '{"step_index":0,"total_steps":5}' 2>&1)
EXIT_CODE=$?
assert_exit "1. sub_step normal write exits 0" 0 "$EXIT_CODE"
# Verify event written to events.jsonl
LAST_LINE=$(tail -1 "$EVENTS_FILE")
assert_json_field "1a. type is sub_step" "$LAST_LINE" "type" "sub_step"
assert_contains "1b. step_id in payload" "$LAST_LINE" "env-check"
assert_contains "1c. step_label in payload" "$LAST_LINE" "Environment Check"

echo "--- 2. sub_step missing args → exit 1 ---"
OUTPUT=$(bash "$SCRIPT_DIR/emit-sub-step-event.sh" 2>&1)
EXIT_CODE=$?
assert_exit "2. sub_step no args exits 1" 1 "$EXIT_CODE"

OUTPUT=$(bash "$SCRIPT_DIR/emit-sub-step-event.sh" 0 2>&1)
EXIT_CODE=$?
assert_exit "2a. sub_step missing step_label exits 1" 1 "$EXIT_CODE"

echo "--- 3. sub_step no active autopilot → silent exit ---"
# Force-remove lockfile to simulate no active autopilot
SAVED_LOCK=""
if [ -f "$REPO_ROOT/openspec/changes/.autopilot-active" ]; then
  SAVED_LOCK=$(cat "$REPO_ROOT/openspec/changes/.autopilot-active")
  rm -f "$REPO_ROOT/openspec/changes/.autopilot-active"
fi
unset AUTOPILOT_PROJECT_ROOT
: > "$EVENTS_FILE"
rm -rf "$REPO_ROOT/logs/.event_sequence.lk" 2>/dev/null || true
OUTPUT=$(bash "$SCRIPT_DIR/emit-sub-step-event.sh" 0 "test-step" "Test Step" 2>&1)
EXIT_CODE=$?
assert_exit "3. no active autopilot exits 0" 0 "$EXIT_CODE"
# Restore lockfile
if [ -n "$SAVED_LOCK" ]; then
  mkdir -p "$REPO_ROOT/openspec/changes"
  echo "$SAVED_LOCK" > "$REPO_ROOT/openspec/changes/.autopilot-active"
fi
# File should be empty (0 bytes) — no event written
FILE_SIZE=$(wc -c < "$EVENTS_FILE" | tr -d ' ')
if [ "$FILE_SIZE" = "0" ]; then
  green "  PASS: 3a. no event written without active autopilot"
  PASS=$((PASS + 1))
else
  red "  FAIL: 3a. event written without active autopilot (size=$FILE_SIZE)"
  FAIL=$((FAIL + 1))
fi
# Fixture remains active for remaining tests

echo "--- 4. gate_step event write ---"
: > "$EVENTS_FILE"
export AUTOPILOT_MODE=full
OUTPUT=$(bash "$SCRIPT_DIR/emit-gate-event.sh" gate_step 3 1 "predecessor_check" "pass" "all clear" 2>&1)
EXIT_CODE=$?
assert_exit "4. gate_step exits 0" 0 "$EXIT_CODE"
LAST_LINE=$(tail -1 "$EVENTS_FILE")
assert_json_field "4a. type is gate_step" "$LAST_LINE" "type" "gate_step"
assert_contains "4b. step_name in payload" "$LAST_LINE" "predecessor_check"
assert_contains "4c. step_result in payload" "$LAST_LINE" "pass"
unset AUTOPILOT_MODE

echo "--- 5. tdd-audit-event.sh sequence != 0 ---"
# Setup change directory structure for tdd-audit
CHANGES_DIR="$TMP_DIR/openspec/changes"
CHANGE_NAME="test-tdd-fix"
mkdir -p "$CHANGES_DIR/$CHANGE_NAME/logs"
mkdir -p "$CHANGES_DIR/$CHANGE_NAME/context"

# Reset sequence
echo "200" > "$REPO_ROOT/logs/.event_sequence"
export PROJECT_ROOT_QUICK="$REPO_ROOT"

OUTPUT=$(bash "$SCRIPT_DIR/emit-tdd-audit-event.sh" "$CHANGES_DIR" "$CHANGE_NAME" "full" "sess-001" 2>&1)
EXIT_CODE=$?
assert_exit "5. tdd-audit exits 0" 0 "$EXIT_CODE"

TDD_EVENT=$(tail -1 "$CHANGES_DIR/$CHANGE_NAME/logs/events.jsonl")
SEQ_VAL=$(echo "$TDD_EVENT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('sequence',0))" 2>/dev/null || echo "0")
if [ "$SEQ_VAL" != "0" ]; then
  green "  PASS: 5a. tdd_audit sequence=$SEQ_VAL (not 0)"
  PASS=$((PASS + 1))
else
  red "  FAIL: 5a. tdd_audit sequence is still 0"
  FAIL=$((FAIL + 1))
fi

TOTAL_VAL=$(echo "$TDD_EVENT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('total_phases',0))" 2>/dev/null || echo "0")
if [ "$TOTAL_VAL" = "8" ]; then
  green "  PASS: 5b. tdd_audit total_phases=8 (dynamic, full mode)"
  PASS=$((PASS + 1))
else
  red "  FAIL: 5b. tdd_audit total_phases=$TOTAL_VAL (expected 8)"
  FAIL=$((FAIL + 1))
fi

echo "--- 6. report-ready-event.sh sequence != 0 ---"
REPORT_CHANGES_DIR="$TMP_DIR/openspec2/changes"
REPORT_CHANGE="test-report-fix"
mkdir -p "$REPORT_CHANGES_DIR/$REPORT_CHANGE/logs"
mkdir -p "$REPORT_CHANGES_DIR/$REPORT_CHANGE/context"

echo "300" > "$REPO_ROOT/logs/.event_sequence"

OUTPUT=$(bash "$SCRIPT_DIR/emit-report-ready-event.sh" "$REPORT_CHANGES_DIR" "$REPORT_CHANGE" "lite" "sess-002" 2>&1)
EXIT_CODE=$?
assert_exit "6. report-ready exits 0" 0 "$EXIT_CODE"

REPORT_EVENT=$(tail -1 "$REPORT_CHANGES_DIR/$REPORT_CHANGE/logs/events.jsonl")
SEQ_VAL=$(echo "$REPORT_EVENT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('sequence',0))" 2>/dev/null || echo "0")
if [ "$SEQ_VAL" != "0" ]; then
  green "  PASS: 6a. report_ready sequence=$SEQ_VAL (not 0)"
  PASS=$((PASS + 1))
else
  red "  FAIL: 6a. report_ready sequence is still 0"
  FAIL=$((FAIL + 1))
fi

TOTAL_VAL=$(echo "$REPORT_EVENT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('total_phases',0))" 2>/dev/null || echo "0")
if [ "$TOTAL_VAL" = "5" ]; then
  green "  PASS: 6b. report_ready total_phases=5 (dynamic, lite mode)"
  PASS=$((PASS + 1))
else
  red "  FAIL: 6b. report_ready total_phases=$TOTAL_VAL (expected 5)"
  FAIL=$((FAIL + 1))
fi

unset PROJECT_ROOT_QUICK

# Restore sequence counter
if [ -n "$SEQ_BACKUP" ]; then
  echo "$SEQ_BACKUP" > "$REPO_ROOT/logs/.event_sequence"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1; exit 0

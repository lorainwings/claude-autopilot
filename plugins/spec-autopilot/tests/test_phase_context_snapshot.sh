#!/usr/bin/env bash
# test_phase_context_snapshot.sh — Tests for save-phase-context.sh
# Verifies: context snapshot write, markdown structure, compaction integration
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../runtime/scripts" && pwd)"
source "$TEST_DIR/_test_helpers.sh"
source "$TEST_DIR/_fixtures.sh"

echo "--- phase context snapshots ---"
setup_autopilot_fixture

# Setup: Create a change directory
CHANGE_DIR="$REPO_ROOT/openspec/changes/test-fixture"
mkdir -p "$CHANGE_DIR/context/phase-results"

# 4a. save-phase-context.sh syntax check
if bash -n "$SCRIPT_DIR/save-phase-context.sh" 2>/dev/null; then
  green "  PASS: 4a. save-phase-context.sh syntax OK"
  PASS=$((PASS + 1))
else
  red "  FAIL: 4a. save-phase-context.sh syntax error"
  FAIL=$((FAIL + 1))
fi

# 4b. Write context snapshot
bash "$SCRIPT_DIR/save-phase-context.sh" 1 full '{"summary":"Requirements analyzed","decisions":["Use REST API","PostgreSQL DB"],"constraints":["Max 100ms latency"],"artifacts":["phase-1-requirements.json"]}' 2>/dev/null
EXIT_CODE=$?
assert_exit "4b. write context snapshot → exit 0" 0 "$EXIT_CODE"

# 4c. Verify snapshot file exists
SNAPSHOT_DIR="$CHANGE_DIR/context/phase-context-snapshots"
SNAPSHOT_FILE="$SNAPSHOT_DIR/phase-1-context.md"
if [ -f "$SNAPSHOT_FILE" ]; then
  green "  PASS: 4c. snapshot file created"
  PASS=$((PASS + 1))
else
  red "  FAIL: 4c. snapshot file not created"
  FAIL=$((FAIL + 1))
fi

# 4d. Verify markdown structure
if [ -f "$SNAPSHOT_FILE" ]; then
  CONTENT=$(cat "$SNAPSHOT_FILE")
  if echo "$CONTENT" | grep -q "Phase 1 Context Snapshot"; then
    green "  PASS: 4d. markdown has Phase 1 header"
    PASS=$((PASS + 1))
  else
    red "  FAIL: 4d. markdown missing Phase 1 header"
    FAIL=$((FAIL + 1))
  fi
else
  red "  FAIL: 4d. (skipped - no file)"
  FAIL=$((FAIL + 1))
fi

# 4e. Verify content includes decisions
if [ -f "$SNAPSHOT_FILE" ] && grep -q "REST API" "$SNAPSHOT_FILE"; then
  green "  PASS: 4e. snapshot contains decisions"
  PASS=$((PASS + 1))
else
  red "  FAIL: 4e. snapshot missing decisions content"
  FAIL=$((FAIL + 1))
fi

# 4f. Empty phase arg exits 0 gracefully
bash "$SCRIPT_DIR/save-phase-context.sh" 2>/dev/null
EXIT_CODE=$?
assert_exit "4f. empty args → exit 0" 0 "$EXIT_CODE"

# 4g. reinject-state-after-compact.sh syntax check
if bash -n "$SCRIPT_DIR/reinject-state-after-compact.sh" 2>/dev/null; then
  green "  PASS: 4g. reinject-state-after-compact.sh syntax OK"
  PASS=$((PASS + 1))
else
  red "  FAIL: 4g. reinject-state-after-compact.sh syntax error"
  FAIL=$((FAIL + 1))
fi

# 4h. save-state-before-compact.sh syntax check
if bash -n "$SCRIPT_DIR/save-state-before-compact.sh" 2>/dev/null; then
  green "  PASS: 4h. save-state-before-compact.sh syntax OK"
  PASS=$((PASS + 1))
else
  red "  FAIL: 4h. save-state-before-compact.sh syntax error"
  FAIL=$((FAIL + 1))
fi

# === Compact state with progress files (v5.9) ===

# 4i. save-state-before-compact.sh includes in-progress phase from progress files
# Setup: create change dir with Phase 1 checkpoint + Phase 3 progress file
COMPACT_TEST_DIR="$REPO_ROOT/openspec/changes/compact-test"
mkdir -p "$COMPACT_TEST_DIR/context/phase-results"
echo '{"status":"ok","summary":"Done","decisions":[{"point":"x","choice":"y"}]}' \
  > "$COMPACT_TEST_DIR/context/phase-results/phase-1-requirements.json"
echo '{"step":"agent_dispatched","status":"in_progress"}' \
  > "$COMPACT_TEST_DIR/context/phase-results/phase-3-progress.json"
# Lock file pointing to compact-test
echo '{"change":"compact-test","mode":"full","pid":"99999","started":"2026-01-01T00:00:00Z","anchor_sha":"abc123"}' \
  > "$REPO_ROOT/openspec/changes/.autopilot-active"
FIXTURE_LOCK_CREATED=true

# Run save-state
echo '{"cwd":"'"$REPO_ROOT"'"}' | bash "$SCRIPT_DIR/save-state-before-compact.sh" 2>/dev/null
STATE_MD="$COMPACT_TEST_DIR/context/autopilot-state.md"
if [ -f "$STATE_MD" ] && grep -q "Current in-progress phase" "$STATE_MD"; then
  green "  PASS: 4i. compact state includes in-progress phase"
  PASS=$((PASS + 1))
else
  red "  FAIL: 4i. compact state missing in-progress phase"
  FAIL=$((FAIL + 1))
fi

# 4j. State file contains next_phase extractable by POSIX sed (validates reinject compatibility)
if [ -f "$STATE_MD" ]; then
  EXTRACTED=$(sed -n 's/.*\*\*Next phase to execute\*\*: \([0-9][0-9]*\).*/\1/p' "$STATE_MD" | head -1)
  if [ -n "$EXTRACTED" ] && [ "$EXTRACTED" -gt 0 ] 2>/dev/null; then
    green "  PASS: 4j. state file next_phase extractable by POSIX sed (phase=$EXTRACTED)"
    PASS=$((PASS + 1))
  else
    red "  FAIL: 4j. state file next_phase not extractable by POSIX sed (got: '$EXTRACTED')"
    FAIL=$((FAIL + 1))
  fi
else
  red "  FAIL: 4j. (skipped — state file not created)"
  FAIL=$((FAIL + 1))
fi

# Cleanup compact-test
rm -rf "$COMPACT_TEST_DIR" 2>/dev/null || true

# Cleanup
rm -rf "$CHANGE_DIR" 2>/dev/null || true

teardown_autopilot_fixture
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1; exit 0

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

# Cleanup
rm -rf "$CHANGE_DIR" 2>/dev/null || true

teardown_autopilot_fixture
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1; exit 0

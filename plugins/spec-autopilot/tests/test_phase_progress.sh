#!/usr/bin/env bash
# test_phase_progress.sh — Tests for write-phase-progress.sh
# Verifies: progress file write, atomic tmp+mv, JSON structure
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../runtime/scripts" && pwd)"
source "$TEST_DIR/_test_helpers.sh"
source "$TEST_DIR/_fixtures.sh"

echo "--- phase progress tracking ---"
setup_autopilot_fixture

# Setup: Create a change with phase-results directory
CHANGE_DIR="$REPO_ROOT/openspec/changes/test-fixture/context/phase-results"
mkdir -p "$CHANGE_DIR"

# 3a. write-phase-progress.sh syntax check
if bash -n "$SCRIPT_DIR/write-phase-progress.sh" 2>/dev/null; then
  green "  PASS: 3a. write-phase-progress.sh syntax OK"
  PASS=$((PASS + 1))
else
  red "  FAIL: 3a. write-phase-progress.sh syntax error"
  FAIL=$((FAIL + 1))
fi

# 3b. Write progress file — gate_passed
bash "$SCRIPT_DIR/write-phase-progress.sh" 2 gate_passed in_progress 2>/dev/null
EXIT_CODE=$?
assert_exit "3b. write gate_passed progress → exit 0" 0 "$EXIT_CODE"

# 3c. Verify progress file exists
PROGRESS_FILE="$CHANGE_DIR/phase-2-progress.json"
if [ -f "$PROGRESS_FILE" ]; then
  green "  PASS: 3c. progress file created"
  PASS=$((PASS + 1))
else
  red "  FAIL: 3c. progress file not created"
  FAIL=$((FAIL + 1))
fi

# 3d. Verify JSON structure
if command -v python3 &>/dev/null && [ -f "$PROGRESS_FILE" ]; then
  STEP=$(python3 -c "import json; d=json.load(open('$PROGRESS_FILE')); print(d.get('step',''))" 2>/dev/null)
  if [ "$STEP" = "gate_passed" ]; then
    green "  PASS: 3d. JSON step field = gate_passed"
    PASS=$((PASS + 1))
  else
    red "  FAIL: 3d. JSON step field = '$STEP' (expected gate_passed)"
    FAIL=$((FAIL + 1))
  fi
else
  red "  FAIL: 3d. python3 unavailable or file missing"
  FAIL=$((FAIL + 1))
fi

# 3e. Overwrite with new step
bash "$SCRIPT_DIR/write-phase-progress.sh" 2 agent_dispatched in_progress '{"agent_id":"phase2-openspec"}' 2>/dev/null
if command -v python3 &>/dev/null && [ -f "$PROGRESS_FILE" ]; then
  STEP=$(python3 -c "import json; d=json.load(open('$PROGRESS_FILE')); print(d.get('step',''))" 2>/dev/null)
  if [ "$STEP" = "agent_dispatched" ]; then
    green "  PASS: 3e. progress overwritten to agent_dispatched"
    PASS=$((PASS + 1))
  else
    red "  FAIL: 3e. progress not overwritten (step=$STEP)"
    FAIL=$((FAIL + 1))
  fi
else
  red "  FAIL: 3e. cannot verify overwrite"
  FAIL=$((FAIL + 1))
fi

# 3f. Empty args exit 0 gracefully
bash "$SCRIPT_DIR/write-phase-progress.sh" 2>/dev/null
EXIT_CODE=$?
assert_exit "3f. empty args → exit 0" 0 "$EXIT_CODE"

# 3g. No .tmp residual after write
TMP_FILES=$(find "$CHANGE_DIR" -name "*.tmp" 2>/dev/null | wc -l)
if [ "$TMP_FILES" -eq 0 ]; then
  green "  PASS: 3g. no .tmp residual files"
  PASS=$((PASS + 1))
else
  red "  FAIL: 3g. found $TMP_FILES .tmp residual files"
  FAIL=$((FAIL + 1))
fi

# Cleanup
rm -f "$PROGRESS_FILE" 2>/dev/null || true
rm -rf "$REPO_ROOT/openspec/changes/test-fixture" 2>/dev/null || true

teardown_autopilot_fixture
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1; exit 0

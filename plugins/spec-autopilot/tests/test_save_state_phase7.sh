#!/usr/bin/env bash
# test_save_state_phase7.sh — Section 18: save-state Phase 7 scan
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../runtime/scripts" && pwd)"
source "$TEST_DIR/_test_helpers.sh"
source "$TEST_DIR/_fixtures.sh"

echo "--- 18. save-state Phase 7 scan ---"
setup_autopilot_fixture

# 18a. save-state-before-compact.sh scans Phase 1-7 (not 1-6)
if grep -q 'for phase_num in \[1, 2, 3, 4, 5, 6, 7\]' "$SCRIPT_DIR/save-state-before-compact.sh"; then
  green "  PASS: PreCompact state save scans Phase 1-7"
  PASS=$((PASS + 1))
else
  red "  FAIL: PreCompact state save does not scan Phase 1-7"
  FAIL=$((FAIL + 1))
fi

# 18b. phase_names includes Phase 7
if grep -q "7: 'Archive'" "$SCRIPT_DIR/save-state-before-compact.sh"; then
  green "  PASS: phase_names includes Phase 7 (Archive)"
  PASS=$((PASS + 1))
else
  red "  FAIL: phase_names missing Phase 7"
  FAIL=$((FAIL + 1))
fi

teardown_autopilot_fixture
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1; exit 0

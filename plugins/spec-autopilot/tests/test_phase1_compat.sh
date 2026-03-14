#!/usr/bin/env bash
# test_phase1_compat.sh — Section 14: Phase 1 checkpoint compatibility
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../scripts" && pwd)"
source "$TEST_DIR/_test_helpers.sh"
source "$TEST_DIR/_fixtures.sh"

echo "--- 14. Phase 1 checkpoint compatibility ---"
setup_autopilot_fixture

# 14a. check-predecessor-checkpoint.sh scans Phase 1-7
if grep -q 'for phase_num in 1 2 3 4 5 6 7' "$SCRIPT_DIR/check-predecessor-checkpoint.sh"; then
  green "  PASS: predecessor hook scans Phase 1-7 checkpoints"
  PASS=$((PASS + 1))
else
  red "  FAIL: predecessor hook does not scan Phase 1-7"
  FAIL=$((FAIL + 1))
fi

# 14b. scan-checkpoints-on-start.sh scans Phase 1-7
if grep -q 'for phase_num in 1 2 3 4 5 6 7' "$SCRIPT_DIR/scan-checkpoints-on-start.sh"; then
  green "  PASS: SessionStart scan includes Phase 1-7"
  PASS=$((PASS + 1))
else
  red "  FAIL: SessionStart scan does not include Phase 1-7"
  FAIL=$((FAIL + 1))
fi

# 14c. save-state scans Phase 1 (included in 1-7 range)
if grep -q 'for phase_num in \[1, 2, 3, 4, 5, 6, 7\]' "$SCRIPT_DIR/save-state-before-compact.sh"; then
  green "  PASS: PreCompact state save includes Phase 1"
  PASS=$((PASS + 1))
else
  red "  FAIL: PreCompact state save does not include Phase 1"
  FAIL=$((FAIL + 1))
fi

# 14d. Phase 2 independent check is documented
if grep -q 'Phase 2 independent check' "$SCRIPT_DIR/check-predecessor-checkpoint.sh"; then
  green "  PASS: Phase 2 independent check documented in comments"
  PASS=$((PASS + 1))
else
  red "  FAIL: Phase 2 independent check not documented"
  FAIL=$((FAIL + 1))
fi

teardown_autopilot_fixture
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1; exit 0

#!/usr/bin/env bash
# test_common.sh — Section 12: _common.sh basic tests
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../scripts" && pwd)"
source "$TEST_DIR/_test_helpers.sh"
source "$TEST_DIR/_fixtures.sh"

echo "--- 12. _common.sh shared library ---"
setup_autopilot_fixture

# 12a. _common.sh syntax check
if bash -n "$SCRIPT_DIR/_common.sh" 2>/dev/null; then
  green "  PASS: _common.sh syntax OK"
  PASS=$((PASS + 1))
else
  red "  FAIL: _common.sh syntax error"
  FAIL=$((FAIL + 1))
fi

# 12b. _common.sh is sourced by both hook scripts
if grep -q 'source.*_common.sh' "$SCRIPT_DIR/check-predecessor-checkpoint.sh" && \
   grep -q 'source.*_common.sh' "$SCRIPT_DIR/save-state-before-compact.sh"; then
  green "  PASS: both hook scripts source _common.sh"
  PASS=$((PASS + 1))
else
  red "  FAIL: hook scripts not sourcing _common.sh"
  FAIL=$((FAIL + 1))
fi

teardown_autopilot_fixture
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1; exit 0

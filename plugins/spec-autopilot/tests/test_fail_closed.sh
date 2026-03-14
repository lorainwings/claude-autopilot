#!/usr/bin/env bash
# test_fail_closed.sh — Sections 7+9: fail-closed + consistency
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../scripts" && pwd)"
source "$TEST_DIR/_test_helpers.sh"
source "$TEST_DIR/_fixtures.sh"

echo "--- 7. deny() fail-closed test ---"
setup_autopilot_fixture

# 7a. Verify deny fallback works when python3 json.dumps "crashes"
# We can't easily crash json.dumps, but we can verify the fallback structure exists
if grep -q 'hookSpecificOutput.*permissionDecision.*deny.*internal error' "$SCRIPT_DIR/check-predecessor-checkpoint.sh"; then
  green "  PASS: deny() has hardcoded JSON fallback for fail-closed behavior"
  PASS=$((PASS + 1))
else
  red "  FAIL: deny() missing fail-closed fallback"
  FAIL=$((FAIL + 1))
fi

echo ""

echo "--- 9. Fail-closed consistency check ---"

# 9a. validate-json-envelope.sh should block autopilot tasks with fail-closed behavior
if grep -q 'decision.*block' "$SCRIPT_DIR/validate-json-envelope.sh" && \
   grep -q 'python3 is required' "$SCRIPT_DIR/validate-json-envelope.sh"; then
  green "  PASS: validate-json-envelope.sh has fail-closed block for missing python3"
  PASS=$((PASS + 1))
else
  red "  FAIL: validate-json-envelope.sh missing fail-closed behavior"
  FAIL=$((FAIL + 1))
fi

# 9b. check-predecessor-checkpoint.sh should deny autopilot tasks (verified by checking source)
if grep -q 'permissionDecision.*deny' "$SCRIPT_DIR/check-predecessor-checkpoint.sh" && \
   grep -q 'python3 is required' "$SCRIPT_DIR/check-predecessor-checkpoint.sh"; then
  green "  PASS: check-predecessor-checkpoint.sh has fail-closed deny for missing python3"
  PASS=$((PASS + 1))
else
  red "  FAIL: check-predecessor-checkpoint.sh missing fail-closed behavior"
  FAIL=$((FAIL + 1))
fi

# 9c. Both scripts use bash marker pre-check before python3
if grep -q 'autopilot-phase:\[0-9\]' "$SCRIPT_DIR/check-predecessor-checkpoint.sh" && \
   grep -q 'autopilot-phase:\[0-9\]' "$SCRIPT_DIR/validate-json-envelope.sh"; then
  green "  PASS: both scripts use pure bash marker pre-check"
  PASS=$((PASS + 1))
else
  red "  FAIL: missing bash marker pre-check in one or both scripts"
  FAIL=$((FAIL + 1))
fi

# 9d. unified-write-edit-check.sh uses require_python3 (not raw command -v python3)
if grep -q 'require_python3' "$SCRIPT_DIR/unified-write-edit-check.sh" && \
   ! grep -q 'command -v python3.*exit 0' "$SCRIPT_DIR/unified-write-edit-check.sh"; then
  green "  PASS: unified-write-edit-check.sh uses require_python3 fail-closed pattern"
  PASS=$((PASS + 1))
else
  red "  FAIL: unified-write-edit-check.sh still uses raw command -v python3 (silent exit)"
  FAIL=$((FAIL + 1))
fi

teardown_autopilot_fixture
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1; exit 0

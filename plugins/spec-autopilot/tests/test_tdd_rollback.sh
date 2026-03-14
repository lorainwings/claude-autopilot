#!/usr/bin/env bash
# test_tdd_rollback.sh — Tests for tdd-refactor-rollback.sh
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../scripts" && pwd)"
source "$TEST_DIR/_test_helpers.sh"
source "$TEST_DIR/_fixtures.sh"

ROLLBACK_SCRIPT="$SCRIPT_DIR/tdd-refactor-rollback.sh"

echo "--- TDD Refactor Rollback Tests ---"

# 1a. Script is executable
if [ -x "$ROLLBACK_SCRIPT" ]; then
  green "  PASS: tdd-refactor-rollback.sh is executable"
  PASS=$((PASS + 1))
else
  red "  FAIL: tdd-refactor-rollback.sh is not executable"
  FAIL=$((FAIL + 1))
fi

# 1b. No arguments → error JSON with usage message
OUTPUT=$(bash "$ROLLBACK_SCRIPT" 2>&1) || true
assert_contains "1b. no-arg produces error JSON" "$OUTPUT" '"status":"error"'

# 1c. Non-REFACTOR stage → rejected
TEMP_CHANGE_DIR=$(mktemp -d)
mkdir -p "$TEMP_CHANGE_DIR/context"
echo "green" > "$TEMP_CHANGE_DIR/context/.tdd-stage"
OUTPUT=$(bash "$ROLLBACK_SCRIPT" "$TEMP_CHANGE_DIR" 2>&1) || true
assert_contains "1c. non-REFACTOR stage rejected" "$OUTPUT" "not REFACTOR"
rm -rf "$TEMP_CHANGE_DIR"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1; exit 0

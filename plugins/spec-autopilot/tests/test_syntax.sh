#!/usr/bin/env bash
# test_syntax.sh — Section 1: bash -n syntax checks
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../runtime/scripts" && pwd)"
source "$TEST_DIR/_test_helpers.sh"
source "$TEST_DIR/_fixtures.sh"

echo "--- 1. Syntax checks (bash -n) ---"
setup_autopilot_fixture

for script in "$SCRIPT_DIR"/*.sh; do
  name=$(basename "$script")

  if bash -n "$script" 2>/dev/null; then
    green "  PASS: $name syntax OK"
    PASS=$((PASS + 1))
  else
    red "  FAIL: $name syntax error"
    FAIL=$((FAIL + 1))
  fi
done

teardown_autopilot_fixture
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1; exit 0

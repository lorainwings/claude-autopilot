#!/usr/bin/env bash
# test_lock_file_parsing.sh — Section 13: JSON lock file parsing
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../runtime/scripts" && pwd)"
source "$TEST_DIR/_test_helpers.sh"
source "$TEST_DIR/_fixtures.sh"

echo "--- 13. JSON lock file parsing ---"
setup_autopilot_fixture

# 13a. parse_lock_file reads JSON format
TMPDIR_TEST=$(mktemp -d)
echo '{"change":"test-feature","pid":12345,"started":"2026-01-01T00:00:00Z"}' >"$TMPDIR_TEST/.autopilot-active"
source "$SCRIPT_DIR/_common.sh"
lock_result=$(parse_lock_file "$TMPDIR_TEST/.autopilot-active")
if [ "$lock_result" = "test-feature" ]; then
  green "  PASS: parse_lock_file reads JSON format correctly"
  PASS=$((PASS + 1))
else
  red "  FAIL: parse_lock_file JSON result='$lock_result', expected 'test-feature'"
  FAIL=$((FAIL + 1))
fi

# 13b. parse_lock_file reads legacy plain text format
echo "legacy-change-name" >"$TMPDIR_TEST/.autopilot-active"
lock_result=$(parse_lock_file "$TMPDIR_TEST/.autopilot-active")
if [ "$lock_result" = "legacy-change-name" ]; then
  green "  PASS: parse_lock_file reads legacy plain text format"
  PASS=$((PASS + 1))
else
  red "  FAIL: parse_lock_file legacy result='$lock_result', expected 'legacy-change-name'"
  FAIL=$((FAIL + 1))
fi

# 13c. parse_lock_file handles missing file
lock_result=$(parse_lock_file "$TMPDIR_TEST/nonexistent" 2>/dev/null) || true
if [ -z "$lock_result" ]; then
  green "  PASS: parse_lock_file handles missing file gracefully"
  PASS=$((PASS + 1))
else
  red "  FAIL: parse_lock_file should return empty for missing file"
  FAIL=$((FAIL + 1))
fi

rm -rf "$TMPDIR_TEST"

teardown_autopilot_fixture
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1
exit 0

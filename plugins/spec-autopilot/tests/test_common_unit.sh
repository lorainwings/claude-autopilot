#!/usr/bin/env bash
# test_common_unit.sh — Section 19: _common.sh unit tests (extensive)
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../scripts" && pwd)"
source "$TEST_DIR/_test_helpers.sh"
source "$TEST_DIR/_fixtures.sh"

echo "--- 19. _common.sh unit tests ---"
setup_autopilot_fixture

# Need a temp directory for these tests
COMMON_TEST_DIR=$(mktemp -d)
trap "rm -rf $COMMON_TEST_DIR" EXIT

# Source _common.sh
source "$SCRIPT_DIR/_common.sh"

# 19a. parse_lock_file with JSON format
echo '{"change":"my-feature","pid":"12345","started":"2026-01-01T00:00:00Z"}' > "$COMMON_TEST_DIR/lock.json"
result=$(parse_lock_file "$COMMON_TEST_DIR/lock.json")
if [ "$result" = "my-feature" ]; then
  green "  PASS: parse_lock_file JSON format"
  PASS=$((PASS + 1))
else
  red "  FAIL: parse_lock_file JSON format (got '$result')"
  FAIL=$((FAIL + 1))
fi

# 19b. parse_lock_file with legacy plain text
echo "legacy-change-name" > "$COMMON_TEST_DIR/lock.txt"
result=$(parse_lock_file "$COMMON_TEST_DIR/lock.txt")
if [ "$result" = "legacy-change-name" ]; then
  green "  PASS: parse_lock_file legacy plain text"
  PASS=$((PASS + 1))
else
  red "  FAIL: parse_lock_file legacy plain text (got '$result')"
  FAIL=$((FAIL + 1))
fi

# 19c. parse_lock_file with invalid/empty file
echo "" > "$COMMON_TEST_DIR/lock_empty.txt"
result=$(parse_lock_file "$COMMON_TEST_DIR/lock_empty.txt")
if [ -z "$result" ]; then
  green "  PASS: parse_lock_file empty file returns empty"
  PASS=$((PASS + 1))
else
  red "  FAIL: parse_lock_file empty file (got '$result')"
  FAIL=$((FAIL + 1))
fi

# 19d. parse_lock_file with missing file
result=""
parse_lock_file "$COMMON_TEST_DIR/nonexistent.json" || true
result=$(parse_lock_file "$COMMON_TEST_DIR/nonexistent.json" 2>/dev/null || echo "")
if [ -z "$result" ]; then
  green "  PASS: parse_lock_file missing file returns empty"
  PASS=$((PASS + 1))
else
  red "  FAIL: parse_lock_file missing file (got '$result')"
  FAIL=$((FAIL + 1))
fi

# 19e. find_active_change with lock file priority
mkdir -p "$COMMON_TEST_DIR/changes/feature-a"
mkdir -p "$COMMON_TEST_DIR/changes/feature-b"
echo '{"change":"feature-a"}' > "$COMMON_TEST_DIR/changes/.autopilot-active"
result=$(find_active_change "$COMMON_TEST_DIR/changes")
if echo "$result" | grep -q "feature-a"; then
  green "  PASS: find_active_change lock file priority"
  PASS=$((PASS + 1))
else
  red "  FAIL: find_active_change lock file priority (got '$result')"
  FAIL=$((FAIL + 1))
fi

# 19f. find_active_change with trailing slash
result=$(find_active_change "$COMMON_TEST_DIR/changes" "yes")
if [[ "$result" == */ ]]; then
  green "  PASS: find_active_change trailing slash"
  PASS=$((PASS + 1))
else
  red "  FAIL: find_active_change trailing slash (got '$result')"
  FAIL=$((FAIL + 1))
fi

# 19g. find_active_change excludes _prefixed dirs
mkdir -p "$COMMON_TEST_DIR/changes2/_archived"
mkdir -p "$COMMON_TEST_DIR/changes2/real-change"
result=$(find_active_change "$COMMON_TEST_DIR/changes2")
if echo "$result" | grep -q "real-change"; then
  green "  PASS: find_active_change excludes _prefix"
  PASS=$((PASS + 1))
else
  red "  FAIL: find_active_change excludes _prefix (got '$result')"
  FAIL=$((FAIL + 1))
fi

# 19h. read_checkpoint_status with all statuses
for status_val in ok warning blocked failed; do
  echo "{\"status\":\"$status_val\"}" > "$COMMON_TEST_DIR/ckpt_${status_val}.json"
  result=$(read_checkpoint_status "$COMMON_TEST_DIR/ckpt_${status_val}.json")
  if [ "$result" = "$status_val" ]; then
    green "  PASS: read_checkpoint_status '$status_val'"
    PASS=$((PASS + 1))
  else
    red "  FAIL: read_checkpoint_status '$status_val' (got '$result')"
    FAIL=$((FAIL + 1))
  fi
done

# 19i. read_checkpoint_status with invalid JSON
echo "not json at all" > "$COMMON_TEST_DIR/ckpt_bad.json"
result=$(read_checkpoint_status "$COMMON_TEST_DIR/ckpt_bad.json")
if [ "$result" = "error" ]; then
  green "  PASS: read_checkpoint_status invalid JSON returns error"
  PASS=$((PASS + 1))
else
  red "  FAIL: read_checkpoint_status invalid JSON (got '$result')"
  FAIL=$((FAIL + 1))
fi

# 19j. find_checkpoint
mkdir -p "$COMMON_TEST_DIR/phase-results"
echo '{"status":"ok"}' > "$COMMON_TEST_DIR/phase-results/phase-3-ff.json"
result=$(find_checkpoint "$COMMON_TEST_DIR/phase-results" 3)
if [ -n "$result" ] && echo "$result" | grep -q "phase-3-ff.json"; then
  green "  PASS: find_checkpoint finds phase-3"
  PASS=$((PASS + 1))
else
  red "  FAIL: find_checkpoint phase-3 (got '$result')"
  FAIL=$((FAIL + 1))
fi

# 19k. find_checkpoint for missing phase
result=$(find_checkpoint "$COMMON_TEST_DIR/phase-results" 9)
if [ -z "$result" ]; then
  green "  PASS: find_checkpoint missing phase returns empty"
  PASS=$((PASS + 1))
else
  red "  FAIL: find_checkpoint missing phase (got '$result')"
  FAIL=$((FAIL + 1))
fi

teardown_autopilot_fixture
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1; exit 0

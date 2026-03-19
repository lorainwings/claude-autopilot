#!/usr/bin/env bash
# test_tdd_rollback.sh — Tests for tdd-refactor-rollback.sh
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../runtime/scripts" && pwd)"
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

# 1d. No .tdd-refactor-files → ok (nothing to rollback)
TEMP_CHANGE_DIR=$(mktemp -d)
mkdir -p "$TEMP_CHANGE_DIR/context"
echo "refactor" > "$TEMP_CHANGE_DIR/context/.tdd-stage"
OUTPUT=$(bash "$ROLLBACK_SCRIPT" "$TEMP_CHANGE_DIR" 2>&1) || true
assert_contains "1d. no refactor-files → ok" "$OUTPUT" '"status":"ok"'
assert_contains "1d. mentions nothing to rollback" "$OUTPUT" "Nothing to rollback"
rm -rf "$TEMP_CHANGE_DIR"

# 1e. .tdd-refactor-files with 2 files → only those 2 files rolled back, others untouched
TEMP_CHANGE_DIR=$(mktemp -d)
mkdir -p "$TEMP_CHANGE_DIR/context"
echo "refactor" > "$TEMP_CHANGE_DIR/context/.tdd-stage"
# Set up a git repo for rollback testing
GIT_TMPDIR=$(mktemp -d)
trap 'rm -rf "$TEMP_CHANGE_DIR" "$GIT_TMPDIR"' EXIT
cd "$GIT_TMPDIR"
git init -q
echo "original-a" > file_a.txt
echo "original-b" > file_b.txt
echo "original-c" > file_c.txt
git add -A && git commit -q -m "init"
# Modify files (simulating REFACTOR changes)
echo "modified-a" > file_a.txt
echo "modified-b" > file_b.txt
echo "modified-c" > file_c.txt
# Only record file_a and file_b as refactor files
echo "$GIT_TMPDIR/file_a.txt" > "$TEMP_CHANGE_DIR/context/.tdd-refactor-files"
echo "$GIT_TMPDIR/file_b.txt" >> "$TEMP_CHANGE_DIR/context/.tdd-refactor-files"
OUTPUT=$(bash "$ROLLBACK_SCRIPT" "$TEMP_CHANGE_DIR" 2>&1) || true
assert_contains "1e. rollback 2 files → ok" "$OUTPUT" '"status":"ok"'
# file_a and file_b should be restored, file_c should remain modified
FILE_A_CONTENT=$(cat "$GIT_TMPDIR/file_a.txt")
FILE_C_CONTENT=$(cat "$GIT_TMPDIR/file_c.txt")
if [ "$FILE_A_CONTENT" = "original-a" ]; then
  green "  PASS: 1e. file_a restored to original"
  PASS=$((PASS + 1))
else
  red "  FAIL: 1e. file_a not restored (got: $FILE_A_CONTENT)"
  FAIL=$((FAIL + 1))
fi
if [ "$FILE_C_CONTENT" = "modified-c" ]; then
  green "  PASS: 1e. file_c untouched"
  PASS=$((PASS + 1))
else
  red "  FAIL: 1e. file_c was incorrectly rolled back"
  FAIL=$((FAIL + 1))
fi
# .tdd-refactor-files should be cleaned up
if [ ! -f "$TEMP_CHANGE_DIR/context/.tdd-refactor-files" ]; then
  green "  PASS: 1e. .tdd-refactor-files cleaned up"
  PASS=$((PASS + 1))
else
  red "  FAIL: 1e. .tdd-refactor-files not cleaned up"
  FAIL=$((FAIL + 1))
fi
cd "$TEST_DIR"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1; exit 0

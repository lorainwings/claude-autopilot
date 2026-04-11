#!/usr/bin/env bash
# test_lockfile_scripts.sh — Tests for create-lockfile.sh and update-anchor-sha.sh
# WP-6: Validates the standalone scripts extracted from Phase 0 inline Python.
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../runtime/scripts" && pwd)"
source "$TEST_DIR/_test_helpers.sh"

echo "--- Lockfile standalone scripts ---"

TMPDIR_TEST=$(mktemp -d)
trap 'rm -rf "$TMPDIR_TEST"' EXIT

# ============================================================
# create-lockfile.sh tests
# ============================================================

echo "  -- create-lockfile.sh --"

# 1. Create new lockfile -> status ok, action created
LOCK_JSON='{"change":"feat-abc","pid":99999,"started":"2026-01-01T00:00:00Z","session_cwd":"'"$TMPDIR_TEST"'","anchor_sha":"","session_id":"test-session-1","mode":"full"}'
OUT=$(bash "$SCRIPT_DIR/create-lockfile.sh" "$TMPDIR_TEST" "$LOCK_JSON")
assert_json_field "1. new lockfile status" "$OUT" "status" "ok"
assert_json_field "1. new lockfile action" "$OUT" "action" "created"

# 2. Overwrite stale lockfile (PID dead) -> status ok, action overwritten
#    Write a lockfile with a PID that is certainly not alive (PID 2147483647)
mkdir -p "$TMPDIR_TEST/openspec/changes"
echo '{"change":"old","pid":2147483647,"session_id":"old-session"}' > "$TMPDIR_TEST/openspec/changes/.autopilot-active"
LOCK_JSON2='{"change":"feat-xyz","pid":99998,"started":"2026-02-01T00:00:00Z","session_cwd":"'"$TMPDIR_TEST"'","anchor_sha":"","session_id":"test-session-2","mode":"full"}'
OUT2=$(bash "$SCRIPT_DIR/create-lockfile.sh" "$TMPDIR_TEST" "$LOCK_JSON2")
assert_json_field "2. overwrite stale status" "$OUT2" "status" "ok"
assert_json_field "2. overwrite stale action" "$OUT2" "action" "overwritten"

# 3. Verify atomic write (file is valid JSON after creation)
LOCK_FILE="$TMPDIR_TEST/openspec/changes/.autopilot-active"
VALIDATE=$(python3 -c "import json,sys; json.load(open(sys.argv[1])); print('valid')" "$LOCK_FILE" 2>/dev/null || echo "invalid")
if [ "$VALIDATE" = "valid" ]; then
  green "  PASS: 3. lockfile is valid JSON after atomic write"
  PASS=$((PASS + 1))
else
  red "  FAIL: 3. lockfile is not valid JSON after atomic write"
  FAIL=$((FAIL + 1))
fi

# ============================================================
# update-anchor-sha.sh tests
# ============================================================

echo "  -- update-anchor-sha.sh --"

# 4. Update anchor_sha -> status ok, verify field updated
mkdir -p "$TMPDIR_TEST/openspec/changes"
echo '{"change":"feat-update","pid":12345,"anchor_sha":"","session_id":"s1"}' > "$TMPDIR_TEST/openspec/changes/.autopilot-active"
LOCK_PATH="$TMPDIR_TEST/openspec/changes/.autopilot-active"
OUT4=$(bash "$SCRIPT_DIR/update-anchor-sha.sh" "$LOCK_PATH" "abc123def")
assert_json_field "4. update anchor status" "$OUT4" "status" "ok"
assert_json_field "4. update anchor sha" "$OUT4" "anchor_sha" "abc123def"

# Verify the file on disk has the updated anchor_sha
DISK_SHA=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('anchor_sha',''))" "$LOCK_PATH" 2>/dev/null || echo "")
if [ "$DISK_SHA" = "abc123def" ]; then
  green "  PASS: 4b. on-disk anchor_sha matches"
  PASS=$((PASS + 1))
else
  red "  FAIL: 4b. on-disk anchor_sha='$DISK_SHA', expected 'abc123def'"
  FAIL=$((FAIL + 1))
fi

# 5. Invalid lock path -> status error
OUT5=$(bash "$SCRIPT_DIR/update-anchor-sha.sh" "$TMPDIR_TEST/nonexistent/path/.autopilot-active" "sha123" 2>/dev/null) || true
assert_contains "5. invalid path returns error" "$OUT5" '"status"'

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1; exit 0

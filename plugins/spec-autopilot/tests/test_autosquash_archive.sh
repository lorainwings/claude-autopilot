#!/usr/bin/env bash
# test_autosquash_archive.sh — Tests for autosquash-archive.sh (WP-5)
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../runtime/scripts" && pwd)"
source "$TEST_DIR/_test_helpers.sh"

SCRIPT="$SCRIPT_DIR/autosquash-archive.sh"

echo "--- autosquash-archive.sh tests ---"

# ── Helper: create a temp git repo with autopilot-style commits ──
create_test_repo() {
  local tmpdir
  tmpdir=$(mktemp -d)
  local repo="$tmpdir/repo"
  mkdir -p "$repo"
  (
    cd "$repo" || exit 1
    git init -q 2>/dev/null
    git config user.email "test@test.com"
    git config user.name "Test"

    echo "initial" >README.md
    git add README.md
    git commit -q --no-verify -m "initial commit" 2>/dev/null
  ) >/dev/null 2>&1
  echo "$repo"
}

# ══════════════════════════════════════════════════════════════════
# 1. Valid anchor + all autopilot fixups → status ok
# ══════════════════════════════════════════════════════════════════
echo "  1. Valid anchor + all autopilot fixups → status ok"
REPO1=$(create_test_repo)
ANCHOR_FILE1="$(dirname "$REPO1")/.anchor"
(
  cd "$REPO1" || exit 1

  # Create anchor commit
  git commit -q --no-verify --allow-empty -m "autopilot: start test-change" 2>/dev/null
  ANCHOR_SHA=$(git rev-parse HEAD)

  # Create phase-results with 2 checkpoints
  mkdir -p openspec/changes/test-change/context/phase-results
  echo '{"status":"ok","phase":5}' >openspec/changes/test-change/context/phase-results/phase-5-implementation.json
  echo '{"status":"ok","phase":6}' >openspec/changes/test-change/context/phase-results/phase-6-test-report.json

  # Create 2 fixup commits (matching checkpoint count)
  echo "impl code" >src.txt
  git add -A 2>/dev/null
  git commit -q --no-verify --fixup="$ANCHOR_SHA" -m "fixup! autopilot: start test-change — Phase 5" 2>/dev/null

  echo "test report" >report.txt
  git add -A 2>/dev/null
  git commit -q --no-verify --fixup="$ANCHOR_SHA" -m "fixup! autopilot: start test-change — Phase 6" 2>/dev/null

  echo "$ANCHOR_SHA"
) >"$ANCHOR_FILE1" 2>/dev/null

ANCHOR1=$(cat "$ANCHOR_FILE1")
OUTPUT1=$(bash "$SCRIPT" "$REPO1" "$ANCHOR1" "test-change" 2>/dev/null)

assert_json_field "1a: status is ok" "$OUTPUT1" "status" "ok"
assert_contains "1b: anchor_sha present" "$OUTPUT1" "anchor_sha"
assert_contains "1c: squash_count present" "$OUTPUT1" "squash_count"

# Verify commits were actually squashed
COMMIT_COUNT1=$(git -C "$REPO1" rev-list --count HEAD 2>/dev/null)
assert_exit "1d: squashed to 2 commits (initial + squashed)" 2 "$COMMIT_COUNT1"

rm -rf "$(dirname "$REPO1")"

# ══════════════════════════════════════════════════════════════════
# 2. Fixup count < checkpoint count → status blocked
# ══════════════════════════════════════════════════════════════════
echo "  2. Fixup count < checkpoint count → status blocked"
REPO2=$(create_test_repo)
ANCHOR_FILE2="$(dirname "$REPO2")/.anchor"
(
  cd "$REPO2" || exit 1

  git commit -q --no-verify --allow-empty -m "autopilot: start test-change2" 2>/dev/null
  ANCHOR_SHA=$(git rev-parse HEAD)

  # Create 3 checkpoints but only 1 fixup
  mkdir -p openspec/changes/test-change2/context/phase-results
  echo '{"status":"ok","phase":4}' >openspec/changes/test-change2/context/phase-results/phase-4-test-design.json
  echo '{"status":"ok","phase":5}' >openspec/changes/test-change2/context/phase-results/phase-5-implementation.json
  echo '{"status":"ok","phase":6}' >openspec/changes/test-change2/context/phase-results/phase-6-test-report.json

  echo "some code" >code.txt
  git add -A 2>/dev/null
  git commit -q --no-verify --fixup="$ANCHOR_SHA" -m "fixup! autopilot: start test-change2 — Phase 5" 2>/dev/null

  echo "$ANCHOR_SHA"
) >"$ANCHOR_FILE2" 2>/dev/null

ANCHOR2=$(cat "$ANCHOR_FILE2")
OUTPUT2=$(bash "$SCRIPT" "$REPO2" "$ANCHOR2" "test-change2" 2>/dev/null)

assert_json_field "2a: status is blocked" "$OUTPUT2" "status" "blocked"
assert_contains "2b: error mentions fixup count" "$OUTPUT2" "Fixup count"

rm -rf "$(dirname "$REPO2")"

# ══════════════════════════════════════════════════════════════════
# 3. Non-autopilot fixups found → status needs_confirmation
# ══════════════════════════════════════════════════════════════════
echo "  3. Non-autopilot fixups → status needs_confirmation"
REPO3=$(create_test_repo)
ANCHOR_FILE3="$(dirname "$REPO3")/.anchor"
(
  cd "$REPO3" || exit 1

  git commit -q --no-verify --allow-empty -m "autopilot: start test-change3" 2>/dev/null
  ANCHOR_SHA=$(git rev-parse HEAD)

  # 1 checkpoint
  mkdir -p openspec/changes/test-change3/context/phase-results
  echo '{"status":"ok","phase":5}' >openspec/changes/test-change3/context/phase-results/phase-5-implementation.json

  # 1 autopilot fixup
  echo "impl" >impl.txt
  git add -A 2>/dev/null
  git commit -q --no-verify --fixup="$ANCHOR_SHA" -m "fixup! autopilot: start test-change3 — Phase 5" 2>/dev/null

  # 1 non-autopilot fixup (manual user fixup)
  echo "manual fix" >manual.txt
  git add -A 2>/dev/null
  git commit -q --no-verify -m "fixup! manual: user correction" 2>/dev/null

  echo "$ANCHOR_SHA"
) >"$ANCHOR_FILE3" 2>/dev/null

ANCHOR3=$(cat "$ANCHOR_FILE3")
OUTPUT3=$(bash "$SCRIPT" "$REPO3" "$ANCHOR3" "test-change3" 2>/dev/null)

assert_json_field "3a: status is needs_confirmation" "$OUTPUT3" "status" "needs_confirmation"

# Verify non_autopilot_fixups array is non-empty
HAS_NON_AP=$(python3 -c "
import json, sys
data = json.load(sys.stdin)
fixups = data.get('non_autopilot_fixups', [])
print('yes' if len(fixups) > 0 else 'no')
" <<<"$OUTPUT3" 2>/dev/null || echo "no")
assert_contains "3b: non_autopilot_fixups non-empty" "$HAS_NON_AP" "yes"

assert_contains "3c: fixup list contains manual" "$OUTPUT3" "fixup! manual"

rm -rf "$(dirname "$REPO3")"

# ══════════════════════════════════════════════════════════════════
# 4. Invalid anchor SHA + rebuild path → status ok
# ══════════════════════════════════════════════════════════════════
echo "  4. Invalid anchor SHA + rebuild path → status ok"
REPO4=$(create_test_repo)
ANCHOR_FILE4="$(dirname "$REPO4")/.anchor"
(
  cd "$REPO4" || exit 1

  git commit -q --no-verify --allow-empty -m "autopilot: start test-change4" 2>/dev/null
  ANCHOR_SHA=$(git rev-parse HEAD)

  mkdir -p openspec/changes/test-change4/context/phase-results
  echo '{"status":"ok","phase":5}' >openspec/changes/test-change4/context/phase-results/phase-5-implementation.json
  mkdir -p openspec/changes
  echo '{"change":"test-change4","anchor_sha":"deadbeef","session_id":"sess-4"}' >openspec/changes/.autopilot-active

  echo "impl" >impl.txt
  git add -A 2>/dev/null
  git commit -q --no-verify --fixup="$ANCHOR_SHA" -m "fixup! autopilot: start test-change4 — Phase 5" 2>/dev/null

  echo "$ANCHOR_SHA"
) >"$ANCHOR_FILE4" 2>/dev/null

OUTPUT4=$(bash "$SCRIPT" "$REPO4" "deadbeef1234567890deadbeef1234567890dead" "test-change4" 2>/dev/null)

assert_json_field "4a: status is ok after anchor rebuild" "$OUTPUT4" "status" "ok"
HEAD_SUBJECT4=$(git -C "$REPO4" log -1 --format='%s' 2>/dev/null || echo "")
assert_contains "4b: rebuilt anchor keeps autosquash-compatible subject" "$HEAD_SUBJECT4" "autopilot: start test-change4"

rm -rf "$(dirname "$REPO4")"

# ══════════════════════════════════════════════════════════════════
# 5. Non-autopilot fixups + confirmation flag → status ok
# ══════════════════════════════════════════════════════════════════
echo "  5. Non-autopilot fixups + confirmation flag → status ok"
REPO5=$(create_test_repo)
ANCHOR_FILE5="$(dirname "$REPO5")/.anchor"
(
  cd "$REPO5" || exit 1

  git commit -q --no-verify --allow-empty -m "autopilot: start test-change5" 2>/dev/null
  ANCHOR_SHA=$(git rev-parse HEAD)

  mkdir -p openspec/changes/test-change5/context/phase-results
  echo '{"status":"ok","phase":5}' >openspec/changes/test-change5/context/phase-results/phase-5-implementation.json

  echo "impl" >impl.txt
  git add -A 2>/dev/null
  git commit -q --no-verify --fixup="$ANCHOR_SHA" -m "fixup! autopilot: start test-change5 — Phase 5" 2>/dev/null

  echo "manual fix" >manual.txt
  git add -A 2>/dev/null
  git commit -q --no-verify -m "fixup! manual: user correction" 2>/dev/null

  echo "$ANCHOR_SHA"
) >"$ANCHOR_FILE5" 2>/dev/null

ANCHOR5=$(cat "$ANCHOR_FILE5")
OUTPUT5=$(bash "$SCRIPT" "$REPO5" "$ANCHOR5" "test-change5" true 2>/dev/null)

assert_json_field "5a: status is ok with confirmation flag" "$OUTPUT5" "status" "ok"

rm -rf "$(dirname "$REPO5")"

# ══════════════════════════════════════════════════════════════════
# 6. Missing arguments → exit 1 with blocked JSON
# ══════════════════════════════════════════════════════════════════
echo "  6. Missing arguments → exit 1"
OUTPUT6=$(bash "$SCRIPT" 2>/dev/null)
EXIT6=$?
assert_exit "6a: exit code 1 for missing args" 1 "$EXIT6"
assert_json_field "6b: status is blocked" "$OUTPUT6" "status" "blocked"
assert_contains "6c: error mentions usage" "$OUTPUT6" "Usage"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1
exit 0

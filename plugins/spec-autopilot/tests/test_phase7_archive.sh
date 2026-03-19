#!/usr/bin/env bash
# test_phase7_archive.sh — Section 49: Phase 7 archive timing integration
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../runtime/scripts" && pwd)"
source "$TEST_DIR/_test_helpers.sh"
source "$TEST_DIR/_fixtures.sh"

echo "--- 49. Phase 7 archive timing integration (git simulation) ---"
setup_autopilot_fixture

TMPDIR_49=$(mktemp -d)
TMPDIR_49_REPO="$TMPDIR_49/repo"
TMPDIR_49_OUT="$TMPDIR_49/results.txt"
mkdir -p "$TMPDIR_49_REPO"

# --- Setup: create a git repo simulating mid-autopilot state ---
# NOTE: results.txt MUST be outside the git repo dir to avoid
# "unstaged changes" error during rebase.
(
  cd "$TMPDIR_49_REPO" || exit 1
  git init -q 2>/dev/null
  git config user.email "test@test.com"
  git config user.name "Test"

  # Initial commit (--no-verify instead of hooksPath=/dev/null to avoid polluting any repo config)
  echo "initial" > README.md
  git add README.md
  git commit -q --no-verify -m "initial commit" 2>/dev/null

  # Anchor commit (simulates Phase 0 step 8)
  git commit -q --allow-empty -m "autopilot: start test-change" 2>/dev/null
  ANCHOR_SHA=$(git rev-parse HEAD)

  # Simulate Phase 5 creating files
  mkdir -p openspec/changes/test-change/context/phase-results
  echo '{"status":"ok","phase":5,"summary":"impl done"}' > openspec/changes/test-change/context/phase-results/phase-5-implementation.json
  echo "1741500000" > openspec/changes/test-change/context/phase-results/phase5-start-time.txt
  echo "main code" > src_file.txt
  git add -A 2>/dev/null
  git commit -q --fixup="$ANCHOR_SHA" -m "fixup! autopilot: start test-change — Phase 5" 2>/dev/null

  # Simulate Phase 7 step 0: write in_progress checkpoint
  echo '{"status":"in_progress","phase":7,"description":"Archive and cleanup"}' > openspec/changes/test-change/context/phase-results/phase-7-summary.json
  git add -A 2>/dev/null
  git commit -q --fixup="$ANCHOR_SHA" -m "fixup! autopilot: start test-change — Phase 7 start" 2>/dev/null

  # --- NEW flow (v3.3.2): cleanup BEFORE git add -A ---

  # Step 4a: Update phase-7-summary.json to "ok"
  echo '{"status":"ok","phase":7,"description":"Archive complete","archived_change":"test-change","mode":"full"}' > openspec/changes/test-change/context/phase-results/phase-7-summary.json

  # Step 4a: Delete phase5-start-time.txt
  rm -f openspec/changes/test-change/context/phase-results/phase5-start-time.txt

  # Step 4b: git add -A → fixup commit (captures all cleanup)
  git add -A 2>/dev/null
  git diff --cached --quiet || git commit -q --fixup="$ANCHOR_SHA" -m "fixup! autopilot: start test-change — final" 2>/dev/null

  # Step 4b: autosquash
  GIT_SEQUENCE_EDITOR=: git rebase -q -i --autosquash "${ANCHOR_SHA}~1" 2>/dev/null

  # Amend commit message
  git commit -q --amend -m "feat(autopilot): test-change — integration test" 2>/dev/null

  # --- Verify final commit state ---

  # Check 1: phase-7-summary.json should have status "ok" in working tree
  P7_STATUS=$(python3 -c "import json; print(json.load(open('openspec/changes/test-change/context/phase-results/phase-7-summary.json'))['status'])")
  echo "P7_STATUS=$P7_STATUS"

  # Check 2: phase5-start-time.txt should NOT exist
  if [ -f openspec/changes/test-change/context/phase-results/phase5-start-time.txt ]; then
    echo "START_TIME_EXISTS=true"
  else
    echo "START_TIME_EXISTS=false"
  fi

  # Check 3: git status should be clean (no uncommitted changes)
  DIRTY=$(git status --porcelain)
  if [ -z "$DIRTY" ]; then
    echo "GIT_CLEAN=true"
  else
    echo "GIT_CLEAN=false"
    echo "DIRTY_FILES=$DIRTY"
  fi

  # Check 4: phase-7-summary.json in the commit should have "ok" status
  COMMITTED_P7=$(git show HEAD:openspec/changes/test-change/context/phase-results/phase-7-summary.json 2>/dev/null)
  COMMITTED_STATUS=$(echo "$COMMITTED_P7" | python3 -c "import json,sys; print(json.load(sys.stdin)['status'])")
  echo "COMMITTED_P7_STATUS=$COMMITTED_STATUS"

  # Check 5: phase5-start-time.txt should NOT be in the commit
  if git show HEAD:openspec/changes/test-change/context/phase-results/phase5-start-time.txt 2>/dev/null 1>/dev/null; then
    echo "COMMITTED_START_TIME=true"
  else
    echo "COMMITTED_START_TIME=false"
  fi

  # Check 6: should be exactly 2 commits (initial + squashed autopilot)
  COMMIT_COUNT=$(git rev-list --count HEAD)
  echo "COMMIT_COUNT=$COMMIT_COUNT"
) > "$TMPDIR_49_OUT" 2>&1

RESULTS_49=$(cat "$TMPDIR_49_OUT")

# 49a: phase-7-summary.json has status "ok" in working tree
assert_contains "49a: phase-7-summary.json status=ok in working tree" "$RESULTS_49" "P7_STATUS=ok"

# 49b: phase5-start-time.txt deleted from working tree
assert_contains "49b: phase5-start-time.txt deleted from working tree" "$RESULTS_49" "START_TIME_EXISTS=false"

# 49c: git working tree is clean (all changes committed)
assert_contains "49c: git working tree clean after squash" "$RESULTS_49" "GIT_CLEAN=true"

# 49d: phase-7-summary.json committed with status "ok" (not "in_progress")
assert_contains "49d: phase-7-summary.json committed with status=ok" "$RESULTS_49" "COMMITTED_P7_STATUS=ok"

# 49e: phase5-start-time.txt NOT in final commit
assert_contains "49e: phase5-start-time.txt not in final commit" "$RESULTS_49" "COMMITTED_START_TIME=false"

# 49f: fixup commits squashed into 2 total (initial + autopilot)
assert_contains "49f: fixup commits squashed (2 total)" "$RESULTS_49" "COMMIT_COUNT=2"

# --- 49g-49i: Simulate OLD (broken) flow to prove it fails ---
TMPDIR_49B=$(mktemp -d)
TMPDIR_49B_REPO="$TMPDIR_49B/repo"
TMPDIR_49B_OUT="$TMPDIR_49B/results.txt"
mkdir -p "$TMPDIR_49B_REPO"
(
  cd "$TMPDIR_49B_REPO"
  git init -q 2>/dev/null
  git config user.email "test@test.com"
  git config user.name "Test"
  git config core.hooksPath /dev/null

  echo "initial" > README.md
  git add README.md
  git commit -q -m "initial commit" 2>/dev/null

  git commit -q --allow-empty -m "autopilot: start test-change" 2>/dev/null
  ANCHOR_SHA=$(git rev-parse HEAD)

  mkdir -p openspec/changes/test-change/context/phase-results
  echo '{"status":"ok","phase":5,"summary":"impl done"}' > openspec/changes/test-change/context/phase-results/phase-5-implementation.json
  echo "1741500000" > openspec/changes/test-change/context/phase-results/phase5-start-time.txt
  echo "main code" > src_file.txt
  git add -A 2>/dev/null
  git commit -q --fixup="$ANCHOR_SHA" -m "fixup! autopilot: start test-change — Phase 5" 2>/dev/null

  echo '{"status":"in_progress","phase":7,"description":"Archive and cleanup"}' > openspec/changes/test-change/context/phase-results/phase-7-summary.json
  git add -A 2>/dev/null
  git commit -q --fixup="$ANCHOR_SHA" -m "fixup! autopilot: start test-change — Phase 7 start" 2>/dev/null

  # --- OLD flow (broken): git add -A FIRST, then cleanup AFTER ---

  # Step 4a (old): git add -A → fixup commit (nothing new to commit)
  git add -A 2>/dev/null
  git diff --cached --quiet || git commit -q --fixup="$ANCHOR_SHA" -m "fixup! autopilot: start test-change — final" 2>/dev/null

  # Step 4a (old): autosquash
  GIT_SEQUENCE_EDITOR=: git rebase -q -i --autosquash "${ANCHOR_SHA}~1" 2>/dev/null
  git commit -q --amend -m "feat(autopilot): test-change — old flow" 2>/dev/null

  # Step 4c (old): Update checkpoint AFTER squash
  echo '{"status":"ok","phase":7,"description":"Archive complete","archived_change":"test-change","mode":"full"}' > openspec/changes/test-change/context/phase-results/phase-7-summary.json

  # Step 7 (old): Delete start-time AFTER squash
  rm -f openspec/changes/test-change/context/phase-results/phase5-start-time.txt

  # --- Verify: these changes are now UNCOMMITTED ---
  DIRTY=$(git status --porcelain)
  if [ -z "$DIRTY" ]; then
    echo "OLD_GIT_CLEAN=true"
  else
    echo "OLD_GIT_CLEAN=false"
  fi

  # phase-7-summary.json in commit still has "in_progress"
  COMMITTED_P7=$(git show HEAD:openspec/changes/test-change/context/phase-results/phase-7-summary.json 2>/dev/null)
  COMMITTED_STATUS=$(echo "$COMMITTED_P7" | python3 -c "import json,sys; print(json.load(sys.stdin)['status'])")
  echo "OLD_COMMITTED_P7_STATUS=$COMMITTED_STATUS"

  # phase5-start-time.txt still in commit
  if git show HEAD:openspec/changes/test-change/context/phase-results/phase5-start-time.txt 2>/dev/null 1>/dev/null; then
    echo "OLD_COMMITTED_START_TIME=true"
  else
    echo "OLD_COMMITTED_START_TIME=false"
  fi
) > "$TMPDIR_49B_OUT" 2>&1

RESULTS_49B=$(cat "$TMPDIR_49B_OUT")

# 49g: OLD flow leaves dirty working tree
assert_contains "49g: OLD flow: git NOT clean (uncommitted changes)" "$RESULTS_49B" "OLD_GIT_CLEAN=false"

# 49h: OLD flow commits phase-7-summary.json with "in_progress" (bug)
assert_contains "49h: OLD flow: committed phase-7 has in_progress (bug)" "$RESULTS_49B" "OLD_COMMITTED_P7_STATUS=in_progress"

# 49i: OLD flow still has phase5-start-time.txt in commit (bug)
assert_contains "49i: OLD flow: start-time.txt still in commit (bug)" "$RESULTS_49B" "OLD_COMMITTED_START_TIME=true"

rm -rf "$TMPDIR_49" "$TMPDIR_49B"

teardown_autopilot_fixture
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1; exit 0

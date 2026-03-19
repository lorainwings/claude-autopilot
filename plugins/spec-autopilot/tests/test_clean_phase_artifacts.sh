#!/usr/bin/env bash
# test_clean_phase_artifacts.sh — Unit tests for clean-phase-artifacts.sh
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../runtime/scripts" && pwd)"
source "$TEST_DIR/_test_helpers.sh"
source "$SCRIPT_DIR/_common.sh"

CLEAN_SCRIPT="$SCRIPT_DIR/clean-phase-artifacts.sh"

echo "--- Clean Phase Artifacts tests ---"

# Helper: create a mock change directory with artifacts
setup_clean_test() {
  local tmpdir
  tmpdir=$(mktemp -d)
  local change_dir="$tmpdir/openspec/changes/test-feature"
  local pr="$change_dir/context/phase-results"
  local cs="$change_dir/context/phase-context-snapshots"
  mkdir -p "$pr" "$cs" "$change_dir/context" "$tmpdir/logs"

  # Create some phase artifacts across phases 1-7
  echo '{"status":"ok"}' > "$pr/phase-1-requirements.json"
  echo '{"status":"ok"}' > "$pr/phase-2-openspec.json"
  echo '{"status":"ok"}' > "$pr/phase-3-ff.json"
  echo '{"status":"ok"}' > "$pr/phase-4-testing.json"
  echo '{"status":"ok"}' > "$pr/phase-5-implement.json"
  echo '{"status":"ok"}' > "$pr/phase-6-report.json"
  echo '{"status":"ok"}' > "$pr/phase-7-summary.json"

  # Context snapshots
  echo "Phase 1 context" > "$cs/phase-1-context.md"
  echo "Phase 2 context" > "$cs/phase-2-context.md"
  echo "Phase 3 context" > "$cs/phase-3-context.md"
  echo "Phase 5 context" > "$cs/phase-5-context.md"

  echo "$tmpdir"
}

# 1. Clean from phase 3 keeps phases 1-2, removes 3-7
echo "  1. Clean from phase 3 in full mode"
TMPDIR=$(setup_clean_test)
CHANGE="$TMPDIR/openspec/changes/test-feature"
PR="$CHANGE/context/phase-results"
CS="$CHANGE/context/phase-context-snapshots"
# Run script directly with change_dir
bash "$CLEAN_SCRIPT" 3 full "$CHANGE" > /dev/null 2>&1
# Phase 1-2 should survive
assert_file_exists "1a. phase-1 survives" "$PR/phase-1-requirements.json"
assert_file_exists "1b. phase-2 survives" "$PR/phase-2-openspec.json"
# Phase 3+ should be gone
if [ ! -f "$PR/phase-3-ff.json" ]; then
  green "  PASS: 1c. phase-3 removed"
  PASS=$((PASS + 1))
else
  red "  FAIL: 1c. phase-3 still exists"
  FAIL=$((FAIL + 1))
fi
if [ ! -f "$PR/phase-5-implement.json" ]; then
  green "  PASS: 1d. phase-5 removed"
  PASS=$((PASS + 1))
else
  red "  FAIL: 1d. phase-5 still exists"
  FAIL=$((FAIL + 1))
fi
rm -rf "$TMPDIR"

# 2. Context snapshots cleaned for >= from_phase
echo "  2. Context snapshots cleaned"
TMPDIR=$(setup_clean_test)
CHANGE="$TMPDIR/openspec/changes/test-feature"
CS="$CHANGE/context/phase-context-snapshots"
bash "$CLEAN_SCRIPT" 3 full "$CHANGE" > /dev/null 2>&1
assert_file_exists "2a. phase-1-context survives" "$CS/phase-1-context.md"
assert_file_exists "2b. phase-2-context survives" "$CS/phase-2-context.md"
if [ ! -f "$CS/phase-3-context.md" ]; then
  green "  PASS: 2c. phase-3-context removed"
  PASS=$((PASS + 1))
else
  red "  FAIL: 2c. phase-3-context still exists"
  FAIL=$((FAIL + 1))
fi
rm -rf "$TMPDIR"

# 3. Phase 5 special: .tdd-stage and phase5-tasks cleanup
echo "  3. Phase 5 special cleanup"
TMPDIR=$(setup_clean_test)
CHANGE="$TMPDIR/openspec/changes/test-feature"
PR="$CHANGE/context/phase-results"
mkdir -p "$PR/phase5-tasks"
echo '{"task":1}' > "$PR/phase5-tasks/task-1.json"
echo '{"task":2}' > "$PR/phase5-tasks/task-2.json"
echo "red" > "$CHANGE/context/.tdd-stage"
bash "$CLEAN_SCRIPT" 5 full "$CHANGE" > /dev/null 2>&1
if [ ! -d "$PR/phase5-tasks" ]; then
  green "  PASS: 3a. phase5-tasks dir removed"
  PASS=$((PASS + 1))
else
  red "  FAIL: 3a. phase5-tasks still exists"
  FAIL=$((FAIL + 1))
fi
if [ ! -f "$CHANGE/context/.tdd-stage" ]; then
  green "  PASS: 3b. .tdd-stage removed"
  PASS=$((PASS + 1))
else
  red "  FAIL: 3b. .tdd-stage still exists"
  FAIL=$((FAIL + 1))
fi
rm -rf "$TMPDIR"

# 4. Phase 6 special: phase-6.5-*.json cleanup
echo "  4. Phase 6 special cleanup (phase-6.5 files)"
TMPDIR=$(setup_clean_test)
CHANGE="$TMPDIR/openspec/changes/test-feature"
PR="$CHANGE/context/phase-results"
echo '{"status":"ok"}' > "$PR/phase-6.5-code-review.json"
echo '{"status":"ok"}' > "$PR/phase-6.5-quality-scan.json"
bash "$CLEAN_SCRIPT" 6 full "$CHANGE" > /dev/null 2>&1
if [ ! -f "$PR/phase-6.5-code-review.json" ]; then
  green "  PASS: 4a. phase-6.5-code-review removed"
  PASS=$((PASS + 1))
else
  red "  FAIL: 4a. phase-6.5-code-review still exists"
  FAIL=$((FAIL + 1))
fi
if [ ! -f "$PR/phase-6.5-quality-scan.json" ]; then
  green "  PASS: 4b. phase-6.5-quality-scan removed"
  PASS=$((PASS + 1))
else
  red "  FAIL: 4b. phase-6.5-quality-scan still exists"
  FAIL=$((FAIL + 1))
fi
rm -rf "$TMPDIR"

# 5. .json.tmp residual cleanup
echo "  5. .json.tmp residual cleanup"
TMPDIR=$(setup_clean_test)
CHANGE="$TMPDIR/openspec/changes/test-feature"
PR="$CHANGE/context/phase-results"
echo "temp" > "$PR/phase-2-openspec.json.tmp"
echo "temp" > "$PR/phase-4-testing.json.tmp"
bash "$CLEAN_SCRIPT" 1 full "$CHANGE" > /dev/null 2>&1
if [ ! -f "$PR/phase-2-openspec.json.tmp" ]; then
  green "  PASS: 5a. tmp residual removed"
  PASS=$((PASS + 1))
else
  red "  FAIL: 5a. tmp residual still exists"
  FAIL=$((FAIL + 1))
fi
rm -rf "$TMPDIR"

# 6. Events filtering (remove events with phase >= from_phase)
echo "  6. Events filtering"
TMPDIR=$(setup_clean_test)
CHANGE="$TMPDIR/openspec/changes/test-feature"
cat > "$TMPDIR/logs/events.jsonl" <<'EOF'
{"type":"phase_start","phase":0,"mode":"full"}
{"type":"phase_end","phase":0,"mode":"full"}
{"type":"phase_start","phase":1,"mode":"full"}
{"type":"phase_end","phase":1,"mode":"full"}
{"type":"phase_start","phase":2,"mode":"full"}
{"type":"phase_end","phase":2,"mode":"full"}
{"type":"phase_start","phase":3,"mode":"full"}
EOF
# Clean from phase 2 — should keep phase 0 and 1 events
bash "$CLEAN_SCRIPT" 2 full "$CHANGE" > /dev/null 2>&1
LINE_COUNT=$(wc -l < "$TMPDIR/logs/events.jsonl" | tr -d ' ')
if [ "$LINE_COUNT" -eq 4 ]; then
  green "  PASS: 6a. events filtered correctly (kept 4 lines for phase 0+1)"
  PASS=$((PASS + 1))
else
  red "  FAIL: 6a. events line count (expected 4, got $LINE_COUNT)"
  FAIL=$((FAIL + 1))
fi
rm -rf "$TMPDIR"

# 7. JSON summary output
echo "  7. JSON summary output"
TMPDIR=$(setup_clean_test)
CHANGE="$TMPDIR/openspec/changes/test-feature"
OUTPUT=$(bash "$CLEAN_SCRIPT" 5 full "$CHANGE" 2>/dev/null)
assert_contains "7a. JSON has status ok" "$OUTPUT" '"status":"ok"'
assert_contains "7b. JSON has from_phase" "$OUTPUT" '"from_phase":5'
assert_contains "7c. JSON has mode" "$OUTPUT" '"mode":"full"'
rm -rf "$TMPDIR"

# 8. Lite mode respects phase sequence (only cleans mode-relevant phases)
echo "  8. Lite mode cleanup"
TMPDIR=$(setup_clean_test)
CHANGE="$TMPDIR/openspec/changes/test-feature"
PR="$CHANGE/context/phase-results"
bash "$CLEAN_SCRIPT" 5 lite "$CHANGE" > /dev/null 2>&1
# Phase 1 should survive (not in cleanup range)
assert_file_exists "8a. phase-1 survives in lite" "$PR/phase-1-requirements.json"
# Phase 5+ should be cleaned
if [ ! -f "$PR/phase-5-implement.json" ]; then
  green "  PASS: 8b. phase-5 removed in lite mode"
  PASS=$((PASS + 1))
else
  red "  FAIL: 8b. phase-5 still exists in lite mode"
  FAIL=$((FAIL + 1))
fi
rm -rf "$TMPDIR"

# 9. Clean from phase 1 removes everything
echo "  9. Clean from phase 1 removes all"
TMPDIR=$(setup_clean_test)
CHANGE="$TMPDIR/openspec/changes/test-feature"
PR="$CHANGE/context/phase-results"
bash "$CLEAN_SCRIPT" 1 full "$CHANGE" > /dev/null 2>&1
REMAINING=$(find "$PR" -name "phase-*.json" 2>/dev/null | wc -l | tr -d ' ')
if [ "$REMAINING" -eq 0 ]; then
  green "  PASS: 9a. all phase files removed"
  PASS=$((PASS + 1))
else
  red "  FAIL: 9a. $REMAINING files remaining"
  FAIL=$((FAIL + 1))
fi
rm -rf "$TMPDIR"

# 10. Interim and progress files cleaned
echo "  10. Interim and progress files cleaned"
TMPDIR=$(setup_clean_test)
CHANGE="$TMPDIR/openspec/changes/test-feature"
PR="$CHANGE/context/phase-results"
echo '{"status":"in_progress","stage":"research_complete"}' > "$PR/phase-1-interim.json"
echo '{"step":"gate_passed"}' > "$PR/phase-3-progress.json"
bash "$CLEAN_SCRIPT" 1 full "$CHANGE" > /dev/null 2>&1
if [ ! -f "$PR/phase-1-interim.json" ]; then
  green "  PASS: 10a. interim file removed"
  PASS=$((PASS + 1))
else
  red "  FAIL: 10a. interim file still exists"
  FAIL=$((FAIL + 1))
fi
if [ ! -f "$PR/phase-3-progress.json" ]; then
  green "  PASS: 10b. progress file removed"
  PASS=$((PASS + 1))
else
  red "  FAIL: 10b. progress file still exists"
  FAIL=$((FAIL + 1))
fi
rm -rf "$TMPDIR"

# 11. Atomic events write — no .tmp residuals after filtering
echo "  11. Atomic events write — no .tmp residuals"
TMPDIR=$(setup_clean_test)
CHANGE="$TMPDIR/openspec/changes/test-feature"
cat > "$TMPDIR/logs/events.jsonl" <<'EOF'
{"type":"phase_start","phase":0,"mode":"full"}
{"type":"phase_start","phase":1,"mode":"full"}
{"type":"phase_start","phase":2,"mode":"full"}
EOF
bash "$CLEAN_SCRIPT" 2 full "$CHANGE" > /dev/null 2>&1
TMP_COUNT=$(find "$TMPDIR/logs" -name "*.tmp" 2>/dev/null | wc -l | tr -d ' ')
if [ "$TMP_COUNT" -eq 0 ]; then
  green "  PASS: 11a. no .tmp residuals after events filtering"
  PASS=$((PASS + 1))
else
  red "  FAIL: 11a. found $TMP_COUNT .tmp files"
  FAIL=$((FAIL + 1))
fi
rm -rf "$TMPDIR"

# 12. --dry-run outputs manifest but does not modify files
echo "  12. --dry-run mode"
TMPDIR=$(setup_clean_test)
CHANGE="$TMPDIR/openspec/changes/test-feature"
PR="$CHANGE/context/phase-results"
OUTPUT=$(bash "$CLEAN_SCRIPT" 3 full "$CHANGE" --dry-run 2>/dev/null)
# Verify dry_run=true in output
assert_contains "12a. dry_run in output" "$OUTPUT" '"dry_run":true'
# Verify files were NOT actually removed
assert_file_exists "12b. phase-3 still exists after dry-run" "$PR/phase-3-ff.json"
assert_file_exists "12c. phase-5 still exists after dry-run" "$PR/phase-5-implement.json"
rm -rf "$TMPDIR"

# 13. JSON output includes rebase_aborted/merge_aborted fields
echo "  13. JSON output includes rebase/merge abort fields"
TMPDIR=$(setup_clean_test)
CHANGE="$TMPDIR/openspec/changes/test-feature"
OUTPUT=$(bash "$CLEAN_SCRIPT" 3 full "$CHANGE" 2>/dev/null)
assert_contains "13a. rebase_aborted field" "$OUTPUT" '"rebase_aborted":'
assert_contains "13b. merge_aborted field" "$OUTPUT" '"merge_aborted":'
rm -rf "$TMPDIR"

# 14. Preserve non-cleanup user changes without restoring cleaned phase artifacts
echo "  14. Preserve user WIP without phase artifact rollback"
TMPDIR=$(mktemp -d)
REPO="$TMPDIR/repo"
CHANGE="$REPO/openspec/changes/test-feature"
PR="$CHANGE/context/phase-results"
mkdir -p "$PR" "$REPO/logs"
ORIG_PWD=$(pwd)
cd "$REPO" || exit 1
git init -q
git config user.email test@example.com
git config user.name test
echo "base" > tracked.txt
git add tracked.txt
git commit -q -m init
echo "user-change" > tracked.txt
echo '{"status":"ok"}' > "$PR/phase-5-implement.json"
OUTPUT=$(bash "$CLEAN_SCRIPT" 5 full "$CHANGE" --git-target-sha HEAD 2>/dev/null)
STATUS=$(printf '%s' "$OUTPUT" | python3 -c "import json,sys; print(json.load(sys.stdin)['status'])" 2>/dev/null)
STASH_RESTORED=$(printf '%s' "$OUTPUT" | python3 -c "import json,sys; print(json.load(sys.stdin)['stash_restored'])" 2>/dev/null)
STASH_REF=$(printf '%s' "$OUTPUT" | python3 -c "import json,sys; print(json.load(sys.stdin)['stash_ref'])" 2>/dev/null)
STASH_COUNT=$(git stash list 2>/dev/null | wc -l | tr -d ' ')
TRACKED_CONTENT=$(cat tracked.txt)
if [ -f "$PR/phase-5-implement.json" ]; then
  PHASE_EXISTS=yes
else
  PHASE_EXISTS=no
fi
cd "$ORIG_PWD" || exit 1

if [ "$STATUS" = "ok" ]; then
  green "  PASS: 14a. script status ok after restore"
  PASS=$((PASS + 1))
else
  red "  FAIL: 14a. script status (got '$STATUS')"
  FAIL=$((FAIL + 1))
fi

if [ "$STASH_RESTORED" = "True" ] || [ "$STASH_RESTORED" = "true" ]; then
  green "  PASS: 14b. preserved stash restored automatically"
  PASS=$((PASS + 1))
else
  red "  FAIL: 14b. stash_restored (got '$STASH_RESTORED')"
  FAIL=$((FAIL + 1))
fi

if [ -z "$STASH_REF" ]; then
  green "  PASS: 14c. no stash_ref left after successful restore"
  PASS=$((PASS + 1))
else
  red "  FAIL: 14c. stash_ref still set (got '$STASH_REF')"
  FAIL=$((FAIL + 1))
fi

if [ "$STASH_COUNT" = "0" ]; then
  green "  PASS: 14d. no stash entries left behind"
  PASS=$((PASS + 1))
else
  red "  FAIL: 14d. stash entries remaining ($STASH_COUNT)"
  FAIL=$((FAIL + 1))
fi

if [ "$TRACKED_CONTENT" = "user-change" ]; then
  green "  PASS: 14e. tracked user change restored"
  PASS=$((PASS + 1))
else
  red "  FAIL: 14e. tracked content (got '$TRACKED_CONTENT')"
  FAIL=$((FAIL + 1))
fi

if [ "$PHASE_EXISTS" = "no" ]; then
  green "  PASS: 14f. cleaned phase artifact not restored"
  PASS=$((PASS + 1))
else
  red "  FAIL: 14f. phase artifact restored unexpectedly"
  FAIL=$((FAIL + 1))
fi
rm -rf "$TMPDIR"

echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1; exit 0

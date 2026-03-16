#!/usr/bin/env bash
# test_recovery_decision.sh — Unit tests for recovery-decision.sh
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../scripts" && pwd)"
source "$TEST_DIR/_test_helpers.sh"

RECOVERY_SCRIPT="$SCRIPT_DIR/recovery-decision.sh"

echo "--- Recovery Decision tests ---"

# Helper: create a mock changes directory with artifacts
setup_recovery_test() {
  local tmpdir
  tmpdir=$(mktemp -d)
  local changes_dir="$tmpdir/openspec/changes"
  mkdir -p "$changes_dir"
  # Initialize as git repo for git_state detection
  (cd "$tmpdir" && git init -q 2>/dev/null) || true
  echo "$tmpdir"
}

# Helper: add a change with checkpoints
add_change_with_checkpoints() {
  local tmpdir="$1"
  local name="$2"
  shift 2
  local pr="$tmpdir/openspec/changes/$name/context/phase-results"
  mkdir -p "$pr"
  # Each remaining arg is "phase:status"
  for spec in "$@"; do
    local phase="${spec%%:*}"
    local status="${spec##*:}"
    local slug
    case "$phase" in
      1) slug="requirements" ;;
      2) slug="openspec" ;;
      3) slug="ff" ;;
      4) slug="testing" ;;
      5) slug="implement" ;;
      6) slug="report" ;;
      7) slug="summary" ;;
      *) slug="unknown" ;;
    esac
    echo "{\"status\":\"$status\"}" > "$pr/phase-${phase}-${slug}.json"
  done
}

# 1. Empty project — no checkpoints
echo "  1. Empty project — no checkpoints"
TMPDIR=$(setup_recovery_test)
OUTPUT=$(bash "$RECOVERY_SCRIPT" "$TMPDIR/openspec/changes" "full" 2>/dev/null)
assert_json_field "1a. status is ok" "$OUTPUT" "status" "ok"
HAS_CK=$(echo "$OUTPUT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('has_checkpoints',True))" 2>/dev/null)
if [ "$HAS_CK" = "False" ]; then
  green "  PASS: 1b. has_checkpoints=false"
  PASS=$((PASS + 1))
else
  red "  FAIL: 1b. has_checkpoints (got $HAS_CK)"
  FAIL=$((FAIL + 1))
fi
rm -rf "$TMPDIR"

# 2. Phase 1+2 ok → last_valid=2, continue.phase=3
echo "  2. Phase 1+2 ok → last_valid=2, continue=3"
TMPDIR=$(setup_recovery_test)
add_change_with_checkpoints "$TMPDIR" "feat-a" "1:ok" "2:ok"
OUTPUT=$(bash "$RECOVERY_SCRIPT" "$TMPDIR/openspec/changes" "full" 2>/dev/null)
LVP=$(echo "$OUTPUT" | python3 -c "import json,sys; d=json.load(sys.stdin); c=[x for x in d['changes'] if x['name']=='feat-a'][0]; print(c['last_valid_phase'])" 2>/dev/null)
if [ "$LVP" = "2" ]; then
  green "  PASS: 2a. last_valid_phase=2"
  PASS=$((PASS + 1))
else
  red "  FAIL: 2a. last_valid_phase (got $LVP)"
  FAIL=$((FAIL + 1))
fi
CONT_PHASE=$(echo "$OUTPUT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['recovery_options']['continue']['phase'])" 2>/dev/null)
if [ "$CONT_PHASE" = "3" ]; then
  green "  PASS: 2b. continue.phase=3"
  PASS=$((PASS + 1))
else
  red "  FAIL: 2b. continue.phase (got $CONT_PHASE)"
  FAIL=$((FAIL + 1))
fi
rm -rf "$TMPDIR"

# 3. Gap detection: P1 ok, P2 ok, P3 missing, P4 ok → has_gaps=true
echo "  3. Gap detection (P3 missing, P4 ok)"
TMPDIR=$(setup_recovery_test)
add_change_with_checkpoints "$TMPDIR" "feat-gap" "1:ok" "2:ok" "4:ok"
OUTPUT=$(bash "$RECOVERY_SCRIPT" "$TMPDIR/openspec/changes" "full" 2>/dev/null)
HAS_GAPS=$(echo "$OUTPUT" | python3 -c "import json,sys; d=json.load(sys.stdin); c=[x for x in d['changes'] if x['name']=='feat-gap'][0]; print(c['has_gaps'])" 2>/dev/null)
if [ "$HAS_GAPS" = "True" ]; then
  green "  PASS: 3a. has_gaps=true"
  PASS=$((PASS + 1))
else
  red "  FAIL: 3a. has_gaps (got $HAS_GAPS)"
  FAIL=$((FAIL + 1))
fi
rm -rf "$TMPDIR"

# 4. Phase 7 ok (fully completed)
echo "  4. Phase 7 ok (fully completed)"
TMPDIR=$(setup_recovery_test)
add_change_with_checkpoints "$TMPDIR" "feat-done" "1:ok" "2:ok" "3:ok" "4:ok" "5:ok" "6:ok" "7:ok"
OUTPUT=$(bash "$RECOVERY_SCRIPT" "$TMPDIR/openspec/changes" "full" 2>/dev/null)
P7_STATUS=$(echo "$OUTPUT" | python3 -c "import json,sys; d=json.load(sys.stdin); c=[x for x in d['changes'] if x['name']=='feat-done'][0]; print(c['phase7_status'])" 2>/dev/null)
if [ "$P7_STATUS" = "ok" ]; then
  green "  PASS: 4a. phase7_status=ok"
  PASS=$((PASS + 1))
else
  red "  FAIL: 4a. phase7_status (got $P7_STATUS)"
  FAIL=$((FAIL + 1))
fi
rm -rf "$TMPDIR"

# 5. Phase 7 in_progress
echo "  5. Phase 7 in_progress"
TMPDIR=$(setup_recovery_test)
add_change_with_checkpoints "$TMPDIR" "feat-archiving" "1:ok" "2:ok" "3:ok" "4:ok" "5:ok" "6:ok" "7:in_progress"
OUTPUT=$(bash "$RECOVERY_SCRIPT" "$TMPDIR/openspec/changes" "full" 2>/dev/null)
P7_STATUS=$(echo "$OUTPUT" | python3 -c "import json,sys; d=json.load(sys.stdin); c=[x for x in d['changes'] if x['name']=='feat-archiving'][0]; print(c['phase7_status'])" 2>/dev/null)
if [ "$P7_STATUS" = "in_progress" ]; then
  green "  PASS: 5a. phase7_status=in_progress"
  PASS=$((PASS + 1))
else
  red "  FAIL: 5a. phase7_status (got $P7_STATUS)"
  FAIL=$((FAIL + 1))
fi
rm -rf "$TMPDIR"

# 6. Phase 1 interim
echo "  6. Phase 1 interim detection"
TMPDIR=$(setup_recovery_test)
mkdir -p "$TMPDIR/openspec/changes/feat-interim/context/phase-results"
echo '{"status":"in_progress","stage":"research_complete"}' > "$TMPDIR/openspec/changes/feat-interim/context/phase-results/phase-1-interim.json"
OUTPUT=$(bash "$RECOVERY_SCRIPT" "$TMPDIR/openspec/changes" "full" 2>/dev/null)
INTERIM_STAGE=$(echo "$OUTPUT" | python3 -c "import json,sys; d=json.load(sys.stdin); c=[x for x in d['changes'] if x['name']=='feat-interim'][0]; print(c['phase1_interim']['stage'])" 2>/dev/null)
if [ "$INTERIM_STAGE" = "research_complete" ]; then
  green "  PASS: 6a. phase1_interim.stage=research_complete"
  PASS=$((PASS + 1))
else
  red "  FAIL: 6a. phase1_interim.stage (got $INTERIM_STAGE)"
  FAIL=$((FAIL + 1))
fi
rm -rf "$TMPDIR"

# 7. Progress files detected
echo "  7. Progress file detection"
TMPDIR=$(setup_recovery_test)
add_change_with_checkpoints "$TMPDIR" "feat-progress" "1:ok"
echo '{"step":"gate_passed","status":"in_progress"}' > "$TMPDIR/openspec/changes/feat-progress/context/phase-results/phase-2-progress.json"
OUTPUT=$(bash "$RECOVERY_SCRIPT" "$TMPDIR/openspec/changes" "full" 2>/dev/null)
PROG_COUNT=$(echo "$OUTPUT" | python3 -c "import json,sys; d=json.load(sys.stdin); c=[x for x in d['changes'] if x['name']=='feat-progress'][0]; print(len(c['progress_files']))" 2>/dev/null)
if [ "$PROG_COUNT" = "1" ]; then
  green "  PASS: 7a. progress_files count=1"
  PASS=$((PASS + 1))
else
  red "  FAIL: 7a. progress_files count (got $PROG_COUNT)"
  FAIL=$((FAIL + 1))
fi
rm -rf "$TMPDIR"

# 8. Lite mode sequence — only scans 1,5,6,7
echo "  8. Lite mode phase sequence"
TMPDIR=$(setup_recovery_test)
add_change_with_checkpoints "$TMPDIR" "feat-lite" "1:ok" "2:ok" "5:ok"
OUTPUT=$(bash "$RECOVERY_SCRIPT" "$TMPDIR/openspec/changes" "lite" 2>/dev/null)
SCAN_COUNT=$(echo "$OUTPUT" | python3 -c "import json,sys; d=json.load(sys.stdin); c=[x for x in d['changes'] if x['name']=='feat-lite'][0]; print(len(c['checkpoint_scan']))" 2>/dev/null)
if [ "$SCAN_COUNT" = "4" ]; then
  green "  PASS: 8a. lite mode scans 4 phases"
  PASS=$((PASS + 1))
else
  red "  FAIL: 8a. lite mode scan count (got $SCAN_COUNT)"
  FAIL=$((FAIL + 1))
fi
rm -rf "$TMPDIR"

# 9. Invalid directory — error path
echo "  9. Invalid directory error path"
OUTPUT=$(bash "$RECOVERY_SCRIPT" "/nonexistent/path" "full" 2>/dev/null)
assert_json_field "9a. status is error" "$OUTPUT" "status" "error"
EXIT_CODE=$?
# Script should always exit 0
bash "$RECOVERY_SCRIPT" "/nonexistent/path" "full" > /dev/null 2>&1
RC=$?
if [ "$RC" -eq 0 ]; then
  green "  PASS: 9b. exit code is 0 even on error"
  PASS=$((PASS + 1))
else
  red "  FAIL: 9b. exit code (got $RC, expected 0)"
  FAIL=$((FAIL + 1))
fi

# 10. --change preselection
echo "  10. --change preselection"
TMPDIR=$(setup_recovery_test)
add_change_with_checkpoints "$TMPDIR" "feat-a" "1:ok"
add_change_with_checkpoints "$TMPDIR" "feat-b" "1:ok" "2:ok"
OUTPUT=$(bash "$RECOVERY_SCRIPT" "$TMPDIR/openspec/changes" "full" --change "feat-b" 2>/dev/null)
SEL=$(echo "$OUTPUT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('selected_change',''))" 2>/dev/null)
if [ "$SEL" = "feat-b" ]; then
  green "  PASS: 10a. selected_change=feat-b"
  PASS=$((PASS + 1))
else
  red "  FAIL: 10a. selected_change (got $SEL)"
  FAIL=$((FAIL + 1))
fi
rm -rf "$TMPDIR"

# 11. Lock file status reading
echo "  11. Lock file status reading"
TMPDIR=$(setup_recovery_test)
echo '{"change":"test","mode":"lite","anchor_sha":"abc123","session_id":"999"}' > "$TMPDIR/openspec/changes/.autopilot-active"
add_change_with_checkpoints "$TMPDIR" "test" "1:ok"
OUTPUT=$(bash "$RECOVERY_SCRIPT" "$TMPDIR/openspec/changes" "full" 2>/dev/null)
LOCK_EXISTS=$(echo "$OUTPUT" | python3 -c "import json,sys; print(json.load(sys.stdin)['lock_file']['exists'])" 2>/dev/null)
LOCK_MODE=$(echo "$OUTPUT" | python3 -c "import json,sys; print(json.load(sys.stdin)['lock_file']['mode'])" 2>/dev/null)
if [ "$LOCK_EXISTS" = "True" ] && [ "$LOCK_MODE" = "lite" ]; then
  green "  PASS: 11a. lock_file fields correct"
  PASS=$((PASS + 1))
else
  red "  FAIL: 11a. lock_file (exists=$LOCK_EXISTS, mode=$LOCK_MODE)"
  FAIL=$((FAIL + 1))
fi
rm -rf "$TMPDIR"

# 12. Non-git directory — git_state fields all false
echo "  12. Non-git directory git_state"
TMPDIR=$(mktemp -d)
mkdir -p "$TMPDIR/openspec/changes/test/context/phase-results"
echo '{"status":"ok"}' > "$TMPDIR/openspec/changes/test/context/phase-results/phase-1-requirements.json"
OUTPUT=$(bash "$RECOVERY_SCRIPT" "$TMPDIR/openspec/changes" "full" 2>/dev/null)
REBASE=$(echo "$OUTPUT" | python3 -c "import json,sys; print(json.load(sys.stdin)['git_state']['rebase_in_progress'])" 2>/dev/null)
MERGE=$(echo "$OUTPUT" | python3 -c "import json,sys; print(json.load(sys.stdin)['git_state']['merge_in_progress'])" 2>/dev/null)
if [ "$REBASE" = "False" ] && [ "$MERGE" = "False" ]; then
  green "  PASS: 12a. git_state all false for non-git dir"
  PASS=$((PASS + 1))
else
  red "  FAIL: 12a. git_state (rebase=$REBASE, merge=$MERGE)"
  FAIL=$((FAIL + 1))
fi
rm -rf "$TMPDIR"

# 13. Fix #1: Gap → continue.phase should be the gap, not skip over it
echo "  13. Gap detection drives continue.phase"
TMPDIR=$(setup_recovery_test)
add_change_with_checkpoints "$TMPDIR" "feat-gap" "1:ok" "2:ok" "4:ok"
OUTPUT=$(bash "$RECOVERY_SCRIPT" "$TMPDIR/openspec/changes" "full" 2>/dev/null)
CONT_PHASE=$(echo "$OUTPUT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['recovery_options']['continue']['phase'])" 2>/dev/null)
if [ "$CONT_PHASE" = "3" ]; then
  green "  PASS: 13a. gap → continue.phase=3 (the gap phase)"
  PASS=$((PASS + 1))
else
  red "  FAIL: 13a. gap → continue.phase (got $CONT_PHASE, expected 3)"
  FAIL=$((FAIL + 1))
fi
rm -rf "$TMPDIR"

# 14. Fix #2: Lockfile mode overrides CLI mode
echo "  14. Lockfile mode overrides CLI mode"
TMPDIR=$(setup_recovery_test)
echo '{"change":"test","mode":"lite","anchor_sha":"","session_id":"999"}' > "$TMPDIR/openspec/changes/.autopilot-active"
add_change_with_checkpoints "$TMPDIR" "test" "1:ok" "5:ok"
# Pass "full" as CLI mode, but lockfile says "lite"
OUTPUT=$(bash "$RECOVERY_SCRIPT" "$TMPDIR/openspec/changes" "full" 2>/dev/null)
EFF_MODE=$(echo "$OUTPUT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('effective_mode',''))" 2>/dev/null)
if [ "$EFF_MODE" = "lite" ]; then
  green "  PASS: 14a. effective_mode=lite (from lockfile, not CLI)"
  PASS=$((PASS + 1))
else
  red "  FAIL: 14a. effective_mode (got '$EFF_MODE', expected 'lite')"
  FAIL=$((FAIL + 1))
fi
rm -rf "$TMPDIR"

# 15. Fix #3: Only interim (no final checkpoint) → has_checkpoints=true
echo "  15. Interim-only → has_checkpoints=true"
TMPDIR=$(setup_recovery_test)
mkdir -p "$TMPDIR/openspec/changes/feat-interim/context/phase-results"
echo '{"status":"in_progress","stage":"research_complete"}' > "$TMPDIR/openspec/changes/feat-interim/context/phase-results/phase-1-interim.json"
OUTPUT=$(bash "$RECOVERY_SCRIPT" "$TMPDIR/openspec/changes" "full" 2>/dev/null)
HAS_CK=$(echo "$OUTPUT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('has_checkpoints',False))" 2>/dev/null)
if [ "$HAS_CK" = "True" ]; then
  green "  PASS: 15a. interim-only → has_checkpoints=True"
  PASS=$((PASS + 1))
else
  red "  FAIL: 15a. interim-only has_checkpoints (got $HAS_CK)"
  FAIL=$((FAIL + 1))
fi
RECOMMENDED=$(echo "$OUTPUT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('recommended_recovery_phase',0))" 2>/dev/null)
if [ "$RECOMMENDED" = "1" ]; then
  green "  PASS: 15b. interim-only → recommended_recovery_phase=1"
  PASS=$((PASS + 1))
else
  red "  FAIL: 15b. interim-only recommended (got $RECOMMENDED)"
  FAIL=$((FAIL + 1))
fi
rm -rf "$TMPDIR"

# 16. Gap: last_valid_phase stops at gap, specify_range excludes gap phases
echo "  16. Gap metadata consistency"
TMPDIR=$(setup_recovery_test)
add_change_with_checkpoints "$TMPDIR" "feat-gap2" "1:ok" "2:ok" "4:ok"
OUTPUT=$(bash "$RECOVERY_SCRIPT" "$TMPDIR/openspec/changes" "full" 2>/dev/null)
LVP=$(echo "$OUTPUT" | python3 -c "import json,sys; d=json.load(sys.stdin); c=[x for x in d['changes'] if x['name']=='feat-gap2'][0]; print(c['last_valid_phase'])" 2>/dev/null)
if [ "$LVP" = "2" ]; then
  green "  PASS: 16a. last_valid_phase=2 (stops at gap, not 4)"
  PASS=$((PASS + 1))
else
  red "  FAIL: 16a. last_valid_phase (got $LVP, expected 2)"
  FAIL=$((FAIL + 1))
fi
SPEC_RANGE=$(echo "$OUTPUT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['recovery_options']['specify_range'])" 2>/dev/null)
if [ "$SPEC_RANGE" = "[1, 2]" ]; then
  green "  PASS: 16b. specify_range=[1, 2] (no gap phases)"
  PASS=$((PASS + 1))
else
  red "  FAIL: 16b. specify_range (got $SPEC_RANGE, expected [1, 2])"
  FAIL=$((FAIL + 1))
fi
rm -rf "$TMPDIR"

# 17. Progress file for non-Phase-1 → recovery uses progress phase
echo "  17. Progress-only at Phase 5 (lite mode)"
TMPDIR=$(setup_recovery_test)
add_change_with_checkpoints "$TMPDIR" "feat-p5" "1:ok"
echo '{"step":"gate_passed","status":"in_progress"}' > "$TMPDIR/openspec/changes/feat-p5/context/phase-results/phase-5-progress.json"
OUTPUT=$(bash "$RECOVERY_SCRIPT" "$TMPDIR/openspec/changes" "lite" 2>/dev/null)
CONT_PHASE=$(echo "$OUTPUT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['recovery_options']['continue']['phase'])" 2>/dev/null)
if [ "$CONT_PHASE" = "5" ]; then
  green "  PASS: 17a. lite mode P1=ok + P5 progress → continue.phase=5"
  PASS=$((PASS + 1))
else
  red "  FAIL: 17a. continue.phase (got $CONT_PHASE, expected 5)"
  FAIL=$((FAIL + 1))
fi
# Check sub_step is attached
SUB_STEP=$(echo "$OUTPUT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['recovery_options']['continue'].get('sub_step','none'))" 2>/dev/null)
if [ "$SUB_STEP" = "gate_passed" ]; then
  green "  PASS: 17b. sub_step=gate_passed attached to continue"
  PASS=$((PASS + 1))
else
  red "  FAIL: 17b. sub_step (got $SUB_STEP, expected gate_passed)"
  FAIL=$((FAIL + 1))
fi
rm -rf "$TMPDIR"

# 18. Progress-only (no checkpoints at all) uses max progress phase
echo "  18. Progress-only (no checkpoints) uses max progress phase"
TMPDIR=$(setup_recovery_test)
mkdir -p "$TMPDIR/openspec/changes/feat-prog-only/context/phase-results"
echo '{"step":"agent_dispatched","status":"in_progress"}' > "$TMPDIR/openspec/changes/feat-prog-only/context/phase-results/phase-5-progress.json"
OUTPUT=$(bash "$RECOVERY_SCRIPT" "$TMPDIR/openspec/changes" "lite" 2>/dev/null)
RECOMMENDED=$(echo "$OUTPUT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('recommended_recovery_phase',0))" 2>/dev/null)
if [ "$RECOMMENDED" = "5" ]; then
  green "  PASS: 18a. progress-only P5 → recommended=5"
  PASS=$((PASS + 1))
else
  red "  FAIL: 18a. recommended (got $RECOMMENDED, expected 5)"
  FAIL=$((FAIL + 1))
fi
rm -rf "$TMPDIR"

echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1; exit 0

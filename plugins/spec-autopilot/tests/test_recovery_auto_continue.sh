#!/usr/bin/env bash
# test_recovery_auto_continue.sh — Tests for auto-continue, fixup detection, and git risk level
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../runtime/scripts" && pwd)"
source "$TEST_DIR/_test_helpers.sh"

RECOVERY_SCRIPT="$SCRIPT_DIR/recovery-decision.sh"

echo "--- Recovery Auto-Continue tests ---"

# Helper: create a mock changes directory with artifacts (reused from test_recovery_decision.sh)
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

# 1. Single candidate, no ambiguity → auto_continue_eligible=true
echo "  1. Single candidate, clear recovery → auto_continue_eligible=true"
TMPDIR=$(setup_recovery_test)
add_change_with_checkpoints "$TMPDIR" "feat-single" "1:ok" "2:ok"
OUTPUT=$(bash "$RECOVERY_SCRIPT" "$TMPDIR/openspec/changes" "full" 2>/dev/null)
AUTO_CONT=$(echo "$OUTPUT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('auto_continue_eligible', False))" 2>/dev/null)
if [ "$AUTO_CONT" = "True" ]; then
  green "  PASS: 1a. auto_continue_eligible=True"
  PASS=$((PASS + 1))
else
  red "  FAIL: 1a. auto_continue_eligible (got $AUTO_CONT)"
  FAIL=$((FAIL + 1))
fi
INTERACT=$(echo "$OUTPUT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('recovery_interaction_required', True))" 2>/dev/null)
if [ "$INTERACT" = "False" ]; then
  green "  PASS: 1b. recovery_interaction_required=False"
  PASS=$((PASS + 1))
else
  red "  FAIL: 1b. recovery_interaction_required (got $INTERACT)"
  FAIL=$((FAIL + 1))
fi
RISK=$(echo "$OUTPUT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('git_risk_level', ''))" 2>/dev/null)
if [ "$RISK" = "none" ]; then
  green "  PASS: 1c. git_risk_level=none"
  PASS=$((PASS + 1))
else
  red "  FAIL: 1c. git_risk_level (got $RISK)"
  FAIL=$((FAIL + 1))
fi
rm -rf "$TMPDIR"

# 2. Has fixup commits → has_fixup_commits=true, git_risk_level=low
echo "  2. Fixup commits detected"
TMPDIR=$(setup_recovery_test)
add_change_with_checkpoints "$TMPDIR" "feat-fixup" "1:ok" "2:ok"
# Create some fixup commits in the test repo
(cd "$TMPDIR" && git commit --allow-empty -m "feat: initial" -q 2>/dev/null) || true
(cd "$TMPDIR" && git commit --allow-empty -m "fixup! feat: initial" -q 2>/dev/null) || true
(cd "$TMPDIR" && git commit --allow-empty -m "fixup! feat: initial" -q 2>/dev/null) || true
OUTPUT=$(bash "$RECOVERY_SCRIPT" "$TMPDIR/openspec/changes" "full" 2>/dev/null)
HAS_FIXUP=$(echo "$OUTPUT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('has_fixup_commits', False))" 2>/dev/null)
if [ "$HAS_FIXUP" = "True" ]; then
  green "  PASS: 2a. has_fixup_commits=True"
  PASS=$((PASS + 1))
else
  red "  FAIL: 2a. has_fixup_commits (got $HAS_FIXUP)"
  FAIL=$((FAIL + 1))
fi
FIXUP_CNT=$(echo "$OUTPUT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('fixup_commit_count', 0))" 2>/dev/null)
if [ "$FIXUP_CNT" = "2" ]; then
  green "  PASS: 2b. fixup_commit_count=2"
  PASS=$((PASS + 1))
else
  red "  FAIL: 2b. fixup_commit_count (got $FIXUP_CNT)"
  FAIL=$((FAIL + 1))
fi
RISK=$(echo "$OUTPUT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('git_risk_level', ''))" 2>/dev/null)
if [ "$RISK" = "low" ]; then
  green "  PASS: 2c. git_risk_level=low (fixup present)"
  PASS=$((PASS + 1))
else
  red "  FAIL: 2c. git_risk_level (got $RISK, expected low)"
  FAIL=$((FAIL + 1))
fi
rm -rf "$TMPDIR"

# 3. Rebase in progress → git_risk_level=high, auto_continue_eligible=false
echo "  3. Rebase conflict → git_risk_level=high"
TMPDIR=$(setup_recovery_test)
add_change_with_checkpoints "$TMPDIR" "feat-rebase" "1:ok" "2:ok"
# Simulate rebase in progress
mkdir -p "$TMPDIR/.git/rebase-merge"
OUTPUT=$(bash "$RECOVERY_SCRIPT" "$TMPDIR/openspec/changes" "full" 2>/dev/null)
RISK=$(echo "$OUTPUT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('git_risk_level', ''))" 2>/dev/null)
if [ "$RISK" = "high" ]; then
  green "  PASS: 3a. git_risk_level=high (rebase in progress)"
  PASS=$((PASS + 1))
else
  red "  FAIL: 3a. git_risk_level (got $RISK, expected high)"
  FAIL=$((FAIL + 1))
fi
AUTO_CONT=$(echo "$OUTPUT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('auto_continue_eligible', True))" 2>/dev/null)
if [ "$AUTO_CONT" = "False" ]; then
  green "  PASS: 3b. auto_continue_eligible=False (high git risk)"
  PASS=$((PASS + 1))
else
  red "  FAIL: 3b. auto_continue_eligible (got $AUTO_CONT, expected False)"
  FAIL=$((FAIL + 1))
fi
INTERACT=$(echo "$OUTPUT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('recovery_interaction_required', False))" 2>/dev/null)
if [ "$INTERACT" = "True" ]; then
  green "  PASS: 3c. recovery_interaction_required=True (high git risk)"
  PASS=$((PASS + 1))
else
  red "  FAIL: 3c. recovery_interaction_required (got $INTERACT)"
  FAIL=$((FAIL + 1))
fi
rm -rf "$TMPDIR"

# 4. Merge in progress → git_risk_level=high
echo "  4. Merge conflict → git_risk_level=high"
TMPDIR=$(setup_recovery_test)
add_change_with_checkpoints "$TMPDIR" "feat-merge" "1:ok"
# Simulate merge in progress
(cd "$TMPDIR" && git commit --allow-empty -m "initial" -q 2>/dev/null) || true
touch "$TMPDIR/.git/MERGE_HEAD"
OUTPUT=$(bash "$RECOVERY_SCRIPT" "$TMPDIR/openspec/changes" "full" 2>/dev/null)
RISK=$(echo "$OUTPUT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('git_risk_level', ''))" 2>/dev/null)
if [ "$RISK" = "high" ]; then
  green "  PASS: 4a. git_risk_level=high (merge in progress)"
  PASS=$((PASS + 1))
else
  red "  FAIL: 4a. git_risk_level (got $RISK, expected high)"
  FAIL=$((FAIL + 1))
fi
rm -rf "$TMPDIR"

# 5. Multiple candidates (no --change) → auto_continue_eligible=false
echo "  5. Multiple candidates → auto_continue_eligible=false"
TMPDIR=$(setup_recovery_test)
add_change_with_checkpoints "$TMPDIR" "feat-a" "1:ok" "2:ok"
add_change_with_checkpoints "$TMPDIR" "feat-b" "1:ok" "3:ok"
OUTPUT=$(bash "$RECOVERY_SCRIPT" "$TMPDIR/openspec/changes" "full" 2>/dev/null)
AUTO_CONT=$(echo "$OUTPUT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('auto_continue_eligible', True))" 2>/dev/null)
if [ "$AUTO_CONT" = "False" ]; then
  green "  PASS: 5a. auto_continue_eligible=False (multiple candidates)"
  PASS=$((PASS + 1))
else
  red "  FAIL: 5a. auto_continue_eligible (got $AUTO_CONT, expected False)"
  FAIL=$((FAIL + 1))
fi
INTERACT=$(echo "$OUTPUT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('recovery_interaction_required', False))" 2>/dev/null)
if [ "$INTERACT" = "True" ]; then
  green "  PASS: 5b. recovery_interaction_required=True (multiple candidates)"
  PASS=$((PASS + 1))
else
  red "  FAIL: 5b. recovery_interaction_required (got $INTERACT)"
  FAIL=$((FAIL + 1))
fi
rm -rf "$TMPDIR"

# 6. No fixup commits → has_fixup_commits=false, fixup_commit_count=0
echo "  6. No fixup commits → clean state"
TMPDIR=$(setup_recovery_test)
add_change_with_checkpoints "$TMPDIR" "feat-clean" "1:ok"
(cd "$TMPDIR" && git commit --allow-empty -m "feat: normal commit" -q 2>/dev/null) || true
OUTPUT=$(bash "$RECOVERY_SCRIPT" "$TMPDIR/openspec/changes" "full" 2>/dev/null)
HAS_FIXUP=$(echo "$OUTPUT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('has_fixup_commits', True))" 2>/dev/null)
if [ "$HAS_FIXUP" = "False" ]; then
  green "  PASS: 6a. has_fixup_commits=False"
  PASS=$((PASS + 1))
else
  red "  FAIL: 6a. has_fixup_commits (got $HAS_FIXUP)"
  FAIL=$((FAIL + 1))
fi
FIXUP_CNT=$(echo "$OUTPUT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('fixup_commit_count', -1))" 2>/dev/null)
if [ "$FIXUP_CNT" = "0" ]; then
  green "  PASS: 6b. fixup_commit_count=0"
  PASS=$((PASS + 1))
else
  red "  FAIL: 6b. fixup_commit_count (got $FIXUP_CNT)"
  FAIL=$((FAIL + 1))
fi
rm -rf "$TMPDIR"

# 7. Config override: auto_continue disabled → auto_continue_eligible=false
echo "  7. Config disables auto_continue"
TMPDIR=$(setup_recovery_test)
add_change_with_checkpoints "$TMPDIR" "feat-cfg" "1:ok" "2:ok"
OUTPUT=$(AUTOPILOT_RECOVERY_AUTO_CONTINUE_SINGLE_CANDIDATE=false bash "$RECOVERY_SCRIPT" "$TMPDIR/openspec/changes" "full" 2>/dev/null)
AUTO_CONT=$(echo "$OUTPUT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('auto_continue_eligible', True))" 2>/dev/null)
if [ "$AUTO_CONT" = "False" ]; then
  green "  PASS: 7a. auto_continue_eligible=False (config disabled)"
  PASS=$((PASS + 1))
else
  red "  FAIL: 7a. auto_continue_eligible (got $AUTO_CONT, expected False)"
  FAIL=$((FAIL + 1))
fi
rm -rf "$TMPDIR"

# 8. Empty project → new fields have sensible defaults
echo "  8. Empty project defaults for new fields"
TMPDIR=$(setup_recovery_test)
OUTPUT=$(bash "$RECOVERY_SCRIPT" "$TMPDIR/openspec/changes" "full" 2>/dev/null)
HAS_FIXUP=$(echo "$OUTPUT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('has_fixup_commits', True))" 2>/dev/null)
RISK=$(echo "$OUTPUT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('git_risk_level', 'unknown'))" 2>/dev/null)
if [ "$HAS_FIXUP" = "False" ] && [ "$RISK" = "none" ]; then
  green "  PASS: 8a. empty project defaults (no fixup, risk=none)"
  PASS=$((PASS + 1))
else
  red "  FAIL: 8a. empty project defaults (fixup=$HAS_FIXUP, risk=$RISK)"
  FAIL=$((FAIL + 1))
fi
rm -rf "$TMPDIR"

echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1; exit 0

#!/usr/bin/env bash
# test_guard_ask_user_phase.sh — Tests for AskUserQuestion phase guard
# Verifies that AskUserQuestion is blocked during Phase 2-6 of autopilot
# unless explicitly allowed via gates.user_confirmation.after_phase_{N}.
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$TEST_DIR/.." && pwd)"
source "$TEST_DIR/_test_helpers.sh"

GUARD_SCRIPT="$PLUGIN_ROOT/runtime/scripts/guard-ask-user-phase.sh"

echo "--- guard-ask-user-phase.sh: phase gate tests ---"

# ============================================
# Setup: create a temp project with autopilot structure
# ============================================
TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT

setup_project() {
  local project_dir="$1"
  local phase="${2:-}"
  local user_confirmation_phase="${3:-}"
  local user_confirmation_value="${4:-}"

  rm -rf "$project_dir"
  mkdir -p "$project_dir/.claude"
  mkdir -p "$project_dir/openspec/changes/test-change/context/phase-results"
  mkdir -p "$project_dir/plugins/spec-autopilot/hooks"
  echo '{}' >"$project_dir/plugins/spec-autopilot/hooks/hooks.json"

  # Init git repo
  git -C "$project_dir" init -q 2>/dev/null
  git -C "$project_dir" -c user.name="Test" -c user.email="test@test.com" commit -q --allow-empty -m "init" 2>/dev/null

  # Create config
  if [ -n "$user_confirmation_phase" ] && [ -n "$user_confirmation_value" ]; then
    cat >"$project_dir/.claude/autopilot.config.yaml" <<YAML
gates:
  user_confirmation:
    after_phase_${user_confirmation_phase}: ${user_confirmation_value}
YAML
  else
    cat >"$project_dir/.claude/autopilot.config.yaml" <<YAML
gates:
  user_confirmation: {}
YAML
  fi

  # Create progress file for the given phase (if specified)
  if [ -n "$phase" ]; then
    cat >"$project_dir/openspec/changes/test-change/context/phase-results/phase-${phase}-progress.json" <<JSON
{
  "phase": ${phase},
  "step": "gate_check",
  "status": "in_progress",
  "timestamp": "2026-01-01T00:00:00Z"
}
JSON
  fi
}

# Helper: run the guard with stdin JSON pointing at the project
run_guard() {
  local project_dir="$1"
  echo "{\"tool_name\":\"AskUserQuestion\",\"tool_input\":{\"questions\":[]},\"cwd\":\"${project_dir}\"}" | bash "$GUARD_SCRIPT" 2>/dev/null
}

# ============================================
# Test 1: No active autopilot (no lockfile) → exit 0 (allow)
# ============================================
echo ""
echo "--- Test 1: No active autopilot ---"

PROJECT_1="$TMP_ROOT/project-no-autopilot"
setup_project "$PROJECT_1" "3"
# Do NOT create the lockfile
rm -f "$PROJECT_1/openspec/changes/.autopilot-active"

output=$(run_guard "$PROJECT_1")
[ -z "$output" ]
assert_exit "1. no lockfile → allow (empty output)" 0 $?

# ============================================
# Test 2: Phase 3 active, no user_confirmation configured → deny
# ============================================
echo ""
echo "--- Test 2: Phase 3 active, no config → deny ---"

PROJECT_2="$TMP_ROOT/project-phase3-deny"
setup_project "$PROJECT_2" "3"
# Create the lockfile (activates autopilot)
echo '{"change":"test-change","current_phase":3}' >"$PROJECT_2/openspec/changes/.autopilot-active"

output=$(run_guard "$PROJECT_2")
grep -q '"deny"' <<<"$output"
assert_exit "2a. phase 3 → deny decision present" 0 $?

grep -q 'Phase 3' <<<"$output"
assert_exit "2b. phase 3 → reason mentions Phase 3" 0 $?

grep -q 'guard-ask-user-phase' <<<"$output"
assert_exit "2c. phase 3 → reason mentions guard name" 0 $?

# ============================================
# Test 3: Phase 1 active → exit 0 (allow)
# ============================================
echo ""
echo "--- Test 3: Phase 1 active → allow ---"

PROJECT_3="$TMP_ROOT/project-phase1-allow"
setup_project "$PROJECT_3" "1"
echo '{"change":"test-change","current_phase":1}' >"$PROJECT_3/openspec/changes/.autopilot-active"

output=$(run_guard "$PROJECT_3")
[ -z "$output" ]
assert_exit "3. phase 1 → allow (empty output)" 0 $?

# ============================================
# Test 4: Phase 7 active → exit 0 (allow)
# ============================================
echo ""
echo "--- Test 4: Phase 7 active → allow ---"

PROJECT_4="$TMP_ROOT/project-phase7-allow"
setup_project "$PROJECT_4" "7"
echo '{"change":"test-change","current_phase":7}' >"$PROJECT_4/openspec/changes/.autopilot-active"

output=$(run_guard "$PROJECT_4")
[ -z "$output" ]
assert_exit "4. phase 7 → allow (empty output)" 0 $?

# ============================================
# Test 5: Phase 4 active, user_confirmation.after_phase_4: true → allow
# ============================================
echo ""
echo "--- Test 5: Phase 4 active, user_confirmation enabled → allow ---"

PROJECT_5="$TMP_ROOT/project-phase4-configured"
setup_project "$PROJECT_5" "4" "4" "true"
echo '{"change":"test-change","current_phase":4}' >"$PROJECT_5/openspec/changes/.autopilot-active"

output=$(run_guard "$PROJECT_5")
[ -z "$output" ]
assert_exit "5. phase 4 + config true → allow (empty output)" 0 $?

# ============================================
# Summary
# ============================================
echo ""
echo "--- Test 6: stale progress from another change must not override active change ---"

PROJECT_6="$TMP_ROOT/project-stale-progress"
setup_project "$PROJECT_6" "1"
mkdir -p "$PROJECT_6/openspec/changes/old-change/context/phase-results"
cat >"$PROJECT_6/openspec/changes/old-change/context/phase-results/phase-6-progress.json" <<JSON
{
  "phase": 6,
  "step": "agent_dispatched",
  "status": "in_progress",
  "timestamp": "2026-01-01T00:00:00Z"
}
JSON
echo '{"change":"test-change","current_phase":1}' >"$PROJECT_6/openspec/changes/.autopilot-active"

output=$(run_guard "$PROJECT_6")
[ -z "$output" ]
assert_exit "6. stale progress in another change does not block Phase 1" 0 $?

# ============================================
# Test 7: Phase 5 active → allow (exception recovery paths need AskUserQuestion)
# ============================================
echo ""
echo "--- Test 7: Phase 5 active → allow (exception recovery) ---"

PROJECT_7="$TMP_ROOT/project-phase5-allow"
setup_project "$PROJECT_7" "5"
echo '{"change":"test-change","current_phase":5}' >"$PROJECT_7/openspec/changes/.autopilot-active"

output=$(run_guard "$PROJECT_7")
[ -z "$output" ]
assert_exit "7. phase 5 → allow (merge conflict/worktree failure recovery)" 0 $?

echo ""
echo "=== guard-ask-user-phase: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] || exit 1

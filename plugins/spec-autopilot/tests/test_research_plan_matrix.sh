#!/usr/bin/env bash
# test_research_plan_matrix.sh — Verify select-research-plan.sh implements
# the maturity × project_type research plan matrix (Phase 1 redesign Task 18).
#
# Matrix:
#   clear     + greenfield  → scan only            (no ResearchAgent)
#   clear     + brownfield  → scan + lite-regression subtask (no ResearchAgent)
#   partial   + any         → scan + research (depth=standard)
#   ambiguous + any         → scan + research (depth=deep, websearch_subtask=true)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/_test_helpers.sh"

PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPT="$PLUGIN_ROOT/runtime/scripts/select-research-plan.sh"
DIST_INCLUDE="$PLUGIN_ROOT/runtime/scripts/.dist-include"
PHASE1_DOC="$PLUGIN_ROOT/skills/autopilot-phase1-requirements/references/phase1-requirements.md"

echo "=== select-research-plan.sh matrix tests ==="

# --- (1) script exists and is executable ---
assert_file_exists "select-research-plan.sh present" "$SCRIPT"
if [ -x "$SCRIPT" ]; then
  green "  PASS: script is executable"
  PASS=$((PASS + 1))
else
  red "  FAIL: script is not executable"
  FAIL=$((FAIL + 1))
fi

# --- (2) registered in .dist-include ---
assert_file_contains "registered in .dist-include" "$DIST_INCLUDE" "select-research-plan.sh"

# helper: run script and capture json
run_plan() {
  "$SCRIPT" --maturity "$1" --project-type "$2"
}

# --- (3) clear + greenfield ---
OUT=$(run_plan clear greenfield)
RC=$?
assert_exit "clear+greenfield exit 0" 0 "$RC"
assert_json_field "clear+greenfield scan=true" "$OUT" "scan" "True"
assert_json_field "clear+greenfield research=false" "$OUT" "research" "False"
assert_json_field "clear+greenfield depth=none" "$OUT" "research_depth" "none"
assert_json_field "clear+greenfield websearch=false" "$OUT" "websearch_subtask" "False"

# --- (4) clear + brownfield (lite-regression subtask, still no ResearchAgent) ---
OUT=$(run_plan clear brownfield)
RC=$?
assert_exit "clear+brownfield exit 0" 0 "$RC"
assert_json_field "clear+brownfield scan=true" "$OUT" "scan" "True"
assert_json_field "clear+brownfield research=false" "$OUT" "research" "False"
assert_json_field "clear+brownfield depth=none" "$OUT" "research_depth" "none"
assert_json_field "clear+brownfield websearch=false" "$OUT" "websearch_subtask" "False"
assert_contains "clear+brownfield notes mention lite-regression" "$OUT" "lite-regression"

# --- (5) partial + greenfield → standard two-way ---
OUT=$(run_plan partial greenfield)
assert_json_field "partial+greenfield scan=true" "$OUT" "scan" "True"
assert_json_field "partial+greenfield research=true" "$OUT" "research" "True"
assert_json_field "partial+greenfield depth=standard" "$OUT" "research_depth" "standard"
assert_json_field "partial+greenfield websearch=false" "$OUT" "websearch_subtask" "False"

# --- (6) partial + brownfield → standard two-way ---
OUT=$(run_plan partial brownfield)
assert_json_field "partial+brownfield scan=true" "$OUT" "scan" "True"
assert_json_field "partial+brownfield research=true" "$OUT" "research" "True"
assert_json_field "partial+brownfield depth=standard" "$OUT" "research_depth" "standard"
assert_json_field "partial+brownfield websearch=false" "$OUT" "websearch_subtask" "False"

# --- (7) ambiguous + greenfield → deep two-way + websearch ---
OUT=$(run_plan ambiguous greenfield)
assert_json_field "ambiguous+greenfield scan=true" "$OUT" "scan" "True"
assert_json_field "ambiguous+greenfield research=true" "$OUT" "research" "True"
assert_json_field "ambiguous+greenfield depth=deep" "$OUT" "research_depth" "deep"
assert_json_field "ambiguous+greenfield websearch=true" "$OUT" "websearch_subtask" "True"

# --- (8) ambiguous + brownfield → deep two-way + websearch ---
OUT=$(run_plan ambiguous brownfield)
assert_json_field "ambiguous+brownfield scan=true" "$OUT" "scan" "True"
assert_json_field "ambiguous+brownfield research=true" "$OUT" "research" "True"
assert_json_field "ambiguous+brownfield depth=deep" "$OUT" "research_depth" "deep"
assert_json_field "ambiguous+brownfield websearch=true" "$OUT" "websearch_subtask" "True"

# --- (9) invalid maturity → exit 2 ---
"$SCRIPT" --maturity bogus --project-type greenfield >/dev/null 2>&1
assert_exit "invalid maturity exit 2" 2 "$?"

# --- (10) invalid project_type → exit 2 ---
"$SCRIPT" --maturity clear --project-type unknown >/dev/null 2>&1
assert_exit "invalid project_type exit 2" 2 "$?"

# --- (11) missing args → exit 2 ---
"$SCRIPT" >/dev/null 2>&1
assert_exit "no args exit 2" 2 "$?"
"$SCRIPT" --maturity clear >/dev/null 2>&1
assert_exit "missing project-type exit 2" 2 "$?"

# --- (12) output is valid JSON (python-parseable) ---
OUT=$(run_plan ambiguous brownfield)
if python3 -c "import json,sys;json.loads(sys.stdin.read())" <<< "$OUT" >/dev/null 2>&1; then
  green "  PASS: output is valid JSON"
  PASS=$((PASS + 1))
else
  red "  FAIL: output is not valid JSON"
  FAIL=$((FAIL + 1))
fi

# --- (13) phase1 doc references the script (no longer hard-coded mapping) ---
assert_file_contains "phase1-requirements references select-research-plan.sh" \
  "$PHASE1_DOC" "select-research-plan.sh"
assert_file_contains "phase1-requirements documents project_type axis" \
  "$PHASE1_DOC" "project_type"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1
exit 0

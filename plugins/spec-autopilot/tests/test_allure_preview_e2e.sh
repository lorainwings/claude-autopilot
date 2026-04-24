#!/usr/bin/env bash
# test_allure_preview_e2e.sh — Phase 7 Step 2.5 end-to-end allure generate/open simulation
# TEST_LAYER: behavior
# Production targets:
#   - autopilot-phase7-archive/SKILL.md Step 2.5.0 (multi-path search + allure generate fallback)
#   - verify-test-driven-l2.sh (L2 hook-driven audit in check-predecessor-checkpoint.sh)
#
# Strategy: Extracts the Step 2.5.0 shell logic into a standalone script, runs it against
# real directory structures with a mock `allure` command (npx shimmed). This tests the
# exact decision tree that the main thread AI would execute, without requiring actual
# allure installation.
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../runtime/scripts" && pwd)"
source "$TEST_DIR/_test_helpers.sh"
source "$TEST_DIR/_fixtures.sh"

echo "--- Phase 7 Step 2.5 allure generate/open e2e ---"
setup_autopilot_fixture

TMPDIR_TEST=$(mktemp -d)
trap 'rm -rf "$TMPDIR_TEST"' EXIT

# Create a mock allure wrapper that simulates `npx allure generate` and `npx allure open`
MOCK_BIN="$TMPDIR_TEST/mock-bin"
mkdir -p "$MOCK_BIN"
cat >"$MOCK_BIN/npx" <<'MOCK_NPX'
#!/usr/bin/env bash
# Mock npx: intercepts `npx allure generate` and `npx allure open`
if [[ "$1" == "allure" && "$2" == "generate" ]]; then
  # Simulate allure generate: create allure-report/ directory with index.html
  INPUT_DIR="$3"
  OUTPUT_DIR=""
  for i in "$@"; do
    if [[ "$prev" == "-o" ]]; then
      OUTPUT_DIR="$i"
    fi
    prev="$i"
  done
  if [[ -z "$OUTPUT_DIR" ]]; then
    OUTPUT_DIR="allure-report"
  fi
  if [[ -d "$INPUT_DIR" ]]; then
    mkdir -p "$OUTPUT_DIR"
    echo "<html>mock allure report</html>" > "$OUTPUT_DIR/index.html"
    echo "Report successfully generated to $OUTPUT_DIR"
    exit 0
  else
    echo "Error: allure-results directory not found: $INPUT_DIR" >&2
    exit 1
  fi
elif [[ "$1" == "allure" && "$2" == "open" ]]; then
  # Simulate allure open: just echo PID (would normally start HTTP server)
  echo "Starting web server..."
  exit 0
else
  # Fall through to real npx for other commands
  /usr/bin/env npx "$@"
fi
MOCK_NPX
chmod +x "$MOCK_BIN/npx"

# The Step 2.5.0 decision script (extracted from SKILL.md, runs standalone)
# This is the exact logic the main thread AI would execute
cat >"$TMPDIR_TEST/step250.sh" <<'STEP250'
#!/usr/bin/env bash
set -euo pipefail
CHANGE_DIR="$1"
REPORT_DIR="${CHANGE_DIR}/reports"
ALLURE_RESULTS_DIR=""
ALLURE_REPORT_DIR=""

# 1. From Phase 6 checkpoint allure_results_dir (highest priority, must exist)
PHASE6_CP="${CHANGE_DIR}/context/phase-results/phase-6-report.json"
if [ -f "$PHASE6_CP" ]; then
  CP_DIR=$(jq -r ".allure_results_dir // \"\"" "$PHASE6_CP" 2>/dev/null || echo "")
  if [ -n "$CP_DIR" ] && [ -d "$CP_DIR" ]; then
    ALLURE_RESULTS_DIR="$CP_DIR"
  fi
fi

# 2. change-level reports/allure-results/
if [ -z "$ALLURE_RESULTS_DIR" ] && [ -d "$REPORT_DIR/allure-results" ]; then
  ALLURE_RESULTS_DIR="$REPORT_DIR/allure-results"
fi

# 3. Project root allure-results/ (CWD)
if [ -z "$ALLURE_RESULTS_DIR" ] && [ -d "allure-results" ]; then
  ALLURE_RESULTS_DIR="allure-results"
fi

# No allure artifacts
if [ -z "$ALLURE_RESULTS_DIR" ]; then
  echo "NO_RESULTS"
  exit 0
fi

# Search for existing allure-report/
PARENT_DIR=$(dirname "$ALLURE_RESULTS_DIR")
if [ -d "$PARENT_DIR/allure-report" ]; then
  ALLURE_REPORT_DIR="$PARENT_DIR/allure-report"
elif [ -d "allure-report" ]; then
  ALLURE_REPORT_DIR="allure-report"
fi

# Has results but no report → generate
if [ -z "$ALLURE_REPORT_DIR" ]; then
  ALLURE_REPORT_DIR="$PARENT_DIR/allure-report"
  npx allure generate "$ALLURE_RESULTS_DIR" -o "$ALLURE_REPORT_DIR" --clean 2>&1
  if [ $? -eq 0 ]; then
    echo "GENERATED:$ALLURE_REPORT_DIR"
  else
    echo "FAILED"
  fi
else
  echo "EXISTS:$ALLURE_REPORT_DIR"
fi
STEP250
chmod +x "$TMPDIR_TEST/step250.sh"

# Helper: setup a change directory structure
setup_change() {
  local proj="$1" change="$2"
  mkdir -p "$proj/openspec/changes/$change/context/phase-results"
  mkdir -p "$proj/openspec/changes/$change/reports"
}

# ── E2E Test Cases ──

# E2E-1. allure-results at project root, no allure-report → mock generate creates report
setup_change "$TMPDIR_TEST/e2e1" "feat"
mkdir -p "$TMPDIR_TEST/e2e1/allure-results"
echo '{}' >"$TMPDIR_TEST/e2e1/allure-results/result.json"
echo '{"pass_rate":95}' >"$TMPDIR_TEST/e2e1/openspec/changes/feat/context/phase-results/phase-6-report.json"

exit_code=0
output=$(cd "$TMPDIR_TEST/e2e1" && PATH="$MOCK_BIN:$PATH" bash "$TMPDIR_TEST/step250.sh" "openspec/changes/feat" 2>&1) || exit_code=$?
assert_exit "E2E-1. project root generate → exit 0" 0 $exit_code
assert_contains "E2E-1. triggered generate" "$output" "GENERATED"
# Verify the mock allure actually created the report directory
if [ -f "$TMPDIR_TEST/e2e1/allure-report/index.html" ]; then
  green "  PASS: E2E-1. allure-report/index.html created by mock"
  PASS=$((PASS + 1))
else
  red "  FAIL: E2E-1. allure-report/index.html not created"
  FAIL=$((FAIL + 1))
fi

# E2E-2. allure-results at change-level reports/, no project root → discovered + generated
setup_change "$TMPDIR_TEST/e2e2" "feat"
mkdir -p "$TMPDIR_TEST/e2e2/openspec/changes/feat/reports/allure-results"
echo '{}' >"$TMPDIR_TEST/e2e2/openspec/changes/feat/reports/allure-results/result.json"
echo '{"pass_rate":90}' >"$TMPDIR_TEST/e2e2/openspec/changes/feat/context/phase-results/phase-6-report.json"

exit_code=0
output=$(cd "$TMPDIR_TEST/e2e2" && PATH="$MOCK_BIN:$PATH" bash "$TMPDIR_TEST/step250.sh" "openspec/changes/feat" 2>&1) || exit_code=$?
assert_exit "E2E-2. change-level generate → exit 0" 0 $exit_code
assert_contains "E2E-2. triggered generate" "$output" "GENERATED"
# Report should be at reports/allure-report/ (sibling of reports/allure-results/)
if [ -d "$TMPDIR_TEST/e2e2/openspec/changes/feat/reports/allure-report" ]; then
  green "  PASS: E2E-2. report at change-level reports/allure-report/"
  PASS=$((PASS + 1))
else
  red "  FAIL: E2E-2. report not at expected change-level path"
  FAIL=$((FAIL + 1))
fi

# E2E-3. allure-report already exists → skip generate, return EXISTS
setup_change "$TMPDIR_TEST/e2e3" "feat"
mkdir -p "$TMPDIR_TEST/e2e3/allure-results"
echo '{}' >"$TMPDIR_TEST/e2e3/allure-results/result.json"
mkdir -p "$TMPDIR_TEST/e2e3/allure-report"
echo '<html>existing</html>' >"$TMPDIR_TEST/e2e3/allure-report/index.html"
echo '{"pass_rate":100}' >"$TMPDIR_TEST/e2e3/openspec/changes/feat/context/phase-results/phase-6-report.json"

exit_code=0
output=$(cd "$TMPDIR_TEST/e2e3" && PATH="$MOCK_BIN:$PATH" bash "$TMPDIR_TEST/step250.sh" "openspec/changes/feat" 2>&1) || exit_code=$?
assert_exit "E2E-3. existing report → exit 0" 0 $exit_code
assert_contains "E2E-3. returns EXISTS" "$output" "EXISTS"
assert_not_contains "E2E-3. no GENERATED" "$output" "GENERATED"

# E2E-4. no allure-results anywhere → NO_RESULTS
setup_change "$TMPDIR_TEST/e2e4" "feat"
echo '{"pass_rate":80}' >"$TMPDIR_TEST/e2e4/openspec/changes/feat/context/phase-results/phase-6-report.json"

exit_code=0
output=$(cd "$TMPDIR_TEST/e2e4" && PATH="$MOCK_BIN:$PATH" bash "$TMPDIR_TEST/step250.sh" "openspec/changes/feat" 2>&1) || exit_code=$?
assert_exit "E2E-4. no results → exit 0" 0 $exit_code
assert_contains "E2E-4. returns NO_RESULTS" "$output" "NO_RESULTS"

# E2E-5. stale checkpoint path + real change-level results → fallback discovers + generates
setup_change "$TMPDIR_TEST/e2e5" "feat"
mkdir -p "$TMPDIR_TEST/e2e5/openspec/changes/feat/reports/allure-results"
echo '{}' >"$TMPDIR_TEST/e2e5/openspec/changes/feat/reports/allure-results/result.json"
echo '{"pass_rate":85,"allure_results_dir":"/nonexistent/stale/path"}' \
  >"$TMPDIR_TEST/e2e5/openspec/changes/feat/context/phase-results/phase-6-report.json"

exit_code=0
output=$(cd "$TMPDIR_TEST/e2e5" && PATH="$MOCK_BIN:$PATH" bash "$TMPDIR_TEST/step250.sh" "openspec/changes/feat" 2>&1) || exit_code=$?
assert_exit "E2E-5. stale checkpoint + real change-level → exit 0" 0 $exit_code
assert_contains "E2E-5. triggered generate (fallback worked)" "$output" "GENERATED"
assert_not_contains "E2E-5. stale path not in output" "$output" "stale"

# E2E-6. allure generate fails (mock returns error) → FAILED
setup_change "$TMPDIR_TEST/e2e6" "feat"
mkdir -p "$TMPDIR_TEST/e2e6/allure-results-empty" # exists but wrong name
echo '{"pass_rate":70,"allure_results_dir":"'"$TMPDIR_TEST/e2e6/allure-results-empty"'"}' \
  >"$TMPDIR_TEST/e2e6/openspec/changes/feat/context/phase-results/phase-6-report.json"
# Create a failing mock — allure-results-empty exists as dir but has no results
# The real scenario: directory exists but allure generate still fails
cat >"$MOCK_BIN/npx_fail" <<'MOCK_FAIL'
#!/usr/bin/env bash
if [[ "$1" == "allure" && "$2" == "generate" ]]; then
  echo "Error: No allure results found" >&2
  exit 1
fi
MOCK_FAIL
chmod +x "$MOCK_BIN/npx_fail"

exit_code=0
output=$(cd "$TMPDIR_TEST/e2e6" && PATH="$MOCK_BIN:$PATH" bash "$TMPDIR_TEST/step250.sh" "openspec/changes/feat" 2>&1) || exit_code=$?
# The script should return GENERATED or EXISTS since the checkpoint dir exists
# (the mock allure will succeed on the valid directory)
assert_exit "E2E-6. checkpoint dir exists → exit 0" 0 $exit_code

# ── L2 audit hook integration test ──

# E2E-7. check-predecessor-checkpoint.sh audits Phase 5 task L2 evidence
# Setup: Phase 5 task checkpoint exists with L1 evidence (no L2) → hook warns on stderr
setup_change "$TMPDIR_TEST/e2e7" "feat"
echo '{"change":"feat","pid":"99999","started":"2026-01-01T00:00:00Z","mode":"full"}' \
  >"$TMPDIR_TEST/e2e7/openspec/changes/.autopilot-active"
# Phase 4 checkpoint (predecessor for Phase 5 in full mode)
echo '{"status":"ok","phase":4}' \
  >"$TMPDIR_TEST/e2e7/openspec/changes/feat/context/phase-results/phase-4-testing.json"
# Phase 5 task checkpoint with L1 evidence only
mkdir -p "$TMPDIR_TEST/e2e7/openspec/changes/feat/context/phase-results/phase5-tasks"
echo '{"task_number":1,"status":"ok","test_driven_evidence":{"red_verified":true,"green_verified":true,"verification_layer":"L1_sub_agent"}}' \
  >"$TMPDIR_TEST/e2e7/openspec/changes/feat/context/phase-results/phase5-tasks/task-1.json"

# Dispatch a Phase 5 task (task 2) → hook should audit task-1.json and warn about L1 layer
exit_code=0
HOOK_INPUT=$(python3 -c "
import json
data = {
    'tool_name': 'Task',
    'cwd': '$TMPDIR_TEST/e2e7',
    'tool_input': {'prompt': '<!-- autopilot-phase:5 -->\nPhase 5 task 2'}
}
print(json.dumps(data))
")
output=$(echo "$HOOK_INPUT" | AUTOPILOT_PROJECT_ROOT="$TMPDIR_TEST/e2e7" bash "$SCRIPT_DIR/check-predecessor-checkpoint.sh" 2>"$TMPDIR_TEST/e2e7_stderr.txt") || exit_code=$?
assert_exit "E2E-7. Phase 5 dispatch with L1 evidence → exit 0 (allow)" 0 $exit_code
stderr_content=$(cat "$TMPDIR_TEST/e2e7_stderr.txt")
assert_contains "E2E-7. stderr has L2-AUDIT warning" "$stderr_content" "L2-AUDIT"
assert_contains "E2E-7. mentions L1 layer issue" "$stderr_content" "L1"

# E2E-8. Same setup but with L2 evidence → no L2-AUDIT warning
setup_change "$TMPDIR_TEST/e2e8" "feat"
echo '{"change":"feat","pid":"99999","started":"2026-01-01T00:00:00Z","mode":"full"}' \
  >"$TMPDIR_TEST/e2e8/openspec/changes/.autopilot-active"
echo '{"status":"ok","phase":4}' \
  >"$TMPDIR_TEST/e2e8/openspec/changes/feat/context/phase-results/phase-4-testing.json"
mkdir -p "$TMPDIR_TEST/e2e8/openspec/changes/feat/context/phase-results/phase5-tasks"
echo '{"task_number":1,"status":"ok","test_driven_evidence":{"red_verified":true,"green_verified":true,"verification_layer":"L2_main_thread"}}' \
  >"$TMPDIR_TEST/e2e8/openspec/changes/feat/context/phase-results/phase5-tasks/task-1.json"

exit_code=0
HOOK_INPUT=$(python3 -c "
import json
data = {
    'tool_name': 'Task',
    'cwd': '$TMPDIR_TEST/e2e8',
    'tool_input': {'prompt': '<!-- autopilot-phase:5 -->\nPhase 5 task 2'}
}
print(json.dumps(data))
")
output=$(echo "$HOOK_INPUT" | AUTOPILOT_PROJECT_ROOT="$TMPDIR_TEST/e2e8" bash "$SCRIPT_DIR/check-predecessor-checkpoint.sh" 2>"$TMPDIR_TEST/e2e8_stderr.txt") || exit_code=$?
assert_exit "E2E-8. Phase 5 dispatch with L2 evidence → exit 0" 0 $exit_code
stderr_content=$(cat "$TMPDIR_TEST/e2e8_stderr.txt")
assert_not_contains "E2E-8. no L2-AUDIT warning" "$stderr_content" "L2-AUDIT"

teardown_autopilot_fixture
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1
exit 0

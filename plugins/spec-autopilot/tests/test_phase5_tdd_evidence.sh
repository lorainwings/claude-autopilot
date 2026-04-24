#!/usr/bin/env bash
# test_phase5_tdd_evidence.sh — Phase 5 L2 test_driven_evidence verification
# TEST_LAYER: behavior
# Production targets:
#   - verify-test-driven-l2.sh (L2 checkpoint validator)
#   - _post_task_validator.py (PostToolUse hook, L1 envelope check)
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../runtime/scripts" && pwd)"
source "$TEST_DIR/_test_helpers.sh"
source "$TEST_DIR/_fixtures.sh"

echo "--- Phase 5 L2 test_driven_evidence verification ---"
setup_autopilot_fixture

VERIFY_SCRIPT="$SCRIPT_DIR/verify-test-driven-l2.sh"
TMPDIR_TEST=$(mktemp -d)
trap 'rm -rf "$TMPDIR_TEST"' EXIT

# ── verify-test-driven-l2.sh tests ──

# 1a. valid RED→GREEN evidence → ok
cat >"$TMPDIR_TEST/task-1.json" <<'EOF'
{
  "task_number": 1,
  "status": "ok",
  "test_driven_evidence": {
    "red_verified": true,
    "green_verified": true,
    "red_skipped_reason": null,
    "verification_layer": "L2_main_thread"
  }
}
EOF
exit_code=0
output=$(bash "$VERIFY_SCRIPT" "$TMPDIR_TEST/task-1.json" 2>/dev/null) || exit_code=$?
assert_exit "1a. valid evidence → exit 0" 0 $exit_code
assert_contains "1a. status is ok" "$output" '"status":"ok"'
assert_contains "1a. red_verified true" "$output" '"red_verified":true'
assert_contains "1a. green_verified true" "$output" '"green_verified":true'

# 1b. missing test_driven_evidence → warn
cat >"$TMPDIR_TEST/task-2.json" <<'EOF'
{
  "task_number": 2,
  "status": "ok"
}
EOF
exit_code=0
output=$(bash "$VERIFY_SCRIPT" "$TMPDIR_TEST/task-2.json" 2>/dev/null) || exit_code=$?
assert_exit "1b. missing evidence → exit 0" 0 $exit_code
assert_contains "1b. status is warn" "$output" '"status":"warn"'
assert_contains "1b. message mentions missing" "$output" "missing"

# 1c. RED skipped → warn with reason
cat >"$TMPDIR_TEST/task-3.json" <<'EOF'
{
  "task_number": 3,
  "status": "ok",
  "test_driven_evidence": {
    "red_verified": false,
    "green_verified": true,
    "red_skipped_reason": "test_already_passing",
    "verification_layer": "L2_main_thread"
  }
}
EOF
exit_code=0
output=$(bash "$VERIFY_SCRIPT" "$TMPDIR_TEST/task-3.json" 2>/dev/null) || exit_code=$?
assert_exit "1c. RED skipped → exit 0" 0 $exit_code
assert_contains "1c. status is warn" "$output" '"status":"warn"'
assert_contains "1c. message mentions skipped" "$output" "RED skipped"

# 1d. GREEN not verified → warn
cat >"$TMPDIR_TEST/task-4.json" <<'EOF'
{
  "task_number": 4,
  "status": "ok",
  "test_driven_evidence": {
    "red_verified": true,
    "green_verified": false,
    "red_skipped_reason": null,
    "verification_layer": "L2_main_thread"
  }
}
EOF
exit_code=0
output=$(bash "$VERIFY_SCRIPT" "$TMPDIR_TEST/task-4.json" 2>/dev/null) || exit_code=$?
assert_exit "1d. GREEN failed → exit 0" 0 $exit_code
assert_contains "1d. status is warn" "$output" '"status":"warn"'
assert_contains "1d. message mentions GREEN" "$output" "GREEN not verified"

# 1e. non-existent file → warn
exit_code=0
output=$(bash "$VERIFY_SCRIPT" "$TMPDIR_TEST/nonexistent.json" 2>/dev/null) || exit_code=$?
assert_exit "1e. missing file → exit 0" 0 $exit_code
assert_contains "1e. status is warn" "$output" '"status":"warn"'
assert_contains "1e. message mentions not found" "$output" "not found"

# 1f. output is valid JSON in all cases
for f in task-1 task-2 task-3 task-4; do
  out=$(bash "$VERIFY_SCRIPT" "$TMPDIR_TEST/$f.json" 2>/dev/null)
  if echo "$out" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null; then
    green "  PASS: 1f. $f output is valid JSON"
    PASS=$((PASS + 1))
  else
    red "  FAIL: 1f. $f output is not valid JSON"
    FAIL=$((FAIL + 1))
  fi
done

# 1g. NEGATIVE: L1 sub-agent evidence (verification_layer != L2_main_thread) → must be warn, not ok
# Regression test: sub-agent self-reports red=true, green=true but layer is L1.
# Before fix: script returned status:"ok" — mixing up L1/L2 boundary.
# After fix: script detects non-L2 layer and returns status:"warn".
cat >"$TMPDIR_TEST/task-5.json" <<'EOF'
{
  "task_number": 5,
  "status": "ok",
  "test_driven_evidence": {
    "red_verified": true,
    "green_verified": true,
    "red_skipped_reason": null,
    "verification_layer": "L1_sub_agent"
  }
}
EOF
exit_code=0
output=$(bash "$VERIFY_SCRIPT" "$TMPDIR_TEST/task-5.json" 2>/dev/null) || exit_code=$?
assert_exit "1g. L1 layer evidence → exit 0" 0 $exit_code
assert_contains "1g. status is warn (not ok)" "$output" '"status":"warn"'
assert_contains "1g. message mentions L1" "$output" "L1"
assert_not_contains "1g. must NOT be ok" "$output" '"status":"ok"'

# 1h. NEGATIVE: unknown verification_layer → must be warn
cat >"$TMPDIR_TEST/task-6.json" <<'EOF'
{
  "task_number": 6,
  "status": "ok",
  "test_driven_evidence": {
    "red_verified": true,
    "green_verified": true,
    "red_skipped_reason": null,
    "verification_layer": "unknown"
  }
}
EOF
exit_code=0
output=$(bash "$VERIFY_SCRIPT" "$TMPDIR_TEST/task-6.json" 2>/dev/null) || exit_code=$?
assert_exit "1h. unknown layer → exit 0" 0 $exit_code
assert_contains "1h. status is warn" "$output" '"status":"warn"'
assert_not_contains "1h. must NOT be ok" "$output" '"status":"ok"'

# 1i. NEGATIVE: no verification_layer field at all → defaults to unknown → warn
cat >"$TMPDIR_TEST/task-7.json" <<'EOF'
{
  "task_number": 7,
  "status": "ok",
  "test_driven_evidence": {
    "red_verified": true,
    "green_verified": true,
    "red_skipped_reason": null
  }
}
EOF
exit_code=0
output=$(bash "$VERIFY_SCRIPT" "$TMPDIR_TEST/task-7.json" 2>/dev/null) || exit_code=$?
assert_exit "1i. missing layer → exit 0" 0 $exit_code
assert_contains "1i. status is warn" "$output" '"status":"warn"'
assert_not_contains "1i. must NOT be ok" "$output" '"status":"ok"'

# ── _post_task_validator.py L1 envelope check (PostToolUse scope) ──

run_validator() {
  echo "$1" | python3 "$SCRIPT_DIR/_post_task_validator.py" 2>"$TMPDIR_TEST/stderr.txt"
}

# Helper: build valid Phase 5 PostToolUse JSON input with proper escaping
# Avoids raw \n in shell strings which breaks JSON parsing
build_phase5_input() {
  local extra_fields="${1:-}"
  python3 -c "
import json, sys
envelope = {
    'status': 'ok',
    'summary': 'Task done',
    'artifacts': ['src/foo.ts'],
    'test_results_path': 'test-results.json',
    'tasks_completed': 3,
    'zero_skip_check': {'passed': True}
}
${extra_fields}
data = {
    'tool_name': 'Task',
    'cwd': '$REPO_ROOT',
    'tool_input': {'prompt': '<!-- autopilot-phase:5 -->\nPhase 5'},
    'tool_response': 'Result: ' + json.dumps(envelope)
}
print(json.dumps(data))
"
}

# 2a. Phase 5 envelope WITH test_driven_evidence (L1 self-report) → no block
exit_code=0
input_json=$(build_phase5_input "envelope['test_driven_evidence'] = {'red_verified': True, 'green_verified': True, 'red_skipped_reason': None}")
output=$(run_validator "$input_json") || exit_code=$?
assert_exit "2a. Phase 5 with L1 evidence → exit 0" 0 $exit_code
assert_not_contains "2a. no block" "$output" "block"
stderr_content=$(cat "$TMPDIR_TEST/stderr.txt")
assert_contains "2a. INFO about RED→GREEN" "$stderr_content" "RED"

# 2b. Phase 5 envelope WITHOUT test_driven_evidence → no block (L2 handled separately)
exit_code=0
input_json=$(build_phase5_input "")
output=$(run_validator "$input_json") || exit_code=$?
assert_exit "2b. Phase 5 without evidence → exit 0 (L2 validates later)" 0 $exit_code
assert_not_contains "2b. no block" "$output" "block"

# 2c. Phase 5 envelope with RED skipped → no block, stderr warning
exit_code=0
input_json=$(build_phase5_input "envelope['test_driven_evidence'] = {'red_verified': False, 'green_verified': True, 'red_skipped_reason': 'test_already_passing'}")
output=$(run_validator "$input_json") || exit_code=$?
assert_exit "2c. Phase 5 RED skipped → exit 0" 0 $exit_code
assert_not_contains "2c. no block" "$output" "block"
stderr_content=$(cat "$TMPDIR_TEST/stderr.txt")
assert_contains "2c. WARNING about RED skipped" "$stderr_content" "RED skipped"

teardown_autopilot_fixture
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1
exit 0

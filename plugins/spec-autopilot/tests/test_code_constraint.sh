#!/usr/bin/env bash
# test_code_constraint.sh — Section 54: code_constraints L2 blocking (Phase 5)
# Tests unified-write-edit-check.sh CHECK 4: code constraint validation
# via _constraint_loader.py during Phase 5.
#
# Validates:
#   - forbidden_files blocks matching writes
#   - forbidden_patterns blocks matching content
#   - allowed_dirs blocks out-of-scope writes
#   - No constraints → no blocking
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../scripts" && pwd)"
source "$TEST_DIR/_test_helpers.sh"

echo "--- 54. code_constraints L2 blocking (Phase 5) ---"

# Self-contained temp directory
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/.claude"
mkdir -p "$TMPDIR/openspec/changes/test-fixture/context/phase-results"
echo '{"change":"test-fixture","pid":"99999","started":"2026-01-01T00:00:00Z"}' \
  > "$TMPDIR/openspec/changes/.autopilot-active"
# Phase 1 checkpoint (ok)
echo '{"status":"ok","summary":"Done","decisions":[{"point":"x","choice":"y"}]}' \
  > "$TMPDIR/openspec/changes/test-fixture/context/phase-results/phase-1-test.json"
# Phase 4 checkpoint (ok) → IN_PHASE5=yes
echo '{"status":"ok","summary":"Tests","test_counts":{"unit":5},"sad_path_counts":{"unit":2},"dry_run_results":{"unit":0},"test_pyramid":{"unit_pct":100,"e2e_pct":0},"change_coverage":{"change_points":["A"],"tested_points":["A"],"coverage_pct":100,"untested_points":[]},"artifacts":["t.py"]}' \
  > "$TMPDIR/openspec/changes/test-fixture/context/phase-results/phase-4-test.json"

# Create config with code_constraints
cat > "$TMPDIR/.claude/autopilot.config.yaml" <<'CFGEOF'
version: "1.0"
services: {}
phases:
  requirements:
    agent: main
  testing:
    agent: main
    gate:
      min_test_count_per_type: 3
      required_test_types:
        - unit
  implementation:
    serial_task:
      max_retries_per_task: 3
  reporting:
    coverage_target: 80
    zero_skip_required: true
test_suites:
  unit:
    command: "echo ok"
    type: unit

code_constraints:
  forbidden_files:
    - .env
    - secrets.json
  forbidden_patterns:
    - pattern: "eval\\("
    - pattern: "exec\\("
  allowed_dirs:
    - src/
    - tests/
  max_file_lines: 500
CFGEOF

# Helper: create file and build Write hook stdin
write_and_input() {
  local rel_path="$1" content="$2"
  local fpath="$TMPDIR/$rel_path"
  mkdir -p "$(dirname "$fpath")"
  printf '%s' "$content" > "$fpath"
  echo '{"tool_name":"Write","tool_input":{"file_path":"'"$fpath"'"},"cwd":"'"$TMPDIR"'"}'
}

# 54a. Forbidden file (.env) → block
exit_code=0
output=$(write_and_input "src/.env" "SECRET_KEY=abc123" \
  | bash "$SCRIPT_DIR/unified-write-edit-check.sh" 2>/dev/null) || exit_code=$?
assert_exit "54a. forbidden file .env → exit 0" 0 $exit_code
assert_contains "54a. forbidden file .env → block" "$output" "block"
assert_contains "54a. mentions forbidden" "$output" "orbidden"

# 54b. Forbidden pattern eval() → block
exit_code=0
output=$(write_and_input "src/danger.ts" "const result = eval(userInput);" \
  | bash "$SCRIPT_DIR/unified-write-edit-check.sh" 2>/dev/null) || exit_code=$?
assert_exit "54b. forbidden pattern eval() → exit 0" 0 $exit_code
assert_contains "54b. forbidden pattern eval() → block" "$output" "block"

# 54c. Out-of-scope directory → block
exit_code=0
output=$(write_and_input "config/settings.ts" "export const config = {};" \
  | bash "$SCRIPT_DIR/unified-write-edit-check.sh" 2>/dev/null) || exit_code=$?
assert_exit "54c. out-of-scope dir → exit 0" 0 $exit_code
assert_contains "54c. out-of-scope dir → block" "$output" "block"
assert_contains "54c. mentions scope" "$output" "scope"

# 54d. Allowed file in allowed dir with clean content → pass
exit_code=0
output=$(write_and_input "src/service.ts" "export function add(a: number, b: number) { return a + b; }" \
  | bash "$SCRIPT_DIR/unified-write-edit-check.sh" 2>/dev/null) || exit_code=$?
assert_exit "54d. clean file in allowed dir → exit 0" 0 $exit_code
assert_not_contains "54d. clean file in allowed dir → no block" "$output" "block"

# 54e. No config constraints → no constraint blocking
rm -f "$TMPDIR/.claude/autopilot.config.yaml"
exit_code=0
output=$(write_and_input "anywhere/file.ts" "const x = eval('1+1');" \
  | bash "$SCRIPT_DIR/unified-write-edit-check.sh" 2>/dev/null) || exit_code=$?
assert_exit "54e. no config → exit 0" 0 $exit_code
assert_not_contains "54e. no config → no constraint block" "$output" "constraint"

echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1; exit 0

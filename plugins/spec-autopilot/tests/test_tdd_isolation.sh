#!/usr/bin/env bash
# test_tdd_isolation.sh — Section 52: TDD RED/GREEN/REFACTOR file write isolation
# Tests that .tdd-stage drives L2 Hook enforcement:
#   RED:      only test files may be written
#   GREEN:    only implementation files may be written
#   REFACTOR: both types allowed (no blocking)
#   No stage:  no TDD blocking
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../runtime/scripts" && pwd)"
source "$TEST_DIR/_test_helpers.sh"

echo "--- 52. TDD phase isolation (RED/GREEN/REFACTOR) ---"

# Self-contained temp directory
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/.claude"
mkdir -p "$TMPDIR/openspec/changes/test-fixture/context/phase-results"
echo '{"change":"test-fixture","pid":"99999","started":"2026-01-01T00:00:00Z"}' \
  >"$TMPDIR/openspec/changes/.autopilot-active"

# Phase 1 checkpoint (ok) — required for all checks
echo '{"status":"ok","summary":"Req done","decisions":[{"point":"x","choice":"y"}]}' \
  >"$TMPDIR/openspec/changes/test-fixture/context/phase-results/phase-1-test.json"
# Phase 4 checkpoint (ok) — triggers IN_PHASE5=yes (no Phase 5 checkpoint)
echo '{"status":"ok","summary":"Tests designed","test_counts":{"unit":5},"sad_path_counts":{"unit":2},"dry_run_results":{"unit":0},"test_pyramid":{"unit_pct":100,"e2e_pct":0},"change_coverage":{"change_points":["A"],"tested_points":["A"],"coverage_pct":100,"untested_points":[]},"artifacts":["t.py"]}' \
  >"$TMPDIR/openspec/changes/test-fixture/context/phase-results/phase-4-test.json"

TDD_STAGE_FILE="$TMPDIR/openspec/changes/test-fixture/context/.tdd-stage"

# Helper: build Write hook stdin JSON
# Args: file_path
make_write_input() {
  echo '{"tool_name":"Write","tool_input":{"file_path":"'"$1"'"},"cwd":"'"$TMPDIR"'"}'
}

# === RED stage tests ===
echo "RED" >"$TDD_STAGE_FILE"

# 52a. RED + implementation file → block
exit_code=0
output=$(make_write_input "$TMPDIR/src/service.ts" | bash "$SCRIPT_DIR/unified-write-edit-check.sh" 2>/dev/null) || exit_code=$?
assert_exit "52a. RED + impl file → exit 0" 0 $exit_code
assert_contains "52a. RED + impl file → block" "$output" "block"
assert_contains "52a. RED + impl file → mentions RED" "$output" "RED"

# 52b. RED + test file (*.test.ts) → pass
exit_code=0
output=$(make_write_input "$TMPDIR/src/service.test.ts" | bash "$SCRIPT_DIR/unified-write-edit-check.sh" 2>/dev/null) || exit_code=$?
assert_exit "52b. RED + test file → exit 0" 0 $exit_code
assert_not_contains "52b. RED + test file → no block" "$output" "block"

# 52c. RED + test file in __tests__ dir → pass
exit_code=0
output=$(make_write_input "$TMPDIR/src/__tests__/service.ts" | bash "$SCRIPT_DIR/unified-write-edit-check.sh" 2>/dev/null) || exit_code=$?
assert_exit "52c. RED + __tests__ dir file → exit 0" 0 $exit_code
assert_not_contains "52c. RED + __tests__ dir file → no block" "$output" "block"

# === GREEN stage tests ===
echo "GREEN" >"$TDD_STAGE_FILE"

# 52d. GREEN + test file → block
exit_code=0
output=$(make_write_input "$TMPDIR/src/service.spec.ts" | bash "$SCRIPT_DIR/unified-write-edit-check.sh" 2>/dev/null) || exit_code=$?
assert_exit "52d. GREEN + test file → exit 0" 0 $exit_code
assert_contains "52d. GREEN + test file → block" "$output" "block"
assert_contains "52d. GREEN + test file → mentions GREEN" "$output" "GREEN"

# 52e. GREEN + implementation file → pass
exit_code=0
output=$(make_write_input "$TMPDIR/src/service.ts" | bash "$SCRIPT_DIR/unified-write-edit-check.sh" 2>/dev/null) || exit_code=$?
assert_exit "52e. GREEN + impl file → exit 0" 0 $exit_code
assert_not_contains "52e. GREEN + impl file → no block" "$output" "block"

# === REFACTOR stage tests ===
echo "REFACTOR" >"$TDD_STAGE_FILE"

# 52f. REFACTOR + any file → pass (no TDD blocking)
exit_code=0
output=$(make_write_input "$TMPDIR/src/service.ts" | bash "$SCRIPT_DIR/unified-write-edit-check.sh" 2>/dev/null) || exit_code=$?
assert_exit "52f. REFACTOR + impl file → exit 0" 0 $exit_code
assert_not_contains "52f. REFACTOR + impl file → no block" "$output" "block"

exit_code=0
output=$(make_write_input "$TMPDIR/src/service.test.ts" | bash "$SCRIPT_DIR/unified-write-edit-check.sh" 2>/dev/null) || exit_code=$?
assert_exit "52f2. REFACTOR + test file → exit 0" 0 $exit_code
assert_not_contains "52f2. REFACTOR + test file → no block" "$output" "block"

# === No TDD stage file ===
rm -f "$TDD_STAGE_FILE"

# 52g. No .tdd-stage → no TDD blocking
exit_code=0
output=$(make_write_input "$TMPDIR/src/service.ts" | bash "$SCRIPT_DIR/unified-write-edit-check.sh" 2>/dev/null) || exit_code=$?
assert_exit "52g. no .tdd-stage + impl file → exit 0" 0 $exit_code
assert_not_contains "52g. no .tdd-stage → no block" "$output" "block"

echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1
exit 0

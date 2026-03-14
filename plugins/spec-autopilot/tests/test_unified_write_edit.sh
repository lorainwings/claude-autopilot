#!/usr/bin/env bash
# test_unified_write_edit.sh — Section 53: unified-write-edit-check.sh banned patterns & assertion quality
# End-to-end tests for:
#   CHECK 2: TODO/FIXME/HACK detection → block on source files, skip on non-source
#   CHECK 3: Tautological assertion detection → block on test files
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../scripts" && pwd)"
source "$TEST_DIR/_test_helpers.sh"

echo "--- 53. unified-write-edit banned patterns & assertion quality ---"

# Self-contained temp directory
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/.claude"
mkdir -p "$TMPDIR/openspec/changes/test-fixture/context/phase-results"
echo '{"change":"test-fixture","pid":"99999","started":"2026-01-01T00:00:00Z"}' \
  > "$TMPDIR/openspec/changes/.autopilot-active"
# Phase 1 checkpoint (ok) — required for checks to run
echo '{"status":"ok","summary":"Done","decisions":[{"point":"x","choice":"y"}]}' \
  > "$TMPDIR/openspec/changes/test-fixture/context/phase-results/phase-1-test.json"

# Create temp source files with banned patterns
mkdir -p "$TMPDIR/src"

# Helper: create file and build Write hook stdin
# Args: relative_path content
write_file_and_input() {
  local fpath="$TMPDIR/$1"
  mkdir -p "$(dirname "$fpath")"
  echo "$2" > "$fpath"
  echo '{"tool_name":"Write","tool_input":{"file_path":"'"$fpath"'"},"cwd":"'"$TMPDIR"'"}'
}

# === CHECK 2: Banned Patterns (TODO/FIXME/HACK) ===

# 53a. Source file with TODO: → block
exit_code=0
output=$(write_file_and_input "src/service.ts" "function init() {
  // TODO: implement later
  return null;
}" | bash "$SCRIPT_DIR/unified-write-edit-check.sh" 2>/dev/null) || exit_code=$?
assert_exit "53a. TODO: in source → exit 0" 0 $exit_code
assert_contains "53a. TODO: in source → block" "$output" "block"
assert_contains "53a. mentions banned pattern" "$output" "TODO"

# 53b. Source file with FIXME: → block
exit_code=0
output=$(write_file_and_input "src/handler.py" "def handle():
    pass  # FIXME: broken logic
" | bash "$SCRIPT_DIR/unified-write-edit-check.sh" 2>/dev/null) || exit_code=$?
assert_exit "53b. FIXME: in source → exit 0" 0 $exit_code
assert_contains "53b. FIXME: in source → block" "$output" "block"

# 53c. Source file with HACK: → block
exit_code=0
output=$(write_file_and_input "src/util.js" "// HACK: workaround for issue #123
module.exports = {}" | bash "$SCRIPT_DIR/unified-write-edit-check.sh" 2>/dev/null) || exit_code=$?
assert_exit "53c. HACK: in source → exit 0" 0 $exit_code
assert_contains "53c. HACK: in source → block" "$output" "block"

# 53d. Markdown file with TODO: → skip (non-source file exempted)
exit_code=0
output=$(write_file_and_input "docs/notes.md" "# Notes
- TODO: add more docs" | bash "$SCRIPT_DIR/unified-write-edit-check.sh" 2>/dev/null) || exit_code=$?
assert_exit "53d. TODO: in .md → exit 0" 0 $exit_code
assert_not_contains "53d. TODO: in .md → no block" "$output" "block"

# 53e. Clean source file → pass
exit_code=0
output=$(write_file_and_input "src/clean.ts" "export function add(a: number, b: number): number {
  return a + b;
}" | bash "$SCRIPT_DIR/unified-write-edit-check.sh" 2>/dev/null) || exit_code=$?
assert_exit "53e. clean source → exit 0" 0 $exit_code
assert_not_contains "53e. clean source → no block" "$output" "block"

# === CHECK 3: Tautological Assertions ===

# 53f. JS tautological assertion expect(true).toBe(true) → block
exit_code=0
output=$(write_file_and_input "src/service.test.ts" "describe('service', () => {
  it('should work', () => {
    expect(true).toBe(true);
  });
});" | bash "$SCRIPT_DIR/unified-write-edit-check.sh" 2>/dev/null) || exit_code=$?
assert_exit "53f. expect(true).toBe(true) → exit 0" 0 $exit_code
assert_contains "53f. tautological assertion → block" "$output" "block"
assert_contains "53f. mentions tautological" "$output" "autological"

# 53g. Python assert True → block
exit_code=0
output=$(write_file_and_input "tests/test_core.py" "class TestCore:
    def test_basic(self):
        assert True
" | bash "$SCRIPT_DIR/unified-write-edit-check.sh" 2>/dev/null) || exit_code=$?
assert_exit "53g. Python assert True → exit 0" 0 $exit_code
assert_contains "53g. Python assert True → block" "$output" "block"

# 53h. Legitimate assertion → pass
exit_code=0
output=$(write_file_and_input "src/__tests__/math.test.ts" "describe('math', () => {
  it('adds numbers', () => {
    expect(add(1, 2)).toBe(3);
    expect(add(-1, 1)).toBe(0);
  });
});" | bash "$SCRIPT_DIR/unified-write-edit-check.sh" 2>/dev/null) || exit_code=$?
assert_exit "53h. legitimate assertions → exit 0" 0 $exit_code
assert_not_contains "53h. legitimate assertions → no block" "$output" "block"

# === SKIP_HEAVY_CHECKS: Non-source files skip CHECK 2/3/4 ===

# 53i. JSON file with TODO: → skip (non-source)
exit_code=0
output=$(write_file_and_input "config/settings.json" '{"key": "TODO: placeholder"}' \
  | bash "$SCRIPT_DIR/unified-write-edit-check.sh" 2>/dev/null) || exit_code=$?
assert_exit "53i. TODO: in .json → exit 0" 0 $exit_code
assert_not_contains "53i. TODO: in .json → no block" "$output" "block"

# 53j. YAML file with FIXME: → skip (non-source)
exit_code=0
output=$(write_file_and_input "config/app.yaml" "# FIXME: update this value
db_host: localhost" \
  | bash "$SCRIPT_DIR/unified-write-edit-check.sh" 2>/dev/null) || exit_code=$?
assert_exit "53j. FIXME: in .yaml → exit 0" 0 $exit_code
assert_not_contains "53j. FIXME: in .yaml → no block" "$output" "block"

# 53k. CSV file with HACK: → skip (non-source)
exit_code=0
output=$(write_file_and_input "data/report.csv" "name,status
HACK: entry,active" \
  | bash "$SCRIPT_DIR/unified-write-edit-check.sh" 2>/dev/null) || exit_code=$?
assert_exit "53k. HACK: in .csv → exit 0" 0 $exit_code
assert_not_contains "53k. HACK: in .csv → no block" "$output" "block"

# === CHECK 1: TDD REFACTOR file tracking ===

# 53l. REFACTOR stage → file path recorded in .tdd-refactor-files
echo "refactor" > "$TMPDIR/openspec/changes/test-fixture/context/.tdd-stage"
# Phase 4 checkpoint needed to trigger IN_PHASE5
echo '{"status":"ok","summary":"Done"}' \
  > "$TMPDIR/openspec/changes/test-fixture/context/phase-results/phase-4-test.json"
rm -f "$TMPDIR/openspec/changes/test-fixture/context/.tdd-refactor-files"
exit_code=0
output=$(write_file_and_input "src/refactored.ts" "export const x = 1;" \
  | bash "$SCRIPT_DIR/unified-write-edit-check.sh" 2>/dev/null) || exit_code=$?
assert_exit "53l. REFACTOR write → exit 0" 0 $exit_code
assert_not_contains "53l. REFACTOR write → no block" "$output" "block"
REFACTOR_FILE="$TMPDIR/openspec/changes/test-fixture/context/.tdd-refactor-files"
if [ -f "$REFACTOR_FILE" ] && grep -q "refactored.ts" "$REFACTOR_FILE"; then
  green "  PASS: 53l. REFACTOR file tracked in .tdd-refactor-files"
  PASS=$((PASS + 1))
else
  red "  FAIL: 53l. REFACTOR file NOT tracked in .tdd-refactor-files"
  FAIL=$((FAIL + 1))
fi
# Clean up TDD state for subsequent tests
rm -f "$TMPDIR/openspec/changes/test-fixture/context/.tdd-stage"
rm -f "$TMPDIR/openspec/changes/test-fixture/context/.tdd-refactor-files"

# === P1-5: .md TODO detection in delivery phases ===

# 53m. Phase 4+ .md file with TODO: → block (delivery phase)
# Phase 3 checkpoint present → IN_DELIVERY_PHASE=yes
echo '{"status":"ok","summary":"Done"}' \
  > "$TMPDIR/openspec/changes/test-fixture/context/phase-results/phase-3-test.json"
exit_code=0
output=$(write_file_and_input "docs/design.md" "# Design
- TODO: finish this section" \
  | bash "$SCRIPT_DIR/unified-write-edit-check.sh" 2>/dev/null) || exit_code=$?
assert_exit "53m. TODO: in .md (delivery phase) → exit 0" 0 $exit_code
assert_contains "53m. TODO: in .md (delivery phase) → block" "$output" "block"

# 53n. Phase 1 only .md file with TODO: → no block (pre-delivery)
# Remove Phase 3 & 4 checkpoints to simulate Phase 1 only (full mode)
rm -f "$TMPDIR/openspec/changes/test-fixture/context/phase-results/phase-3-test.json"
rm -f "$TMPDIR/openspec/changes/test-fixture/context/phase-results/phase-4-test.json"
exit_code=0
output=$(write_file_and_input "docs/notes2.md" "# Notes
- TODO: add more docs" \
  | bash "$SCRIPT_DIR/unified-write-edit-check.sh" 2>/dev/null) || exit_code=$?
assert_exit "53n. TODO: in .md (phase 1 only) → exit 0" 0 $exit_code
assert_not_contains "53n. TODO: in .md (phase 1 only) → no block" "$output" "block"

echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1; exit 0

#!/usr/bin/env bash
# test_run_all.sh — Regression tests for tests/run_all.sh
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TEST_DIR/_test_helpers.sh"

RUNNER="$TEST_DIR/run_all.sh"
UNIQ="tmp_runner_$$"
PASS_TEST="$TEST_DIR/test_${UNIQ}_pass.sh"
FAIL_TEST="$TEST_DIR/test_${UNIQ}_fail.sh"

cleanup() {
  rm -f "$PASS_TEST" "$FAIL_TEST"
}
trap cleanup EXIT

cat > "$PASS_TEST" <<'EOF'
#!/usr/bin/env bash
echo "  PASS: temp runner pass"
exit 0
EOF

cat > "$FAIL_TEST" <<'EOF'
#!/usr/bin/env bash
echo "  FAIL: temp hidden failure"
exit 0
EOF

chmod +x "$PASS_TEST" "$FAIL_TEST"

echo "--- run_all.sh regression tests ---"

output=$(bash "$RUNNER" "$UNIQ" 2>&1)
exit_code=$?

assert_exit "run_all catches hidden FAIL output → exit 1" 1 "$exit_code"
assert_contains "run_all summary counts failed file" "$output" "Test Summary: 2 files, 1 passed, 1 failed"
assert_contains "run_all lists hidden-fail file" "$output" "test_${UNIQ}_fail"

echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1
exit 0

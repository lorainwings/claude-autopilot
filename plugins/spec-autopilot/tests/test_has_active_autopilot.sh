#!/usr/bin/env bash
# test_has_active_autopilot.sh — Section 26: has_active_autopilot unit tests
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../runtime/scripts" && pwd)"
source "$TEST_DIR/_test_helpers.sh"
source "$TEST_DIR/_fixtures.sh"

echo "--- 26. has_active_autopilot unit tests ---"
setup_autopilot_fixture

# 26a. No changes dir → not active
HAS_TEST_DIR=$(mktemp -d)
exit_code=0
(source "$SCRIPT_DIR/_common.sh" && has_active_autopilot "$HAS_TEST_DIR") || exit_code=$?
assert_exit "no changes dir → not active (exit 1)" 1 $exit_code

# 26b. Changes dir but no lock file → not active
mkdir -p "$HAS_TEST_DIR/openspec/changes/some-change"
exit_code=0
(source "$SCRIPT_DIR/_common.sh" && has_active_autopilot "$HAS_TEST_DIR") || exit_code=$?
assert_exit "no lock file → not active (exit 1)" 1 $exit_code

# 26c. Lock file exists → active
echo '{"change":"test"}' > "$HAS_TEST_DIR/openspec/changes/.autopilot-active"
exit_code=0
(source "$SCRIPT_DIR/_common.sh" && has_active_autopilot "$HAS_TEST_DIR") || exit_code=$?
assert_exit "lock file exists → active (exit 0)" 0 $exit_code

rm -rf "$HAS_TEST_DIR"

teardown_autopilot_fixture
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1; exit 0

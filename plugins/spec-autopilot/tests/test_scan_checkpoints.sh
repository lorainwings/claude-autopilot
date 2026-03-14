#!/usr/bin/env bash
# test_scan_checkpoints.sh — Section 4: scan-checkpoints-on-start.sh
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../scripts" && pwd)"
source "$TEST_DIR/_test_helpers.sh"
source "$TEST_DIR/_fixtures.sh"

echo "--- 4. scan-checkpoints-on-start.sh ---"
setup_autopilot_fixture

exit_code=0
output=$(bash "$SCRIPT_DIR/scan-checkpoints-on-start.sh" 2>/dev/null) || exit_code=$?
assert_exit "SessionStart hook → exit 0" 0 $exit_code

teardown_autopilot_fixture
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1; exit 0

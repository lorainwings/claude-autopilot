#!/usr/bin/env bash
# test_phase4_missing_fields.sh — Section 32: Phase 4 missing required fields
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../scripts" && pwd)"
source "$TEST_DIR/_test_helpers.sh"
source "$TEST_DIR/_fixtures.sh"

echo "--- 32. Phase 4 missing individual required fields ---"
setup_autopilot_fixture

# 32a. Phase 4 missing test_pyramid → should block
exit_code=0
output=$(echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:4 -->\nPhase 4"},"tool_response":"Result: {\"status\":\"ok\",\"summary\":\"Tests done\",\"artifacts\":[\"tests/unit.py\"],\"test_counts\":{\"unit\":10,\"api\":5,\"e2e\":3,\"ui\":2},\"dry_run_results\":{\"unit\":0,\"api\":0,\"e2e\":0,\"ui\":0}}"}' \
  | bash "$SCRIPT_DIR/validate-json-envelope.sh" 2>/dev/null) || exit_code=$?
assert_exit "Phase 4 missing test_pyramid → exit 0" 0 $exit_code
assert_contains "Phase 4 missing test_pyramid → block" "$output" "block"
assert_contains "Phase 4 missing test_pyramid → mentions field" "$output" "test_pyramid"

# 32b. Phase 4 missing dry_run_results → should block
exit_code=0
output=$(echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:4 -->\nPhase 4"},"tool_response":"Result: {\"status\":\"ok\",\"summary\":\"Tests done\",\"artifacts\":[\"tests/unit.py\"],\"test_counts\":{\"unit\":10,\"api\":5,\"e2e\":3,\"ui\":2},\"test_pyramid\":{\"unit_pct\":50,\"e2e_pct\":15}}"}' \
  | bash "$SCRIPT_DIR/validate-json-envelope.sh" 2>/dev/null) || exit_code=$?
assert_exit "Phase 4 missing dry_run_results → exit 0" 0 $exit_code
assert_contains "Phase 4 missing dry_run_results → block" "$output" "block"

# 32c. Phase 4 missing test_counts → should block
exit_code=0
output=$(echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:4 -->\nPhase 4"},"tool_response":"Result: {\"status\":\"ok\",\"summary\":\"Tests done\",\"artifacts\":[\"tests/unit.py\"],\"dry_run_results\":{\"unit\":0},\"test_pyramid\":{\"unit_pct\":50,\"e2e_pct\":15}}"}' \
  | bash "$SCRIPT_DIR/validate-json-envelope.sh" 2>/dev/null) || exit_code=$?
assert_exit "Phase 4 missing test_counts → exit 0" 0 $exit_code
assert_contains "Phase 4 missing test_counts → block" "$output" "block"

teardown_autopilot_fixture
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1; exit 0

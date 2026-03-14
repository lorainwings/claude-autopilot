#!/usr/bin/env bash
# test_phase7_predecessor.sh — Section 34: Phase 7 predecessor independent of Phase 6.5
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../scripts" && pwd)"
source "$TEST_DIR/_test_helpers.sh"
source "$TEST_DIR/_fixtures.sh"

echo "--- 34. v3.2.2 Phase 7 predecessor check independent of Phase 6.5 ---"
setup_autopilot_fixture

P7_TEST_DIR=$(mktemp -d)
mkdir -p "$P7_TEST_DIR/openspec/changes/test-feat/context/phase-results"
echo '{"change":"test-feat","mode":"full"}' > "$P7_TEST_DIR/openspec/changes/.autopilot-active"

# 34a. Phase 6 ok, Phase 6.5 absent → Phase 7 allowed
echo '{"status":"ok","summary":"Tests passed","pass_rate":100,"report_path":"r.html","report_format":"html"}' \
  > "$P7_TEST_DIR/openspec/changes/test-feat/context/phase-results/phase-6-report.json"
exit_code=0
output=$(echo "{\"tool_name\":\"Task\",\"tool_input\":{\"prompt\":\"<!-- autopilot-phase:7 -->\\nPhase 7\",\"subagent_type\":\"general-purpose\"},\"cwd\":\"$P7_TEST_DIR\"}" \
  | bash "$SCRIPT_DIR/check-predecessor-checkpoint.sh" 2>/dev/null) || exit_code=$?
assert_exit "Phase 7: Phase 6 ok, no Phase 6.5 → allow (exit 0)" 0 $exit_code
assert_not_contains "Phase 7: no deny without Phase 6.5" "$output" "deny"

# 34b. Phase 6 ok, Phase 6.5 exists with blocked → Phase 7 still allowed (6.5 not checked by Hook)
echo '{"status":"blocked","summary":"Critical findings"}' \
  > "$P7_TEST_DIR/openspec/changes/test-feat/context/phase-results/phase-6.5-code-review.json"
exit_code=0
output=$(echo "{\"tool_name\":\"Task\",\"tool_input\":{\"prompt\":\"<!-- autopilot-phase:7 -->\\nPhase 7\",\"subagent_type\":\"general-purpose\"},\"cwd\":\"$P7_TEST_DIR\"}" \
  | bash "$SCRIPT_DIR/check-predecessor-checkpoint.sh" 2>/dev/null) || exit_code=$?
assert_exit "Phase 7: Phase 6 ok, Phase 6.5 blocked → still allow (exit 0)" 0 $exit_code
assert_not_contains "Phase 7: 6.5 blocked does not deny 7" "$output" "deny"

rm -rf "$P7_TEST_DIR"

teardown_autopilot_fixture
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1; exit 0

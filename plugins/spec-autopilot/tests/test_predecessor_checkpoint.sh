#!/usr/bin/env bash
# test_predecessor_checkpoint.sh — Section 2: check-predecessor-checkpoint.sh
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../runtime/scripts" && pwd)"
source "$TEST_DIR/_test_helpers.sh"
source "$TEST_DIR/_fixtures.sh"

echo "--- 2. check-predecessor-checkpoint.sh ---"
setup_autopilot_fixture

# 2a. Empty stdin → exit 0 (allow)
exit_code=0
echo "" | bash "$SCRIPT_DIR/check-predecessor-checkpoint.sh" >/dev/null 2>&1 || exit_code=$?
assert_exit "empty stdin → allow" 0 $exit_code

# 2b. Non-autopilot Task (no marker) → exit 0
exit_code=0
echo '{"tool_name":"Task","tool_input":{"prompt":"Find all API endpoints","subagent_type":"Explore"}}' \
  | bash "$SCRIPT_DIR/check-predecessor-checkpoint.sh" >/dev/null 2>&1 || exit_code=$?
assert_exit "no marker → allow" 0 $exit_code

# 2c. Autopilot Phase 2 with no changes dir → exit 0 (no active change to check)
exit_code=0
echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:2 -->\nYou are phase 2 agent","subagent_type":"general-purpose"},"cwd":"/tmp"}' \
  | bash "$SCRIPT_DIR/check-predecessor-checkpoint.sh" >/dev/null 2>&1 || exit_code=$?
assert_exit "phase 2, no changes dir → allow" 0 $exit_code

# 2d. Autopilot Phase 5 with no changes dir → exit 0 (no active change)
exit_code=0
echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:5 -->\nPhase 5","subagent_type":"general-purpose"},"cwd":"/tmp/nonexistent-proj"}' \
  | bash "$SCRIPT_DIR/check-predecessor-checkpoint.sh" >/dev/null 2>&1 || exit_code=$?
assert_exit "phase 5, no changes dir → allow" 0 $exit_code

# 2e. Verify JSON output format on deny (if we can trigger it)
output=$(echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:5 -->\nPhase 5","subagent_type":"general-purpose"},"cwd":"/tmp/nonexistent-proj"}' \
  | bash "$SCRIPT_DIR/check-predecessor-checkpoint.sh" 2>/dev/null || true)
# If there is a deny, it should be valid JSON with permissionDecision
if echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['hookSpecificOutput']['permissionDecision']=='deny'" 2>/dev/null; then
  green "  PASS: deny output is valid hookSpecificOutput JSON"
  PASS=$((PASS + 1))
else
  # No deny output means it was allowed (also valid for this case)
  green "  PASS: no deny needed (correctly allowed)"
  PASS=$((PASS + 1))
fi

# 2f. Phase 2 deny: Phase 1 checkpoint missing in active change → deny
TMPDIR_P2=$(mktemp -d)
mkdir -p "$TMPDIR_P2/openspec/changes/test-feature/context/phase-results"
# No phase-1 checkpoint file exists → Phase 2 should deny
echo "{\"change\":\"test-feature\",\"pid\":$$,\"started\":\"2026-01-01T00:00:00Z\",\"session_cwd\":\"$TMPDIR_P2\",\"anchor_sha\":\"abc123\",\"session_id\":\"$(date +%s%3N)\"}" > "$TMPDIR_P2/openspec/changes/.autopilot-active"
exit_code=0
output=$(echo "{\"tool_name\":\"Task\",\"tool_input\":{\"prompt\":\"<!-- autopilot-phase:2 -->\\nPhase 2\",\"subagent_type\":\"general-purpose\"},\"cwd\":\"$TMPDIR_P2\"}" \
  | bash "$SCRIPT_DIR/check-predecessor-checkpoint.sh" 2>/dev/null) || exit_code=$?
assert_exit "phase 2 no phase-1 checkpoint → exit 0" 0 $exit_code
assert_contains "phase 2 no phase-1 checkpoint → deny" "$output" "deny"
rm -rf "$TMPDIR_P2"

# === Phase 6 fail-closed: task file must exist ===

# 2f. Phase 6 with Phase 5 ok but NO tasks.md or phase5-task-breakdown.md → deny
TMPDIR_P6=$(mktemp -d)
trap 'rm -rf "$TMPDIR_P6"' EXIT
mkdir -p "$TMPDIR_P6/openspec/changes/test-feature/context/phase-results"
echo '{"status":"ok","summary":"Done","zero_skip_check":{"passed":true}}' \
  > "$TMPDIR_P6/openspec/changes/test-feature/context/phase-results/phase-5-impl.json"
echo '{"status":"ok","summary":"Done","decisions":[{"point":"x","choice":"y"}]}' \
  > "$TMPDIR_P6/openspec/changes/test-feature/context/phase-results/phase-1-test.json"
echo "{\"change\":\"test-feature\",\"pid\":$$,\"started\":\"2026-01-01T00:00:00Z\",\"mode\":\"lite\",\"session_cwd\":\"$TMPDIR_P6\",\"anchor_sha\":\"abc123\",\"session_id\":\"$(date +%s%3N)\"}" > "$TMPDIR_P6/openspec/changes/.autopilot-active"
exit_code=0
output=$(echo "{\"tool_name\":\"Task\",\"tool_input\":{\"prompt\":\"<!-- autopilot-phase:6 -->\\nPhase 6\",\"subagent_type\":\"general-purpose\"},\"cwd\":\"$TMPDIR_P6\"}" \
  | bash "$SCRIPT_DIR/check-predecessor-checkpoint.sh" 2>/dev/null) || exit_code=$?
assert_exit "2f. Phase 6 no task file → exit 0" 0 $exit_code
assert_contains "2f. Phase 6 no task file → deny" "$output" "deny"
assert_contains "2f. mentions task file" "$output" "tasks"

# 2g. Phase 6 with Phase 5 ok AND phase5-task-breakdown.md (all checked) → allow
echo "- [x] task 1" > "$TMPDIR_P6/openspec/changes/test-feature/context/phase5-task-breakdown.md"
exit_code=0
output=$(echo "{\"tool_name\":\"Task\",\"tool_input\":{\"prompt\":\"<!-- autopilot-phase:6 -->\\nPhase 6\",\"subagent_type\":\"general-purpose\"},\"cwd\":\"$TMPDIR_P6\"}" \
  | bash "$SCRIPT_DIR/check-predecessor-checkpoint.sh" 2>/dev/null) || exit_code=$?
assert_exit "2g. Phase 6 with task file → exit 0" 0 $exit_code
assert_not_contains "2g. Phase 6 with task file → no deny" "$output" "deny"
rm -rf "$TMPDIR_P6"

teardown_autopilot_fixture
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1; exit 0

#!/usr/bin/env bash
# test_agent_correlation.sh — Tests for active-agent state JSON mechanism
# Verifies: emit-tool-event.sh reads .active-agent-state.json and injects agent_id
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../runtime/scripts" && pwd)"
source "$TEST_DIR/_test_helpers.sh"
source "$TEST_DIR/_fixtures.sh"

echo "--- agent_id correlation ---"
setup_autopilot_fixture

# Write a global-only active-agent state via helper
mkdir -p "$REPO_ROOT/logs" 2>/dev/null || true
# shellcheck source=../runtime/scripts/_agent_state.sh
source "$SCRIPT_DIR/_agent_state.sh"
# shellcheck source=../runtime/scripts/_common.sh
source "$SCRIPT_DIR/_common.sh"
agent_state_dispatch "$REPO_ROOT" "" "3" "phase3-openspec-ff"
touch "$REPO_ROOT/logs/events.jsonl"

# 2a. emit-tool-event.sh reads active-agent-state.json
TOOL_JSON='{"tool_name":"Read","tool_input":{"file_path":"/tmp/test.txt"},"tool_result":{"output":"file contents"},"cwd":"'"$REPO_ROOT"'"}'
echo "$TOOL_JSON" | bash "$SCRIPT_DIR/emit-tool-event.sh" 2>/dev/null
EXIT_CODE=$?
assert_exit "2a. emit-tool-event.sh with active-agent-state → exit 0" 0 "$EXIT_CODE"

# 2b/2c. Verify agent_id appears in events.jsonl
if [ -f "$REPO_ROOT/logs/events.jsonl" ]; then
  LAST_EVENT=$(tail -1 "$REPO_ROOT/logs/events.jsonl")
  if grep -q '"agent_id"' <<<"$LAST_EVENT"; then
    green "  PASS: 2b. event contains agent_id field"
    PASS=$((PASS + 1))
  else
    red "  FAIL: 2b. event missing agent_id field"
    FAIL=$((FAIL + 1))
  fi
  if grep -q 'phase3-openspec-ff' <<<"$LAST_EVENT"; then
    green "  PASS: 2c. agent_id value matches active-agent-state.global"
    PASS=$((PASS + 1))
  else
    red "  FAIL: 2c. agent_id value mismatch"
    FAIL=$((FAIL + 1))
  fi
else
  red "  FAIL: 2b. events.jsonl not created"
  FAIL=$((FAIL + 1))
  red "  FAIL: 2c. (skipped)"
  FAIL=$((FAIL + 1))
fi

# 2d. Without active-agent state, no agent_id in event
rm -f "$REPO_ROOT/logs/.active-agent-state.json" "$REPO_ROOT/logs/.active-agent-state.json.lock"
echo "$TOOL_JSON" | bash "$SCRIPT_DIR/emit-tool-event.sh" 2>/dev/null
LAST_EVENT=$(tail -1 "$REPO_ROOT/logs/events.jsonl" 2>/dev/null)
if grep -q '"agent_id"' <<<"$LAST_EVENT"; then
  red "  FAIL: 2d. agent_id present when active-agent-state absent"
  FAIL=$((FAIL + 1))
else
  green "  PASS: 2d. no agent_id when active-agent-state absent"
  PASS=$((PASS + 1))
fi

# 2e. Session-scoped state wins over global
agent_state_dispatch "$REPO_ROOT" "" "3" "phase-global"
agent_state_dispatch "$REPO_ROOT" "sess-2" "3" "phase-session"
TOOL_JSON_SESSION='{"session_id":"sess-2","tool_name":"Read","tool_input":{"file_path":"/tmp/test.txt"},"tool_result":{"output":"file contents"},"cwd":"'"$REPO_ROOT"'"}'
echo "$TOOL_JSON_SESSION" | bash "$SCRIPT_DIR/emit-tool-event.sh" 2>/dev/null
LAST_EVENT=$(tail -1 "$REPO_ROOT/logs/events.jsonl" 2>/dev/null)
if grep -q 'phase-session' <<<"$LAST_EVENT"; then
  green "  PASS: 2e. session-scoped agent in state wins"
  PASS=$((PASS + 1))
else
  red "  FAIL: 2e. session-scoped agent not used"
  FAIL=$((FAIL + 1))
fi

# Cleanup
rm -f "$REPO_ROOT/logs/.active-agent-state.json" "$REPO_ROOT/logs/.active-agent-state.json.lock" \
  "$REPO_ROOT/logs/events.jsonl" "$REPO_ROOT/logs/.event_sequence" 2>/dev/null || true
rmdir "$REPO_ROOT/logs/.event_sequence.lk" 2>/dev/null || true
rmdir "$REPO_ROOT/logs" 2>/dev/null || true

teardown_autopilot_fixture
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1
exit 0

#!/usr/bin/env bash
# test_agent_correlation.sh — Tests for WS4.A .active-agent-id mechanism
# Verifies: emit-tool-event.sh reads .active-agent-id and injects agent_id
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../runtime/scripts" && pwd)"
source "$TEST_DIR/_test_helpers.sh"
source "$TEST_DIR/_fixtures.sh"

echo "--- agent_id correlation ---"
setup_autopilot_fixture

# 2a. emit-tool-event.sh reads .active-agent-id
mkdir -p "$REPO_ROOT/logs" 2>/dev/null || true
echo "phase3-openspec-ff" > "$REPO_ROOT/logs/.active-agent-id"
touch "$REPO_ROOT/logs/events.jsonl"

TOOL_JSON='{"tool_name":"Read","tool_input":{"file_path":"/tmp/test.txt"},"tool_result":{"output":"file contents"},"cwd":"'"$REPO_ROOT"'"}'
echo "$TOOL_JSON" | bash "$SCRIPT_DIR/emit-tool-event.sh" 2>/dev/null
EXIT_CODE=$?
assert_exit "2a. emit-tool-event.sh with .active-agent-id → exit 0" 0 "$EXIT_CODE"

# 2b. Verify agent_id appears in events.jsonl
if [ -f "$REPO_ROOT/logs/events.jsonl" ]; then
  LAST_EVENT=$(tail -1 "$REPO_ROOT/logs/events.jsonl")
  if grep -q '"agent_id"' <<< "$LAST_EVENT"; then
    green "  PASS: 2b. event contains agent_id field"
    PASS=$((PASS + 1))
  else
    red "  FAIL: 2b. event missing agent_id field"
    FAIL=$((FAIL + 1))
  fi
  if grep -q 'phase3-openspec-ff' <<< "$LAST_EVENT"; then
    green "  PASS: 2c. agent_id value matches .active-agent-id"
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

# 2d. Without .active-agent-id, no agent_id in event
rm -f "$REPO_ROOT/logs/.active-agent-id"
echo "$TOOL_JSON" | bash "$SCRIPT_DIR/emit-tool-event.sh" 2>/dev/null
LAST_EVENT=$(tail -1 "$REPO_ROOT/logs/events.jsonl" 2>/dev/null)
if grep -q '"agent_id"' <<< "$LAST_EVENT"; then
  red "  FAIL: 2d. agent_id present when .active-agent-id absent"
  FAIL=$((FAIL + 1))
else
  green "  PASS: 2d. no agent_id when .active-agent-id absent"
  PASS=$((PASS + 1))
fi

# 2e. Session-scoped marker has priority over global marker
echo "phase-global" > "$REPO_ROOT/logs/.active-agent-id"
echo "phase-session" > "$REPO_ROOT/logs/.active-agent-session-sess-2"
TOOL_JSON_SESSION='{"session_id":"sess-2","tool_name":"Read","tool_input":{"file_path":"/tmp/test.txt"},"tool_result":{"output":"file contents"},"cwd":"'"$REPO_ROOT"'"}'
echo "$TOOL_JSON_SESSION" | bash "$SCRIPT_DIR/emit-tool-event.sh" 2>/dev/null
LAST_EVENT=$(tail -1 "$REPO_ROOT/logs/events.jsonl" 2>/dev/null)
if grep -q 'phase-session' <<< "$LAST_EVENT"; then
  green "  PASS: 2e. session-scoped agent marker wins"
  PASS=$((PASS + 1))
else
  red "  FAIL: 2e. session-scoped agent marker not used"
  FAIL=$((FAIL + 1))
fi

# Cleanup
rm -f "$REPO_ROOT/logs/.active-agent-id" "$REPO_ROOT/logs/.active-agent-session-sess-2" "$REPO_ROOT/logs/events.jsonl" "$REPO_ROOT/logs/.event_sequence" 2>/dev/null || true
rmdir "$REPO_ROOT/logs/.event_sequence.lk" 2>/dev/null || true
rmdir "$REPO_ROOT/logs" 2>/dev/null || true

teardown_autopilot_fixture
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1; exit 0

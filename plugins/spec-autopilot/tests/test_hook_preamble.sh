#!/usr/bin/env bash
# test_hook_preamble.sh — Section 32: _hook_preamble.sh unit tests
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../runtime/scripts" && pwd)"
source "$TEST_DIR/_test_helpers.sh"
source "$TEST_DIR/_fixtures.sh"

echo "--- 32. _hook_preamble.sh tests ---"

PREAMBLE_SCRIPT="$SCRIPT_DIR/_hook_preamble.sh"

# 32a. Empty stdin → exit 0 (no-op)
result=$(echo "" | bash "$PREAMBLE_SCRIPT" 2>/dev/null)
code=$?
assert_exit "32a. empty stdin → exit 0" 0 $code

# 32b. No active autopilot → exit 0 (Layer 0 bypass)
# We use a fake project root with no lock file
FAKE_JSON='{"tool_name":"Task","cwd":"/tmp/nonexistent-project-root-abc123","tool_input":{"prompt":"test"}}'
result=$(echo "$FAKE_JSON" | bash "$PREAMBLE_SCRIPT" 2>/dev/null)
code=$?
assert_exit "32b. no active autopilot → exit 0" 0 $code

# 32c. Valid stdin with active autopilot → exports SCRIPT_DIR
setup_autopilot_fixture
VALID_JSON="{\"tool_name\":\"Task\",\"cwd\":\"$REPO_ROOT\",\"tool_input\":{\"prompt\":\"test\"}}"
# Source preamble in subshell to test exports
result=$(echo "$VALID_JSON" | bash -c "
  source '$PREAMBLE_SCRIPT'
  echo \"\$SCRIPT_DIR\"
" 2>/dev/null) || true
if [ -n "$result" ] && [ -d "$result" ]; then
  green "  PASS: 32c. SCRIPT_DIR exported and valid"
  PASS=$((PASS + 1))
else
  red "  FAIL: 32c. SCRIPT_DIR not exported (got '$result')"
  FAIL=$((FAIL + 1))
fi

# 32d. PROJECT_ROOT_QUICK extracted from cwd field
result=$(echo "$VALID_JSON" | bash -c "
  source '$PREAMBLE_SCRIPT'
  echo \"\$PROJECT_ROOT_QUICK\"
" 2>/dev/null) || true
if [ "$result" = "$REPO_ROOT" ]; then
  green "  PASS: 32d. PROJECT_ROOT_QUICK = cwd"
  PASS=$((PASS + 1))
else
  red "  FAIL: 32d. PROJECT_ROOT_QUICK (got '$result', expected '$REPO_ROOT')"
  FAIL=$((FAIL + 1))
fi

# 32e. STDIN_DATA preserved for downstream hooks
result=$(echo "$VALID_JSON" | bash -c "
  source '$PREAMBLE_SCRIPT'
  echo \"\$STDIN_DATA\" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get(\"tool_name\",\"\"))' 2>/dev/null
" 2>/dev/null) || true
if [ "$result" = "Task" ]; then
  green "  PASS: 32e. STDIN_DATA contains tool_name"
  PASS=$((PASS + 1))
else
  red "  FAIL: 32e. STDIN_DATA (got '$result')"
  FAIL=$((FAIL + 1))
fi

teardown_autopilot_fixture
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1; exit 0

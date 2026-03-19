#!/usr/bin/env bash
# test_e2e_hook_chain.sh — E2E: Complete Phase 0→1 hook call chain
# Verifies that the hook infrastructure works end-to-end:
#   _hook_preamble.sh → _common.sh → _post_task_validator.py
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../runtime/scripts" && pwd)"
source "$TEST_DIR/_test_helpers.sh"
source "$TEST_DIR/_fixtures.sh"

echo "--- E2E-1. Hook chain integration tests ---"
setup_autopilot_fixture

# E2E-1a. Full hook chain: valid Phase 2 Task → passes all hooks
VALID_PROMPT="<!-- autopilot-phase:2 --> Create OpenSpec for test feature"
VALID_RESPONSE='{"status":"ok","summary":"Created OpenSpec change: test-feature","artifacts":["openspec/changes/test-feature/proposal.md"]}'
HOOK_INPUT="{\"tool_name\":\"Task\",\"cwd\":\"$REPO_ROOT\",\"tool_input\":{\"prompt\":\"$VALID_PROMPT\"},\"tool_response\":\"$VALID_RESPONSE\"}"

export SCRIPT_DIR
result=$(echo "$HOOK_INPUT" | python3 "$SCRIPT_DIR/_post_task_validator.py" 2>/dev/null)
if [ -z "$result" ] || ! echo "$result" | grep -q '"block"'; then
  green "  PASS: E2E-1a. valid Phase 2 Task passes full hook chain"
  PASS=$((PASS + 1))
else
  red "  FAIL: E2E-1a. valid Phase 2 Task blocked: $result"
  FAIL=$((FAIL + 1))
fi

# E2E-1b. Full hook chain: missing envelope → block with reason
BAD_PROMPT="<!-- autopilot-phase:3 --> Generate FF artifacts"
BAD_RESPONSE="I completed the task successfully but forgot the JSON envelope."
HOOK_INPUT="{\"tool_name\":\"Task\",\"cwd\":\"$REPO_ROOT\",\"tool_input\":{\"prompt\":\"$BAD_PROMPT\"},\"tool_response\":\"$BAD_RESPONSE\"}"

result=$(echo "$HOOK_INPUT" | python3 "$SCRIPT_DIR/_post_task_validator.py" 2>/dev/null)
assert_contains "E2E-1b. missing envelope → block" "$result" "block"
assert_contains "E2E-1b. block reason mentions JSON" "$result" "JSON"

# E2E-1c. Non-autopilot Task (no phase marker) → passes without validation
NORMAL_PROMPT="Research the best authentication library for Node.js"
NORMAL_RESPONSE="I recommend passport.js for its flexibility."
HOOK_INPUT="{\"tool_name\":\"Task\",\"cwd\":\"$REPO_ROOT\",\"tool_input\":{\"prompt\":\"$NORMAL_PROMPT\"},\"tool_response\":\"$NORMAL_RESPONSE\"}"

result=$(echo "$HOOK_INPUT" | python3 "$SCRIPT_DIR/_post_task_validator.py" 2>/dev/null)
if [ -z "$result" ]; then
  green "  PASS: E2E-1c. non-autopilot Task → no validation"
  PASS=$((PASS + 1))
else
  red "  FAIL: E2E-1c. non-autopilot Task got output: $result"
  FAIL=$((FAIL + 1))
fi

# E2E-1d. Layer 0 bypass: _hook_preamble exits early when no autopilot session
teardown_autopilot_fixture
PREAMBLE_INPUT="{\"tool_name\":\"Write\",\"cwd\":\"/tmp/no-autopilot-here\",\"tool_input\":{\"file_path\":\"/tmp/test.txt\",\"content\":\"hello\"}}"
result=$(echo "$PREAMBLE_INPUT" | bash "$SCRIPT_DIR/_hook_preamble.sh" 2>/dev/null)
code=$?
assert_exit "E2E-1d. no autopilot → preamble exit 0" 0 $code

# E2E-1e. Anti-rationalization chain: Phase 5 with excuse patterns
setup_autopilot_fixture
EXCUSE_OUTPUT='{"status":"ok","summary":"Partially implemented","artifacts":["src/auth.ts"],"test_results_path":"tests/","tasks_completed":3,"zero_skip_check":{"passed":true}} I skipped the OAuth integration because it was too complex and deferred to a future sprint. The tests were skipped because the environment was not ready.'
result=$(python3 -c "
import json, sys, subprocess
prompt = '<!-- autopilot-phase:5 --> Implement user authentication'
data = {
    'tool_name': 'Task',
    'cwd': sys.argv[1],
    'tool_input': {'prompt': prompt},
    'tool_response': sys.argv[2]
}
proc = subprocess.run(
    [sys.executable, sys.argv[3]],
    input=json.dumps(data),
    capture_output=True, text=True, timeout=30
)
if proc.stdout.strip():
    print(proc.stdout.strip())
" "$REPO_ROOT" "$EXCUSE_OUTPUT" "$SCRIPT_DIR/_post_task_validator.py" 2>/dev/null) || true
assert_contains "E2E-1e. anti-rationalization catches excuses" "$result" "block"

teardown_autopilot_fixture
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1; exit 0

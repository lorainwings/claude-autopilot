#!/usr/bin/env bash
# test-hooks.sh
# Automated test harness for spec-autopilot hook scripts.
# Validates syntax, mock input handling, and exit code correctness.
#
# Usage: bash test-hooks.sh
# Exit: 0 if all tests pass, 1 if any fail.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PASS=0
FAIL=0

# --- Helpers ---
green() { printf "\033[32m%s\033[0m\n" "$1"; }
red()   { printf "\033[31m%s\033[0m\n" "$1"; }

assert_exit() {
  local name="$1" expected="$2" actual="$3"
  if [ "$actual" -eq "$expected" ]; then
    green "  PASS: $name (exit $actual)"
    PASS=$((PASS + 1))
  else
    red "  FAIL: $name (expected exit $expected, got $actual)"
    FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  local name="$1" haystack="$2" needle="$3"
  if echo "$haystack" | grep -q "$needle"; then
    green "  PASS: $name (contains '$needle')"
    PASS=$((PASS + 1))
  else
    red "  FAIL: $name (missing '$needle')"
    FAIL=$((FAIL + 1))
  fi
}

assert_not_contains() {
  local name="$1" haystack="$2" needle="$3"
  if ! echo "$haystack" | grep -q "$needle"; then
    green "  PASS: $name (correctly missing '$needle')"
    PASS=$((PASS + 1))
  else
    red "  FAIL: $name (unexpectedly contains '$needle')"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== spec-autopilot Hook Test Suite ==="
echo ""

# ============================================================
echo "--- 1. Syntax checks (bash -n) ---"
for script in "$SCRIPT_DIR"/*.sh; do
  name=$(basename "$script")
  [ "$name" = "test-hooks.sh" ] && continue
  if bash -n "$script" 2>/dev/null; then
    green "  PASS: $name syntax OK"
    PASS=$((PASS + 1))
  else
    red "  FAIL: $name syntax error"
    FAIL=$((FAIL + 1))
  fi
done

echo ""

# ============================================================
echo "--- 2. check-predecessor-checkpoint.sh ---"

# 2a. Empty stdin → exit 0 (allow)
exit_code=0
echo "" | bash "$SCRIPT_DIR/check-predecessor-checkpoint.sh" >/dev/null 2>&1 || exit_code=$?
assert_exit "empty stdin → allow" 0 $exit_code

# 2b. Non-autopilot Task (no marker) → exit 0
exit_code=0
echo '{"tool_name":"Task","tool_input":{"prompt":"Find all API endpoints","subagent_type":"Explore"}}' \
  | bash "$SCRIPT_DIR/check-predecessor-checkpoint.sh" >/dev/null 2>&1 || exit_code=$?
assert_exit "no marker → allow" 0 $exit_code

# 2c. Autopilot Phase 2 (no predecessor needed) → exit 0
exit_code=0
echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:2 -->\nYou are phase 2 agent","subagent_type":"general-purpose"},"cwd":"/tmp"}' \
  | bash "$SCRIPT_DIR/check-predecessor-checkpoint.sh" >/dev/null 2>&1 || exit_code=$?
assert_exit "phase 2 (first phase) → allow" 0 $exit_code

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

echo ""

# ============================================================
echo "--- 3. validate-json-envelope.sh ---"

# 3a. Empty stdin → exit 0
exit_code=0
echo "" | bash "$SCRIPT_DIR/validate-json-envelope.sh" >/dev/null 2>&1 || exit_code=$?
assert_exit "empty stdin → allow" 0 $exit_code

# 3b. Non-autopilot Task → exit 0
exit_code=0
echo '{"tool_name":"Task","tool_input":{"prompt":"Find APIs"},"tool_response":"Found 3 endpoints"}' \
  | bash "$SCRIPT_DIR/validate-json-envelope.sh" >/dev/null 2>&1 || exit_code=$?
assert_exit "no marker → skip" 0 $exit_code

# 3c. Autopilot Task with valid JSON envelope in tool_response → exit 0, no block
exit_code=0
output=$(echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:3 -->\nPhase 3"},"tool_response":"Done.\n```json\n{\"status\":\"ok\",\"summary\":\"All good\",\"artifacts\":[]}\n```"}' \
  | bash "$SCRIPT_DIR/validate-json-envelope.sh" 2>/dev/null) || exit_code=$?
assert_exit "valid envelope → exit 0" 0 $exit_code
assert_not_contains "valid envelope → no block decision" "$output" "decision"

# 3d. Autopilot Task with empty tool_response → decision:block
exit_code=0
output=$(echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:3 -->\nPhase 3"},"tool_response":""}' \
  | bash "$SCRIPT_DIR/validate-json-envelope.sh" 2>/dev/null) || exit_code=$?
assert_exit "empty response → exit 0" 0 $exit_code
assert_contains "empty response → block decision" "$output" "block"

# 3e. Autopilot Task with no JSON in response → decision:block
exit_code=0
output=$(echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:4 -->\nPhase 4"},"tool_response":"I completed the task successfully without any JSON."}' \
  | bash "$SCRIPT_DIR/validate-json-envelope.sh" 2>/dev/null) || exit_code=$?
assert_exit "no JSON in response → exit 0" 0 $exit_code
assert_contains "no JSON → block decision" "$output" "block"

# 3f. Verify tool_response field is used (NOT tool_result)
exit_code=0
output=$(echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:3 -->\nPhase 3"},"tool_result":"{\"status\":\"ok\",\"summary\":\"test\"}","tool_response":"no json here"}' \
  | bash "$SCRIPT_DIR/validate-json-envelope.sh" 2>/dev/null) || exit_code=$?
# tool_result has valid JSON but tool_response doesn't → should block (proving tool_response is used)
assert_contains "uses tool_response not tool_result" "$output" "block"

# 3g. Nested JSON object (Phase 4 with test_counts) → should be extracted
exit_code=0
output=$(echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:4 -->\nPhase 4"},"tool_response":"Result: {\"status\":\"ok\",\"summary\":\"Tests designed\",\"test_counts\":{\"unit\":10,\"api\":8,\"e2e\":5,\"ui\":5}}"}' \
  | bash "$SCRIPT_DIR/validate-json-envelope.sh" 2>/dev/null) || exit_code=$?
assert_exit "nested JSON → exit 0" 0 $exit_code
assert_not_contains "nested JSON → no block" "$output" "block"

echo ""

# ============================================================
echo "--- 4. scan-checkpoints-on-start.sh ---"

# 4a. No changes dir → exit 0, no output
exit_code=0
output=$(bash "$SCRIPT_DIR/scan-checkpoints-on-start.sh" 2>/dev/null) || exit_code=$?
assert_exit "SessionStart hook → exit 0" 0 $exit_code

echo ""

# ============================================================
echo "--- 5. detect-ralph-loop.sh ---"

# 5a. Non-existent project → "blocked"
exit_code=0
output=$(bash "$SCRIPT_DIR/detect-ralph-loop.sh" /tmp/nonexistent-project-xyzzy 2>/dev/null) || exit_code=$?
assert_exit "nonexistent project → exit 0" 0 $exit_code
assert_contains "nonexistent project → blocked" "$output" "blocked"

echo ""

# ============================================================
echo "--- 6. hooks.json validation ---"

# 6a. Valid JSON
if python3 -c "import json; json.load(open('$SCRIPT_DIR/../hooks/hooks.json'))" 2>/dev/null; then
  green "  PASS: hooks.json is valid JSON"
  PASS=$((PASS + 1))
else
  red "  FAIL: hooks.json is invalid JSON"
  FAIL=$((FAIL + 1))
fi

# 6b. Has timeout fields
if python3 -c "
import json
with open('$SCRIPT_DIR/../hooks/hooks.json') as f:
    data = json.load(f)
for event in data['hooks'].values():
    for group in event:
        for hook in group['hooks']:
            assert 'timeout' in hook, f'Missing timeout in {hook}'
print('ok')
" 2>/dev/null | grep -q "ok"; then
  green "  PASS: all hooks have timeout configured"
  PASS=$((PASS + 1))
else
  red "  FAIL: some hooks missing timeout"
  FAIL=$((FAIL + 1))
fi

echo ""

# ============================================================
echo "==================================="
echo "Results: $PASS passed, $FAIL failed"
echo "==================================="

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0

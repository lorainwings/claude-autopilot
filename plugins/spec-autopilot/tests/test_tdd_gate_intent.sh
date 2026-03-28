#!/usr/bin/env bash
# test_tdd_gate_intent.sh — WS-E: TDD test_intent and failing_signal gate enforcement
# Verifies:
#   1. TDD checkpoint without test_intent is detectable as a governance gap
#   2. TDD checkpoint with valid test_intent and failing_signal is compliant
#   3. The tdd-cycle.md protocol documents test_intent as a gate requirement
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../runtime/scripts" && pwd)"
PLUGIN_ROOT="$(cd "$TEST_DIR/.." && pwd)"
source "$TEST_DIR/_test_helpers.sh"

echo "--- WS-E: TDD test_intent and failing_signal gate ---"

# Self-contained temp directory
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# === 1. Verify tdd-cycle.md documents test_intent ===
TDD_DOC="$PLUGIN_ROOT/skills/autopilot/references/tdd-cycle.md"
if [ -f "$TDD_DOC" ]; then
  tdd_content=$(cat "$TDD_DOC")
  assert_contains "1a. tdd-cycle.md documents test_intent" "$tdd_content" "test_intent"
  assert_contains "1b. tdd-cycle.md documents failing_signal" "$tdd_content" "failing_signal"
  assert_contains "1c. tdd-cycle.md documents assertion_message" "$tdd_content" "assertion_message"
  assert_contains "1d. tdd-cycle.md has gate enforcement section" "$tdd_content" "门禁"
else
  red "  FAIL: 1. tdd-cycle.md not found"
  FAIL=$((FAIL + 4))
fi

# === 2. Verify phase5-implementation.md includes test_intent in checkpoint format ===
PHASE5_DOC="$PLUGIN_ROOT/skills/autopilot/references/phase5-implementation.md"
if [ -f "$PHASE5_DOC" ]; then
  p5_content=$(cat "$PHASE5_DOC")
  assert_contains "2a. phase5 doc includes test_intent in checkpoint" "$p5_content" "test_intent"
  assert_contains "2b. phase5 doc includes failing_signal in checkpoint" "$p5_content" "failing_signal"
else
  red "  FAIL: 2. phase5-implementation.md not found"
  FAIL=$((FAIL + 2))
fi

# === 3. Validate TDD checkpoint structure with test_intent ===
mkdir -p "$TMPDIR/phase5-tasks"
# 3a. Valid checkpoint with test_intent and failing_signal
cat > "$TMPDIR/phase5-tasks/task-1.json" << 'TASK'
{
  "task_number": 1,
  "task_title": "实现用户登录",
  "status": "ok",
  "tdd_cycle": {
    "test_intent": "UserService.login() 在密码错误时返回 401 (sad-path)",
    "failing_signal": {
      "exit_code": 1,
      "assertion_message": "AssertionError: expected 401 but got undefined",
      "test_file": "tests/test_login.py"
    },
    "red": {"verified": true},
    "green": {"verified": true},
    "refactor": {"verified": true}
  },
  "artifacts": ["src/login.py"]
}
TASK

# Verify JSON is valid and has required fields
output=$(python3 -c "
import json, sys
with open('$TMPDIR/phase5-tasks/task-1.json') as f:
    data = json.load(f)
tdd = data.get('tdd_cycle', {})
checks = {
    'has_test_intent': bool(tdd.get('test_intent')),
    'has_failing_signal': bool(tdd.get('failing_signal')),
    'has_assertion_message': bool(tdd.get('failing_signal', {}).get('assertion_message')),
    'red_verified': tdd.get('red', {}).get('verified', False),
    'green_verified': tdd.get('green', {}).get('verified', False),
}
print(json.dumps(checks))
" 2>/dev/null)
assert_contains "3a. valid checkpoint has test_intent" "$output" '"has_test_intent": true'
assert_contains "3b. valid checkpoint has failing_signal" "$output" '"has_failing_signal": true'
assert_contains "3c. valid checkpoint has assertion_message" "$output" '"has_assertion_message": true'

# 3d. Checkpoint without test_intent → detectable gap
cat > "$TMPDIR/phase5-tasks/task-2.json" << 'TASK'
{
  "task_number": 2,
  "task_title": "实现注册功能",
  "status": "ok",
  "tdd_cycle": {
    "red": {"verified": true},
    "green": {"verified": true}
  },
  "artifacts": ["src/register.py"]
}
TASK

output=$(python3 -c "
import json, sys
with open('$TMPDIR/phase5-tasks/task-2.json') as f:
    data = json.load(f)
tdd = data.get('tdd_cycle', {})
has_intent = bool(tdd.get('test_intent'))
has_signal = bool(tdd.get('failing_signal'))
print(json.dumps({'missing_intent': not has_intent, 'missing_signal': not has_signal}))
" 2>/dev/null)
assert_contains "3d. checkpoint without test_intent detected" "$output" '"missing_intent": true'
assert_contains "3e. checkpoint without failing_signal detected" "$output" '"missing_signal": true'

# === 4. Batch TDD audit: validate all tasks in phase5-tasks/ ===
output=$(python3 -c "
import json, sys, glob, os
tasks_dir = '$TMPDIR/phase5-tasks'
violations = []
for f in sorted(glob.glob(os.path.join(tasks_dir, 'task-*.json'))):
    with open(f) as fh:
        data = json.load(fh)
    tdd = data.get('tdd_cycle', {})
    task_num = data.get('task_number', '?')
    if tdd:
        if not tdd.get('test_intent'):
            violations.append(f'task-{task_num}: missing test_intent')
        if not tdd.get('failing_signal'):
            violations.append(f'task-{task_num}: missing failing_signal')
        elif not tdd.get('failing_signal', {}).get('assertion_message'):
            violations.append(f'task-{task_num}: failing_signal missing assertion_message')
print(json.dumps({'violations': violations, 'count': len(violations)}))
" 2>/dev/null)
assert_contains "4a. batch audit detects violations" "$output" '"count": 2'
assert_contains "4b. task-2 missing test_intent flagged" "$output" 'task-2: missing test_intent'
assert_contains "4c. task-2 missing failing_signal flagged" "$output" 'task-2: missing failing_signal'

echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1; exit 0

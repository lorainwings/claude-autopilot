#!/usr/bin/env bash
# test_hooks_json.sh — Section 6: hooks.json validation
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../runtime/scripts" && pwd)"
source "$TEST_DIR/_test_helpers.sh"
source "$TEST_DIR/_fixtures.sh"

echo "--- 6. hooks.json validation ---"
setup_autopilot_fixture

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

# 6c. Matcher uses ^Task$ (exact match, not substring)
if python3 -c "
import json, re
with open('$SCRIPT_DIR/../hooks/hooks.json') as f:
    data = json.load(f)
for event_name in ['PreToolUse', 'PostToolUse']:
    for group in data['hooks'][event_name]:
        m = group.get('matcher', '')
        # Only check Task-related matchers (skip Write|Edit etc.)
        if not m or 'Task' not in m:
            continue
        # Verify matcher only matches 'Task', not 'TaskCreate' etc.
        assert re.fullmatch(m, 'Task'), f'{event_name} matcher {m!r} does not match Task'
        assert not re.search(m, 'TaskCreate'), f'{event_name} matcher {m!r} also matches TaskCreate!'
        assert not re.search(m, 'TaskUpdate'), f'{event_name} matcher {m!r} also matches TaskUpdate!'
print('ok')
" 2>/dev/null | grep -q "ok"; then
  green "  PASS: matchers use exact ^Task\$ (no collision with TaskCreate/TaskUpdate)"
  PASS=$((PASS + 1))
else
  red "  FAIL: matchers collide with TaskCreate/TaskUpdate/etc."
  FAIL=$((FAIL + 1))
fi

# 6d. Plugin version is > 1.0.0
if python3 -c "
import json
with open('$SCRIPT_DIR/../.claude-plugin/plugin.json') as f:
    data = json.load(f)
v = data.get('version', '0.0.0')
major, minor, patch = (int(x) for x in v.split('.'))
assert (major, minor, patch) > (1, 0, 0), f'Version {v} not bumped from 1.0.0'
print('ok')
" 2>/dev/null | grep -q "ok"; then
  green "  PASS: plugin.json version bumped (> 1.0.0)"
  PASS=$((PASS + 1))
else
  red "  FAIL: plugin.json version still 1.0.0"
  FAIL=$((FAIL + 1))
fi

teardown_autopilot_fixture
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1; exit 0

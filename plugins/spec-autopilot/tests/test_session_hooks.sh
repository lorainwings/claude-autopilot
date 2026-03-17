#!/usr/bin/env bash
# test_session_hooks.sh — Sections 10+11: SessionStart async + PreCompact/reinject hooks
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../scripts" && pwd)"
source "$TEST_DIR/_test_helpers.sh"
source "$TEST_DIR/_fixtures.sh"

echo "--- 10. SessionStart async configuration ---"
setup_autopilot_fixture

# 10a. hooks.json SessionStart scan-checkpoints hook has async: true
if python3 -c "
import json
with open('$SCRIPT_DIR/../hooks/hooks.json') as f:
    data = json.load(f)
# scan-checkpoints hook must remain async even if other capture hooks share the same group
scan_groups = [g for g in data['hooks']['SessionStart'] if 'matcher' not in g]
assert scan_groups, 'Missing default SessionStart group'
hooks = [hook for group in scan_groups for hook in group['hooks']]
scan_hooks = [hook for hook in hooks if 'scan-checkpoints-on-start.sh' in hook.get('command', '')]
assert len(scan_hooks) == 1, f'Expected exactly one scan-checkpoints hook, got {len(scan_hooks)}'
assert scan_hooks[0].get('async') is True, 'scan-checkpoints hook missing async: true'
print('ok')
" 2>/dev/null | grep -q "ok"; then
  green "  PASS: SessionStart scan-checkpoints hook has async: true"
  PASS=$((PASS + 1))
else
  red "  FAIL: SessionStart scan-checkpoints hook missing async: true"
  FAIL=$((FAIL + 1))
fi

echo ""

# ============================================================
echo "--- 11. PreCompact + SessionStart(compact) hooks ---"

# 11a. hooks.json has PreCompact section
if python3 -c "
import json
with open('$SCRIPT_DIR/../hooks/hooks.json') as f:
    data = json.load(f)
assert 'PreCompact' in data['hooks'], 'Missing PreCompact hook'
assert len(data['hooks']['PreCompact']) > 0, 'PreCompact has no groups'
print('ok')
" 2>/dev/null | grep -q "ok"; then
  green "  PASS: hooks.json has PreCompact hook"
  PASS=$((PASS + 1))
else
  red "  FAIL: hooks.json missing PreCompact hook"
  FAIL=$((FAIL + 1))
fi

# 11b. SessionStart has a compact matcher group
if python3 -c "
import json
with open('$SCRIPT_DIR/../hooks/hooks.json') as f:
    data = json.load(f)
compact_groups = [g for g in data['hooks']['SessionStart'] if g.get('matcher') == 'compact']
assert len(compact_groups) == 1, f'Expected 1 compact group, got {len(compact_groups)}'
# Compact reinject must NOT be async (needs to feed stdout into context)
for hook in compact_groups[0]['hooks']:
    assert hook.get('async') is not True, 'compact reinject hook must be synchronous'
print('ok')
" 2>/dev/null | grep -q "ok"; then
  green "  PASS: SessionStart(compact) hook is synchronous"
  PASS=$((PASS + 1))
else
  red "  FAIL: SessionStart(compact) hook misconfigured"
  FAIL=$((FAIL + 1))
fi

# 11c. save-state-before-compact.sh syntax check
if bash -n "$SCRIPT_DIR/save-state-before-compact.sh" 2>/dev/null; then
  green "  PASS: save-state-before-compact.sh syntax OK"
  PASS=$((PASS + 1))
else
  red "  FAIL: save-state-before-compact.sh syntax error"
  FAIL=$((FAIL + 1))
fi

# 11d. reinject-state-after-compact.sh syntax check
if bash -n "$SCRIPT_DIR/reinject-state-after-compact.sh" 2>/dev/null; then
  green "  PASS: reinject-state-after-compact.sh syntax OK"
  PASS=$((PASS + 1))
else
  red "  FAIL: reinject-state-after-compact.sh syntax error"
  FAIL=$((FAIL + 1))
fi

# 11e. save-state script exits 0 with no changes dir
exit_code=0
bash "$SCRIPT_DIR/save-state-before-compact.sh" </dev/null >/dev/null 2>&1 || exit_code=$?
assert_exit "save-state no changes → exit 0" 0 $exit_code

# 11f. reinject-state script exits 0 with no state file
exit_code=0
output=$(cd /tmp && bash "$SCRIPT_DIR/reinject-state-after-compact.sh" 2>/dev/null) || exit_code=$?
assert_exit "reinject-state no state file → exit 0" 0 $exit_code

teardown_autopilot_fixture
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1; exit 0

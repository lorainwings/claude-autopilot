#!/usr/bin/env bash
# test_reference_files.sh — Section 30: v3.2.0 reference files existence
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../scripts" && pwd)"
source "$TEST_DIR/_test_helpers.sh"
source "$TEST_DIR/_fixtures.sh"

echo "--- 30. v3.2.0 reference files existence ---"
setup_autopilot_fixture

# 30a. parallel-dispatch.md exists
if [ -f "$SCRIPT_DIR/../skills/autopilot/references/parallel-dispatch.md" ]; then
  green "  PASS: parallel-dispatch.md exists"
  PASS=$((PASS + 1))
else
  red "  FAIL: parallel-dispatch.md not found"
  FAIL=$((FAIL + 1))
fi

# 30b. parallel-phase-dispatch.md merged into parallel-dispatch.md (v4.1)
if [ ! -f "$SCRIPT_DIR/../skills/autopilot/references/parallel-phase-dispatch.md" ]; then
  green "  PASS: parallel-phase-dispatch.md removed (merged into parallel-dispatch.md)"
  PASS=$((PASS + 1))
else
  red "  FAIL: parallel-phase-dispatch.md should have been merged and removed"
  FAIL=$((FAIL + 1))
fi

# 30c. config-schema.md exists
if [ -f "$SCRIPT_DIR/../skills/autopilot/references/config-schema.md" ]; then
  green "  PASS: config-schema.md exists"
  PASS=$((PASS + 1))
else
  red "  FAIL: config-schema.md not found"
  FAIL=$((FAIL + 1))
fi

# 30d. phase1-supplementary.md exists
if [ -f "$SCRIPT_DIR/../skills/autopilot/references/phase1-supplementary.md" ]; then
  green "  PASS: phase1-supplementary.md exists"
  PASS=$((PASS + 1))
else
  red "  FAIL: phase1-supplementary.md not found"
  FAIL=$((FAIL + 1))
fi

# 30e. plugin.json version >= 3.2.0
if python3 -c "
import json
with open('$SCRIPT_DIR/../.claude-plugin/plugin.json') as f:
    data = json.load(f)
v = data.get('version', '0.0.0')
major, minor, patch = (int(x) for x in v.split('.'))
assert (major, minor, patch) >= (3, 2, 0), f'Version {v} < 3.2.0'
print('ok')
" 2>/dev/null | grep -q "ok"; then
  green "  PASS: plugin.json version >= 3.2.0"
  PASS=$((PASS + 1))
else
  red "  FAIL: plugin.json version < 3.2.0"
  FAIL=$((FAIL + 1))
fi

teardown_autopilot_fixture
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1; exit 0

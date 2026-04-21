#!/usr/bin/env bash
# TEST_LAYER: contract
# test_reference_files.sh — Reference directory contract
#   合并自:
#     - 旧 Section 30 (v3.2.0 reference files existence): 本文件原内容
#     - 旧 Section 15 (references/ directory structure): 已迁入 "Section A: directory structure"
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../runtime/scripts" && pwd)"
source "$TEST_DIR/_test_helpers.sh"
source "$TEST_DIR/_fixtures.sh"

echo "--- Reference directory contract ---"
setup_autopilot_fixture

# === Section A: references/ directory structure (原 test_references_dir.sh §15) ===

# A1 (原 15a). protocol.md is in autopilot/references/ (official pattern)
if [ -f "$SCRIPT_DIR/../../skills/autopilot/references/protocol.md" ]; then
  green "  PASS: A1: protocol.md in autopilot/references/ (official pattern)"
  PASS=$((PASS + 1))
else
  red "  FAIL: A1: protocol.md not found in autopilot/references/"
  FAIL=$((FAIL + 1))
fi

# A2 (原 15b). No leftover shared/ directory
if [ ! -d "$SCRIPT_DIR/../../skills/shared" ]; then
  green "  PASS: A2: no leftover skills/shared/ directory"
  PASS=$((PASS + 1))
else
  red "  FAIL: A2: skills/shared/ directory still exists (should be migrated)"
  FAIL=$((FAIL + 1))
fi

# === Section B: v3.2.0 reference files existence (原 §30) ===

# B1 (原 30a). parallel-dispatch.md exists
if [ -f "$SCRIPT_DIR/../../skills/autopilot/references/parallel-dispatch.md" ]; then
  green "  PASS: B1: parallel-dispatch.md exists"
  PASS=$((PASS + 1))
else
  red "  FAIL: B1: parallel-dispatch.md not found"
  FAIL=$((FAIL + 1))
fi

# B2 (原 30b). parallel-phase-dispatch.md merged into parallel-dispatch.md (v4.1)
if [ ! -f "$SCRIPT_DIR/../../skills/autopilot/references/parallel-phase-dispatch.md" ]; then
  green "  PASS: B2: parallel-phase-dispatch.md removed (merged into parallel-dispatch.md)"
  PASS=$((PASS + 1))
else
  red "  FAIL: B2: parallel-phase-dispatch.md should have been merged and removed"
  FAIL=$((FAIL + 1))
fi

# B3 (原 30c). config-schema.md exists
if [ -f "$SCRIPT_DIR/../../skills/autopilot-setup/references/config-schema.md" ]; then
  green "  PASS: B3: config-schema.md exists"
  PASS=$((PASS + 1))
else
  red "  FAIL: B3: config-schema.md not found"
  FAIL=$((FAIL + 1))
fi

# B4 (原 30d). phase1-supplementary.md exists
if [ -f "$SCRIPT_DIR/../../skills/autopilot-phase1-requirements/references/phase1-supplementary.md" ]; then
  green "  PASS: B4: phase1-supplementary.md exists"
  PASS=$((PASS + 1))
else
  red "  FAIL: B4: phase1-supplementary.md not found"
  FAIL=$((FAIL + 1))
fi

# B5 (原 30e). plugin.json version >= 3.2.0
if python3 -c "
import json
with open('$SCRIPT_DIR/../../.claude-plugin/plugin.json') as f:
    data = json.load(f)
v = data.get('version', '0.0.0')
major, minor, patch = (int(x) for x in v.split('.'))
assert (major, minor, patch) >= (3, 2, 0), f'Version {v} < 3.2.0'
print('ok')
" 2>/dev/null | grep -q "ok"; then
  green "  PASS: B5: plugin.json version >= 3.2.0"
  PASS=$((PASS + 1))
else
  red "  FAIL: B5: plugin.json version < 3.2.0"
  FAIL=$((FAIL + 1))
fi

teardown_autopilot_fixture
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1
exit 0

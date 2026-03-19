#!/usr/bin/env bash
# test_references_dir.sh — Section 15: references/ directory structure
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../runtime/scripts" && pwd)"
source "$TEST_DIR/_test_helpers.sh"
source "$TEST_DIR/_fixtures.sh"

echo "--- 15. references/ directory structure ---"
setup_autopilot_fixture

# 15a. protocol.md is in autopilot/references/ (official pattern)
if [ -f "$SCRIPT_DIR/../../skills/autopilot/references/protocol.md" ]; then
  green "  PASS: protocol.md in autopilot/references/ (official pattern)"
  PASS=$((PASS + 1))
else
  red "  FAIL: protocol.md not found in autopilot/references/"
  FAIL=$((FAIL + 1))
fi

# 15b. No leftover shared/ directory
if [ ! -d "$SCRIPT_DIR/../../skills/shared" ]; then
  green "  PASS: no leftover skills/shared/ directory"
  PASS=$((PASS + 1))
else
  red "  FAIL: skills/shared/ directory still exists (should be migrated)"
  FAIL=$((FAIL + 1))
fi

teardown_autopilot_fixture
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1; exit 0

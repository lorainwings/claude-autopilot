#!/usr/bin/env bash
# test_skill_lockfile_path.sh — Section 50: SKILL.md lockfile path uses absolute path
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../runtime/scripts" && pwd)"
source "$TEST_DIR/_test_helpers.sh"
source "$TEST_DIR/_fixtures.sh"

echo "--- 50. SKILL.md lockfile path uses absolute path (v3.3.4 regression) ---"
setup_autopilot_fixture

SKILL_FILE="$SCRIPT_DIR/../../skills/autopilot/SKILL.md"
LOCKFILE_FILE="$SCRIPT_DIR/../../skills/autopilot-phase0-init/SKILL.md"
RECOVERY_FILE="$SCRIPT_DIR/../../skills/autopilot-recovery/SKILL.md"
GATE_FILE="$SCRIPT_DIR/../../skills/autopilot-gate/SKILL.md"

# 50a: Lockfile skill must contain ${session_cwd} absolute path (v3.5.0: moved from main SKILL to lockfile skill)
lockfile_path_line=$(grep 'openspec/changes/\.autopilot-active' "$LOCKFILE_FILE" | head -1 || true)
assert_contains "50a: Step 7 lock write uses absolute path" "$lockfile_path_line" '\${session_cwd}'

# 50b: Lockfile skill must document the absolute path (v3.5.0: path is in 锁文件路径 section)
lockfile_path_section=$(grep '\${session_cwd}/openspec/changes/\.autopilot-active' "$LOCKFILE_FILE" | head -1 || true)
assert_contains "50b: Step 7 has relative path prohibition" "$lockfile_path_section" '\${session_cwd}'

# 50c: No bare relative path 'openspec/changes/.autopilot-active' without ${session_cwd} prefix
#      Check lockfile skill (v3.5.0: lockfile management moved to dedicated skill)
bare_relative_count=$(grep -c 'openspec/changes/\.autopilot-active' "$LOCKFILE_FILE" | head -1)
prefixed_count=$(grep -c '\${session_cwd}/openspec/changes/\.autopilot-active' "$LOCKFILE_FILE" | head -1)
if [ "$bare_relative_count" -eq "$prefixed_count" ]; then
  green "  PASS: 50c: all .autopilot-active refs have \${session_cwd} prefix ($prefixed_count/$bare_relative_count)"
  PASS=$((PASS + 1))
else
  red "  FAIL: 50c: bare relative path found ($prefixed_count prefixed of $bare_relative_count total)"
  FAIL=$((FAIL + 1))
fi

# 50d: Recovery SKILL.md also uses absolute path
recovery_line=$(grep 'autopilot-active' "$RECOVERY_FILE" || true)
assert_contains "50d: Recovery skill uses absolute path" "$recovery_line" '\${session_cwd}'

# 50e: Gate SKILL.md also uses absolute path
gate_line=$(grep 'autopilot-active' "$GATE_FILE" || true)
assert_contains "50e: Gate skill uses absolute path" "$gate_line" '\${session_cwd}'

teardown_autopilot_fixture
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1; exit 0

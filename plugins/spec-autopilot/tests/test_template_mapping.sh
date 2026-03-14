#!/usr/bin/env bash
# test_template_mapping.sh — Section 44: Template file mapping consistency
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../scripts" && pwd)"
source "$TEST_DIR/_test_helpers.sh"
source "$TEST_DIR/_fixtures.sh"

echo "--- 44. Template file mapping consistency ---"
setup_autopilot_fixture

# 44a. dispatch SKILL.md references phase5-serial-task.md (not phase5-ralph-loop.md)
DISPATCH_FILE="$SCRIPT_DIR/../skills/autopilot-dispatch/SKILL.md"
if grep -q 'phase5-serial-task.md' "$DISPATCH_FILE"; then
  green "  PASS: dispatch references phase5-serial-task.md"
  PASS=$((PASS + 1))
else
  red "  FAIL: dispatch missing phase5-serial-task.md reference"
  FAIL=$((FAIL + 1))
fi

if ! grep -qi 'phase5-ralph-loop' "$DISPATCH_FILE"; then
  green "  PASS: dispatch has no phase5-ralph-loop reference"
  PASS=$((PASS + 1))
else
  red "  FAIL: dispatch still references phase5-ralph-loop"
  FAIL=$((FAIL + 1))
fi

# 44b. SKILL.md Phase 5 describes foreground Task (not ralph-loop)
MAIN_SKILL="$SCRIPT_DIR/../skills/autopilot/SKILL.md"
if grep -q '前台 Task' "$MAIN_SKILL"; then
  green "  PASS: SKILL.md Phase 5 describes foreground Task dispatch"
  PASS=$((PASS + 1))
else
  red "  FAIL: SKILL.md Phase 5 missing foreground Task description"
  FAIL=$((FAIL + 1))
fi

# 44c. phase5-implementation.md has serial mode section
IMPL_FILE="$SCRIPT_DIR/../skills/autopilot/references/phase5-implementation.md"
if grep -q '串行模式' "$IMPL_FILE" && grep -q '前台 Task' "$IMPL_FILE"; then
  green "  PASS: phase5-implementation.md has serial mode with foreground Task"
  PASS=$((PASS + 1))
else
  red "  FAIL: phase5-implementation.md missing serial mode description"
  FAIL=$((FAIL + 1))
fi

# 44d. SKILL.md recovery protocol mentions phase5-tasks/ scanning
if grep -q 'phase5-tasks' "$MAIN_SKILL"; then
  green "  PASS: SKILL.md recovery protocol references phase5-tasks/"
  PASS=$((PASS + 1))
else
  red "  FAIL: SKILL.md recovery missing phase5-tasks/ reference"
  FAIL=$((FAIL + 1))
fi

teardown_autopilot_fixture
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1; exit 0

#!/usr/bin/env bash
# test_ralph_removal.sh — Section 41: Ralph-loop removal: no residual references
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../runtime/scripts" && pwd)"
source "$TEST_DIR/_test_helpers.sh"
source "$TEST_DIR/_fixtures.sh"

echo "--- 41. Ralph-loop removal: no residual references ---"
setup_autopilot_fixture

# 41a. No detect-ralph-loop.sh script exists
if [ ! -f "$SCRIPT_DIR/detect-ralph-loop.sh" ]; then
  green "  PASS: detect-ralph-loop.sh removed"
  PASS=$((PASS + 1))
else
  red "  FAIL: detect-ralph-loop.sh still exists (should be deleted)"
  FAIL=$((FAIL + 1))
fi

# 41b. No phase5-ralph-loop.md template (renamed to phase5-serial-task.md)
if [ ! -f "$SCRIPT_DIR/../../skills/autopilot/templates/phase5-ralph-loop.md" ]; then
  green "  PASS: phase5-ralph-loop.md removed (renamed to phase5-serial-task.md)"
  PASS=$((PASS + 1))
else
  red "  FAIL: phase5-ralph-loop.md still exists"
  FAIL=$((FAIL + 1))
fi

# 41c. phase5-serial-task.md exists as replacement
if [ -f "$SCRIPT_DIR/../../skills/autopilot/templates/phase5-serial-task.md" ]; then
  green "  PASS: phase5-serial-task.md exists"
  PASS=$((PASS + 1))
else
  red "  FAIL: phase5-serial-task.md missing (replacement for phase5-ralph-loop.md)"
  FAIL=$((FAIL + 1))
fi

# 41d. validate-config.sh requires serial_task.max_retries_per_task (not ralph_loop keys)
if grep -q 'serial_task.max_retries_per_task' "$SCRIPT_DIR/validate-config.sh"; then
  green "  PASS: validate-config uses serial_task.max_retries_per_task"
  PASS=$((PASS + 1))
else
  red "  FAIL: validate-config missing serial_task.max_retries_per_task"
  FAIL=$((FAIL + 1))
fi

# 41e. validate-config.sh does NOT require old ralph_loop keys
for old_key in "ralph_loop.enabled" "ralph_loop.max_iterations" "ralph_loop.fallback_enabled"; do
  if ! grep -q "$old_key" "$SCRIPT_DIR/validate-config.sh"; then
    green "  PASS: validate-config has no '$old_key'"
    PASS=$((PASS + 1))
  else
    red "  FAIL: validate-config still references '$old_key'"
    FAIL=$((FAIL + 1))
  fi
done

# 41f. config-schema.md uses max_retries_per_task (not max_iterations/fallback_enabled under serial_task)
SCHEMA_FILE="$SCRIPT_DIR/../../skills/autopilot-setup/references/config-schema.md"
if grep -q 'max_retries_per_task' "$SCHEMA_FILE"; then
  green "  PASS: config-schema has max_retries_per_task"
  PASS=$((PASS + 1))
else
  red "  FAIL: config-schema missing max_retries_per_task"
  FAIL=$((FAIL + 1))
fi

# Check serial_task section doesn't have old fields
serial_section=$(sed -n '/serial_task:/,/^    [a-z]/p' "$SCHEMA_FILE" | head -5)
if ! grep -q 'max_iterations' <<< "$serial_section"; then
  green "  PASS: config-schema serial_task has no max_iterations"
  PASS=$((PASS + 1))
else
  red "  FAIL: config-schema serial_task still has max_iterations"
  FAIL=$((FAIL + 1))
fi

if ! grep -q 'fallback_enabled' <<< "$serial_section"; then
  green "  PASS: config-schema serial_task has no fallback_enabled"
  PASS=$((PASS + 1))
else
  red "  FAIL: config-schema serial_task still has fallback_enabled"
  FAIL=$((FAIL + 1))
fi

# 41g. No ralph_loop references in core SKILL files
CORE_FILES=(
  "$SCRIPT_DIR/../../skills/autopilot/SKILL.md"
  "$SCRIPT_DIR/../../skills/autopilot-dispatch/SKILL.md"
  "$SCRIPT_DIR/../../skills/autopilot/references/phase5-implementation.md"
  "$SCRIPT_DIR/../../skills/autopilot/references/parallel-dispatch.md"
  "$SCRIPT_DIR/../../skills/autopilot-setup/references/config-schema.md"
)
ralph_found=false
for f in "${CORE_FILES[@]}"; do
  if [ -f "$f" ] && grep -qi "ralph.loop\|ralph_loop" "$f"; then
    red "  FAIL: ralph-loop reference in $(basename "$f")"
    FAIL=$((FAIL + 1))
    ralph_found=true
  fi
done
if [ "$ralph_found" = "false" ]; then
  green "  PASS: no ralph-loop references in core SKILL files"
  PASS=$((PASS + 1))
fi

teardown_autopilot_fixture
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1; exit 0

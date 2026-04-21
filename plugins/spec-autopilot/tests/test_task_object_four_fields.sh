#!/usr/bin/env bash
# test_task_object_four_fields.sh — Contract test for Anthropic-style
# Four-Field Task Contract (Objective / Output Format / Tool Boundary / Task Boundary)
# embedded in dispatch templates.
#
# Background: Anthropic Engineering — "How we built our multi-agent research system"
# identifies missing task-boundary as the #1 cause of redundant sub-agent investigation.
# Spec-autopilot v6 enforces these four fields in every dispatched sub-agent prompt.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/_test_helpers.sh"

PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEMPLATE_FILE="$PLUGIN_ROOT/skills/autopilot-dispatch/references/dispatch-prompt-template.md"
DISPATCH_SKILL="$PLUGIN_ROOT/skills/autopilot-dispatch/SKILL.md"

echo "=== Task Object Four-Field Contract Tests ==="

# Pre-flight: target files exist
assert_file_exists "template file present" "$TEMPLATE_FILE"
assert_file_exists "dispatch SKILL.md present" "$DISPATCH_SKILL"

# Test 1-4: dispatch-prompt-template.md must contain the four canonical section headers
# Use grep -F for literal matching to avoid regex fragility.
for header in "## Objective" "## Output Format" "## Tool Boundary" "## Task Boundary"; do
  if grep -F -q -- "$header" "$TEMPLATE_FILE"; then
    green "  PASS: template contains section '$header'"
    PASS=$((PASS + 1))
  else
    red "  FAIL: template missing section '$header'"
    FAIL=$((FAIL + 1))
  fi
done

# Test 5: SKILL.md references the four-field contract concept
if grep -E -q -- "(四要素|Four-Field Task Contract)" "$DISPATCH_SKILL"; then
  green "  PASS: dispatch SKILL.md references four-field contract"
  PASS=$((PASS + 1))
else
  red "  FAIL: dispatch SKILL.md does not mention four-field contract"
  FAIL=$((FAIL + 1))
fi

# Test 6 (sanity): SKILL.md points at the template reference path
if grep -F -q -- "references/dispatch-prompt-template.md" "$DISPATCH_SKILL"; then
  green "  PASS: dispatch SKILL.md cites references/dispatch-prompt-template.md"
  PASS=$((PASS + 1))
else
  red "  FAIL: dispatch SKILL.md missing reference path to dispatch-prompt-template.md"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1
exit 0

#!/usr/bin/env bash
# post-task-validator.sh
# Hook: PostToolUse(Task) — Unified entry point (v4.0)
# Purpose: Single orchestrator that runs all 5 PostToolUse(Task) validations
#          in one python3 process, reducing fork overhead from ~420ms to ~100ms.
#
# Replaces 5 separate hooks:
#   1. validate-json-envelope.sh    → JSON structure validation
#   2. anti-rationalization-check.sh → Skip pattern detection
#   3. code-constraint-check.sh     → Code constraint verification
#   4. parallel-merge-guard.sh      → Worktree merge validation
#   5. validate-decision-format.sh  → Decision format validation
#
# Output: PostToolUse `decision: "block"` with `reason` on first validation failure.

# --- Common preamble: stdin read, SCRIPT_DIR, _common.sh, Layer 0 bypass ---
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_hook_preamble.sh"

# --- Fast bypass Layer 1: prompt phase marker detection ---
has_phase_marker || exit 0

# --- Fast bypass Layer 1.5: background agent skip ---
is_background_agent && exit 0

# --- Dependency check: python3 required ---
if ! require_python3; then
  exit 0
fi

# --- Single python3 call for all validations ---
echo "$STDIN_DATA" | python3 "$SCRIPT_DIR/_post_task_validator.py"

exit 0

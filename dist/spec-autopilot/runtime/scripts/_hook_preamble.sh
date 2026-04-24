#!/usr/bin/env bash
# _hook_preamble.sh
# Common preamble for PostToolUse Hook scripts (Task & Write|Edit).
# Source this at the top of each hook script:
#
#   source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_hook_preamble.sh"
#
# Provides (exported to calling script):
#   STDIN_DATA          — raw stdin JSON from Claude Code
#   SCRIPT_DIR          — absolute path to shared scripts directory
#   PROJECT_ROOT_QUICK  — project root (from stdin cwd or git fallback)
#
# Auto-exits (exit 0) if:
#   - stdin is empty (not a hook invocation)
#   - project is not an autopilot project (no openspec/ nor autopilot.config.yaml)
#   - no active autopilot session (Layer 0 bypass, ~1ms)

set -uo pipefail

# --- Read stdin JSON ---
STDIN_DATA=""
if [ ! -t 0 ]; then
  STDIN_DATA=$(cat)
fi
[ -z "$STDIN_DATA" ] && exit 0

# --- Set up shared infrastructure ---
# Use BASH_SOURCE[0] which points to this preamble file (same directory as all scripts)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export SCRIPT_DIR
source "$SCRIPT_DIR/_common.sh"

# --- Extract project root (pure bash, ~1ms) ---
# Priority: $AUTOPILOT_PROJECT_ROOT (test fixtures / explicit override) >
#           cwd from stdin > git rev-parse > pwd
if [ -n "${AUTOPILOT_PROJECT_ROOT:-}" ] && [ -d "${AUTOPILOT_PROJECT_ROOT}" ]; then
  PROJECT_ROOT_QUICK="$AUTOPILOT_PROJECT_ROOT"
else
  PROJECT_ROOT_QUICK=$(echo "$STDIN_DATA" | grep -o '"cwd"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
  if [ -z "$PROJECT_ROOT_QUICK" ]; then
    PROJECT_ROOT_QUICK="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  fi
fi

# --- Layer 0a project-recognition guard: non-autopilot projects exit early ---
# Prevents pollution when this plugin is enabled globally but the user works in
# unrelated projects (no openspec/ nor .claude/autopilot.config.yaml).
is_autopilot_project "$PROJECT_ROOT_QUICK" || exit 0

# --- Layer 0 bypass: no active autopilot session ---
has_active_autopilot "$PROJECT_ROOT_QUICK" || exit 0

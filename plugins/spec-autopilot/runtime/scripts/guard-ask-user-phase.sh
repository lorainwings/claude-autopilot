#!/usr/bin/env bash
# guard-ask-user-phase.sh
# Hook: PreToolUse(AskUserQuestion)
# Purpose: Block AskUserQuestion during Phase 2-6 of the autopilot flow.
#          Phases 2-6 run fully automatically unless the user explicitly enables
#          user_confirmation via config: gates.user_confirmation.after_phase_{N}.
#
# Scope: Only active when autopilot lockfile exists (.autopilot-active).
#        Phase 1 (requirements) and Phase 7 (archive) always allow user questions.
#
# Output: JSON with hookSpecificOutput.permissionDecision on deny.
#         Plain exit 0 on allow.

set -uo pipefail

# --- Read stdin JSON ---
STDIN_DATA=""
if [ ! -t 0 ]; then
  STDIN_DATA=$(cat)
fi
[ -z "$STDIN_DATA" ] && exit 0

# --- Resolve project root from cwd ---
CWD=$(echo "$STDIN_DATA" | grep -o '"cwd"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
if [ -n "$CWD" ]; then
  PROJECT_ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null || true)
else
  PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)
fi
[ -z "$PROJECT_ROOT" ] && exit 0

# --- Source common helpers ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

# --- Project relevance guard: non-autopilot projects exit early ---
is_autopilot_project "$PROJECT_ROOT" || exit 0

# --- Check if autopilot is active ---
LOCK_FILE="${PROJECT_ROOT}/openspec/changes/.autopilot-active"
[ -f "$LOCK_FILE" ] || exit 0

# --- Determine current phase from progress files ---
# Scope the scan to the active change. Otherwise stale progress files from
# older changes can incorrectly block AskUserQuestion in the current session.
CHANGES_DIR="${PROJECT_ROOT}/openspec/changes"
CURRENT_PHASE=""
ACTIVE_CHANGE_NAME=$(parse_lock_file "$LOCK_FILE")
ACTIVE_CHANGE_DIR=""

if [ -n "$ACTIVE_CHANGE_NAME" ] && [ -d "$CHANGES_DIR/$ACTIVE_CHANGE_NAME" ]; then
  ACTIVE_CHANGE_DIR="$CHANGES_DIR/$ACTIVE_CHANGE_NAME"
else
  ACTIVE_CHANGE_DIR=$(find_active_change "$CHANGES_DIR" 2>/dev/null || true)
fi

# Find progress files for the active change only
if [ -n "$ACTIVE_CHANGE_DIR" ]; then
  PROGRESS_FILES=$(find "$ACTIVE_CHANGE_DIR/context/phase-results" -maxdepth 1 -name "phase-*-progress.json" -type f 2>/dev/null) || true
else
  PROGRESS_FILES=""
fi

if [ -n "$PROGRESS_FILES" ]; then
  # Extract the highest phase number with status "in_progress"
  CURRENT_PHASE=$(python3 -c "
import json, sys, re, os

files = sys.argv[1:]
best_phase = 0
for f in files:
    try:
        with open(f) as fh:
            data = json.load(fh)
        if data.get('status') == 'in_progress':
            phase_num = data.get('phase', 0)
            if isinstance(phase_num, int) and phase_num > best_phase:
                best_phase = phase_num
    except Exception:
        continue
print(best_phase if best_phase > 0 else '')
" $PROGRESS_FILES 2>/dev/null) || true
fi

# Fallback: try to read current_phase from lock file
if [ -z "$CURRENT_PHASE" ]; then
  CURRENT_PHASE=$(read_lock_json_field "$LOCK_FILE" "current_phase" "")
fi

# If still undetermined, allow (safe default)
[ -z "$CURRENT_PHASE" ] && exit 0

# --- Phase gate logic ---
# Phase 1 and Phase 7: always allow user questions
# Phase 5: allow — merge conflicts, worktree failures, and consecutive-warn
#   recovery paths require AskUserQuestion per SKILL.md/phase5-implementation.md.
#   Normal continuous execution is enforced by the orchestrator, not this hook.
case "$CURRENT_PHASE" in
  1 | 5 | 7) exit 0 ;;
esac

# Phase 2-6: block unless explicitly configured
if [ "$CURRENT_PHASE" -ge 2 ] && [ "$CURRENT_PHASE" -le 6 ]; then
  ALLOW=$(read_config_value "$PROJECT_ROOT" "gates.user_confirmation.after_phase_${CURRENT_PHASE}" "false")
  if [ "$ALLOW" = "true" ]; then
    exit 0
  fi

  # Deny: output JSON
  cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "[guard-ask-user-phase] AskUserQuestion blocked during Phase ${CURRENT_PHASE} — autopilot continuous execution mode. Phase 2-6 run fully automatically unless config.gates.user_confirmation.after_phase_${CURRENT_PHASE} is true."
  }
}
EOF
  exit 0
fi

# Any other phase (unexpected) — allow
exit 0

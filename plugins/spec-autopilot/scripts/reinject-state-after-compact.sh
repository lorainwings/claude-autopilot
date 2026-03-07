#!/usr/bin/env bash
# reinject-state-after-compact.sh
# Hook: SessionStart(compact)
# Purpose: After context compaction, re-inject saved autopilot state into Claude's context.
#
# Official guidance (hooks-guide):
#   "Use a SessionStart hook with a compact matcher to re-inject critical context
#    after every compaction."
#
# This script reads the state file saved by save-state-before-compact.sh and outputs
# it to stdout. Claude Code automatically feeds stdout back into the conversation.

set -uo pipefail

# --- Determine project root ---
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
CHANGES_DIR="$PROJECT_ROOT/openspec/changes"

if [ ! -d "$CHANGES_DIR" ]; then
  exit 0
fi

# --- Source shared utilities ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

# --- Find active change state file ---
# Priority 1: Use lock file to identify the active change (reliable)
STATE_FILE=""
LOCK_FILE="$CHANGES_DIR/.autopilot-active"
if [ -f "$LOCK_FILE" ]; then
  ACTIVE_NAME=$(parse_lock_file "$LOCK_FILE")
  if [ -n "$ACTIVE_NAME" ] && [ -d "$CHANGES_DIR/$ACTIVE_NAME" ]; then
    candidate="$CHANGES_DIR/$ACTIVE_NAME/context/autopilot-state.md"
    if [ -f "$candidate" ]; then
      STATE_FILE="$candidate"
    fi
  fi
fi

# Priority 2: Fallback to mtime-based search (when lock file missing)
if [ -z "$STATE_FILE" ]; then
  LATEST_MTIME=0
  for state in "$CHANGES_DIR"/*/context/autopilot-state.md; do
    [ -f "$state" ] || continue
    mtime=$(stat -f "%m" "$state" 2>/dev/null || stat -c "%Y" "$state" 2>/dev/null || echo 0)
    if [ "$mtime" -gt "$LATEST_MTIME" ]; then
      LATEST_MTIME=$mtime
      STATE_FILE="$state"
    fi
  done
fi

if [ -z "$STATE_FILE" ] || [ ! -f "$STATE_FILE" ]; then
  exit 0
fi

# --- Output state to stdout (injected into Claude's context) ---
echo ""
echo "=== AUTOPILOT STATE RESTORED AFTER CONTEXT COMPACTION ==="
echo ""
cat "$STATE_FILE"
echo ""
echo "=== END AUTOPILOT STATE ==="
echo ""

exit 0

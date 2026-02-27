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

# --- Find the most recent autopilot-state.md ---
STATE_FILE=""
LATEST_MTIME=0

for state in "$CHANGES_DIR"/*/context/autopilot-state.md; do
  [ -f "$state" ] || continue
  mtime=$(stat -f "%m" "$state" 2>/dev/null || stat -c "%Y" "$state" 2>/dev/null || echo 0)
  if [ "$mtime" -gt "$LATEST_MTIME" ]; then
    LATEST_MTIME=$mtime
    STATE_FILE="$state"
  fi
done

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

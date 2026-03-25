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

# v5.3: Output all phase context snapshots for reasoning continuity (v5.8: all snapshots, not just latest)
SNAPSHOTS_DIR="$(dirname "$STATE_FILE")/phase-context-snapshots"
if [ -d "$SNAPSHOTS_DIR" ]; then
  SNAP_COUNT=0
  TOTAL_CHARS=0
  MAX_TOTAL_CHARS=4000  # Total budget across all snapshots
  for snap in "$SNAPSHOTS_DIR"/phase-*-context.md; do
    [ -f "$snap" ] || continue
    SNAP_COUNT=$((SNAP_COUNT + 1))
  done

  if [ "$SNAP_COUNT" -gt 0 ]; then
    echo ""
    echo "--- Phase Context Snapshots ($SNAP_COUNT phases) ---"
    echo ""
    for snap in $(ls -1 "$SNAPSHOTS_DIR"/phase-*-context.md 2>/dev/null | sort); do
      [ -f "$snap" ] || continue
      SNAP_SIZE=$(wc -c <"$snap" 2>/dev/null || echo 0)
      REMAINING=$((MAX_TOTAL_CHARS - TOTAL_CHARS))
      if [ "$REMAINING" -le 100 ]; then
        echo "... (remaining snapshots truncated, see files in phase-context-snapshots/)"
        break
      fi
      echo "### $(basename "$snap")"
      if [ "$SNAP_SIZE" -le "$REMAINING" ]; then
        cat "$snap"
        TOTAL_CHARS=$((TOTAL_CHARS + SNAP_SIZE))
      else
        head -c "$REMAINING" "$snap"
        TOTAL_CHARS=$MAX_TOTAL_CHARS
        echo ""
        echo "... (truncated)"
      fi
      echo ""
    done
    echo "--- End Phase Context Snapshots ---"
  fi
fi

# v5.8: Deterministic recovery instruction — tell orchestrator exactly what to do next
echo ""
echo "=== DETERMINISTIC RECOVERY INSTRUCTION ==="
echo ""
# Extract next_phase from state file
NEXT_PHASE=$(grep -oP '(?<=\*\*Next phase to execute\*\*: )\d+' "$STATE_FILE" 2>/dev/null || echo "")
EXEC_MODE=$(grep -oP '(?<=\*\*Execution mode\*\*: `)\w+' "$STATE_FILE" 2>/dev/null || echo "full")
CHANGE_NAME_RESTORE=$(grep -oP '(?<=\*\*Active change\*\*: `)[^`]+' "$STATE_FILE" 2>/dev/null || echo "")

if [ -n "$NEXT_PHASE" ]; then
  echo "ACTION REQUIRED: Resume autopilot from Phase ${NEXT_PHASE} (mode: ${EXEC_MODE}, change: ${CHANGE_NAME_RESTORE})."
  echo ""
  echo "Steps:"
  echo "1. Re-read config: .claude/autopilot.config.yaml"
  echo "2. Call Skill(spec-autopilot:autopilot-gate) for Phase ${NEXT_PHASE}"
  echo "3. If gate passes, call Skill(spec-autopilot:autopilot-dispatch) and dispatch Phase ${NEXT_PHASE}"
  echo "4. DO NOT re-execute any Phase marked 'ok' or 'warning' in the Phase Status table above"
  if [ "$NEXT_PHASE" = "5" ]; then
    echo "5. Phase 5 in-progress: scan phase5-tasks/ for task-level recovery point before dispatching"
  fi
else
  echo "ACTION REQUIRED: Read autopilot-state.md above and resume from the next incomplete phase."
  echo "DO NOT re-execute completed phases."
fi

echo ""
echo "=== END AUTOPILOT STATE ==="
echo ""

exit 0

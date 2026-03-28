#!/usr/bin/env bash
# reinject-state-after-compact.sh
# Hook: SessionStart(compact)
# Purpose: After context compaction, re-inject saved autopilot state into Claude's context.
#
# Official guidance (hooks-guide):
#   "Use a SessionStart hook with a compact matcher to re-inject critical context
#    after every compaction."
#
# v6.0: Prioritizes state-snapshot.json (structured control state) over autopilot-state.md.
#        Verifies snapshot_hash consistency before injecting structured state.
#        Falls back to markdown only if JSON is missing or corrupted.

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

# --- Find active change directory ---
# Priority 1: Use lock file to identify the active change (reliable)
CHANGE_DIR=""
STATE_FILE=""
SNAPSHOT_JSON=""
LOCK_FILE="$CHANGES_DIR/.autopilot-active"
if [ -f "$LOCK_FILE" ]; then
  ACTIVE_NAME=$(parse_lock_file "$LOCK_FILE")
  if [ -n "$ACTIVE_NAME" ] && [ -d "$CHANGES_DIR/$ACTIVE_NAME" ]; then
    CHANGE_DIR="$CHANGES_DIR/$ACTIVE_NAME"
    candidate_md="$CHANGE_DIR/context/autopilot-state.md"
    candidate_json="$CHANGE_DIR/context/state-snapshot.json"
    [ -f "$candidate_md" ] && STATE_FILE="$candidate_md"
    [ -f "$candidate_json" ] && SNAPSHOT_JSON="$candidate_json"
  fi
fi

# Priority 2: Fallback to mtime-based search (when lock file missing)
if [ -z "$STATE_FILE" ] && [ -z "$SNAPSHOT_JSON" ]; then
  LATEST_MTIME=0
  for state in "$CHANGES_DIR"/*/context/autopilot-state.md; do
    [ -f "$state" ] || continue
    mtime=$(stat -f "%m" "$state" 2>/dev/null || stat -c "%Y" "$state" 2>/dev/null || echo 0)
    if [ "$mtime" -gt "$LATEST_MTIME" ]; then
      LATEST_MTIME=$mtime
      STATE_FILE="$state"
      CHANGE_DIR="$(dirname "$(dirname "$state")")"
    fi
  done
  # Also check for state-snapshot.json in the same change dir
  if [ -n "$CHANGE_DIR" ] && [ -f "$CHANGE_DIR/context/state-snapshot.json" ]; then
    SNAPSHOT_JSON="$CHANGE_DIR/context/state-snapshot.json"
  fi
fi

if [ -z "$STATE_FILE" ] && [ -z "$SNAPSHOT_JSON" ]; then
  exit 0
fi

# --- v6.0: Try structured state-snapshot.json first (primary path) ---
SNAPSHOT_VALID=false
if [ -n "$SNAPSHOT_JSON" ] && [ -f "$SNAPSHOT_JSON" ] && command -v python3 &>/dev/null; then
  SNAPSHOT_OUTPUT=$(python3 -c "
import json, sys, hashlib

snapshot_file = sys.argv[1]
try:
    with open(snapshot_file) as f:
        data = json.load(f)

    # Verify schema_version
    if data.get('schema_version') != '6.0':
        print('INVALID:schema_version_mismatch', file=sys.stderr)
        sys.exit(1)

    # Verify snapshot_hash consistency
    stored_hash = data.get('snapshot_hash', '')
    if not stored_hash:
        print('INVALID:no_snapshot_hash', file=sys.stderr)
        sys.exit(1)

    # Recompute hash (exclude snapshot_hash field itself)
    verify_data = {k: v for k, v in data.items() if k != 'snapshot_hash'}
    verify_content = json.dumps(verify_data, sort_keys=True, ensure_ascii=False)
    computed_hash = hashlib.sha256(verify_content.encode('utf-8')).hexdigest()[:16]

    if computed_hash != stored_hash:
        print(f'INVALID:hash_mismatch stored={stored_hash} computed={computed_hash}', file=sys.stderr)
        sys.exit(1)

    # Structured output
    change_name = data.get('change_name', 'unknown')
    mode = data.get('execution_mode', 'full')
    gate_frontier = data.get('gate_frontier', 0)
    last_completed = data.get('last_completed_phase', 0)
    next_action = data.get('next_action', {})
    next_phase = next_action.get('phase', 1)
    anchor_sha = data.get('anchor_sha') or ''
    req_hash = data.get('requirement_packet_hash') or ''
    phase_results = data.get('phase_results', {})
    active_tasks = data.get('active_tasks', [])
    tasks_progress = data.get('tasks_progress', {})
    phase5_tasks = data.get('phase5_task_details', [])
    snapshot_hash = stored_hash

    print('=== AUTOPILOT STATE RESTORED (STRUCTURED) ===')
    print()
    print(f'Structured recovery from state-snapshot.json (hash={snapshot_hash})')
    print()
    print(f'## Control State')
    print(f'- Change: {change_name}')
    print(f'- Mode: {mode}')
    print(f'- Gate frontier: Phase {gate_frontier}')
    print(f'- Last completed: Phase {last_completed}')
    print(f'- Next action: Phase {next_phase} ({next_action.get(\"type\", \"resume\")})')
    if req_hash:
        print(f'- Requirement packet hash: {req_hash}')
    if anchor_sha:
        print(f'- Anchor SHA: {anchor_sha}')
    print(f'- Snapshot hash: {snapshot_hash} (verified)')
    print()

    # Phase results table
    print('## Phase Results')
    print('| Phase | Status | Summary |')
    print('|-------|--------|---------|')
    phase_names = {'1': 'Requirements', '2': 'OpenSpec', '3': 'FF Generate', '4': 'Test Design', '5': 'Implementation', '6': 'Test Report', '7': 'Archive'}
    for pnum_str in sorted(phase_results.keys(), key=int):
        pr = phase_results[pnum_str]
        name = phase_names.get(pnum_str, f'Phase {pnum_str}')
        status = pr.get('status', 'pending')
        summary = (pr.get('summary', '') or '')[:80]
        print(f'| {pnum_str}. {name} | {status} | {summary or \"-\"} |')
    print()

    # Active tasks
    if active_tasks:
        print('## Active Tasks (in-progress)')
        for at in active_tasks:
            print(f'- Phase {at[\"phase\"]}: sub-step={at[\"step\"]}')
        print()

    # Task progress
    if tasks_progress.get('completed', 0) > 0 or tasks_progress.get('remaining', 0) > 0:
        print(f'## Tasks: {tasks_progress.get(\"completed\", 0)} completed, {tasks_progress.get(\"remaining\", 0)} remaining')
        print()

    # Phase 5 task details
    if phase5_tasks:
        print('## Phase 5 Task Details')
        print('| Task | Status | Summary |')
        print('|------|--------|---------|')
        for td in phase5_tasks:
            print(f'| {td[\"number\"]} | {td[\"status\"]} | {td.get(\"summary\", \"-\")} |')
        print()

    print('=== DETERMINISTIC RECOVERY INSTRUCTION ===')
    print()
    print(f'ACTION REQUIRED: Resume autopilot from Phase {next_phase} (mode: {mode}, change: {change_name}).')
    if active_tasks:
        at = active_tasks[-1]
        print(f'NOTE: Phase {at[\"phase\"]} was in-progress at sub-step \"{at[\"step\"]}\" when compaction occurred.')
    print()
    print('Steps:')
    print(f'1. Re-read config: .claude/autopilot.config.yaml')
    print(f'2. Call Skill(spec-autopilot:autopilot-gate) for Phase {next_phase}')
    print(f'3. If gate passes, call Skill(spec-autopilot:autopilot-dispatch) and dispatch Phase {next_phase}')
    print(f'4. DO NOT re-execute any Phase marked ok or warning in the Phase Results table above')
    if next_phase == 5:
        print(f'5. Phase 5 in-progress: scan phase5-tasks/ for task-level recovery point before dispatching')
    print()
    print('=== END AUTOPILOT STATE ===')
    print()
except Exception as e:
    print(f'INVALID:{e}', file=sys.stderr)
    sys.exit(1)
" "$SNAPSHOT_JSON" 2>/dev/null)

  if [ $? -eq 0 ] && [ -n "$SNAPSHOT_OUTPUT" ]; then
    SNAPSHOT_VALID=true
    echo ""
    echo "$SNAPSHOT_OUTPUT"
    exit 0
  fi
fi

# --- Fallback: use autopilot-state.md (legacy path) ---
if [ -z "$STATE_FILE" ] || [ ! -f "$STATE_FILE" ]; then
  # v6.0: If snapshot JSON existed but was invalid, warn about fail-closed
  if [ -n "$SNAPSHOT_JSON" ] && [ -f "$SNAPSHOT_JSON" ]; then
    echo ""
    echo "=== WARNING: SNAPSHOT HASH VERIFICATION FAILED ==="
    echo ""
    echo "state-snapshot.json exists but failed integrity check."
    echo "Falling back to autopilot-state.md (legacy markdown recovery)."
    echo "Recovery confidence: LOW — recommend manual verification before continuing."
    echo ""
  fi
  exit 0
fi

echo ""
echo "=== AUTOPILOT STATE RESTORED AFTER CONTEXT COMPACTION (LEGACY) ==="
echo ""

# v6.0: Warn if structured snapshot was expected but failed
if [ -n "$SNAPSHOT_JSON" ] && [ -f "$SNAPSHOT_JSON" ]; then
  echo "WARNING: state-snapshot.json failed hash verification. Using legacy markdown recovery."
  echo "Recovery confidence: MEDIUM — state-snapshot.json should be the primary control state."
  echo ""
fi

cat "$STATE_FILE"

# v5.3: Output all phase context snapshots for reasoning continuity (v5.8: all snapshots, not just latest)
SNAPSHOTS_DIR="$(dirname "$STATE_FILE")/phase-context-snapshots"
if [ -d "$SNAPSHOTS_DIR" ]; then
  SNAP_COUNT=0
  TOTAL_CHARS=0
  MAX_TOTAL_CHARS=4000 # Total budget across all snapshots
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
# Extract next_phase from state file (POSIX-compatible — no grep -P which is GNU-only)
NEXT_PHASE=$(sed -n 's/.*\*\*Next phase to execute\*\*: \([0-9][0-9]*\).*/\1/p' "$STATE_FILE" 2>/dev/null | head -1)
EXEC_MODE=$(sed -n 's/.*\*\*Execution mode\*\*: `\([a-zA-Z_]*\)`.*/\1/p' "$STATE_FILE" 2>/dev/null | head -1)
[ -z "$EXEC_MODE" ] && EXEC_MODE="full"
CHANGE_NAME_RESTORE=$(sed -n 's/.*\*\*Active change\*\*: `\([^`]*\)`.*/\1/p' "$STATE_FILE" 2>/dev/null | head -1)
# v5.9: Extract in-progress phase sub-step for fine-grained recovery
IN_PROGRESS_PHASE=$(sed -n 's/.*\*\*Current in-progress phase\*\*: \([0-9][0-9]*\).*/\1/p' "$STATE_FILE" 2>/dev/null | head -1)
IN_PROGRESS_SUBSTEP=$(sed -n 's/.*\*\*Current in-progress phase\*\*: [0-9]* (sub-step: \(.*\))/\1/p' "$STATE_FILE" 2>/dev/null | head -1)

if [ -n "$NEXT_PHASE" ]; then
  echo "ACTION REQUIRED: Resume autopilot from Phase ${NEXT_PHASE} (mode: ${EXEC_MODE}, change: ${CHANGE_NAME_RESTORE})."
  if [ -n "$IN_PROGRESS_PHASE" ] && [ "$IN_PROGRESS_PHASE" = "$NEXT_PHASE" ] && [ -n "$IN_PROGRESS_SUBSTEP" ]; then
    echo "NOTE: Phase ${IN_PROGRESS_PHASE} was in-progress at sub-step '${IN_PROGRESS_SUBSTEP}' when compaction occurred."
  fi
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

#!/usr/bin/env bash
# save-state-before-compact.sh
# Hook: PreCompact
# Purpose: Before context compaction, save critical autopilot orchestration state
#          to a file that survives compaction and can be re-injected afterwards.
#
# Official guidance (hooks-guide):
#   "Use a SessionStart hook with a compact matcher to re-inject critical context
#    after every compaction."
#
# This script is the "save" half. The "restore" half is reinject-state-after-compact.sh.
# Output: Writes state to openspec/changes/<active>/context/autopilot-state.md

set -uo pipefail

# --- Read stdin JSON ---
STDIN_DATA=""
if [ ! -t 0 ]; then
  STDIN_DATA=$(cat)
fi

# --- Determine project root ---
PROJECT_ROOT=""
if [ -n "$STDIN_DATA" ] && command -v python3 &>/dev/null; then
  PROJECT_ROOT=$(echo "$STDIN_DATA" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    print(data.get('cwd', ''))
except Exception:
    pass
" 2>/dev/null || echo "")
fi

if [ -z "$PROJECT_ROOT" ]; then
  PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi

CHANGES_DIR="$PROJECT_ROOT/openspec/changes"

# --- No changes dir → nothing to save ---
if [ ! -d "$CHANGES_DIR" ]; then
  exit 0
fi

# --- Find active change (most recent checkpoint) ---
find_active_change() {
  # Priority 0: Read lock file written by autopilot Phase 0
  local lock_file="$CHANGES_DIR/.autopilot-active"
  if [ -f "$lock_file" ]; then
    local active_name
    active_name=$(cat "$lock_file" | tr -d '[:space:]')
    if [ -n "$active_name" ] && [ -d "$CHANGES_DIR/$active_name" ]; then
      echo "$CHANGES_DIR/$active_name"
      return 0
    fi
  fi

  # Priority 1: find the change with the most recent checkpoint file
  local latest_file=""
  local find_results
  find_results=$(find "$CHANGES_DIR" -path "*/context/phase-results/phase-*.json" -type f 2>/dev/null) || true
  if [ -n "$find_results" ]; then
    latest_file=$(echo "$find_results" | tr '\n' '\0' | xargs -0 ls -t 2>/dev/null | head -1) || true
  fi

  if [ -n "$latest_file" ]; then
    echo "$latest_file" | sed 's|/context/phase-results/.*||'
    return 0
  fi

  # Fallback: most recently modified change directory (sorted by mtime)
  local latest=""
  local latest_time=0
  for dir in "$CHANGES_DIR"/*/; do
    [ -d "$dir" ] || continue
    [[ "$(basename "$dir")" == _* ]] && continue
    local mtime
    mtime=$(stat -f "%m" "$dir" 2>/dev/null || stat -c "%Y" "$dir" 2>/dev/null || echo 0)
    if [ "$mtime" -gt "$latest_time" ]; then
      latest_time=$mtime
      latest="${dir%/}"
    fi
  done
  if [ -n "$latest" ]; then
    echo "$latest"
    return 0
  fi
  return 1
}

ACTIVE_CHANGE=$(find_active_change) || exit 0
CHANGE_NAME=$(basename "$ACTIVE_CHANGE")
PHASE_RESULTS_DIR="$ACTIVE_CHANGE/context/phase-results"
STATE_FILE="$ACTIVE_CHANGE/context/autopilot-state.md"

# --- Build state summary ---
if ! command -v python3 &>/dev/null; then
  exit 0
fi

python3 -c "
import json, os, sys, glob
from datetime import datetime

change_dir = sys.argv[1]
change_name = sys.argv[2]
phase_results_dir = sys.argv[3]
state_file = sys.argv[4]

# Scan all checkpoints
phases = {}
last_completed = 0
for phase_num in [2, 3, 4, 5, 6]:
    pattern = os.path.join(phase_results_dir, f'phase-{phase_num}-*.json')
    files = sorted(glob.glob(pattern), key=os.path.getmtime, reverse=True)
    if files:
        try:
            with open(files[0]) as f:
                data = json.load(f)
            phases[phase_num] = {
                'status': data.get('status', 'unknown'),
                'summary': data.get('summary', ''),
                'file': os.path.basename(files[0])
            }
            if data.get('status') in ('ok', 'warning'):
                last_completed = phase_num
        except Exception:
            phases[phase_num] = {'status': 'error', 'summary': 'JSON parse error', 'file': os.path.basename(files[0])}

if not phases:
    # No checkpoints yet, nothing to save
    sys.exit(0)

next_phase = last_completed + 1 if last_completed < 7 else 7

# Read tasks.md if exists
tasks_summary = ''
tasks_file = os.path.join(change_dir, 'tasks.md')
if os.path.isfile(tasks_file):
    try:
        with open(tasks_file) as f:
            content = f.read()
        checked = content.count('- [x]')
        unchecked = content.count('- [ ]')
        tasks_summary = f'{checked} completed, {unchecked} remaining'
    except Exception:
        pass

# Read config if exists
config_summary = ''
config_file = os.path.join(change_dir, '..', '..', '..', '.claude', 'autopilot.config.yaml')
config_file = os.path.normpath(config_file)
if os.path.isfile(config_file):
    config_summary = f'Config: {config_file}'

# Generate state markdown
lines = [
    f'# Autopilot State — {change_name}',
    f'',
    f'> Auto-saved before context compaction at {datetime.now().isoformat()}',
    f'> This file is auto-generated. Re-injected into context after compaction.',
    f'',
    f'## Current Progress',
    f'',
    f'- **Active change**: \`{change_name}\`',
    f'- **Last completed phase**: {last_completed}',
    f'- **Next phase to execute**: {next_phase}',
    f'- **Change directory**: \`openspec/changes/{change_name}/\`',
]

if tasks_summary:
    lines.append(f'- **Tasks progress**: {tasks_summary}')
if config_summary:
    lines.append(f'- **{config_summary}**')

lines.extend([
    f'',
    f'## Phase Status',
    f'',
    f'| Phase | Status | Summary |',
    f'|-------|--------|---------|',
])

phase_names = {2: 'OpenSpec', 3: 'FF Generate', 4: 'Test Design', 5: 'Implementation', 6: 'Test Report'}
for phase_num in [2, 3, 4, 5, 6]:
    name = phase_names.get(phase_num, f'Phase {phase_num}')
    if phase_num in phases:
        p = phases[phase_num]
        status_icon = {'ok': 'ok', 'warning': 'warn', 'blocked': 'BLOCKED', 'failed': 'FAILED'}.get(p['status'], p['status'])
        summary = p['summary'][:80] if p['summary'] else '-'
        lines.append(f'| {phase_num}. {name} | {status_icon} | {summary} |')
    else:
        lines.append(f'| {phase_num}. {name} | pending | - |')

lines.extend([
    f'',
    f'## Recovery Instructions',
    f'',
    f'After compaction, the autopilot orchestrator should:',
    f'1. Read this file to restore context',
    f'2. Resume from Phase {next_phase}',
    f'3. Call Skill(\`spec-autopilot:autopilot-gate\`) before dispatching Phase {next_phase}',
    f'4. All completed phase checkpoints are in \`openspec/changes/{change_name}/context/phase-results/\`',
    f'',
])

# Write state file
os.makedirs(os.path.dirname(state_file), exist_ok=True)
with open(state_file, 'w') as f:
    f.write('\n'.join(lines))

print(f'Autopilot state saved: {state_file}', file=sys.stderr)
" "$ACTIVE_CHANGE" "$CHANGE_NAME" "$PHASE_RESULTS_DIR" "$STATE_FILE" 2>/dev/null

exit 0

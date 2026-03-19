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

# --- Source shared utilities ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

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

# --- Find active change (uses _common.sh) ---

ACTIVE_CHANGE=$(find_active_change "$CHANGES_DIR") || exit 0
CHANGE_NAME=$(basename "$ACTIVE_CHANGE")
PHASE_RESULTS_DIR="$ACTIVE_CHANGE/context/phase-results"
STATE_FILE="$ACTIVE_CHANGE/context/autopilot-state.md"

# --- Read execution mode and anchor_sha from lock file ---
LOCK_FILE="$CHANGES_DIR/.autopilot-active"
EXEC_MODE="full"
ANCHOR_SHA=""
if [ -f "$LOCK_FILE" ] && command -v python3 &>/dev/null; then
  EXEC_MODE=$(python3 -c "
import json, sys
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
    print(data.get('mode', 'full'))
except Exception:
    print('full')
" "$LOCK_FILE" 2>/dev/null || echo "full")
  ANCHOR_SHA=$(python3 -c "
import json, sys
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
    print(data.get('anchor_sha', ''))
except Exception:
    pass
" "$LOCK_FILE" 2>/dev/null || echo "")
fi

# --- Build state summary ---
if ! command -v python3 &>/dev/null; then
  exit 0
fi

# shellcheck disable=SC2140
python3 -c "
import json, os, sys, glob, re
from datetime import datetime

change_dir = sys.argv[1]
change_name = sys.argv[2]
phase_results_dir = sys.argv[3]
state_file = sys.argv[4]
exec_mode = sys.argv[5] if len(sys.argv) > 5 else 'full'
anchor_sha = sys.argv[6] if len(sys.argv) > 6 else ''

# Scan all checkpoints
phases = {}
last_completed = 0
for phase_num in [1, 2, 3, 4, 5, 6, 7]:
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

# v5.3: Read phase context snapshots
context_snapshots = {}
snapshots_dir = os.path.join(change_dir, 'context', 'phase-context-snapshots')
if os.path.isdir(snapshots_dir):
    for snap_file in sorted(glob.glob(os.path.join(snapshots_dir, 'phase-*-context.md'))):
        try:
            fname = os.path.basename(snap_file)
            # Extract phase number from filename
            m = re.search(r'phase-(\d+)-context\.md', fname)
            if m:
                snap_phase = int(m.group(1))
                with open(snap_file) as f:
                    content = f.read()
                # Extract summary section (first 500 chars)
                context_snapshots[snap_phase] = content[:500]
        except Exception:
            pass

# Read tasks file (phase5-task-breakdown.md for lite/minimal, tasks.md for full)
tasks_summary = ''
breakdown_file = os.path.join(change_dir, 'context', 'phase5-task-breakdown.md')
tasks_file = os.path.join(change_dir, 'tasks.md')
# Prefer phase5-task-breakdown.md (used in lite/minimal modes)
if os.path.isfile(breakdown_file):
    tasks_file = breakdown_file
if os.path.isfile(tasks_file):
    try:
        with open(tasks_file) as f:
            content = f.read()
        checked = content.count('- [x]')
        unchecked = content.count('- [ ]')
        tasks_summary = f'{checked} completed, {unchecked} remaining'
    except Exception:
        pass

# Scan phase5-tasks/ for task-level progress
phase5_task_details = []
phase5_tasks_dir = os.path.join(phase_results_dir, 'phase5-tasks')
if os.path.isdir(phase5_tasks_dir):
    for task_file in sorted(glob.glob(os.path.join(phase5_tasks_dir, 'task-*.json'))):
        try:
            with open(task_file) as f:
                tdata = json.load(f)
            phase5_task_details.append({
                'number': tdata.get('task_number', '?'),
                'status': tdata.get('status', 'unknown'),
                'summary': (tdata.get('summary', '') or '')[:60]
            })
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
    f'- **Execution mode**: \`{exec_mode}\`',
]

if anchor_sha:
    lines.append(f'- **Anchor SHA**: \`{anchor_sha}\`')

if tasks_summary:
    lines.append(f'- **Tasks progress**: {tasks_summary}')

if phase5_task_details:
    lines.extend([
        f'',
        f'## Phase 5 Task Progress',
        f'',
        f'| Task | Status | Summary |',
        f'|------|--------|---------|',
    ])
    for td in phase5_task_details:
        lines.append(f'| {td["number"]} | {td["status"]} | {td["summary"]} |')

if config_summary:
    lines.append(f'- **{config_summary}**')

lines.extend([
    f'',
    f'## Phase Status',
    f'',
    f'| Phase | Status | Summary |',
    f'|-------|--------|---------|',
])

phase_names = {1: 'Requirements', 2: 'OpenSpec', 3: 'FF Generate', 4: 'Test Design', 5: 'Implementation', 6: 'Test Report', 7: 'Archive'}
for phase_num in [1, 2, 3, 4, 5, 6, 7]:
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

# v5.3: Include context snapshots for reasoning continuity
if context_snapshots:
    lines.extend([
        f'',
        f'## Phase Context Snapshots (v5.3)',
        f'',
        f'Key decisions and context from completed phases:',
        f'',
    ])
    for snap_phase in sorted(context_snapshots.keys()):
        snap_content = context_snapshots[snap_phase]
        lines.extend([
            f'### Phase {snap_phase}',
            f'',
            snap_content,
            f'',
        ])

# Write state file
os.makedirs(os.path.dirname(state_file), exist_ok=True)
with open(state_file, 'w') as f:
    f.write('\n'.join(lines))

print(f'Autopilot state saved: {state_file}', file=sys.stderr)
" "$ACTIVE_CHANGE" "$CHANGE_NAME" "$PHASE_RESULTS_DIR" "$STATE_FILE" "$EXEC_MODE" "$ANCHOR_SHA" 2>/dev/null

exit 0

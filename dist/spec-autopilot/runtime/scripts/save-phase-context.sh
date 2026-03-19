#!/usr/bin/env bash
# save-phase-context.sh
# Phase boundary context snapshot for crash recovery and compaction resilience.
# Called from main thread (synchronous Bash) at the end of each Phase.
#
# Usage: save-phase-context.sh <phase> <mode> '<context_json>'
#   phase: 0-7
#   mode: full | lite | minimal
#   context_json: JSON with fields: summary, decisions, constraints, next_phase_context
#
# Output: Writes to {change_dir}/context/phase-context-snapshots/phase-{N}-context.md
# Exit: Always 0 (informational, never blocks orchestration)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

PHASE="${1:-}"
MODE="${2:-full}"
CONTEXT_JSON="${3:-}"
[ -z "$CONTEXT_JSON" ] && CONTEXT_JSON='{}'

if [ -z "$PHASE" ]; then
  echo "Usage: save-phase-context.sh <phase> <mode> '<context_json>'" >&2
  exit 0
fi

# --- Find active change directory (unified resolution) ---
ACTIVE_CHANGE=$(resolve_active_change_dir) || exit 0
SNAPSHOTS_DIR="$ACTIVE_CHANGE/context/phase-context-snapshots"
mkdir -p "$SNAPSHOTS_DIR" 2>/dev/null || true

SNAPSHOT_FILE="$SNAPSHOTS_DIR/phase-${PHASE}-context.md"
PHASE_LABEL=$(get_phase_label "$PHASE")

# --- Generate ISO-8601 timestamp ---
TIMESTAMP=$(python3 -c "from datetime import datetime,timezone; print(datetime.now(timezone.utc).isoformat())" 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%SZ")

# --- Build context snapshot markdown ---
python3 -c "
import json, sys
from datetime import datetime

phase = sys.argv[1]
mode = sys.argv[2]
context_json = sys.argv[3]
phase_label = sys.argv[4]
timestamp = sys.argv[5]
snapshot_file = sys.argv[6]

# Parse context JSON
try:
    ctx = json.loads(context_json) if context_json else {}
except (json.JSONDecodeError, ValueError):
    ctx = {}

summary = ctx.get('summary', '')
decisions = ctx.get('decisions', [])
constraints = ctx.get('constraints', [])
next_context = ctx.get('next_phase_context', '')
artifacts = ctx.get('artifacts', [])

lines = [
    f'# Phase {phase} Context Snapshot — {phase_label}',
    f'',
    f'> Auto-saved at {timestamp} | Mode: {mode}',
    f'',
]

if summary:
    lines.extend([
        f'## 关键决策摘要',
        f'',
        summary,
        f'',
    ])

if decisions:
    lines.extend([
        f'## 决策记录',
        f'',
    ])
    for d in decisions:
        if isinstance(d, dict):
            lines.append(f'- **{d.get(\"topic\", \"决策\")}**: {d.get(\"decision\", \"\")} (理由: {d.get(\"rationale\", \"\")})')
        else:
            lines.append(f'- {d}')
    lines.append('')

if constraints:
    lines.extend([
        f'## 发现的约束',
        f'',
    ])
    for c in constraints:
        lines.append(f'- {c}')
    lines.append('')

if artifacts:
    lines.extend([
        f'## 产出文件',
        f'',
    ])
    for a in artifacts:
        lines.append(f'- \`{a}\`')
    lines.append('')

if next_context:
    lines.extend([
        f'## 下阶段所需上下文',
        f'',
        next_context,
        f'',
    ])

import os
os.makedirs(os.path.dirname(snapshot_file), exist_ok=True)
with open(snapshot_file, 'w') as f:
    f.write('\n'.join(lines))
" "$PHASE" "$MODE" "$CONTEXT_JSON" "$PHASE_LABEL" "$TIMESTAMP" "$SNAPSHOT_FILE" 2>/dev/null

exit 0

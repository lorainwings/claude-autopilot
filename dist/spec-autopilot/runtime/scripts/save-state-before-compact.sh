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
#         AND openspec/changes/<active>/context/state-snapshot.json (v7.0: 统一控制面工件)

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
SNAPSHOT_JSON_FILE="$ACTIVE_CHANGE/context/state-snapshot.json"

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
import json, os, sys, glob, re, hashlib
from datetime import datetime, timezone

change_dir = sys.argv[1]
change_name = sys.argv[2]
phase_results_dir = sys.argv[3]
state_file = sys.argv[4]
exec_mode = sys.argv[5] if len(sys.argv) > 5 else 'full'
anchor_sha = sys.argv[6] if len(sys.argv) > 6 else ''
scripts_dir = sys.argv[7] if len(sys.argv) > 7 else ''
snapshot_json_file = sys.argv[8] if len(sys.argv) > 8 else ''

# Scan all checkpoints — mode-aware phase sequence
phases = {}
last_completed = 0

# import _phase_graph for consistent phase sequences
phase_scan_list = None
if scripts_dir:
    try:
        import importlib.util
        _pg_spec = importlib.util.spec_from_file_location('_phase_graph', os.path.join(scripts_dir, '_phase_graph.py'))
        if _pg_spec and _pg_spec.loader:
            _pg = importlib.util.module_from_spec(_pg_spec)
            _pg_spec.loader.exec_module(_pg)
            phase_scan_list = _pg.get_phase_sequence(exec_mode)
    except Exception:
        pass

if phase_scan_list is None:
    if exec_mode == 'lite':
        phase_scan_list = [1, 5, 6, 7]
    elif exec_mode == 'minimal':
        phase_scan_list = [1, 5, 7]
    else:
        phase_scan_list = [1, 2, 3, 4, 5, 6, 7]

# v6.0: Collect full phase results for state-snapshot.json
phase_results_full = {}
for phase_num in phase_scan_list:
    pattern = os.path.join(phase_results_dir, f'phase-{phase_num}-*.json')
    files = sorted(glob.glob(pattern), key=os.path.getmtime, reverse=True)
    # Exclude progress/interim/tmp files
    files = [f for f in files if not f.endswith('-progress.json') and not f.endswith('-interim.json') and not f.endswith('.tmp')]
    if files:
        try:
            with open(files[0]) as f:
                data = json.load(f)
            phases[phase_num] = {
                'status': data.get('status', 'unknown'),
                'summary': data.get('summary', ''),
                'file': os.path.basename(files[0])
            }
            phase_results_full[phase_num] = {
                'status': data.get('status', 'unknown'),
                'summary': data.get('summary', ''),
                'file': os.path.basename(files[0]),
                'artifacts': data.get('artifacts', []),
            }
            if data.get('status') in ('ok', 'warning'):
                last_completed = phase_num
        except Exception:
            phases[phase_num] = {'status': 'error', 'summary': 'JSON parse error', 'file': os.path.basename(files[0])}
            phase_results_full[phase_num] = {'status': 'error', 'summary': 'JSON parse error', 'file': os.path.basename(files[0]), 'artifacts': []}

if not phases:
    # No checkpoints yet, nothing to save
    sys.exit(0)

# next_phase: mode-aware — take the next element in the phase sequence (v5.1.51: fix P0-2)
next_phase = 7  # default: done
if last_completed < phase_scan_list[-1]:
    for i, p in enumerate(phase_scan_list):
        if p == last_completed and i + 1 < len(phase_scan_list):
            next_phase = phase_scan_list[i + 1]
            break
    else:
        # last_completed not in scan list (e.g. 0) -> start from first phase
        next_phase = phase_scan_list[0]

# Determine gate_frontier: the highest phase that passed gate (ok/warning)
gate_frontier = last_completed

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
                # v5.8: Increased from 500 to 1000 chars per snapshot for better recovery
                context_snapshots[snap_phase] = content[:1000]
        except Exception:
            pass

# Read tasks file (phase5-task-breakdown.md for lite/minimal, tasks.md for full)
tasks_summary = ''
tasks_checked = 0
tasks_unchecked = 0
breakdown_file = os.path.join(change_dir, 'context', 'phase5-task-breakdown.md')
tasks_file = os.path.join(change_dir, 'tasks.md')
# Prefer phase5-task-breakdown.md (used in lite/minimal modes)
if os.path.isfile(breakdown_file):
    tasks_file = breakdown_file
if os.path.isfile(tasks_file):
    try:
        with open(tasks_file) as f:
            content = f.read()
        tasks_checked = content.count('- [x]')
        tasks_unchecked = content.count('- [ ]')
        tasks_summary = f'{tasks_checked} completed, {tasks_unchecked} remaining'
    except Exception:
        pass

# v5.9: Scan progress files for in-progress phase sub-step tracking
progress_entries = []
if os.path.isdir(phase_results_dir):
    for pf in sorted(glob.glob(os.path.join(phase_results_dir, 'phase-*-progress.json'))):
        try:
            with open(pf) as fh:
                pdata = json.load(fh)
            fname = os.path.basename(pf)
            parts = fname.replace('phase-', '').replace('-progress.json', '')
            pnum = int(parts)
            progress_entries.append({
                'phase': pnum,
                'step': pdata.get('step', 'unknown'),
                'status': pdata.get('status', 'unknown')
            })
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

# v6.0: Compute requirement_packet_hash from requirement artifacts
requirement_packet_hash = ''
req_file = os.path.join(phase_results_dir, 'phase-1-requirements.json')
if not os.path.isfile(req_file):
    # Try glob fallback
    req_files = sorted(glob.glob(os.path.join(phase_results_dir, 'phase-1-*.json')), key=os.path.getmtime, reverse=True)
    req_files = [f for f in req_files if not f.endswith('-progress.json') and not f.endswith('-interim.json') and not f.endswith('.tmp')]
    if req_files:
        req_file = req_files[0]
if os.path.isfile(req_file):
    try:
        with open(req_file, 'rb') as fh:
            requirement_packet_hash = hashlib.sha256(fh.read()).hexdigest()[:16]
    except Exception:
        pass

# v7.1: Extract clarity_score and discussion_rounds from Phase 1 checkpoint
clarity_score = None
discussion_rounds = None
challenge_agents_activated = []
if os.path.isfile(req_file):
    try:
        with open(req_file, 'r') as fh:
            phase1_data = json.load(fh)
        clarity_score = phase1_data.get('clarity_score')
        discussion_rounds = phase1_data.get('discussion_rounds')
        challenge_agents_activated = phase1_data.get('challenge_agents_activated', [])
    except Exception:
        pass

# v7.0: 构建统一控制面工件 state-snapshot.json
now_iso = datetime.now(timezone.utc).isoformat()

# --- 活跃任务（从进度条目中提取 in_progress 的子步骤）---
active_tasks = []
for pe in progress_entries:
    if pe['status'] == 'in_progress':
        active_tasks.append({'phase': pe['phase'], 'step': pe['step']})

# --- 构建 phase_results 字典（以字符串 phase 编号为 key）---
json_phase_results = {}
for pnum in phase_scan_list:
    if pnum in phase_results_full:
        json_phase_results[str(pnum)] = phase_results_full[pnum]
    else:
        json_phase_results[str(pnum)] = {'status': 'pending', 'summary': '', 'file': None, 'artifacts': []}

# --- v7.0 新增: current_phase（当前正在执行或待执行的阶段）---
current_phase = next_phase
if active_tasks:
    # 如果有正在进行的任务，以最高 phase 为当前阶段
    current_phase = max(at['phase'] for at in active_tasks)

# --- v7.0 新增: executed_phases（已执行完成的阶段列表）---
executed_phases = []
for pnum in phase_scan_list:
    if pnum in phase_results_full and phase_results_full[pnum]['status'] in ('ok', 'warning', 'failed', 'blocked', 'error'):
        executed_phases.append(pnum)

# --- v7.0 新增: skipped_phases（根据 mode 跳过的阶段）---
full_phases = [1, 2, 3, 4, 5, 6, 7]
skipped_phases = [p for p in full_phases if p not in phase_scan_list]

# --- v7.0 新增: recovery_source（恢复来源，保存时默认为 "fresh"）---
recovery_source = 'fresh'
recovery_reason = None
resume_from_phase = None

# --- v7.0 新增: discarded_artifacts（需要丢弃的工件）---
discarded_artifacts = []

# --- v7.0 新增: replay_required_tasks（需要重放的任务）---
replay_required_tasks = []

# --- v7.0 新增: report_state（Phase 6 报告产物扫描）---
report_state = {
    'report_format': None,
    'report_path': None,
    'report_url': None,
    'allure_results_dir': None,
    'suite_results': None,
    'anomaly_alerts': [],
}
# 从 Phase 6 结果中扫描报告信息
if 6 in phase_results_full:
    p6_data = phase_results_full[6]
    # 优先从顶层字段读取（Phase 6 checkpoint 权威来源）
    if p6_data.get('report_path'):
        report_state['report_path'] = p6_data['report_path']
    if p6_data.get('report_format'):
        report_state['report_format'] = p6_data['report_format']
    if p6_data.get('report_url'):
        report_state['report_url'] = p6_data['report_url']
    if p6_data.get('allure_results_dir'):
        report_state['allure_results_dir'] = p6_data['allure_results_dir']
    if p6_data.get('suite_results'):
        report_state['suite_results'] = p6_data['suite_results']
    if p6_data.get('anomaly_alerts'):
        report_state['anomaly_alerts'] = p6_data['anomaly_alerts']
    # 从 artifacts 数组补充（向后兼容）
    p6_artifacts = p6_data.get('artifacts', [])
    for artifact in p6_artifacts:
        if isinstance(artifact, str):
            if artifact.endswith('.html'):
                report_state['report_path'] = artifact
                report_state['report_format'] = 'html'
            elif artifact.endswith('.md'):
                report_state['report_path'] = artifact
                report_state['report_format'] = 'markdown'
            elif 'allure-results' in artifact:
                report_state['allure_results_dir'] = artifact
        elif isinstance(artifact, dict):
            if artifact.get('type') == 'report':
                report_state['report_path'] = artifact.get('path')
                report_state['report_format'] = artifact.get('format')
                report_state['report_url'] = artifact.get('url')
            elif artifact.get('type') == 'allure':
                report_state['allure_results_dir'] = artifact.get('path')
            elif artifact.get('type') == 'suite_results':
                report_state['suite_results'] = artifact.get('data')
            elif artifact.get('type') == 'anomaly':
                report_state['anomaly_alerts'].append(artifact)
# 扫描 Phase 6 报告文件目录（多路径兼容）
for p6_report_dir in [
    os.path.join(change_dir, 'reports'),          # change 级 reports/
    os.path.join(change_dir, 'context', 'reports'),  # 向后兼容 context/reports/
]:
    if os.path.isdir(p6_report_dir):
        for rpt in sorted(glob.glob(os.path.join(p6_report_dir, '*'))):
            rpt_name = os.path.basename(rpt)
            if rpt_name.endswith('.html') and not report_state['report_path']:
                report_state['report_path'] = rpt
                report_state['report_format'] = 'html'
            elif 'allure-results' in rpt_name and not report_state['allure_results_dir']:
                report_state['allure_results_dir'] = rpt
# 工作目录根 allure-results/（Phase 6 模板默认输出位置）
_project_root = os.path.dirname(os.path.dirname(change_dir))  # change_dir = .../openspec/changes/<name>
project_allure_dir = os.path.join(_project_root, 'allure-results')
if os.path.isdir(project_allure_dir) and not report_state['allure_results_dir']:
    report_state['allure_results_dir'] = project_allure_dir

# --- v7.0 新增: active_agents（当前活跃的 agent 列表）---
active_agents = []
agents_dir = os.path.join(change_dir, 'context', 'agents')
if os.path.isdir(agents_dir):
    for agent_file in sorted(glob.glob(os.path.join(agents_dir, 'agent-*.json'))):
        try:
            with open(agent_file) as f:
                adata = json.load(f)
            if adata.get('status') == 'running':
                active_agents.append({
                    'id': adata.get('id', os.path.basename(agent_file)),
                    'phase': adata.get('phase'),
                    'task': adata.get('task'),
                    'started_at': adata.get('started_at'),
                })
        except Exception:
            pass

# --- v7.0 新增: model_routing（当前模型路由信息）---
model_routing = None
routing_file = os.path.join(change_dir, '..', '..', '..', '.claude', 'autopilot.config.yaml')
routing_file = os.path.normpath(routing_file)
if os.path.isfile(routing_file):
    try:
        # 简单提取 model_routing 相关配置
        with open(routing_file) as f:
            cfg_content = f.read()
        # 解析 YAML 需要 pyyaml，用正则做 fallback
        import re
        model_match = re.search(r'model_routing:\s*\n((?:\s+.+\n)*)', cfg_content)
        if model_match:
            model_routing = {'raw_config': model_match.group(0).strip()[:500]}
    except Exception:
        pass

snapshot_data = {
    'schema_version': '7.1',
    'saved_at': now_iso,
    'change_name': change_name,
    # --- v7.0 新增字段 ---
    'mode': exec_mode,
    'current_phase': current_phase,
    'executed_phases': executed_phases,
    'skipped_phases': skipped_phases,
    'recovery_source': recovery_source,
    'recovery_reason': recovery_reason,
    'resume_from_phase': resume_from_phase,
    'discarded_artifacts': discarded_artifacts,
    'replay_required_tasks': replay_required_tasks,
    'report_state': report_state,
    'active_agents': active_agents,
    'active_tasks': active_tasks,
    'model_routing': model_routing,
    # --- 保留的 v6.0 字段 ---
    'execution_mode': exec_mode,
    'anchor_sha': anchor_sha or None,
    'requirement_packet_hash': requirement_packet_hash or None,
    'clarity_score': clarity_score,
    'discussion_rounds': discussion_rounds,
    'challenge_agents_activated': challenge_agents_activated,
    'gate_frontier': gate_frontier,
    'last_completed_phase': last_completed,
    'next_action': {
        'phase': next_phase,
        'type': 'resume',
        'description': f'Resume from Phase {next_phase}',
    },
    'phase_results': json_phase_results,
    'phase_sequence': phase_scan_list,
    'tasks_progress': {
        'completed': tasks_checked,
        'remaining': tasks_unchecked,
    },
    'phase5_task_details': phase5_task_details,
    'progress_entries': progress_entries,
    'review_status': None,
    'fixup_status': None,
    'archive_status': None,
    'recovery_confidence': 'high',
}

# v7.0: 在所有字段写入后最后计算 snapshot_hash
snapshot_content = json.dumps(snapshot_data, sort_keys=True, ensure_ascii=False)
snapshot_hash = hashlib.sha256(snapshot_content.encode('utf-8')).hexdigest()[:16]
snapshot_data['snapshot_hash'] = snapshot_hash

if snapshot_json_file:
    os.makedirs(os.path.dirname(snapshot_json_file), exist_ok=True)
    with open(snapshot_json_file, 'w') as f:
        json.dump(snapshot_data, f, indent=2, ensure_ascii=False)
    print(f'State snapshot saved: {snapshot_json_file} (hash={snapshot_hash})', file=sys.stderr)

# Generate state markdown (legacy, kept for human-readable fallback)
lines = [
    f'# Autopilot State - {change_name}',
    f'',
    f'> Auto-saved before context compaction at {now_iso}',
    f'> This file is auto-generated. Re-injected into context after compaction.',
    f'> **Primary control state**: state-snapshot.json v7.1 (snapshot_hash={snapshot_hash})',
    f'',
    f'## Current Progress',
    f'',
    f'- **Active change**: \`{change_name}\`',
    f'- **Last completed phase**: {last_completed}',
    f'- **Next phase to execute**: {next_phase}',
    f'- **Change directory**: \`openspec/changes/{change_name}/\`',
    f'- **Execution mode**: \`{exec_mode}\`',
    f'- **Gate frontier**: {gate_frontier}',
    f'- **Snapshot hash**: \`{snapshot_hash}\`',
]

if requirement_packet_hash:
    lines.append(f'- **Requirement packet hash**: \`{requirement_packet_hash}\`')

if anchor_sha:
    lines.append(f'- **Anchor SHA**: \`{anchor_sha}\`')

if tasks_summary:
    lines.append(f'- **Tasks progress**: {tasks_summary}')

# v5.9: Include in-progress phase sub-step for fine-grained recovery
if progress_entries:
    in_progress = [pe for pe in progress_entries if pe['status'] == 'in_progress']
    if in_progress:
        latest = max(in_progress, key=lambda x: x['phase'])
        lp = latest['phase']
        ls = latest['step']
        lines.append(f'- **Current in-progress phase**: {lp} (sub-step: {ls})')

if phase5_task_details:
    lines.extend([
        f'',
        f'## Phase 5 Task Progress',
        f'',
        f'| Task | Status | Summary |',
        f'|------|--------|---------|',
    ])
    for td in phase5_task_details:
        lines.append(f'| {td[\"number\"]} | {td[\"status\"]} | {td[\"summary\"]} |')

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
for phase_num in phase_scan_list:
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
    f'1. Read state-snapshot.json for structured recovery (preferred)',
    f'2. Verify snapshot_hash consistency',
    f'3. Resume from Phase {next_phase}',
    f'4. Call Skill(\`spec-autopilot:autopilot-gate\`) before dispatching Phase {next_phase}',
    f'5. All completed phase checkpoints are in \`openspec/changes/{change_name}/context/phase-results/\`',
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
" "$ACTIVE_CHANGE" "$CHANGE_NAME" "$PHASE_RESULTS_DIR" "$STATE_FILE" "$EXEC_MODE" "$ANCHOR_SHA" "$SCRIPT_DIR" "$SNAPSHOT_JSON_FILE" 2>/dev/null

exit 0

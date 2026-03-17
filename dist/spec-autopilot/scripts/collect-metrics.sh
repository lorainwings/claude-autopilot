#!/usr/bin/env bash
# collect-metrics.sh
# Utility: Collects execution metrics from phase checkpoint files.
# Called from Phase 7 to generate a metrics summary.
#
# Usage: bash collect-metrics.sh [project_root]
# Output: JSON summary on stdout

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

PROJECT_ROOT="${1:-$(resolve_project_root)}"
CHANGES_DIR="$PROJECT_ROOT/openspec/changes"

# Find active change
change_dir=$(find_active_change "$CHANGES_DIR" "yes") || {
  echo '{"error":"no_active_change","phases":[],"totals":{}}'
  exit 0
}

phase_results_dir="${change_dir}context/phase-results"

if [ ! -d "$phase_results_dir" ]; then
  echo '{"error":"no_phase_results","phases":[],"totals":{}}'
  exit 0
fi

# Collect metrics using python3
if ! command -v python3 &>/dev/null; then
  echo '{"error":"python3_not_found","phases":[],"totals":{}}'
  exit 0
fi

python3 -c "
import json, sys, os, glob

phase_dir = sys.argv[1]
phases = []
total_duration = 0
total_retries = 0

def latest_checkpoint(pattern):
    files = glob.glob(pattern)
    if not files:
        return None
    return max(files, key=os.path.getmtime)

for phase_num in range(1, 8):
    pattern = os.path.join(phase_dir, f'phase-{phase_num}-*.json')
    latest_file = latest_checkpoint(pattern)
    if not latest_file:
        continue

    try:
        with open(latest_file) as f:
            data = json.load(f)
    except Exception:
        continue

    metrics = data.get('_metrics', {})
    duration = metrics.get('duration_seconds', 0)
    retries = metrics.get('retry_count', 0)

    phase_entry = {
        'phase': phase_num,
        'status': data.get('status', 'unknown'),
        'duration_seconds': duration,
        'retry_count': retries,
        'start_time': metrics.get('start_time', ''),
        'end_time': metrics.get('end_time', ''),
    }

    # Phase 6: extract TDD evidence fields if present
    if phase_num == 6:
        for evidence_key in ('red_evidence', 'suite_results', 'sample_failure_excerpt'):
            if evidence_key in data:
                phase_entry[evidence_key] = data[evidence_key]

    phases.append(phase_entry)

    if isinstance(duration, (int, float)):
        total_duration += duration
    if isinstance(retries, int):
        total_retries += retries

# --- 也检查 Phase 6.5 代码审查 checkpoint ---
review_pattern = os.path.join(phase_dir, 'phase-6.5-*.json')
review_file = latest_checkpoint(review_pattern)
if review_file:
    try:
        with open(review_file) as f:
            review_data = json.load(f)
        review_metrics = review_data.get('_metrics', {})
        review_duration = review_metrics.get('duration_seconds', 0)
        phases.append({
            'phase': 6.5,
            'status': review_data.get('status', 'unknown'),
            'duration_seconds': review_duration,
            'retry_count': review_metrics.get('retry_count', 0),
            'start_time': review_metrics.get('start_time', ''),
            'end_time': review_metrics.get('end_time', ''),
        })
        if isinstance(review_duration, (int, float)):
            total_duration += review_duration
    except Exception:
        pass

# 按 phase 编号排序
phases.sort(key=lambda p: p['phase'])

# === 格式化工具函数 ===
def format_duration(seconds):
    if not isinstance(seconds, (int, float)) or seconds <= 0:
        return '—'
    minutes = int(seconds // 60)
    secs = int(seconds % 60)
    if minutes > 0:
        return f'{minutes}m {secs:02d}s'
    return f'{secs}s'

# === Markdown 表格 ===
md = []
md.append('| Phase | Status | Duration | Retries |')
md.append('|-------|--------|----------|---------|')
status_icons = {'ok': 'ok', 'warning': 'WARN', 'blocked': 'BLOCKED', 'failed': 'FAIL', 'unknown': '?'}
for p in phases:
    s = status_icons.get(p['status'], p['status'])
    phase_label = str(p['phase']) if isinstance(p['phase'], int) else f\"{p['phase']}\"
    md.append(f\"| {phase_label} | {s} | {format_duration(p['duration_seconds'])} | {p['retry_count']} |\")
md.append(f'| **Total** | | **{format_duration(total_duration)}** | **{total_retries}** |')

# === ASCII 条形图（耗时分布）===
max_dur = max((p['duration_seconds'] for p in phases if isinstance(p['duration_seconds'], (int, float))), default=1) or 1
bar_width = 30
chart = []
chart.append('')
chart.append('Duration Distribution:')
chart.append('')
for p in phases:
    d = p['duration_seconds'] if isinstance(p['duration_seconds'], (int, float)) else 0
    bar_len = int((d / max_dur) * bar_width) if max_dur > 0 else 0
    bar = chr(9608) * bar_len + chr(9617) * (bar_width - bar_len)
    pct = (d / total_duration * 100) if total_duration > 0 else 0
    phase_label = str(p['phase']).rjust(4)
    chart.append(f'  Phase {phase_label} |{bar}| {format_duration(d)} ({pct:.0f}%)')
chart.append('')

result = {
    'phases': phases,
    'totals': {
        'total_duration_seconds': total_duration,
        'total_retries': total_retries,
        'phases_completed': len(phases),
    },
    'markdown_table': '\\n'.join(md),
    'ascii_chart': '\\n'.join(chart),
}

# === 知识库统计（v2.4.0 新增）===
knowledge_file = os.path.normpath(os.path.join(phase_dir, '..', '..', '..', '.autopilot-knowledge.json'))
knowledge_stats = {}
if os.path.isfile(knowledge_file):
    try:
        with open(knowledge_file) as f:
            kdata = json.load(f)
        knowledge_stats = kdata.get('stats', {})
        knowledge_stats['file_path'] = knowledge_file
    except Exception:
        pass
result['knowledge_stats'] = knowledge_stats

print(json.dumps(result, indent=2, ensure_ascii=False))
" "$phase_results_dir"

exit 0

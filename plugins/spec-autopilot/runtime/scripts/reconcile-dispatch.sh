#!/usr/bin/env bash
# reconcile-dispatch.sh
# Archive 前做 plan/actual reconcile — 逐项对比每个 planned agent 是否实际执行，
# 执行结果是否符合预期，是否有未计划的 agent 执行。
#
# Usage:
#   reconcile-dispatch.sh <project_root> <change_name>
#
# Args:
#   project_root: 项目根目录
#   change_name: 变更名称 (openspec/changes/<change_name>)
#
# Output: 结构化 JSON on stdout
#   成功: {"status": "ok", "summary": "..."}
#   失败: {"status": "blocked", "mismatches": [...]}

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

PROJECT_ROOT="${1:-$(resolve_project_root)}"
CHANGE_NAME="${2:-}"

# --- 参数校验 ---
if [ -z "$CHANGE_NAME" ]; then
  echo "ERROR: 缺少 change_name 参数" >&2
  exit 1
fi

CONTEXT_DIR="$PROJECT_ROOT/openspec/changes/$CHANGE_NAME/context"

if [ ! -d "$CONTEXT_DIR" ]; then
  echo '{"status": "ok", "summary": "context 目录不存在，跳过 reconcile"}'
  exit 0
fi

# --- Reconcile 核心逻辑 (Python3) ---
python3 -c "
import json, sys, os, glob
from datetime import datetime, timezone

context_dir = sys.argv[1]

plan_file = os.path.join(context_dir, 'dispatch-plan.json')
actual_file = os.path.join(context_dir, 'dispatch-actual.json')

# 同时支持多 dispatch 场景（扫描 dispatch-plan-*.json）
plan_files = sorted(glob.glob(os.path.join(context_dir, 'dispatch-plan*.json')))
actual_files = sorted(glob.glob(os.path.join(context_dir, 'dispatch-actual*.json')))

# 如果没有 plan 文件，视为无 dispatch 流程，直接通过
if not plan_files:
    result = {
        'status': 'ok',
        'summary': '无 dispatch plan 文件，跳过 reconcile',
        'reconciled_at': datetime.now(timezone.utc).isoformat(),
        'plan_count': 0,
        'actual_count': len(actual_files),
    }
    print(json.dumps(result, ensure_ascii=False))
    sys.exit(0)

# 加载所有 plan 和 actual
plans = []
for pf in plan_files:
    try:
        with open(pf) as f:
            plans.append(json.load(f))
    except (json.JSONDecodeError, ValueError, OSError):
        plans.append({'_error': f'无法解析: {os.path.basename(pf)}'})

actuals = []
for af in actual_files:
    try:
        with open(af) as f:
            actuals.append(json.load(f))
    except (json.JSONDecodeError, ValueError, OSError):
        actuals.append({'_error': f'无法解析: {os.path.basename(af)}'})

mismatches = []

# === 检查 1: 每个 planned agent 是否有对应的 actual ===
planned_agents = set()
for p in plans:
    if '_error' in p:
        mismatches.append({
            'type': 'plan_parse_error',
            'detail': p['_error'],
        })
        continue
    agent = p.get('resolved_agent', p.get('requested_agent', 'unknown'))
    planned_agents.add(agent)

actual_agents = set()
for a in actuals:
    if '_error' in a:
        mismatches.append({
            'type': 'actual_parse_error',
            'detail': a['_error'],
        })
        continue
    agent = a.get('actual_agent', 'unknown')
    actual_agents.add(agent)

# 已计划但未执行的 agent
missing_agents = planned_agents - actual_agents
for ma in sorted(missing_agents):
    mismatches.append({
        'type': 'planned_not_executed',
        'agent': ma,
        'detail': f'Agent \"{ma}\" 在 plan 中但未在 actual 中找到执行记录',
    })

# === 检查 2: 未计划但实际执行的 agent ===
unplanned_agents = actual_agents - planned_agents
for ua in sorted(unplanned_agents):
    mismatches.append({
        'type': 'unplanned_execution',
        'agent': ua,
        'detail': f'Agent \"{ua}\" 未在 plan 中但实际执行了',
    })

# === 检查 3: 每个 actual 的执行状态 ===
for a in actuals:
    if '_error' in a:
        continue
    status = a.get('exit_status', 'unknown')
    agent = a.get('actual_agent', 'unknown')
    if status in ('failed', 'blocked'):
        mismatches.append({
            'type': 'execution_failed',
            'agent': agent,
            'exit_status': status,
            'detail': f'Agent \"{agent}\" 执行状态为 {status}',
        })

# === 检查 4: plan vs actual 的 diffs ===
for a in actuals:
    if '_error' in a:
        continue
    diffs = a.get('diffs', [])
    for d in diffs:
        mismatches.append({
            'type': 'plan_actual_drift',
            'agent': a.get('actual_agent', 'unknown'),
            'field': d.get('field', 'unknown'),
            'planned': d.get('planned'),
            'actual': d.get('actual'),
        })

# === 输出结果 ===
if mismatches:
    result = {
        'status': 'blocked',
        'reconciled_at': datetime.now(timezone.utc).isoformat(),
        'plan_count': len(plans),
        'actual_count': len(actuals),
        'mismatch_count': len(mismatches),
        'mismatches': mismatches,
    }
else:
    result = {
        'status': 'ok',
        'summary': f'{len(plans)} dispatch(es) 全部 reconcile 通过',
        'reconciled_at': datetime.now(timezone.utc).isoformat(),
        'plan_count': len(plans),
        'actual_count': len(actuals),
    }

print(json.dumps(result, ensure_ascii=False))
" "$CONTEXT_DIR"

exit $?

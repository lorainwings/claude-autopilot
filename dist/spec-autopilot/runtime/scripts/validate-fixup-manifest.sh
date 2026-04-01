#!/usr/bin/env bash
# validate-fixup-manifest.sh
# Phase 7 归档前逐项映射校验 — 读取 fixup-manifest.json，验证每个条目的
# squash_result，有任一缺口（squash_result = "missing"）即输出 blocked。
#
# Usage:
#   validate-fixup-manifest.sh <project_root> <change_name>
#
# Args:
#   project_root: 项目根目录
#   change_name: 变更名称 (openspec/changes/<change_name>)
#
# Output: 结构化 JSON on stdout
#   通过: {"status": "ok", "total": N, "squashed": M, "missing": 0, "gaps": []}
#   阻断: {"status": "blocked", "total": N, "squashed": M, "missing": K, "gaps": [...]}

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
MANIFEST_FILE="$CONTEXT_DIR/fixup-manifest.json"

if [ ! -f "$MANIFEST_FILE" ]; then
  echo '{"status": "ok", "total": 0, "squashed": 0, "missing": 0, "gaps": [], "note": "fixup-manifest.json 不存在，跳过校验"}'
  exit 0
fi

# --- 逐项校验 (Python3) ---
python3 -c "
import json, sys

manifest_file = sys.argv[1]

try:
    with open(manifest_file) as f:
        manifest = json.load(f)
except (json.JSONDecodeError, ValueError, OSError) as e:
    print(json.dumps({
        'status': 'blocked',
        'total': 0,
        'squashed': 0,
        'missing': 0,
        'gaps': [],
        'error': f'无法解析 fixup-manifest.json: {str(e)}',
    }))
    sys.exit(0)

entries = manifest.get('entries', [])
total = len(entries)

# 逐项检查 squash_result
gaps = []
squashed_count = 0
pending_count = 0
missing_count = 0

for entry in entries:
    sr = entry.get('squash_result', 'missing')
    phase = entry.get('checkpoint_phase', '?')
    cp_id = entry.get('checkpoint_id', '?')

    if sr == 'squashed':
        squashed_count += 1
    elif sr == 'pending':
        pending_count += 1
        # pending 也视为缺口 — fixup 存在但尚未 squash
        gaps.append({
            'checkpoint_id': cp_id,
            'checkpoint_phase': phase,
            'squash_result': sr,
            'detail': f'Phase {phase} fixup commit 存在但未 squash',
        })
    elif sr == 'missing':
        missing_count += 1
        gaps.append({
            'checkpoint_id': cp_id,
            'checkpoint_phase': phase,
            'squash_result': sr,
            'detail': f'Phase {phase} 缺少 fixup commit',
        })

# 判定状态: 有 missing 即 blocked，pending 也视为 blocked（需先完成 autosquash）
if gaps:
    result = {
        'status': 'blocked',
        'total': total,
        'squashed': squashed_count,
        'pending': pending_count,
        'missing': missing_count,
        'gaps': gaps,
    }
else:
    result = {
        'status': 'ok',
        'total': total,
        'squashed': squashed_count,
        'pending': pending_count,
        'missing': missing_count,
        'gaps': [],
    }

print(json.dumps(result, ensure_ascii=False))
" "$MANIFEST_FILE"

exit $?

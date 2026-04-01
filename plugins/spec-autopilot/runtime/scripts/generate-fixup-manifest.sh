#!/usr/bin/env bash
# generate-fixup-manifest.sh
# 建立 fixup-manifest.json — 扫描所有 checkpoint 和对应的 fixup commit，
# 记录每个条目的 checkpoint_id、所属 phase、期望 fixup message、实际 SHA 和 squash 状态。
#
# Usage:
#   generate-fixup-manifest.sh <project_root> <change_name> [mode]
#
# Args:
#   project_root: 项目根目录
#   change_name: 变更名称 (openspec/changes/<change_name>)
#   mode: 运行模式 (full/lite/minimal) 默认 full
#
# Output: fixup-manifest.json 路径 on stdout
# Side effect: 写入 openspec/changes/<change>/context/fixup-manifest.json

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

PROJECT_ROOT="${1:-$(resolve_project_root)}"
CHANGE_NAME="${2:-}"
MODE="${3:-full}"

# --- 参数校验 ---
if [ -z "$CHANGE_NAME" ]; then
  echo "ERROR: 缺少 change_name 参数" >&2
  exit 1
fi

CONTEXT_DIR="$PROJECT_ROOT/openspec/changes/$CHANGE_NAME/context"
PHASE_RESULTS_DIR="$CONTEXT_DIR/phase-results"
OUTPUT_FILE="$CONTEXT_DIR/fixup-manifest.json"

if [ ! -d "$PHASE_RESULTS_DIR" ]; then
  # 无 phase-results 目录，输出空清单
  python3 -c "
import json, sys
from datetime import datetime, timezone
result = {
    'manifest_version': '1.0',
    'generated_at': datetime.now(timezone.utc).isoformat(),
    'change_name': sys.argv[1],
    'entries': [],
    'total': 0,
    'squashed': 0,
    'pending': 0,
    'missing': 0,
}
output_file = sys.argv[2]
with open(output_file, 'w') as f:
    json.dump(result, f, ensure_ascii=False, indent=2)
print(output_file)
" "$CHANGE_NAME" "$OUTPUT_FILE"
  exit 0
fi

# --- 确定要扫描的 phase 序列 ---
PHASES=$(get_phase_sequence "$MODE")

# --- 扫描 checkpoint 和 fixup commit (Python3) ---
python3 -c "
import json, sys, os, glob, subprocess
from datetime import datetime, timezone

project_root = sys.argv[1]
change_name = sys.argv[2]
phases_str = sys.argv[3]
phase_results_dir = sys.argv[4]
output_file = sys.argv[5]

phases = [int(p) for p in phases_str.split()]

entries = []

for phase in phases:
    # 查找该 phase 的 checkpoint 文件
    pattern = os.path.join(phase_results_dir, f'phase-{phase}-*.json')
    files = sorted(glob.glob(pattern), key=lambda f: os.path.getmtime(f), reverse=True)
    # 排除临时和进度文件
    files = [
        f for f in files
        if not f.endswith('.tmp')
        and not f.endswith('-progress.json')
        and not f.endswith('-interim.json')
    ]

    if not files:
        continue

    checkpoint_file = files[0]
    checkpoint_id = os.path.basename(checkpoint_file).replace('.json', '')

    # 读取 checkpoint 内容
    try:
        with open(checkpoint_file) as fh:
            cp_data = json.load(fh)
        cp_status = cp_data.get('status', 'unknown')
    except (json.JSONDecodeError, ValueError, OSError):
        cp_status = 'error'

    # 仅对 ok/warning 状态的 checkpoint 检查 fixup
    if cp_status not in ('ok', 'warning'):
        continue

    # 期望的 fixup commit message 格式
    expected_msg = f'fixup! autopilot: {change_name} Phase {phase}'

    # 搜索 git log 中对应的 fixup commit
    actual_sha = None
    squash_result = 'missing'

    try:
        result = subprocess.run(
            ['git', 'log', '--grep', f'fixup!.*{change_name}.*Phase {phase}',
             '--format=%H', '-1'],
            cwd=project_root, capture_output=True, text=True, timeout=15
        )
        if result.returncode == 0 and result.stdout.strip():
            actual_sha = result.stdout.strip()
            squash_result = 'pending'
    except (subprocess.TimeoutExpired, FileNotFoundError, OSError):
        pass

    # 检查是否已被 squash（通过检查 SHA 是否仍在 reflog 中可达但不在 log 中）
    if actual_sha:
        try:
            # 检查 fixup commit 是否仍然存在（未被 autosquash）
            result = subprocess.run(
                ['git', 'cat-file', '-t', actual_sha],
                cwd=project_root, capture_output=True, text=True, timeout=5
            )
            if result.returncode == 0 and result.stdout.strip() == 'commit':
                # commit 仍存在，检查是否在当前 branch 上
                in_branch = subprocess.run(
                    ['git', 'branch', '--contains', actual_sha, '--list', 'HEAD'],
                    cwd=project_root, capture_output=True, text=True, timeout=5
                )
                # 如果 fixup commit 已不在当前分支，说明已被 squash
                merge_base = subprocess.run(
                    ['git', 'merge-base', '--is-ancestor', actual_sha, 'HEAD'],
                    cwd=project_root, capture_output=True, text=True, timeout=5
                )
                if merge_base.returncode == 0:
                    squash_result = 'pending'  # 仍在 HEAD 祖先链中，未 squash
                else:
                    squash_result = 'squashed'  # 不在祖先链中，已被 squash
            else:
                squash_result = 'squashed'  # SHA 不存在，已被 squash
        except (subprocess.TimeoutExpired, FileNotFoundError, OSError):
            pass

    # 也检查主 autopilot commit（非 fixup 的原始提交）
    if squash_result == 'missing':
        try:
            result = subprocess.run(
                ['git', 'log', '--grep', f'autopilot:.*{change_name}.*Phase {phase}',
                 '--format=%H', '-1'],
                cwd=project_root, capture_output=True, text=True, timeout=15
            )
            if result.returncode == 0 and result.stdout.strip():
                # 有主 commit 但无 fixup，可能已经 squash 完成
                squash_result = 'squashed'
                actual_sha = result.stdout.strip()
        except (subprocess.TimeoutExpired, FileNotFoundError, OSError):
            pass

    entries.append({
        'checkpoint_id': checkpoint_id,
        'checkpoint_phase': phase,
        'checkpoint_status': cp_status,
        'expected_fixup_message': expected_msg,
        'actual_sha': actual_sha,
        'squash_result': squash_result,
    })

# 统计
total = len(entries)
squashed = sum(1 for e in entries if e['squash_result'] == 'squashed')
pending = sum(1 for e in entries if e['squash_result'] == 'pending')
missing = sum(1 for e in entries if e['squash_result'] == 'missing')

manifest = {
    'manifest_version': '1.0',
    'generated_at': datetime.now(timezone.utc).isoformat(),
    'change_name': change_name,
    'entries': entries,
    'total': total,
    'squashed': squashed,
    'pending': pending,
    'missing': missing,
}

with open(output_file, 'w') as f:
    json.dump(manifest, f, ensure_ascii=False, indent=2)

print(output_file)
" "$PROJECT_ROOT" "$CHANGE_NAME" "$PHASES" "$PHASE_RESULTS_DIR" "$OUTPUT_FILE"

exit $?

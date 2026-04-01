#!/usr/bin/env bash
# validate-openspec-artifacts.sh
# Phase 2/3 产物验证器 — OpenSpec / FF 产物 manifest 生成和校验
#
# 用途:
#   bash validate-openspec-artifacts.sh <change_dir> [mode] [requirement_packet_hash]
#
# 功能:
#   1. 读取真实文件，校验文件存在和必要 section
#   2. 校验与 change_name 和 requirement_packet_hash 绑定
#   3. lite/minimal 跳过 OpenSpec 时，输出结构化 JSON:
#      - skipped_reason
#      - lost_governance_surface（跳过后丢失了哪些治理能力）
#      - downstream_implications（对下游 phase 的影响）
#   4. 生成产物 manifest（含 file_path, file_hash, required_sections, change_name, requirement_packet_hash）
#
# 输出: stdout 为结构化 JSON
# 错误: stderr 输出诊断信息
# 退出码: 始终 0（校验结果通过 JSON status 传递）

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

CHANGE_DIR="${1:-}"
MODE="${2:-full}"
REQ_PACKET_HASH="${3:-}"

# --- 参数校验 ---
if [ -z "$CHANGE_DIR" ]; then
  echo '{"status":"error","errors":["未提供 change 目录路径"],"warnings":[],"manifest":null,"skip_info":null}'
  echo "ERROR: 用法: validate-openspec-artifacts.sh <change_dir> [mode] [requirement_packet_hash]" >&2
  exit 0
fi

if [ ! -d "$CHANGE_DIR" ]; then
  echo "{\"status\":\"error\",\"errors\":[\"目录不存在: $CHANGE_DIR\"],\"warnings\":[],\"manifest\":null,\"skip_info\":null}"
  echo "ERROR: 目录不存在: $CHANGE_DIR" >&2
  exit 0
fi

# --- 依赖检查 ---
if ! command -v python3 &>/dev/null; then
  echo '{"status":"error","errors":["python3 未找到"],"warnings":[],"manifest":null,"skip_info":null}'
  echo "ERROR: python3 is required but not found in PATH" >&2
  exit 0
fi

# --- 主校验逻辑 (python3) ---
python3 -c "
import json
import hashlib
import sys
import os
import re

change_dir = sys.argv[1]
mode = sys.argv[2]
req_packet_hash = sys.argv[3] if len(sys.argv) > 3 and sys.argv[3] else ''

errors = []
warnings = []

# ── change_name 推导 ──
change_name = os.path.basename(change_dir.rstrip('/'))

# ── 模式判定: lite/minimal 跳过 OpenSpec ──
if mode in ('lite', 'minimal'):
    # 跳过 OpenSpec/FF 阶段，输出治理影响分析
    skip_info = {
        'skipped': True,
        'skipped_reason': f'{mode} 模式跳过 OpenSpec/FF 阶段（Phase 2/3），直接从 Phase 1 进入 Phase 5',
        'lost_governance_surface': [
            'OpenSpec 规格文档验证（goals/scope/constraints/acceptance-criteria section 校验）',
            'FF (Fast-Forward) 产物完整性验证',
            '规格与需求 packet 的双向追溯绑定',
            '产物 manifest hash 完整性链',
            'OpenSpec section 覆盖度检查',
        ],
        'downstream_implications': [
            'Phase 5 实现缺少 OpenSpec 作为设计约束，完全依赖 requirement-packet.json',
            'Phase 4 测试设计无法引用 OpenSpec 中的 scope/constraints',
            'Phase 6 报告无法引用规格文档进行合规性对比',
            'Code review 缺少 OpenSpec 作为评审基准',
        ],
        'mode': mode,
        'change_name': change_name,
    }

    result = {
        'status': 'warning',
        'errors': [],
        'warnings': [f'{mode} 模式: OpenSpec/FF 阶段已跳过，治理面受限'],
        'manifest': None,
        'skip_info': skip_info,
    }
    print(json.dumps(result, ensure_ascii=False))
    sys.exit(0)

# ── full 模式: 真实产物校验 ──

# 定义 OpenSpec 核心 section（在产物文件中必须存在）
REQUIRED_SECTIONS = ['goals', 'scope', 'constraints', 'acceptance-criteria']

# OpenSpec 产物可能存放的位置
OPENSPEC_CANDIDATES = [
    os.path.join(change_dir, 'openspec.md'),
    os.path.join(change_dir, 'open-spec.md'),
    os.path.join(change_dir, 'spec.md'),
    os.path.join(change_dir, 'context', 'openspec.md'),
    os.path.join(change_dir, 'context', 'open-spec.md'),
]

# FF 产物可能存放的位置
FF_CANDIDATES = [
    os.path.join(change_dir, 'fast-forward.md'),
    os.path.join(change_dir, 'ff.md'),
    os.path.join(change_dir, 'context', 'fast-forward.md'),
    os.path.join(change_dir, 'context', 'ff.md'),
]

def find_first_existing(candidates):
    \"\"\"从候选路径中找到第一个存在的文件\"\"\"
    for c in candidates:
        if os.path.isfile(c):
            return c
    return None

def compute_file_hash(filepath):
    \"\"\"计算文件 SHA-256 hash（前 16 字符）\"\"\"
    h = hashlib.sha256()
    with open(filepath, 'rb') as f:
        for chunk in iter(lambda: f.read(8192), b''):
            h.update(chunk)
    return h.hexdigest()[:16]

def check_sections(filepath, required_sections):
    \"\"\"检查 Markdown 文件中是否存在必要的 section（标题匹配）\"\"\"
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            content = f.read().lower()
    except OSError:
        return [], required_sections[:]

    found = []
    missing = []
    for section in required_sections:
        # 匹配 # Goals, ## Goals, ### Goals, # goals 等
        pattern = rf'#+\s+{re.escape(section)}'
        if re.search(pattern, content):
            found.append(section)
        else:
            # 也尝试匹配中文变体
            zh_map = {
                'goals': '目标',
                'scope': '范围',
                'constraints': '约束',
                'acceptance-criteria': '验收标准|验收条件|acceptance.criteria',
            }
            zh_pattern = zh_map.get(section, '')
            if zh_pattern and re.search(rf'#+\s+.*({zh_pattern})', content):
                found.append(section)
            else:
                missing.append(section)

    return found, missing

# ── 查找 OpenSpec 产物 ──
openspec_file = find_first_existing(OPENSPEC_CANDIDATES)
manifest_entries = []

if openspec_file:
    found_sections, missing_sections = check_sections(openspec_file, REQUIRED_SECTIONS)

    if missing_sections:
        errors.append(
            f'OpenSpec 缺少必要 section: {missing_sections}（文件: {os.path.basename(openspec_file)}）'
        )

    file_hash = compute_file_hash(openspec_file)
    manifest_entries.append({
        'artifact_type': 'openspec',
        'file_path': openspec_file,
        'file_hash': file_hash,
        'required_sections': REQUIRED_SECTIONS,
        'found_sections': found_sections,
        'missing_sections': missing_sections,
        'change_name': change_name,
        'requirement_packet_hash': req_packet_hash,
    })
else:
    errors.append(
        f'OpenSpec 产物未找到。已搜索: {[os.path.basename(c) for c in OPENSPEC_CANDIDATES]}'
    )

# ── 查找 FF 产物 ──
ff_file = find_first_existing(FF_CANDIDATES)

if ff_file:
    # FF 产物不要求完整 section，但校验文件非空
    try:
        with open(ff_file, 'r', encoding='utf-8') as f:
            ff_content = f.read()
        if len(ff_content.strip()) < 10:
            warnings.append(f'FF 产物内容过短（{len(ff_content)} 字节）: {os.path.basename(ff_file)}')
    except OSError as e:
        warnings.append(f'FF 产物读取失败: {e}')
        ff_content = ''

    file_hash = compute_file_hash(ff_file)
    manifest_entries.append({
        'artifact_type': 'fast-forward',
        'file_path': ff_file,
        'file_hash': file_hash,
        'required_sections': [],
        'found_sections': [],
        'missing_sections': [],
        'change_name': change_name,
        'requirement_packet_hash': req_packet_hash,
    })
else:
    warnings.append(
        f'FF 产物未找到（非必须，仅 Phase 3 产出）。已搜索: {[os.path.basename(c) for c in FF_CANDIDATES]}'
    )

# ── requirement_packet_hash 绑定校验 ──
if req_packet_hash:
    # 检查 packet hash 是否嵌入在产物中（可选，增强追溯性）
    for entry in manifest_entries:
        try:
            with open(entry['file_path'], 'r', encoding='utf-8') as f:
                content = f.read()
            if req_packet_hash not in content:
                warnings.append(
                    f'{entry[\"artifact_type\"]} 未嵌入 requirement_packet_hash '
                    f'（建议在文档中引用 hash 以增强追溯性）'
                )
        except OSError:
            pass
else:
    warnings.append('未提供 requirement_packet_hash，无法进行绑定校验')

# ── change_name 一致性校验 ──
# 检查产物文件是否在正确的 change 目录下
for entry in manifest_entries:
    fp = entry['file_path']
    if change_name not in fp:
        errors.append(
            f'{entry[\"artifact_type\"]} 文件路径不在 change \"{change_name}\" 目录下: {fp}'
        )

# ── 构建 manifest ──
manifest = {
    'change_name': change_name,
    'requirement_packet_hash': req_packet_hash,
    'artifacts': manifest_entries,
    'artifact_count': len(manifest_entries),
} if manifest_entries else None

# ── 汇总输出 ──
if errors:
    status = 'blocked'
else:
    status = 'ok' if len(warnings) <= 2 else 'warning'

result = {
    'status': status,
    'errors': errors,
    'warnings': warnings,
    'manifest': manifest,
    'skip_info': None,
}

print(json.dumps(result, ensure_ascii=False))

# 摘要输出到 stderr
if errors:
    print(f'BLOCKED: {len(errors)} 个错误, {len(warnings)} 个警告', file=sys.stderr)
else:
    print(f'OK: {status}, 产物 {len(manifest_entries)} 个, 警告 {len(warnings)} 个', file=sys.stderr)
" "$CHANGE_DIR" "$MODE" "$REQ_PACKET_HASH"

exit 0

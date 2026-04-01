#!/usr/bin/env bash
# validate-requirement-packet.sh
# Phase 1 产物验证器 — 将 requirement-packet.json 作为唯一需求事实源
#
# 用途:
#   bash validate-requirement-packet.sh <packet_file> [project_root]
#
# 功能:
#   1. 强校验: requirement_type, decisions, acceptance_criteria, closed_questions, packet hash
#   2. 成熟度驱动三路调研方案推荐:
#      - clear → auto-scan only
#      - partial → auto-scan + tech research
#      - ambiguous → auto-scan + tech research + web research
#   3. 输出结构化 JSON 结果
#
# 输出: stdout 为结构化 JSON
# 错误: stderr 输出诊断信息
# 退出码: 始终 0（校验结果通过 JSON status 传递）

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

PACKET_FILE="${1:-}"
PROJECT_ROOT="${2:-$(resolve_project_root)}"

# --- 参数校验 ---
if [ -z "$PACKET_FILE" ]; then
  echo '{"status":"error","errors":["未提供 packet 文件路径"],"warnings":[],"research_plan":null}'
  echo "ERROR: 用法: validate-requirement-packet.sh <packet_file> [project_root]" >&2
  exit 0
fi

if [ ! -f "$PACKET_FILE" ]; then
  echo "{\"status\":\"error\",\"errors\":[\"文件不存在: $PACKET_FILE\"],\"warnings\":[],\"research_plan\":null}"
  echo "ERROR: 文件不存在: $PACKET_FILE" >&2
  exit 0
fi

# --- 依赖检查 ---
if ! command -v python3 &>/dev/null; then
  echo '{"status":"error","errors":["python3 未找到"],"warnings":[],"research_plan":null}'
  echo "ERROR: python3 is required but not found in PATH" >&2
  exit 0
fi

if ! command -v jq &>/dev/null; then
  # 无 jq 时回退到 python3 纯解析
  echo "WARNING: jq 未找到，使用 python3 回退模式" >&2
fi

# --- 主校验逻辑 (python3) ---
python3 -c "
import json
import hashlib
import sys
import os

packet_file = sys.argv[1]
project_root = sys.argv[2]

errors = []
warnings = []

# ── 1. JSON 解析 ──
try:
    with open(packet_file, 'r', encoding='utf-8') as f:
        raw_content = f.read()
    packet = json.loads(raw_content)
except json.JSONDecodeError as e:
    print(json.dumps({
        'status': 'error',
        'errors': [f'JSON 解析失败: {e}'],
        'warnings': [],
        'research_plan': None
    }))
    sys.exit(0)
except OSError as e:
    print(json.dumps({
        'status': 'error',
        'errors': [f'文件读取失败: {e}'],
        'warnings': [],
        'research_plan': None
    }))
    sys.exit(0)

if not isinstance(packet, dict):
    print(json.dumps({
        'status': 'error',
        'errors': ['packet 必须是 JSON 对象'],
        'warnings': [],
        'research_plan': None
    }))
    sys.exit(0)

# ── 2. 必填字段校验 ──
REQUIRED_FIELDS = [
    'requirement_type',
    'decisions',
    'acceptance_criteria',
    'closed_questions',
    'maturity',
    'change_name',
]

for field in REQUIRED_FIELDS:
    if field not in packet:
        errors.append(f'缺少必填字段: {field}')
    elif packet[field] is None:
        errors.append(f'字段为 null: {field}')

# ── 3. requirement_type 校验 ──
VALID_TYPES = ['feature', 'bugfix', 'refactor', 'chore']
req_type = packet.get('requirement_type', '')
if isinstance(req_type, str):
    if req_type.lower() not in VALID_TYPES:
        errors.append(
            f'requirement_type \"{req_type}\" 无效，必须为: {VALID_TYPES}'
        )
else:
    errors.append('requirement_type 必须是字符串')

# ── 4. decisions 校验 ──
decisions = packet.get('decisions', [])
if not isinstance(decisions, list):
    errors.append('decisions 必须是数组')
elif len(decisions) == 0:
    warnings.append('decisions 数组为空（简单需求可接受）')
else:
    for idx, d in enumerate(decisions):
        prefix = f'decisions[{idx}]'
        if not isinstance(d, dict):
            errors.append(f'{prefix}: 不是对象')
            continue
        if not d.get('point') and not d.get('choice'):
            errors.append(f'{prefix}: 缺少 point 和 choice')
        if not d.get('choice'):
            warnings.append(f'{prefix}: 缺少 choice（建议补充）')
        if not d.get('rationale'):
            warnings.append(f'{prefix}: 缺少 rationale（建议补充）')

# ── 5. acceptance_criteria 校验 ──
criteria = packet.get('acceptance_criteria', [])
if not isinstance(criteria, list):
    errors.append('acceptance_criteria 必须是数组')
elif len(criteria) == 0:
    errors.append('acceptance_criteria 不能为空，至少需要一个验收标准')
else:
    for idx, c in enumerate(criteria):
        if isinstance(c, str):
            if len(c.strip()) < 5:
                warnings.append(f'acceptance_criteria[{idx}]: 内容过短，可能不够具体')
        elif isinstance(c, dict):
            if not c.get('description') and not c.get('criterion'):
                warnings.append(f'acceptance_criteria[{idx}]: 缺少 description 或 criterion')
        else:
            errors.append(f'acceptance_criteria[{idx}]: 类型无效，需为字符串或对象')

# ── 6. closed_questions 校验 ──
closed_q = packet.get('closed_questions')
if isinstance(closed_q, bool):
    if not closed_q:
        errors.append('closed_questions 为 false: 仍有未闭合的开放问题，Phase 1 不可推进')
elif isinstance(closed_q, dict):
    all_closed = closed_q.get('all_closed', False)
    open_items = closed_q.get('open_items', [])
    if not all_closed:
        if isinstance(open_items, list) and len(open_items) > 0:
            errors.append(
                f'存在 {len(open_items)} 个未闭合的开放问题: '
                + ', '.join(str(q) for q in open_items[:3])
            )
        else:
            errors.append('closed_questions.all_closed 为 false')
else:
    errors.append('closed_questions 类型无效，需为 bool 或对象')

# ── 7. maturity 校验与调研方案推荐 ──
VALID_MATURITY = ['clear', 'partial', 'ambiguous']
maturity = packet.get('maturity', '')
research_plan = None

if isinstance(maturity, str) and maturity in VALID_MATURITY:
    if maturity == 'clear':
        research_plan = {
            'maturity': 'clear',
            'strategy': 'auto-scan only',
            'agents': ['auto-scan'],
            'rationale': '需求清晰，仅需自动扫描确认技术上下文'
        }
    elif maturity == 'partial':
        research_plan = {
            'maturity': 'partial',
            'strategy': 'auto-scan + tech research',
            'agents': ['auto-scan', 'tech-research'],
            'rationale': '需求部分清晰，需补充技术调研填补信息缺口'
        }
    elif maturity == 'ambiguous':
        research_plan = {
            'maturity': 'ambiguous',
            'strategy': 'auto-scan + tech research + web research',
            'agents': ['auto-scan', 'tech-research', 'web-research'],
            'rationale': '需求模糊，需要全方位调研（代码扫描 + 技术调研 + 联网搜索）'
        }
elif maturity:
    errors.append(f'maturity \"{maturity}\" 无效，必须为: {VALID_MATURITY}')
else:
    # maturity 缺失时已在必填字段检查中报错
    pass

# ── 8. packet hash 校验 ──
declared_hash = packet.get('packet_hash', '')
if declared_hash:
    # 计算实际内容 hash（排除 packet_hash 字段本身）
    packet_for_hash = {k: v for k, v in packet.items() if k != 'packet_hash'}
    canonical = json.dumps(packet_for_hash, sort_keys=True, ensure_ascii=False)
    computed_hash = hashlib.sha256(canonical.encode('utf-8')).hexdigest()[:16]
    if declared_hash != computed_hash:
        warnings.append(
            f'packet_hash 不匹配: 声明={declared_hash}, 计算={computed_hash}。'
            '可能 packet 内容已被修改但 hash 未更新'
        )
else:
    warnings.append('缺少 packet_hash 字段（建议添加以支持完整性校验）')

# ── 9. change_name 绑定校验 ──
change_name = packet.get('change_name', '')
if isinstance(change_name, str) and change_name:
    # 检查 change_name 对应的目录是否存在
    changes_dir = os.path.join(project_root, 'openspec', 'changes', change_name)
    if os.path.isdir(project_root) and not os.path.isdir(changes_dir):
        warnings.append(
            f'change_name \"{change_name}\" 对应的目录不存在: {changes_dir}'
        )

# ── 10. 可选字段检查 ──
RECOMMENDED_FIELDS = ['summary', 'tech_constraints', 'scope', 'raw_requirement']
for field in RECOMMENDED_FIELDS:
    if field not in packet:
        warnings.append(f'建议添加字段: {field}')

# ── 汇总输出 ──
if errors:
    status = 'blocked'
else:
    status = 'ok' if len(warnings) <= 2 else 'warning'

result = {
    'status': status,
    'errors': errors,
    'warnings': warnings,
    'research_plan': research_plan,
    'packet_file': packet_file,
    'requirement_type': packet.get('requirement_type', ''),
    'maturity': packet.get('maturity', ''),
    'change_name': packet.get('change_name', ''),
    'decisions_count': len(decisions) if isinstance(decisions, list) else 0,
    'acceptance_criteria_count': len(criteria) if isinstance(criteria, list) else 0,
}

print(json.dumps(result, ensure_ascii=False))

# 同时输出摘要到 stderr 便于调试
if errors:
    print(f'BLOCKED: {len(errors)} 个错误, {len(warnings)} 个警告', file=sys.stderr)
else:
    print(f'OK: {status}, {len(warnings)} 个警告', file=sys.stderr)
" "$PACKET_FILE" "$PROJECT_ROOT"

exit 0

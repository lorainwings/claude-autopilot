#!/usr/bin/env bash
# scan-code-ref-anchors.sh — 提取代码 / 文档 / 配置中的 ownership 锚点
#
# 设计原则：
#   - 静态扫描（grep / regex），不依赖 LLM
#   - 输出统一 JSON 配对表，供 detect-anchor-drift.sh 使用
#   - 必须过滤自身（避免示例注释被误识别）
#   - 退出码恒为 0（warn-only）
#
# 锚点语法：
#   代码侧:  # CODE-REF: <doc-path>     (sh / py)
#            // CODE-REF: <doc-path>    (ts / js)
#            <!-- CODE-REF: <doc-path> --> (md)
#   文档侧:  <!-- CODE-OWNED-BY: <code-path>[, <code-path>...] -->
#   配置:    .claude/docs-ownership.yaml (mappings 列表)
#
# 用法：
#   scan-code-ref-anchors.sh [--format json|text] [--only-inline]

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_common.sh
source "$SCRIPT_DIR/_common.sh"

FORMAT="json"
ONLY_INLINE=false
while [ $# -gt 0 ]; do
  case "$1" in
    --format)
      FORMAT="${2:-json}"
      shift 2
      ;;
    --only-inline)
      ONLY_INLINE=true
      shift
      ;;
    *)
      shift
      ;;
  esac
done

PROJECT_ROOT=$(resolve_project_root)
SELF_REL="plugins/spec-autopilot/runtime/scripts/scan-code-ref-anchors.sh"

# 排除清单：fixture / 锚点语法演示 / 扫描器自检测试 — 这些路径中出现的 CODE-REF / CODE-OWNED-BY
# 是文档示例或 fixture 噪声，不应被识别为真实锚点
is_excluded_file() {
  case "$1" in
    *"/tests/fixtures/"*) return 0 ;;
    *"/skills/autopilot-docs-sync/references/anchor-syntax.md") return 0 ;;
    *"/skills/autopilot-docs-sync/references/ownership-config.md") return 0 ;;
    *"/skills/autopilot-docs-sync/references/docs-ownership.yaml.example") return 0 ;;
    *"/tests/test_scan_anchors.sh") return 0 ;;
    *"/tests/test_detect_anchor_drift.sh") return 0 ;;
    *"/tests/test_engineering_sync_gate.sh") return 0 ;;
  esac
  return 1
}

# 路径格式校验：合法路径只允许字母数字 / . _ - / ，禁止反引号 / # 占位符
is_valid_path() {
  printf '%s' "$1" | grep -qE '^[A-Za-z0-9_./-]+$'
}

# Scan roots（仅扫描这些目录以避免噪声）
SCAN_DIRS=(
  "plugins/spec-autopilot"
  "docs/plans"
)

# 累积器（行格式：source<TAB>code<TAB>doc<TAB>line）
RAW=$(mktemp)
# shellcheck disable=SC2064
trap "rm -f '$RAW'" EXIT

# ---- 内联锚点扫描 ----
for d in "${SCAN_DIRS[@]}"; do
  full="$PROJECT_ROOT/$d"
  [ -d "$full" ] || continue

  # CODE-REF (代码侧 → 文档)
  while IFS= read -r hit; do
    [ -z "$hit" ] && continue
    file="${hit%%:*}"
    rest="${hit#*:}"
    line="${rest%%:*}"
    content="${rest#*:}"
    rel="${file#"$PROJECT_ROOT"/}"
    # 过滤扫描器自身
    [ "$rel" = "$SELF_REL" ] && continue
    # 过滤排除清单（fixture / 语法示例文件）
    is_excluded_file "$rel" && continue
    # 提取 CODE-REF: 后的路径（去掉前导/尾部空白与 -->）
    docpath=$(printf '%s\n' "$content" |
      sed -n 's/.*CODE-REF:[[:space:]]*\([^[:space:]>]*\).*/\1/p')
    [ -z "$docpath" ] && continue
    # 路径格式校验，过滤反引号 / 占位符
    is_valid_path "$docpath" || continue
    printf 'inline\t%s\t%s\t%s\n' "$rel" "$docpath" "$line" >>"$RAW"
  done < <(grep -RIn -- "CODE-REF:" "$full" 2>/dev/null || true)

  # CODE-OWNED-BY (文档侧 → 代码), 支持逗号分隔
  while IFS= read -r hit; do
    [ -z "$hit" ] && continue
    file="${hit%%:*}"
    rest="${hit#*:}"
    line="${rest%%:*}"
    content="${rest#*:}"
    rel="${file#"$PROJECT_ROOT"/}"
    [ "$rel" = "$SELF_REL" ] && continue
    is_excluded_file "$rel" && continue
    paths=$(printf '%s\n' "$content" |
      sed -n 's/.*CODE-OWNED-BY:[[:space:]]*\([^>]*\)-->.*/\1/p')
    if [ -z "$paths" ]; then
      paths=$(printf '%s\n' "$content" |
        sed -n 's/.*CODE-OWNED-BY:[[:space:]]*\(.*\)/\1/p')
    fi
    [ -z "$paths" ] && continue
    # 拆分逗号
    OLD_IFS="$IFS"
    IFS=','
    # shellcheck disable=SC2086
    set -- $paths
    IFS="$OLD_IFS"
    for p in "$@"; do
      cleaned=$(printf '%s' "$p" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//; s/[[:space:]]*-->.*$//')
      [ -z "$cleaned" ] && continue
      # 路径格式校验
      is_valid_path "$cleaned" || continue
      # owned-by: code=cleaned, doc=rel (file containing the anchor)
      printf 'inline\t%s\t%s\t%s\n' "$cleaned" "$rel" "$line" >>"$RAW"
    done
  done < <(grep -RIn -- "CODE-OWNED-BY:" "$full" 2>/dev/null || true)
done

# ---- 配置 fallback (.claude/docs-ownership.yaml) ----
CFG="$PROJECT_ROOT/.claude/docs-ownership.yaml"
if [ "$ONLY_INLINE" = "false" ] && [ -f "$CFG" ]; then
  python3 - "$CFG" "$PROJECT_ROOT" >>"$RAW" 2>/dev/null <<'PY' || echo "WARN: invalid yaml" >&2
import sys, os, glob, re

cfg_path, project_root = sys.argv[1], sys.argv[2]

def parse_minimal_yaml(text):
    """轻量 YAML 解析：仅支持本配置格式 (mappings 列表 + code/code_glob/docs)."""
    mappings = []
    cur = None
    cur_docs = False
    for raw in text.splitlines():
        line = raw.rstrip()
        if not line.strip() or line.lstrip().startswith('#'):
            continue
        # top-level key
        if line.startswith('mappings:'):
            continue
        # new mapping entry
        m = re.match(r'^\s*-\s*(code|code_glob)\s*:\s*(.+)$', line)
        if m:
            if cur is not None:
                mappings.append(cur)
            cur = {'kind': m.group(1), 'value': m.group(2).strip(), 'docs': []}
            cur_docs = False
            continue
        # subsequent code/code_glob within same entry
        m = re.match(r'^\s+(code|code_glob)\s*:\s*(.+)$', line)
        if m and cur is not None:
            cur['kind'] = m.group(1)
            cur['value'] = m.group(2).strip()
            cur_docs = False
            continue
        if re.match(r'^\s+docs\s*:\s*$', line):
            cur_docs = True
            continue
        m = re.match(r'^\s+-\s*(.+)$', line)
        if m and cur_docs and cur is not None:
            cur['docs'].append(m.group(1).strip())
            continue
    if cur is not None:
        mappings.append(cur)
    return mappings

with open(cfg_path) as f:
    text = f.read()

try:
    mappings = parse_minimal_yaml(text)
except Exception:
    sys.exit(1)

for m in mappings:
    docs = m.get('docs') or []
    if not docs:
        continue
    if m['kind'] == 'code':
        codes = [m['value']]
    else:
        pat = os.path.join(project_root, m['value'])
        matches = glob.glob(pat, recursive=True)
        codes = [os.path.relpath(p, project_root) for p in matches]
    for c in codes:
        for d in docs:
            print('config\t{}\t{}\t0'.format(c, d))
PY
fi

# ---- 聚合：按 code 合并 docs，去重并稳定排序 ----
RESULT=$(
  python3 - "$RAW" <<'PY'
import sys, json, os
from collections import OrderedDict

raw_path = sys.argv[1]
entries = OrderedDict()  # code -> {'docs': set/list, 'source': 'inline'|'config'|'mixed', 'line': N}

if os.path.exists(raw_path):
    with open(raw_path) as f:
        for line in f:
            line = line.rstrip('\n')
            if not line:
                continue
            parts = line.split('\t')
            if len(parts) != 4:
                continue
            src, code, doc, ln = parts
            try:
                ln_i = int(ln)
            except ValueError:
                ln_i = 0
            if code not in entries:
                entries[code] = {'docs': [], 'source': src, 'line': ln_i}
            e = entries[code]
            if doc not in e['docs']:
                e['docs'].append(doc)
            if e['source'] != src:
                # mixed sources; prefer 'inline' as primary if any inline present
                if 'inline' in (e['source'], src):
                    e['source'] = 'inline'
                else:
                    e['source'] = src
            # earliest non-zero line wins
            if e['line'] == 0 and ln_i > 0:
                e['line'] = ln_i

anchors = []
for code in sorted(entries.keys()):
    e = entries[code]
    anchors.append({
        'code': code,
        'docs': sorted(set(e['docs'])),
        'source': e['source'],
        'line': e['line'],
    })

print(json.dumps({'anchors': anchors}, indent=2))
PY
)

if [ "$FORMAT" = "text" ]; then
  printf '%s\n' "$RESULT" | python3 -c "
import json, sys
data = json.load(sys.stdin)
for a in data['anchors']:
    print('{} [{}] -> {}'.format(a['code'], a['source'], ', '.join(a['docs'])))
"
else
  printf '%s\n' "$RESULT"
fi

exit 0

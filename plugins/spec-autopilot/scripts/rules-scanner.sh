#!/usr/bin/env bash
# rules-scanner.sh
# Utility: Scans a project's .claude/rules/ directory and CLAUDE.md,
# extracts key constraints (forbidden items, required patterns, naming conventions).
# Outputs a JSON summary for injection into sub-agent prompts.
#
# Usage: bash rules-scanner.sh <project_root>
# Output: JSON on stdout

set -uo pipefail

PROJECT_ROOT="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
RULES_DIR="$PROJECT_ROOT/.claude/rules"
CLAUDE_MD="$PROJECT_ROOT/CLAUDE.md"

# --- No rules at all → early exit ---
if [ ! -d "$RULES_DIR" ] && [ ! -f "$CLAUDE_MD" ]; then
  echo '{"rules_found":false,"constraints":[],"summary":"No .claude/rules/ directory or CLAUDE.md found"}'
  exit 0
fi

# --- Dependency check ---
if ! command -v python3 &>/dev/null; then
  echo '{"rules_found":false,"constraints":[],"summary":"python3 not available"}'
  exit 0
fi

# --- Scan via python3 ---
python3 -c "
import json, os, re, sys, glob

root = sys.argv[1]
rules_dir = os.path.join(root, '.claude', 'rules')
claude_md = os.path.join(root, 'CLAUDE.md')

constraints = []

def add(source, ctype, pattern, replacement=None, context=None):
    entry = {'source': source, 'type': ctype, 'pattern': pattern}
    if replacement:
        entry['replacement'] = replacement
    if context:
        entry['context'] = context
    constraints.append(entry)

# === 1. Scan .claude/rules/*.md files ===
if os.path.isdir(rules_dir):
    for md_path in sorted(glob.glob(os.path.join(rules_dir, '*.md'))):
        fname = os.path.basename(md_path)
        try:
            with open(md_path, 'r', errors='ignore') as f:
                content = f.read(50_000)
        except Exception:
            continue

        # --- 禁止项: 表格行 '| \`xxx\` | \`yyy\` |' 或 '禁止/禁' 模式 ---
        # 表格行: | 禁止项 | 替代方案 | 格式
        for m in re.finditer(
            r'\|\s*\x60([^\x60]+)\x60\s*\|\s*\x60([^\x60]+)\x60\s*\|',
            content
        ):
            left, right = m.group(1).strip(), m.group(2).strip()
            # 检查上下文是否为禁止表格
            line_start = content.rfind('\n', 0, m.start()) + 1
            line = content[line_start:m.end()]
            if re.search(r'禁止|禁|替代|forbidden|replace', line, re.IGNORECASE):
                add(fname, 'forbidden', left, replacement=right)
            elif re.search(r'必须|required|must', line, re.IGNORECASE):
                add(fname, 'required', right, context=left)

        # --- 禁止行: '禁止xxx' 或 '❌ xxx' ---
        for m in re.finditer(
            r'(?:禁止|❌|禁)\s*(?:使用\s*)?[\x60]([^\x60]+)[\x60]',
            content
        ):
            pat = m.group(1).strip()
            if len(pat) > 1:
                add(fname, 'forbidden', pat)

        # --- 必须使用: '必须xxx' 或 '✅ xxx' ---
        for m in re.finditer(
            r'(?:必须|✅|强制)\s*(?:使用\s*)?[\x60]([^\x60]+)[\x60]',
            content
        ):
            pat = m.group(1).strip()
            if len(pat) > 1:
                add(fname, 'required', pat)

        # --- 命名约定: 'kebab-case' / 'camelCase' / 'PascalCase' ---
        for m in re.finditer(
            r'(?:命名|naming|文件名|file\s*name)[^.:\n]{0,60}(kebab-case|camelCase|PascalCase|snake_case)',
            content, re.IGNORECASE
        ):
            add(fname, 'naming', m.group(1))

# === 2. Scan CLAUDE.md (supplementary) ===
if os.path.isfile(claude_md):
    try:
        with open(claude_md, 'r', errors='ignore') as f:
            md = f.read(80_000)
    except Exception:
        md = ''

    if md:
        # 禁止表格行
        for m in re.finditer(
            r'\|\s*\x60([^\x60]+)\x60\s*\|\s*\x60([^\x60]+)\x60\s*\|',
            md
        ):
            left, right = m.group(1).strip(), m.group(2).strip()
            line_start = md.rfind('\n', 0, m.start()) + 1
            line = md[line_start:m.end()]
            if re.search(r'禁止|禁|替代|forbidden|replace', line, re.IGNORECASE):
                add('CLAUDE.md', 'forbidden', left, replacement=right)

        # 核心约束表格
        for m in re.finditer(
            r'\|\s*\*\*([^*]+)\*\*\s*\|\s*([^|]+)\|',
            md
        ):
            key, val = m.group(1).strip(), m.group(2).strip()
            if re.search(r'必须|must|required', val, re.IGNORECASE):
                add('CLAUDE.md', 'required', val, context=key)

# === 3. Deduplicate ===
seen = set()
unique = []
for c in constraints:
    key = (c['type'], c['pattern'])
    if key not in seen:
        seen.add(key)
        unique.append(c)

# === 4. Output ===
sources = set(c['source'] for c in unique)
result = {
    'rules_found': len(unique) > 0,
    'constraints': unique,
    'summary': f'Found {len(unique)} constraints from {len(sources)} rule file(s)' if unique else 'No constraints extracted'
}

print(json.dumps(result, indent=2, ensure_ascii=False))
" "$PROJECT_ROOT"

exit 0

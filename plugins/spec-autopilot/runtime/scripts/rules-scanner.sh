#!/usr/bin/env bash
# rules-scanner.sh
# Utility: Scans a project's rules & agent configuration hierarchy,
# extracts key constraints (forbidden items, required patterns, naming conventions,
# agent priority definitions).
# Outputs a JSON summary for injection into sub-agent prompts.
#
# Scanned sources (ordered by priority):
#   1. <project_root>/CLAUDE.md              — 仓库级全局规则
#   2. <plugin_root>/CLAUDE.md               — 插件级规则
#   3. <project_root>/.claude/rules/*.md     — 声明式规则文件
#   4. <project_root>/.claude/agents/*.md    — agent 定义与优先级
#   5. Phase-local rules (via --phase-rules) — phase 级局部规则
#
# Usage: bash rules-scanner.sh <project_root> [--plugin-root <path>] [--phase-rules <path>]
# Output: JSON on stdout

set -uo pipefail

PROJECT_ROOT="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
shift || true

PLUGIN_ROOT=""
PHASE_RULES_PATH=""

# --- 参数解析 ---
while [ $# -gt 0 ]; do
  case "$1" in
    --plugin-root)
      PLUGIN_ROOT="${2:-}"
      shift 2 || break
      ;;
    --phase-rules)
      PHASE_RULES_PATH="${2:-}"
      shift 2 || break
      ;;
    *)
      shift
      ;;
  esac
done

RULES_DIR="$PROJECT_ROOT/.claude/rules"
AGENTS_DIR="$PROJECT_ROOT/.claude/agents"
CLAUDE_MD="$PROJECT_ROOT/CLAUDE.md"
PLUGIN_CLAUDE_MD=""
[ -n "$PLUGIN_ROOT" ] && PLUGIN_CLAUDE_MD="$PLUGIN_ROOT/CLAUDE.md"

# --- No rules at all → early exit ---
_has_any=false
[ -d "$RULES_DIR" ] && _has_any=true
[ -f "$CLAUDE_MD" ] && _has_any=true
[ -d "$AGENTS_DIR" ] && _has_any=true
[ -n "$PLUGIN_CLAUDE_MD" ] && [ -f "$PLUGIN_CLAUDE_MD" ] && _has_any=true
[ -n "$PHASE_RULES_PATH" ] && [ -f "$PHASE_RULES_PATH" ] && _has_any=true

if [ "$_has_any" = "false" ]; then
  echo '{"rules_found":false,"constraints":[],"agents_found":false,"agents":[],"scanned_sources":[],"summary":"No .claude/rules/, .claude/agents/, or CLAUDE.md found"}'
  exit 0
fi

# --- Dependency check ---
if ! command -v python3 &>/dev/null; then
  echo '{"rules_found":false,"constraints":[],"agents_found":false,"agents":[],"scanned_sources":[],"summary":"python3 not available"}'
  exit 0
fi

# --- Scan via python3 ---
python3 -c "
import json, os, re, sys, glob

root = sys.argv[1]
plugin_claude_md = sys.argv[2] if len(sys.argv) > 2 and sys.argv[2] else ''
phase_rules_path = sys.argv[3] if len(sys.argv) > 3 and sys.argv[3] else ''

rules_dir = os.path.join(root, '.claude', 'rules')
agents_dir = os.path.join(root, '.claude', 'agents')
claude_md = os.path.join(root, 'CLAUDE.md')

constraints = []
agents = []
scanned_sources = []

def add(source, ctype, pattern, replacement=None, context=None):
    entry = {'source': source, 'type': ctype, 'pattern': pattern}
    if replacement:
        entry['replacement'] = replacement
    if context:
        entry['context'] = context
    constraints.append(entry)

def scan_md_content(source_name, content):
    \"\"\"通用 markdown 规则提取逻辑\"\"\"
    # --- 禁止项: 表格行 '| \\\`xxx\\\` | \\\`yyy\\\` |' 或 '禁止/禁' 模式 ---
    for m in re.finditer(
        r'\|\s*\x60([^\x60]+)\x60\s*\|\s*\x60([^\x60]+)\x60\s*\|',
        content
    ):
        left, right = m.group(1).strip(), m.group(2).strip()
        line_start = content.rfind('\n', 0, m.start()) + 1
        line = content[line_start:m.end()]
        if re.search(r'禁止|禁|替代|forbidden|replace', line, re.IGNORECASE):
            add(source_name, 'forbidden', left, replacement=right)
        elif re.search(r'必须|required|must', line, re.IGNORECASE):
            add(source_name, 'required', right, context=left)

    # --- 禁止行: '禁止xxx' 或 '❌ xxx' ---
    for m in re.finditer(
        r'(?:禁止|❌|禁)\s*(?:使用\s*)?[\x60]([^\x60]+)[\x60]',
        content
    ):
        pat = m.group(1).strip()
        if len(pat) > 1:
            add(source_name, 'forbidden', pat)

    # --- 必须使用: '必须xxx' 或 '✅ xxx' ---
    for m in re.finditer(
        r'(?:必须|✅|强制)\s*(?:使用\s*)?[\x60]([^\x60]+)[\x60]',
        content
    ):
        pat = m.group(1).strip()
        if len(pat) > 1:
            add(source_name, 'required', pat)

    # --- 命名约定: 'kebab-case' / 'camelCase' / 'PascalCase' ---
    for m in re.finditer(
        r'(?:命名|naming|文件名|file\s*name)[^.:\n]{0,60}(kebab-case|camelCase|PascalCase|snake_case)',
        content, re.IGNORECASE
    ):
        add(source_name, 'naming', m.group(1))

    # --- 核心约束表格 (CLAUDE.md 风格: | **key** | value |) ---
    for m in re.finditer(
        r'\|\s*\*\*([^*]+)\*\*\s*\|\s*([^|]+)\|',
        content
    ):
        key, val = m.group(1).strip(), m.group(2).strip()
        if re.search(r'必须|must|required', val, re.IGNORECASE):
            add(source_name, 'required', val, context=key)

# === 1. Scan .claude/rules/*.md files ===
if os.path.isdir(rules_dir):
    scanned_sources.append('.claude/rules/')
    for md_path in sorted(glob.glob(os.path.join(rules_dir, '*.md'))):
        fname = os.path.basename(md_path)
        try:
            with open(md_path, 'r', errors='ignore') as f:
                content = f.read(50_000)
        except Exception:
            continue
        scan_md_content(fname, content)

# === 2. Scan CLAUDE.md (仓库级全局规则) ===
if os.path.isfile(claude_md):
    scanned_sources.append('CLAUDE.md')
    try:
        with open(claude_md, 'r', errors='ignore') as f:
            md = f.read(80_000)
    except Exception:
        md = ''
    if md:
        scan_md_content('CLAUDE.md', md)

# === 3. Scan plugin CLAUDE.md (插件级规则) ===
if plugin_claude_md and os.path.isfile(plugin_claude_md):
    rel_path = os.path.relpath(plugin_claude_md, root) if os.path.isabs(plugin_claude_md) else plugin_claude_md
    scanned_sources.append(rel_path)
    try:
        with open(plugin_claude_md, 'r', errors='ignore') as f:
            md = f.read(80_000)
    except Exception:
        md = ''
    if md:
        scan_md_content(rel_path, md)

# === 4. Scan .claude/agents/*.md (agent 定义与优先级) ===
if os.path.isdir(agents_dir):
    scanned_sources.append('.claude/agents/')
    for md_path in sorted(glob.glob(os.path.join(agents_dir, '*.md'))):
        fname = os.path.basename(md_path)
        agent_name = os.path.splitext(fname)[0]
        try:
            with open(md_path, 'r', errors='ignore') as f:
                content = f.read(50_000)
        except Exception:
            continue

        agent_entry = {
            'name': agent_name,
            'source': fname,
            'priority': 'normal',
            'domains': [],
            'forbidden_phases': [],
            'required_phases': [],
        }

        # 检测 priority 声明 (如 'priority: high' 或 '优先级: 高')
        prio_m = re.search(r'(?:priority|优先级)\s*[:：]\s*(high|low|normal|highest|critical|高|低|普通|最高|关键)', content, re.IGNORECASE)
        if prio_m:
            prio_raw = prio_m.group(1).lower()
            prio_map = {'high': 'high', '高': 'high', 'highest': 'highest', '最高': 'highest',
                        'critical': 'critical', '关键': 'critical', 'low': 'low', '低': 'low',
                        'normal': 'normal', '普通': 'normal'}
            agent_entry['priority'] = prio_map.get(prio_raw, 'normal')

        # 检测 domain 声明 (如 'domain: backend, frontend')
        domain_m = re.search(r'(?:domain|域|领域)\s*[:：]\s*(.+?)$', content, re.IGNORECASE | re.MULTILINE)
        if domain_m:
            domains_raw = domain_m.group(1).strip()
            agent_entry['domains'] = [d.strip() for d in re.split(r'[,，、;；\s]+', domains_raw) if d.strip()]

        # 检测 phase 约束 (如 'required_for_phase: 5, 6' 或 'forbidden_phase: 1')
        req_m = re.search(r'(?:required_for_phase|必须参与阶段)\s*[:：]\s*(.+?)$', content, re.IGNORECASE | re.MULTILINE)
        if req_m:
            agent_entry['required_phases'] = [int(p) for p in re.findall(r'\d+', req_m.group(1))]

        forb_m = re.search(r'(?:forbidden_phase|禁止参与阶段)\s*[:：]\s*(.+?)$', content, re.IGNORECASE | re.MULTILINE)
        if forb_m:
            agent_entry['forbidden_phases'] = [int(p) for p in re.findall(r'\d+', forb_m.group(1))]

        agents.append(agent_entry)

        # 同时提取 agent 文件中的常规规则
        scan_md_content(fname, content)
else:
    scanned_sources.append('.claude/agents/ (absent)')

# === 5. Scan phase-local rules (如果提供) ===
if phase_rules_path and os.path.isfile(phase_rules_path):
    rel_path = os.path.relpath(phase_rules_path, root) if os.path.isabs(phase_rules_path) else phase_rules_path
    scanned_sources.append(rel_path)
    try:
        with open(phase_rules_path, 'r', errors='ignore') as f:
            content = f.read(50_000)
    except Exception:
        content = ''
    if content:
        scan_md_content(rel_path, content)

# === 6. Deduplicate ===
seen = set()
unique = []
for c in constraints:
    key = (c['type'], c['pattern'])
    if key not in seen:
        seen.add(key)
        unique.append(c)

# === 7. Output ===
sources = set(c['source'] for c in unique)

# Critical rules: top forbidden items for compact injection (Phase 2/3/6)
critical = [c for c in unique if c['type'] == 'forbidden'][:10]
compact_parts = []
for c in critical:
    part = 'FORBIDDEN: ' + c['pattern']
    if c.get('replacement'):
        part += ' → use ' + c['replacement']
    compact_parts.append(part)

# Agent priority summary for dispatch decisions
agent_priority_map = {}
for a in agents:
    agent_priority_map[a['name']] = {
        'priority': a['priority'],
        'domains': a['domains'],
        'required_phases': a['required_phases'],
        'forbidden_phases': a['forbidden_phases'],
    }

result = {
    'rules_found': len(unique) > 0,
    'constraints': unique,
    'critical_rules': critical,
    'compact_summary': '; '.join(compact_parts) if compact_parts else '',
    'agents_found': len(agents) > 0,
    'agents': agents,
    'agent_priority_map': agent_priority_map,
    'scanned_sources': scanned_sources,
    'summary': f'Found {len(unique)} constraints from {len(sources)} source(s), {len(agents)} agent definition(s)' if unique or agents else 'No constraints or agents extracted'
}

print(json.dumps(result, indent=2, ensure_ascii=False))
" "$PROJECT_ROOT" "$PLUGIN_CLAUDE_MD" "$PHASE_RULES_PATH"

exit 0

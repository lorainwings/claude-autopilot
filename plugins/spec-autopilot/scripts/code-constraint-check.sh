#!/usr/bin/env bash
# code-constraint-check.sh
# Hook: PostToolUse(Task) — Phase 4/5/6 代码约束检查
# 检查生成的 artifacts 是否违反项目约束（禁止文件/模式/行数/目录范围）。
# 约束来源: autopilot.config.yaml code_constraints > CLAUDE.md 禁止项 > 无约束放行
# Output: PostToolUse decision: "block" on violation.

set -uo pipefail

# --- Read stdin JSON ---
STDIN_DATA=""
if [ ! -t 0 ]; then
  STDIN_DATA=$(cat)
fi
[ -z "$STDIN_DATA" ] && exit 0

# --- Fast bypass Layer 0: lock file pre-check ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"
PROJECT_ROOT_QUICK=$(echo "$STDIN_DATA" | grep -o '"cwd"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
[ -z "$PROJECT_ROOT_QUICK" ] && PROJECT_ROOT_QUICK="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
has_active_autopilot "$PROJECT_ROOT_QUICK" || exit 0

# --- Fast bypass Layer 1: Phase 4/5/6 代码约束检查 ---
echo "$STDIN_DATA" | grep -qE '"prompt"[[:space:]]*:[[:space:]]*"<!-- autopilot-phase:[456]' || exit 0

# --- Dependency check ---
command -v python3 &>/dev/null || exit 0

# --- Constraint detection via python3 ---
echo "$STDIN_DATA" | python3 -c "
import json, os, re, sys

try:
    data = json.load(sys.stdin)
except (json.JSONDecodeError, ValueError):
    sys.exit(0)

prompt = data.get('tool_input', {}).get('prompt', '')
pm = re.search(r'autopilot-phase:(\d+)', prompt)
if not pm or int(pm.group(1)) not in (4, 5, 6):
    sys.exit(0)

# 提取 tool_response
tr = data.get('tool_response', '')
output = json.dumps(tr) if isinstance(tr, dict) else (tr if isinstance(tr, str) else str(tr or ''))
if not output.strip():
    sys.exit(0)

# 从 JSON envelope 提取 status/artifacts（raw_decode 策略）
envelope = None
decoder = json.JSONDecoder()
for i, ch in enumerate(output):
    if ch == '{':
        try:
            obj, _ = decoder.raw_decode(output, i)
            if isinstance(obj, dict) and 'status' in obj:
                envelope = obj
                break
        except (json.JSONDecodeError, ValueError):
            continue

if not envelope or envelope.get('status') not in ('ok', 'warning'):
    sys.exit(0)

artifacts = envelope.get('artifacts', [])
if not isinstance(artifacts, list) or not artifacts:
    sys.exit(0)

# --- 定位项目根 ---
cwd = data.get('tool_input', {}).get('cwd', '') or os.getcwd()
root = cwd
for _ in range(10):
    if os.path.isdir(os.path.join(root, '.claude')):
        break
    p = os.path.dirname(root)
    if p == root:
        break
    root = p

forbidden_files, forbidden_patterns, allowed_dirs = [], [], []
max_lines = 800
found = False

# 优先级 1: config.yaml code_constraints（轻量 YAML 解析）
cfg = os.path.join(root, '.claude', 'autopilot.config.yaml')
if os.path.isfile(cfg):
    try:
        with open(cfg) as f:
            txt = f.read()
        cc = re.search(r'^code_constraints:\s*$', txt, re.MULTILINE)
        if cc:
            sec = txt[cc.end():]
            nt = re.search(r'^\S', sec, re.MULTILINE)
            sec = sec[:nt.start()] if nt else sec
            def parse_list(key):
                m = re.search(rf'^( +){key}:\s*\n', sec, re.MULTILINE)
                if not m:
                    return []
                indent = m.group(1)
                start = m.end()
                end_m = re.search(rf'^{re.escape(indent)}[a-z_]', sec[start:], re.MULTILINE)
                block = sec[start:start + end_m.start()] if end_m else sec[start:]
                items = []
                # Format 1: nested objects - extract pattern field value
                for obj_m in re.finditer(r'-\s+pattern:\s*[\"\x27]?([^\"\x27}\n]+)[\"\x27]?', block):
                    v = obj_m.group(1).strip()
                    if v:
                        items.append(v)
                # Format 2: flat strings (fallback only if no nested objects found)
                if not items:
                    for x in re.finditer(r'-\s+(.+)', block):
                        v = x.group(1).strip().strip('\x22\x27')
                        if v and not v.startswith('pattern:') and not v.startswith('message:'):
                            items.append(v)
                return items
            forbidden_files = parse_list('forbidden_files')
            forbidden_patterns = parse_list('forbidden_patterns')
            allowed_dirs = parse_list('allowed_dirs')
            ml = re.search(r'max_file_lines:\s*(\d+)', sec)
            if ml:
                max_lines = int(ml.group(1))
            found = True
    except Exception as e:
        print(f'WARNING: code-constraint-check: {e}', file=sys.stderr)

# 优先级 2: CLAUDE.md 禁止项提取（fallback）
if not found:
    cmd = os.path.join(root, 'CLAUDE.md')
    if os.path.isfile(cmd):
        try:
            with open(cmd) as f:
                md = f.read()
            for m in re.finditer(r'[\x60|]([a-zA-Z0-9_.-]+\.[a-zA-Z]{1,5})[\x60|]\s*.*禁', md):
                forbidden_files.append(m.group(1))
            for m in re.finditer(r'禁[^|]*[\x60|]([a-zA-Z0-9_.-]+\.[a-zA-Z]{1,5})[\x60|]', md):
                forbidden_files.append(m.group(1))
            for m in re.finditer(r'[\x60|]([a-zA-Z][a-zA-Z0-9_() ]{2,30})[\x60|]\s*.*(?:禁止|禁)', md):
                p = m.group(1).strip()
                if len(p) > 2:
                    forbidden_patterns.append(p)
            found = bool(forbidden_files or forbidden_patterns)
        except Exception:
            pass

if not found and not forbidden_files and not forbidden_patterns:
    sys.exit(0)

# 去重
forbidden_files = list(dict.fromkeys(forbidden_files))
forbidden_patterns = list(dict.fromkeys(forbidden_patterns))

# --- 检查 artifacts ---
violations = []
for art in artifacts:
    if not isinstance(art, str):
        continue
    rel = os.path.relpath(art, root) if os.path.isabs(art) else art
    base = os.path.basename(rel)

    # 禁止文件名
    for ff in forbidden_files:
        if base == ff or rel.endswith(ff):
            violations.append(f'Forbidden file: {rel} (matches \"{ff}\")')
    # 目录范围
    if allowed_dirs and not any(rel.startswith(d) for d in allowed_dirs):
        violations.append(f'Out of scope: {rel} (allowed: {allowed_dirs})')
    # 文件行数 + 禁止模式（仅已存在文件）
    fp = os.path.join(root, rel) if not os.path.isabs(art) else art
    if os.path.isfile(fp):
        try:
            with open(fp, 'r', errors='ignore') as f:
                content = f.read(100_000)
            lc = content.count('\n') + (1 if content and not content.endswith('\n') else 0)
            if lc > max_lines:
                violations.append(f'File too long: {rel} ({lc} lines > {max_lines})')
            for pat in forbidden_patterns:
                if re.search(re.escape(pat), content):
                    violations.append(f'Forbidden pattern \"{pat}\" in {rel}')
        except Exception:
            pass

if violations:
    shown = violations[:5]
    extra = f' (+{len(violations)-5} more)' if len(violations) > 5 else ''
    print(json.dumps({
        'decision': 'block',
        'reason': f'Code constraint violations ({len(violations)}): ' + '; '.join(shown) + extra + '. Fix before proceeding.'
    }))

sys.exit(0)
"

exit 0

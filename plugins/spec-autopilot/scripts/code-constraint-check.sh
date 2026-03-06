#!/usr/bin/env bash
# code-constraint-check.sh
# Hook: PostToolUse(Task) — Phase 5 代码约束检查
# 检查 Task 子 Agent 返回的 artifacts 是否违反项目约束。
# Uses shared constraint loading from _common.sh (v3.1.0: deduplication).
# Output: PostToolUse decision: "block" on violation.

set -uo pipefail

# --- Read stdin JSON ---
STDIN_DATA=""
if [ ! -t 0 ]; then
  STDIN_DATA=$(cat)
fi
[ -z "$STDIN_DATA" ] && exit 0

# --- Source shared utilities ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

# --- Fast bypass ---
PROJECT_ROOT=$(extract_project_root "$STDIN_DATA")
should_bypass_hook "$STDIN_DATA" "$PROJECT_ROOT" "5" && exit 0

# --- Dependency check ---
command -v python3 &>/dev/null || exit 0

# --- Load constraints (cached) ---
CONSTRAINTS=$(load_constraints "$PROJECT_ROOT")
echo "$CONSTRAINTS" | python3 -c "import json,sys; c=json.load(sys.stdin); sys.exit(0 if c.get('found') else 1)" 2>/dev/null || exit 0

# --- Extract artifacts from Task response and check each ---
echo "$STDIN_DATA" | python3 -c "
import json, os, re, sys

try:
    data = json.load(sys.stdin)
except (json.JSONDecodeError, ValueError):
    sys.exit(0)

prompt = data.get('tool_input', {}).get('prompt', '')
pm = re.search(r'autopilot-phase:(\d+)', prompt)
if not pm or int(pm.group(1)) != 5:
    sys.exit(0)

tr = data.get('tool_response', '')
output = json.dumps(tr) if isinstance(tr, dict) else (tr if isinstance(tr, str) else str(tr or ''))
if not output.strip():
    sys.exit(0)

# Extract JSON envelope
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

# Load constraints from environment
root = sys.argv[1]
constraints = json.loads(sys.argv[2])

forbidden_files = constraints.get('forbidden_files', [])
forbidden_patterns = constraints.get('forbidden_patterns', [])
allowed_dirs = constraints.get('allowed_dirs', [])
max_lines = constraints.get('max_lines', 800)

violations = []
for art in artifacts:
    if not isinstance(art, str):
        continue
    rel = os.path.relpath(art, root) if os.path.isabs(art) else art
    base = os.path.basename(rel)

    for ff in forbidden_files:
        if base == ff or rel.endswith(ff):
            violations.append(f'Forbidden file: {rel} (matches \"{ff}\")')
    if allowed_dirs and not any(rel.startswith(d) for d in allowed_dirs):
        violations.append(f'Out of scope: {rel} (allowed: {allowed_dirs})')
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
" "$PROJECT_ROOT" "$CONSTRAINTS"

exit 0

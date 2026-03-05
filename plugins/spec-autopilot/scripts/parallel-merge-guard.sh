#!/usr/bin/env bash
# parallel-merge-guard.sh
# Hook: PostToolUse(Task) — Phase 5 并行合并验证
# 在 worktree merge 完成后验证：
#   1. 无合并冲突残留 (git diff --check)
#   2. 合并文件在预期 task scope 内 (对比 task artifacts)
#   3. 快速编译/类型检查通过 (读取 config test_suites 中 typecheck 命令)
# Output: PostToolUse decision: "block" on merge validation failure.

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

# --- Fast bypass Layer 1: 仅 Phase 5 ---
echo "$STDIN_DATA" | grep -q '"prompt"[[:space:]]*:[[:space:]]*"<!-- autopilot-phase:5' || exit 0

# --- Fast bypass Layer 2: 仅 worktree merge 相关输出 ---
echo "$STDIN_DATA" | grep -qi 'worktree.*merge\|merge.*worktree\|git merge.*autopilot-task' || exit 0

# --- Dependency check ---
command -v python3 &>/dev/null || exit 0

# --- Merge validation via python3 ---
echo "$STDIN_DATA" | python3 -c "
import json, os, re, subprocess, sys

try:
    data = json.load(sys.stdin)
except (json.JSONDecodeError, ValueError):
    sys.exit(0)

prompt = data.get('tool_input', {}).get('prompt', '')
pm = re.search(r'autopilot-phase:(\d+)', prompt)
if not pm or int(pm.group(1)) != 5:
    sys.exit(0)

# 提取 tool_response
tr = data.get('tool_response', '')
output = json.dumps(tr) if isinstance(tr, dict) else (tr if isinstance(tr, str) else str(tr or ''))
if not output.strip():
    sys.exit(0)

# 确认输出包含 worktree merge 相关内容
merge_pattern = re.compile(r'worktree.*merge|merge.*worktree|git\s+merge.*autopilot-task', re.IGNORECASE)
if not merge_pattern.search(output):
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

violations = []

# === 检查 1: 合并冲突残留 (git diff --check) ===
try:
    result = subprocess.run(
        ['git', 'diff', '--check'],
        cwd=root, capture_output=True, text=True, timeout=15
    )
    if result.returncode != 0 and result.stdout.strip():
        conflict_lines = result.stdout.strip().split('\n')[:5]
        detail = '; '.join(conflict_lines)
        violations.append('Merge conflicts detected: ' + detail)
except (subprocess.TimeoutExpired, FileNotFoundError, OSError):
    pass

# Also check for conflict markers in staged files
try:
    result = subprocess.run(
        ['git', 'diff', '--cached', '--check'],
        cwd=root, capture_output=True, text=True, timeout=15
    )
    if result.returncode != 0 and result.stdout.strip():
        conflict_lines = result.stdout.strip().split('\n')[:5]
        detail = '; '.join(conflict_lines)
        violations.append('Staged merge conflicts: ' + detail)
except (subprocess.TimeoutExpired, FileNotFoundError, OSError):
    pass

# === 检查 2: 合并文件在预期 task scope 内 ===
# 从 JSON envelope 提取 artifacts
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

expected_artifacts = []
if envelope and isinstance(envelope.get('artifacts'), list):
    expected_artifacts = [a for a in envelope['artifacts'] if isinstance(a, str)]

# 获取本次 merge 实际变更的文件
if expected_artifacts:
    try:
        result = subprocess.run(
            ['git', 'diff', '--name-only', 'HEAD~1', 'HEAD'],
            cwd=root, capture_output=True, text=True, timeout=15
        )
        if result.returncode == 0 and result.stdout.strip():
            changed_files = [f.strip() for f in result.stdout.strip().split('\n') if f.strip()]
            # 将 artifacts 转为相对路径集合用于匹配
            expected_rel = set()
            for art in expected_artifacts:
                rel = os.path.relpath(art, root) if os.path.isabs(art) else art
                expected_rel.add(rel)
                # 也添加目录前缀用于宽松匹配
                parts = rel.split('/')
                for j in range(1, len(parts)):
                    expected_rel.add('/'.join(parts[:j]))
            out_of_scope = []
            for cf in changed_files:
                # 检查文件是否在任何 artifact 路径或其父目录下
                in_scope = False
                for art_rel in expected_rel:
                    if cf == art_rel or cf.startswith(art_rel + '/') or art_rel.startswith(cf.split('/')[0]):
                        in_scope = True
                        break
                if not in_scope:
                    out_of_scope.append(cf)
            if out_of_scope:
                shown = out_of_scope[:5]
                extra = f' (+{len(out_of_scope)-5} more)' if len(out_of_scope) > 5 else ''
                detail = ', '.join(shown)
                violations.append('Files outside task scope: ' + detail + extra)
    except (subprocess.TimeoutExpired, FileNotFoundError, OSError):
        pass

# === 检查 3: 快速编译/类型检查 ===
# 从 config.yaml 读取 test_suites 中 type=typecheck 的命令
cfg_path = os.path.join(root, '.claude', 'autopilot.config.yaml')
typecheck_cmds = []
if os.path.isfile(cfg_path):
    try:
        with open(cfg_path) as f:
            cfg_txt = f.read()
        # 轻量 YAML 解析: 提取 test_suites 段
        ts_match = re.search(r'^test_suites:\s*$', cfg_txt, re.MULTILINE)
        if ts_match:
            section = cfg_txt[ts_match.end():]
            next_top = re.search(r'^\S', section, re.MULTILINE)
            section = section[:next_top.start()] if next_top else section
            # 找所有 type: typecheck 的套件及其 command
            suites = re.split(r'\n  (\w[\w_-]*):\s*\n', section)
            # suites[0] is before first suite name, then alternating name/body
            for idx in range(1, len(suites) - 1, 2):
                body = suites[idx + 1]
                type_m = re.search(r'type:\s*(\S+)', body)
                cmd_m = re.search(r'command:\s*[\x22\x27]?(.+?)[\x22\x27]?\s*$', body, re.MULTILINE)
                if type_m and type_m.group(1) == 'typecheck' and cmd_m:
                    typecheck_cmds.append(cmd_m.group(1).strip().strip('\x22\x27'))
    except Exception as e:
        print(f'WARNING: parallel-merge-guard config parse: {e}', file=sys.stderr)

for cmd in typecheck_cmds:
    try:
        result = subprocess.run(
            cmd, shell=True, cwd=root,
            capture_output=True, text=True, timeout=120
        )
        if result.returncode != 0:
            stderr_tail = (result.stderr or result.stdout or '').strip()[-300:]
            violations.append(f'Typecheck failed [{cmd}]: {stderr_tail}')
    except subprocess.TimeoutExpired:
        violations.append(f'Typecheck timed out [{cmd}] (>120s)')
    except (FileNotFoundError, OSError) as e:
        violations.append(f'Typecheck error [{cmd}]: {e}')

# === 输出结果 ===
if violations:
    shown = violations[:5]
    extra = f' (+{len(violations)-5} more)' if len(violations) > 5 else ''
    print(json.dumps({
        'decision': 'block',
        'reason': f'Parallel merge guard: {len(violations)} issue(s) after worktree merge: ' + '; '.join(shown) + extra + '. Fix conflicts or scope issues before proceeding.'
    }))

sys.exit(0)
" 2>/dev/null

exit 0

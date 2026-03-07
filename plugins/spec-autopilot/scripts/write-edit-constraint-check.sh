#!/usr/bin/env bash
# write-edit-constraint-check.sh
# Hook: PostToolUse(Write|Edit) — Phase 5 直接文件写入约束检查
# 与 code-constraint-check.sh 互补：后者检查 Task 子 Agent 返回的 artifacts，
# 本脚本直接拦截 Write/Edit 工具调用，在文件落盘后立即校验。
# 约束来源: autopilot.config.yaml code_constraints > CLAUDE.md 禁止项 > 无约束放行
# Output: PostToolUse decision: "block" on violation.

set -uo pipefail

# --- Read stdin JSON ---
STDIN_DATA=""
if [ ! -t 0 ]; then
  STDIN_DATA=$(cat)
fi
[ -z "$STDIN_DATA" ] && exit 0

# --- Fast bypass Layer 0: lock file pre-check (pure bash, ~1ms) ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"
PROJECT_ROOT_QUICK=$(echo "$STDIN_DATA" | grep -o '"cwd"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
[ -z "$PROJECT_ROOT_QUICK" ] && PROJECT_ROOT_QUICK="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
has_active_autopilot "$PROJECT_ROOT_QUICK" || exit 0

# --- Fast bypass Layer 1: Phase 5 检测 ---
# 读取锁文件获取活跃 change，然后检查最新 checkpoint 判断当前阶段
CHANGES_DIR="$PROJECT_ROOT_QUICK/openspec/changes"
LOCK_FILE="$CHANGES_DIR/.autopilot-active"
[ -f "$LOCK_FILE" ] || exit 0

# 快速判断：如果 phase-5 checkpoint 不存在但 phase-4 存在，说明正在 Phase 5
# 如果 phase-5 checkpoint 已存在且状态为 ok，说明 Phase 5 已完成
CHANGE_NAME=$(parse_lock_file "$LOCK_FILE")
[ -z "$CHANGE_NAME" ] && exit 0
PHASE_RESULTS="$CHANGES_DIR/$CHANGE_NAME/context/phase-results"
[ -d "$PHASE_RESULTS" ] || exit 0

# 快速判断当前是否在 Phase 5 执行中
# full 模式: phase-4 存在 + phase-5 不存在或非 ok → 正在 Phase 5
# lite/minimal: phase-1 存在且 ok + phase-4 不存在 + phase-5 不存在或非 ok → 正在 Phase 5
PHASE4_CP=$(find_checkpoint "$PHASE_RESULTS" 4)
PHASE1_CP=$(find_checkpoint "$PHASE_RESULTS" 1)

# Determine if we're in Phase 5
IN_PHASE5="no"
if [ -n "$PHASE4_CP" ]; then
  # full mode: Phase 4 exists, check Phase 5
  PHASE5_CP=$(find_checkpoint "$PHASE_RESULTS" 5)
  if [ -z "$PHASE5_CP" ]; then
    IN_PHASE5="yes"
  else
    STATUS=$(read_checkpoint_status "$PHASE5_CP")
    [ "$STATUS" != "ok" ] && IN_PHASE5="yes"
  fi
elif [ -n "$PHASE1_CP" ]; then
  # lite/minimal mode: Phase 1 exists but no Phase 4
  PHASE1_STATUS=$(read_checkpoint_status "$PHASE1_CP")
  if [ "$PHASE1_STATUS" = "ok" ] || [ "$PHASE1_STATUS" = "warning" ]; then
    PHASE5_CP=$(find_checkpoint "$PHASE_RESULTS" 5)
    if [ -z "$PHASE5_CP" ]; then
      IN_PHASE5="yes"
    else
      STATUS=$(read_checkpoint_status "$PHASE5_CP")
      [ "$STATUS" != "ok" ] && IN_PHASE5="yes"
    fi
  fi
fi

[ "$IN_PHASE5" != "yes" ] && exit 0

# --- Fast bypass Layer 2: 提取 file_path ---
FILE_PATH=$(echo "$STDIN_DATA" | grep -o '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
[ -z "$FILE_PATH" ] && exit 0
# --- Dependency check ---
command -v python3 &>/dev/null || exit 0

# --- Constraint check via python3 ---
python3 -c "
import json, os, re, sys

file_path = '''$FILE_PATH'''
root = '''$PROJECT_ROOT_QUICK'''

# 相对路径
if os.path.isabs(file_path):
    rel = os.path.relpath(file_path, root)
else:
    rel = file_path
    file_path = os.path.join(root, file_path)
base = os.path.basename(rel)

# --- 加载约束 ---
forbidden_files, forbidden_patterns, allowed_dirs = [], [], []
max_lines = 800
found = False

# 优先级 1: config.yaml code_constraints
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
    except Exception:
        pass

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

# --- 检查违规 ---
violations = []

# 禁止文件名
for ff in forbidden_files:
    if base == ff or rel.endswith(ff):
        violations.append(f'Forbidden file: {rel} (matches \"{ff}\")')

# 目录范围
if allowed_dirs and not any(rel.startswith(d) for d in allowed_dirs):
    violations.append(f'Out of scope: {rel} (allowed: {allowed_dirs})')

# 文件行数 + 禁止模式（文件必须存在）
if os.path.isfile(file_path):
    try:
        with open(file_path, 'r', errors='ignore') as f:
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
        'reason': f'Write/Edit constraint violations ({len(violations)}): ' + '; '.join(shown) + extra + '. Fix before proceeding.'
    }))

sys.exit(0)
"

exit 0

#!/usr/bin/env bash
# write-edit-constraint-check.sh
# Hook: PostToolUse(Write|Edit) — Phase 5 直接文件写入约束检查
# 与 code-constraint-check.sh 互补：后者检查 Task 子 Agent 返回的 artifacts，
# 本脚本直接拦截 Write/Edit 工具调用，在文件落盘后立即校验。
# 约束来源: autopilot.config.yaml code_constraints > CLAUDE.md 禁止项 > 无约束放行
# Output: PostToolUse decision: "block" on violation.

# --- Common preamble: stdin read, SCRIPT_DIR, _common.sh, Layer 0 bypass ---
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_hook_preamble.sh"

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
# full TDD 模式: phase-3 存在 + tdd_mode=true + phase-5 不存在或非 ok → 正在 Phase 5
# lite/minimal: phase-1 存在且 ok + phase-4 不存在 + phase-5 不存在或非 ok → 正在 Phase 5
PHASE4_CP=$(find_checkpoint "$PHASE_RESULTS" 4)
PHASE3_CP=$(find_checkpoint "$PHASE_RESULTS" 3)
PHASE1_CP=$(find_checkpoint "$PHASE_RESULTS" 1)

# Determine if we're in Phase 5
IN_PHASE5="no"
if [ -n "$PHASE4_CP" ]; then
  # full mode (normal or TDD override): Phase 4 checkpoint exists, check Phase 5
  PHASE5_CP=$(find_checkpoint "$PHASE_RESULTS" 5)
  if [ -z "$PHASE5_CP" ]; then
    IN_PHASE5="yes"
  else
    STATUS=$(read_checkpoint_status "$PHASE5_CP")
    [ "$STATUS" != "ok" ] && IN_PHASE5="yes"
  fi
elif [ -n "$PHASE3_CP" ] && [ -n "$PHASE1_CP" ]; then
  # full TDD mode: Phase 3 exists but no Phase 4 (tdd_mode_override not yet written)
  # Check if tdd_mode is enabled to distinguish from lite/minimal
  TDD_MODE_VAL=$(read_config_value "$PROJECT_ROOT_QUICK" "phases.implementation.tdd_mode" "false")
  if [ "$TDD_MODE_VAL" = "true" ]; then
    PHASE5_CP=$(find_checkpoint "$PHASE_RESULTS" 5)
    if [ -z "$PHASE5_CP" ]; then
      IN_PHASE5="yes"
    else
      STATUS=$(read_checkpoint_status "$PHASE5_CP")
      [ "$STATUS" != "ok" ] && IN_PHASE5="yes"
    fi
  fi
elif [ -n "$PHASE1_CP" ]; then
  # lite/minimal mode: Phase 1 exists but no Phase 3/4
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
import importlib.util, json, os, re, sys

# Import shared constraint loader
_script_dir = os.environ.get('SCRIPT_DIR', '.')
_spec = importlib.util.spec_from_file_location('_cl', os.path.join(_script_dir, '_constraint_loader.py'))
_cl = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_cl)

file_path = '''$FILE_PATH'''
root = '''$PROJECT_ROOT_QUICK'''

# Load constraints using shared module
constraints = _cl.load_constraints(root)
if not constraints['found'] and not constraints['forbidden_files'] and not constraints['forbidden_patterns']:
    sys.exit(0)

# Check violations using shared module
violations = _cl.check_file_violations(file_path, root, constraints)

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

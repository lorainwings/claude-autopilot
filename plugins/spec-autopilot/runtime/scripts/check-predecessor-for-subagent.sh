#!/usr/bin/env bash
# check-predecessor-for-subagent.sh — 子 Agent 前置 checkpoint 校验（确定性脚本）
#
# 用途：替代子 Agent 自行编写的内联 Python 读取代码，避免 FileNotFoundError。
#       使用 mode-aware phase graph 自动计算前驱阶段，避免写死 N-1。
# 输出：JSON 到 stdout — {"exists": true/false, "status": "...", "predecessor": N}
# 退出码：始终为 0（校验结果通过 JSON 传递，非退出码）
#
# 用法：bash check-predecessor-for-subagent.sh <phase_results_dir> <target_phase> [mode]
#   phase_results_dir: openspec/changes/<name>/context/phase-results
#   target_phase: 当前要执行的 Phase 编号（脚本自动计算其前驱）
#   mode: 执行模式 full/lite/minimal（默认 full）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh
source "$SCRIPT_DIR/_common.sh"

PHASE_RESULTS_DIR="${1:-}"
TARGET_PHASE="${2:-}"
MODE="${3:-full}"

if [ -z "$PHASE_RESULTS_DIR" ] || [ -z "$TARGET_PHASE" ]; then
  echo '{"exists":false,"status":"unknown","predecessor":0,"error":"missing arguments"}'
  exit 0
fi

# 将相对路径转为绝对路径，确保后续模式匹配不受 cwd 影响
if [[ "$PHASE_RESULTS_DIR" != /* ]]; then
  PHASE_RESULTS_DIR="$(cd "$PHASE_RESULTS_DIR" 2>/dev/null && pwd)" || {
    # 目录不存在时用 pwd 拼接（目录可能尚未创建）
    PHASE_RESULTS_DIR="$(pwd)/${1}"
  }
fi

# --- 通过 phase graph 计算 mode-aware 前驱 ---
PRED_PHASE=0

# TDD mode 运行时覆盖：full mode Phase 5 前驱从 4 → 3
# 注意：这需要项目根目录，从 phase_results_dir 向上推导
if [ "$MODE" = "full" ] && [ "$TARGET_PHASE" -eq 5 ] 2>/dev/null; then
  PROJECT_ROOT=""
  # phase_results_dir 格式: .../openspec/changes/<name>/context/phase-results
  # 项目根: 去掉 /openspec/changes/<name>/context/phase-results
  if [[ "$PHASE_RESULTS_DIR" == */openspec/changes/*/context/phase-results ]]; then
    PROJECT_ROOT="${PHASE_RESULTS_DIR%/openspec/changes/*/context/phase-results}"
  fi
  if [ -n "$PROJECT_ROOT" ]; then
    TDD_MODE=$(read_config_value "$PROJECT_ROOT" "phases.implementation.tdd_mode" "false" 2>/dev/null || echo "false")
    if [ "$TDD_MODE" = "true" ]; then
      PRED_PHASE=3
    fi
  fi
fi

# 若 TDD 未覆盖，使用 _phase_graph.py 查询
if [ "$PRED_PHASE" -eq 0 ] 2>/dev/null; then
  PRED_PHASE=$(python3 "$SCRIPT_DIR/_phase_graph.py" get_predecessor "$TARGET_PHASE" "$MODE" 2>/dev/null || echo "0")
fi

# Phase 1 或不在序列中的 phase 没有前驱
if [ "$PRED_PHASE" -eq 0 ] 2>/dev/null; then
  echo "{\"exists\":true,\"status\":\"ok\",\"predecessor\":0}"
  exit 0
fi

if [ ! -d "$PHASE_RESULTS_DIR" ]; then
  echo "{\"exists\":false,\"status\":\"unknown\",\"predecessor\":${PRED_PHASE},\"error\":\"directory not found\"}"
  exit 0
fi

checkpoint_file=$(find_checkpoint "$PHASE_RESULTS_DIR" "$PRED_PHASE")

if [ -z "$checkpoint_file" ] || [ ! -f "$checkpoint_file" ]; then
  echo "{\"exists\":false,\"status\":\"unknown\",\"predecessor\":${PRED_PHASE}}"
  exit 0
fi

status=$(read_checkpoint_status "$checkpoint_file")
echo "{\"exists\":true,\"status\":\"${status}\",\"predecessor\":${PRED_PHASE}}"
exit 0

#!/usr/bin/env bash
# check-tdd-mode.sh — 确定性 TDD 模式检测（Phase 4 入口判定）
# 用途：在 Phase 4 启动时确定性读取 TDD 配置，避免 AI 编排器依赖记忆判断
#
# Usage: check-tdd-mode.sh [project_root]
#   project_root: 项目根目录（默认 resolve_project_root 自动解析）
#
# Output (stdout):
#   TDD_SKIP     — tdd_mode=true 且 mode=full，Phase 4 应跳过
#   TDD_DISPATCH — 非 TDD 模式，Phase 4 应正常 dispatch
#
# Exit: 始终 0（不影响调用方流程）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=_common.sh
source "$SCRIPT_DIR/_common.sh"

# 项目根目录解析：显式参数 > resolve_project_root (AUTOPILOT_PROJECT_ROOT > git > pwd)
PROJECT_ROOT="${1:-$(resolve_project_root)}"

# ── Step 1: 检测执行模式 ──
# 从 .autopilot-active 锁文件读取 mode，fallback 到 config
LOCK_FILE=""
if [ -f "$PROJECT_ROOT/openspec/changes/.autopilot-active" ]; then
  LOCK_FILE="$PROJECT_ROOT/openspec/changes/.autopilot-active"
fi

EXEC_MODE=""
if [ -n "$LOCK_FILE" ]; then
  EXEC_MODE=$(read_lock_json_field "$LOCK_FILE" "mode" "")
fi
if [ -z "$EXEC_MODE" ]; then
  EXEC_MODE=$(read_config_value "$PROJECT_ROOT" "default_mode" "full")
fi

# TDD 仅在 full 模式下生效
if [ "$EXEC_MODE" != "full" ]; then
  echo "TDD_DISPATCH"
  exit 0
fi

# ── Step 2: 读取 TDD 配置（统一数据源：_common.sh get_tdd_mode）──
TDD_MODE=$(get_tdd_mode "$PROJECT_ROOT")

# ── Step 3: 输出确定性判定 ──
if [ "$TDD_MODE" = "true" ]; then
  echo "TDD_SKIP"
else
  echo "TDD_DISPATCH"
fi

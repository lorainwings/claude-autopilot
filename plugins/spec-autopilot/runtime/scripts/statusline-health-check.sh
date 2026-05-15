#!/usr/bin/env bash
# statusline-health-check.sh — Statusline 安装状态健康检查
# 用法: statusline-health-check.sh [--project-root <path>] [--json]
# 输出 JSON: {"healthy":bool,"issues":["..."]}
# --json 标志: 输出带缩进的详细 JSON（含 checks、metadata）
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

PROJECT_ROOT=""
JSON_OUTPUT="false"

while [ $# -gt 0 ]; do
  case "${1:-}" in
    --project-root)
      PROJECT_ROOT="${2:-}"
      shift 2
      ;;
    --json)
      JSON_OUTPUT="true"
      shift
      ;;
    *)
      shift
      ;;
  esac
done

[ -z "$PROJECT_ROOT" ] && PROJECT_ROOT="$(resolve_project_root)"

ISSUES=()
# 详细检查结果数组（供 --json 模式使用）
CHECKS=()

# --- 检查 1: settings.local.json 是否存在且包含 statusLine 配置 ---
CLAUDE_DIR="$PROJECT_ROOT/.claude"
LOCAL_SETTINGS="$CLAUDE_DIR/settings.local.json"

if [ ! -f "$LOCAL_SETTINGS" ]; then
  ISSUES+=("settings_missing")
  CHECKS+=('{"name":"settings_local_json","status":"fail","detail":"settings.local.json not found"}')
else
  # 检查是否包含 statusLine 配置
  if ! jq -e '.statusLine | select(type == "object" and .command != null and .command != "")' "$LOCAL_SETTINGS" >/dev/null 2>&1; then
    ISSUES+=("statusline_config_missing")
    CHECKS+=('{"name":"statusline_config","status":"fail","detail":"statusLine configuration missing or invalid"}')
  else
    CHECKS+=('{"name":"settings_local_json","status":"pass","detail":"settings.local.json exists with valid statusLine config"}')
  fi
fi

# --- 检查 2: statusLine.command 中引用的脚本路径是否存在且可执行 ---
if [ -f "$LOCAL_SETTINGS" ]; then
  CMD_PATH=$(
    CMD_RAW=$(jq -r '.statusLine.command // ""' "$LOCAL_SETTINGS" 2>/dev/null || true)
    # 解析 ${CLAUDE_PLUGIN_ROOT:-fallback} 中的 fallback 路径
    RESOLVED=$(echo "$CMD_RAW" | sed -E 's/\$\{CLAUDE_PLUGIN_ROOT:-([^}]+)\}/\1/g')
    RESOLVED=$(echo "$RESOLVED" | sed "s|\\\$CLAUDE_PLUGIN_ROOT|${CLAUDE_PLUGIN_ROOT:-}|g")
    # 提取 .sh 路径
    PATHS=$(echo "$RESOLVED" | grep -oE '(/[^ ]+\.sh)' || true)
    for p in $PATHS; do
      if [ ! -f "$p" ]; then
        echo "$p"
        break
      fi
    done
  )
  if [ -n "$CMD_PATH" ]; then
    ISSUES+=("command_path_invalid:$CMD_PATH")
    CHECKS+=("{\"name\":\"command_path\",\"status\":\"fail\",\"detail\":\"script path not found: $CMD_PATH\"}")
  else
    CHECKS+=('{"name":"command_path","status":"pass","detail":"all referenced script paths exist"}')
  fi
fi

# --- 检查 2.5: statusLine.command 中是否包含 spec-autopilot collector（或其链式调用）---
# 仅检查 command 字符串是否引用了 spec-autopilot 自己的 statusline-collector.sh
# 允许任意链式形式：CLAUDE_PLUGIN_ROOT env var / 绝对路径 / 市场安装路径
# 判据：command 中存在路径片段 spec-autopilot[}]?/runtime/scripts/statusline-collector.sh
#       （兼容 ${CLAUDE_PLUGIN_ROOT:-/.../spec-autopilot}/runtime/... 形态）
if [ -f "$LOCAL_SETTINGS" ]; then
  AUTOPILOT_IN_CHAIN=$(
    CMD_RAW=$(jq -r '.statusLine.command // ""' "$LOCAL_SETTINGS" 2>/dev/null || true)
    if echo "$CMD_RAW" | grep -qE 'spec-autopilot[}]?/runtime/scripts/statusline-collector\.sh'; then
      echo "yes"
    else
      echo "no"
    fi
  )
  if [ "$AUTOPILOT_IN_CHAIN" != "yes" ]; then
    ISSUES+=("autopilot_collector_not_in_chain")
    CHECKS+=('{"name":"autopilot_collector_in_chain","status":"fail","detail":"spec-autopilot collector not found in statusLine command chain"}')
  else
    CHECKS+=('{"name":"autopilot_collector_in_chain","status":"pass","detail":"spec-autopilot collector present in command chain"}')
  fi
fi

# --- 检查 3: CLAUDE_PLUGIN_ROOT 是否已解析为有效路径 ---
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-}"
FALLBACK_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
if [ -n "$PLUGIN_ROOT" ]; then
  if [ ! -d "$PLUGIN_ROOT" ]; then
    ISSUES+=("plugin_root_invalid:$PLUGIN_ROOT")
    CHECKS+=("{\"name\":\"plugin_root\",\"status\":\"fail\",\"detail\":\"CLAUDE_PLUGIN_ROOT directory not found: $PLUGIN_ROOT\"}")
  else
    CHECKS+=("{\"name\":\"plugin_root\",\"status\":\"pass\",\"detail\":\"CLAUDE_PLUGIN_ROOT is valid: $PLUGIN_ROOT\"}")
  fi
elif [ ! -d "$FALLBACK_ROOT" ]; then
  ISSUES+=("fallback_root_invalid:$FALLBACK_ROOT")
  CHECKS+=("{\"name\":\"plugin_root\",\"status\":\"fail\",\"detail\":\"fallback root directory not found: $FALLBACK_ROOT\"}")
else
  CHECKS+=("{\"name\":\"plugin_root\",\"status\":\"pass\",\"detail\":\"using fallback root: $FALLBACK_ROOT\"}")
fi

# --- 检查 4: statusline-collector.sh 是否存在且可执行 ---
COLLECTOR="$SCRIPT_DIR/statusline-collector.sh"
if [ ! -f "$COLLECTOR" ]; then
  ISSUES+=("collector_missing")
  CHECKS+=('{"name":"collector_script","status":"fail","detail":"statusline-collector.sh not found"}')
elif [ ! -x "$COLLECTOR" ]; then
  ISSUES+=("collector_not_executable")
  CHECKS+=('{"name":"collector_script","status":"fail","detail":"statusline-collector.sh not executable"}')
else
  CHECKS+=('{"name":"collector_script","status":"pass","detail":"statusline-collector.sh exists and is executable"}')
fi

# --- 检查 5: session 目录 logs/sessions/ 是否可写 ---
LOGS_DIR="$PROJECT_ROOT/logs/sessions"
if [ -d "$LOGS_DIR" ]; then
  if [ ! -w "$LOGS_DIR" ]; then
    ISSUES+=("sessions_dir_not_writable")
    CHECKS+=('{"name":"sessions_directory","status":"fail","detail":"logs/sessions/ exists but is not writable"}')
  else
    CHECKS+=('{"name":"sessions_directory","status":"pass","detail":"logs/sessions/ is writable"}')
  fi
else
  # 目录不存在时检查父目录是否可创建
  PARENT_DIR="$PROJECT_ROOT/logs"
  if [ -d "$PARENT_DIR" ] && [ ! -w "$PARENT_DIR" ]; then
    ISSUES+=("logs_dir_not_writable")
    CHECKS+=('{"name":"sessions_directory","status":"fail","detail":"logs/ directory not writable, cannot create sessions/"}')
  else
    CHECKS+=('{"name":"sessions_directory","status":"pass","detail":"logs/sessions/ can be created"}')
  fi
fi

# --- 输出 JSON 结果 ---
HEALTHY="true"
if [ ${#ISSUES[@]} -gt 0 ]; then
  HEALTHY="false"
fi

# 构造 issues JSON 数组
ISSUES_JSON="[]"
if [ ${#ISSUES[@]} -gt 0 ]; then
  ISSUES_JSON=$(printf '%s\n' "${ISSUES[@]}" | jq -R . | jq -s .)
fi

if [ "$JSON_OUTPUT" = "true" ]; then
  # --json 模式: 输出带缩进的详细 JSON
  CHECKS_JSON="[]"
  if [ ${#CHECKS[@]} -gt 0 ]; then
    CHECKS_JSON=$(printf '%s\n' "${CHECKS[@]}" | jq -s .)
  fi

  jq -n \
    --argjson healthy "$HEALTHY" \
    --argjson issues "$ISSUES_JSON" \
    --argjson checks "$CHECKS_JSON" \
    --arg check_time "$(date -u +%Y-%m-%dT%H:%M:%S%z)" \
    --arg project_root "$PROJECT_ROOT" \
    '{
      healthy: ($healthy == true or $healthy == "true"),
      issues: $issues,
      checks: $checks,
      metadata: {
        check_time: $check_time,
        project_root: $project_root
      }
    }'
else
  # 默认模式: 紧凑单行 JSON（保持向后兼容）
  printf '{"healthy":%s,"issues":%s}\n' "$HEALTHY" "$ISSUES_JSON"
fi

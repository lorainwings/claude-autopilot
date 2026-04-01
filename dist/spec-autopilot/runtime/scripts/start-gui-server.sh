#!/usr/bin/env bash
# start-gui-server.sh
# v5.5 GUI 服务器守护进程启动器 (结构化 JSON 输出增强)
# Purpose: 检测 autopilot-server 是否存活，未存活则后台启动
# Usage:
#   bash runtime/scripts/start-gui-server.sh [project_root]       # 默认：检测+启动
#   bash runtime/scripts/start-gui-server.sh --stop               # 通过 PID 文件终止服务器
#   bash runtime/scripts/start-gui-server.sh --check-health       # 检测进程是否存活，死掉则重启
# Output:
#   stdout: 结构化 JSON（前缀 GUI_SERVER_JSON:），包含 status/http_url/ws_url/health_url 等字段
#   stderr: 诊断信息（人类可读）

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- 端口配置 ---
HTTP_PORT=9527
WS_PORT=9528

# --- 结构化 JSON 输出 ---
# 所有诊断信息输出到 stderr，JSON 输出到 stdout
# 调用方通过 GUI_SERVER_JSON: 前缀解析结构化数据
emit_json() {
  local status="$1"
  local reused="${2:-false}"
  local started="${3:-false}"
  local error="${4:-}"

  local http_url="http://localhost:${HTTP_PORT}"
  local ws_url="ws://localhost:${WS_PORT}"
  local health_url="http://localhost:${HTTP_PORT}/api/health"

  # 使用 printf 手动构建 JSON，避免对 jq 的硬依赖
  local json
  if [ -n "$error" ]; then
    # 转义 error 中的双引号和反斜杠
    local escaped_error
    escaped_error=$(printf '%s' "$error" | sed 's/\\/\\\\/g; s/"/\\"/g')
    json=$(printf '{"status":"%s","http_url":"%s","ws_url":"%s","health_url":"%s","reused_existing":%s,"started_new":%s,"error":"%s"}' \
      "$status" "$http_url" "$ws_url" "$health_url" "$reused" "$started" "$escaped_error")
  else
    json=$(printf '{"status":"%s","http_url":"%s","ws_url":"%s","health_url":"%s","reused_existing":%s,"started_new":%s}' \
      "$status" "$http_url" "$ws_url" "$health_url" "$reused" "$started")
  fi

  echo "GUI_SERVER_JSON:${json}"
}

# --- Parse mode flag ---
MODE="start"
POSITIONAL_ARGS=()
for arg in "$@"; do
  case "$arg" in
    --stop) MODE="stop" ;;
    --check-health) MODE="check-health" ;;
    *) POSITIONAL_ARGS+=("$arg") ;;
  esac
done

PROJECT_ROOT="${POSITIONAL_ARGS[0]:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

# --- Paths ---
LOGS_DIR="$PROJECT_ROOT/logs"
PID_FILE="$LOGS_DIR/.gui-server.pid"
SERVER_LOG="$LOGS_DIR/gui-server.log"
SERVER_ERR_LOG="$LOGS_DIR/gui-server.err.log"

# --- Check if server is alive via HTTP and belongs to this project ---
check_server_alive() {
  local resp
  # 优先使用 /api/health 端点（v5.9），fallback 到 /api/info
  resp=$(curl -s --max-time 1 http://localhost:${HTTP_PORT}/api/health 2>/dev/null) ||
    resp=$(curl -s --max-time 1 http://localhost:${HTTP_PORT}/api/info 2>/dev/null) || return 1
  # Validate response belongs to THIS project (prevent cross-project false positives)
  if [ -n "$resp" ]; then
    local resp_root
    # /api/health 不含 projectRoot，使用 /api/info 验证归属
    local info_resp
    info_resp=$(curl -s --max-time 1 http://localhost:${HTTP_PORT}/api/info 2>/dev/null) || return 1
    resp_root=$(echo "$info_resp" | python3 -c "import json,sys; print(json.load(sys.stdin).get('projectRoot',''))" 2>/dev/null) || true
    if [ -z "$resp_root" ]; then
      # Server too old to return projectRoot — reject (cannot verify ownership)
      return 1
    fi
    # The API returns sanitized paths (~/... instead of /Users/foo/...).
    # Sanitize our PROJECT_ROOT the same way for apples-to-apples comparison.
    local sanitized_ours
    sanitized_ours=$(python3 -c "
import sys, os, pathlib
p = sys.argv[1]
home = str(pathlib.Path.home())
if p.startswith(home):
    p = '~' + p[len(home):]
print(p)
" "$PROJECT_ROOT" 2>/dev/null) || sanitized_ours="$PROJECT_ROOT"
    if [ "$resp_root" = "$sanitized_ours" ]; then
      return 0
    fi
    # Server belongs to different project
    return 1
  fi
  return 1
}

# --- Check if PID file process is alive ---
check_pid_alive() {
  if [ ! -f "$PID_FILE" ]; then
    return 1
  fi
  local pid
  pid=$(cat "$PID_FILE" 2>/dev/null)
  if [ -z "$pid" ]; then
    return 1
  fi
  kill -0 "$pid" 2>/dev/null
  return $?
}

# --- Write PID file ---
write_pid() {
  local pid="$1"
  mkdir -p "$LOGS_DIR"
  echo "$pid" >"$PID_FILE"
}

# --- Remove PID file ---
remove_pid() {
  rm -f "$PID_FILE"
}

# --- Stop server via PID file ---
stop_server() {
  if [ ! -f "$PID_FILE" ]; then
    echo "[INFO] No PID file found at $PID_FILE" >&2
    return 1
  fi
  local pid
  pid=$(cat "$PID_FILE" 2>/dev/null)
  if [ -z "$pid" ]; then
    remove_pid
    return 1
  fi
  if kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null
    # Wait up to 3s for graceful shutdown
    local count=0
    while [ $count -lt 30 ] && kill -0 "$pid" 2>/dev/null; do
      sleep 0.1
      count=$((count + 1))
    done
    # Force kill if still alive
    if kill -0 "$pid" 2>/dev/null; then
      kill -9 "$pid" 2>/dev/null || true
    fi
    remove_pid
    echo "[INFO] GUI server (PID $pid) stopped" >&2
    return 0
  else
    remove_pid
    echo "[INFO] GUI server (PID $pid) was not running, cleaned PID file" >&2
    return 1
  fi
}

# --- Start server in background ---
start_server() {
  local server_script=""

  # runtime/server/ 为标准路径（源码态 & dist 态统一）
  if [ -f "$SCRIPT_DIR/../server/autopilot-server.ts" ]; then
    server_script="$SCRIPT_DIR/../server/autopilot-server.ts"
  else
    echo "[WARN] GUI server script not found at runtime/server/autopilot-server.ts" >&2
    return 1
  fi

  # Check if bun is available
  if ! command -v bun &>/dev/null; then
    echo "[WARN] bun not found. GUI dashboard unavailable. Install: https://bun.sh" >&2
    return 1
  fi

  mkdir -p "$LOGS_DIR"

  # Start server as daemon (detached, logs to files)
  nohup bun run "$server_script" --project-root "$PROJECT_ROOT" --no-open \
    >>"$SERVER_LOG" 2>>"$SERVER_ERR_LOG" &

  local server_pid=$!
  write_pid "$server_pid"

  # Wait up to 3 seconds for server to be ready (health check)
  local max_wait=30 # 30 * 0.1s = 3s
  local count=0
  while [ $count -lt $max_wait ]; do
    if check_server_alive; then
      return 0
    fi
    sleep 0.1
    count=$((count + 1))
  done

  # Timeout
  echo "[WARN] GUI server failed to start within 3s" >&2
  return 1
}

# --- Mode dispatch ---

case "$MODE" in
  stop)
    stop_server
    exit $?
    ;;

  check-health)
    # 检测进程是否存活，若死掉则重启
    if check_server_alive; then
      emit_json "reused" "true" "false"
      exit 0
    fi
    # HTTP 不通 — 检查 PID 是否存活
    if check_pid_alive; then
      # 进程在但 HTTP 无响应 → 杀掉僵尸进程并重启
      echo "[WARN] GUI server process alive but HTTP not responding, killing and restarting..." >&2
      stop_server
    else
      # 进程已死，清理 PID 文件
      remove_pid
      echo "[INFO] GUI server dead, restarting..." >&2
    fi
    # 重启
    if start_server; then
      echo "✨ GUI 服务器已自动重启，大盘见 http://localhost:${HTTP_PORT}" >&2
      emit_json "started" "false" "true"
    else
      emit_json "failed" "false" "false" "健康检查重启失败"
      exit 1
    fi
    ;;

  start)
    # 先检查 PID 文件中的进程是否存活
    if check_pid_alive && check_server_alive; then
      # 已运行，复用现有服务器
      emit_json "reused" "true" "false"
      exit 0
    fi

    # HTTP 探活（兼容无 PID 文件但已有服务的情况）
    if check_server_alive; then
      emit_json "reused" "true" "false"
      exit 0
    fi

    # 清理可能的残留 PID 文件
    remove_pid

    # Not running, start it
    if start_server; then
      echo "✨ 引擎已启动，GUI 大盘见 http://localhost:${HTTP_PORT}" >&2
      emit_json "started" "false" "true"
    else
      # 启动失败，输出失败 JSON 但不阻断 autopilot 执行
      emit_json "failed" "false" "false" "GUI 服务器启动失败"
      exit 0
    fi
    ;;
esac

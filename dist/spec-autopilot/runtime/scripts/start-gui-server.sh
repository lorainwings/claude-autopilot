#!/usr/bin/env bash
# start-gui-server.sh
# v5.0 GUI 服务器守护进程启动器
# Purpose: 检测 autopilot-server 是否存活，未存活则后台启动
# Usage: bash runtime/scripts/start-gui-server.sh [project_root]
# Output: 一行优雅提示或静默（已存活时）

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

# --- Check if server is already running ---
check_server_alive() {
  curl -s --max-time 1 http://localhost:9527/api/info >/dev/null 2>&1
  return $?
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

  # Start server as daemon (detached, no output)
  nohup bun run "$server_script" --project-root "$PROJECT_ROOT" --no-open \
    >/dev/null 2>&1 &

  local server_pid=$!

  # Wait up to 3 seconds for server to be ready
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

# --- Main logic ---
if check_server_alive; then
  # Already running, silent exit
  exit 0
fi

# Not running, start it
if start_server; then
  echo "✨ 引擎已启动，GUI 大盘见 http://localhost:9527"
else
  # Failed to start, but don't block autopilot execution
  exit 0
fi

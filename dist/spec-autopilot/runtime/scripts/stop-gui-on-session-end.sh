#!/usr/bin/env bash
# stop-gui-on-session-end.sh
# SessionEnd 钩子：仅终止"当前项目"GUI 服务器，严禁 pkill 全局匹配
# 作用域锚定：stdin.cwd → git toplevel → $PROJECT_ROOT/logs/.gui-server.pid
# 决不对其它项目正在运行的 autopilot GUI 造成影响

set -uo pipefail

STDIN_DATA=""
if [ ! -t 0 ]; then
  STDIN_DATA=$(cat)
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 解析 project root：优先 stdin.cwd（Claude Code SessionEnd 载荷），兜底 $CLAUDE_PROJECT_DIR / pwd
resolve_project_root() {
  local payload="$1"
  printf '%s' "$payload" | python3 -c '
import json, os, sys, subprocess
raw = sys.stdin.read()
try:
    data = json.loads(raw) if raw else {}
except Exception:
    data = {}
cwd = data.get("cwd") or os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()
try:
    root = subprocess.check_output(
        ["git", "rev-parse", "--show-toplevel"],
        cwd=cwd, stderr=subprocess.DEVNULL
    ).decode().strip()
except Exception:
    root = cwd
print(root)
' 2>/dev/null || true
}

PROJECT_ROOT=""
if [ -n "$STDIN_DATA" ]; then
  PROJECT_ROOT=$(resolve_project_root "$STDIN_DATA")
fi
[ -z "$PROJECT_ROOT" ] && PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"

PID_FILE="$PROJECT_ROOT/logs/.gui-server.pid"

# 没有 PID 文件 → 本项目没启过 GUI / 已停 → 静默退出，绝不误伤其它项目
if [ ! -f "$PID_FILE" ]; then
  exit 0
fi

# 委托给 start-gui-server.sh --stop，它只操作 PID 文件中的进程（项目作用域）
# 严禁在本脚本使用 `pkill -f "autopilot-server"` — 会误伤其它项目实例
bash "$SCRIPT_DIR/start-gui-server.sh" --stop "$PROJECT_ROOT" >/dev/null 2>&1 || true

exit 0

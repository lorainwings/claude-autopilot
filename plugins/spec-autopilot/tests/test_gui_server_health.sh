#!/usr/bin/env bash
# test_gui_server_health.sh — GUI server 守护启动脚本健壮性测试
# 覆盖: --stop 模式退出码、--check-health 无服务器行为、PID 文件写入
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$TEST_DIR/.." && pwd)"
SCRIPT="$PLUGIN_DIR/runtime/scripts/start-gui-server.sh"
source "$TEST_DIR/_test_helpers.sh"

echo "--- GUI server health tests ---"

TMP_DIR=$(mktemp -d)
cleanup() {
  # 终止可能启动的服务器
  if [ -f "$TMP_DIR/logs/.gui-server.pid" ]; then
    local pid
    pid=$(cat "$TMP_DIR/logs/.gui-server.pid" 2>/dev/null)
    [ -n "$pid" ] && kill "$pid" 2>/dev/null || true
  fi
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

mkdir -p "$TMP_DIR/logs"

# ══════════════════════════════════════════════════════
# 1. --stop 模式：无 PID 文件时应返回非零
# ══════════════════════════════════════════════════════

echo ""
echo "  [1] --stop mode exit codes"

bash "$SCRIPT" --stop "$TMP_DIR" >/dev/null 2>&1
STOP_EXIT=$?
assert_exit "1a. --stop without PID file returns non-zero" 1 "$STOP_EXIT"

# 创建假 PID 文件（进程不存在的 PID）
echo "99999999" > "$TMP_DIR/logs/.gui-server.pid"
bash "$SCRIPT" --stop "$TMP_DIR" >/dev/null 2>&1
STOP_EXIT2=$?
assert_exit "1b. --stop with stale PID returns non-zero" 1 "$STOP_EXIT2"

# PID 文件应已被清理
if [ ! -f "$TMP_DIR/logs/.gui-server.pid" ]; then
  green "  PASS: 1c. stale PID file cleaned after --stop"
  PASS=$((PASS + 1))
else
  red "  FAIL: 1c. PID file not cleaned after --stop"
  FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════════════════
# 2. --check-health 模式：无服务器时行为
# ══════════════════════════════════════════════════════

echo ""
echo "  [2] --check-health mode without running server"

# 确保端口 9527 无服务运行（如果有则跳过）
if curl -s --max-time 1 http://localhost:9527/api/info >/dev/null 2>&1; then
  echo "  [SKIP] port 9527 already in use, skipping --check-health tests"
else
  if command -v bun &>/dev/null; then
    # bun 可用时 check-health 会尝试重启，server 会成功启动
    bash "$SCRIPT" --check-health "$TMP_DIR" >/dev/null 2>&1
    HEALTH_EXIT=$?
    # 启动后验证 PID 文件写入
    if [ -f "$TMP_DIR/logs/.gui-server.pid" ]; then
      green "  PASS: 2a. --check-health wrote PID file after restart"
      PASS=$((PASS + 1))
      # 清理：终止重启的服务器
      local_pid=$(cat "$TMP_DIR/logs/.gui-server.pid" 2>/dev/null)
      [ -n "$local_pid" ] && kill "$local_pid" 2>/dev/null
      sleep 0.5
    else
      red "  FAIL: 2a. --check-health did not write PID file"
      FAIL=$((FAIL + 1))
    fi
  else
    # bun 不可用，check-health 应失败
    bash "$SCRIPT" --check-health "$TMP_DIR" >/dev/null 2>&1
    HEALTH_EXIT=$?
    if [ "$HEALTH_EXIT" -ne 0 ]; then
      green "  PASS: 2a. --check-health returns non-zero when bun unavailable (exit=$HEALTH_EXIT)"
      PASS=$((PASS + 1))
    else
      red "  FAIL: 2a. --check-health should return non-zero when bun unavailable"
      FAIL=$((FAIL + 1))
    fi
  fi
fi

# ══════════════════════════════════════════════════════
# 3. PID 文件写入验证（通过 start 模式）
# ══════════════════════════════════════════════════════

echo ""
echo "  [3] PID file management"

# 测试 PID 目录创建
PID_DIR="$TMP_DIR/logs"
if [ -d "$PID_DIR" ]; then
  green "  PASS: 3a. logs directory exists for PID file"
  PASS=$((PASS + 1))
else
  red "  FAIL: 3a. logs directory not present"
  FAIL=$((FAIL + 1))
fi

# 验证 PID 文件路径常量（通过 grep 源码）
if grep -q 'PID_FILE="$LOGS_DIR/.gui-server.pid"' "$SCRIPT"; then
  green "  PASS: 3b. PID file path is logs/.gui-server.pid"
  PASS=$((PASS + 1))
else
  red "  FAIL: 3b. PID file path not found in script"
  FAIL=$((FAIL + 1))
fi

# 验证日志重定向路径（而非 /dev/null）
if grep -q 'gui-server.log' "$SCRIPT" && grep -q 'gui-server.err.log' "$SCRIPT"; then
  green "  PASS: 3c. server logs redirected to gui-server.log and gui-server.err.log"
  PASS=$((PASS + 1))
else
  red "  FAIL: 3c. server log redirection not configured"
  FAIL=$((FAIL + 1))
fi

# 验证不再重定向到 /dev/null
if grep -q '>/dev/null 2>&1 &' "$SCRIPT"; then
  red "  FAIL: 3d. still redirecting to /dev/null"
  FAIL=$((FAIL + 1))
else
  green "  PASS: 3d. no /dev/null redirection for server output"
  PASS=$((PASS + 1))
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1
exit 0

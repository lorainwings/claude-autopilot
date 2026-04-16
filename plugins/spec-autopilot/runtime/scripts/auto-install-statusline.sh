#!/usr/bin/env bash
# auto-install-statusline.sh
# Hook: SessionStart (async)
# Purpose: Auto-detect and install statusLine configuration if not already present.
#          Ensures GUI telemetry receives status_snapshot events without manual setup.
#          安装后执行健康检查验证，stale 配置自动重新安装，支持重试。
#
# Output: stdout text is added to Claude's context (SessionStart behavior).
# Exit codes: 0 (informational only, never blocks)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COLLECTOR_SCRIPT="$SCRIPT_DIR/statusline-collector.sh"
HEALTH_CHECK_SCRIPT="$SCRIPT_DIR/statusline-health-check.sh"
[ -f "$COLLECTOR_SCRIPT" ] || exit 0

# --- Resolve project root ---
STDIN_DATA=""
if [ ! -t 0 ]; then
  STDIN_DATA=$(cat)
fi

PROJECT_ROOT=""
if [ -n "$STDIN_DATA" ]; then
  PROJECT_ROOT=$(echo "$STDIN_DATA" | grep -o '"cwd"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
fi
[ -z "$PROJECT_ROOT" ] && PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

# --- Project relevance guard: only install in projects that use autopilot ---
[ -d "$PROJECT_ROOT/openspec" ] || [ -f "$PROJECT_ROOT/.claude/autopilot.config.yaml" ] || exit 0

# --- Check if statusLine is already configured in any scope ---
# Priority: local > project > user
CLAUDE_DIR="$PROJECT_ROOT/.claude"
LOCAL_SETTINGS="$CLAUDE_DIR/settings.local.json"
PROJECT_SETTINGS="$CLAUDE_DIR/settings.json"
USER_SETTINGS="${HOME}/.claude/settings.json"

statusline_configured() {
  local file="$1"
  [ -f "$file" ] || return 1
  python3 -c "
import json, sys, os, re
try:
    d = json.loads(open(sys.argv[1]).read())
    sl = d.get('statusLine')
    if sl and isinstance(sl, dict) and sl.get('command'):
        cmd = sl['command']
        # If command uses \${CLAUDE_PLUGIN_ROOT}, trust it (resolved at runtime).
        if '\${CLAUDE_PLUGIN_ROOT' in cmd or '\$CLAUDE_PLUGIN_ROOT' in cmd:
            sys.exit(0)
        # Extract .sh script path(s) and verify existence.
        paths = re.findall(r'(?:^|\s)(/.+?\.sh)', cmd)
        for p in paths:
            if not os.path.isfile(p):
                sys.exit(1)  # stale path — trigger re-install
        sys.exit(0)
    sys.exit(1)
except Exception:
    sys.exit(1)
" "$file" 2>/dev/null
}

# --- 健康检查函数：验证安装后配置是否有效 ---
run_health_check() {
  if [ -f "$HEALTH_CHECK_SCRIPT" ]; then
    local result
    result=$(bash "$HEALTH_CHECK_SCRIPT" --project-root "$PROJECT_ROOT" 2>/dev/null) || true
    # 从 JSON 输出中提取 healthy 字段
    if python3 -c "import json,sys; d=json.loads(sys.argv[1]); sys.exit(0 if d.get('healthy') else 1)" "$result" 2>/dev/null; then
      return 0
    fi
    echo "$result"
    return 1
  fi
  # 如果健康检查脚本不存在，跳过检查
  return 0
}

# --- 安装函数（含重试机制）---
do_install() {
  local retries=0
  local max_retries=1
  local installed=false
  local issues="[]"

  while [ "$retries" -le "$max_retries" ]; do
    if bash "$SCRIPT_DIR/install-statusline-config.sh" --project-root "$PROJECT_ROOT" --scope local >/dev/null 2>&1; then
      # 安装后立即执行健康检查验证
      local check_result=""
      if check_result=$(run_health_check 2>/dev/null); then
        installed=true
        break
      else
        # 健康检查返回了问题
        issues=$(python3 -c "import json,sys; print(json.dumps(json.loads(sys.argv[1]).get('issues',[])))" "$check_result" 2>/dev/null || echo "[]")
      fi
    fi

    if [ "$retries" -lt "$max_retries" ]; then
      sleep 1
    fi
    retries=$((retries + 1))
  done

  # 写入安装结果日志
  write_install_log "$installed" "$retries" "$issues"

  if [ "$installed" = "true" ]; then
    return 0
  fi
  return 1
}

# --- 写入安装结果到 logs/statusline-install.json ---
write_install_log() {
  local installed="$1"
  local retries="$2"
  local issues="$3"
  local log_dir="$PROJECT_ROOT/logs"
  mkdir -p "$log_dir" 2>/dev/null || return 0
  local timestamp
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo "unknown")

  python3 -c "
import json, sys
data = {
    'installed': sys.argv[1] == 'true',
    'timestamp': sys.argv[2],
    'issues': json.loads(sys.argv[3]),
    'retries': int(sys.argv[4])
}
print(json.dumps(data, ensure_ascii=False, indent=2))
" "$installed" "$timestamp" "$issues" "$retries" >"$log_dir/statusline-install.json" 2>/dev/null || true
}

# --- 检查命令是否包含运行时 env var（仅 Claude Code 运行时解析）---
has_envvar_format() {
  local file="$1"
  [ -f "$file" ] || return 1
  grep -q 'CLAUDE_PLUGIN_ROOT' "$file" 2>/dev/null
}

# --- 已配置时检查是否 stale ---
if statusline_configured "$LOCAL_SETTINGS" ||
  statusline_configured "$PROJECT_SETTINGS" ||
  statusline_configured "$USER_SETTINGS"; then
  # env var 格式路径只能在 Claude Code 运行时解析，跳过 stale 检测
  if has_envvar_format "$LOCAL_SETTINGS" ||
    has_envvar_format "$PROJECT_SETTINGS" ||
    has_envvar_format "$USER_SETTINGS"; then
    exit 0
  fi
  # 即使已配置，运行健康检查确认非 stale
  if run_health_check >/dev/null 2>&1; then
    exit 0
  fi
  # 健康检查失败 → stale 配置，重新安装
  if do_install; then
    echo "[autopilot] statusLine config was stale — re-installed (scope: local). GUI telemetry is now active."
  fi
  exit 0
fi

# --- Auto-install statusLine (local scope, non-intrusive) ---
if do_install; then
  echo "[autopilot] statusLine hook auto-installed (scope: local). GUI telemetry is now active."
fi
exit 0

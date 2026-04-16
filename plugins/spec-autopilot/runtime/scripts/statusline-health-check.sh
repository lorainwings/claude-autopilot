#!/usr/bin/env bash
# statusline-health-check.sh — Statusline 安装状态健康检查
# 用法: statusline-health-check.sh [--project-root <path>]
# 输出 JSON: {"healthy":bool,"issues":["..."]}
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

PROJECT_ROOT=""

while [ $# -gt 0 ]; do
  case "${1:-}" in
    --project-root)
      PROJECT_ROOT="${2:-}"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

[ -z "$PROJECT_ROOT" ] && PROJECT_ROOT="$(resolve_project_root)"

ISSUES=()

# --- 检查 1: settings.local.json 是否存在且包含 statusLine 配置 ---
CLAUDE_DIR="$PROJECT_ROOT/.claude"
LOCAL_SETTINGS="$CLAUDE_DIR/settings.local.json"

if [ ! -f "$LOCAL_SETTINGS" ]; then
  ISSUES+=("settings_missing")
else
  # 检查是否包含 statusLine 配置
  if ! python3 -c "
import json, sys
d = json.loads(open(sys.argv[1]).read())
sl = d.get('statusLine')
if not sl or not isinstance(sl, dict) or not sl.get('command'):
    sys.exit(1)
" "$LOCAL_SETTINGS" 2>/dev/null; then
    ISSUES+=("statusline_config_missing")
  fi
fi

# --- 检查 2: statusLine.command 中引用的脚本路径是否存在且可执行 ---
if [ -f "$LOCAL_SETTINGS" ]; then
  CMD_PATH=$(python3 -c "
import json, sys, re, os
try:
    d = json.loads(open(sys.argv[1]).read())
    cmd = d.get('statusLine', {}).get('command', '')
    # 解析 \${CLAUDE_PLUGIN_ROOT:-fallback} 中的 fallback 路径
    resolved = re.sub(r'\\\$\{CLAUDE_PLUGIN_ROOT:-([^}]+)\}', r'\1', cmd)
    resolved = re.sub(r'\\\$CLAUDE_PLUGIN_ROOT', os.environ.get('CLAUDE_PLUGIN_ROOT', ''), resolved)
    paths = re.findall(r'(?:^|\s)(/.+?\.sh)', resolved)
    for p in paths:
        if not os.path.isfile(p):
            print(p)
            sys.exit(0)
    # 也检查 bash 后面的路径
    paths2 = re.findall(r'bash\s+(/.+?\.sh)', resolved)
    for p in paths2:
        if not os.path.isfile(p):
            print(p)
            sys.exit(0)
except Exception:
    pass
" "$LOCAL_SETTINGS" 2>/dev/null || true)
  if [ -n "$CMD_PATH" ]; then
    ISSUES+=("command_path_invalid:$CMD_PATH")
  fi
fi

# --- 检查 3: CLAUDE_PLUGIN_ROOT 是否已解析为有效路径 ---
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-}"
FALLBACK_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
if [ -n "$PLUGIN_ROOT" ]; then
  if [ ! -d "$PLUGIN_ROOT" ]; then
    ISSUES+=("plugin_root_invalid:$PLUGIN_ROOT")
  fi
elif [ ! -d "$FALLBACK_ROOT" ]; then
  ISSUES+=("fallback_root_invalid:$FALLBACK_ROOT")
fi

# --- 检查 4: statusline-collector.sh 是否存在且可执行 ---
COLLECTOR="$SCRIPT_DIR/statusline-collector.sh"
if [ ! -f "$COLLECTOR" ]; then
  ISSUES+=("collector_missing")
elif [ ! -x "$COLLECTOR" ]; then
  ISSUES+=("collector_not_executable")
fi

# --- 检查 5: session 目录 logs/sessions/ 是否可写 ---
LOGS_DIR="$PROJECT_ROOT/logs/sessions"
if [ -d "$LOGS_DIR" ]; then
  if [ ! -w "$LOGS_DIR" ]; then
    ISSUES+=("sessions_dir_not_writable")
  fi
else
  # 目录不存在时检查父目录是否可创建
  PARENT_DIR="$PROJECT_ROOT/logs"
  if [ -d "$PARENT_DIR" ] && [ ! -w "$PARENT_DIR" ]; then
    ISSUES+=("logs_dir_not_writable")
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
  ISSUES_JSON=$(python3 -c "
import json, sys
issues = sys.argv[1:]
print(json.dumps(issues))
" "${ISSUES[@]}")
fi

printf '{"healthy":%s,"issues":%s}\n' "$HEALTHY" "$ISSUES_JSON"

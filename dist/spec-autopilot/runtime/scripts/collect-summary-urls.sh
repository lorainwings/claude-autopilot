#!/usr/bin/env bash
# collect-summary-urls.sh — Phase 7 Summary Box 地址收集 (确定性 + 自愈)
#
# 修复历史：原 summary-box.md 内联 bash 仅从 allure-preview.json 被动读取 URL,
# 任一上游 AI 步骤 (Phase 6 A5.5 / Phase 7 Step 2.5) 被跳过则 URL 字段空,
# 导致 Allure 行渲染为 unavailable。本脚本将"自愈 + 收集"统一为确定性调用。
#
# 用法: collect-summary-urls.sh <change_dir> [base_port]
#
# 参数:
#   change_dir  — openspec/changes/<change_name> 路径
#   base_port   — Allure base port (默认 4040)
#
# 输出: stdout 单行 JSON
#   {
#     "allure_url":  "http://localhost:4041" | "",
#     "allure_pid":  "12345"                 | "",
#     "gui_url":     "http://localhost:9527" | "",
#     "services":    {"name": "url", ...}
#   }
#
# 副作用: 必要时调用 start-allure-serve.sh 自愈，写 allure-preview.json
# 退出码: 始终 0 (信息性脚本)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CHANGE_DIR="${1:-}"
BASE_PORT="${2:-4040}"

if [[ -z "$CHANGE_DIR" ]]; then
  echo "ERROR: 缺少 change_dir 参数" >&2
  echo "用法: collect-summary-urls.sh <change_dir> [base_port]" >&2
  exit 0
fi

CONTEXT_DIR="$CHANGE_DIR/context"
PREVIEW_FILE="$CONTEXT_DIR/allure-preview.json"
PID_FILE="$CONTEXT_DIR/allure-serve.pid"

# ─────────────────────────────────────────────────────────────
# Step 1: Allure 自愈 — 缺失 / 死进程 / URL 不通 → 调 start-allure-serve.sh
# ─────────────────────────────────────────────────────────────
allure_alive() {
  # 三重校验：preview 文件存在 + PID 存活 + URL 200/301/302
  [[ -f "$PREVIEW_FILE" ]] || return 1
  local pid url
  pid=$(python3 -c "import json; print(json.load(open('$PREVIEW_FILE')).get('pid',''))" 2>/dev/null || echo "")
  url=$(python3 -c "import json; print(json.load(open('$PREVIEW_FILE')).get('url',''))" 2>/dev/null || echo "")
  [[ -n "$pid" ]] && [[ -n "$url" ]] || return 1
  kill -0 "$pid" 2>/dev/null || return 1
  curl -s -o /dev/null -w "%{http_code}" --max-time 2 "$url" 2>/dev/null | grep -qE "^(200|301|302)$"
}

if ! allure_alive; then
  # 自愈：清理可能的僵尸 PID 文件，然后调用统一启动脚本
  if [[ -f "$PID_FILE" ]]; then
    stale_pid=$(cat "$PID_FILE" 2>/dev/null || echo "")
    if [[ -n "$stale_pid" ]] && ! kill -0 "$stale_pid" 2>/dev/null; then
      rm -f "$PID_FILE"
    fi
  fi
  # 静默调用，stderr 抑制（不污染 Summary Box）
  bash "$SCRIPT_DIR/start-allure-serve.sh" "$CHANGE_DIR" "$BASE_PORT" >/dev/null 2>&1 || true

  # 自愈后再校验：若仍不存活，清空 preview 文件避免渲染出陈旧 stale URL
  if ! allure_alive; then
    rm -f "$PREVIEW_FILE"
  fi
fi

# ─────────────────────────────────────────────────────────────
# Step 2: 读取 Allure URL / PID (自愈后再读一次)
# ─────────────────────────────────────────────────────────────
ALLURE_URL=""
ALLURE_PID=""
if [[ -f "$PREVIEW_FILE" ]]; then
  ALLURE_URL=$(python3 -c "import json; print(json.load(open('$PREVIEW_FILE')).get('url',''))" 2>/dev/null || echo "")
  ALLURE_PID=$(python3 -c "import json; print(json.load(open('$PREVIEW_FILE')).get('pid',''))" 2>/dev/null || echo "")
fi

# ─────────────────────────────────────────────────────────────
# Step 3: GUI URL (端口配置 + PID 存活校验)
# ─────────────────────────────────────────────────────────────
# CHANGE_DIR 形如 .../openspec/changes/<name>，向上 3 层才是项目根
PROJECT_ROOT=$(cd "$CHANGE_DIR/../../.." 2>/dev/null && pwd || pwd)
GUI_URL=""
GUI_PORT=$(python3 -c "
import yaml
try:
    cfg = yaml.safe_load(open('$PROJECT_ROOT/.claude/autopilot.config.yaml'))
    print(cfg.get('gui', {}).get('port', 9527))
except Exception:
    print(9527)
" 2>/dev/null || echo 9527)

GUI_PID_FILE="$PROJECT_ROOT/logs/.gui-server.pid"
if [[ -f "$GUI_PID_FILE" ]]; then
  GUI_PID_VAL=$(cat "$GUI_PID_FILE" 2>/dev/null || echo "")
  if [[ -n "$GUI_PID_VAL" ]] && kill -0 "$GUI_PID_VAL" 2>/dev/null; then
    GUI_URL="http://localhost:${GUI_PORT}"
  fi
fi
# Fallback: 即使 PID 文件缺失，端口 listen 也算可用 (兜底 vibeFlow 用例)
if [[ -z "$GUI_URL" ]] && lsof -iTCP:"$GUI_PORT" -sTCP:LISTEN -P 2>/dev/null | grep -q LISTEN; then
  GUI_URL="http://localhost:${GUI_PORT}"
fi

# ─────────────────────────────────────────────────────────────
# Step 4: services 字典 (从 autopilot.config.yaml)
# ─────────────────────────────────────────────────────────────
SERVICES_JSON=$(python3 -c "
import yaml, json
try:
    cfg = yaml.safe_load(open('$PROJECT_ROOT/.claude/autopilot.config.yaml'))
    svcs = cfg.get('services', {})
    out = {k: v for k, v in svcs.items() if isinstance(v, str)}
    print(json.dumps(out))
except Exception:
    print('{}')
" 2>/dev/null || echo "{}")

# ─────────────────────────────────────────────────────────────
# Step 5: 输出统一 JSON (通过 export 避免 shell 转义问题)
# ─────────────────────────────────────────────────────────────
export ALLURE_URL ALLURE_PID GUI_URL SERVICES_JSON
python3 -c "
import json, os
print(json.dumps({
    'allure_url': os.environ.get('ALLURE_URL', ''),
    'allure_pid': os.environ.get('ALLURE_PID', ''),
    'gui_url':    os.environ.get('GUI_URL', ''),
    'services':   json.loads(os.environ.get('SERVICES_JSON', '{}') or '{}')
}))
" 2>/dev/null || echo '{"allure_url":"","allure_pid":"","gui_url":"","services":{}}'
exit 0

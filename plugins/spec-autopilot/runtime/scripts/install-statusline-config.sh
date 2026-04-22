#!/usr/bin/env bash
# install-statusline-config.sh
# Install Claude Code statusLine configuration for spec-autopilot.
# Default scope: local project settings (.claude/settings.local.json).
# 增强: 安装前备份、写入后 JSON 验证、CLAUDE_PLUGIN_ROOT 绝对路径解析。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
SCOPE="local"
MODE="chain" # chain: 保留现有命令并 chain spec-autopilot; replace: 覆盖

while [ $# -gt 0 ]; do
  case "${1:-}" in
    --scope)
      SCOPE="${2:-local}"
      shift 2
      ;;
    --project-root)
      PROJECT_ROOT="$(cd "${2:-$PROJECT_ROOT}" && pwd)"
      shift 2
      ;;
    --mode)
      MODE="${2:-chain}"
      shift 2
      ;;
    *)
      echo "Usage: install-statusline-config.sh [--scope local|project|user] [--project-root PATH] [--mode chain|replace]" >&2
      exit 1
      ;;
  esac
done

case "$MODE" in
  chain | replace) ;;
  *)
    echo "ERROR: invalid mode '$MODE' (expected chain|replace)" >&2
    exit 1
    ;;
esac

case "$SCOPE" in
  local | project | user) ;;
  *)
    echo "ERROR: invalid scope '$SCOPE' (expected local|project|user)" >&2
    exit 1
    ;;
esac

COLLECTOR_SCRIPT="$SCRIPT_DIR/statusline-collector.sh"
[ -f "$COLLECTOR_SCRIPT" ] || {
  echo "ERROR: collector script not found: $COLLECTOR_SCRIPT" >&2
  exit 1
}

# 解析插件根目录（两级上层: runtime/scripts/ → 插件根）
# 优先使用 CLAUDE_PLUGIN_ROOT 解析为绝对路径，否则使用 $SCRIPT_DIR/../.. 作为 fallback
PLUGIN_ROOT_ABS="$(cd "$SCRIPT_DIR/../.." && pwd)"

# 如果 CLAUDE_PLUGIN_ROOT 已设置且有效，使用其绝对路径
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -d "$CLAUDE_PLUGIN_ROOT" ]; then
  RESOLVED_PLUGIN_ROOT="$(cd "$CLAUDE_PLUGIN_ROOT" && pwd)"
else
  RESOLVED_PLUGIN_ROOT="$PLUGIN_ROOT_ABS"
fi

if [ "$SCOPE" = "user" ]; then
  CLAUDE_DIR="${HOME}/.claude"
  SETTINGS_FILE="$CLAUDE_DIR/settings.json"
else
  CLAUDE_DIR="$PROJECT_ROOT/.claude"
  if [ "$SCOPE" = "project" ]; then
    SETTINGS_FILE="$CLAUDE_DIR/settings.json"
  else
    SETTINGS_FILE="$CLAUDE_DIR/settings.local.json"
  fi
fi

mkdir -p "$CLAUDE_DIR"

# 安装前备份已有 settings 文件
if [ -f "$SETTINGS_FILE" ]; then
  cp "$SETTINGS_FILE" "${SETTINGS_FILE}.bak"
fi

# 使用 ${CLAUDE_PLUGIN_ROOT} 运行时变量 + 绝对路径 fallback，确保跨版本可用
STATUSLINE_COMMAND="bash \${CLAUDE_PLUGIN_ROOT:-$RESOLVED_PLUGIN_ROOT}/runtime/scripts/statusline-collector.sh"

python3 - "$SETTINGS_FILE" "$STATUSLINE_COMMAND" "$MODE" <<'PY'
import json
import sys
from pathlib import Path

settings_path = Path(sys.argv[1])
autopilot_cmd = sys.argv[2]
mode = sys.argv[3]

data = {}
if settings_path.exists():
    try:
        data = json.loads(settings_path.read_text(encoding="utf-8"))
        if not isinstance(data, dict):
            data = {}
    except Exception:
        backup = settings_path.with_suffix(settings_path.suffix + ".bak")
        settings_path.replace(backup)
        data = {}

if "$schema" not in data:
    data["$schema"] = "https://json.schemastore.org/claude-code-settings.json"

existing = data.get("statusLine") or {}
existing_cmd = existing.get("command", "") if isinstance(existing, dict) else ""

# 判定 chain 场景：mode=chain 且 existing 非空且不含 spec-autopilot collector
needs_chain = (
    mode == "chain"
    and isinstance(existing_cmd, str)
    and existing_cmd.strip()
    and "spec-autopilot/runtime/scripts/statusline-collector.sh" not in existing_cmd
)

if needs_chain:
    # 构造 chain 命令：两个 collector 各自读取 stdin 并 join 输出
    # 关键要求：
    #   1. 两个 collector 都能读到同一份 stdin（通过 $INPUT 变量）
    #   2. 任一 collector 失败不影响整体（|| fallback）
    #   3. 输出合并，顺序：autopilot | existing
    # 设计：使用 base64 编码 existing 命令，避免嵌套 bash -c 的引号地狱
    import base64 as _b64
    prev_b64 = _b64.b64encode(existing_cmd.encode("utf-8")).decode("ascii")
    chain_cmd = (
        "bash -c 'INPUT=$(cat); "
        f"AP_OUT=$(printf \"%s\" \"$INPUT\" | {autopilot_cmd} 2>/dev/null || echo \"[autopilot] idle\"); "
        f"PREV_B64={prev_b64}; "
        "PREV_CMD=$(printf \"%s\" \"$PREV_B64\" | base64 -d 2>/dev/null); "
        "PREV_OUT=$(printf \"%s\" \"$INPUT\" | bash -c \"$PREV_CMD\" 2>/dev/null || true); "
        "if [ -n \"$PREV_OUT\" ]; then printf \"%s | %s\" \"$AP_OUT\" \"$PREV_OUT\"; "
        "else printf \"%s\" \"$AP_OUT\"; fi'"
    )
    data["statusLine"] = {
        "type": "command",
        "command": chain_cmd,
        "padding": 1,
    }
else:
    # replace 模式 或 现有 statusLine 已含 spec-autopilot collector 或 无现有 statusLine
    data["statusLine"] = {
        "type": "command",
        "command": autopilot_cmd,
        "padding": 1,
    }

settings_path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY

# 写入后验证 JSON 格式正确
if ! python3 -m json.tool "$SETTINGS_FILE" >/dev/null 2>&1; then
  echo "ERROR: generated settings file is not valid JSON: $SETTINGS_FILE" >&2
  # 如果有备份，恢复
  if [ -f "${SETTINGS_FILE}.bak" ]; then
    mv "${SETTINGS_FILE}.bak" "$SETTINGS_FILE"
  fi
  exit 1
fi

# Local scope should remain untracked when inside a git repository.
if [ "$SCOPE" = "local" ] && git -C "$PROJECT_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  GIT_DIR="$(git -C "$PROJECT_ROOT" rev-parse --git-dir)"
  case "$GIT_DIR" in
    /*) ;;
    *) GIT_DIR="$PROJECT_ROOT/$GIT_DIR" ;;
  esac
  EXCLUDE_FILE="$GIT_DIR/info/exclude"
  touch "$EXCLUDE_FILE"
  if ! grep -qxF '.claude/settings.local.json' "$EXCLUDE_FILE" 2>/dev/null; then
    printf "%s\n" '.claude/settings.local.json' >>"$EXCLUDE_FILE"
  fi
fi

printf "statusLine installed\n"
printf "scope=%s\n" "$SCOPE"
printf "settings=%s\n" "$SETTINGS_FILE"

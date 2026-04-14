#!/bin/bash
# check-skill-size.sh — 检测所有 SKILL.md 行数是否超过阈值
# 触发: SessionStart hook
# 用途: 防止 SKILL.md 膨胀导致 Claude Code 上下文消耗过大

set -euo pipefail

# --- Project relevance guard: only check in autopilot projects ---
# Parse cwd from SessionStart stdin JSON for accurate project root resolution.
_STDIN_CWD=""
if [ ! -t 0 ]; then
  _STDIN_DATA=$(cat)
  _STDIN_CWD=$(echo "$_STDIN_DATA" | grep -o '"cwd"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
fi
if [ -n "$_STDIN_CWD" ]; then
  _PROJECT_ROOT=$(git -C "$_STDIN_CWD" rev-parse --show-toplevel 2>/dev/null || echo "$_STDIN_CWD")
else
  _PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi
[ -d "$_PROJECT_ROOT/openspec" ] || [ -f "$_PROJECT_ROOT/.claude/autopilot.config.yaml" ] || exit 0

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
MAX_LINES=500
WARN_LINES=450
EXIT_CODE=0

for f in "$PLUGIN_ROOT"/skills/*/SKILL.md; do
  [ -f "$f" ] || continue
  lines=$(wc -l <"$f" | tr -d ' ')
  name=$(basename "$(dirname "$f")")
  if [ "$lines" -gt "$MAX_LINES" ]; then
    echo "BLOCKED: $name/SKILL.md = $lines lines (max: $MAX_LINES)"
    EXIT_CODE=1
  elif [ "$lines" -gt "$WARN_LINES" ]; then
    echo "WARNING: $name/SKILL.md = $lines lines (approaching $MAX_LINES)"
  fi
done

exit $EXIT_CODE

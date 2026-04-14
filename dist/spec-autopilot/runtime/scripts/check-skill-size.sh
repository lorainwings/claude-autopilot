#!/bin/bash
# check-skill-size.sh — 检测所有 SKILL.md 行数是否超过阈值
# 触发: SessionStart hook
# 用途: 防止 SKILL.md 膨胀导致 Claude Code 上下文消耗过大

set -euo pipefail

# --- Project relevance guard: only check in autopilot projects ---
_PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
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

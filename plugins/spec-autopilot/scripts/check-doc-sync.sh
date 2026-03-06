#!/usr/bin/env bash
# check-doc-sync.sh
# 检查文档是否与代码版本同步（用于 SessionStart Hook）

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# 提取版本号
PLUGIN_VERSION=$(grep '"version"' "$PLUGIN_DIR/.claude-plugin/plugin.json" 2>/dev/null | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+' | head -1)

if [ -z "$PLUGIN_VERSION" ]; then
  # 无法提取版本号，静默退出
  exit 0
fi

# 检查核心文档是否提及当前版本
DOCS=(
  "$PLUGIN_DIR/README.md"
  "$PLUGIN_DIR/docs/phases.md"
  "$PLUGIN_DIR/docs/configuration.md"
)

MISSING_DOCS=()
for doc in "${DOCS[@]}"; do
  if [ ! -f "$doc" ]; then
    continue
  fi

  # 检查是否包含版本号（支持 v3.1.0 或 3.1.0 格式）
  if ! grep -qE "$PLUGIN_VERSION|v$PLUGIN_VERSION" "$doc" 2>/dev/null; then
    MISSING_DOCS+=("$(basename "$doc")")
  fi
done

# 如果有文档未同步，输出警告
if [ ${#MISSING_DOCS[@]} -gt 0 ]; then
  echo ""
  echo "⚠️  文档同步警告"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "当前插件版本: $PLUGIN_VERSION"
  echo ""
  echo "以下文档未提及此版本:"
  printf '  • %s\n' "${MISSING_DOCS[@]}"
  echo ""
  echo "建议运行: /spec-autopilot:doc-sync"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
fi

exit 0

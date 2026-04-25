#!/usr/bin/env bash
# figma-handoff 构建脚本
# 用途:纯文件复制,生成 dist 产物(无编译步骤)
set -euo pipefail

PLUGIN_NAME="figma-handoff"
PLUGIN_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPO_ROOT="$(cd "$PLUGIN_DIR/../.." && pwd)"
DIST_DIR="$REPO_ROOT/dist/$PLUGIN_NAME"

echo "=== figma-handoff 构建流程 ==="
echo "插件目录: $PLUGIN_DIR"
echo "dist 目标: $DIST_DIR"
echo ""

# 1. 清理旧 dist
echo "--- 步骤 1/3: 清理旧 dist ---"
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"
echo "已清理"

# 2. 复制产物
echo ""
echo "--- 步骤 2/3: 复制产物 ---"

# 插件元数据
cp -r "$PLUGIN_DIR/.claude-plugin" "$DIST_DIR/"

# Skills
cp -r "$PLUGIN_DIR/skills" "$DIST_DIR/"

# CLAUDE.md — 裁剪 dev-only 段落(如有标记)
if grep -q "<!-- DEV-ONLY-BEGIN -->" "$PLUGIN_DIR/CLAUDE.md" 2>/dev/null; then
  sed '/<!-- DEV-ONLY-BEGIN -->/,/<!-- DEV-ONLY-END -->/d' "$PLUGIN_DIR/CLAUDE.md" >"$DIST_DIR/CLAUDE.md"
else
  cp "$PLUGIN_DIR/CLAUDE.md" "$DIST_DIR/"
fi

# 校验:dist 不包含禁止路径
for forbidden in tools version.txt CHANGELOG.md; do
  if [ -e "$DIST_DIR/$forbidden" ]; then
    echo "ERROR: dist 包含不应存在的路径: $forbidden"
    exit 1
  fi
done

SRC_SIZE=$(du -sh "$PLUGIN_DIR" 2>/dev/null | cut -f1)
DIST_SIZE=$(du -sh "$DIST_DIR" 2>/dev/null | cut -f1)
echo "dist built: $DIST_SIZE (source: $SRC_SIZE)"

# 3. 验证 dist 结构
echo ""
echo "--- 步骤 3/3: 验证 dist 结构 ---"

EXPECTED_FILES=(
  ".claude-plugin/plugin.json"
  "skills/figma-handoff/SKILL.md"
  "skills/figma-handoff/references/preflight.md"
  "skills/figma-handoff/references/figma-mcp-protocol.md"
  "skills/figma-handoff/references/translation-core.md"
  "skills/figma-handoff/references/translation-rules.md"
  "skills/figma-handoff/references/pixel-diff-protocol.md"
  "skills/figma-handoff/references/vendor-vant.md"
  "skills/figma-handoff/references/vendor-element-plus.md"
  "skills/figma-handoff/references/prompt-template.md"
  "skills/figma-handoff/references/scripts/preflight.sh"
  "skills/figma-handoff/references/scripts/visual-diff.mjs"
  "skills/figma-handoff/references/adapters/framework-vue.md"
  "skills/figma-handoff/references/adapters/framework-react.md"
  "skills/figma-handoff/references/adapters/lib-tailwind.md"
  "skills/figma-handoff/references/adapters/lib-shadcn.md"
  "skills/figma-handoff/references/adapters/lib-antd.md"
  "skills/figma-handoff/references/adapters/lib-mui.md"
  "skills/figma-handoff/references/adapters/lib-chakra.md"
  "skills/figma-handoff/references/adapters/lib-mantine.md"
  "skills/figma-handoff/references/adapters/lib-vant.md"
  "skills/figma-handoff/references/adapters/lib-element-plus.md"
  "skills/figma-handoff/references/adapters/lib-naive.md"
  "skills/figma-handoff/references/adapters/lib-arco.md"
  "skills/figma-handoff/references/adapters/lib-tdesign.md"
  "skills/figma-handoff/references/adapters/lib-primevue.md"
  "CLAUDE.md"
)

ALL_OK=true
for f in "${EXPECTED_FILES[@]}"; do
  if [ -f "$DIST_DIR/$f" ]; then
    echo "  ✓ $f"
  else
    echo "  ✗ $f (MISSING)"
    ALL_OK=false
  fi
done

if [ "$ALL_OK" = false ]; then
  echo ""
  echo "ERROR: dist 结构验证失败"
  exit 1
fi

echo ""
echo "=== 构建完成 ==="
echo "  dist: $DIST_DIR"

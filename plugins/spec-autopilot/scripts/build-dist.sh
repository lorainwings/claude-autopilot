#!/usr/bin/env bash
# build-dist.sh — 构建运行时插件发布包
set -euo pipefail

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$PLUGIN_ROOT/../.." && pwd)"
DIST_DIR="$REPO_ROOT/dist/plugin"

# 1. 清空并重建
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

# 2. 白名单复制
cp -r "$PLUGIN_ROOT/.claude-plugin" "$DIST_DIR/"
cp -r "$PLUGIN_ROOT/hooks"          "$DIST_DIR/"
cp -r "$PLUGIN_ROOT/skills"         "$DIST_DIR/"
cp -r "$PLUGIN_ROOT/gui-dist"       "$DIST_DIR/"

# 3. scripts/ — 排除开发专用脚本
mkdir -p "$DIST_DIR/scripts"
EXCLUDE_SCRIPTS="test-hooks.sh|bump-version.sh|build-dist.sh"
for f in "$PLUGIN_ROOT/scripts/"*; do
  fname=$(basename "$f")
  if ! echo "$fname" | grep -qE "^($EXCLUDE_SCRIPTS)$"; then
    cp "$f" "$DIST_DIR/scripts/"
  fi
done

# 4. CLAUDE.md — 裁剪 dev-only 段落
sed '/<!-- DEV-ONLY-BEGIN -->/,/<!-- DEV-ONLY-END -->/d' \
  "$PLUGIN_ROOT/CLAUDE.md" > "$DIST_DIR/CLAUDE.md"

# 5. 校验: hooks.json 引用的脚本都存在于 dist
MISSING=0
for script in $(grep -o 'scripts/[^"]*' "$DIST_DIR/hooks/hooks.json" | sed 's|scripts/||'); do
  if [ ! -f "$DIST_DIR/scripts/$script" ]; then
    echo "ERROR: hooks.json references scripts/$script but it's missing from dist"
    MISSING=1
  fi
done
[ "$MISSING" -eq 1 ] && exit 1

# 6. CLAUDE.md 裁剪验证
for keyword in "测试纪律" "构建纪律" "发版纪律"; do
  if grep -q "$keyword" "$DIST_DIR/CLAUDE.md"; then
    echo "ERROR: dist CLAUDE.md still contains dev-only section: $keyword"
    exit 1
  fi
done

# 7. 隔离验证
for forbidden in "gui" "docs" "tests" "test-hooks.sh" "CHANGELOG.md" "README.md"; do
  if [ -e "$DIST_DIR/$forbidden" ]; then
    echo "ERROR: dist contains forbidden path: $forbidden"
    exit 1
  fi
done

# 8. 大小对比
SRC_SIZE=$(du -sh "$PLUGIN_ROOT" | cut -f1)
DIST_SIZE=$(du -sh "$DIST_DIR" | cut -f1)
echo "✅ dist built: $DIST_SIZE (source: $SRC_SIZE)"

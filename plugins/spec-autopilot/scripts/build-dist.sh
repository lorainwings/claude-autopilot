#!/usr/bin/env bash
# build-dist.sh — 构建运行时插件发布包
set -euo pipefail

PLUGIN_NAME="spec-autopilot"
PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$PLUGIN_ROOT/../.." && pwd)"
DIST_DIR="$REPO_ROOT/dist/$PLUGIN_NAME"
GUI_ROOT="$PLUGIN_ROOT/gui"
GUI_DIST_DIR="$PLUGIN_ROOT/gui-dist"

# 1. 清空并重建
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

# 2. 重新构建 GUI（确保 __PLUGIN_VERSION__ 与 plugin.json 同步）
try_build_gui() {
  if ! command -v bun >/dev/null 2>&1 || [ ! -d "$GUI_ROOT/node_modules" ]; then
    return 1
  fi
  echo "🔨 Building GUI (syncing version from plugin.json)..."
  local build_output
  if build_output=$(cd "$GUI_ROOT" && bun run build --mode production 2>&1); then
    echo "$build_output" | tail -1
    # Kill running autopilot-server so next access starts fresh with new assets
    pkill -f "bun.*autopilot-server.ts.*--project-root" 2>/dev/null || true
    return 0
  else
    echo "WARNING: GUI build failed, checking for fallback gui-dist..." >&2
    echo "$build_output" | tail -3 >&2
    return 1
  fi
}

if [ -f "$GUI_ROOT/package.json" ]; then
  if ! try_build_gui; then
    if [ -d "$GUI_DIST_DIR" ]; then
      echo "ℹ️ GUI build unavailable; using checked-in gui-dist (fallback)"
    else
      echo "ERROR: gui-dist missing and GUI rebuild failed"
      exit 1
    fi
  fi
fi

if [ ! -d "$GUI_DIST_DIR" ]; then
  echo "ERROR: gui-dist directory is missing: $GUI_DIST_DIR"
  exit 1
fi

# 2b. Write gui-dist build metadata
PLUGIN_VERSION=$(python3 -c "import json; print(json.load(open('$PLUGIN_ROOT/.claude-plugin/plugin.json'))['version'])" 2>/dev/null || echo "unknown")
cat > "$GUI_DIST_DIR/.build-meta.json" <<BMEOF
{"plugin_version":"$PLUGIN_VERSION","build_time":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","build_tool":"$(bun --version 2>/dev/null || echo 'fallback')"}
BMEOF

# 3. 白名单复制
cp -r "$PLUGIN_ROOT/.claude-plugin" "$DIST_DIR/"
cp -r "$PLUGIN_ROOT/hooks"          "$DIST_DIR/"
cp -r "$PLUGIN_ROOT/skills"         "$DIST_DIR/"
cp -r "$GUI_DIST_DIR"               "$DIST_DIR/"

# 4. scripts/ — 排除开发专用脚本和 node_modules
mkdir -p "$DIST_DIR/scripts"
EXCLUDE_SCRIPTS="bump-version.sh|build-dist.sh"
for f in "$PLUGIN_ROOT/scripts/"*; do
  # Skip subdirectories (including node_modules/)
  [ -f "$f" ] || continue
  fname=$(basename "$f")
  if ! echo "$fname" | grep -qE "^($EXCLUDE_SCRIPTS)$"; then
    cp "$f" "$DIST_DIR/scripts/"
  fi
done

# 5. CLAUDE.md — 裁剪 dev-only 段落
sed '/<!-- DEV-ONLY-BEGIN -->/,/<!-- DEV-ONLY-END -->/d' \
  "$PLUGIN_ROOT/CLAUDE.md" > "$DIST_DIR/CLAUDE.md"

# 6. 校验: hooks.json 引用的脚本都存在于 dist
MISSING=0
for script in $(grep -o 'scripts/[^"]*' "$DIST_DIR/hooks/hooks.json" | sed 's|scripts/||'); do
  if [ ! -f "$DIST_DIR/scripts/$script" ]; then
    echo "ERROR: hooks.json references scripts/$script but it's missing from dist"
    MISSING=1
  fi
done
[ "$MISSING" -eq 1 ] && exit 1

# 7. CLAUDE.md 裁剪验证
for keyword in "测试纪律" "构建纪律" "发版纪律"; do
  if grep -q "$keyword" "$DIST_DIR/CLAUDE.md"; then
    echo "ERROR: dist CLAUDE.md still contains dev-only section: $keyword"
    exit 1
  fi
done

# 8. 隔离验证
for forbidden in "gui" "docs" "tests" "CHANGELOG.md" "README.md" "scripts/node_modules"; do
  if [ -e "$DIST_DIR/$forbidden" ]; then
    echo "ERROR: dist contains forbidden path: $forbidden"
    exit 1
  fi
done

# 9. 大小对比
SRC_SIZE=$(du -sh "$PLUGIN_ROOT" | cut -f1)
DIST_SIZE=$(du -sh "$DIST_DIR" | cut -f1)
echo "✅ dist/$PLUGIN_NAME built: $DIST_SIZE (source: $SRC_SIZE)"

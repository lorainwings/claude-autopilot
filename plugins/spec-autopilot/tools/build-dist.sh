#!/usr/bin/env bash
# build-dist.sh — 构建运行时插件发布包
set -euo pipefail

PLUGIN_NAME="spec-autopilot"
PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$PLUGIN_ROOT/../.." && pwd)"
DIST_DIR="$REPO_ROOT/dist/$PLUGIN_NAME"
GUI_ROOT="$PLUGIN_ROOT/gui"
GUI_DIST_DIR="$PLUGIN_ROOT/gui-dist"

# 1. Fresh-clone fallback: plugins/gui-dist is gitignored, but dist/gui-dist
#    is tracked. Recover it before we wipe DIST_DIR, so the build can fall
#    back to it when bun is unavailable.
if [ ! -d "$GUI_DIST_DIR" ] && [ -d "$DIST_DIR/gui-dist" ]; then
  cp -r "$DIST_DIR/gui-dist" "$GUI_DIST_DIR"
  echo "ℹ️  Recovered gui-dist from dist/ (fresh-clone fallback)"
fi

# 2. 清空并重建
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

# 3. 重新构建 GUI（确保 __PLUGIN_VERSION__ 与 plugin.json 同步）
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

# 3b. Write gui-dist build metadata
PLUGIN_VERSION=$(python3 -c "import json; print(json.load(open('$PLUGIN_ROOT/.claude-plugin/plugin.json'))['version'])" 2>/dev/null || echo "unknown")
cat > "$GUI_DIST_DIR/.build-meta.json" <<BMEOF
{"plugin_version":"$PLUGIN_VERSION","build_time":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","build_tool":"$(bun --version 2>/dev/null || echo 'fallback')"}
BMEOF

# 4. 白名单复制
cp -r "$PLUGIN_ROOT/.claude-plugin" "$DIST_DIR/"
cp -r "$PLUGIN_ROOT/hooks"          "$DIST_DIR/"
cp -r "$PLUGIN_ROOT/skills"         "$DIST_DIR/"
cp -r "$GUI_DIST_DIR"               "$DIST_DIR/"

# 5. scripts/ — 按 runtime manifest 逐项复制（Phase 0: 排除式 → 清单式）
MANIFEST="$PLUGIN_ROOT/scripts/.dist-include"
if [ ! -f "$MANIFEST" ]; then
  echo "ERROR: runtime manifest not found: $MANIFEST"
  exit 1
fi
mkdir -p "$DIST_DIR/scripts"
MANIFEST_COUNT=0
while IFS= read -r line; do
  # 跳过注释和空行
  line="${line%%#*}"
  line="$(echo "$line" | xargs)"
  [ -z "$line" ] && continue
  if [ ! -f "$PLUGIN_ROOT/scripts/$line" ]; then
    echo "ERROR: manifest entry missing from source: scripts/$line"
    exit 1
  fi
  cp "$PLUGIN_ROOT/scripts/$line" "$DIST_DIR/scripts/"
  MANIFEST_COUNT=$((MANIFEST_COUNT + 1))
done < "$MANIFEST"
echo "📋 Manifest-driven copy: $MANIFEST_COUNT files → dist/scripts/"

# 5b. server 回填: 将 server/autopilot-server.ts 复制到 dist/scripts/（dist 态需要）
if [ -f "$PLUGIN_ROOT/server/autopilot-server.ts" ]; then
  cp "$PLUGIN_ROOT/server/autopilot-server.ts" "$DIST_DIR/scripts/"
  echo "📋 Server backfill: server/autopilot-server.ts → dist/scripts/"
fi

# 6. CLAUDE.md — 裁剪 dev-only 段落
sed '/<!-- DEV-ONLY-BEGIN -->/,/<!-- DEV-ONLY-END -->/d' \
  "$PLUGIN_ROOT/CLAUDE.md" > "$DIST_DIR/CLAUDE.md"

# 7. 校验: hooks.json 引用的脚本都存在于 dist
MISSING=0
for script in $(grep -o 'scripts/[^" ]*\.sh' "$DIST_DIR/hooks/hooks.json" | sed 's|scripts/||'); do
  if [ ! -f "$DIST_DIR/scripts/$script" ]; then
    echo "ERROR: hooks.json references scripts/$script but it's missing from dist"
    MISSING=1
  fi
done
[ "$MISSING" -eq 1 ] && exit 1

# 7b. 校验: hooks.json 引用的脚本都在 manifest 中
for script in $(grep -o 'scripts/[^" ]*\.sh' "$DIST_DIR/hooks/hooks.json" | sed 's|scripts/||'); do
  if ! grep -qxF "$script" <(sed 's/#.*//' "$MANIFEST" | xargs -n1 2>/dev/null); then
    echo "ERROR: hooks.json references scripts/$script but it's NOT in manifest"
    MISSING=1
  fi
done
[ "$MISSING" -eq 1 ] && exit 1

# 7c. 校验: dist/scripts/ 中不存在清单外文件（server 回填的 autopilot-server.ts 豁免）
LEAKED=0
for f in "$DIST_DIR/scripts/"*; do
  [ -f "$f" ] || continue
  fname=$(basename "$f")
  [ "$fname" = "autopilot-server.ts" ] && continue
  if ! grep -qxF "$fname" <(sed 's/#.*//' "$MANIFEST" | xargs -n1 2>/dev/null); then
    echo "ERROR: dist/scripts/ contains file not in manifest: $fname"
    LEAKED=1
  fi
done
[ "$LEAKED" -eq 1 ] && exit 1

# 8. CLAUDE.md 裁剪验证
for keyword in "测试纪律" "构建纪律" "发版纪律"; do
  if grep -q "$keyword" "$DIST_DIR/CLAUDE.md"; then
    echo "ERROR: dist CLAUDE.md still contains dev-only section: $keyword"
    exit 1
  fi
done

# 9. 隔离验证
for forbidden in "gui" "docs" "tests" "CHANGELOG.md" "README.md" "scripts/node_modules"; do
  if [ -e "$DIST_DIR/$forbidden" ]; then
    echo "ERROR: dist contains forbidden path: $forbidden"
    exit 1
  fi
done

# 10. 大小对比
SRC_SIZE=$(du -sh "$PLUGIN_ROOT" | cut -f1)
DIST_SIZE=$(du -sh "$DIST_DIR" | cut -f1)
echo "✅ dist/$PLUGIN_NAME built: $DIST_SIZE (source: $SRC_SIZE)"

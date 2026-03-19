#!/usr/bin/env bash
# build-dist.sh — 构建运行时插件发布包
set -euo pipefail

PLUGIN_NAME="spec-autopilot"
PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$PLUGIN_ROOT/../.." && pwd)"
DIST_DIR="$REPO_ROOT/dist/$PLUGIN_NAME"
GUI_ROOT="$PLUGIN_ROOT/gui"
GUI_DIST_DIR="$PLUGIN_ROOT/gui-dist"

# 1. Fresh-clone fallback: plugins/gui-dist is gitignored, but dist/assets/gui
#    is tracked. Recover it before we wipe DIST_DIR.
if [ ! -d "$GUI_DIST_DIR" ] && [ -d "$DIST_DIR/assets/gui" ]; then
  cp -r "$DIST_DIR/assets/gui" "$GUI_DIST_DIR"
  echo "ℹ️  Recovered gui-dist from dist/assets/gui (fresh-clone fallback)"
elif [ ! -d "$GUI_DIST_DIR" ] && [ -d "$DIST_DIR/gui-dist" ]; then
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

# ═══════════════════════════════════════════════════════
# 4. 目标 dist 结构:
#   dist/spec-autopilot/
#     .claude-plugin/
#     hooks/
#     runtime/
#       server/    ← TS 模块化 server
#       scripts/   ← shell hook + util 脚本
#     assets/
#       gui/       ← GUI 静态产物 (从 gui-dist 收敛)
#     skills/
#     CLAUDE.md
# ═══════════════════════════════════════════════════════

cp -r "$PLUGIN_ROOT/.claude-plugin" "$DIST_DIR/"
cp -r "$PLUGIN_ROOT/hooks"          "$DIST_DIR/"
cp -r "$PLUGIN_ROOT/skills"         "$DIST_DIR/"

# 4a. GUI 产物 → assets/gui/ (语义收敛，不再用 gui-dist)
mkdir -p "$DIST_DIR/assets"
cp -r "$GUI_DIST_DIR" "$DIST_DIR/assets/gui"

# 5. runtime/scripts/ — 按 manifest 逐项复制
MANIFEST="$PLUGIN_ROOT/runtime/scripts/.dist-include"
if [ ! -f "$MANIFEST" ]; then
  echo "ERROR: runtime manifest not found: $MANIFEST"
  exit 1
fi
mkdir -p "$DIST_DIR/runtime/scripts"
MANIFEST_COUNT=0
while IFS= read -r line; do
  line="${line%%#*}"
  line="$(echo "$line" | xargs)"
  [ -z "$line" ] && continue
  if [ ! -f "$PLUGIN_ROOT/runtime/scripts/$line" ]; then
    echo "ERROR: manifest entry missing from source: runtime/scripts/$line"
    exit 1
  fi
  cp "$PLUGIN_ROOT/runtime/scripts/$line" "$DIST_DIR/runtime/scripts/"
  MANIFEST_COUNT=$((MANIFEST_COUNT + 1))
done < "$MANIFEST"
echo "📋 Manifest-driven copy: $MANIFEST_COUNT files → dist/runtime/scripts/"

# 5b. runtime/server/ — 模块化 TS server 复制
if [ -d "$PLUGIN_ROOT/runtime/server/src" ] && [ -f "$PLUGIN_ROOT/runtime/server/autopilot-server.ts" ]; then
  mkdir -p "$DIST_DIR/runtime/server/src"
  cp "$PLUGIN_ROOT/runtime/server/autopilot-server.ts" "$DIST_DIR/runtime/server/"
  find "$PLUGIN_ROOT/runtime/server/src" -name '*.ts' -type f | while read -r tsfile; do
    rel="${tsfile#"$PLUGIN_ROOT/runtime/server/src/"}"
    mkdir -p "$DIST_DIR/runtime/server/src/$(dirname "$rel")"
    cp "$tsfile" "$DIST_DIR/runtime/server/src/$rel"
  done
  SERVER_MODULE_COUNT=$(find "$DIST_DIR/runtime/server/src" -name '*.ts' -type f | wc -l | xargs)
  echo "📋 Server modules: $SERVER_MODULE_COUNT files → dist/runtime/server/src/"
fi

# 6. CLAUDE.md — 裁剪 dev-only 段落
sed '/<!-- DEV-ONLY-BEGIN -->/,/<!-- DEV-ONLY-END -->/d' \
  "$PLUGIN_ROOT/CLAUDE.md" > "$DIST_DIR/CLAUDE.md"

# 7. 校验: hooks.json 引用的脚本都存在于 dist
MISSING=0
for script in $(grep -o 'runtime/scripts/[^" ]*\.sh' "$DIST_DIR/hooks/hooks.json" | sed 's|runtime/scripts/||'); do
  if [ ! -f "$DIST_DIR/runtime/scripts/$script" ]; then
    echo "ERROR: hooks.json references runtime/scripts/$script but it's missing from dist"
    MISSING=1
  fi
done
[ "$MISSING" -eq 1 ] && exit 1

# 7b. 校验: hooks.json 引用的脚本都在 manifest 中
for script in $(grep -o 'runtime/scripts/[^" ]*\.sh' "$DIST_DIR/hooks/hooks.json" | sed 's|runtime/scripts/||'); do
  if ! grep -qxF "$script" <(sed 's/#.*//' "$MANIFEST" | xargs -n1 2>/dev/null); then
    echo "ERROR: hooks.json references runtime/scripts/$script but it's NOT in manifest"
    MISSING=1
  fi
done
[ "$MISSING" -eq 1 ] && exit 1

# 7c. 校验: dist/runtime/scripts/ 中不存在清单外文件
LEAKED=0
for f in "$DIST_DIR/runtime/scripts/"*; do
  [ -f "$f" ] || continue
  fname=$(basename "$f")
  if ! grep -qxF "$fname" <(sed 's/#.*//' "$MANIFEST" | xargs -n1 2>/dev/null); then
    echo "ERROR: dist/runtime/scripts/ contains file not in manifest: $fname"
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

# 9. 隔离验证 — 旧路径不应存在
for forbidden in "gui" "gui-dist" "docs" "tests" "CHANGELOG.md" "README.md" "scripts" "server" "runtime/scripts/node_modules" "runtime/server/node_modules" "runtime/server/bun.lock" "runtime/server/tsconfig.json" "runtime/server/package.json"; do
  if [ -e "$DIST_DIR/$forbidden" ]; then
    echo "ERROR: dist contains forbidden path: $forbidden"
    exit 1
  fi
done

# 9b. runtime/server 模块化结构校验
if [ -d "$DIST_DIR/runtime/server/src" ]; then
  if [ ! -f "$DIST_DIR/runtime/server/autopilot-server.ts" ]; then
    echo "ERROR: dist/runtime/server/autopilot-server.ts missing"
    exit 1
  fi
  if [ ! -f "$DIST_DIR/runtime/server/src/bootstrap.ts" ]; then
    echo "ERROR: dist/runtime/server/src/bootstrap.ts missing"
    exit 1
  fi
  DIST_SERVER_MODULES=$(find "$DIST_DIR/runtime/server/src" -name '*.ts' -type f | wc -l | xargs)
  if [ "$DIST_SERVER_MODULES" -lt 10 ]; then
    echo "ERROR: dist/runtime/server/src/ has too few modules ($DIST_SERVER_MODULES, expected >= 10)"
    exit 1
  fi
  echo "📋 Server structure validated: $DIST_SERVER_MODULES modules in dist/runtime/server/src/"
fi

# 9c. assets/gui 产物验证
if [ ! -f "$DIST_DIR/assets/gui/index.html" ]; then
  echo "ERROR: dist/assets/gui/index.html missing"
  exit 1
fi

# 10. 大小对比
SRC_SIZE=$(du -sh "$PLUGIN_ROOT" | cut -f1)
DIST_SIZE=$(du -sh "$DIST_DIR" | cut -f1)
echo "✅ dist/$PLUGIN_NAME built: $DIST_SIZE (source: $SRC_SIZE)"

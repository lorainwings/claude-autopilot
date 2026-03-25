#!/usr/bin/env bash
# tools/release.sh — 统一发版脚本（两个插件通用）
#
# 用法: bash tools/release.sh <patch|minor|major> <spec-autopilot|parallel-harness>
#
# 步骤:
#   1. 读取当前版本 → 计算新版本
#   2. 更新所有版本文件 (plugin.json / package.json / marketplace.json / README badge)
#   3. CHANGELOG: [Unreleased] → [X.Y.Z] - DATE + 新建空 [Unreleased] 段
#   4. 重新构建 dist/
#   5. 打印操作摘要 + 后续 git 命令提示
#
# 脚本不执行 git commit / git tag，由开发者检查后手动完成。

set -euo pipefail

# ── 参数校验 ──────────────────────────────────────────────────────
BUMP_TYPE="${1:-}"
PLUGIN_NAME="${2:-}"

if [ -z "$BUMP_TYPE" ] || [ -z "$PLUGIN_NAME" ]; then
  echo "用法: $0 <patch|minor|major> <spec-autopilot|parallel-harness>"
  echo ""
  echo "示例:"
  echo "  bash tools/release.sh patch spec-autopilot"
  echo "  bash tools/release.sh minor parallel-harness"
  exit 1
fi

case "$BUMP_TYPE" in
  patch | minor | major) ;;
  *)
    echo "❌ 无效的 bump 类型: $BUMP_TYPE"
    echo "   必须是 patch | minor | major"
    exit 1
    ;;
esac

case "$PLUGIN_NAME" in
  spec-autopilot | parallel-harness) ;;
  *)
    echo "❌ 无效的插件名: $PLUGIN_NAME"
    echo "   必须是 spec-autopilot | parallel-harness"
    exit 1
    ;;
esac

# ── 路径解析 ──────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PLUGIN_ROOT="$REPO_ROOT/plugins/$PLUGIN_NAME"
MARKETPLACE_JSON="$REPO_ROOT/.claude-plugin/marketplace.json"

# ── 前置检查 ──────────────────────────────────────────────────────
if [ ! -d "$PLUGIN_ROOT" ]; then
  echo "❌ 插件目录不存在: $PLUGIN_ROOT"
  exit 1
fi

if ! command -v jq &>/dev/null; then
  echo "❌ jq 未安装。请执行: brew install jq"
  exit 1
fi

# Cross-platform in-place sed
sedi() {
  if sed --version 2>/dev/null | grep -q GNU; then
    sed -i "$@"
  else
    sed -i '' "$@"
  fi
}

# ── 读取当前版本 ──────────────────────────────────────────────────
if [ "$PLUGIN_NAME" = "spec-autopilot" ]; then
  VERSION_FILE="$PLUGIN_ROOT/.claude-plugin/plugin.json"
else
  VERSION_FILE="$PLUGIN_ROOT/package.json"
fi

if [ ! -f "$VERSION_FILE" ]; then
  echo "❌ 版本源文件不存在: $VERSION_FILE"
  exit 1
fi

CURRENT_VERSION=$(jq -r '.version' "$VERSION_FILE" 2>/dev/null)
if [ -z "$CURRENT_VERSION" ] || [ "$CURRENT_VERSION" = "null" ]; then
  echo "❌ 无法读取版本号: $VERSION_FILE"
  exit 1
fi

# ── 计算新版本 ────────────────────────────────────────────────────
BASE_VERSION="${CURRENT_VERSION%%-*}" # strip pre-release suffix
MAJOR=$(echo "$BASE_VERSION" | cut -d. -f1)
MINOR=$(echo "$BASE_VERSION" | cut -d. -f2)
PATCH=$(echo "$BASE_VERSION" | cut -d. -f3)

# 整数校验
for part in MAJOR MINOR PATCH; do
  val="${!part}"
  if ! [ "$val" -eq "$val" ] 2>/dev/null; then
    echo "❌ 无法解析版本号 '$CURRENT_VERSION' 中的 $part='$val'"
    exit 1
  fi
done

case "$BUMP_TYPE" in
  patch) NEW_VERSION="${MAJOR}.${MINOR}.$((PATCH + 1))" ;;
  minor) NEW_VERSION="${MAJOR}.$((MINOR + 1)).0" ;;
  major) NEW_VERSION="$((MAJOR + 1)).0.0" ;;
esac

echo "🔖 $PLUGIN_NAME: $CURRENT_VERSION → $NEW_VERSION ($BUMP_TYPE)"
echo ""

# ── [1/5] 更新版本源文件 ─────────────────────────────────────────
jq --arg v "$NEW_VERSION" '.version = $v' "$VERSION_FILE" > "${VERSION_FILE}.tmp" || {
  echo "❌ 更新 $VERSION_FILE 失败"
  exit 1
}
mv "${VERSION_FILE}.tmp" "$VERSION_FILE"
echo "  ✅ [1/5] $(basename "$VERSION_FILE") → $NEW_VERSION"

# parallel-harness 额外同步 .claude-plugin/plugin.json
if [ "$PLUGIN_NAME" = "parallel-harness" ]; then
  CLAUDE_PLUGIN_JSON="$PLUGIN_ROOT/.claude-plugin/plugin.json"
  if [ -f "$CLAUDE_PLUGIN_JSON" ]; then
    jq --arg v "$NEW_VERSION" '.version = $v' "$CLAUDE_PLUGIN_JSON" > "${CLAUDE_PLUGIN_JSON}.tmp" || {
      echo "❌ 更新 $CLAUDE_PLUGIN_JSON 失败"
      exit 1
    }
    mv "${CLAUDE_PLUGIN_JSON}.tmp" "$CLAUDE_PLUGIN_JSON"
    echo "         .claude-plugin/plugin.json → $NEW_VERSION"
  fi
fi

# ── [2/5] 同步 marketplace.json ──────────────────────────────────
if [ ! -f "$MARKETPLACE_JSON" ]; then
  echo "❌ marketplace.json 不存在: $MARKETPLACE_JSON"
  exit 1
fi

jq --arg v "$NEW_VERSION" --arg n "$PLUGIN_NAME" '
  .plugins = [.plugins[] | if .name == $n then .version = $v else . end]
' "$MARKETPLACE_JSON" > "${MARKETPLACE_JSON}.tmp" || {
  echo "❌ 更新 marketplace.json 失败"
  exit 1
}
mv "${MARKETPLACE_JSON}.tmp" "$MARKETPLACE_JSON"
echo "  ✅ [2/5] marketplace.json → $NEW_VERSION"

# ── [3/5] 同步 README.md badge ───────────────────────────────────
README_MD="$PLUGIN_ROOT/README.md"
if [ -f "$README_MD" ] && grep -q 'version-[0-9]' "$README_MD"; then
  sedi "s/version-[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\(--*[a-zA-Z0-9._-]*\)*-blue/version-${NEW_VERSION}-blue/" "$README_MD"
  echo "  ✅ [3/5] README.md badge → $NEW_VERSION"
else
  echo "  ⏭️  [3/5] README.md: 无版本 badge，跳过"
fi

# ── [4/5] CHANGELOG.md 处理 ──────────────────────────────────────
CHANGELOG_MD="$PLUGIN_ROOT/CHANGELOG.md"
TODAY=$(date +%Y-%m-%d)

if [ ! -f "$CHANGELOG_MD" ]; then
  echo "❌ CHANGELOG.md 不存在: $CHANGELOG_MD"
  exit 1
fi

if ! grep -q '## \[Unreleased\]' "$CHANGELOG_MD"; then
  echo "❌ CHANGELOG.md 中没有 ## [Unreleased] 段"
  echo "   请先在 ## [Unreleased] 下记录变更内容，再执行发版"
  exit 1
fi

# 检查 [Unreleased] 段是否有实质内容
UNRELEASED_CONTENT=$(awk '/^## \[Unreleased\]/{f=1;next} /^## \[[0-9]/{f=0} f && NF' "$CHANGELOG_MD")
if [ -z "$UNRELEASED_CONTENT" ]; then
  echo "❌ CHANGELOG.md 的 [Unreleased] 段为空"
  echo "   请先记录变更内容，再执行发版"
  exit 1
fi

# 替换 [Unreleased] → [X.Y.Z] - DATE
sedi "s/^## \[Unreleased\]/## [${NEW_VERSION}] - ${TODAY}/" "$CHANGELOG_MD"

# 在 # Changelog 后插入新的空 [Unreleased] 段
TMPFILE=$(mktemp)
awk 'NR==1{print; print ""; print "## [Unreleased]"; next}1' "$CHANGELOG_MD" > "$TMPFILE"
mv "$TMPFILE" "$CHANGELOG_MD"

echo "  ✅ [4/5] CHANGELOG: [Unreleased] → [$NEW_VERSION] - $TODAY + 新 [Unreleased] 段已添加"

# ── [5/5] 重新构建 dist ──────────────────────────────────────────
BUILD_SCRIPT="$PLUGIN_ROOT/tools/build-dist.sh"
if [ -f "$BUILD_SCRIPT" ]; then
  echo "  📦 [5/5] 重新构建 dist/..."
  if bash "$BUILD_SCRIPT"; then
    echo "  ✅ [5/5] dist 构建完成"
  else
    echo "❌ dist 构建失败"
    exit 1
  fi
else
  echo "  ⏭️  [5/5] 无 build-dist.sh，跳过"
fi

# ── 验证 ──────────────────────────────────────────────────────────
echo ""
echo "📋 版本验证:"

VERIFY_PASS=true
V_SOURCE=$(jq -r '.version' "$VERSION_FILE")
V_MARKET=$(jq -r --arg n "$PLUGIN_NAME" '.plugins[] | select(.name == $n) | .version' "$MARKETPLACE_JSON")

if [ "$V_SOURCE" = "$NEW_VERSION" ]; then
  echo "  ✅ $(basename "$VERSION_FILE"): $V_SOURCE"
else
  echo "  ❌ $(basename "$VERSION_FILE"): $V_SOURCE (期望 $NEW_VERSION)"
  VERIFY_PASS=false
fi

if [ "$V_MARKET" = "$NEW_VERSION" ]; then
  echo "  ✅ marketplace.json: $V_MARKET"
else
  echo "  ❌ marketplace.json: $V_MARKET (期望 $NEW_VERSION)"
  VERIFY_PASS=false
fi

if [ -f "$README_MD" ] && grep -q 'version-[0-9]' "$README_MD"; then
  V_README=$(grep -oE 'version-[0-9]+\.[0-9]+\.[0-9]+(--?[a-zA-Z0-9._-]*)*-blue' "$README_MD" | head -1 | sed 's/^version-//;s/-blue$//')
  if [ "$V_README" = "$NEW_VERSION" ]; then
    echo "  ✅ README.md badge: $V_README"
  else
    echo "  ❌ README.md badge: $V_README (期望 $NEW_VERSION)"
    VERIFY_PASS=false
  fi
fi

V_CL=$(grep -oE '^## \[[0-9]+\.[0-9]+\.[0-9]+' "$CHANGELOG_MD" | head -1 | sed 's/^## \[//')
if [ "$V_CL" = "$NEW_VERSION" ]; then
  echo "  ✅ CHANGELOG.md: $V_CL"
else
  echo "  ❌ CHANGELOG.md: $V_CL (期望 $NEW_VERSION)"
  VERIFY_PASS=false
fi

echo ""
if [ "$VERIFY_PASS" = true ]; then
  echo "✅ $PLUGIN_NAME v$NEW_VERSION 发版准备完成"
else
  echo "❌ 版本验证失败 — 部分文件未正确更新"
  exit 1
fi

# ── 后续操作提示 ──────────────────────────────────────────────────
echo ""
echo "后续操作:"
echo ""
echo "  git add plugins/$PLUGIN_NAME/ .claude-plugin/marketplace.json dist/$PLUGIN_NAME/"
echo "  git commit -m \"chore(release): $PLUGIN_NAME $NEW_VERSION\""
echo "  git tag \"$PLUGIN_NAME-v$NEW_VERSION\""
echo ""

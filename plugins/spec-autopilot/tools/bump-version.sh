#!/usr/bin/env bash
# bump-version.sh — 全局版本号确定性同步脚本
# 一键同步修改 plugin.json / marketplace.json / README.md / CHANGELOG.md
#
# Usage: bash tools/bump-version.sh <new_version>
# Example: bash tools/bump-version.sh 4.3.0
#
# 此脚本是版本升级的唯一合法入口。禁止人工或 AI 散弹式手动修改版本号。

set -euo pipefail

# --- Argument validation ---
NEW_VERSION="${1:-}"
if [ -z "$NEW_VERSION" ]; then
  echo "❌ Usage: $0 <new_version>"
  echo "   Example: $0 4.3.0"
  exit 1
fi

# Validate semver format (MAJOR.MINOR.PATCH, optional pre-release)
if ! echo "$NEW_VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?$'; then
  echo "❌ Invalid version format: $NEW_VERSION"
  echo "   Expected: MAJOR.MINOR.PATCH (e.g., 4.3.0 or 4.3.0-beta.1)"
  exit 1
fi

# --- Resolve paths ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_ROOT="$(cd "$PLUGIN_ROOT/../.." && pwd)"

PLUGIN_JSON="$PLUGIN_ROOT/.claude-plugin/plugin.json"
MARKETPLACE_JSON="$PROJECT_ROOT/.claude-plugin/marketplace.json"
README_MD="$PLUGIN_ROOT/README.md"
CHANGELOG_MD="$PLUGIN_ROOT/CHANGELOG.md"

# --- Pre-flight checks ---
MISSING=()
[ -f "$PLUGIN_JSON" ] || MISSING+=("plugin.json: $PLUGIN_JSON")
[ -f "$MARKETPLACE_JSON" ] || MISSING+=("marketplace.json: $MARKETPLACE_JSON")
[ -f "$README_MD" ] || MISSING+=("README.md: $README_MD")
[ -f "$CHANGELOG_MD" ] || MISSING+=("CHANGELOG.md: $CHANGELOG_MD")

if [ ${#MISSING[@]} -gt 0 ]; then
  echo "❌ Missing files:"
  printf "   - %s\n" "${MISSING[@]}"
  exit 1
fi

# Check jq availability
if ! command -v jq &>/dev/null; then
  echo "❌ jq is required but not found. Install: brew install jq"
  exit 1
fi

# Read current version from plugin.json (source of truth)
OLD_VERSION=$(jq -r '.version' "$PLUGIN_JSON")

# Check ALL files, not just plugin.json — other files may be out of sync
MKT_VERSION=$(jq -r '.plugins[] | select(.name == "spec-autopilot") | .version' "$MARKETPLACE_JSON")
README_VERSION=$(grep -oE 'version-[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?-blue' "$README_MD" | head -1 | sed 's/version-//;s/-blue//')
CL_VERSION=$(grep -oE '## \[[0-9]+\.[0-9]+\.[0-9]+' "$CHANGELOG_MD" | head -1 | sed 's/## \[//')

ALL_MATCH=true
for v in "$OLD_VERSION" "$MKT_VERSION" "$README_VERSION" "$CL_VERSION"; do
  [ "$v" != "$NEW_VERSION" ] && ALL_MATCH=false
done

if [ "$ALL_MATCH" = true ]; then
  echo "✅ All 4 files already at v$NEW_VERSION. No changes needed."
  exit 0
fi

echo "🔄 Bumping version: $OLD_VERSION → $NEW_VERSION"
echo ""

# --- 1. Update plugin.json ---
echo "  [1/4] plugin.json"
jq --arg v "$NEW_VERSION" '.version = $v' "$PLUGIN_JSON" > "$PLUGIN_JSON.tmp"
mv "$PLUGIN_JSON.tmp" "$PLUGIN_JSON"
echo "        ✅ version: $NEW_VERSION"

# --- 2. Update marketplace.json (cross-level, plugins array) ---
echo "  [2/4] marketplace.json"
# Find the spec-autopilot entry in plugins array and update its version
jq --arg v "$NEW_VERSION" '
  .plugins = [.plugins[] | if .name == "spec-autopilot" then .version = $v else . end]
' "$MARKETPLACE_JSON" > "$MARKETPLACE_JSON.tmp"
mv "$MARKETPLACE_JSON.tmp" "$MARKETPLACE_JSON"
echo "        ✅ plugins[spec-autopilot].version: $NEW_VERSION"

# --- 3. Update README.md version badge ---
echo "  [3/4] README.md"
# Pattern: version-X.Y.Z-blue (in shields.io badge URL)
sed -i '' "s|version-[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\(-[a-zA-Z0-9.]*\)\{0,1\}-blue|version-${NEW_VERSION}-blue|g" "$README_MD"
echo "        ✅ badge: version-${NEW_VERSION}-blue"

# --- 4. Insert CHANGELOG.md header ---
echo "  [4/4] CHANGELOG.md"
TODAY=$(date +%Y-%m-%d)
# Insert new version header after "# Changelog" line
HEADER="## [$NEW_VERSION] - $TODAY"
# Check if this version already exists in CHANGELOG
if grep -qF "## [$NEW_VERSION]" "$CHANGELOG_MD"; then
  echo "        ⚠️  Version $NEW_VERSION already exists in CHANGELOG.md, skipping insertion"
else
  # Insert after the first line (# Changelog)
  sed -i '' "2a\\
\\
${HEADER}\\
" "$CHANGELOG_MD"
  echo "        ✅ inserted: $HEADER"
fi

# --- Verification ---
echo ""
echo "📋 Verification:"

V1=$(jq -r '.version' "$PLUGIN_JSON")
V2=$(jq -r '.plugins[] | select(.name == "spec-autopilot") | .version' "$MARKETPLACE_JSON")
V3=$(grep -oE 'version-[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?-blue' "$README_MD" | head -1 | sed 's/version-//;s/-blue//')
V4_EXISTS=$(grep -c "## \[$NEW_VERSION\]" "$CHANGELOG_MD" || echo 0)
V4="$NEW_VERSION"
[ "$V4_EXISTS" -eq 0 ] && V4="missing"

PASS=true
for label_version in "plugin.json:$V1" "marketplace.json:$V2" "README.md:$V3" "CHANGELOG.md:$V4"; do
  label="${label_version%%:*}"
  version="${label_version#*:}"
  if [ "$version" = "$NEW_VERSION" ]; then
    echo "  ✅ $label: $version"
  else
    echo "  ❌ $label: $version (expected $NEW_VERSION)"
    PASS=false
  fi
done

echo ""
if [ "$PASS" = true ]; then
  echo "✅ All 4 files synchronized to v$NEW_VERSION"
else
  echo "❌ Verification FAILED — some files were not updated correctly"
  exit 1
fi

# 重新构建 dist 以同步版本号
echo ""
echo "📦 Rebuilding dist/plugin/..."
bash "$SCRIPT_DIR/build-dist.sh"

#!/usr/bin/env bash
# check-release-discipline.sh
# CI guard for release metadata discipline when plugin files change.
#
# Usage:
#   bash scripts/check-release-discipline.sh <base_ref> <head_ref> [plugin_filter]
#
# plugin_filter: spec-autopilot | parallel-harness | all (default)
# Checks the specified plugin(s).
# Fails when:
#   1. files under plugins/<plugin>/ changed but CHANGELOG / CHANGELOG-equivalent did not
#   2. files under plugins/<plugin>/ changed but plugin version did not bump
#   3. version metadata is out of sync across plugin.json / marketplace / README

set -euo pipefail

BASE_REF="${1:-}"
HEAD_REF="${2:-HEAD}"
PLUGIN_FILTER="${3:-all}"

case "$PLUGIN_FILTER" in
  spec-autopilot|parallel-harness|all) ;;
  *)
    echo "❌ Invalid plugin_filter: '$PLUGIN_FILTER'. Must be spec-autopilot | parallel-harness | all"
    exit 1
    ;;
esac

if [ -z "$BASE_REF" ]; then
  echo "❌ Usage: $0 <base_ref> <head_ref>"
  exit 1
fi

# ── release-please bot bypass ──
# Skip checks for commits made by release-please (github-actions bot or "chore(main): release" message)
# Check both HEAD and the commit range to handle merge commits that include release commits
HEAD_AUTHOR=$(git log -1 --format='%an' "$HEAD_REF" 2>/dev/null || true)
HEAD_MESSAGE=$(git log -1 --format='%s' "$HEAD_REF" 2>/dev/null || true)
if [[ "$HEAD_AUTHOR" == *"github-actions"* ]] || [[ "$HEAD_MESSAGE" == "chore(main): release"* ]] || [[ "$HEAD_MESSAGE" == "chore: release main"* ]]; then
  echo "ℹ️  release-please bot commit detected — skipping discipline check"
  exit 0
fi

# Check if any commit in the range is a release-please commit (handles merge commits)
if git log --format='%s' "$BASE_REF..$HEAD_REF" 2>/dev/null | grep -qE '^(chore\(main\): release|chore: release main)'; then
  echo "ℹ️  release-please commit in range — skipping discipline check"
  exit 0
fi

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
if [ -z "$REPO_ROOT" ]; then
  echo "❌ Error: not inside a git repository."
  exit 1
fi

cd "$REPO_ROOT"

MARKETPLACE_JSON=".claude-plugin/marketplace.json"

if ! command -v jq >/dev/null 2>&1; then
  echo "❌ Error: jq is required for release-discipline check."
  exit 1
fi

if ! git rev-parse --verify "$BASE_REF^{commit}" >/dev/null 2>&1; then
  echo "❌ Error: base ref '$BASE_REF' is not a valid commit."
  exit 1
fi

if ! git rev-parse --verify "$HEAD_REF^{commit}" >/dev/null 2>&1; then
  echo "❌ Error: head ref '$HEAD_REF' is not a valid commit."
  exit 1
fi

OVERALL_FAIL=0

# ── check_plugin <plugin_root> <marketplace_name> <version_source>
# version_source: "plugin_json" (reads .claude-plugin/plugin.json)
#                 "package_json" (reads package.json)
check_plugin() {
  local PLUGIN_ROOT="$1"
  local MARKETPLACE_NAME="$2"
  local VERSION_SOURCE="${3:-plugin_json}"

  local CHANGED_FILES
  # 使用 merge-base 三点语义：只比较本分支相对分叉点的改动，不把 base 分支后续提交算进来
  local MERGE_BASE
  MERGE_BASE="$(git merge-base "$BASE_REF" "$HEAD_REF" 2>/dev/null || echo "$BASE_REF")"
  CHANGED_FILES="$(git diff --name-only "$MERGE_BASE" "$HEAD_REF" -- "$PLUGIN_ROOT" || true)"

  if [ -z "$CHANGED_FILES" ]; then
    echo "✅ No $PLUGIN_ROOT changes between $BASE_REF and $HEAD_REF"
    return 0
  fi

  echo "🔎 $PLUGIN_ROOT changes detected between $BASE_REF and $HEAD_REF"

  # Determine version files
  local PLUGIN_JSON README_MD CHANGELOG_MD
  if [ "$VERSION_SOURCE" = "package_json" ]; then
    PLUGIN_JSON="$PLUGIN_ROOT/package.json"
  else
    PLUGIN_JSON="$PLUGIN_ROOT/.claude-plugin/plugin.json"
  fi
  README_MD="$PLUGIN_ROOT/README.md"
  CHANGELOG_MD="$PLUGIN_ROOT/CHANGELOG.md"

  # Metadata-only check: if ALL changed files are version/release metadata or docs,
  # this is a version-sync or docs-only commit and should not require CHANGELOG + bump again.
  # Metadata files: CHANGELOG.md, plugin.json, package.json, README.md, CLAUDE.md, docs/, reports/, dist/
  local SUBSTANTIVE_FILES
  SUBSTANTIVE_FILES=$(echo "$CHANGED_FILES" | grep -v -E "^(${CHANGELOG_MD}|${PLUGIN_JSON}|${PLUGIN_ROOT}/\.claude-plugin/plugin\.json|${PLUGIN_ROOT}/package\.json|${README_MD}|${PLUGIN_ROOT}/README\.zh\.md|${PLUGIN_ROOT}/CLAUDE\.md|\.claude-plugin/marketplace\.json|${PLUGIN_ROOT}/docs/|${PLUGIN_ROOT}/reports/|dist/).*$" || true)
  if [ -z "$SUBSTANTIVE_FILES" ]; then
    echo "✅ $PLUGIN_ROOT changes are metadata/docs-only — skipping discipline check"
    return 0
  fi

  # CHANGELOG check — info-only (release-please manages changelogs automatically)
  if [ -f "$CHANGELOG_MD" ]; then
    if ! echo "$CHANGED_FILES" | grep -qx "$CHANGELOG_MD"; then
      echo "ℹ️  $CHANGELOG_MD not updated (release-please will handle this)"
    fi
  fi

  # Version bump check
  local BASE_VERSION HEAD_VERSION HEAD_MARKETPLACE_VERSION
  local NEW_PLUGIN=0
  if ! git show "$BASE_REF:$PLUGIN_JSON" >/dev/null 2>&1; then
    echo "ℹ️  $PLUGIN_JSON not found in base ref — new plugin, skipping version bump check"
    NEW_PLUGIN=1
  fi

  if [ "$VERSION_SOURCE" = "package_json" ]; then
    HEAD_VERSION="$(jq -r '.version' "$PLUGIN_JSON")"
  else
    HEAD_VERSION="$(jq -r '.version' "$PLUGIN_JSON")"
  fi

  # Always verify marketplace entry exists and version matches
  HEAD_MARKETPLACE_VERSION="$(jq -r --arg name "$MARKETPLACE_NAME" '.plugins[] | select(.name == $name) | .version // empty' "$MARKETPLACE_JSON")"
  if [ -z "$HEAD_MARKETPLACE_VERSION" ]; then
    echo "❌ Error: $MARKETPLACE_NAME not found in $MARKETPLACE_JSON."
    echo "   Add an entry with source ./dist/$MARKETPLACE_NAME and version $HEAD_VERSION"
    OVERALL_FAIL=1
    return 0
  fi

  if [ "$NEW_PLUGIN" -eq 1 ]; then
    # New plugin: only check marketplace entry exists (already done above)
    if [ "$HEAD_VERSION" != "$HEAD_MARKETPLACE_VERSION" ]; then
      echo "❌ Error: $MARKETPLACE_NAME marketplace version mismatch (new plugin)."
      echo "   $PLUGIN_JSON:  $HEAD_VERSION"
      echo "   marketplace:   $HEAD_MARKETPLACE_VERSION"
      OVERALL_FAIL=1
    else
      echo "✅ $PLUGIN_ROOT new plugin marketplace entry OK (version $HEAD_VERSION)"
    fi
    return 0
  fi

  BASE_VERSION="$(git show "$BASE_REF:$PLUGIN_JSON" | jq -r '.version')"

  if [ "$BASE_VERSION" = "$HEAD_VERSION" ]; then
    # ── 开发提交: 版本未 bump ──
    # release-please 接管后，开发提交不再要求 [Unreleased] 有内容
    echo "ℹ️  $PLUGIN_ROOT: dev commit (no version bump) — OK"
    return 0
  fi

  # ── 发版提交: 版本已 bump — 执行完整发版纪律检查 ──
  echo "🔖 $PLUGIN_ROOT: release commit ($BASE_VERSION → $HEAD_VERSION)"

  local MISMATCH=0

  if [ "$HEAD_VERSION" != "$HEAD_MARKETPLACE_VERSION" ]; then
    echo "❌ Error: $MARKETPLACE_NAME marketplace version mismatch."
    echo "   $PLUGIN_JSON:  $HEAD_VERSION"
    echo "   marketplace:   $HEAD_MARKETPLACE_VERSION"
    MISMATCH=1
  fi

  # 交叉校验：当以 package.json 为版本源时，.claude-plugin/plugin.json 也必须同步
  if [ "$VERSION_SOURCE" = "package_json" ]; then
    local CLAUDE_PLUGIN_JSON="$PLUGIN_ROOT/.claude-plugin/plugin.json"
    if [ -f "$CLAUDE_PLUGIN_JSON" ]; then
      local CLAUDE_PLUGIN_VERSION
      CLAUDE_PLUGIN_VERSION="$(jq -r '.version' "$CLAUDE_PLUGIN_JSON")"
      if [ "$HEAD_VERSION" != "$CLAUDE_PLUGIN_VERSION" ]; then
        echo "❌ Error: $CLAUDE_PLUGIN_JSON version mismatch with $PLUGIN_JSON."
        echo "   package.json:           $HEAD_VERSION"
        echo "   .claude-plugin/plugin.json: $CLAUDE_PLUGIN_VERSION"
        MISMATCH=1
      fi
    fi
  fi

  # README badge check (optional — skip if badge not present)
  if [ -f "$README_MD" ]; then
    local HEAD_README_VERSION
    HEAD_README_VERSION="$(grep -oE 'version-[0-9]+\.[0-9]+\.[0-9]+(--?[a-zA-Z0-9._-]*)*-blue' "$README_MD" 2>/dev/null | head -1 | sed 's/^version-//;s/-blue$//' || true)"
    if [ -n "$HEAD_README_VERSION" ] && [ "$HEAD_VERSION" != "$HEAD_README_VERSION" ]; then
      echo "❌ Error: $PLUGIN_ROOT README badge version mismatch."
      echo "   $PLUGIN_JSON: $HEAD_VERSION"
      echo "   README.md:    $HEAD_README_VERSION"
      MISMATCH=1
    fi
  fi

  # CHANGELOG top version check (if CHANGELOG exists)
  if [ -f "$CHANGELOG_MD" ]; then
    # 发版提交: [Unreleased] 段应存在但为空（release.sh 新建空段）
    if grep -q '## \[Unreleased\]' "$CHANGELOG_MD"; then
      local UNRELEASED_CONTENT
      UNRELEASED_CONTENT=$(awk '/^## \[Unreleased\]/{f=1;next} /^## \[[0-9]/{f=0} f && NF' "$CHANGELOG_MD")
      if [ -n "$UNRELEASED_CONTENT" ]; then
        echo "❌ Error: $CHANGELOG_MD [Unreleased] section still has content after release."
        echo "   Use 'bash tools/release.sh <bump-type> $MARKETPLACE_NAME' to handle releases properly."
        MISMATCH=1
      fi
    else
      echo "❌ Error: $CHANGELOG_MD should have an empty [Unreleased] section after release."
      echo "   Use 'bash tools/release.sh <bump-type> $MARKETPLACE_NAME' to handle releases properly."
      MISMATCH=1
    fi

    local HEAD_CHANGELOG_VERSION
    HEAD_CHANGELOG_VERSION="$(grep -oE '^## \[[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?\]' "$CHANGELOG_MD" 2>/dev/null | head -1 | sed 's/^## \[//;s/\]$//' || true)"
    if [ -n "$HEAD_CHANGELOG_VERSION" ] && [ "$HEAD_VERSION" != "$HEAD_CHANGELOG_VERSION" ]; then
      echo "❌ Error: $PLUGIN_ROOT CHANGELOG top version mismatch."
      echo "   $PLUGIN_JSON: $HEAD_VERSION"
      echo "   CHANGELOG.md: $HEAD_CHANGELOG_VERSION"
      MISMATCH=1
    fi
  fi

  if [ "$MISMATCH" -eq 1 ]; then
    OVERALL_FAIL=1
    return 0
  fi

  echo "✅ $PLUGIN_ROOT release discipline OK: $BASE_VERSION -> $HEAD_VERSION"
}

if [ "$PLUGIN_FILTER" = "all" ] || [ "$PLUGIN_FILTER" = "spec-autopilot" ]; then
  check_plugin "plugins/spec-autopilot" "spec-autopilot" "plugin_json"
fi
if [ "$PLUGIN_FILTER" = "all" ] || [ "$PLUGIN_FILTER" = "parallel-harness" ]; then
  check_plugin "plugins/parallel-harness" "parallel-harness" "package_json"
fi

if [ "$OVERALL_FAIL" -eq 1 ]; then
  exit 1
fi

echo "✅ All release discipline checks passed"

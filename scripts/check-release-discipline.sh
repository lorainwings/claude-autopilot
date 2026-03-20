#!/usr/bin/env bash
# check-release-discipline.sh
# CI guard for release metadata discipline when spec-autopilot changes.
#
# Usage:
#   bash scripts/check-release-discipline.sh <base_ref> <head_ref>
#
# Fails when:
#   1. files under plugins/spec-autopilot/ changed but CHANGELOG.md did not
#   2. files under plugins/spec-autopilot/ changed but plugin version did not bump
#   3. version metadata is out of sync across plugin.json / marketplace / README / CHANGELOG

set -euo pipefail

BASE_REF="${1:-}"
HEAD_REF="${2:-HEAD}"

if [ -z "$BASE_REF" ]; then
  echo "❌ Usage: $0 <base_ref> <head_ref>"
  exit 1
fi

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
if [ -z "$REPO_ROOT" ]; then
  echo "❌ Error: not inside a git repository."
  exit 1
fi

cd "$REPO_ROOT"

PLUGIN_ROOT="plugins/spec-autopilot"
PLUGIN_JSON="$PLUGIN_ROOT/.claude-plugin/plugin.json"
README_MD="$PLUGIN_ROOT/README.md"
CHANGELOG_MD="$PLUGIN_ROOT/CHANGELOG.md"
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

CHANGED_FILES="$(git diff --name-only "$BASE_REF" "$HEAD_REF" -- "$PLUGIN_ROOT" || true)"

if [ -z "$CHANGED_FILES" ]; then
  echo "✅ No spec-autopilot changes between $BASE_REF and $HEAD_REF"
  exit 0
fi

echo "🔎 spec-autopilot changes detected between $BASE_REF and $HEAD_REF"

if ! echo "$CHANGED_FILES" | grep -qx "$CHANGELOG_MD"; then
  echo "❌ Error: $CHANGELOG_MD must be updated when $PLUGIN_ROOT changes."
  exit 1
fi

BASE_PLUGIN_VERSION="$(git show "$BASE_REF:$PLUGIN_JSON" | jq -r '.version')"
HEAD_PLUGIN_VERSION="$(jq -r '.version' "$PLUGIN_JSON")"
HEAD_MARKETPLACE_VERSION="$(jq -r '.plugins[] | select(.name == "spec-autopilot") | .version' "$MARKETPLACE_JSON")"
HEAD_README_VERSION="$(grep -oE 'version-[0-9]+\.[0-9]+\.[0-9]+(--?[a-zA-Z0-9._-]*)*-blue' "$README_MD" | head -1 | sed 's/^version-//;s/-blue$//')"
HEAD_CHANGELOG_VERSION="$(grep -oE '^## \[[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?\]' "$CHANGELOG_MD" | head -1 | sed 's/^## \[//;s/\]$//')"

if [ "$BASE_PLUGIN_VERSION" = "$HEAD_PLUGIN_VERSION" ]; then
  echo "❌ Error: plugin version was not bumped."
  echo "   base: $BASE_PLUGIN_VERSION"
  echo "   head: $HEAD_PLUGIN_VERSION"
  exit 1
fi

MISMATCH=0

if [ "$HEAD_PLUGIN_VERSION" != "$HEAD_MARKETPLACE_VERSION" ]; then
  echo "❌ Error: marketplace version mismatch."
  echo "   plugin.json:    $HEAD_PLUGIN_VERSION"
  echo "   marketplace:    $HEAD_MARKETPLACE_VERSION"
  MISMATCH=1
fi

if [ "$HEAD_PLUGIN_VERSION" != "$HEAD_README_VERSION" ]; then
  echo "❌ Error: README badge version mismatch."
  echo "   plugin.json:    $HEAD_PLUGIN_VERSION"
  echo "   README.md:      $HEAD_README_VERSION"
  MISMATCH=1
fi

if [ "$HEAD_PLUGIN_VERSION" != "$HEAD_CHANGELOG_VERSION" ]; then
  echo "❌ Error: CHANGELOG top version mismatch."
  echo "   plugin.json:    $HEAD_PLUGIN_VERSION"
  echo "   CHANGELOG.md:   $HEAD_CHANGELOG_VERSION"
  MISMATCH=1
fi

if [ "$MISMATCH" -eq 1 ]; then
  exit 1
fi

echo "✅ Release discipline check passed"
echo "   bumped: $BASE_PLUGIN_VERSION -> $HEAD_PLUGIN_VERSION"

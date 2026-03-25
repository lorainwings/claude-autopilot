#!/usr/bin/env bash
# test_release_discipline_ci.sh — Regression tests for CI release discipline guard
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$TEST_DIR/.." && pwd)"
REPO_ROOT="$(cd "$PLUGIN_ROOT/../.." && pwd)"
source "$TEST_DIR/_test_helpers.sh"

CHECK_SCRIPT="$REPO_ROOT/scripts/check-release-discipline.sh"

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not found"
  exit 0
fi

TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT

seed_repo() {
  local repo="$1"
  mkdir -p "$repo/plugins/spec-autopilot/.claude-plugin"
  mkdir -p "$repo/plugins/spec-autopilot"
  mkdir -p "$repo/.claude-plugin"

  cat > "$repo/plugins/spec-autopilot/.claude-plugin/plugin.json" << 'JSON'
{"version":"1.0.0"}
JSON

  cat > "$repo/.claude-plugin/marketplace.json" << 'JSON'
{
  "plugins": [
    {"name": "spec-autopilot", "version": "1.0.0"}
  ]
}
JSON

  cat > "$repo/plugins/spec-autopilot/README.md" << 'MD'
![](https://img.shields.io/badge/version-1.0.0-blue)
MD

  cat > "$repo/plugins/spec-autopilot/CHANGELOG.md" << 'MD'
# Changelog

## [1.0.0] - 2026-03-20

### Added
- init
MD
}

echo "--- release discipline CI guard ---"

# 1. Plugin changed without changelog/version bump -> fail
FAIL_REPO="$TMP_ROOT/fail-repo"
git -C "$TMP_ROOT" init -q "$FAIL_REPO"
seed_repo "$FAIL_REPO"
git -C "$FAIL_REPO" add -A
git -C "$FAIL_REPO" -c user.name="Test" -c user.email="test@test.com" commit -q -m "initial"
BASE_FAIL="$(git -C "$FAIL_REPO" rev-parse HEAD)"

echo "// new code" > "$FAIL_REPO/plugins/spec-autopilot/app.ts"
git -C "$FAIL_REPO" add "$FAIL_REPO/plugins/spec-autopilot/app.ts"
git -C "$FAIL_REPO" -c user.name="Test" -c user.email="test@test.com" commit -q -m "feat: code without release metadata"
HEAD_FAIL="$(git -C "$FAIL_REPO" rev-parse HEAD)"

fail_exit=0
fail_output=$(cd "$FAIL_REPO" && bash "$CHECK_SCRIPT" "$BASE_FAIL" "$HEAD_FAIL" 2>&1) || fail_exit=$?
[ "$fail_exit" -ne 0 ]
assert_exit "1a. missing changelog/version bump is rejected" 0 $?
assert_contains "1b. failure points to CHANGELOG update" "$fail_output" "CHANGELOG.md must be updated"

# 2. Plugin changed with synced version/changelog -> pass
PASS_REPO="$TMP_ROOT/pass-repo"
git -C "$TMP_ROOT" init -q "$PASS_REPO"
seed_repo "$PASS_REPO"
git -C "$PASS_REPO" add -A
git -C "$PASS_REPO" -c user.name="Test" -c user.email="test@test.com" commit -q -m "initial"
BASE_PASS="$(git -C "$PASS_REPO" rev-parse HEAD)"

echo "// new code" > "$PASS_REPO/plugins/spec-autopilot/app.ts"
cat > "$PASS_REPO/plugins/spec-autopilot/.claude-plugin/plugin.json" << 'JSON'
{"version":"1.0.1"}
JSON
cat > "$PASS_REPO/.claude-plugin/marketplace.json" << 'JSON'
{
  "plugins": [
    {"name": "spec-autopilot", "version": "1.0.1"}
  ]
}
JSON
cat > "$PASS_REPO/plugins/spec-autopilot/README.md" << 'MD'
![](https://img.shields.io/badge/version-1.0.1-blue)
MD
cat > "$PASS_REPO/plugins/spec-autopilot/CHANGELOG.md" << 'MD'
# Changelog

## [Unreleased]

## [1.0.1] - 2026-03-21

### Added
- new feature

## [1.0.0] - 2026-03-20

### Added
- init
MD
git -C "$PASS_REPO" add -A
git -C "$PASS_REPO" -c user.name="Test" -c user.email="test@test.com" commit -q -m "feat: code with release metadata"
HEAD_PASS="$(git -C "$PASS_REPO" rev-parse HEAD)"

pass_exit=0
pass_output=$(cd "$PASS_REPO" && bash "$CHECK_SCRIPT" "$BASE_PASS" "$HEAD_PASS" 2>&1) || pass_exit=$?
assert_exit "2a. synced release metadata passes" 0 $pass_exit
assert_contains "2b. success output emitted" "$pass_output" "All release discipline checks passed"

# ── parallel-harness: 双版本源失配场景 ──────────────────────────

seed_ph_repo() {
  local repo="$1"
  mkdir -p "$repo/plugins/parallel-harness/.claude-plugin"
  mkdir -p "$repo/plugins/parallel-harness"
  mkdir -p "$repo/.claude-plugin"

  cat > "$repo/plugins/parallel-harness/package.json" << 'JSON'
{"version":"1.0.0"}
JSON

  cat > "$repo/plugins/parallel-harness/.claude-plugin/plugin.json" << 'JSON'
{"version":"1.0.0"}
JSON

  cat > "$repo/.claude-plugin/marketplace.json" << 'JSON'
{
  "plugins": [
    {"name": "parallel-harness", "version": "1.0.0"}
  ]
}
JSON
}

# 3. package.json 升版但 .claude-plugin/plugin.json 未同步 → fail
MISMATCH_REPO="$TMP_ROOT/ph-mismatch-repo"
git -C "$TMP_ROOT" init -q "$MISMATCH_REPO"
seed_ph_repo "$MISMATCH_REPO"
git -C "$MISMATCH_REPO" add -A
git -C "$MISMATCH_REPO" -c user.name="Test" -c user.email="test@test.com" commit -q -m "initial"
BASE_MISMATCH="$(git -C "$MISMATCH_REPO" rev-parse HEAD)"

echo "// new code" > "$MISMATCH_REPO/plugins/parallel-harness/app.ts"
# 只升 package.json，漏改 plugin.json
cat > "$MISMATCH_REPO/plugins/parallel-harness/package.json" << 'JSON'
{"version":"1.1.0"}
JSON
cat > "$MISMATCH_REPO/.claude-plugin/marketplace.json" << 'JSON'
{
  "plugins": [
    {"name": "parallel-harness", "version": "1.1.0"}
  ]
}
JSON
git -C "$MISMATCH_REPO" add -A
git -C "$MISMATCH_REPO" -c user.name="Test" -c user.email="test@test.com" commit -q -m "feat: bump package.json only"
HEAD_MISMATCH="$(git -C "$MISMATCH_REPO" rev-parse HEAD)"

mismatch_exit=0
mismatch_output=$(cd "$MISMATCH_REPO" && bash "$CHECK_SCRIPT" "$BASE_MISMATCH" "$HEAD_MISMATCH" 2>&1) || mismatch_exit=$?
[ "$mismatch_exit" -ne 0 ]
assert_exit "3a. ph package.json/plugin.json mismatch is rejected" 0 $?
assert_contains "3b. failure mentions plugin.json mismatch" "$mismatch_output" ".claude-plugin/plugin.json version mismatch"

# 4. package.json + plugin.json + marketplace 全部同步 → pass
SYNC_REPO="$TMP_ROOT/ph-sync-repo"
git -C "$TMP_ROOT" init -q "$SYNC_REPO"
seed_ph_repo "$SYNC_REPO"
git -C "$SYNC_REPO" add -A
git -C "$SYNC_REPO" -c user.name="Test" -c user.email="test@test.com" commit -q -m "initial"
BASE_SYNC="$(git -C "$SYNC_REPO" rev-parse HEAD)"

echo "// new code" > "$SYNC_REPO/plugins/parallel-harness/app.ts"
cat > "$SYNC_REPO/plugins/parallel-harness/package.json" << 'JSON'
{"version":"1.1.0"}
JSON
cat > "$SYNC_REPO/plugins/parallel-harness/.claude-plugin/plugin.json" << 'JSON'
{"version":"1.1.0"}
JSON
cat > "$SYNC_REPO/.claude-plugin/marketplace.json" << 'JSON'
{
  "plugins": [
    {"name": "parallel-harness", "version": "1.1.0"}
  ]
}
JSON
git -C "$SYNC_REPO" add -A
git -C "$SYNC_REPO" -c user.name="Test" -c user.email="test@test.com" commit -q -m "feat: synced version bump"
HEAD_SYNC="$(git -C "$SYNC_REPO" rev-parse HEAD)"

sync_exit=0
sync_output=$(cd "$SYNC_REPO" && bash "$CHECK_SCRIPT" "$BASE_SYNC" "$HEAD_SYNC" 2>&1) || sync_exit=$?
assert_exit "4a. ph synced version bump passes" 0 $sync_exit
assert_contains "4b. success output emitted" "$sync_output" "All release discipline checks passed"

echo ""
echo "=== release-discipline-ci: $PASS passed, $FAIL failed ==="
[ "$FAIL" -gt 0 ] && exit 1
exit 0

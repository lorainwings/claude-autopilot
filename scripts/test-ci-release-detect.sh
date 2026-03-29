#!/usr/bin/env bash
# test-ci-release-detect.sh
# 回归测试: 验证 scripts/ci-detect-release-context.sh 在各种 CI 场景下的正确性
#
# 用法: bash scripts/test-ci-release-detect.sh
#
# 在临时 git 仓库中模拟各种 commit 场景，验证检测脚本的输出。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DETECT_SCRIPT="$SCRIPT_DIR/ci-detect-release-context.sh"
PASS=0
FAIL=0
TMPDIR=""

cleanup() {
  if [ -n "$TMPDIR" ] && [ -d "$TMPDIR" ]; then
    rm -rf "$TMPDIR"
  fi
}
trap cleanup EXIT

assert_check() {
  local desc="$1"
  local check_name="$2"
  local expected_exit="$3"
  shift 3
  local actual_exit=0
  bash "$DETECT_SCRIPT" --check="$check_name" "$@" >/dev/null 2>&1 || actual_exit=$?

  if [ "$actual_exit" -eq "$expected_exit" ]; then
    echo -e "  \033[32mPASS\033[0m: $desc"
    PASS=$((PASS + 1))
  else
    echo -e "  \033[31mFAIL\033[0m: $desc (expected exit=$expected_exit, got exit=$actual_exit)"
    FAIL=$((FAIL + 1))
  fi
}

assert_output_contains() {
  local desc="$1"
  local expected_key="$2"
  local expected_val="$3"
  shift 3
  local output
  output=$(bash "$DETECT_SCRIPT" "$@" 2>/dev/null || true)

  if echo "$output" | grep -q "^${expected_key}=${expected_val}$"; then
    echo -e "  \033[32mPASS\033[0m: $desc"
    PASS=$((PASS + 1))
  else
    echo -e "  \033[31mFAIL\033[0m: $desc (expected ${expected_key}=${expected_val})"
    echo "    actual output: $output"
    FAIL=$((FAIL + 1))
  fi
}

# ── Setup: 创建临时仓库 ──
TMPDIR=$(mktemp -d)
cd "$TMPDIR"
git init -q
git config user.name "test-user"
git config user.email "test@example.com"

# ── Scenario 1: 普通开发 commit ──
echo "--- Scenario 1: Normal dev commit ---"
echo "hello" > file.txt
git add file.txt
git commit -q -m "feat: add new feature"

BASE_REF=$(git rev-parse HEAD)
assert_check "normal commit: is_post_release_bot=false" is_post_release_bot 1
assert_check "normal commit: skip_dist_stale=false" skip_dist_stale 1
assert_output_contains "normal commit: IS_RELEASE_CONTEXT=false" IS_RELEASE_CONTEXT false

# ── Scenario 2: post-release bot commit ──
echo "--- Scenario 2: Post-release bot commit ---"
git config user.name "github-actions[bot]"
git config user.email "github-actions[bot]@users.noreply.github.com"
echo "v2" > file.txt
git add file.txt
git commit -q -m "chore: post-release update dist + README versions"

assert_check "post-release bot: is_post_release_bot=true" is_post_release_bot 0
assert_check "post-release bot: skip_dist_stale=true" skip_dist_stale 0
assert_output_contains "post-release bot: IS_POST_RELEASE_BOT=true" IS_POST_RELEASE_BOT true

# ── Scenario 3: release-please commit (非 bot author = 人工合并) ──
echo "--- Scenario 3: Release commit merged by human ---"
git config user.name "test-user"
git config user.email "test@example.com"
echo "v3" > file.txt
git add file.txt
git commit -q -m "chore(main): release spec-autopilot 5.3.0"

assert_check "human-merged release: is_post_release_bot=false" is_post_release_bot 1
assert_check "human-merged release: skip_dist_stale=true (message matches)" skip_dist_stale 0
assert_output_contains "human-merged release: IS_RELEASE_MESSAGE=true" IS_RELEASE_MESSAGE true
assert_output_contains "human-merged release: IS_BOT_AUTHOR=false" IS_BOT_AUTHOR false

# ── Scenario 4: commit range 包含 release commit ──
echo "--- Scenario 4: Release commit in range ---"
echo "v4" > file.txt
git add file.txt
git commit -q -m "feat: next feature after release"

HEAD_REF=$(git rev-parse HEAD)
assert_check "range with release: is_release_context=true" is_release_context 0 "$BASE_REF" "$HEAD_REF"

# ── Scenario 5: 纯开发 commit range ──
echo "--- Scenario 5: Pure dev commit range ---"
CLEAN_BASE=$(git rev-parse HEAD)
echo "v5" > file.txt
git add file.txt
git commit -q -m "fix: bug fix"
echo "v6" > file.txt
git add file.txt
git commit -q -m "refactor: cleanup"

CLEAN_HEAD=$(git rev-parse HEAD)
assert_check "dev-only range: is_release_context=false" is_release_context 1 "$CLEAN_BASE" "$CLEAN_HEAD"
assert_output_contains "dev-only range: IS_RELEASE_IN_RANGE=false" IS_RELEASE_IN_RANGE false "$CLEAN_BASE" "$CLEAN_HEAD"

# ── Scenario 6: bot release commit (author=bot AND message=release) ──
echo "--- Scenario 6: Bot release commit ---"
git config user.name "github-actions[bot]"
git config user.email "github-actions[bot]@users.noreply.github.com"
echo "v7" > file.txt
git add file.txt
git commit -q -m "chore: release main"

assert_check "bot release: is_post_release_bot=true" is_post_release_bot 0
assert_output_contains "bot release: IS_POST_RELEASE_BOT=true" IS_POST_RELEASE_BOT true

# ── 汇总 ──
echo ""
echo "=== ci-detect-release-context: $PASS passed, $FAIL failed ==="
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi

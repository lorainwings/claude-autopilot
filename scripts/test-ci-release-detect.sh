#!/usr/bin/env bash
# test-ci-release-detect.sh
# 回归测试: 验证 scripts/ci-detect-release-context.sh 在各种 CI 场景下的正确性
#
# 用法: bash scripts/test-ci-release-detect.sh

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
assert_output_contains "normal: SKIP_WHOLE_CI=false" SKIP_WHOLE_CI false
assert_output_contains "normal: SKIP_DIST_STALE=false" SKIP_DIST_STALE false
assert_output_contains "normal: IS_RELEASE_CONTEXT=false" IS_RELEASE_CONTEXT false
assert_output_contains "normal: IS_POST_RELEASE_BOT=false" IS_POST_RELEASE_BOT false

# ── Scenario 2: post-release bot commit ──
echo "--- Scenario 2: Post-release bot commit ---"
git config user.name "github-actions[bot]"
git config user.email "github-actions[bot]@users.noreply.github.com"
echo "v2" > file.txt
git add file.txt
git commit -q -m "chore: post-release update dist + README versions"

assert_output_contains "post-release bot: SKIP_WHOLE_CI=true" SKIP_WHOLE_CI true
assert_output_contains "post-release bot: SKIP_DIST_STALE=true" SKIP_DIST_STALE true
assert_output_contains "post-release bot: IS_POST_RELEASE_BOT=true" IS_POST_RELEASE_BOT true
assert_output_contains "post-release bot: IS_RELEASE_BOT=false" IS_RELEASE_BOT false

# ── Scenario 3: bot release commit (chore: release main) ──
# 关键断言: bot release != post-release, 不能跳过整套 CI
echo "--- Scenario 3: Bot release commit (NOT post-release) ---"
echo "v3" > file.txt
git add file.txt
git commit -q -m "chore: release main"

assert_output_contains "bot release: SKIP_WHOLE_CI=false (must NOT skip CI)" SKIP_WHOLE_CI false
assert_output_contains "bot release: SKIP_DIST_STALE=true" SKIP_DIST_STALE true
assert_output_contains "bot release: IS_RELEASE_BOT=true" IS_RELEASE_BOT true
assert_output_contains "bot release: IS_POST_RELEASE_BOT=false" IS_POST_RELEASE_BOT false

# ── Scenario 4: human-merged release commit ──
echo "--- Scenario 4: Release commit merged by human ---"
git config user.name "test-user"
git config user.email "test@example.com"
echo "v4" > file.txt
git add file.txt
git commit -q -m "chore(main): release spec-autopilot 5.3.0"

assert_output_contains "human release: SKIP_WHOLE_CI=false" SKIP_WHOLE_CI false
assert_output_contains "human release: SKIP_DIST_STALE=true" SKIP_DIST_STALE true
assert_output_contains "human release: IS_RELEASE_COMMIT_MESSAGE=true" IS_RELEASE_COMMIT_MESSAGE true
assert_output_contains "human release: IS_BOT_AUTHOR=false" IS_BOT_AUTHOR false

# ── Scenario 5: commit range 包含 release commit ──
echo "--- Scenario 5: Release commit in range ---"
echo "v5" > file.txt
git add file.txt
git commit -q -m "feat: next feature after release"

HEAD_REF=$(git rev-parse HEAD)
assert_output_contains "range with release: IS_RELEASE_IN_RANGE=true" IS_RELEASE_IN_RANGE true "$BASE_REF" "$HEAD_REF"
assert_output_contains "range with release: IS_RELEASE_CONTEXT=true" IS_RELEASE_CONTEXT true "$BASE_REF" "$HEAD_REF"
assert_output_contains "range with release: SKIP_DIST_STALE=true" SKIP_DIST_STALE true "$BASE_REF" "$HEAD_REF"

# ── Scenario 6: merge commit 场景 ──
# HEAD 是普通 merge commit 但 range 包含 release commit → skip_dist_stale=true
echo "--- Scenario 6: Merge commit with release in range ---"
MERGE_BASE=$(git rev-parse HEAD)
# 创建分支模拟 release PR
git checkout -q -b release-branch
echo "release-v" > file.txt
git add file.txt
git commit -q -m "chore(main): release parallel-harness 1.2.0"
git checkout -q -
# merge（非 fast-forward 生成 merge commit）
git merge -q --no-ff release-branch -m "Merge pull request #99 from release-please"
git branch -q -d release-branch

MERGE_HEAD=$(git rev-parse HEAD)
# HEAD 的 message 是 "Merge pull request..." 不是 release message
assert_output_contains "merge commit: IS_RELEASE_COMMIT_MESSAGE=false (HEAD is merge)" IS_RELEASE_COMMIT_MESSAGE false
assert_output_contains "merge commit: SKIP_WHOLE_CI=false" SKIP_WHOLE_CI false
# 但 range 包含 release commit
assert_output_contains "merge commit: IS_RELEASE_IN_RANGE=true" IS_RELEASE_IN_RANGE true "$MERGE_BASE" "$MERGE_HEAD"
assert_output_contains "merge commit: SKIP_DIST_STALE=true (range)" SKIP_DIST_STALE true "$MERGE_BASE" "$MERGE_HEAD"

# ── Scenario 7: 纯开发 commit range ──
echo "--- Scenario 7: Pure dev commit range ---"
CLEAN_BASE=$(git rev-parse HEAD)
echo "v7a" > file.txt
git add file.txt
git commit -q -m "fix: bug fix"
echo "v7b" > file.txt
git add file.txt
git commit -q -m "refactor: cleanup"

CLEAN_HEAD=$(git rev-parse HEAD)
assert_output_contains "dev-only range: IS_RELEASE_IN_RANGE=false" IS_RELEASE_IN_RANGE false "$CLEAN_BASE" "$CLEAN_HEAD"
assert_output_contains "dev-only range: SKIP_DIST_STALE=false" SKIP_DIST_STALE false "$CLEAN_BASE" "$CLEAN_HEAD"
assert_output_contains "dev-only range: SKIP_WHOLE_CI=false" SKIP_WHOLE_CI false "$CLEAN_BASE" "$CLEAN_HEAD"

# ── Scenario 8: author 含 "github-actions" 子串但非 bot → 不能误判 ──
echo "--- Scenario 8: Non-bot author with github-actions substring ---"
git config user.name "my-github-actions-helper"
git config user.email "helper@example.com"
echo "v8" > file.txt
git add file.txt
git commit -q -m "chore: post-release update dist"

assert_output_contains "non-bot author: IS_BOT_AUTHOR=false" IS_BOT_AUTHOR false
assert_output_contains "non-bot author: SKIP_WHOLE_CI=false" SKIP_WHOLE_CI false
assert_output_contains "non-bot author: IS_POST_RELEASE_BOT=false" IS_POST_RELEASE_BOT false

# ── Scenario 9: PR 事件 + release-please 分支（PR #118 复现）──
# GitHub PR 事件下 github.sha 是自动生成的 merge commit (message="Merge X into Y"),
# commit-message 与 range 检查均失效，必须靠分支名信号兜底
echo "--- Scenario 9: PR event on release-please branch (PR #118 regression) ---"
# 构造一个完全无 release 痕迹的 HEAD（普通 dev commit）模拟 GitHub merge commit
git config user.name "developer"
git config user.email "dev@example.com"
echo "v9" > file.txt
git add file.txt
git commit -q -m "Merge abc123 into def456"
MERGE_HEAD=$(git rev-parse HEAD)

# 不带分支名 → 不应跳过（仅靠 message/range 时的旧行为）
assert_check "PR baseline (no branch hint): SKIP_DIST_STALE=false" skip_dist_stale 1 "" "$MERGE_HEAD"

# 注入 release-please 分支名 → 必须跳过（新行为）
GITHUB_HEAD_REF=release-please--branches--main \
  bash "$DETECT_SCRIPT" --check=skip_dist_stale "" "$MERGE_HEAD" >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 0 ]; then
  echo -e "  \033[32mPASS\033[0m: PR on release-please branch: SKIP_DIST_STALE=true"
  PASS=$((PASS + 1))
else
  echo -e "  \033[31mFAIL\033[0m: PR on release-please branch: expected skip but got exit=$rc"
  FAIL=$((FAIL + 1))
fi

# 验证 IS_RELEASE_PLEASE_BRANCH 字段输出
out=$(GITHUB_HEAD_REF=release-please--branches--main bash "$DETECT_SCRIPT" 2>/dev/null || true)
if echo "$out" | grep -q "^IS_RELEASE_PLEASE_BRANCH=true$"; then
  echo -e "  \033[32mPASS\033[0m: GITHUB_HEAD_REF detected → IS_RELEASE_PLEASE_BRANCH=true"
  PASS=$((PASS + 1))
else
  echo -e "  \033[31mFAIL\033[0m: GITHUB_HEAD_REF detection failed"
  FAIL=$((FAIL + 1))
fi

# ── Scenario 10: push 直推 release-please 分支（GITHUB_REF_NAME 路径）──
echo "--- Scenario 10: push event on release-please branch ---"
out=$(GITHUB_HEAD_REF='' GITHUB_REF_NAME=release-please--branches--main bash "$DETECT_SCRIPT" 2>/dev/null || true)
if echo "$out" | grep -q "^IS_RELEASE_PLEASE_BRANCH=true$"; then
  echo -e "  \033[32mPASS\033[0m: GITHUB_REF_NAME detected → IS_RELEASE_PLEASE_BRANCH=true"
  PASS=$((PASS + 1))
else
  echo -e "  \033[31mFAIL\033[0m: GITHUB_REF_NAME detection failed"
  FAIL=$((FAIL + 1))
fi

# 普通分支不应误判
out=$(GITHUB_HEAD_REF='' GITHUB_REF_NAME=feature/foo bash "$DETECT_SCRIPT" 2>/dev/null || true)
if echo "$out" | grep -q "^IS_RELEASE_PLEASE_BRANCH=false$"; then
  echo -e "  \033[32mPASS\033[0m: regular branch → IS_RELEASE_PLEASE_BRANCH=false"
  PASS=$((PASS + 1))
else
  echo -e "  \033[31mFAIL\033[0m: regular branch incorrectly flagged"
  FAIL=$((FAIL + 1))
fi

# ── Scenario 11: 安全加固 — 人类伪造 release-please-* 分支名（actor 校验拦截）──
echo "--- Scenario 11: spoofed release-please branch by human (actor guard) ---"
# 人类用户在 CI 环境下伪造分支名 → actor 不是 bot → 不应跳过
out=$(GITHUB_HEAD_REF=release-please--evil GITHUB_ACTOR=evil-user bash "$DETECT_SCRIPT" 2>/dev/null || true)
if echo "$out" | grep -q "^IS_RELEASE_PLEASE_BRANCH=false$"; then
  echo -e "  \033[32mPASS\033[0m: spoofed branch + human actor → IS_RELEASE_PLEASE_BRANCH=false"
  PASS=$((PASS + 1))
else
  echo -e "  \033[31mFAIL\033[0m: spoofed branch was incorrectly accepted"
  FAIL=$((FAIL + 1))
fi

# 真正 release-please bot PR：分支名 + bot actor 双因子通过
out=$(GITHUB_HEAD_REF=release-please--branches--main GITHUB_ACTOR='github-actions[bot]' bash "$DETECT_SCRIPT" 2>/dev/null || true)
if echo "$out" | grep -q "^IS_RELEASE_PLEASE_BRANCH=true$"; then
  echo -e "  \033[32mPASS\033[0m: legit release-please bot PR → IS_RELEASE_PLEASE_BRANCH=true"
  PASS=$((PASS + 1))
else
  echo -e "  \033[31mFAIL\033[0m: legit release-please PR rejected"
  FAIL=$((FAIL + 1))
fi

# 本地测试场景（无 GITHUB_ACTOR）退化为只看分支名，便于开发自检
out=$(GITHUB_HEAD_REF=release-please--branches--main bash "$DETECT_SCRIPT" 2>/dev/null || true)
if echo "$out" | grep -q "^IS_RELEASE_PLEASE_BRANCH=true$"; then
  echo -e "  \033[32mPASS\033[0m: local test (no GITHUB_ACTOR) → degrades to branch-only check"
  PASS=$((PASS + 1))
else
  echo -e "  \033[31mFAIL\033[0m: local test fallback failed"
  FAIL=$((FAIL + 1))
fi

# ── Scenario 12: 人类 actor 重开 bot PR（PR #128 复现）──
# 真实场景：lorainwings 手动 close → reopen 一个 release-please bot PR，
# 此时 GITHUB_ACTOR=人类用户名，但分支 tip commit 仍由 bot 创建。
# 通过 origin/<branch> 的 tip commit 作者回退识别为合法 release-please 上下文。
echo "--- Scenario 12: human actor reopened bot release-please PR (PR #128 regression) ---"
git checkout -q -b release-please--branches--main 2>/dev/null || git checkout -q release-please--branches--main
git config user.name "github-actions[bot]"
git config user.email "github-actions[bot]@users.noreply.github.com"
echo "rp-bot-tip" > file.txt
git add file.txt
git commit -q -m "chore: release main"
# 模拟 origin/<branch> 远程引用（CI 环境 actions/checkout 会拉到 origin/<branch>）
git update-ref "refs/remotes/origin/release-please--branches--main" HEAD
git checkout -q -

out=$(GITHUB_HEAD_REF=release-please--branches--main GITHUB_ACTOR='lorainwings' \
      bash "$DETECT_SCRIPT" 2>/dev/null || true)
if echo "$out" | grep -q "^IS_RELEASE_PLEASE_BRANCH=true$"; then
  echo -e "  \033[32mPASS\033[0m: human reopened bot PR → IS_RELEASE_PLEASE_BRANCH=true (branch-tip fallback)"
  PASS=$((PASS + 1))
else
  echo -e "  \033[31mFAIL\033[0m: human reopened bot PR was incorrectly rejected"
  FAIL=$((FAIL + 1))
fi

# 反面：人类 actor + 分支 tip 也是人类提交 → 拒绝（防止人类完全伪造）
git checkout -q -b release-please--evil 2>/dev/null || git checkout -q release-please--evil
git config user.name "evil-user"
git config user.email "evil@example.com"
echo "evil-tip" > file.txt
git add file.txt
git commit -q -m "chore: release main"
git update-ref "refs/remotes/origin/release-please--evil" HEAD
git checkout -q -

out=$(GITHUB_HEAD_REF=release-please--evil GITHUB_ACTOR='evil-user' \
      bash "$DETECT_SCRIPT" 2>/dev/null || true)
if echo "$out" | grep -q "^IS_RELEASE_PLEASE_BRANCH=false$"; then
  echo -e "  \033[32mPASS\033[0m: human actor + human-authored branch tip → rejected"
  PASS=$((PASS + 1))
else
  echo -e "  \033[31mFAIL\033[0m: spoofed branch with human tip was incorrectly accepted"
  FAIL=$((FAIL + 1))
fi

# ── 汇总 ──
echo ""
echo "=== ci-detect-release-context: $PASS passed, $FAIL failed ==="
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi

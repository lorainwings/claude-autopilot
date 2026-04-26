#!/usr/bin/env bash
# ci-detect-release-context.sh
# 统一检测当前 CI 上下文是否属于 release / post-release 场景。
# 被 GitHub Actions workflow 和其他 CI 脚本共同调用，消除判断逻辑的重复与分歧。
#
# 用法:
#   bash scripts/ci-detect-release-context.sh [--check=<check_name>] [<base_ref> <head_ref>]
#
# 可选 check_name:
# 可选 check_name:
#   is_post_release_bot       — HEAD 是 bot 的 "chore: post-release ..." 提交
#   is_release_bot            — HEAD 是 bot 的 "chore: release ..." 或 "chore(main): release ..." 提交
#   is_release_please_branch  — 当前 ref 在 release-please--* 分支上（最稳定信号）
#   is_release_context        — HEAD 或 commit range 包含 release/post-release，或在 release-please 分支
#   skip_dist_stale           — 当前场景应跳过 dist staleness 检查
#
# 不带参数时输出所有检测结果的 KEY=VALUE 对（可 eval 使用）。
#
# 退出码:
#   --check 模式: 0 = 条件成立, 1 = 条件不成立
#   无参数模式: 始终 0（输出变量）
#
# ── 关键语义 ──
#
# SKIP_WHOLE_CI=true   — 仅 post-release bot 回写提交（bot + "chore: post-release ..."）
# SKIP_DIST_STALE=true — release 上下文均可跳过（release/post-release message, 或 range 含 release commit）
#
# 区分 release vs post-release:
#   "chore: release main" / "chore(main): release ..." → release commit（不跳过整套 CI）
#   "chore: post-release ..."                          → post-release 回写（跳过整套 CI）

set -euo pipefail

# ── 参数解析 ──
CHECK_NAME=""
BASE_REF=""
HEAD_REF="HEAD"
_positional_idx=0

for arg in "$@"; do
  case "$arg" in
    --check=*) CHECK_NAME="${arg#--check=}" ;;
    *)
      # 按位置赋值，空字串也消耗一个位置（避免空 BASE_REF 吞掉下一个 HEAD_REF）
      if [ "$_positional_idx" -eq 0 ]; then
        BASE_REF="$arg"
        _positional_idx=1
      elif [ "$_positional_idx" -eq 1 ]; then
        HEAD_REF="$arg"
        _positional_idx=2
      fi
      ;;
  esac
done

# ── 核心检测函数 ──

_is_bot_author() {
  local author
  author=$(git log -1 --format='%an' "$HEAD_REF" 2>/dev/null || echo "")
  # 精确匹配 GitHub Actions bot 身份，不使用模糊通配符
  [[ "$author" == "github-actions[bot]" ]]
}

# HEAD message 是 release commit（不含 post-release）
_is_release_commit_message() {
  local msg
  msg=$(git log -1 --format='%s' "$HEAD_REF" 2>/dev/null || echo "")
  # 匹配 "chore: release main" 或 "chore(main): release ..."
  # 不匹配 "chore: post-release ..."
  echo "$msg" | grep -qE '^chore(\(main\))?: release'
}

# HEAD message 是 post-release commit
_is_post_release_message() {
  local msg
  msg=$(git log -1 --format='%s' "$HEAD_REF" 2>/dev/null || echo "")
  echo "$msg" | grep -qE '^chore: post-release'
}

# HEAD message 是 release 或 post-release（广义 release message）
_is_any_release_message() {
  _is_release_commit_message || _is_post_release_message
}

# bot 创建的 release commit（如 release-please PR 合入 main 时的 bot commit）
_is_release_bot() {
  _is_bot_author && _is_release_commit_message
}

# bot 创建的 post-release 回写 commit（唯一允许跳过整套 CI 的场景）
_is_post_release_bot() {
  _is_bot_author && _is_post_release_message
}

# 当前 ref 是否为 release-please 创建的分支（最稳定的识别信号）
# - pull_request 事件：GITHUB_HEAD_REF=release-please--branches--main
# - push 事件：GITHUB_REF_NAME=release-please--branches--main
# 优先级最高：分支名由 release-please 强保证，比 commit message 更可靠
# （PR 事件下 github.sha 是 GitHub 自动生成的 merge commit，message 为 "Merge X into Y"
#  → _is_release_commit_message 失效；BASE_REF 又常为空 → _is_release_in_range 也失效。
#  分支名检查是唯一不会被这两种边界绕过的信号。）
#
# 安全加固：双因子识别 — 分支名 + (actor 或 分支 tip 提交者)。
# release-please 自动开 PR 时 GITHUB_ACTOR=github-actions[bot]；但人类协作者也可能
# 手动 close → reopen 一个 bot PR，此时 GITHUB_ACTOR 退化为人类用户名（PR opener）。
# 此时回退到第二信号：上游分支 tip 提交是否由 bot 创建 —— 人类无法在不窃取 bot token
# 的情况下伪造 bot 提交者身份，因此回退仍能阻止纯人类伪造的攻击场景。
# 仅当 GITHUB_ACTOR 未设置（如本地手动测试场景）时退化为只看分支名。
_is_release_please_branch() {
  local ref="${GITHUB_HEAD_REF:-${GITHUB_REF_NAME:-}}"
  [[ "$ref" == release-please--* ]] || return 1
  # 本地无 actor 时仅看分支名
  if [ -z "${GITHUB_ACTOR:-}" ]; then
    return 0
  fi
  # 主信号：actor 是 bot
  if [[ "$GITHUB_ACTOR" == "github-actions[bot]" ]]; then
    return 0
  fi
  # 回退信号：人类 actor 重开 bot PR — 校验上游分支 tip 是否由 bot 提交
  local branch_author
  branch_author=$(git log -1 --format='%an' "origin/${ref}" 2>/dev/null \
              || git log -1 --format='%an' "${ref}" 2>/dev/null \
              || echo "")
  [[ "$branch_author" == "github-actions[bot]" ]]
}

# commit range 中是否包含 release 或 post-release 提交（处理 merge commit 场景）
_is_release_in_range() {
  if [ -z "$BASE_REF" ]; then
    return 1
  fi
  if ! git rev-parse --verify "${BASE_REF}^{commit}" >/dev/null 2>&1; then
    return 1
  fi
  git log --format='%s' "${BASE_REF}..${HEAD_REF}" 2>/dev/null \
    | grep -qE '^chore(\(main\))?: (release|post-release)'
}

# 当前场景是否属于 release 上下文（HEAD 或 range 中有 release/post-release，或在 release-please 分支上）
_is_release_context() {
  _is_release_please_branch || _is_any_release_message || _is_release_in_range
}

# 是否应跳过整套 CI — 仅 post-release bot commit
_skip_whole_ci() {
  _is_post_release_bot
}

# 是否应跳过 dist stale check — release 上下文均跳过
# （因为 post-release job 会负责重建 dist，release merge commit 时 dist 尚未更新；
#  release-please PR 上 GUI bundle hash 因 version bump 必然漂移，由分支名直接放行）
_skip_dist_stale() {
  _is_release_please_branch || _is_any_release_message || _is_release_in_range
}

# ── 执行 ──

if [ -n "$CHECK_NAME" ]; then
  case "$CHECK_NAME" in
    is_post_release_bot)     _is_post_release_bot ;;
    is_release_bot)          _is_release_bot ;;
    is_release_please_branch) _is_release_please_branch ;;
    is_release_context)      _is_release_context ;;
    skip_dist_stale)         _skip_dist_stale ;;
    skip_whole_ci)           _skip_whole_ci ;;
    *)
      echo "❌ Unknown check: $CHECK_NAME" >&2
      echo "   Available: is_post_release_bot, is_release_bot, is_release_please_branch, is_release_context, skip_dist_stale, skip_whole_ci" >&2
      exit 2
      ;;
  esac
else
  IS_BOT=$(_is_bot_author && echo "true" || echo "false")
  IS_RP_BRANCH=$(_is_release_please_branch && echo "true" || echo "false")
  IS_RELEASE_COMMIT_MSG=$(_is_release_commit_message && echo "true" || echo "false")
  IS_POST_RELEASE_MSG=$(_is_post_release_message && echo "true" || echo "false")
  IS_RELEASE_BOT=$(_is_release_bot && echo "true" || echo "false")
  IS_POST_RELEASE_BOT=$(_is_post_release_bot && echo "true" || echo "false")
  IS_RELEASE_IN_RANGE=$(_is_release_in_range && echo "true" || echo "false")
  IS_RELEASE_CONTEXT=$(_is_release_context && echo "true" || echo "false")
  SKIP_WHOLE_CI=$(_skip_whole_ci && echo "true" || echo "false")
  SKIP_DIST_STALE=$(_skip_dist_stale && echo "true" || echo "false")

  echo "IS_BOT_AUTHOR=$IS_BOT"
  echo "IS_RELEASE_PLEASE_BRANCH=$IS_RP_BRANCH"
  echo "IS_RELEASE_COMMIT_MESSAGE=$IS_RELEASE_COMMIT_MSG"
  echo "IS_POST_RELEASE_MESSAGE=$IS_POST_RELEASE_MSG"
  echo "IS_RELEASE_BOT=$IS_RELEASE_BOT"
  echo "IS_POST_RELEASE_BOT=$IS_POST_RELEASE_BOT"
  echo "IS_RELEASE_IN_RANGE=$IS_RELEASE_IN_RANGE"
  echo "IS_RELEASE_CONTEXT=$IS_RELEASE_CONTEXT"
  echo "SKIP_WHOLE_CI=$SKIP_WHOLE_CI"
  echo "SKIP_DIST_STALE=$SKIP_DIST_STALE"
fi

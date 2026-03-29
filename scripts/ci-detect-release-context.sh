#!/usr/bin/env bash
# ci-detect-release-context.sh
# 统一检测当前 CI 上下文是否属于 release / post-release 场景。
# 被 GitHub Actions workflow 和其他 CI 脚本共同调用，消除判断逻辑的重复与分歧。
#
# 用法:
#   bash scripts/ci-detect-release-context.sh [--check=<check_name>] [<base_ref> <head_ref>]
#
# 可选 check_name:
#   is_post_release_bot   — HEAD 是 github-actions bot 的 post-release 提交（author AND message 双重匹配）
#   is_release_context    — commit range 中包含 release-please 或 post-release 提交
#   skip_dist_stale       — 当前场景应跳过 dist staleness 检查（release merge commit 或 post-release）
#
# 不带参数时输出所有检测结果的 KEY=VALUE 对（可 source 使用）。
#
# 退出码:
#   --check 模式: 0 = 条件成立, 1 = 条件不成立
#   无参数模式: 始终 0（输出变量）

set -euo pipefail

# ── 参数解析 ──
CHECK_NAME=""
BASE_REF=""
HEAD_REF="HEAD"

for arg in "$@"; do
  case "$arg" in
    --check=*) CHECK_NAME="${arg#--check=}" ;;
    *)
      if [ -z "$BASE_REF" ]; then
        BASE_REF="$arg"
      else
        HEAD_REF="$arg"
      fi
      ;;
  esac
done

# ── 核心检测函数 ──

# 检测 HEAD 提交是否由 github-actions bot 创建
_is_bot_author() {
  local author
  author=$(git log -1 --format='%an' "$HEAD_REF" 2>/dev/null || echo "")
  [[ "$author" == *"github-actions"* ]]
}

# 检测 HEAD commit message 是否匹配 release/post-release 模式
_is_release_message() {
  local msg
  msg=$(git log -1 --format='%s' "$HEAD_REF" 2>/dev/null || echo "")
  echo "$msg" | grep -qE '^chore(\(main\))?: (release|post-release)'
}

# 检测 HEAD 是否是 post-release bot 提交（author AND message 双重匹配）
_is_post_release_bot() {
  _is_bot_author && _is_release_message
}

# 检测 commit range 中是否包含 release-please 或 post-release 提交
_is_release_in_range() {
  if [ -z "$BASE_REF" ]; then
    return 1
  fi
  # 先确保 base ref 存在
  if ! git rev-parse --verify "${BASE_REF}^{commit}" >/dev/null 2>&1; then
    return 1
  fi
  git log --format='%s' "${BASE_REF}..${HEAD_REF}" 2>/dev/null \
    | grep -qE '^chore(\(main\))?: (release|post-release)'
}

# 组合判断: 当前场景是否属于 release 上下文
_is_release_context() {
  _is_release_message || _is_release_in_range
}

# 组合判断: 是否应跳过 dist stale check
# release merge commit 和 post-release commit 都应跳过
# （因为 post-release job 会负责重建 dist）
_skip_dist_stale() {
  _is_release_message || _is_post_release_bot
}

# ── 执行 ──

if [ -n "$CHECK_NAME" ]; then
  case "$CHECK_NAME" in
    is_post_release_bot) _is_post_release_bot ;;
    is_release_context)  _is_release_context ;;
    skip_dist_stale)     _skip_dist_stale ;;
    *)
      echo "❌ Unknown check: $CHECK_NAME" >&2
      echo "   Available: is_post_release_bot, is_release_context, skip_dist_stale" >&2
      exit 2
      ;;
  esac
else
  # 输出所有检测结果为 KEY=VALUE
  IS_BOT=$(_is_bot_author && echo "true" || echo "false")
  IS_RELEASE_MSG=$(_is_release_message && echo "true" || echo "false")
  IS_POST_RELEASE_BOT=$(_is_post_release_bot && echo "true" || echo "false")
  IS_RELEASE_IN_RANGE=$(_is_release_in_range && echo "true" || echo "false")
  IS_RELEASE_CONTEXT=$(_is_release_context && echo "true" || echo "false")
  SKIP_DIST_STALE=$(_skip_dist_stale && echo "true" || echo "false")

  echo "IS_BOT_AUTHOR=$IS_BOT"
  echo "IS_RELEASE_MESSAGE=$IS_RELEASE_MSG"
  echo "IS_POST_RELEASE_BOT=$IS_POST_RELEASE_BOT"
  echo "IS_RELEASE_IN_RANGE=$IS_RELEASE_IN_RANGE"
  echo "IS_RELEASE_CONTEXT=$IS_RELEASE_CONTEXT"
  echo "SKIP_DIST_STALE=$SKIP_DIST_STALE"
fi

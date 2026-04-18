#!/usr/bin/env bash
# check-branch-synced.sh — pre-push 闸口：当前分支必须与 origin/main 同步
#
# 设计原则：
#   - 主分支与 release-please 分支自动放行
#   - 通过 merge-base 比对：当前分支若不包含 origin/main 最新 commit → 阻断
#   - 网络不可用时降级为警告（不阻断），避免离线场景误伤
#   - 紧急通道：AUTOPILOT_SKIP_MAIN_SYNC=1 临时绕过
#
# 用法（独立可调用，便于测试与脚本复用）：
#   bash scripts/check-branch-synced.sh           # 检查当前分支
#   bash scripts/check-branch-synced.sh --quiet   # 仅在阻断时输出
#
# 退出码：
#   0 — 已同步 / 主分支 / release-please / 应跳过
#   1 — 分支落后 origin/main，必须 rebase / merge
#   2 — 内部错误（git 命令失败等）

set -uo pipefail

QUIET=false
for arg in "$@"; do
  case "$arg" in
    --quiet) QUIET=true ;;
  esac
done

log() { [ "$QUIET" = "true" ] || echo "$@" >&2; }

if [ "${AUTOPILOT_SKIP_MAIN_SYNC:-0}" = "1" ]; then
  log "⚠️  AUTOPILOT_SKIP_MAIN_SYNC=1 — 跳过 main 同步检查（紧急通道）"
  exit 0
fi

CURRENT=$(git symbolic-ref --short HEAD 2>/dev/null || echo "")
if [ -z "$CURRENT" ]; then
  log "ℹ️  detached HEAD，跳过 main 同步检查"
  exit 0
fi

# 主分支与 release-please 分支：白名单放行
case "$CURRENT" in
  main|master)
    exit 0
    ;;
  release-please--*|release/*)
    exit 0
    ;;
esac

# 探测 main 分支名（兼容历史 master 仓库）
MAIN_BRANCH="main"
if ! git rev-parse --verify "origin/${MAIN_BRANCH}" >/dev/null 2>&1; then
  if git rev-parse --verify "origin/master" >/dev/null 2>&1; then
    MAIN_BRANCH="master"
  else
    log "⚠️  origin/main 与 origin/master 都不存在，跳过同步检查"
    exit 0
  fi
fi

# 拉取 origin/${MAIN_BRANCH}（5s 超时，断网降级为警告而非阻断）
# macOS 默认无 timeout/gtimeout，缺失时直接 fetch（依赖 git 自身网络超时）
if command -v timeout >/dev/null 2>&1; then
  _fetch_cmd=(timeout 5 git fetch --quiet origin "${MAIN_BRANCH}")
elif command -v gtimeout >/dev/null 2>&1; then
  _fetch_cmd=(gtimeout 5 git fetch --quiet origin "${MAIN_BRANCH}")
else
  _fetch_cmd=(git fetch --quiet origin "${MAIN_BRANCH}")
fi
if ! "${_fetch_cmd[@]}" 2>/dev/null; then
  log "⚠️  无法 fetch origin/${MAIN_BRANCH}（网络不可用？），跳过同步检查"
  log "    若需强制检查，请联网后重试，或显式: git fetch origin ${MAIN_BRANCH}"
  exit 0
fi

REMOTE_TIP=$(git rev-parse "origin/${MAIN_BRANCH}" 2>/dev/null || echo "")
if [ -z "$REMOTE_TIP" ]; then
  log "⚠️  无法解析 origin/${MAIN_BRANCH} HEAD，跳过同步检查"
  exit 0
fi

MERGE_BASE=$(git merge-base HEAD "origin/${MAIN_BRANCH}" 2>/dev/null || echo "")
if [ -z "$MERGE_BASE" ]; then
  log "❌ 无法计算 HEAD 与 origin/${MAIN_BRANCH} 的 merge-base（仓库历史损坏？）"
  exit 2
fi

# 当前分支已包含 origin/main 最新 commit ⇔ merge-base == REMOTE_TIP
if [ "$MERGE_BASE" = "$REMOTE_TIP" ]; then
  log "✅ 分支 $CURRENT 已与 origin/${MAIN_BRANCH} 同步"
  exit 0
fi

# 落后了 — 计算落后多少 commit
BEHIND=$(git rev-list --count "$MERGE_BASE..origin/${MAIN_BRANCH}" 2>/dev/null || echo "?")
AHEAD=$(git rev-list --count "$MERGE_BASE..HEAD" 2>/dev/null || echo "?")

cat >&2 <<EOF

❌ 分支同步检查失败

  当前分支:   $CURRENT
  目标基线:   origin/${MAIN_BRANCH}
  落后 commit: $BEHIND
  本地 commit: $AHEAD

  推送被阻断 — 请先与 origin/${MAIN_BRANCH} 同步：

  推荐（保持线性历史）:
    git fetch origin ${MAIN_BRANCH}
    git rebase origin/${MAIN_BRANCH}
    # 解决冲突后再 git push（feature 分支首次同步可能需要 --force-with-lease）

  替代（保留 merge commit）:
    git fetch origin ${MAIN_BRANCH}
    git merge origin/${MAIN_BRANCH}
    git push

  紧急绕过（不推荐，仅在极端情况下）:
    AUTOPILOT_SKIP_MAIN_SYNC=1 git push ...

EOF

exit 1

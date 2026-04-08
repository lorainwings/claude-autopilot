#!/usr/bin/env bash
# check-dist-freshness.sh
# 统一 dist 一致性校验。被 pre-commit、pre-push、CI 共同调用。
#
# 用法:
#   bash scripts/check-dist-freshness.sh <plugin-name> [--rebuild] [--git-add]
#   bash scripts/check-dist-freshness.sh all [--rebuild] [--git-add]
#
# 参数:
#   plugin-name: spec-autopilot | parallel-harness | daily-report | all
#   --rebuild:   发现 stale 时自动重建
#   --git-add:   重建后自动 git add dist/<plugin>/
#   --ci-git-check: CI 模式 — 用 git diff 检查 build 后 dist/ 是否与提交一致
#                   (在 make build 之后调用，检测 build 是否产生了任何 diff)
#   --warn-only: 发现 stale 时输出警告但返回 0 (用于 pre-commit 非阻断提示)
#
# 退出码:
#   0: dist 一致 (或已成功重建)
#   1: dist 不一致且未重建
#   2: 重建失败

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$REPO_ROOT"

# ── 参数解析 ──
PLUGIN_NAME="${1:-}"
REBUILD=false
GIT_ADD=false
CI_GIT_CHECK=false
WARN_ONLY=false

for arg in "$@"; do
  case "$arg" in
    --rebuild) REBUILD=true ;;
    --git-add) GIT_ADD=true ;;
    --ci-git-check) CI_GIT_CHECK=true ;;
    --warn-only) WARN_ONLY=true ;;
  esac
done

if [ -z "$PLUGIN_NAME" ]; then
  echo "❌ Usage: $0 <plugin-name|all> [--rebuild] [--git-add]" >&2
  exit 1
fi

# ── 核心: 检查单个插件的 dist 一致性 ──
check_plugin_dist() {
  local plugin="$1"
  local src_dir="plugins/$plugin"
  local dst_dir="dist/$plugin"

  case "$plugin" in
    spec-autopilot|parallel-harness|daily-report) ;;
    *)
      echo "❌ Unknown plugin: $plugin" >&2
      return 1
      ;;
  esac

  if [ ! -d "$src_dir" ]; then
    echo "⚠️  $src_dir 不存在，跳过" >&2
    return 0
  fi

  if [ ! -d "$dst_dir" ]; then
    echo "❌ $dst_dir 不存在但 $src_dir 存在" >&2
    return 1
  fi

  local stale=false

  case "$plugin" in
    spec-autopilot)
      # 对比白名单目录: .claude-plugin, hooks, skills
      for _dir in .claude-plugin hooks skills; do
        if [ -d "$src_dir/$_dir" ] && ! diff -rq "$src_dir/$_dir" "$dst_dir/$_dir" >/dev/null 2>&1; then
          stale=true
          break
        fi
      done
      # 对比 runtime/scripts/ 按 .dist-include manifest
      if [ "$stale" = "false" ]; then
        local manifest="$src_dir/runtime/scripts/.dist-include"
        if [ -f "$manifest" ]; then
          while IFS= read -r line; do
            line="${line%%#*}"
            line="$(echo "$line" | xargs)"
            [ -z "$line" ] && continue
            local sf="$src_dir/runtime/scripts/$line"
            local df="$dst_dir/runtime/scripts/$line"
            if [ -f "$sf" ] && [ -f "$df" ]; then
              if ! diff -q "$sf" "$df" >/dev/null 2>&1; then
                stale=true; break
              fi
            elif [ -f "$sf" ]; then
              stale=true; break
            fi
          done < "$manifest"
        fi
      fi
      # 对比 runtime/server/src TS 模块
      if [ "$stale" = "false" ] && [ -d "$src_dir/runtime/server/src" ]; then
        if ! diff -rq "$src_dir/runtime/server/src" "$dst_dir/runtime/server/src" >/dev/null 2>&1; then
          stale=true
        fi
      fi
      # 对比 runtime/server/autopilot-server.ts 入口
      if [ "$stale" = "false" ] && [ -f "$src_dir/runtime/server/autopilot-server.ts" ]; then
        if ! diff -q "$src_dir/runtime/server/autopilot-server.ts" "$dst_dir/runtime/server/autopilot-server.ts" >/dev/null 2>&1; then
          stale=true
        fi
      fi
      # 对比 assets/gui/ (GUI 构建产物，源在 gui-dist/ 非 gui/dist)
      if [ "$stale" = "false" ] && [ -d "$dst_dir/assets/gui" ]; then
        local gui_dist="$src_dir/gui-dist"
        if [ -d "$gui_dist" ]; then
          if ! diff -rq "$gui_dist" "$dst_dir/assets/gui" >/dev/null 2>&1; then
            stale=true
          fi
        fi
      fi
      # 校验 dist/runtime/scripts/ 无清单外残留文件
      if [ "$stale" = "false" ] && [ -d "$dst_dir/runtime/scripts" ]; then
        local manifest="$src_dir/runtime/scripts/.dist-include"
        if [ -f "$manifest" ]; then
          local manifest_entries
          manifest_entries=$(sed 's/#.*//' "$manifest" | tr -s '[:space:]' '\n' | grep -v '^$')
          for f in "$dst_dir/runtime/scripts/"*; do
            [ -f "$f" ] || continue
            local fname
            fname=$(basename "$f")
            if ! grep -qxF "$fname" <<< "$manifest_entries"; then
              stale=true
              break
            fi
          done
        fi
      fi
      ;;

    parallel-harness)
      for _dir in runtime skills config .claude-plugin; do
        if [ -d "$src_dir/$_dir" ] && ! diff -rq "$src_dir/$_dir" "$dst_dir/$_dir" >/dev/null 2>&1; then
          stale=true
          break
        fi
      done
      ;;

    daily-report)
      for _dir in skills .claude-plugin; do
        if [ -d "$src_dir/$_dir" ] && ! diff -rq "$src_dir/$_dir" "$dst_dir/$_dir" >/dev/null 2>&1; then
          stale=true
          break
        fi
      done
      ;;
  esac

  # 对比 CLAUDE.md (需考虑 DEV-ONLY 裁剪)
  if [ "$stale" = "false" ] && [ -f "$src_dir/CLAUDE.md" ]; then
    local expected actual
    if grep -q "<!-- DEV-ONLY-BEGIN -->" "$src_dir/CLAUDE.md" 2>/dev/null; then
      expected=$(sed '/<!-- DEV-ONLY-BEGIN -->/,/<!-- DEV-ONLY-END -->/d' "$src_dir/CLAUDE.md")
    else
      expected=$(cat "$src_dir/CLAUDE.md")
    fi
    actual=$(cat "$dst_dir/CLAUDE.md" 2>/dev/null || echo "")
    if [ "$expected" != "$actual" ]; then
      stale=true
    fi
  fi

  if [ "$stale" = "true" ]; then
    return 1
  fi
  return 0
}

# ── 检查 + 可选重建 ──
check_and_maybe_rebuild() {
  local plugin="$1"
  local build_script="plugins/$plugin/tools/build-dist.sh"

  # CI git-check 模式: build 已在前一步完成，这里用 git diff 检查 dist/ 是否变化
  # 如果 build 产生了 diff，说明提交的 dist 是 stale 的
  if [ "$CI_GIT_CHECK" = "true" ]; then
    local stale=0
    if ! git diff --exit-code "dist/$plugin" >/dev/null 2>&1; then
      echo "❌ dist/$plugin has modified tracked files after fresh build"
      stale=1
    fi
    local untracked
    untracked=$(git ls-files --others --exclude-standard "dist/$plugin")
    if [ -n "$untracked" ]; then
      echo "❌ dist/$plugin has untracked files after fresh build:"
      echo "$untracked"
      stale=1
    fi
    if [ "$stale" -eq 1 ]; then
      local make_target
      case "$plugin" in
        spec-autopilot)    make_target="make build" ;;
        parallel-harness)  make_target="make ph-build" ;;
        daily-report)      make_target="make dr-build" ;;
        *)                 make_target="make <plugin>-build" ;;
      esac
      echo "   Run '$make_target' and commit the result"
      return 1
    fi
    echo "✅ dist/$plugin is up-to-date (git check)"
    return 0
  fi

  # 本地模式: 比较源码与 dist 内容
  if check_plugin_dist "$plugin"; then
    echo "✅ dist/$plugin is up-to-date"
    return 0
  fi

  echo "❌ dist/$plugin is stale"

  if [ "$WARN_ONLY" = "true" ]; then
    echo "⚠️  dist/$plugin is stale (warn-only mode, not blocking)"
    return 0
  fi

  if [ "$REBUILD" = "true" ]; then
    echo "📦 Rebuilding dist/$plugin..."
    if [ ! -f "$build_script" ]; then
      echo "❌ Build script not found: $build_script" >&2
      return 2
    fi
    if ! bash "$build_script"; then
      echo "❌ $plugin dist build failed" >&2
      return 2
    fi
    if [ "$GIT_ADD" = "true" ]; then
      git add "dist/$plugin/"
    fi
    echo "✅ dist/$plugin rebuilt successfully"
    return 0
  fi

  # 生成正确的 make target 提示
  local make_target
  case "$plugin" in
    spec-autopilot)    make_target="make build" ;;
    parallel-harness)  make_target="make ph-build" ;;
    daily-report)      make_target="make dr-build" ;;
    *)                 make_target="make <plugin>-build" ;;
  esac
  echo "   Run '$make_target' and commit the result"
  return 1
}

# ── 主逻辑 ──
OVERALL_FAIL=0

if [ "$PLUGIN_NAME" = "all" ]; then
  for p in spec-autopilot parallel-harness daily-report; do
    if ! check_and_maybe_rebuild "$p"; then
      OVERALL_FAIL=1
    fi
  done
else
  if ! check_and_maybe_rebuild "$PLUGIN_NAME"; then
    OVERALL_FAIL=1
  fi
fi

exit "$OVERALL_FAIL"

#!/usr/bin/env bash
# tools/release.sh — 统一发版向导（两个插件通用）
#
# 用法:
#   bash tools/release.sh                              # 交互式向导
#   bash tools/release.sh patch spec-autopilot          # 快速模式（向后兼容）
#   bash tools/release.sh --dry-run patch spec-autopilot # 干跑预览
#   bash tools/release.sh --no-git patch spec-autopilot  # 跳过 git 提示
#   bash tools/release.sh -h                            # 帮助
#
# 步骤:
#   1. 更新版本源文件 (plugin.json / package.json)
#   2. 同步 marketplace.json
#   3. 同步 README.md badge
#   4. CHANGELOG: [Unreleased] → [X.Y.Z] - DATE + 新建空 [Unreleased] 段
#   5. 重新构建 dist/

set -euo pipefail

# ── 常量 ─────────────────────────────────────────────────────────
readonly VALID_PLUGINS=("spec-autopilot" "parallel-harness")
readonly VALID_BUMPS=("patch" "minor" "major")

# ── 全局变量 ─────────────────────────────────────────────────────
BUMP_TYPE=""
PLUGIN_NAME=""
DRY_RUN=false
NO_GIT=false
WIZARD_MODE=false
CURRENT_VERSION=""
NEW_VERSION=""

# ── 路径解析 ─────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MARKETPLACE_JSON="$REPO_ROOT/.claude-plugin/marketplace.json"

# ── 颜色输出 ─────────────────────────────────────────────────────
_red()    { printf '\033[0;31m%s\033[0m\n' "$*"; }
_green()  { printf '\033[0;32m%s\033[0m\n' "$*"; }
_yellow() { printf '\033[0;33m%s\033[0m\n' "$*"; }
_cyan()   { printf '\033[0;36m%s\033[0m\n' "$*"; }
_bold()   { printf '\033[1m%s\033[0m\n' "$*"; }

# ── Cross-platform in-place sed ──────────────────────────────────
sedi() {
  if sed --version 2>/dev/null | grep -q GNU; then
    sed -i "$@"
  else
    sed -i '' "$@"
  fi
}

# ── usage / help ─────────────────────────────────────────────────
print_usage() {
  cat <<'USAGE'
用法:
  bash tools/release.sh                              # 交互式向导
  bash tools/release.sh <bump> <plugin>              # 快速模式
  bash tools/release.sh --dry-run <bump> <plugin>    # 干跑预览
  bash tools/release.sh --no-git <bump> <plugin>     # 跳过 git 提示
  bash tools/release.sh -h | --help                  # 帮助

参数:
  <bump>     patch | minor | major
  <plugin>   spec-autopilot | parallel-harness

选项:
  --dry-run  预览所有变更，不实际写入文件
  --no-git   跳过最后的 git commit/tag/push 交互提示
  -h,--help  显示此帮助

示例:
  bash tools/release.sh                              # 引导式选择
  bash tools/release.sh patch spec-autopilot          # 直接发 patch
  bash tools/release.sh --dry-run minor parallel-harness
USAGE
}

# ── parse_args ───────────────────────────────────────────────────
parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h | --help)
        print_usage
        exit 0
        ;;
      --dry-run)
        DRY_RUN=true
        shift
        ;;
      --no-git)
        NO_GIT=true
        shift
        ;;
      patch | minor | major)
        BUMP_TYPE="$1"
        shift
        ;;
      spec-autopilot | parallel-harness)
        PLUGIN_NAME="$1"
        shift
        ;;
      *)
        _red "❌ 未知参数: $1"
        echo ""
        print_usage
        exit 1
        ;;
    esac
  done

  # 两个位置参数都有 → 快速模式，否则 → 向导模式
  if [[ -n "$BUMP_TYPE" && -n "$PLUGIN_NAME" ]]; then
    WIZARD_MODE=false
  elif [[ -z "$BUMP_TYPE" && -z "$PLUGIN_NAME" ]]; then
    WIZARD_MODE=true
  else
    _red "❌ 快速模式需要同时提供 <bump> 和 <plugin>"
    echo ""
    print_usage
    exit 1
  fi
}

# ── print_banner ─────────────────────────────────────────────────
print_banner() {
  echo ""
  _bold "╔═══════════════════════════════════════╗"
  _bold "║       🚀 claude-autopilot 发版向导      ║"
  _bold "╚═══════════════════════════════════════╝"
  echo ""
  if [[ "$DRY_RUN" = true ]]; then
    _yellow "  ⚠️  DRY-RUN 模式 — 不写入任何文件"
    echo ""
  fi
}

# ── read_current_version ─────────────────────────────────────────
read_current_version() {
  local plugin="$1"
  local plugin_root="$REPO_ROOT/plugins/$plugin"
  local version_file

  if [[ "$plugin" = "spec-autopilot" ]]; then
    version_file="$plugin_root/.claude-plugin/plugin.json"
  else
    version_file="$plugin_root/package.json"
  fi

  if [[ ! -f "$version_file" ]]; then
    _red "❌ 版本源文件不存在: $version_file"
    exit 1
  fi

  CURRENT_VERSION=$(jq -r '.version' "$version_file" 2>/dev/null)
  if [[ -z "$CURRENT_VERSION" || "$CURRENT_VERSION" = "null" ]]; then
    _red "❌ 无法读取版本号: $version_file"
    exit 1
  fi
}

# ── compute_new_version ──────────────────────────────────────────
compute_new_version() {
  local bump="$1"
  local base_version="${CURRENT_VERSION%%-*}"
  local major minor patch

  major=$(echo "$base_version" | cut -d. -f1)
  minor=$(echo "$base_version" | cut -d. -f2)
  patch=$(echo "$base_version" | cut -d. -f3)

  # 整数校验
  for part in major minor patch; do
    local val="${!part}"
    if ! [[ "$val" =~ ^[0-9]+$ ]]; then
      _red "❌ 无法解析版本号 '$CURRENT_VERSION' 中的 $part='$val'"
      exit 1
    fi
  done

  case "$bump" in
    patch) NEW_VERSION="${major}.${minor}.$((patch + 1))" ;;
    minor) NEW_VERSION="${major}.$((minor + 1)).0" ;;
    major) NEW_VERSION="$((major + 1)).0.0" ;;
  esac
}

# ── select_plugin (wizard) ───────────────────────────────────────
select_plugin() {
  _bold "📦 选择插件:"
  echo ""

  local idx=1
  for p in "${VALID_PLUGINS[@]}"; do
    read_current_version "$p"
    printf "  %d) %-24s (当前 v%s)\n" "$idx" "$p" "$CURRENT_VERSION"
    idx=$((idx + 1))
  done
  echo ""

  local choice
  while true; do
    read -rp "  请输入编号 [1-${#VALID_PLUGINS[@]}]: " choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#VALID_PLUGINS[@]} )); then
      PLUGIN_NAME="${VALID_PLUGINS[$((choice - 1))]}"
      break
    fi
    _red "  无效输入，请重试"
  done

  # 重新读取选定插件的版本
  read_current_version "$PLUGIN_NAME"
  echo ""
  _green "  → $PLUGIN_NAME (v$CURRENT_VERSION)"
  echo ""
}

# ── select_bump_type (wizard) ────────────────────────────────────
select_bump_type() {
  _bold "📈 选择版本递增类型:"
  echo ""

  local idx=1
  for b in "${VALID_BUMPS[@]}"; do
    compute_new_version "$b"
    printf "  %d) %-8s → v%s\n" "$idx" "$b" "$NEW_VERSION"
    idx=$((idx + 1))
  done
  echo ""

  local choice
  while true; do
    read -rp "  请输入编号 [1-${#VALID_BUMPS[@]}]: " choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#VALID_BUMPS[@]} )); then
      BUMP_TYPE="${VALID_BUMPS[$((choice - 1))]}"
      break
    fi
    _red "  无效输入，请重试"
  done

  compute_new_version "$BUMP_TYPE"
  echo ""
  _green "  → $BUMP_TYPE: v$CURRENT_VERSION → v$NEW_VERSION"
  echo ""
}

# ── preflight_checks ─────────────────────────────────────────────
preflight_checks() {
  local plugin_root="$REPO_ROOT/plugins/$PLUGIN_NAME"
  local errors=0
  local warnings=0

  _bold "🔍 前置检查:"
  echo ""

  # 1. jq 已安装（阻断）
  if command -v jq &>/dev/null; then
    _green "  ✅ jq 已安装"
  else
    _red "  ❌ jq 未安装 — 请执行: brew install jq"
    errors=$((errors + 1))
  fi

  # 2. 插件目录存在（阻断）
  if [[ -d "$plugin_root" ]]; then
    _green "  ✅ 插件目录存在"
  else
    _red "  ❌ 插件目录不存在: $plugin_root"
    errors=$((errors + 1))
  fi

  # 3. 工作区干净（阻断）
  if [[ -z "$(git -C "$REPO_ROOT" status --porcelain 2>/dev/null)" ]]; then
    _green "  ✅ 工作区干净"
  else
    _red "  ❌ 工作区有未提交的变更"
    echo "     请先 commit 或 stash 当前变更"
    errors=$((errors + 1))
  fi

  # 4. 当前分支（非 main 警告，不阻断）
  local branch
  branch=$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
  if [[ "$branch" = "main" || "$branch" = "master" ]]; then
    _green "  ✅ 当前分支: $branch"
  else
    _yellow "  ⚠️  当前分支: $branch (非 main)"
    warnings=$((warnings + 1))
  fi

  # 5. 远程同步状态（落后警告，不阻断）
  local upstream
  upstream=$(git -C "$REPO_ROOT" rev-parse --abbrev-ref '@{u}' 2>/dev/null || echo "")
  if [[ -n "$upstream" ]]; then
    git -C "$REPO_ROOT" fetch --quiet 2>/dev/null || true
    local behind
    behind=$(git -C "$REPO_ROOT" rev-list --count HEAD.."$upstream" 2>/dev/null || echo "0")
    if [[ "$behind" -gt 0 ]]; then
      _yellow "  ⚠️  本地落后远程 $behind 个提交"
      warnings=$((warnings + 1))
    else
      _green "  ✅ 与远程同步"
    fi
  else
    _yellow "  ⚠️  未设置远程追踪分支"
    warnings=$((warnings + 1))
  fi

  # 6. CHANGELOG [Unreleased] 段有内容（阻断）
  local changelog="$plugin_root/CHANGELOG.md"
  if [[ ! -f "$changelog" ]]; then
    _red "  ❌ CHANGELOG.md 不存在: $changelog"
    errors=$((errors + 1))
  elif ! grep -q '## \[Unreleased\]' "$changelog"; then
    _red "  ❌ CHANGELOG.md 中没有 ## [Unreleased] 段"
    errors=$((errors + 1))
  else
    local content
    content=$(awk '/^## \[Unreleased\]/{f=1;next} /^## \[[0-9]/{f=0} f && NF' "$changelog")
    if [[ -z "$content" ]]; then
      _red "  ❌ CHANGELOG.md 的 [Unreleased] 段为空"
      echo "     请先记录变更内容，再执行发版"
      errors=$((errors + 1))
    else
      _green "  ✅ CHANGELOG [Unreleased] 段有内容"
    fi
  fi

  echo ""
  if [[ $errors -gt 0 ]]; then
    _red "前置检查失败: $errors 项阻断错误"
    exit 1
  fi
  if [[ $warnings -gt 0 ]]; then
    _yellow "有 $warnings 项警告（不影响继续）"
    echo ""
  fi
}

# ── preview_changes ──────────────────────────────────────────────
preview_changes() {
  local plugin_root="$REPO_ROOT/plugins/$PLUGIN_NAME"
  local changelog="$plugin_root/CHANGELOG.md"

  _bold "📋 变更预览: $PLUGIN_NAME v$CURRENT_VERSION → v$NEW_VERSION ($BUMP_TYPE)"
  echo ""

  _cyan "  将修改的文件:"
  if [[ "$PLUGIN_NAME" = "spec-autopilot" ]]; then
    echo "    • plugins/$PLUGIN_NAME/.claude-plugin/plugin.json"
  else
    echo "    • plugins/$PLUGIN_NAME/package.json"
    echo "    • plugins/$PLUGIN_NAME/.claude-plugin/plugin.json"
  fi
  echo "    • .claude-plugin/marketplace.json"
  if [[ -f "$plugin_root/README.md" ]] && grep -q 'version-[0-9]' "$plugin_root/README.md"; then
    echo "    • plugins/$PLUGIN_NAME/README.md (badge)"
  fi
  echo "    • plugins/$PLUGIN_NAME/CHANGELOG.md"
  if [[ -f "$plugin_root/tools/build-dist.sh" ]]; then
    echo "    • dist/$PLUGIN_NAME/ (rebuild)"
  fi

  echo ""
  _cyan "  [Unreleased] 内容（将归入 v$NEW_VERSION）:"
  awk '/^## \[Unreleased\]/{f=1;next} /^## \[[0-9]/{f=0} f && NF' "$changelog" | head -20 | while IFS= read -r line; do
    echo "    $line"
  done
  echo ""
}

# ── confirm ──────────────────────────────────────────────────────
confirm() {
  if [[ "$DRY_RUN" = true ]]; then
    _yellow "🏁 DRY-RUN 模式 — 预览完成，未修改任何文件"
    exit 0
  fi

  local answer
  read -rp "确认执行发版? [y/N] " answer
  case "$answer" in
    [yY] | [yY][eE][sS]) ;;
    *)
      _yellow "已取消"
      exit 0
      ;;
  esac
  echo ""
}

# ── step_1: 更新版本源文件 ───────────────────────────────────────
step_1_update_version_source() {
  local plugin_root="$REPO_ROOT/plugins/$PLUGIN_NAME"
  local version_file

  if [[ "$PLUGIN_NAME" = "spec-autopilot" ]]; then
    version_file="$plugin_root/.claude-plugin/plugin.json"
  else
    version_file="$plugin_root/package.json"
  fi

  jq --arg v "$NEW_VERSION" '.version = $v' "$version_file" > "${version_file}.tmp" || {
    _red "❌ 更新 $version_file 失败"
    exit 1
  }
  mv "${version_file}.tmp" "$version_file"
  _green "  ✅ [1/5] $(basename "$version_file") → $NEW_VERSION"

  # parallel-harness 额外同步 .claude-plugin/plugin.json
  if [[ "$PLUGIN_NAME" = "parallel-harness" ]]; then
    local claude_plugin_json="$plugin_root/.claude-plugin/plugin.json"
    if [[ -f "$claude_plugin_json" ]]; then
      jq --arg v "$NEW_VERSION" '.version = $v' "$claude_plugin_json" > "${claude_plugin_json}.tmp" || {
        _red "❌ 更新 $claude_plugin_json 失败"
        exit 1
      }
      mv "${claude_plugin_json}.tmp" "$claude_plugin_json"
      echo "         .claude-plugin/plugin.json → $NEW_VERSION"
    fi
  fi
}

# ── step_2: 同步 marketplace.json ────────────────────────────────
step_2_update_marketplace() {
  if [[ ! -f "$MARKETPLACE_JSON" ]]; then
    _red "❌ marketplace.json 不存在: $MARKETPLACE_JSON"
    exit 1
  fi

  jq --arg v "$NEW_VERSION" --arg n "$PLUGIN_NAME" '
    .plugins = [.plugins[] | if .name == $n then .version = $v else . end]
  ' "$MARKETPLACE_JSON" > "${MARKETPLACE_JSON}.tmp" || {
    _red "❌ 更新 marketplace.json 失败"
    exit 1
  }
  mv "${MARKETPLACE_JSON}.tmp" "$MARKETPLACE_JSON"
  _green "  ✅ [2/5] marketplace.json → $NEW_VERSION"
}

# ── step_3: 同步 README.md badge ─────────────────────────────────
step_3_update_readme_badge() {
  local readme="$REPO_ROOT/plugins/$PLUGIN_NAME/README.md"
  if [[ -f "$readme" ]] && grep -q 'version-[0-9]' "$readme"; then
    sedi "s/version-[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\(--*[a-zA-Z0-9._-]*\)*-blue/version-${NEW_VERSION}-blue/" "$readme"
    _green "  ✅ [3/5] README.md badge → $NEW_VERSION"
  else
    echo "  ⏭️  [3/5] README.md: 无版本 badge，跳过"
  fi
}

# ── step_4: CHANGELOG 处理 ───────────────────────────────────────
step_4_update_changelog() {
  local changelog="$REPO_ROOT/plugins/$PLUGIN_NAME/CHANGELOG.md"
  local today
  today=$(date +%Y-%m-%d)

  # 替换 [Unreleased] → [X.Y.Z] - DATE
  sedi "s/^## \[Unreleased\]/## [${NEW_VERSION}] - ${today}/" "$changelog"

  # 在 # Changelog 后插入新的空 [Unreleased] 段
  local tmpfile
  tmpfile=$(mktemp)
  awk 'NR==1{print; print ""; print "## [Unreleased]"; next}1' "$changelog" > "$tmpfile"
  mv "$tmpfile" "$changelog"

  _green "  ✅ [4/5] CHANGELOG: [Unreleased] → [$NEW_VERSION] - $today + 新 [Unreleased] 段"
}

# ── step_5: 重新构建 dist ────────────────────────────────────────
step_5_rebuild_dist() {
  local build_script="$REPO_ROOT/plugins/$PLUGIN_NAME/tools/build-dist.sh"
  if [[ -f "$build_script" ]]; then
    echo "  📦 [5/5] 重新构建 dist/..."
    if bash "$build_script"; then
      _green "  ✅ [5/5] dist 构建完成"
    else
      _red "❌ dist 构建失败"
      exit 1
    fi
  else
    echo "  ⏭️  [5/5] 无 build-dist.sh，跳过"
  fi
}

# ── verify_versions ──────────────────────────────────────────────
verify_versions() {
  local plugin_root="$REPO_ROOT/plugins/$PLUGIN_NAME"
  local version_file readme changelog

  if [[ "$PLUGIN_NAME" = "spec-autopilot" ]]; then
    version_file="$plugin_root/.claude-plugin/plugin.json"
  else
    version_file="$plugin_root/package.json"
  fi
  readme="$plugin_root/README.md"
  changelog="$plugin_root/CHANGELOG.md"

  echo ""
  _bold "📋 版本验证:"

  local verify_pass=true

  local v_source
  v_source=$(jq -r '.version' "$version_file")
  if [[ "$v_source" = "$NEW_VERSION" ]]; then
    _green "  ✅ $(basename "$version_file"): $v_source"
  else
    _red "  ❌ $(basename "$version_file"): $v_source (期望 $NEW_VERSION)"
    verify_pass=false
  fi

  local v_market
  v_market=$(jq -r --arg n "$PLUGIN_NAME" '.plugins[] | select(.name == $n) | .version' "$MARKETPLACE_JSON")
  if [[ "$v_market" = "$NEW_VERSION" ]]; then
    _green "  ✅ marketplace.json: $v_market"
  else
    _red "  ❌ marketplace.json: $v_market (期望 $NEW_VERSION)"
    verify_pass=false
  fi

  if [[ -f "$readme" ]] && grep -q 'version-[0-9]' "$readme"; then
    local v_readme
    v_readme=$(grep -oE 'version-[0-9]+\.[0-9]+\.[0-9]+(--?[a-zA-Z0-9._-]*)*-blue' "$readme" | head -1 | sed 's/^version-//;s/-blue$//')
    if [[ "$v_readme" = "$NEW_VERSION" ]]; then
      _green "  ✅ README.md badge: $v_readme"
    else
      _red "  ❌ README.md badge: $v_readme (期望 $NEW_VERSION)"
      verify_pass=false
    fi
  fi

  local v_cl
  v_cl=$(grep -oE '^## \[[0-9]+\.[0-9]+\.[0-9]+' "$changelog" | head -1 | sed 's/^## \[//')
  if [[ "$v_cl" = "$NEW_VERSION" ]]; then
    _green "  ✅ CHANGELOG.md: $v_cl"
  else
    _red "  ❌ CHANGELOG.md: $v_cl (期望 $NEW_VERSION)"
    verify_pass=false
  fi

  echo ""
  if [[ "$verify_pass" = true ]]; then
    _green "✅ $PLUGIN_NAME v$NEW_VERSION 发版准备完成"
  else
    _red "❌ 版本验证失败 — 部分文件未正确更新"
    exit 1
  fi
}

# ── git_automation ───────────────────────────────────────────────
git_automation() {
  if [[ "$NO_GIT" = true ]]; then
    echo ""
    _cyan "后续操作（--no-git 模式已跳过交互）:"
    echo ""
    echo "  git add plugins/$PLUGIN_NAME/ .claude-plugin/marketplace.json dist/$PLUGIN_NAME/"
    echo "  git commit -m \"chore(release): $PLUGIN_NAME $NEW_VERSION\""
    echo "  git tag \"$PLUGIN_NAME-v$NEW_VERSION\""
    return
  fi

  echo ""
  _bold "🔧 Git 操作:"
  echo ""

  # commit
  local answer
  read -rp "  执行 git add + commit? [y/N] " answer
  case "$answer" in
    [yY] | [yY][eE][sS])
      git -C "$REPO_ROOT" add \
        "plugins/$PLUGIN_NAME/" \
        ".claude-plugin/marketplace.json" \
        "dist/$PLUGIN_NAME/" 2>/dev/null || true
      git -C "$REPO_ROOT" commit -m "chore(release): $PLUGIN_NAME $NEW_VERSION"
      _green "  ✅ 已提交"
      ;;
    *)
      echo "  跳过 commit"
      echo ""
      echo "  手动命令:"
      echo "    git add plugins/$PLUGIN_NAME/ .claude-plugin/marketplace.json dist/$PLUGIN_NAME/"
      echo "    git commit -m \"chore(release): $PLUGIN_NAME $NEW_VERSION\""
      return
      ;;
  esac

  # tag
  read -rp "  创建 tag $PLUGIN_NAME-v$NEW_VERSION? [y/N] " answer
  case "$answer" in
    [yY] | [yY][eE][sS])
      git -C "$REPO_ROOT" tag "$PLUGIN_NAME-v$NEW_VERSION"
      _green "  ✅ 已创建 tag: $PLUGIN_NAME-v$NEW_VERSION"
      ;;
    *)
      echo "  跳过 tag"
      echo "    git tag \"$PLUGIN_NAME-v$NEW_VERSION\""
      ;;
  esac

  # push
  read -rp "  推送到远程? [y/N] " answer
  case "$answer" in
    [yY] | [yY][eE][sS])
      git -C "$REPO_ROOT" push
      git -C "$REPO_ROOT" push --tags
      _green "  ✅ 已推送"
      ;;
    *)
      echo "  跳过 push"
      echo "    git push && git push --tags"
      ;;
  esac
}

# ── main ─────────────────────────────────────────────────────────
main() {
  parse_args "$@"

  print_banner

  if [[ "$WIZARD_MODE" = true ]]; then
    # 向导模式：交互选择
    select_plugin
    select_bump_type
  else
    # 快速模式：读取版本 + 计算
    read_current_version "$PLUGIN_NAME"
    compute_new_version "$BUMP_TYPE"
    echo "🔖 $PLUGIN_NAME: v$CURRENT_VERSION → v$NEW_VERSION ($BUMP_TYPE)"
    echo ""
  fi

  preflight_checks
  preview_changes
  confirm

  _bold "🚀 执行发版:"
  echo ""
  step_1_update_version_source
  step_2_update_marketplace
  step_3_update_readme_badge
  step_4_update_changelog
  step_5_rebuild_dist

  verify_versions
  git_automation
}

main "$@"

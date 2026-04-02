#!/usr/bin/env bash
# test_dist_freshness.sh — 测试 check-dist-freshness.sh 的一致性校验逻辑
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CHECKER="$REPO_ROOT/scripts/check-dist-freshness.sh"

PASS=0
FAIL=0

green() { printf "\033[32m%s\033[0m\n" "$1"; }
red()   { printf "\033[31m%s\033[0m\n" "$1"; }

echo "=== check-dist-freshness.sh Tests ==="
echo ""

# ── 1. 当前仓库 dist 应与源码一致 (假设已经 build 过) ──
echo "── Test: current dist should be fresh after build ──"
for plugin in spec-autopilot parallel-harness daily-report; do
  if [ -d "plugins/$plugin" ] && [ -d "dist/$plugin" ]; then
    if bash "$CHECKER" "$plugin" 2>/dev/null; then
      green "  PASS: $plugin dist is fresh"
      PASS=$((PASS + 1))
    else
      red "  FAIL: $plugin dist is stale (run make build first)"
      FAIL=$((FAIL + 1))
    fi
  else
    green "  PASS: $plugin skipped (dirs not found)"
    PASS=$((PASS + 1))
  fi
done
echo ""

# ── 2. 无效插件名应报错 ──
echo "── Test: invalid plugin name ──"
if ! bash "$CHECKER" "nonexistent-plugin" 2>/dev/null; then
  green "  PASS: rejects invalid plugin name"
  PASS=$((PASS + 1))
else
  red "  FAIL: should reject invalid plugin name"
  FAIL=$((FAIL + 1))
fi
echo ""

# ── 3. 不带参数应报错 ──
echo "── Test: no arguments ──"
if ! bash "$CHECKER" 2>/dev/null; then
  green "  PASS: rejects no arguments"
  PASS=$((PASS + 1))
else
  red "  FAIL: should reject no arguments"
  FAIL=$((FAIL + 1))
fi
echo ""

# ── 4. all 模式 ──
echo "── Test: 'all' mode checks all plugins ──"
OUTPUT=$(bash "$CHECKER" all 2>&1) || true
# 应该包含每个存在的插件的结果
for plugin in spec-autopilot parallel-harness daily-report; do
  if [ -d "dist/$plugin" ]; then
    if grep -q "$plugin" <<< "$OUTPUT"; then
      green "  PASS: all mode includes $plugin"
      PASS=$((PASS + 1))
    else
      red "  FAIL: all mode missing $plugin"
      FAIL=$((FAIL + 1))
    fi
  fi
done
echo ""

# ── 5. 负例: 篡改 dist 文件后应检测到 stale ──
echo "── Test: tampered dist detected as stale ──"
# 选一个存在的插件做篡改测试
_NEG_PLUGIN=""
for _p in daily-report parallel-harness spec-autopilot; do
  if [ -d "dist/$_p" ] && [ -d "plugins/$_p" ]; then
    _NEG_PLUGIN="$_p"
    break
  fi
done

if [ -n "$_NEG_PLUGIN" ]; then
  # 找到 dist 中的第一个普通文件，备份后篡改
  _NEG_FILE=$(find "dist/$_NEG_PLUGIN" -type f | head -1)
  if [ -n "$_NEG_FILE" ]; then
    cp "$_NEG_FILE" "$_NEG_FILE.test_backup"
    echo "__TAMPERED_FOR_TEST__" >> "$_NEG_FILE"
    if ! bash "$CHECKER" "$_NEG_PLUGIN" 2>/dev/null; then
      green "  PASS: detects tampered dist/$_NEG_PLUGIN"
      PASS=$((PASS + 1))
    else
      red "  FAIL: missed tampered dist/$_NEG_PLUGIN"
      FAIL=$((FAIL + 1))
    fi
    # 恢复
    mv "$_NEG_FILE.test_backup" "$_NEG_FILE"
  else
    green "  PASS: no files found in dist/$_NEG_PLUGIN (skip)"
    PASS=$((PASS + 1))
  fi
else
  green "  PASS: no plugin dirs found (skip)"
  PASS=$((PASS + 1))
fi
echo ""

# ── 6. 负例: spec-autopilot 泄漏文件检测 ──
echo "── Test: leaked file in dist/runtime/scripts/ detected ──"
if [ -d "dist/spec-autopilot/runtime/scripts" ]; then
  touch "dist/spec-autopilot/runtime/scripts/__leak_test__.sh"
  if ! bash "$CHECKER" spec-autopilot 2>/dev/null; then
    green "  PASS: detects leaked file in dist/runtime/scripts/"
    PASS=$((PASS + 1))
  else
    red "  FAIL: missed leaked file in dist/runtime/scripts/"
    FAIL=$((FAIL + 1))
  fi
  rm -f "dist/spec-autopilot/runtime/scripts/__leak_test__.sh"
else
  green "  PASS: dist/spec-autopilot/runtime/scripts not found (skip)"
  PASS=$((PASS + 1))
fi
echo ""

# ── 7. --ci-git-check 模式: 干净工作树应通过 ──
echo "── Test: --ci-git-check passes on clean tree ──"
# 只有在 git 仓库中才有意义
if git rev-parse --git-dir >/dev/null 2>&1; then
  # 先确保 dist 是 clean 的 (不一定是 committed，但至少是 git add 过的)
  _CI_CLEAN=true
  for _p in spec-autopilot parallel-harness daily-report; do
    if [ -d "dist/$_p" ]; then
      # unstaged changes
      if ! git diff --quiet -- "dist/$_p" 2>/dev/null; then
        _CI_CLEAN=false; break
      fi
      # staged but uncommitted changes
      if ! git diff --cached --quiet -- "dist/$_p" 2>/dev/null; then
        _CI_CLEAN=false; break
      fi
    fi
  done
  if [ "$_CI_CLEAN" = "true" ]; then
    if bash "$CHECKER" all --ci-git-check 2>/dev/null; then
      green "  PASS: --ci-git-check passes on clean tree"
      PASS=$((PASS + 1))
    else
      red "  FAIL: --ci-git-check should pass on clean tree"
      FAIL=$((FAIL + 1))
    fi
  else
    green "  PASS: tree has uncommitted dist changes (skip ci-git-check test)"
    PASS=$((PASS + 1))
  fi
else
  green "  PASS: not a git repo (skip ci-git-check test)"
  PASS=$((PASS + 1))
fi
echo ""

# ── Summary ──
echo "============================================"
echo "Dist Freshness Tests: $PASS passed, $FAIL failed"
echo "============================================"

[ "$FAIL" -gt 0 ] && exit 1
exit 0

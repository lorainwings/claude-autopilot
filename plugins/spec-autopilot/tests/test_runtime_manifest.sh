#!/usr/bin/env bash
# test_runtime_manifest.sh — Runtime manifest 与 hooks 一致性测试
# Phase 0: 验证清单驱动构建的正确性
# 设计原则: 所有断言自洽，不依赖外部 dist/ 状态
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$TEST_DIR/.." && pwd)"
source "$TEST_DIR/_test_helpers.sh"

MANIFEST="$PLUGIN_ROOT/scripts/.dist-include"
HOOKS_JSON="$PLUGIN_ROOT/hooks/hooks.json"

echo "--- runtime manifest consistency ---"

# ── 1. manifest 文件存在 ──
if [ -f "$MANIFEST" ]; then
  green "  PASS: manifest file exists"
  PASS=$((PASS + 1))
else
  red "  FAIL: manifest file not found: $MANIFEST"
  FAIL=$((FAIL + 1))
  echo "Results: $PASS passed, $FAIL failed"
  exit 1
fi

# ── 辅助函数: 解析 manifest 为文件列表 ──
parse_manifest() {
  sed 's/#.*//' "$MANIFEST" | xargs -n1 2>/dev/null | grep -v '^$'
}

# ── 2. manifest 中每个文件都存在于 scripts/ ──
ALL_EXIST=true
while IFS= read -r entry; do
  if [ ! -f "$PLUGIN_ROOT/scripts/$entry" ]; then
    red "  FAIL: manifest entry missing from scripts/: $entry"
    FAIL=$((FAIL + 1))
    ALL_EXIST=false
  fi
done < <(parse_manifest)
if [ "$ALL_EXIST" = true ]; then
  green "  PASS: all manifest entries exist in scripts/"
  PASS=$((PASS + 1))
fi

# ── 3. hooks.json 引用的脚本全部在 manifest 中 ──
HOOKS_COVERED=true
for script in $(grep -o 'scripts/[^" ]*\.sh' "$HOOKS_JSON" | sed 's|scripts/||' | sort -u); do
  if ! parse_manifest | grep -qxF "$script"; then
    red "  FAIL: hooks.json references '$script' but it's NOT in manifest"
    FAIL=$((FAIL + 1))
    HOOKS_COVERED=false
  fi
done
if [ "$HOOKS_COVERED" = true ]; then
  green "  PASS: all hooks.json script references are in manifest"
  PASS=$((PASS + 1))
fi

# ── 4. dev-only 文件不在 manifest 中 ──
DEV_ONLY_FILES="build-dist.sh bump-version.sh mock-event-emitter.js tsconfig.json package.json bun.lock"
DEV_CLEAN=true
for devfile in $DEV_ONLY_FILES; do
  if parse_manifest | grep -qxF "$devfile"; then
    red "  FAIL: dev-only file '$devfile' found in manifest"
    FAIL=$((FAIL + 1))
    DEV_CLEAN=false
  fi
done
if [ "$DEV_CLEAN" = true ]; then
  green "  PASS: no dev-only files in manifest"
  PASS=$((PASS + 1))
fi

# ── 5. 自建 fixture 验证 manifest→dist 精确匹配 ──
# 不依赖真实 dist/，在临时环境内构建后验证
echo "  manifest→dist fixture test"
fix_root=$(mktemp -d)
trap 'rm -rf "$fix_root"' EXIT
fix_repo="$fix_root/repo"
fix_plugin="$fix_repo/plugins/spec-autopilot"
mkdir -p \
  "$fix_plugin/scripts" \
  "$fix_plugin/hooks" \
  "$fix_plugin/skills" \
  "$fix_plugin/.claude-plugin" \
  "$fix_plugin/gui" \
  "$fix_plugin/gui-dist" \
  "$fix_root/bin"

# 复制真实的 build-dist.sh 和 manifest
cp "$PLUGIN_ROOT/scripts/build-dist.sh" "$fix_plugin/scripts/"
cp "$MANIFEST" "$fix_plugin/scripts/.dist-include"
chmod +x "$fix_plugin/scripts/build-dist.sh"

# 为 manifest 中每个文件创建占位脚本
while IFS= read -r entry; do
  if [ ! -f "$fix_plugin/scripts/$entry" ]; then
    printf '#!/usr/bin/env bash\necho "stub: %s"\n' "$entry" > "$fix_plugin/scripts/$entry"
  fi
done < <(parse_manifest)

# 额外放入 dev-only 文件（不应出现在 dist）
printf 'dev-only\n' > "$fix_plugin/scripts/mock-event-emitter.js"
printf '{"devDependencies":{}}\n' > "$fix_plugin/scripts/package.json"
printf 'lockfile\n' > "$fix_plugin/scripts/tsconfig.json"

# 最小化 hooks/skills/plugin 配置
cp "$HOOKS_JSON" "$fix_plugin/hooks/hooks.json"
printf '{ "name": "spec-autopilot", "version": "test" }\n' > "$fix_plugin/.claude-plugin/plugin.json"
printf '# CLAUDE\n' > "$fix_plugin/CLAUDE.md"
printf '{ "name": "gui" }\n' > "$fix_plugin/gui/package.json"
printf '<!doctype html><title>f</title>\n' > "$fix_plugin/gui-dist/index.html"

# 用假 bun（不需要真实 GUI 构建）
cat > "$fix_root/bin/bun" <<'BEOF'
#!/usr/bin/env bash
echo "0.0.0-stub"
BEOF
chmod +x "$fix_root/bin/bun"

# 在 fixture 内构建
fix_output=$(PATH="$fix_root/bin:$PATH" bash "$fix_plugin/scripts/build-dist.sh" 2>&1)
fix_exit=$?
fix_dist="$fix_repo/dist/spec-autopilot"

assert_exit "5a. fixture build completes successfully" 0 "$fix_exit"

if [ -d "$fix_dist/scripts" ]; then
  # 5b. dist 中每个文件都在 manifest 中
  DIST_CLEAN=true
  for f in "$fix_dist/scripts/"*; do
    [ -f "$f" ] || continue
    fname=$(basename "$f")
    if ! parse_manifest | grep -qxF "$fname"; then
      red "  FAIL: 5b. fixture dist contains file not in manifest: $fname"
      FAIL=$((FAIL + 1))
      DIST_CLEAN=false
    fi
  done
  if [ "$DIST_CLEAN" = true ]; then
    green "  PASS: 5b. fixture dist contains only manifest files"
    PASS=$((PASS + 1))
  fi

  # 5c. manifest 中每个文件都在 dist 中
  DIST_COMPLETE=true
  while IFS= read -r entry; do
    if [ ! -f "$fix_dist/scripts/$entry" ]; then
      red "  FAIL: 5c. manifest entry missing from fixture dist: $entry"
      FAIL=$((FAIL + 1))
      DIST_COMPLETE=false
    fi
  done < <(parse_manifest)
  if [ "$DIST_COMPLETE" = true ]; then
    green "  PASS: 5c. all manifest entries present in fixture dist"
    PASS=$((PASS + 1))
  fi

  # 5d. 文件数量精确匹配
  manifest_count=$(parse_manifest | wc -l | xargs)
  dist_count=$(find "$fix_dist/scripts" -maxdepth 1 -type f | wc -l | xargs)
  if [ "$manifest_count" = "$dist_count" ]; then
    green "  PASS: 5d. file count matches (manifest=$manifest_count, dist=$dist_count)"
    PASS=$((PASS + 1))
  else
    red "  FAIL: 5d. file count mismatch (manifest=$manifest_count, dist=$dist_count)"
    FAIL=$((FAIL + 1))
  fi

  # 5e. dev-only 文件确实被排除
  for devfile in mock-event-emitter.js package.json tsconfig.json; do
    if [ -f "$fix_dist/scripts/$devfile" ]; then
      red "  FAIL: 5e. dev-only file leaked into fixture dist: $devfile"
      FAIL=$((FAIL + 1))
    fi
  done
  green "  PASS: 5e. dev-only files excluded from fixture dist"
  PASS=$((PASS + 1))
else
  red "  FAIL: 5. fixture dist/scripts/ not created by build"
  FAIL=$((FAIL + 1))
fi

echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1
exit 0

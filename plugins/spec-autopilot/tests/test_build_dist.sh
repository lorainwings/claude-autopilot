#!/usr/bin/env bash
# test_build_dist.sh — Regression tests for runtime dist completeness
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$TEST_DIR/.." && pwd)"
REPO_ROOT="$(cd "$PLUGIN_ROOT/../.." && pwd)"
source "$TEST_DIR/_test_helpers.sh"

BUILD_SCRIPT="$PLUGIN_ROOT/tools/build-dist.sh"
DIST_DIR="$REPO_ROOT/dist/spec-autopilot"

echo "--- build-dist runtime completeness ---"

output=$(bash "$BUILD_SCRIPT" 2>&1)
exit_code=$?

assert_exit "build-dist.sh completes successfully" 0 "$exit_code"
assert_file_exists "collect-metrics.sh shipped in dist runtime" "$DIST_DIR/scripts/collect-metrics.sh"

if [ ! -e "$DIST_DIR/docs" ] && [ ! -e "$DIST_DIR/tests" ] && [ ! -e "$DIST_DIR/gui" ]; then
  green "  PASS: dist runtime still excludes docs/tests/gui source"
  PASS=$((PASS + 1))
else
  red "  FAIL: dist runtime contains forbidden source directories"
  FAIL=$((FAIL + 1))
fi

assert_contains "build-dist output includes success banner" "$output" "dist/spec-autopilot built"

tmp_root=$(mktemp -d)
trap 'rm -rf "$tmp_root"' EXIT
tmp_repo="$tmp_root/repo"
tmp_plugin="$tmp_repo/plugins/spec-autopilot"
mkdir -p \
  "$tmp_plugin/scripts" \
  "$tmp_plugin/hooks" \
  "$tmp_plugin/skills" \
  "$tmp_plugin/.claude-plugin" \
  "$tmp_plugin/gui" \
  "$tmp_plugin/gui-dist" \
  "$tmp_root/bin"

cp "$BUILD_SCRIPT" "$tmp_plugin/scripts/build-dist.sh"
printf '#!/usr/bin/env bash\necho "collect metrics"\n' > "$tmp_plugin/scripts/collect-metrics.sh"
printf 'collect-metrics.sh\n' > "$tmp_plugin/scripts/.dist-include"
chmod +x "$tmp_plugin/scripts/build-dist.sh" "$tmp_plugin/scripts/collect-metrics.sh"
cat > "$tmp_plugin/hooks/hooks.json" <<'EOF'
{
  "hooks": [
    {
      "hooks": [
        {
          "type": "command",
          "command": "scripts/collect-metrics.sh"
        }
      ]
    }
  ]
}
EOF
printf '{ "name": "spec-autopilot", "version": "test" }\n' > "$tmp_plugin/.claude-plugin/plugin.json"
printf '# CLAUDE\n' > "$tmp_plugin/CLAUDE.md"
printf '{ "name": "gui-fixture" }\n' > "$tmp_plugin/gui/package.json"
printf '<!doctype html><title>fixture</title>\n' > "$tmp_plugin/gui-dist/index.html"
cat > "$tmp_root/bin/bun" <<'EOF'
#!/usr/bin/env bash
echo "bun should not be invoked when gui/node_modules is missing"
exit 99
EOF
chmod +x "$tmp_root/bin/bun"

fallback_output=$(PATH="$tmp_root/bin:$PATH" bash "$tmp_plugin/scripts/build-dist.sh" 2>&1)
fallback_exit=$?
fallback_dist="$tmp_repo/dist/spec-autopilot"

assert_exit "build-dist falls back to checked-in gui-dist when node_modules missing" 0 "$fallback_exit"
assert_contains "fallback path announces checked-in gui-dist" "$fallback_output" "GUI build unavailable"
assert_file_exists "fallback dist still ships collect-metrics.sh" "$fallback_dist/scripts/collect-metrics.sh"
assert_contains "fallback build still emits success banner" "$fallback_output" "dist/spec-autopilot built"

# Test: build failure falls back to gui-dist when available
echo "  build failure fallback test"
fail_root=$(mktemp -d)
fail_repo="$fail_root/repo"
fail_plugin="$fail_repo/plugins/spec-autopilot"
mkdir -p \
  "$fail_plugin/scripts" \
  "$fail_plugin/hooks" \
  "$fail_plugin/skills" \
  "$fail_plugin/.claude-plugin" \
  "$fail_plugin/gui/node_modules" \
  "$fail_plugin/gui-dist" \
  "$fail_root/bin"

cp "$BUILD_SCRIPT" "$fail_plugin/scripts/build-dist.sh"
printf '#!/usr/bin/env bash\necho "collect"\n' > "$fail_plugin/scripts/collect-metrics.sh"
printf 'collect-metrics.sh\n' > "$fail_plugin/scripts/.dist-include"
chmod +x "$fail_plugin/scripts/build-dist.sh" "$fail_plugin/scripts/collect-metrics.sh"
cat > "$fail_plugin/hooks/hooks.json" <<'HEOF'
{ "hooks": [{ "hooks": [{ "type": "command", "command": "scripts/collect-metrics.sh" }] }] }
HEOF
printf '{ "name": "spec-autopilot", "version": "test" }\n' > "$fail_plugin/.claude-plugin/plugin.json"
printf '# CLAUDE\n' > "$fail_plugin/CLAUDE.md"
printf '{ "name": "gui" }\n' > "$fail_plugin/gui/package.json"
printf '<!doctype html><title>f</title>\n' > "$fail_plugin/gui-dist/index.html"
# Fake bun that FAILS the build
cat > "$fail_root/bin/bun" <<'BEOF'
#!/usr/bin/env bash
if [[ "$*" == *"build"* ]]; then
  echo "TypeError: crypto.getRandomValues is not a function" >&2
  exit 1
fi
echo "0.0.0-fake"
BEOF
chmod +x "$fail_root/bin/bun"

fail_output=$(PATH="$fail_root/bin:$PATH" bash "$fail_plugin/scripts/build-dist.sh" 2>&1)
fail_exit=$?
assert_exit "build-dist falls back when bun build fails" 0 "$fail_exit"
assert_contains "build failure fallback message shown" "$fail_output" "GUI build unavailable"
rm -rf "$fail_root"

# Test: fresh-clone scenario — gui-dist only in dist/, NOT in plugins/ (gitignored)
# Simulates: git clone → bun unavailable → must recover gui-dist from dist/
echo "  fresh-clone gui-dist recovery test"
fc_root=$(mktemp -d)
fc_repo="$fc_root/repo"
fc_plugin="$fc_repo/plugins/spec-autopilot"
fc_dist="$fc_repo/dist/spec-autopilot"
mkdir -p \
  "$fc_plugin/scripts" \
  "$fc_plugin/hooks" \
  "$fc_plugin/skills" \
  "$fc_plugin/.claude-plugin" \
  "$fc_plugin/gui" \
  "$fc_dist/gui-dist" \
  "$fc_root/bin"
# NOTE: NO $fc_plugin/gui-dist — simulating fresh clone where it's gitignored

cp "$BUILD_SCRIPT" "$fc_plugin/scripts/build-dist.sh"
printf '#!/usr/bin/env bash\necho "collect"\n' > "$fc_plugin/scripts/collect-metrics.sh"
printf 'collect-metrics.sh\n' > "$fc_plugin/scripts/.dist-include"
chmod +x "$fc_plugin/scripts/build-dist.sh" "$fc_plugin/scripts/collect-metrics.sh"
cat > "$fc_plugin/hooks/hooks.json" <<'FCEOF'
{ "hooks": [{ "hooks": [{ "type": "command", "command": "scripts/collect-metrics.sh" }] }] }
FCEOF
printf '{ "name": "spec-autopilot", "version": "test" }\n' > "$fc_plugin/.claude-plugin/plugin.json"
printf '# CLAUDE\n' > "$fc_plugin/CLAUDE.md"
printf '{ "name": "gui" }\n' > "$fc_plugin/gui/package.json"
# gui-dist ONLY exists in dist/, not plugins/ (fresh-clone scenario)
printf '<!doctype html><title>fc</title>\n' > "$fc_dist/gui-dist/index.html"
# Fake bun that can't build
cat > "$fc_root/bin/bun" <<'FCBEOF'
#!/usr/bin/env bash
echo "bun not available in CI"
exit 99
FCBEOF
chmod +x "$fc_root/bin/bun"

fc_output=$(PATH="$fc_root/bin:$PATH" bash "$fc_plugin/scripts/build-dist.sh" 2>&1)
fc_exit=$?
assert_exit "fresh-clone: build-dist recovers gui-dist from dist/" 0 "$fc_exit"
assert_contains "fresh-clone: recovery message shown" "$fc_output" "Recovered gui-dist from dist/"
assert_contains "fresh-clone: build completes with success banner" "$fc_output" "dist/spec-autopilot built"
rm -rf "$fc_root"

# ── 负向测试: manifest 护栏失败路径 ──

# 辅助函数: 创建最小 fixture 环境
setup_neg_fixture() {
  local root="$1"
  local repo="$root/repo"
  local plugin="$repo/plugins/spec-autopilot"
  mkdir -p \
    "$plugin/scripts" \
    "$plugin/hooks" \
    "$plugin/skills" \
    "$plugin/.claude-plugin" \
    "$plugin/gui" \
    "$plugin/gui-dist" \
    "$root/bin"
  cp "$BUILD_SCRIPT" "$plugin/scripts/build-dist.sh"
  printf '#!/usr/bin/env bash\necho "stub"\n' > "$plugin/scripts/collect-metrics.sh"
  chmod +x "$plugin/scripts/build-dist.sh" "$plugin/scripts/collect-metrics.sh"
  cat > "$plugin/hooks/hooks.json" <<'NEOF'
{ "hooks": [{ "hooks": [{ "type": "command", "command": "scripts/collect-metrics.sh" }] }] }
NEOF
  printf '{ "name": "spec-autopilot", "version": "test" }\n' > "$plugin/.claude-plugin/plugin.json"
  printf '# CLAUDE\n' > "$plugin/CLAUDE.md"
  printf '{ "name": "gui" }\n' > "$plugin/gui/package.json"
  printf '<!doctype html><title>f</title>\n' > "$plugin/gui-dist/index.html"
  cat > "$root/bin/bun" <<'NBEOF'
#!/usr/bin/env bash
echo "0.0.0-stub"
NBEOF
  chmod +x "$root/bin/bun"
  echo "$plugin"
}

# NEG-1. manifest 文件缺失 → exit 1
echo "  neg: manifest missing"
neg1_root=$(mktemp -d)
neg1_plugin=$(setup_neg_fixture "$neg1_root")
# 故意不创建 .dist-include
neg1_output=$(PATH="$neg1_root/bin:$PATH" bash "$neg1_plugin/scripts/build-dist.sh" 2>&1)
neg1_exit=$?
assert_exit "NEG-1. missing manifest → exit 1" 1 "$neg1_exit"
assert_contains "NEG-1. error message mentions manifest" "$neg1_output" "runtime manifest not found"
rm -rf "$neg1_root"

# NEG-2. manifest 条目引用不存在的文件 → exit 1
echo "  neg: manifest references nonexistent file"
neg2_root=$(mktemp -d)
neg2_plugin=$(setup_neg_fixture "$neg2_root")
printf 'collect-metrics.sh\nnonexistent-script.sh\n' > "$neg2_plugin/scripts/.dist-include"
neg2_output=$(PATH="$neg2_root/bin:$PATH" bash "$neg2_plugin/scripts/build-dist.sh" 2>&1)
neg2_exit=$?
assert_exit "NEG-2. nonexistent manifest entry → exit 1" 1 "$neg2_exit"
assert_contains "NEG-2. error message mentions missing entry" "$neg2_output" "manifest entry missing from source"
rm -rf "$neg2_root"

# NEG-3. hooks.json 引用的脚本不在 manifest → exit 1
echo "  neg: hooks reference not in manifest"
neg3_root=$(mktemp -d)
neg3_plugin=$(setup_neg_fixture "$neg3_root")
# manifest 只有 guard.sh，但 hooks.json 引用 collect-metrics.sh
printf '#!/usr/bin/env bash\necho "guard"\n' > "$neg3_plugin/scripts/guard.sh"
chmod +x "$neg3_plugin/scripts/guard.sh"
printf 'guard.sh\n' > "$neg3_plugin/scripts/.dist-include"
neg3_output=$(PATH="$neg3_root/bin:$PATH" bash "$neg3_plugin/scripts/build-dist.sh" 2>&1)
neg3_exit=$?
assert_exit "NEG-3. hooks script not in manifest → exit 1" 1 "$neg3_exit"
assert_contains "NEG-3. error message mentions hooks/dist mismatch" "$neg3_output" "missing from dist"
rm -rf "$neg3_root"

echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1
exit 0

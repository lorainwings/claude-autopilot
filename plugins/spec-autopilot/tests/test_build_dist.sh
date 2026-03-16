#!/usr/bin/env bash
# test_build_dist.sh — Regression tests for runtime dist completeness
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$TEST_DIR/.." && pwd)"
REPO_ROOT="$(cd "$PLUGIN_ROOT/../.." && pwd)"
source "$TEST_DIR/_test_helpers.sh"

BUILD_SCRIPT="$PLUGIN_ROOT/scripts/build-dist.sh"
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
assert_contains "fallback path announces checked-in gui-dist" "$fallback_output" "Skipping GUI rebuild"
assert_file_exists "fallback dist still ships collect-metrics.sh" "$fallback_dist/scripts/collect-metrics.sh"
assert_contains "fallback build still emits success banner" "$fallback_output" "dist/spec-autopilot built"

echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1
exit 0

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

echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1
exit 0

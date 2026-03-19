#!/usr/bin/env bash
# test_routing_overrides.sh — Section 51: Phase 4 routing_overrides dynamic threshold validation
# Tests that Phase 1 checkpoint routing_overrides (Bugfix/Refactor scenarios)
# dynamically adjust Phase 4 L2 Hook thresholds for sad_path and change_coverage.
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../runtime/scripts" && pwd)"
source "$TEST_DIR/_test_helpers.sh"

echo "--- 51. Phase 4 routing_overrides dynamic thresholds ---"

# Self-contained temp directory (avoids repo pollution, ensures find_project_root resolves correctly)
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# Minimal project structure for path resolution
mkdir -p "$TMPDIR/.claude"
mkdir -p "$TMPDIR/openspec/changes/test-fixture/context/phase-results"
echo '{"change":"test-fixture","pid":"99999","started":"2026-01-01T00:00:00Z"}' \
  > "$TMPDIR/openspec/changes/.autopilot-active"

# Phase 1 checkpoint with Bugfix routing_overrides
cat > "$TMPDIR/openspec/changes/test-fixture/context/phase-results/phase-1-test.json" <<'CPEOF'
{
  "status": "ok",
  "summary": "Requirements analyzed",
  "requirement_type": "bugfix",
  "routing_overrides": {
    "sad_path_min_ratio_pct": 40,
    "change_coverage_min_pct": 100,
    "required_test_types": ["unit", "integration"]
  },
  "decisions": [{"point": "fix", "choice": "bugfix"}]
}
CPEOF

# --- Base envelope values ---
# test_counts: unit=10, api=5, e2e=2 → total=17 (≥10 floor)
# test_pyramid: unit_pct=59, e2e_pct=12 (within floors)
# All required Phase 4 fields present.

# 51a. Routing override sad_path=40%: actual ~30% → block
#   unit: 3/10=30% < 40% override → violation
#   (30% would pass default 20% threshold)
exit_code=0
output=$(echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:4 -->\nPhase 4"},"cwd":"'"$TMPDIR"'","tool_response":"Result: {\"status\":\"ok\",\"summary\":\"Tests designed\",\"artifacts\":[\"tests/test_foo.py\"],\"test_counts\":{\"unit\":10,\"api\":5,\"e2e\":2},\"sad_path_counts\":{\"unit\":3,\"api\":1,\"e2e\":1},\"dry_run_results\":{\"unit\":0,\"api\":0,\"e2e\":0},\"test_pyramid\":{\"unit_pct\":59,\"e2e_pct\":12},\"change_coverage\":{\"change_points\":[\"A\",\"B\"],\"tested_points\":[\"A\",\"B\"],\"coverage_pct\":100,\"untested_points\":[]}}"}' \
  | bash "$SCRIPT_DIR/post-task-validator.sh" 2>/dev/null) || exit_code=$?
assert_exit "51a. routing sad_path 30% < override 40% → exit 0" 0 $exit_code
assert_contains "51a. routing sad_path 30% < override 40% → block" "$output" "block"
assert_contains "51a. mentions sad_path" "$output" "sad_path"

# 51b. Routing override sad_path=40%: actual ratio ≥40% → pass
#   unit: 4/10=40%, api: 2/5=40%, e2e: 1/2=50% → all ≥ 40%
exit_code=0
output=$(echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:4 -->\nPhase 4"},"cwd":"'"$TMPDIR"'","tool_response":"Result: {\"status\":\"ok\",\"summary\":\"Tests designed\",\"artifacts\":[\"tests/test_foo.py\"],\"test_counts\":{\"unit\":10,\"api\":5,\"e2e\":2},\"sad_path_counts\":{\"unit\":4,\"api\":2,\"e2e\":1},\"dry_run_results\":{\"unit\":0,\"api\":0,\"e2e\":0},\"test_pyramid\":{\"unit_pct\":59,\"e2e_pct\":12},\"change_coverage\":{\"change_points\":[\"A\",\"B\"],\"tested_points\":[\"A\",\"B\"],\"coverage_pct\":100,\"untested_points\":[]}}"}' \
  | bash "$SCRIPT_DIR/post-task-validator.sh" 2>/dev/null) || exit_code=$?
assert_exit "51b. routing sad_path 40% ≥ override 40% → exit 0" 0 $exit_code
assert_not_contains "51b. routing sad_path 40% ≥ override 40% → no block" "$output" "block"

# 51c. Routing override change_coverage=100%: actual 90% → block
#   90% ≥ default 80% but < 100% override → block
#   sad_path all ≥ 40% → no sad_path block
exit_code=0
output=$(echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:4 -->\nPhase 4"},"cwd":"'"$TMPDIR"'","tool_response":"Result: {\"status\":\"ok\",\"summary\":\"Tests designed\",\"artifacts\":[\"tests/test_foo.py\"],\"test_counts\":{\"unit\":10,\"api\":5,\"e2e\":2},\"sad_path_counts\":{\"unit\":5,\"api\":3,\"e2e\":1},\"dry_run_results\":{\"unit\":0,\"api\":0,\"e2e\":0},\"test_pyramid\":{\"unit_pct\":59,\"e2e_pct\":12},\"change_coverage\":{\"change_points\":[\"A\",\"B\",\"C\",\"D\",\"E\",\"F\",\"G\",\"H\",\"I\",\"J\"],\"tested_points\":[\"A\",\"B\",\"C\",\"D\",\"E\",\"F\",\"G\",\"H\",\"I\"],\"coverage_pct\":90,\"untested_points\":[\"J\"]}}"}' \
  | bash "$SCRIPT_DIR/post-task-validator.sh" 2>/dev/null) || exit_code=$?
assert_exit "51c. routing coverage 90% < override 100% → exit 0" 0 $exit_code
assert_contains "51c. routing coverage 90% < override 100% → block" "$output" "block"
assert_contains "51c. mentions change_coverage" "$output" "change_coverage"

# 51d. Remove routing_overrides → default thresholds apply
#   Default: sad_path ≥ 20%, change_coverage ≥ 80%
#   sad_path: unit=3/10=30%, api=1/5=20%, e2e=1/2=50% → all ≥ 20% → pass
#   coverage: 85% ≥ 80% → pass
cat > "$TMPDIR/openspec/changes/test-fixture/context/phase-results/phase-1-test.json" <<'CPEOF'
{
  "status": "ok",
  "summary": "Requirements analyzed",
  "decisions": [{"point": "scope", "choice": "feature"}]
}
CPEOF

exit_code=0
output=$(echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:4 -->\nPhase 4"},"cwd":"'"$TMPDIR"'","tool_response":"Result: {\"status\":\"ok\",\"summary\":\"Tests designed\",\"artifacts\":[\"tests/test_foo.py\"],\"test_counts\":{\"unit\":10,\"api\":5,\"e2e\":2},\"sad_path_counts\":{\"unit\":3,\"api\":1,\"e2e\":1},\"dry_run_results\":{\"unit\":0,\"api\":0,\"e2e\":0},\"test_pyramid\":{\"unit_pct\":59,\"e2e_pct\":12},\"change_coverage\":{\"change_points\":[\"A\",\"B\"],\"tested_points\":[\"A\",\"B\"],\"coverage_pct\":85,\"untested_points\":[]}}"}' \
  | bash "$SCRIPT_DIR/post-task-validator.sh" 2>/dev/null) || exit_code=$?
assert_exit "51d. default thresholds: 30% sad ≥ 20%, 85% cov ≥ 80% → exit 0" 0 $exit_code
assert_not_contains "51d. default thresholds → no block" "$output" "block"

echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1; exit 0

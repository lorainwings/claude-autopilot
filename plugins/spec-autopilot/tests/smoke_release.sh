#!/usr/bin/env bash
# smoke_release.sh — Stability smoke suite, must pass before release packaging.
# Usage: bash tests/smoke_release.sh
# Exit: 0 if all pass, 1 if any fail
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Release Smoke Suite ==="
echo ""

SMOKE_TESTS=(
  test_build_dist
  test_collect_metrics
  test_phase_context_snapshot
  test_phase_progress
  test_clean_phase_artifacts
  test_common_unit
  test_run_all
  test_poll_gate_decision
)

FAIL_COUNT=0
PASS_COUNT=0
for test_name in "${SMOKE_TESTS[@]}"; do
  test_file="$TEST_DIR/${test_name}.sh"
  if [ ! -f "$test_file" ]; then
    echo "  SKIP: $test_name (file not found)"
    continue
  fi
  if output=$(bash "$test_file" 2>&1); then
    exit_code=0
  else
    exit_code=$?
  fi
  fail=$(echo "$output" | grep -o 'FAIL:' | wc -l | tr -d ' ')
  if [ "$exit_code" -ne 0 ] || [ "$fail" -gt 0 ]; then
    echo "  FAIL: $test_name"
    echo "$output" | grep 'FAIL:' | head -5 || true
    FAIL_COUNT=$((FAIL_COUNT + 1))
  else
    echo "  PASS: $test_name"
    PASS_COUNT=$((PASS_COUNT + 1))
  fi
done

echo ""
echo "=== Smoke Result: $PASS_COUNT/$((PASS_COUNT + FAIL_COUNT)) passed ==="
[ "$FAIL_COUNT" -gt 0 ] && exit 1
exit 0

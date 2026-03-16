#!/usr/bin/env bash
# run_all.sh — Test runner for spec-autopilot modular test suite
#
# Usage:
#   bash tests/run_all.sh                    # Run all tests
#   bash tests/run_all.sh test_json          # Filter by name pattern
#   bash tests/run_all.sh test_syntax test_hooks_json  # Multiple filters
#
# Exit: 0 if all tests pass, 1 if any fail.

set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FILTER="${1:-}"

echo "=== spec-autopilot Modular Test Suite ==="
echo ""

TOTAL_PASS=0
TOTAL_FAIL=0
FAILED_FILES=()
RAN=0

for test_file in "$TEST_DIR"/test_*.sh "$TEST_DIR"/integration/test_*.sh; do
  [ -f "$test_file" ] || continue
  test_name=$(basename "$test_file" .sh)

  # Apply filter if specified
  if [ -n "$FILTER" ]; then
    MATCHED=false
    for pattern in "$@"; do
      if echo "$test_name" | grep -q "$pattern"; then
        MATCHED=true
        break
      fi
    done
    [ "$MATCHED" = "false" ] && continue
  fi

  RAN=$((RAN + 1))

  # Run in subshell for isolation
  if output=$(bash "$test_file" 2>&1); then
    exit_code=0
  else
    exit_code=$?
  fi

  pass=$(echo "$output" | grep -o 'PASS:' | wc -l | tr -d ' ')
  fail=$(echo "$output" | grep -o 'FAIL:' | wc -l | tr -d ' ')
  TOTAL_PASS=$((TOTAL_PASS + pass))

  if [ "$exit_code" -ne 0 ] || [ "$fail" -gt 0 ]; then
    if [ "$fail" -eq 0 ]; then
      fail=1
    fi
    TOTAL_FAIL=$((TOTAL_FAIL + fail))
    FAILED_FILES+=("$test_name")
  fi

  echo "$output"
  echo ""
done

# Summary
echo "============================================"
echo "Test Summary: $RAN files, $TOTAL_PASS passed, $TOTAL_FAIL failed"

if [ ${#FAILED_FILES[@]} -gt 0 ]; then
  echo ""
  echo "Failed test files:"
  for f in "${FAILED_FILES[@]}"; do
    echo "  - $f"
  done
fi

echo "============================================"

[ "$TOTAL_FAIL" -gt 0 ] && exit 1
[ "$RAN" -eq 0 ] && { echo "WARNING: No test files found or matched"; exit 1; }
exit 0

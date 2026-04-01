#!/usr/bin/env bash
# run_all.sh — Test runner for spec-autopilot modular test suite
#
# Usage:
#   bash tests/run_all.sh                    # Run all tests
#   bash tests/run_all.sh test_json          # Filter by name pattern
#   bash tests/run_all.sh --layer behavior   # Run only behavior layer
#   bash tests/run_all.sh --strict-docs      # Fail on docs_consistency failures
#
# Exit: 0 if all tests pass, 1 if any fail.

set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 解析参数
FILTER=""
LAYER_FILTER=""
STRICT_DOCS=false
POSITIONAL_ARGS=()

while [ $# -gt 0 ]; do
  case "$1" in
    --layer)
      LAYER_FILTER="${2:-}"
      shift 2
      ;;
    --strict-docs)
      STRICT_DOCS=true
      shift
      ;;
    *)
      POSITIONAL_ARGS+=("$1")
      shift
      ;;
  esac
done

# 恢复位置参数作为 filter
if [ ${#POSITIONAL_ARGS[@]} -gt 0 ]; then
  set -- "${POSITIONAL_ARGS[@]}"
else
  set --
fi
FILTER="${1:-}"

echo "=== spec-autopilot Modular Test Suite ==="
if [ -n "$LAYER_FILTER" ]; then
  echo "Layer filter: $LAYER_FILTER"
fi
if [ "$STRICT_DOCS" = "true" ]; then
  echo "Strict docs mode: enabled"
fi
echo ""

TOTAL_PASS=0
TOTAL_FAIL=0
FAILED_FILES=()
RAN=0

# 分层统计
CONTRACT_PASS=0
CONTRACT_FAIL=0
BEHAVIOR_PASS=0
BEHAVIOR_FAIL=0
DOCS_PASS=0
DOCS_FAIL=0

for test_file in "$TEST_DIR"/test_*.sh "$TEST_DIR"/integration/test_*.sh; do
  [ -f "$test_file" ] || continue
  test_name=$(basename "$test_file" .sh)

  # 读取测试层标记
  TEST_LAYER=$(grep -m1 '^# TEST_LAYER:' "$test_file" 2>/dev/null | sed 's/^# TEST_LAYER: *//' || echo "behavior")

  # Layer filter
  if [ -n "$LAYER_FILTER" ] && [ "$TEST_LAYER" != "$LAYER_FILTER" ]; then
    continue
  fi

  # Apply name filter if specified
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

  # 分层统计
  case "$TEST_LAYER" in
    contract)
      CONTRACT_PASS=$((CONTRACT_PASS + pass))
      CONTRACT_FAIL=$((CONTRACT_FAIL + fail))
      ;;
    behavior)
      BEHAVIOR_PASS=$((BEHAVIOR_PASS + pass))
      BEHAVIOR_FAIL=$((BEHAVIOR_FAIL + fail))
      ;;
    docs_consistency)
      DOCS_PASS=$((DOCS_PASS + pass))
      DOCS_FAIL=$((DOCS_FAIL + fail))
      ;;
  esac

  # docs_consistency 失败不阻断（除非 --strict-docs）
  if [ "$exit_code" -ne 0 ] || [ "$fail" -gt 0 ]; then
    if [ "$fail" -eq 0 ]; then
      fail=1
    fi

    if [ "$TEST_LAYER" = "docs_consistency" ] && [ "$STRICT_DOCS" = "false" ]; then
      # docs 层失败仅记录，不计入总失败数
      echo "$output"
      echo "[INFO] docs_consistency 测试失败（非阻断）: $test_name"
      echo ""
    else
      TOTAL_FAIL=$((TOTAL_FAIL + fail))
      FAILED_FILES+=("$test_name")
      echo "$output"
      echo ""
    fi
  else
    echo "$output"
    echo ""
  fi
done

# Summary
echo "============================================"
echo "Test Summary: $RAN files, $TOTAL_PASS passed, $TOTAL_FAIL failed"
echo ""
echo "By Layer:"
echo "  contract:         $CONTRACT_PASS passed, $CONTRACT_FAIL failed"
echo "  behavior:         $BEHAVIOR_PASS passed, $BEHAVIOR_FAIL failed"
echo "  docs_consistency: $DOCS_PASS passed, $DOCS_FAIL failed"

if [ ${#FAILED_FILES[@]} -gt 0 ]; then
  echo ""
  echo "Failed test files:"
  for f in "${FAILED_FILES[@]}"; do
    echo "  - $f"
  done
fi

echo "============================================"

# Fail-closed: verify tests haven't polluted the main repo's core.hooksPath
REPO_ROOT="$(cd "$TEST_DIR/../../.." && pwd)"
_HOOKS_PATH=$(git -C "$REPO_ROOT" config --local core.hooksPath 2>/dev/null || echo "")
if [ "$_HOOKS_PATH" = "/dev/null" ]; then
  echo ""
  echo "FATAL: Test suite leaked core.hooksPath=/dev/null into main repo!"
  echo "  Auto-restoring: core.hooksPath = .githooks"
  git -C "$REPO_ROOT" config --local core.hooksPath .githooks
  exit 1
fi

[ "$TOTAL_FAIL" -gt 0 ] && exit 1
[ "$RAN" -eq 0 ] && { echo "WARNING: No test files found or matched"; exit 1; }
exit 0

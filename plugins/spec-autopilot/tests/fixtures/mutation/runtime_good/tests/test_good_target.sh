#!/usr/bin/env bash
# test_good_target.sh — 强测试：正反路径全覆盖
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$SCRIPT_DIR/../scripts/good_target.sh"

# 正路径必须 exit 0
if ! bash "$TARGET" ok >/dev/null 2>&1; then
  echo "FAIL: ok should exit 0"
  exit 1
fi

# 反路径必须 exit 非 0
if bash "$TARGET" bad >/dev/null 2>&1; then
  echo "FAIL: bad should exit non-zero"
  exit 1
fi

echo "PASS"
exit 0

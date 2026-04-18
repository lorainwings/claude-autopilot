#!/usr/bin/env bash
# strong test: 多重断言
set -uo pipefail

OUT=$(bash "$(dirname "$0")/../scripts/s1.sh" hello)

# 断言 1: 输出非空
if [ -z "$OUT" ]; then
  echo "FAIL: empty"
  exit 1
fi

# 断言 2: 输出匹配
if [ "$OUT" != "hello" ]; then
  echo "FAIL: mismatch"
  exit 1
fi

# 断言 3: 长度校验
if [ "${#OUT}" -ne 5 ]; then
  echo "FAIL: length"
  exit 1
fi

# 断言 4: 模式校验
case "$OUT" in
  hello) ;;
  *) echo "FAIL: pattern"; exit 1 ;;
esac

echo "PASS"

#!/usr/bin/env bash
# test_sigpipe_regression.sh — 回归测试: 确保 assert_contains/assert_not_contains
# 在 set -o pipefail 下不会因 SIGPIPE 产生假红。
#
# 背景: echo "$large_content" | grep -q "pattern" 在 pipefail 模式下，
# grep -q 匹配后立即关闭 stdin，echo 收到 SIGPIPE 导致 exit 141，
# pipeline 整体返回非零。这在 Ubuntu/GNU bash 上稳定复现。

set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_test_helpers.sh
source "$TEST_DIR/_test_helpers.sh"

echo "=== SIGPIPE Regression Tests ==="
echo ""

# ── 1. 大字符串的 assert_contains 不应假红 ──
echo "── 1. Large string assert_contains ──"
# 生成一个超过 pipe buffer (通常 64KB) 的字符串
LARGE_CONTENT=$(python3 -c "print('x' * 100000 + 'NEEDLE' + 'y' * 100000)")
assert_contains "1a. large string contains NEEDLE" "$LARGE_CONTENT" "NEEDLE"

# ── 2. 大字符串的 assert_not_contains 不应假红 ──
echo "── 2. Large string assert_not_contains ──"
LARGE_NO_NEEDLE=$(python3 -c "print('x' * 200000)")
assert_not_contains "2a. large string correctly missing ABSENT" "$LARGE_NO_NEEDLE" "ABSENT"

# ── 3. 多行内容 ──
echo "── 3. Multiline content ──"
MULTILINE=$(printf '%s\n' "line1" "line2 with target" "line3" "line4" "line5")
assert_contains "3a. multiline contains target" "$MULTILINE" "target"
assert_not_contains "3b. multiline missing absent" "$MULTILINE" "absent"

# ── 4. 空字符串边界 ──
echo "── 4. Edge cases ──"
assert_not_contains "4a. empty haystack missing anything" "" "something"

# ── 5. 含特殊字符的内容 ──
echo "── 5. Special characters ──"
SPECIAL='{"status":"blocked","reason":"Phase 4 failing_signal detected"}'
assert_contains "5a. JSON contains failing_signal" "$SPECIAL" "failing_signal"
assert_contains "5b. JSON contains blocked" "$SPECIAL" "blocked"

# ── 6. assert_file_contains 不受 SIGPIPE 影响 (直接 grep 文件) ──
echo "── 6. assert_file_contains ──"
TMPFILE=$(mktemp)
python3 -c "print('x' * 100000 + 'FILE_NEEDLE' + 'y' * 100000)" > "$TMPFILE"
assert_file_contains "6a. large file contains FILE_NEEDLE" "$TMPFILE" "FILE_NEEDLE"
assert_file_not_contains "6b. large file missing ABSENT" "$TMPFILE" "ABSENT"
rm -f "$TMPFILE"

echo ""
echo "============================================"
echo "SIGPIPE Regression: $PASS passed, $FAIL failed"
echo "============================================"

[ "$FAIL" -gt 0 ] && exit 1
exit 0

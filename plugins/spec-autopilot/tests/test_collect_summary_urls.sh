#!/usr/bin/env bash
# test_collect_summary_urls.sh — collect-summary-urls.sh 自愈与地址收集
# Production target: runtime/scripts/collect-summary-urls.sh
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../runtime/scripts" && pwd)"
source "$TEST_DIR/_test_helpers.sh"

echo "--- collect-summary-urls.sh: 自愈 + 确定性地址收集 ---"

SCRIPT="$SCRIPT_DIR/collect-summary-urls.sh"

# Helper: create fresh change dir
mk_change() {
  local tmp
  tmp=$(mktemp -d)
  mkdir -p "$tmp/openspec/changes/smoke/context"
  mkdir -p "$tmp/.claude"
  echo "$tmp"
}

# 1. 空 change_dir → 不崩，输出合法 JSON，Allure URL 空
tmp1=$(mk_change)
out1=$("$SCRIPT" "$tmp1/openspec/changes/smoke" 4040 2>/dev/null)
exit1=$?
assert_exit "1. 空 change_dir → exit 0" 0 $exit1
assert_contains "1. 输出含 allure_url 字段" "$out1" '"allure_url"'
assert_contains "1. allure_url 为空字符串 (无产物)" "$out1" '"allure_url": ""'
assert_contains "1. 输出含 services 字段" "$out1" '"services"'
rm -rf "$tmp1"

# 2. 僵尸 allure-preview.json (PID 死) → 自愈后清空 stale URL
tmp2=$(mk_change)
cat >"$tmp2/openspec/changes/smoke/context/allure-preview.json" <<EOF
{"url":"http://localhost:59999","pid":99999,"port":59999}
EOF
out2=$("$SCRIPT" "$tmp2/openspec/changes/smoke" 4040 2>/dev/null)
exit2=$?
assert_exit "2. 僵尸 preview → exit 0" 0 $exit2
assert_not_contains "2. stale URL 已被清理" "$out2" "http://localhost:59999"
assert_contains "2. allure_url 回到空字符串" "$out2" '"allure_url": ""'
rm -rf "$tmp2"

# 3. 缺 change_dir 参数 → 不崩 (信息性脚本)
exit3=0
out3=$("$SCRIPT" 2>/dev/null) || exit3=$?
assert_exit "3. 无参数 → exit 0 (信息性脚本)" 0 $exit3

# 4. change_dir 存在 + autopilot.config.yaml 含 services → services 字典非空
tmp4=$(mk_change)
cat >"$tmp4/.claude/autopilot.config.yaml" <<EOF
gui:
  port: 19527
services:
  backend: "http://localhost:8080/health"
  ws: "ws://localhost:8081"
EOF
out4=$("$SCRIPT" "$tmp4/openspec/changes/smoke" 4040 2>/dev/null)
exit4=$?
assert_exit "4. 带 services 配置 → exit 0" 0 $exit4
assert_contains "4. services 含 backend" "$out4" "backend"
assert_contains "4. services 含 ws" "$out4" "ws"
rm -rf "$tmp4"

# 5. 输出永远是单行合法 JSON (可被 python3 json.loads 解析)
tmp5=$(mk_change)
out5=$("$SCRIPT" "$tmp5/openspec/changes/smoke" 4040 2>/dev/null)
exit5=$?
parse_check=$(echo "$out5" | python3 -c "import json, sys; json.loads(sys.stdin.read()); print('VALID')" 2>&1)
assert_exit "5. 输出合法 JSON → python 可 parse" 0 $exit5
assert_contains "5. python json.loads 成功" "$parse_check" "VALID"
rm -rf "$tmp5"

echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1
exit 0

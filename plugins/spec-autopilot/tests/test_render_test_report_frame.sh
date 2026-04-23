#!/usr/bin/env bash
# test_render_test_report_frame.sh — render-test-report-frame.sh 线框渲染与 Allure URL 展示
# Production target: runtime/scripts/render-test-report-frame.sh
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../runtime/scripts" && pwd)"
source "$TEST_DIR/_test_helpers.sh"

echo "--- render-test-report-frame.sh: Test Report 线框 + Allure URL 行 ---"

SCRIPT="$SCRIPT_DIR/render-test-report-frame.sh"

mk_change() {
  local tmp
  tmp=$(mktemp -d)
  mkdir -p "$tmp/openspec/changes/smoke/context/phase-results"
  mkdir -p "$tmp/openspec/changes/smoke/reports"
  mkdir -p "$tmp/.claude"
  echo "$tmp"
}

# 1. 无 change_dir 参数 → exit 0 (信息性脚本)
exit1=0
out1=$("$SCRIPT" 2>/dev/null) || exit1=$?
assert_exit "1. 无参数 → exit 0" 0 $exit1

# 2. 空 change_dir (无 phase-6 checkpoint / 无 allure-results) → 展示线框 + Allure unavailable
tmp2=$(mk_change)
out2=$("$SCRIPT" "$tmp2/openspec/changes/smoke" "Phase 4 Test Report" 4040 2>/dev/null)
exit2=$?
assert_exit "2. 空 change_dir → exit 0" 0 $exit2
assert_contains "2. 输出含线框顶边 ╭" "$out2" '╭──'
assert_contains "2. 输出含线框底边 ╰" "$out2" '╰──'
assert_contains "2. 含 Phase 4 标题" "$out2" "Phase 4 Test Report"
assert_contains "2. 含 Allure 行" "$out2" "Allure"
assert_contains "2. Allure 行展示 unavailable" "$out2" "unavailable"
assert_contains "2. 状态展示 pending" "$out2" "pending"
rm -rf "$tmp2"

# 3. 带 phase-6-report.json checkpoint → 展示真实统计
tmp3=$(mk_change)
cat >"$tmp3/openspec/changes/smoke/context/phase-results/phase-6-report.json" <<'EOF'
{
  "report_format": "allure",
  "suite_results": [
    {"suite": "unit", "total": 100, "passed": 95, "failed": 3, "skipped": 2},
    {"suite": "e2e", "total": 20, "passed": 19, "failed": 1, "skipped": 0}
  ]
}
EOF
out3=$("$SCRIPT" "$tmp3/openspec/changes/smoke" "Test Report" 4040 2>/dev/null)
exit3=$?
assert_exit "3. 带 checkpoint → exit 0" 0 $exit3
assert_contains "3. Total 合并为 120" "$out3" "Total   120"
assert_contains "3. Passed 合并为 114" "$out3" "Passed  114"
assert_contains "3. Failed 合并为 4" "$out3" "Failed  4"
assert_contains "3. Pass Rate 95.0%" "$out3" "95.0%"
rm -rf "$tmp3"

# 4. 带活进程的 allure-preview.json → 展示 URL
tmp4=$(mk_change)
cat >"$tmp4/openspec/changes/smoke/context/phase-results/phase-6-report.json" <<'EOF'
{"suite_results": [{"suite": "unit", "total": 10, "passed": 10, "failed": 0, "skipped": 0}]}
EOF
cat >"$tmp4/openspec/changes/smoke/context/allure-preview.json" <<EOF
{"url": "http://localhost:4041", "pid": $$, "port": 4041}
EOF
out4=$("$SCRIPT" "$tmp4/openspec/changes/smoke" "Phase 5 TDD Test Report" 4040 2>/dev/null)
exit4=$?
assert_exit "4. 带活 PID → exit 0" 0 $exit4
assert_contains "4. 展示 Phase 5 TDD 标题" "$out4" "Phase 5 TDD Test Report"
assert_contains "4. Allure 行含真实 URL" "$out4" "http://localhost:4041"
assert_not_contains "4. 不再展示 unavailable" "$out4" "Allure  unavailable"
rm -rf "$tmp4"

# 5. 僵尸 allure-preview.json (PID 99999 死进程) → Allure 行回落到 unavailable
tmp5=$(mk_change)
cat >"$tmp5/openspec/changes/smoke/context/allure-preview.json" <<'EOF'
{"url": "http://localhost:59999", "pid": 99999, "port": 59999}
EOF
out5=$("$SCRIPT" "$tmp5/openspec/changes/smoke" "Test Report" 4040 2>/dev/null)
exit5=$?
assert_exit "5. 僵尸 preview → exit 0" 0 $exit5
assert_not_contains "5. 不展示僵尸 URL" "$out5" "http://localhost:59999"
assert_contains "5. Allure 行回落 unavailable" "$out5" "unavailable"
rm -rf "$tmp5"

# 6. 扫描 allure-results/tdd 子目录 → 聚合 RED/GREEN/REFACTOR 结果
tmp6=$(mk_change)
mkdir -p "$tmp6/openspec/changes/smoke/reports/allure-results/tdd/red"
mkdir -p "$tmp6/openspec/changes/smoke/reports/allure-results/tdd/green"
# 构造假的 Allure result.json 文件
cat >"$tmp6/openspec/changes/smoke/reports/allure-results/tdd/red/a-result.json" <<'EOF'
{"name": "test_red_1", "status": "failed"}
EOF
cat >"$tmp6/openspec/changes/smoke/reports/allure-results/tdd/green/b-result.json" <<'EOF'
{"name": "test_green_1", "status": "passed"}
EOF
cat >"$tmp6/openspec/changes/smoke/reports/allure-results/tdd/green/c-result.json" <<'EOF'
{"name": "test_green_2", "status": "passed"}
EOF
out6=$("$SCRIPT" "$tmp6/openspec/changes/smoke" "Phase 5 TDD Test Report" 4040 2>/dev/null)
exit6=$?
assert_exit "6. 扫描 tdd 子目录 → exit 0" 0 $exit6
assert_contains "6. Total 聚合为 3" "$out6" "Total   3"
assert_contains "6. Passed 聚合为 2" "$out6" "Passed  2"
assert_contains "6. Failed 聚合为 1" "$out6" "Failed  1"
rm -rf "$tmp6"

# 7. 无 allure CLI / 无结果 → 必须附加调试提示
tmp7=$(mk_change)
out7=$("$SCRIPT" "$tmp7/openspec/changes/smoke" "Test Report" 4040 2>/dev/null)
exit7=$?
assert_exit "7. 空场景 → exit 0" 0 $exit7
assert_contains "7. 附加 [ALLURE] 调试提示" "$out7" "[ALLURE]"
assert_contains "7. 调试提示含重启命令" "$out7" "start-allure-serve.sh"
rm -rf "$tmp7"

echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1
exit 0

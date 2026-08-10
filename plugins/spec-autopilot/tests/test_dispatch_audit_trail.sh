#!/usr/bin/env bash
# test_dispatch_audit_trail.sh — Section 58: 派发审计轨迹（plan / actual / reconcile）
#
# 背景：这条链路此前是死代码 —— generate-dispatch-plan.sh 在 python3 -c 下引用
# __file__，每次调用必抛 NameError（退出码 1，产物零字节），而三个脚本又互相引用、
# 无任何外部调用方，所以崩溃从未被发现。
# 更糟的是 plan 缺失时下游报 reconcile_status="ok" —— 上游全崩、下游绿灯。
#
# 本文件验证：
#   1. plan 能真正生成（__file__ 修复）
#   2. plan 缺失时 reconcile_status 为 unavailable，绝不为 ok
#   3. plan/actual 一致 → ok；不一致 → drift
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../runtime/scripts" && pwd)"
source "$TEST_DIR/_test_helpers.sh"

echo "--- 58. dispatch audit trail (plan / actual / reconcile) ---"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

CHANGE=test-change
CTX="$TMPDIR/openspec/changes/$CHANGE/context"
mkdir -p "$CTX"

PLAN="$CTX/dispatch-plan.json"
ACTUAL="$CTX/dispatch-actual.json"

json_field() {
  # Args: file field
  python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get(sys.argv[2],''))" "$1" "$2" 2>/dev/null || echo ""
}

# === 58a. 正常路径：plan 生成成功（此前必崩）===
rm -f "$PLAN" "$ACTUAL"
exit_code=0
bash "$SCRIPT_DIR/generate-dispatch-plan.sh" "$TMPDIR" "$CHANGE" spec-analyst 2 >/dev/null 2>&1 || exit_code=$?
assert_exit "58a. generate-dispatch-plan → exit 0" 0 $exit_code
assert_file_exists "58a. dispatch-plan.json created" "$PLAN"
requested=$(json_field "$PLAN" requested_agent)
assert_contains "58a. plan records the requested agent" "$requested" "spec-analyst"

# === 58b. 回归钉子：脚本不得再出现 NameError ===
out=$(bash "$SCRIPT_DIR/generate-dispatch-plan.sh" "$TMPDIR" "$CHANGE" spec-analyst 2 2>&1)
assert_not_contains "58b. no NameError from python3 -c" "$out" "NameError"
assert_not_contains "58b. no __file__ reference error" "$out" "__file__"

# === 58c. 正常路径：plan 与 actual 一致 → reconcile_status=ok ===
bash "$SCRIPT_DIR/generate-dispatch-actual.sh" "$TMPDIR" "$CHANGE" spec-analyst 2 >/dev/null 2>&1
status=$(json_field "$ACTUAL" reconcile_status)
assert_contains "58c. matching plan/actual → ok" "$status" "ok"
plan_avail=$(json_field "$ACTUAL" plan_available)
assert_contains "58c. plan_available is True" "$plan_avail" "True"

# === 58d. 核心修复：plan 缺失 → unavailable，绝不 ok ===
rm -f "$PLAN" "$ACTUAL"
bash "$SCRIPT_DIR/generate-dispatch-actual.sh" "$TMPDIR" "$CHANGE" spec-analyst 2 >/dev/null 2>&1
status=$(json_field "$ACTUAL" reconcile_status)
assert_contains "58d. missing plan → unavailable" "$status" "unavailable"
if [ "$status" = "ok" ]; then
  red "  FAIL: 58d. missing plan must never report ok"
  FAIL=$((FAIL + 1))
else
  green "  PASS: 58d. missing plan must never report ok"
  PASS=$((PASS + 1))
fi

# === 58e. 错误路径：actual 与 plan 不一致 → drift ===
rm -f "$PLAN" "$ACTUAL"
bash "$SCRIPT_DIR/generate-dispatch-plan.sh" "$TMPDIR" "$CHANGE" spec-analyst 2 >/dev/null 2>&1
bash "$SCRIPT_DIR/generate-dispatch-actual.sh" "$TMPDIR" "$CHANGE" some-other-agent 2 >/dev/null 2>&1
status=$(json_field "$ACTUAL" reconcile_status)
assert_contains "58e. agent mismatch → drift" "$status" "drift"

# === 58f. reconcile-dispatch.sh 空输入 → unavailable（不再报 ok）===
EMPTY="$TMPDIR/empty-proj"
mkdir -p "$EMPTY/openspec/changes/$CHANGE/context"
out=$(bash "$SCRIPT_DIR/reconcile-dispatch.sh" "$EMPTY" "$CHANGE" 2>/dev/null)
assert_contains "58f. no plan files → unavailable" "$out" '"status": "unavailable"'
assert_not_contains "58f. must not claim ok" "$out" '"status": "ok"'

# === 58g. 边界：context 目录不存在 → unavailable ===
out=$(bash "$SCRIPT_DIR/reconcile-dispatch.sh" "$TMPDIR/nonexistent" "$CHANGE" 2>/dev/null)
assert_contains "58g. missing context dir → unavailable" "$out" "unavailable"

# === 58h. 接线检查：dispatch SKILL 必须成对调用 plan/actual ===
SKILL_MD="$TEST_DIR/../skills/autopilot-dispatch/SKILL.md"
skill_body=$(cat "$SKILL_MD")
assert_contains "58h. SKILL wires generate-dispatch-plan.sh" "$skill_body" "generate-dispatch-plan.sh"
assert_contains "58h. SKILL wires generate-dispatch-actual.sh" "$skill_body" "generate-dispatch-actual.sh"

echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1
exit 0

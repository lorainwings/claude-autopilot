#!/usr/bin/env bash
# test_l2_audit_fail_closed.sh — Section 55: Phase 5 L2 test-driven evidence gate
#
# 背景：旧实现只校验编号最大的那个 task checkpoint（`ls | tail -1`），
# 且拿到 warn 只 echo 到 stderr（注释自认 "Warn only — does not deny"），
# 校验脚本崩溃时还 `|| echo '{"status":"warn"}'` 兜底 —— 于是
# "证据缺失" / "根本没验证" 与 "验证通过" 三者被合并为同一个静默放行。
#
# 本文件验证：
#   1. 全量校验：非最后一个 task 缺证据同样 deny
#   2. fail-closed：校验脚本失败 / 输出不可解析 → deny（无法验证 ≠ 通过）
#   3. 正常路径：全部 task 证据齐全 → 放行
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../runtime/scripts" && pwd)"
source "$TEST_DIR/_test_helpers.sh"

echo "--- 55. Phase 5 L2 evidence gate (fail-closed, all tasks) ---"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

CHANGE=test-fixture
CTX="$TMPDIR/openspec/changes/$CHANGE/context"
PR="$CTX/phase-results"
TASKS="$PR/phase5-tasks"
mkdir -p "$TASKS" "$TMPDIR/.claude"

echo '{"change":"'"$CHANGE"'","pid":"99999","started":"2026-01-01T00:00:00Z","mode":"full"}' \
  >"$TMPDIR/openspec/changes/.autopilot-active"

# 前驱 Phase 1-4 checkpoint 齐备，使门禁走到 L2 审计段
for p in 1 2 3 4; do
  echo '{"status":"ok","summary":"done"}' >"$PR/phase-${p}-test.json"
done

# 目标：派发 Phase 6（TARGET_PHASE=6 会先过 Phase 5 相关校验）
# 这里用 Phase 5 作为 target 触发 L2 审计段（脚本内条件为 TARGET_PHASE -eq 5）
mk_task() {
  # Args: task_number  evidence_json_or_empty
  local n="$1" ev="$2"
  if [ -z "$ev" ]; then
    echo '{"status":"ok","task":"'"$n"'"}' >"$TASKS/task-${n}.json"
  else
    echo '{"status":"ok","task":"'"$n"'","test_driven_evidence":'"$ev"'}' >"$TASKS/task-${n}.json"
  fi
}

# 真实 schema 见 verify-test-driven-l2.sh：必须是 L2_main_thread 层且 red/green 均已验证
GOOD_EV='{"red_verified":true,"green_verified":true,"verification_layer":"L2_main_thread"}'

dispatch_input() {
  echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:5 -->继续实现","subagent_type":"autopilot-phase5-implement"},"cwd":"'"$TMPDIR"'"}'
}

run_gate() {
  dispatch_input | AUTOPILOT_PROJECT_ROOT="$TMPDIR" bash "$SCRIPT_DIR/check-predecessor-checkpoint.sh" 2>/dev/null
}

# === 55a. 正常路径：全部 task 证据齐全 → 放行 ===
rm -f "$TASKS"/task-*.json
mk_task 1 "$GOOD_EV"
mk_task 2 "$GOOD_EV"
exit_code=0
output=$(run_gate) || exit_code=$?
assert_exit "55a. all tasks have evidence → exit 0" 0 $exit_code
assert_not_contains "55a. complete evidence → no deny" "$output" "deny"

# === 55b. 核心回归：缺证据的是第 1 个 task（不是最后一个）→ 必须 deny ===
# 旧实现只看 tail -1（task-2），task-1 的缺失被完全忽略。
rm -f "$TASKS"/task-*.json
mk_task 1 ""            # 缺 test_driven_evidence
mk_task 2 "$GOOD_EV"    # 最后一个是好的
exit_code=0
output=$(run_gate) || exit_code=$?
assert_exit "55b. non-last task missing evidence → exit 0" 0 $exit_code
assert_contains "55b. non-last task missing evidence → deny" "$output" "deny"
assert_contains "55b. deny names the offending task" "$output" "task-1.json"

# === 55c. 边界：最后一个 task 缺证据 → deny（旧实现唯一能抓到的情形） ===
rm -f "$TASKS"/task-*.json
mk_task 1 "$GOOD_EV"
mk_task 2 ""
exit_code=0
output=$(run_gate) || exit_code=$?
assert_exit "55c. last task missing evidence → exit 0" 0 $exit_code
assert_contains "55c. last task missing evidence → deny" "$output" "deny"
assert_contains "55c. deny names the offending task" "$output" "task-2.json"

# === 55d. 多个 task 同时缺证据 → deny 且计数正确 ===
rm -f "$TASKS"/task-*.json
mk_task 1 ""
mk_task 2 ""
mk_task 3 "$GOOD_EV"
exit_code=0
output=$(run_gate) || exit_code=$?
assert_contains "55d. multiple missing → deny" "$output" "deny"
assert_contains "55d. reports the failure count" "$output" "2 task checkpoint(s)"

# === 55e. 错误路径 fail-closed：校验脚本不可用 → deny，不得静默放行 ===
# 用一个只有坏 verify 脚本的影子 SCRIPT_DIR，模拟脚本崩溃
SHADOW="$TMPDIR/shadow-scripts"
mkdir -p "$SHADOW"
for f in "$SCRIPT_DIR"/*.sh "$SCRIPT_DIR"/*.py; do
  [ -e "$f" ] && ln -sf "$f" "$SHADOW/$(basename "$f")"
done
rm -f "$SHADOW/verify-test-driven-l2.sh"
printf '#!/usr/bin/env bash\nexit 3\n' >"$SHADOW/verify-test-driven-l2.sh"
chmod +x "$SHADOW/verify-test-driven-l2.sh"

rm -f "$TASKS"/task-*.json
mk_task 1 "$GOOD_EV"   # 证据本身是好的，但校验脚本崩溃
exit_code=0
output=$(dispatch_input | AUTOPILOT_PROJECT_ROOT="$TMPDIR" bash "$SHADOW/check-predecessor-checkpoint.sh" 2>/dev/null) || exit_code=$?
assert_exit "55e. verify script crash → exit 0" 0 $exit_code
assert_contains "55e. crash must deny (fail-closed)" "$output" "deny"
assert_contains "55e. deny says it could not verify" "$output" "unable to verify"

# === 55f. 错误路径 fail-closed：校验输出不可解析 → deny ===
printf '#!/usr/bin/env bash\necho "not json at all"\n' >"$SHADOW/verify-test-driven-l2.sh"
chmod +x "$SHADOW/verify-test-driven-l2.sh"
exit_code=0
output=$(dispatch_input | AUTOPILOT_PROJECT_ROOT="$TMPDIR" bash "$SHADOW/check-predecessor-checkpoint.sh" 2>/dev/null) || exit_code=$?
assert_exit "55f. unparseable verify output → exit 0" 0 $exit_code
assert_contains "55f. unparseable output must deny" "$output" "deny"

# === 55g. 无 task checkpoint 目录 → 不误拦（该情形由别的门禁负责） ===
rm -rf "$TASKS"
exit_code=0
output=$(run_gate) || exit_code=$?
assert_exit "55g. no task dir → exit 0" 0 $exit_code
assert_not_contains "55g. no task dir → no spurious deny" "$output" "deny"

echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1
exit 0

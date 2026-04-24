#!/usr/bin/env bash
# test_tdd_parallel_l2.sh — verify-parallel-tdd-l2.sh 的测试套件
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$TEST_DIR/../runtime/scripts"
SCRIPT="$SCRIPT_DIR/verify-parallel-tdd-l2.sh"

source "$TEST_DIR/_test_helpers.sh"
source "$TEST_DIR/_fixtures.sh"

setup_autopilot_fixture

echo "=== verify-parallel-tdd-l2.sh 测试 ==="

# --- 1. 无参数 → exit 1 ---
echo "--- 1. 无参数 ---"
OUTPUT=$(bash "$SCRIPT" 2>&1 || true)
EXITCODE=0
bash "$SCRIPT" >/dev/null 2>&1 || EXITCODE=$?
assert_exit "1. 无参数退出码" 1 "$EXITCODE"
assert_contains "1. 无参数包含错误信息" "$OUTPUT" "缺少必需参数"

# --- 2. worktree 路径不存在 → exit 1 ---
echo "--- 2. worktree 路径不存在 ---"
TMPDIR_BASE=$(mktemp -d)
FAKE_CP="$TMPDIR_BASE/cp.json"
echo '{"tdd_cycle":[]}' >"$FAKE_CP"
EXITCODE=0
OUTPUT=$(bash "$SCRIPT" --worktree-path "/nonexistent/path" --test-command "true" --task-checkpoint "$FAKE_CP" 2>&1 || true)
bash "$SCRIPT" --worktree-path "/nonexistent/path" --test-command "true" --task-checkpoint "$FAKE_CP" >/dev/null 2>&1 || EXITCODE=$?
assert_exit "2. worktree 不存在退出码" 1 "$EXITCODE"
assert_contains "2. worktree 不存在包含路径" "$OUTPUT" "worktree 路径不存在"
rm -rf "$TMPDIR_BASE"

# --- 3. checkpoint 文件不存在 → exit 1 ---
echo "--- 3. checkpoint 文件不存在 ---"
TMPDIR_BASE=$(mktemp -d)
EXITCODE=0
OUTPUT=$(bash "$SCRIPT" --worktree-path "$TMPDIR_BASE" --test-command "true" --task-checkpoint "$TMPDIR_BASE/missing.json" 2>&1 || true)
bash "$SCRIPT" --worktree-path "$TMPDIR_BASE" --test-command "true" --task-checkpoint "$TMPDIR_BASE/missing.json" >/dev/null 2>&1 || EXITCODE=$?
assert_exit "3. checkpoint 不存在退出码" 1 "$EXITCODE"
assert_contains "3. checkpoint 不存在包含信息" "$OUTPUT" "checkpoint 文件不存在"
rm -rf "$TMPDIR_BASE"

# --- 4. 有效 checkpoint + 测试通过 → status ok ---
echo "--- 4. 有效 checkpoint + 测试通过 ---"
TMPDIR_BASE=$(mktemp -d)
cat >"$TMPDIR_BASE/cp.json" <<'CPEOF'
{
  "tdd_cycle": [
    {
      "test_intent": "验证用户登录功能",
      "failing_signal": {"assertion_message": "expected 401 but got 200"}
    }
  ]
}
CPEOF
EXITCODE=0
OUTPUT=$(bash "$SCRIPT" --worktree-path "$TMPDIR_BASE" --test-command "true" --task-checkpoint "$TMPDIR_BASE/cp.json" 2>&1) || EXITCODE=$?
assert_exit "4. 有效+通过退出码" 0 "$EXITCODE"
assert_json_field "4. status=ok" "$OUTPUT" "status" "ok"
assert_json_field "4. per_task_l2=True" "$OUTPUT" "per_task_l2" "True"
assert_json_field "4. cycles_verified=1" "$OUTPUT" "cycles_verified" "1"
rm -rf "$TMPDIR_BASE"

# --- 5. 有效 checkpoint + 测试失败 → status blocked ---
echo "--- 5. 有效 checkpoint + 测试失败 ---"
TMPDIR_BASE=$(mktemp -d)
cat >"$TMPDIR_BASE/cp.json" <<'CPEOF'
{
  "tdd_cycle": [
    {
      "test_intent": "验证删除功能",
      "failing_signal": {"assertion_message": "expected 204"}
    }
  ]
}
CPEOF
EXITCODE=0
OUTPUT=$(bash "$SCRIPT" --worktree-path "$TMPDIR_BASE" --test-command "false" --task-checkpoint "$TMPDIR_BASE/cp.json" 2>&1) || EXITCODE=$?
assert_exit "5. 测试失败退出码" 1 "$EXITCODE"
assert_json_field "5. status=blocked" "$OUTPUT" "status" "blocked"
assert_contains "5. 包含测试执行失败" "$OUTPUT" "测试执行失败"
rm -rf "$TMPDIR_BASE"

# --- 6. checkpoint 中 test_intent 为空 → status warn ---
echo "--- 6. test_intent 为空 ---"
TMPDIR_BASE=$(mktemp -d)
cat >"$TMPDIR_BASE/cp.json" <<'CPEOF'
{
  "tdd_cycle": [
    {
      "test_intent": "",
      "failing_signal": {"assertion_message": "expected error"}
    }
  ]
}
CPEOF
EXITCODE=0
OUTPUT=$(bash "$SCRIPT" --worktree-path "$TMPDIR_BASE" --test-command "true" --task-checkpoint "$TMPDIR_BASE/cp.json" 2>&1) || EXITCODE=$?
assert_exit "6. test_intent 空退出码" 0 "$EXITCODE"
assert_json_field "6. status=warn" "$OUTPUT" "status" "warn"
assert_contains "6. failures 包含 test_intent" "$OUTPUT" "test_intent"
rm -rf "$TMPDIR_BASE"

# --- 7. checkpoint 中 failing_signal 缺失 → status warn ---
echo "--- 7. failing_signal 缺失 ---"
TMPDIR_BASE=$(mktemp -d)
cat >"$TMPDIR_BASE/cp.json" <<'CPEOF'
{
  "tdd_cycle": [
    {
      "test_intent": "验证搜索功能"
    }
  ]
}
CPEOF
EXITCODE=0
OUTPUT=$(bash "$SCRIPT" --worktree-path "$TMPDIR_BASE" --test-command "true" --task-checkpoint "$TMPDIR_BASE/cp.json" 2>&1) || EXITCODE=$?
assert_exit "7. failing_signal 缺失退出码" 0 "$EXITCODE"
assert_json_field "7. status=warn" "$OUTPUT" "status" "warn"
assert_contains "7. failures 包含 assertion_message" "$OUTPUT" "assertion_message"
rm -rf "$TMPDIR_BASE"

# --- 8. 多 cycle 部分失败 → status blocked + failures 列表 ---
echo "--- 8. 多 cycle 部分失败 ---"
TMPDIR_BASE=$(mktemp -d)
cat >"$TMPDIR_BASE/cp.json" <<'CPEOF'
{
  "tdd_cycle": [
    {
      "test_intent": "验证创建功能",
      "failing_signal": {"assertion_message": "expected 201"}
    },
    {
      "test_intent": "",
      "failing_signal": {"assertion_message": ""}
    },
    {
      "test_intent": "验证更新功能",
      "failing_signal": {"assertion_message": "expected 200"}
    }
  ]
}
CPEOF
# 使用 false 让测试失败，触发 blocked
EXITCODE=0
OUTPUT=$(bash "$SCRIPT" --worktree-path "$TMPDIR_BASE" --test-command "false" --task-checkpoint "$TMPDIR_BASE/cp.json" 2>&1) || EXITCODE=$?
assert_exit "8. 多 cycle 部分失败退出码" 1 "$EXITCODE"
assert_json_field "8. status=blocked" "$OUTPUT" "status" "blocked"
assert_json_field "8. cycles_verified=3" "$OUTPUT" "cycles_verified" "3"
assert_contains "8. failures 包含 cycle[1] test_intent" "$OUTPUT" "cycle\[1\]: test_intent"
assert_contains "8. failures 包含 cycle[1] assertion_message" "$OUTPUT" "cycle\[1\]: failing_signal.assertion_message"
assert_contains "8. failures 包含测试执行失败" "$OUTPUT" "测试执行失败"
rm -rf "$TMPDIR_BASE"

# --- 清理 ---
teardown_autopilot_fixture

echo ""
echo "=== 结果: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] || exit 1

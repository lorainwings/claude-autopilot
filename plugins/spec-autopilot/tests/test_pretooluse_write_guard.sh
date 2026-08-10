#!/usr/bin/env bash
# test_pretooluse_write_guard.sh — Section 54: unified-write-edit-check.sh PreToolUse hard-block path
#
# 背景：PostToolUse 在工具执行成功之后触发，官方文档 "Can block: No"（the tool already ran），
# 因此挂在 PostToolUse 上的 {"decision":"block"} 只是事后反馈，文件已落盘。
# 真正需要拦截的约束（状态隔离 / TDD 阶段隔离 / 占位符禁令）必须走 PreToolUse +
# hookSpecificOutput.permissionDecision=deny。
#
# 本文件验证：
#   1. PreToolUse 输出官方 deny schema（hookEventName + permissionDecision）
#   2. 内容取自 tool_input 而非磁盘（PreToolUse 时文件尚不存在/仍是旧内容）
#   3. PostToolUse 保持既有 advisory 语义（向后兼容）
#   4. 正常路径不误拦
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../runtime/scripts" && pwd)"
source "$TEST_DIR/_test_helpers.sh"


# 本地辅助：helpers 只有 assert_file_exists，这里需要反向断言
# —— PreToolUse 的核心价值就是"文件根本没被创建"
assert_file_absent() {
  local name="$1" filepath="$2"
  if [ ! -f "$filepath" ]; then
    green "  PASS: $name (file absent)"
    PASS=$((PASS + 1))
  else
    red "  FAIL: $name (file unexpectedly exists: $filepath)"
    FAIL=$((FAIL + 1))
  fi
}

echo "--- 54. PreToolUse write guard (hard block before write) ---"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/.claude"
mkdir -p "$TMPDIR/openspec/changes/test-fixture/context/phase-results"
echo '{"change":"test-fixture","pid":"99999","started":"2026-01-01T00:00:00Z"}' \
  >"$TMPDIR/openspec/changes/.autopilot-active"
echo '{"status":"ok","summary":"Done","decisions":[{"point":"x","choice":"y"}]}' \
  >"$TMPDIR/openspec/changes/test-fixture/context/phase-results/phase-1-test.json"

# Phase 4 checkpoint → 进入 Phase 5（TDD / 状态隔离检查生效区）
echo '{"status":"ok","summary":"Tests ready"}' \
  >"$TMPDIR/openspec/changes/test-fixture/context/phase-results/phase-4-test.json"

# Helper: 构造 PreToolUse stdin（内容只在 tool_input 里，磁盘上不写）
# Args: abs_or_rel_path content
pre_input() {
  local fpath="$TMPDIR/$1"
  _P="$fpath" _C="$2" _CWD="$TMPDIR" python3 -c '
import json, os
print(json.dumps({
    "tool_name": "Write",
    "tool_input": {"file_path": os.environ["_P"], "content": os.environ["_C"]},
    "cwd": os.environ["_CWD"],
}))'
}

# Helper: 构造 Edit 形态的 PreToolUse stdin（内容在 new_string）
pre_edit_input() {
  local fpath="$TMPDIR/$1"
  _P="$fpath" _C="$2" _CWD="$TMPDIR" python3 -c '
import json, os
print(json.dumps({
    "tool_name": "Edit",
    "tool_input": {
        "file_path": os.environ["_P"],
        "old_string": "placeholder",
        "new_string": os.environ["_C"],
    },
    "cwd": os.environ["_CWD"],
}))'
}

run_pre() { bash "$SCRIPT_DIR/unified-write-edit-check.sh" PreToolUse 2>/dev/null; }
run_post() { bash "$SCRIPT_DIR/unified-write-edit-check.sh" PostToolUse 2>/dev/null; }

# === 54a. 正常路径：干净源码不被拦截 ===
exit_code=0
output=$(pre_input "src/clean.ts" "export function add(a: number, b: number) { return a + b }" | run_pre) || exit_code=$?
assert_exit "54a. clean source → exit 0" 0 $exit_code
assert_not_contains "54a. clean source → no deny" "$output" "deny"

# === 54b. 边界：占位符在 tool_input 内容中（文件尚未落盘）→ PreToolUse deny ===
exit_code=0
output=$(pre_input "src/svc.ts" "function init() {
  // TODO: implement later
  return null
}" | run_pre) || exit_code=$?
assert_exit "54b. TODO in pending content → exit 0" 0 $exit_code
assert_contains "54b. TODO → permissionDecision deny" "$output" '"permissionDecision": "deny"'
assert_contains "54b. deny carries official hookEventName" "$output" '"hookEventName": "PreToolUse"'
assert_contains "54b. reason mentions the banned pattern" "$output" "TODO"
# 关键断言：PreToolUse 不得写盘 —— 文件必须仍不存在
assert_file_absent "54b. file NOT created (block happened before write)" "$TMPDIR/src/svc.ts"

# === 54c. 内容来自 tool_input 而非磁盘：磁盘干净但待写内容脏 → 仍 deny ===
mkdir -p "$TMPDIR/src"
echo "export const ok = 1" >"$TMPDIR/src/existing.ts"
exit_code=0
output=$(pre_edit_input "src/existing.ts" "// FIXME: broken" | run_pre) || exit_code=$?
assert_exit "54c. dirty new_string over clean file → exit 0" 0 $exit_code
assert_contains "54c. evaluates tool_input, not disk" "$output" "deny"
assert_contains "54c. reason mentions FIXME" "$output" "FIXME"
# 磁盘内容必须未被改动
disk_now=$(cat "$TMPDIR/src/existing.ts")
assert_contains "54c. disk content untouched" "$disk_now" "export const ok = 1"

# === 54d. 反向：磁盘脏但待写内容干净 → 放行（证明读的是 tool_input） ===
echo "// TODO: legacy junk" >"$TMPDIR/src/legacy.ts"
exit_code=0
output=$(pre_edit_input "src/legacy.ts" "export const clean = true" | run_pre) || exit_code=$?
assert_exit "54d. clean new_string over dirty file → exit 0" 0 $exit_code
assert_not_contains "54d. stale disk content must not trigger deny" "$output" "deny"

# === 54e. 错误路径：子 agent 写 checkpoint → 状态隔离 deny ===
exit_code=0
output=$(pre_input "openspec/changes/test-fixture/context/phase-results/phase-5-x.json" '{"status":"ok"}' | run_pre) || exit_code=$?
assert_exit "54e. checkpoint write → exit 0" 0 $exit_code
assert_contains "54e. protected path → deny" "$output" "deny"
assert_contains "54e. reason mentions state isolation" "$output" "State isolation"
assert_file_absent "54e. checkpoint NOT written (orchestrator state protected)" "$TMPDIR/openspec/changes/test-fixture/context/phase-results/phase-5-x.json"

# === 54f. 向后兼容：PostToolUse 仍走 advisory decision 形态 ===
mkdir -p "$TMPDIR/src"
cat >"$TMPDIR/src/post.ts" <<'SRC'
function f() {
  // TODO: later
}
SRC
exit_code=0
output=$(pre_input "src/post.ts" "unused-for-post" | run_post) || exit_code=$?
assert_exit "54f. PostToolUse → exit 0" 0 $exit_code
assert_contains "54f. PostToolUse keeps top-level decision" "$output" '"decision"'
assert_not_contains "54f. PostToolUse must NOT emit permissionDecision" "$output" "permissionDecision"

# === 54g. 默认参数（无 argv）保持 PostToolUse 语义 ===
exit_code=0
output=$(pre_input "src/post.ts" "unused" | bash "$SCRIPT_DIR/unified-write-edit-check.sh" 2>/dev/null) || exit_code=$?
assert_exit "54g. no argv → exit 0" 0 $exit_code
assert_not_contains "54g. no argv defaults to PostToolUse schema" "$output" "permissionDecision"

# === 54h. TDD RED 阶段：写实现文件 → deny 且文件未创建 ===
echo "red" >"$TMPDIR/openspec/changes/test-fixture/context/.tdd-stage"
exit_code=0
output=$(pre_input "src/impl.ts" "export const impl = 1" | run_pre) || exit_code=$?
assert_exit "54h. RED + impl file → exit 0" 0 $exit_code
assert_contains "54h. RED stage → deny" "$output" "deny"
assert_contains "54h. reason mentions RED" "$output" "RED"
assert_file_absent "54h. impl file NOT created during RED" "$TMPDIR/src/impl.ts"

# === 54i. TDD RED 阶段：写测试文件 → 放行 ===
exit_code=0
output=$(pre_input "src/impl.test.ts" "it('works', () => { expect(add(1,2)).toBe(3) })" | run_pre) || exit_code=$?
assert_exit "54i. RED + test file → exit 0" 0 $exit_code
assert_not_contains "54i. RED allows test files" "$output" "deny"

rm -f "$TMPDIR/openspec/changes/test-fixture/context/.tdd-stage"

# === 54j. 畸形 stdin：缺 tool_input → 不得崩溃、不得误 deny ===
exit_code=0
output=$(echo '{"tool_name":"Write","cwd":"'"$TMPDIR"'"}' | run_pre) || exit_code=$?
assert_exit "54j. missing tool_input → exit 0" 0 $exit_code
assert_not_contains "54j. missing tool_input → no spurious deny" "$output" "deny"

# === 54k. 畸形 stdin：content 为 null → 不得崩溃 ===
exit_code=0
output=$(echo '{"tool_name":"Write","tool_input":{"file_path":"'"$TMPDIR"'/src/n.ts","content":null},"cwd":"'"$TMPDIR"'"}' | run_pre) || exit_code=$?
assert_exit "54k. null content → exit 0" 0 $exit_code

echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1
exit 0

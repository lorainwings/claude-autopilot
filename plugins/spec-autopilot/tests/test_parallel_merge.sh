#!/usr/bin/env bash
# test_parallel_merge.sh — Section 39: parallel-merge-guard.sh anchor_sha diff base
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../runtime/scripts" && pwd)"
source "$TEST_DIR/_test_helpers.sh"
source "$TEST_DIR/_fixtures.sh"

echo "--- 39. parallel-merge-guard.sh anchor_sha diff base ---"
setup_autopilot_fixture

# 构建真实 git repo 用于 anchor_sha 测试
ANCHOR_TEST_DIR=$(mktemp -d)
(
  cd "$ANCHOR_TEST_DIR" || exit 1
  git init -q
  git config user.email "test@test.com"
  git config user.name "test"
  # 初始 commit
  echo "init" > init.txt
  git add init.txt && git commit -q -m "init"
  # 模拟 Phase 0 锚定 commit
  git commit -q --allow-empty -m "autopilot: start test-change"
  ANCHOR_SHA=$(git rev-parse HEAD)
  # 模拟 Phase 5 实现 — 在 scope 内
  mkdir -p backend/src
  echo "code" > backend/src/Foo.java
  git add . && git commit -q -m "impl task 1"
  # 模拟 scope 外文件
  echo "rogue" > unrelated.txt
  git add . && git commit -q -m "rogue change"
  # 写出 anchor SHA 供后续引用
  echo "$ANCHOR_SHA" > "$ANCHOR_TEST_DIR/_anchor_sha"
)
ANCHOR_SHA=$(cat "$ANCHOR_TEST_DIR/_anchor_sha")

# 创建 autopilot 锁文件
mkdir -p "$ANCHOR_TEST_DIR/.claude"
mkdir -p "$ANCHOR_TEST_DIR/openspec/changes/test-change/context/phase-results"
echo "{\"change\":\"test-change\",\"anchor_sha\":\"$ANCHOR_SHA\"}" > "$ANCHOR_TEST_DIR/openspec/changes/.autopilot-active"

# 构造 merge guard 输入 JSON：Phase 5 + worktree merge + artifacts 只含 backend/src/Foo.java
# 注意：必须用 printf + 单引号避免 bash 解释 JSON 转义（如 \n, \"）
mk_merge_input() {
  local cwd="$1"
  printf '%s' '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:5 -->\nPhase 5 impl","subagent_type":"backend-developer"},"tool_response":"{\"status\":\"ok\",\"summary\":\"worktree merge done\",\"artifacts\":[\"backend/src/Foo.java\"]}","cwd":"'"$cwd"'"}'
}

# 39a. 有效 anchor_sha → diff 覆盖锚定点之后全部 commit → 检测到 scope 外文件
exit_code=0
output=$(mk_merge_input "$ANCHOR_TEST_DIR" | bash "$SCRIPT_DIR/parallel-merge-guard.sh" 2>/dev/null) || exit_code=$?
assert_exit "anchor_sha valid → exit 0" 0 $exit_code
assert_contains "anchor_sha valid → scope violation detected" "$output" "outside task scope"
assert_contains "anchor_sha valid → unrelated.txt flagged" "$output" "unrelated.txt"

# 39b. 无效 anchor_sha（不是 HEAD 祖先）→ 降级 HEAD~1
echo '{"change":"test-change","anchor_sha":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}' \
  > "$ANCHOR_TEST_DIR/openspec/changes/.autopilot-active"
exit_code=0
output=$(mk_merge_input "$ANCHOR_TEST_DIR" | bash "$SCRIPT_DIR/parallel-merge-guard.sh" 2>/dev/null) || exit_code=$?
assert_exit "anchor_sha invalid → exit 0 (fallback HEAD~1)" 0 $exit_code
# HEAD~1 只看最后一个 commit（unrelated.txt），仍能检测到 scope 外
assert_contains "anchor_sha invalid → fallback still detects scope" "$output" "outside task scope"

# 39c. anchor_sha 为空字符串 → 降级 HEAD~1
echo '{"change":"test-change","anchor_sha":""}' \
  > "$ANCHOR_TEST_DIR/openspec/changes/.autopilot-active"
exit_code=0
output=$(mk_merge_input "$ANCHOR_TEST_DIR" | bash "$SCRIPT_DIR/parallel-merge-guard.sh" 2>/dev/null) || exit_code=$?
assert_exit "anchor_sha empty → exit 0 (fallback HEAD~1)" 0 $exit_code
assert_contains "anchor_sha empty → fallback detects scope" "$output" "outside task scope"

# 39d. 无锁文件 → 脚本在 Layer 0 bypass（has_active_autopilot 失败）
rm "$ANCHOR_TEST_DIR/openspec/changes/.autopilot-active"
exit_code=0
output=$(mk_merge_input "$ANCHOR_TEST_DIR" | bash "$SCRIPT_DIR/parallel-merge-guard.sh" 2>/dev/null) || exit_code=$?
assert_exit "no lock file → exit 0 (bypass)" 0 $exit_code
assert_not_contains "no lock file → no block" "$output" "block"

# 39e. 有效 anchor_sha + 所有文件在 scope 内 → 无 violation
# 重建：只有 scope 内的文件
SCOPE_TEST_DIR=$(mktemp -d)
(
  cd "$SCOPE_TEST_DIR" || exit 1
  git init -q
  git config user.email "test@test.com"
  git config user.name "test"
  echo "init" > init.txt
  git add init.txt && git commit -q -m "init"
  git commit -q --allow-empty -m "autopilot: start scope-test"
  SCOPE_ANCHOR=$(git rev-parse HEAD)
  mkdir -p backend/src
  echo "code" > backend/src/Bar.java
  git add . && git commit -q -m "impl in scope"
  echo "$SCOPE_ANCHOR" > "$SCOPE_TEST_DIR/_anchor_sha"
)
SCOPE_ANCHOR=$(cat "$SCOPE_TEST_DIR/_anchor_sha")
mkdir -p "$SCOPE_TEST_DIR/.claude"
mkdir -p "$SCOPE_TEST_DIR/openspec/changes/scope-test/context/phase-results"
echo "{\"change\":\"scope-test\",\"anchor_sha\":\"$SCOPE_ANCHOR\"}" > "$SCOPE_TEST_DIR/openspec/changes/.autopilot-active"
mk_scope_input() {
  printf '%s' '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:5 -->\nPhase 5","subagent_type":"backend-developer"},"tool_response":"{\"status\":\"ok\",\"summary\":\"worktree merge done\",\"artifacts\":[\"backend/src/Bar.java\"]}","cwd":"'"$1"'"}'
}
exit_code=0
output=$(mk_scope_input "$SCOPE_TEST_DIR" | bash "$SCRIPT_DIR/parallel-merge-guard.sh" 2>/dev/null) || exit_code=$?
assert_exit "anchor_sha valid + all in scope → exit 0" 0 $exit_code
assert_not_contains "anchor_sha valid + all in scope → no block" "$output" "block"

rm -rf "$ANCHOR_TEST_DIR" "$SCOPE_TEST_DIR"

teardown_autopilot_fixture
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1; exit 0

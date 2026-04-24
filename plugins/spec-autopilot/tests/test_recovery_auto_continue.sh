#!/usr/bin/env bash
# test_recovery_auto_continue.sh — 恢复场景自动推进测试
# 验证 recovery-decision.sh 在满足条件时设置 auto_continue_eligible = true
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../runtime/scripts" && pwd)"
source "$TEST_DIR/_test_helpers.sh"
source "$TEST_DIR/_fixtures.sh"

echo "--- Recovery auto-continue: auto_continue_eligible 判断 ---"
setup_autopilot_fixture

# --- 1. recovery-decision.sh 包含 auto_continue_eligible 字段 ---
RECOVERY_SCRIPT="$SCRIPT_DIR/recovery-decision.sh"
recovery_content=$(cat "$RECOVERY_SCRIPT")

# 1a. 脚本包含 auto_continue_eligible 计算逻辑
assert_contains "1a: recovery 包含 auto_continue_eligible 计算" "$recovery_content" 'auto_continue_eligible'

# 1b. 脚本在单候选 + 无 git 风险时设置 auto_continue_eligible = True
assert_contains "1b: 单候选 + 无 git 风险 → auto_continue" "$recovery_content" 'no_ambiguity and no_git_risk'

# 1c. 脚本在 recovery_confidence = low 时覆盖为 False
assert_contains "1c: recovery_confidence low → 覆盖 auto_continue" "$recovery_content" "recovery_confidence == 'low'"

# --- 2. 实际运行 recovery-decision.sh 验证 auto_continue_eligible ---
# 构建一个简单的恢复场景
TMPDIR_REC=$(mktemp -d)
(
  cd "$TMPDIR_REC" || exit 1
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"
  echo "init" >README.md
  git add README.md
  git commit -q --no-verify -m "initial commit"

  # 创建 anchor commit
  git commit -q --allow-empty --no-verify -m "autopilot: start test-recovery"
  ANCHOR_SHA=$(git rev-parse HEAD)

  # 创建 change 目录和 checkpoint
  mkdir -p openspec/changes/test-recovery/context/phase-results
  echo '{"status":"ok","summary":"req done"}' >openspec/changes/test-recovery/context/phase-results/phase-1-requirements.json
  echo "{\"change\":\"test-recovery\",\"mode\":\"full\",\"anchor_sha\":\"$ANCHOR_SHA\"}" >openspec/changes/.autopilot-active

  # 创建一个 fixup commit
  echo "code" >src.txt
  git add -A
  git commit -q --no-verify --fixup="$ANCHOR_SHA" -m "fixup! autopilot: start test-recovery — Phase 1"

  # 创建 config
  mkdir -p .claude
  cat >.claude/autopilot.config.yaml <<'YAML'
default_mode: full
context_management:
  auto_continue_on_recovery: true
YAML
) 2>/dev/null

# 运行 recovery-decision.sh
exit_code=0
output=$(cd "$TMPDIR_REC" && bash "$SCRIPT_DIR/recovery-decision.sh" "$TMPDIR_REC" 2>/dev/null) || exit_code=$?
assert_exit "2a: recovery-decision.sh 正常退出" 0 $exit_code

# 2b. 输出包含 auto_continue_eligible 字段
if [ -n "$output" ]; then
  has_field=$(echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); print('true' if 'auto_continue_eligible' in d else 'false')" 2>/dev/null || echo "false")
  if [ "$has_field" = "true" ]; then
    green "  PASS: 2b: recovery 输出包含 auto_continue_eligible 字段"
    PASS=$((PASS + 1))
  else
    red "  FAIL: 2b: recovery 输出缺少 auto_continue_eligible 字段"
    FAIL=$((FAIL + 1))
  fi
else
  red "  FAIL: 2b: recovery-decision.sh 无输出"
  FAIL=$((FAIL + 1))
fi

rm -rf "$TMPDIR_REC"

# --- 3. poll-gate-decision.sh 支持 auto_continue action ---
POLL_SCRIPT="$SCRIPT_DIR/poll-gate-decision.sh"
poll_content=$(cat "$POLL_SCRIPT")

# 3a. poll 脚本验证列表中包含 auto_continue
assert_contains "3a: poll action 列表包含 auto_continue" "$poll_content" "auto_continue"

# 3b. 验证 poll 脚本的 action 校验逻辑正确包含 auto_continue
assert_contains "3b: poll 脚本 action 枚举包含 auto_continue" "$poll_content" "'override', 'retry', 'fix', 'auto_continue'"

# --- 4. autopilot-gate SKILL.md 支持 auto_continue 语义 ---
GATE_SKILL="$TEST_DIR/../skills/autopilot-gate/SKILL.md"
gate_content=$(cat "$GATE_SKILL")

# 4a. gate 文档包含 auto_continue action 说明
assert_contains "4a: gate 文档 auto_continue action" "$gate_content" 'auto_continue.*自动推进'

teardown_autopilot_fixture
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1
exit 0

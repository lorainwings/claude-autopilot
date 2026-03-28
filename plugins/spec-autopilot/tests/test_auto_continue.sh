#!/usr/bin/env bash
# test_auto_continue.sh — 自动推进语义测试
# 验证 requirement packet 确认后自动推进到 archive-ready
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../runtime/scripts" && pwd)"
SKILL_DIR="$(cd "$TEST_DIR/../skills" && pwd)"
source "$TEST_DIR/_test_helpers.sh"
source "$TEST_DIR/_fixtures.sh"

echo "--- Auto-continue: requirement packet 确认后自动推进 ---"
setup_autopilot_fixture

# --- 1. autopilot-init 预设: 所有预设 after_phase_1 = false ---
INIT_SKILL="$SKILL_DIR/autopilot-init/SKILL.md"
init_content=$(cat "$INIT_SKILL")

# 1a. Strict 预设: after_phase_1 = false
strict_section=$(echo "$init_content" | sed -n '/# --- Strict 预设/,/# --- Moderate 预设/p')
assert_contains "1a: strict after_phase_1 = false" "$strict_section" 'after_phase_1: false'

# 1b. Moderate 预设: after_phase_1 = false
moderate_section=$(echo "$init_content" | sed -n '/# --- Moderate 预设/,/# --- Relaxed 预设/p')
assert_contains "1b: moderate after_phase_1 = false" "$moderate_section" 'after_phase_1: false'

# 1c. Relaxed 预设: after_phase_1 = false
relaxed_section=$(echo "$init_content" | sed -n '/# --- Relaxed 预设/,/^```$/p')
assert_contains "1c: relaxed after_phase_1 = false" "$relaxed_section" 'after_phase_1: false'

# 1d. 所有预设 after_phase_3 = false
assert_contains "1d: strict after_phase_3 = false" "$strict_section" 'after_phase_3: false'
assert_contains "1e: moderate after_phase_3 = false" "$moderate_section" 'after_phase_3: false'

# 1f. 所有预设包含 auto_continue_after_requirement = true
assert_contains "1f: strict auto_continue_after_requirement" "$strict_section" 'auto_continue_after_requirement: true'
assert_contains "1g: moderate auto_continue_after_requirement" "$moderate_section" 'auto_continue_after_requirement: true'
assert_contains "1h: relaxed auto_continue_after_requirement" "$relaxed_section" 'auto_continue_after_requirement: true'

# 1i. 所有预设包含 archive_auto_on_readiness = true
assert_contains "1i: strict archive_auto_on_readiness" "$strict_section" 'archive_auto_on_readiness: true'
assert_contains "1j: moderate archive_auto_on_readiness" "$moderate_section" 'archive_auto_on_readiness: true'
assert_contains "1k: relaxed archive_auto_on_readiness" "$relaxed_section" 'archive_auto_on_readiness: true'

# --- 2. autopilot-gate: 支持 auto_continue action ---
GATE_SKILL="$SKILL_DIR/autopilot-gate/SKILL.md"
gate_content=$(cat "$GATE_SKILL")

# 2a. gate 支持 auto_continue action
assert_contains "2a: gate 支持 auto_continue action" "$gate_content" 'auto_continue'

# 2b. gate 包含自动推进语义说明
assert_contains "2b: gate 包含自动推进语义" "$gate_content" '自动推进语义'

# 2c. gate 门禁通过后默认自动推进
assert_contains "2c: gate 通过后默认自动推进" "$gate_content" '默认自动推进到下一阶段'

# --- 3. poll-gate-decision.sh: 支持 auto_continue action ---
POLL_SCRIPT="$SCRIPT_DIR/poll-gate-decision.sh"
poll_content=$(cat "$POLL_SCRIPT")

# 3a. poll 脚本接受 auto_continue action
assert_contains "3a: poll 脚本接受 auto_continue" "$poll_content" 'auto_continue'

# --- 4. autopilot-phase7: 自动归档（不再强制 AskUser）---
PHASE7_SKILL="$SKILL_DIR/autopilot-phase7/SKILL.md"
phase7_content=$(cat "$PHASE7_SKILL")

# 4a. archive-readiness ready → 自动归档
assert_contains "4a: readiness ready → 无需 AskUserQuestion" "$phase7_content" '无需 AskUserQuestion'

# 4b. 不再有"必须 AskUserQuestion 询问用户"的归档确认
assert_not_contains "4b: 无强制 AskUser 归档确认" "$phase7_content" '必须.*AskUserQuestion.*归档'

# --- 5. 三模式 auto-continue 行为验证（checkpoint 层面）---
# 5a. full 模式: Phase 1 ok → Phase 2 应该可以直接推进（无需人工确认）
FULL_TEST_DIR=$(mktemp -d)
mkdir -p "$FULL_TEST_DIR/openspec/changes/test-full/context/phase-results"
echo '{"change":"test-full","mode":"full"}' > "$FULL_TEST_DIR/openspec/changes/.autopilot-active"
echo '{"status":"ok","summary":"Requirements confirmed"}' > "$FULL_TEST_DIR/openspec/changes/test-full/context/phase-results/phase-1-requirements.json"

exit_code=0
output=$(echo "{\"tool_name\":\"Task\",\"tool_input\":{\"prompt\":\"<!-- autopilot-phase:2 -->\\nPhase 2\"},\"cwd\":\"$FULL_TEST_DIR\"}" \
  | bash "$SCRIPT_DIR/check-predecessor-checkpoint.sh" 2>/dev/null) || exit_code=$?
assert_exit "5a: full: Phase 1 ok → Phase 2 允许 (exit 0)" 0 $exit_code
assert_not_contains "5b: full: Phase 2 无 deny" "$output" "deny"
rm -rf "$FULL_TEST_DIR"

# 5c. lite 模式: Phase 1 ok → Phase 5 应该可以直接推进
LITE_TEST_DIR=$(mktemp -d)
mkdir -p "$LITE_TEST_DIR/openspec/changes/test-lite/context/phase-results"
echo '{"change":"test-lite","mode":"lite"}' > "$LITE_TEST_DIR/openspec/changes/.autopilot-active"
echo '{"status":"ok","summary":"Requirements confirmed"}' > "$LITE_TEST_DIR/openspec/changes/test-lite/context/phase-results/phase-1-requirements.json"

exit_code=0
output=$(echo "{\"tool_name\":\"Task\",\"tool_input\":{\"prompt\":\"<!-- autopilot-phase:5 -->\\nPhase 5\"},\"cwd\":\"$LITE_TEST_DIR\"}" \
  | bash "$SCRIPT_DIR/check-predecessor-checkpoint.sh" 2>/dev/null) || exit_code=$?
assert_exit "5c: lite: Phase 1 ok → Phase 5 允许 (exit 0)" 0 $exit_code
assert_not_contains "5d: lite: Phase 5 无 deny" "$output" "deny"
rm -rf "$LITE_TEST_DIR"

# 5e. minimal 模式: Phase 1 ok → Phase 5 应该可以直接推进
MIN_TEST_DIR=$(mktemp -d)
mkdir -p "$MIN_TEST_DIR/openspec/changes/test-min/context/phase-results"
echo '{"change":"test-min","mode":"minimal"}' > "$MIN_TEST_DIR/openspec/changes/.autopilot-active"
echo '{"status":"ok","summary":"Requirements confirmed"}' > "$MIN_TEST_DIR/openspec/changes/test-min/context/phase-results/phase-1-requirements.json"

exit_code=0
output=$(echo "{\"tool_name\":\"Task\",\"tool_input\":{\"prompt\":\"<!-- autopilot-phase:5 -->\\nPhase 5\"},\"cwd\":\"$MIN_TEST_DIR\"}" \
  | bash "$SCRIPT_DIR/check-predecessor-checkpoint.sh" 2>/dev/null) || exit_code=$?
assert_exit "5e: minimal: Phase 1 ok → Phase 5 允许 (exit 0)" 0 $exit_code
assert_not_contains "5f: minimal: Phase 5 无 deny" "$output" "deny"
rm -rf "$MIN_TEST_DIR"

# --- 6. 不允许通过预设切换改变自动推进语义 ---
# 验证: 即使是 Strict 预设，after_phase_1 也是 false（不中断）
# 这在 1a 已验证。再做一个反面验证：确保没有任何预设将 after_phase_1 设为 true
after_phase1_true_count=$(echo "$init_content" | grep -c 'after_phase_1: true' 2>/dev/null || true)
after_phase1_true_count=$(echo "$after_phase1_true_count" | tr -d '[:space:]')
if [ "$after_phase1_true_count" = "0" ]; then
  green "  PASS: 6a: 没有任何预设将 after_phase_1 设为 true"
  PASS=$((PASS + 1))
else
  red "  FAIL: 6a: 发现 $after_phase1_true_count 个预设将 after_phase_1 设为 true"
  FAIL=$((FAIL + 1))
fi

teardown_autopilot_fixture
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1; exit 0

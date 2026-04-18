#!/usr/bin/env bash
# TEST_LAYER: behavior
# test_agent_dispatch_resolution.sh — 验证 Sub-Agent 名称硬解析协议
# 目标：确保派发前模板变量（如 config.phases.requirements.agent）被实际值替换，
#       未注册名/未解析占位符必须 fail-fast。
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../runtime/scripts" && pwd)"
source "$TEST_DIR/_test_helpers.sh"

VALIDATOR="$SCRIPT_DIR/validate-agent-registry.sh"

echo "--- agent dispatch resolution ---"

# 0. 脚本存在且可执行
if [ -x "$VALIDATOR" ]; then
  green "  PASS: 0. validate-agent-registry.sh exists & executable"
  PASS=$((PASS + 1))
else
  red "  FAIL: 0. validate-agent-registry.sh missing or not executable: $VALIDATOR"
  FAIL=$((FAIL + 1))
fi

# 0a. 语法校验
if bash -n "$VALIDATOR" 2>/dev/null; then
  green "  PASS: 0a. validator syntax OK"
  PASS=$((PASS + 1))
else
  red "  FAIL: 0a. validator syntax error"
  FAIL=$((FAIL + 1))
fi

# ---- Test 1: 正常解析（传入内置/已注册名，返回 exit 0） ----
# general-purpose / Explore / Plan 是 Claude Code 内置 agent，必须接受
RESULT=$(bash "$VALIDATOR" "general-purpose" 2>&1)
EC=$?
assert_exit "1a. builtin general-purpose → exit 0" 0 "$EC"

RESULT=$(bash "$VALIDATOR" "Explore" 2>&1)
EC=$?
assert_exit "1b. builtin Explore → exit 0" 0 "$EC"

RESULT=$(bash "$VALIDATOR" "Plan" 2>&1)
EC=$?
assert_exit "1c. builtin Plan → exit 0" 0 "$EC"

# ---- Test 2: 未注册名 fail-fast ----
RESULT=$(bash "$VALIDATOR" "definitely-not-a-real-agent-xyz" 2>&1)
EC=$?
assert_exit "2a. unknown agent → exit 1" 1 "$EC"
assert_contains "2b. unknown agent prints error message" "$RESULT" "definitely-not-a-real-agent-xyz"

# ---- Test 3: 模板未替换检测 ----
# 输入含 config.phases. → block
RESULT=$(bash "$VALIDATOR" "config.phases.requirements.agent" 2>&1)
EC=$?
assert_exit "3a. unresolved 'config.phases.' → exit 1" 1 "$EC"
assert_contains "3b. unresolved 'config.phases.' prints error" "$RESULT" "unresolved"

# 输入含 {{ → block
RESULT=$(bash "$VALIDATOR" "{{RESOLVED_AGENT_NAME}}" 2>&1)
EC=$?
assert_exit "3c. unresolved '{{' placeholder → exit 1" 1 "$EC"
assert_contains "3d. unresolved '{{' prints error" "$RESULT" "unresolved"

# 输入以 config. 开头 → block
RESULT=$(bash "$VALIDATOR" "config.something" 2>&1)
EC=$?
assert_exit "3e. unresolved 'config.' prefix → exit 1" 1 "$EC"

# ---- Test 4: 空输入 fail-fast ----
RESULT=$(bash "$VALIDATOR" "" 2>&1)
EC=$?
assert_exit "4a. empty agent name → exit 1" 1 "$EC"

# ---- Test 5: 自定义 agent 注册扫描（如果 .claude/agents 或 ~/.claude/agents 存在自定义 agent，应被识别） ----
# 创建一个临时本地 agent 文件，并将 PROJECT_ROOT 指向临时目录
TMP_AGENTS_ROOT=$(mktemp -d)
mkdir -p "$TMP_AGENTS_ROOT/.claude/agents"
cat >"$TMP_AGENTS_ROOT/.claude/agents/my-custom-agent.md" <<'AGENT_EOF'
---
name: my-custom-agent
description: Custom test agent
---
Test agent body.
AGENT_EOF

RESULT=$(AUTOPILOT_PROJECT_ROOT="$TMP_AGENTS_ROOT" bash "$VALIDATOR" "my-custom-agent" 2>&1)
EC=$?
assert_exit "5a. custom registered agent → exit 0" 0 "$EC"

# 同时在自定义 root 下，未注册名仍应失败
RESULT=$(AUTOPILOT_PROJECT_ROOT="$TMP_AGENTS_ROOT" bash "$VALIDATOR" "ghost-agent" 2>&1)
EC=$?
assert_exit "5b. custom root unknown agent → exit 1" 1 "$EC"

rm -rf "$TMP_AGENTS_ROOT"

# ---- Test 6: PostToolUse hook 增强 — Phase ≥ 2 + Explore subagent_type 应 block ----
DISPATCH_HOOK="$SCRIPT_DIR/auto-emit-agent-dispatch.sh"

# 准备 fixture lock，使 has_active_autopilot 通过
REPO_ROOT="$(cd "$TEST_DIR/../../.." && pwd)"
FIXTURE_LOCK_DIR="$REPO_ROOT/openspec/changes"
FIXTURE_LOCK_FILE="$FIXTURE_LOCK_DIR/.autopilot-active"
FIXTURE_CREATED=false
if [ ! -f "$FIXTURE_LOCK_FILE" ]; then
  mkdir -p "$FIXTURE_LOCK_DIR"
  echo '{"change":"test-fixture","pid":"99999","started":"2026-01-01T00:00:00Z","mode":"full"}' >"$FIXTURE_LOCK_FILE"
  FIXTURE_CREATED=true
fi
mkdir -p "$REPO_ROOT/logs" 2>/dev/null || true

# Phase 2 + subagent_type=Explore → 应通过 stdout 输出 block JSON
PHASE2_EXPLORE_JSON='{"tool_name":"Task","tool_input":{"subagent_type":"Explore","prompt":"<!-- autopilot-phase:2 --> Generate openspec","description":"OpenSpec gen"},"cwd":"'"$REPO_ROOT"'"}'
RESULT=$(echo "$PHASE2_EXPLORE_JSON" | bash "$DISPATCH_HOOK" 2>/dev/null)
assert_contains "6a. Phase2 + Explore → block JSON in stdout" "$RESULT" '"decision":"block"'
assert_contains "6b. Phase2 + Explore → block reason mentions Explore" "$RESULT" "Explore"

# Phase 1 + Explore 应允许（Auto-Scan 例外），不输出 block
PHASE1_EXPLORE_JSON='{"tool_name":"Task","tool_input":{"subagent_type":"Explore","prompt":"<!-- autopilot-phase:1 --> Auto-scan","description":"Phase 1 scan"},"cwd":"'"$REPO_ROOT"'"}'
RESULT=$(echo "$PHASE1_EXPLORE_JSON" | bash "$DISPATCH_HOOK" 2>/dev/null)
assert_not_contains "6c. Phase1 + Explore → no block JSON (Phase 1 exempted)" "$RESULT" '"decision":"block"'

# Phase 5 + 显式自定义 agent 不应 block
PHASE5_OK_JSON='{"tool_name":"Task","tool_input":{"subagent_type":"backend-engineer","prompt":"<!-- autopilot-phase:5 --> Implement","description":"Phase 5 impl"},"cwd":"'"$REPO_ROOT"'"}'
RESULT=$(echo "$PHASE5_OK_JSON" | bash "$DISPATCH_HOOK" 2>/dev/null)
assert_not_contains "6d. Phase5 + custom agent → no block" "$RESULT" '"decision":"block"'

# Cleanup
rm -f "$REPO_ROOT/logs/.active-agent-id" "$REPO_ROOT/logs/.agent-dispatch-ts-"* 2>/dev/null || true
rm -f "$REPO_ROOT/logs/.active-agent-phase-"* 2>/dev/null || true
rm -f "$REPO_ROOT/logs/agent-dispatch-record.json" 2>/dev/null || true
rm -f "$REPO_ROOT/logs/events.jsonl" 2>/dev/null || true
rm -f "$REPO_ROOT/logs/.event_sequence" 2>/dev/null || true
rmdir "$REPO_ROOT/logs/.event_sequence.lk" 2>/dev/null || true
rmdir "$REPO_ROOT/logs" 2>/dev/null || true
if [ "$FIXTURE_CREATED" = "true" ]; then
  rm -f "$FIXTURE_LOCK_FILE"
  rmdir "$FIXTURE_LOCK_DIR" 2>/dev/null || true
  rmdir "$REPO_ROOT/openspec" 2>/dev/null || true
fi

echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1
exit 0

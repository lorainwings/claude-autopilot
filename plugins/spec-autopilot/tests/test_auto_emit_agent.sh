#!/usr/bin/env bash
# test_auto_emit_agent.sh — Tests for auto-emit-agent-dispatch.sh and auto-emit-agent-complete.sh
# Verifies: hook auto-fires agent lifecycle events for autopilot Task dispatches
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../runtime/scripts" && pwd)"
source "$TEST_DIR/_test_helpers.sh"
source "$TEST_DIR/_fixtures.sh"

echo "--- auto-emit-agent hooks ---"
setup_autopilot_fixture

# 1a. auto-emit-agent-dispatch.sh syntax check
if bash -n "$SCRIPT_DIR/auto-emit-agent-dispatch.sh" 2>/dev/null; then
  green "  PASS: 1a. auto-emit-agent-dispatch.sh syntax OK"
  PASS=$((PASS + 1))
else
  red "  FAIL: 1a. auto-emit-agent-dispatch.sh syntax error"
  FAIL=$((FAIL + 1))
fi

# 1b. auto-emit-agent-complete.sh syntax check
if bash -n "$SCRIPT_DIR/auto-emit-agent-complete.sh" 2>/dev/null; then
  green "  PASS: 1b. auto-emit-agent-complete.sh syntax OK"
  PASS=$((PASS + 1))
else
  red "  FAIL: 1b. auto-emit-agent-complete.sh syntax error"
  FAIL=$((FAIL + 1))
fi

# 1c. dispatch hook exits 0 on empty stdin (no-op)
RESULT=$(echo "" | bash "$SCRIPT_DIR/auto-emit-agent-dispatch.sh" 2>/dev/null; echo $?)
assert_exit "1c. dispatch empty stdin → exit 0" 0 "$RESULT"

# 1d. complete hook exits 0 on empty stdin (no-op)
RESULT=$(echo "" | bash "$SCRIPT_DIR/auto-emit-agent-complete.sh" 2>/dev/null; echo $?)
assert_exit "1d. complete empty stdin → exit 0" 0 "$RESULT"

# 1e. dispatch hook exits 0 for non-autopilot Task (no phase marker)
NON_AUTOPILOT_JSON='{"tool_name":"Task","tool_input":{"prompt":"Do something normal","description":"normal task"},"cwd":"'"$REPO_ROOT"'"}'
RESULT=$(echo "$NON_AUTOPILOT_JSON" | bash "$SCRIPT_DIR/auto-emit-agent-dispatch.sh" 2>/dev/null; echo $?)
assert_exit "1e. dispatch non-autopilot Task → exit 0" 0 "$RESULT"
# 1e'. 内容校验：non-autopilot Task 不应生成 .active-agent-id（hook 跳过）
if [ ! -f "$REPO_ROOT/logs/.active-agent-id" ]; then
  green "  PASS: 1e'. non-autopilot Task did NOT create .active-agent-id (skipped correctly)"
  PASS=$((PASS + 1))
else
  red "  FAIL: 1e'. non-autopilot Task unexpectedly created .active-agent-id"
  FAIL=$((FAIL + 1))
fi

# 1f. dispatch hook exits 0 for checkpoint-writer Task
CHECKPOINT_JSON='{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:2 --> <!-- checkpoint-writer --> write checkpoint","description":"checkpoint writer"},"cwd":"'"$REPO_ROOT"'"}'
RESULT=$(echo "$CHECKPOINT_JSON" | bash "$SCRIPT_DIR/auto-emit-agent-dispatch.sh" 2>/dev/null; echo $?)
assert_exit "1f. dispatch checkpoint-writer → exit 0 (skipped)" 0 "$RESULT"
# 1f'. 内容校验：checkpoint-writer 也应被跳过，不写 .active-agent-id
if [ ! -f "$REPO_ROOT/logs/.active-agent-id" ]; then
  green "  PASS: 1f'. checkpoint-writer Task did NOT create .active-agent-id (skipped correctly)"
  PASS=$((PASS + 1))
else
  red "  FAIL: 1f'. checkpoint-writer Task unexpectedly created .active-agent-id"
  FAIL=$((FAIL + 1))
fi

# 1g. dispatch hook processes valid autopilot Task
VALID_JSON='{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:2 --> Generate OpenSpec","description":"OpenSpec generation"},"cwd":"'"$REPO_ROOT"'"}'
# Create logs dir and events.jsonl for the test
mkdir -p "$REPO_ROOT/logs" 2>/dev/null || true
RESULT=$(echo "$VALID_JSON" | bash "$SCRIPT_DIR/auto-emit-agent-dispatch.sh" 2>/dev/null; echo $?)
assert_exit "1g. dispatch valid autopilot Task → exit 0" 0 "$RESULT"
# 1g'. 内容校验：events.jsonl 应包含 agent dispatch 相关事件并带 phase 字段
EVENTS_FILE="$REPO_ROOT/logs/events.jsonl"
if [ -f "$EVENTS_FILE" ] && grep -q "agent" "$EVENTS_FILE" && grep -q '"phase"' "$EVENTS_FILE"; then
  green "  PASS: 1g'. events.jsonl contains agent event with phase field"
  PASS=$((PASS + 1))
else
  red "  FAIL: 1g'. events.jsonl missing agent event or phase field (file=$EVENTS_FILE)"
  FAIL=$((FAIL + 1))
fi

# 1h. Verify .active-agent-id file was written
if [ -f "$REPO_ROOT/logs/.active-agent-id" ]; then
  AGENT_ID=$(cat "$REPO_ROOT/logs/.active-agent-id")
  if grep -q "phase2" <<< "$AGENT_ID"; then
    green "  PASS: 1h. .active-agent-id contains phase2 agent_id"
    PASS=$((PASS + 1))
  else
    red "  FAIL: 1h. .active-agent-id wrong content: $AGENT_ID"
    FAIL=$((FAIL + 1))
  fi
else
  red "  FAIL: 1h. .active-agent-id file not created"
  FAIL=$((FAIL + 1))
fi

# 1i. Verify dispatch timestamp file was written
DISPATCH_TS_FILE=$(find "$REPO_ROOT/logs" -name ".agent-dispatch-ts-phase2*" 2>/dev/null | head -1)
if [ -n "$DISPATCH_TS_FILE" ] && [ -f "$DISPATCH_TS_FILE" ]; then
  green "  PASS: 1i. dispatch timestamp file exists"
  PASS=$((PASS + 1))
else
  red "  FAIL: 1i. dispatch timestamp file not created"
  FAIL=$((FAIL + 1))
fi

# Cleanup
rm -f "$REPO_ROOT/logs/.active-agent-id" "$REPO_ROOT/logs/.agent-dispatch-ts-"* 2>/dev/null || true
rm -f "$REPO_ROOT/logs/.active-agent-phase-"* "$REPO_ROOT/logs/.active-agent-session-"* 2>/dev/null || true
rm -f "$REPO_ROOT/logs/agent-dispatch-record.json" 2>/dev/null || true
rm -f "$REPO_ROOT/logs/events.jsonl" 2>/dev/null || true
rm -f "$REPO_ROOT/logs/.event_sequence" 2>/dev/null || true
rmdir "$REPO_ROOT/logs/.event_sequence.lk" 2>/dev/null || true
rmdir "$REPO_ROOT/logs" 2>/dev/null || true

# ────────────────────────────────────────
# Phase 1 research pre-marker guards (config-driven)
# ─────────────────���──────────────────────
echo "--- Phase 1 research pre-marker guards (config-driven) ---"

# Setup temp project root with autopilot.config.yaml
TMP_PROJECT=$(mktemp -d)
trap 'rm -rf "$TMP_PROJECT"' EXIT
mkdir -p "$TMP_PROJECT/.claude" "$TMP_PROJECT/openspec/changes"
cat > "$TMP_PROJECT/.claude/autopilot.config.yaml" <<'YAML'
phases:
  requirements:
    agent: "my-analyst"
    research:
      agent: "my-researcher"
YAML
echo '{"change":"test","pid":"99999"}' > "$TMP_PROJECT/openspec/changes/.autopilot-active"

# 2a. dispatch agent matches config → 放行
MATCH_JSON='{"tool_name":"Task","tool_input":{"subagent_type":"my-researcher","description":"tech research","prompt":"调研 输出: openspec/changes/foo/context/research-findings.md"},"cwd":"'"$TMP_PROJECT"'"}'
OUT=$(echo "$MATCH_JSON" | bash "$SCRIPT_DIR/auto-emit-agent-dispatch.sh" 2>/dev/null || true)
if echo "$OUT" | grep -q '"decision":"block"'; then
  red "  FAIL: 2a. matched agent should not be blocked, got: $OUT"
  FAIL=$((FAIL + 1))
else
  green "  PASS: 2a. dispatch=my-researcher matches config → 放行"
  PASS=$((PASS + 1))
fi

# 2b. dispatch agent != config → block（运行时禁止偏离）
MISMATCH_JSON='{"tool_name":"Task","tool_input":{"subagent_type":"Explore","description":"tech research","prompt":"调研 输出: research-findings.md"},"cwd":"'"$TMP_PROJECT"'"}'
OUT=$(echo "$MISMATCH_JSON" | bash "$SCRIPT_DIR/auto-emit-agent-dispatch.sh" 2>/dev/null || true)
if echo "$OUT" | grep -q '"decision":"block"' && echo "$OUT" | grep -q 'my-researcher'; then
  green "  PASS: 2b. dispatch=Explore != config=my-researcher → block"
  PASS=$((PASS + 1))
else
  red "  FAIL: 2b. expected mismatch block, got: $OUT"
  FAIL=$((FAIL + 1))
fi

# 2c. 缺失 subagent_type + research 模式 → block
MISSING_JSON='{"tool_name":"Task","tool_input":{"description":"research","prompt":"输出到 research-findings.md"},"cwd":"'"$TMP_PROJECT"'"}'
OUT=$(echo "$MISSING_JSON" | bash "$SCRIPT_DIR/auto-emit-agent-dispatch.sh" 2>/dev/null || true)
if echo "$OUT" | grep -q '"decision":"block"' && echo "$OUT" | grep -q 'subagent_type'; then
  green "  PASS: 2c. missing subagent_type → block"
  PASS=$((PASS + 1))
else
  red "  FAIL: 2c. expected block, got: $OUT"
  FAIL=$((FAIL + 1))
fi

# 2d. Auto-Scan 任务（project-context.md）使用 phases.requirements.agent
SCAN_OK_JSON='{"tool_name":"Task","tool_input":{"subagent_type":"my-analyst","description":"auto scan","prompt":"分析项目结构 输出 project-context.md"},"cwd":"'"$TMP_PROJECT"'"}'
OUT=$(echo "$SCAN_OK_JSON" | bash "$SCRIPT_DIR/auto-emit-agent-dispatch.sh" 2>/dev/null || true)
if echo "$OUT" | grep -q '"decision":"block"'; then
  red "  FAIL: 2d. Auto-Scan with matching agent should pass, got: $OUT"
  FAIL=$((FAIL + 1))
else
  green "  PASS: 2d. Auto-Scan dispatch=my-analyst matches phases.requirements.agent → 放行"
  PASS=$((PASS + 1))
fi

# 2e. Auto-Scan dispatch != requirements.agent → block
SCAN_BAD_JSON='{"tool_name":"Task","tool_input":{"subagent_type":"Explore","description":"auto scan","prompt":"分析项目结构 输出 existing-patterns.md"},"cwd":"'"$TMP_PROJECT"'"}'
OUT=$(echo "$SCAN_BAD_JSON" | bash "$SCRIPT_DIR/auto-emit-agent-dispatch.sh" 2>/dev/null || true)
if echo "$OUT" | grep -q '"decision":"block"' && echo "$OUT" | grep -q 'my-analyst'; then
  green "  PASS: 2e. Auto-Scan dispatch=Explore != config=my-analyst → block"
  PASS=$((PASS + 1))
else
  red "  FAIL: 2e. expected block, got: $OUT"
  FAIL=$((FAIL + 1))
fi

# 2f. config 缺失字段 → block 并提示运行 setup
TMP_NOCONFIG=$(mktemp -d)
mkdir -p "$TMP_NOCONFIG/.claude" "$TMP_NOCONFIG/openspec/changes"
cat > "$TMP_NOCONFIG/.claude/autopilot.config.yaml" <<'YAML'
phases:
  requirements: {}
YAML
echo '{"change":"test","pid":"99999"}' > "$TMP_NOCONFIG/openspec/changes/.autopilot-active"
NOCONFIG_JSON='{"tool_name":"Task","tool_input":{"subagent_type":"foo","description":"research","prompt":"输出 research-findings.md"},"cwd":"'"$TMP_NOCONFIG"'"}'
OUT=$(echo "$NOCONFIG_JSON" | bash "$SCRIPT_DIR/auto-emit-agent-dispatch.sh" 2>/dev/null || true)
if echo "$OUT" | grep -q '"decision":"block"' && echo "$OUT" | grep -q 'autopilot-setup'; then
  green "  PASS: 2f. config 字段为空 → block 提示 setup"
  PASS=$((PASS + 1))
else
  red "  FAIL: 2f. expected block with setup hint, got: $OUT"
  FAIL=$((FAIL + 1))
fi
rm -rf "$TMP_NOCONFIG"

# 2g. 普通 prompt（无 research/scan 输出路径）→ guard 不介入
NORMAL_JSON='{"tool_name":"Task","tool_input":{"subagent_type":"Explore","description":"normal","prompt":"分析代码"},"cwd":"'"$TMP_PROJECT"'"}'
OUT=$(echo "$NORMAL_JSON" | bash "$SCRIPT_DIR/auto-emit-agent-dispatch.sh" 2>/dev/null || true)
if echo "$OUT" | grep -q '"decision":"block"'; then
  red "  FAIL: 2g. unrelated prompt should not be blocked by Phase 1 guard, got: $OUT"
  FAIL=$((FAIL + 1))
else
  green "  PASS: 2g. unrelated prompt → guard 不介入"
  PASS=$((PASS + 1))
fi

teardown_autopilot_fixture
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1; exit 0

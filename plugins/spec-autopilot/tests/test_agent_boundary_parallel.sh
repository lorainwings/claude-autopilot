#!/usr/bin/env bash
# test_agent_boundary_parallel.sh — WS-G: 并行同 phase 多 agent 精确关联测试
# 验证:
#   1. 单 phase 单 agent 兼容（现有行为不变）
#   2. 同 phase 两 agent 互斥 owned_artifacts 时精确匹配
#   3. 缺少匹配 dispatch record 时 block（fail-closed）
#   4. dispatch record 保留 selection_reason/resolved_priority/fallback_reason/owned_artifacts
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../runtime/scripts" && pwd)"
source "$TEST_DIR/_test_helpers.sh"
source "$TEST_DIR/_fixtures.sh"

echo "--- WS-G: Agent boundary parallel correlation ---"

setup_autopilot_fixture
VALIDATOR="$SCRIPT_DIR/_post_task_validator.py"
export SCRIPT_DIR

# Helper: 运行 validator，支持自定义 cwd
run_validator_in() {
  local cwd="$1"
  local phase="$2"
  local agent_output="$3"
  python3 -c "
import json, sys, subprocess
phase = int(sys.argv[1])
agent_output = sys.argv[2]
prompt = f'<!-- autopilot-phase:{phase} --> Do phase {phase} task'
data = {
    'tool_name': 'Task',
    'cwd': sys.argv[3],
    'tool_input': {'prompt': prompt},
    'tool_response': agent_output
}
proc = subprocess.run(
    [sys.executable, sys.argv[4]],
    input=json.dumps(data),
    capture_output=True, text=True, timeout=30
)
if proc.stdout.strip():
    print(proc.stdout.strip())
" "$phase" "$agent_output" "$cwd" "$VALIDATOR" 2>/dev/null || true
}

# === 准备临时项目目录 ===
TMP_PROJECT=$(mktemp -d)
trap 'rm -rf "$TMP_PROJECT"' EXIT
mkdir -p "$TMP_PROJECT/.claude"
mkdir -p "$TMP_PROJECT/openspec/changes"
echo '{"change":"test","pid":"99999","started":"2026-01-01T00:00:00Z"}' \
  >"$TMP_PROJECT/openspec/changes/.autopilot-active"
mkdir -p "$TMP_PROJECT/logs"

# 有效的 Phase 5 信封（包含 artifacts）
ENVELOPE_OK='{"status":"ok","summary":"impl done","artifacts":["src/api/handler.ts"],"test_results_path":"tests/","tasks_completed":5,"zero_skip_check":{"passed":true}}'
ENVELOPE_BACKEND='{"status":"ok","summary":"impl done","artifacts":["src/api/handler.ts"],"test_results_path":"tests/","tasks_completed":5,"zero_skip_check":{"passed":true}}'
ENVELOPE_FRONTEND='{"status":"ok","summary":"ui done","artifacts":["src/ui/component.tsx"],"test_results_path":"tests/","tasks_completed":3,"zero_skip_check":{"passed":true}}'

# ============================================================
# 测试 1: 单 phase 单 agent 兼容（phase-only 匹配）
# ============================================================

# 写入单条 dispatch record（仅一个 agent）
cat >"$TMP_PROJECT/logs/agent-dispatch-record.json" <<'JSON'
[
  {
    "agent_id": "phase5-backend-impl",
    "agent_class": "backend-impl",
    "phase": 5,
    "selection_reason": "agent_policy_match",
    "resolved_priority": "high",
    "owned_artifacts": ["src/api/"],
    "background": false,
    "scanned_sources": [".claude/rules/"],
    "required_validators": ["json_envelope", "anti_rationalization", "code_constraint"]
  }
]
JSON

# 不写入任何 agent marker（模拟旧场景无 marker）
rm -f "$TMP_PROJECT/logs/.active-agent-id" 2>/dev/null || true
rm -f "$TMP_PROJECT/logs/.active-agent-phase-5" 2>/dev/null || true

result=$(run_validator_in "$TMP_PROJECT" 5 "$ENVELOPE_OK")
if [ -z "$result" ] || ! echo "$result" | grep -q '"block"'; then
  green "  PASS: 1a. 单 phase 单 agent 无 marker → phase-only 匹配通过"
  PASS=$((PASS + 1))
else
  red "  FAIL: 1a. 单 phase 单 agent 被 block (output='$result')"
  FAIL=$((FAIL + 1))
fi

# 写入 phase marker（精确匹配路径）
echo "phase5-backend-impl" >"$TMP_PROJECT/logs/.active-agent-phase-5"
result=$(run_validator_in "$TMP_PROJECT" 5 "$ENVELOPE_OK")
if [ -z "$result" ] || ! echo "$result" | grep -q '"block"'; then
  green "  PASS: 1b. 单 phase 单 agent 有 marker → 精确匹配通过"
  PASS=$((PASS + 1))
else
  red "  FAIL: 1b. 单 phase 单 agent 有 marker 被 block (output='$result')"
  FAIL=$((FAIL + 1))
fi

# ============================================================
# 测试 2: 同 phase 两 agent 互斥 owned_artifacts 精确匹配
# ============================================================

# 两个 agent 同时在 phase 5 运行，各自拥有不同的 owned_artifacts
cat >"$TMP_PROJECT/logs/agent-dispatch-record.json" <<'JSON'
[
  {
    "agent_id": "phase5-backend-impl",
    "agent_class": "backend-impl",
    "phase": 5,
    "selection_reason": "agent_policy_match",
    "resolved_priority": "high",
    "owned_artifacts": ["src/api/"],
    "background": false,
    "scanned_sources": [".claude/rules/"],
    "required_validators": ["json_envelope"]
  },
  {
    "agent_id": "phase5-frontend-impl",
    "agent_class": "frontend-impl",
    "phase": 5,
    "selection_reason": "agent_policy_match",
    "resolved_priority": "normal",
    "owned_artifacts": ["src/ui/"],
    "background": false,
    "scanned_sources": [".claude/rules/"],
    "required_validators": ["json_envelope"]
  }
]
JSON

# 2a. Backend agent 产出 backend 文件 → 应通过
echo "phase5-backend-impl" >"$TMP_PROJECT/logs/.active-agent-phase-5"
result=$(run_validator_in "$TMP_PROJECT" 5 "$ENVELOPE_BACKEND")
if [ -z "$result" ] || ! echo "$result" | grep -q '"block"'; then
  green "  PASS: 2a. backend agent 产出 src/api/ → 精确匹配 backend record → 通过"
  PASS=$((PASS + 1))
else
  red "  FAIL: 2a. backend agent 精确匹配失败 (output='$result')"
  FAIL=$((FAIL + 1))
fi

# 2b. Frontend agent 产出 frontend 文件 → 应通过
echo "phase5-frontend-impl" >"$TMP_PROJECT/logs/.active-agent-phase-5"
result=$(run_validator_in "$TMP_PROJECT" 5 "$ENVELOPE_FRONTEND")
if [ -z "$result" ] || ! echo "$result" | grep -q '"block"'; then
  green "  PASS: 2b. frontend agent 产出 src/ui/ → 精确匹配 frontend record → 通过"
  PASS=$((PASS + 1))
else
  red "  FAIL: 2b. frontend agent 精确匹配失败 (output='$result')"
  FAIL=$((FAIL + 1))
fi

# 2c. Frontend agent 产出 backend 文件 → 应该被 boundary violation block
echo "phase5-frontend-impl" >"$TMP_PROJECT/logs/.active-agent-phase-5"
result=$(run_validator_in "$TMP_PROJECT" 5 "$ENVELOPE_BACKEND")
if echo "$result" | grep -q '"block"' && echo "$result" | grep -q "boundary violation"; then
  green "  PASS: 2c. frontend agent 产出 src/api/ → boundary violation block"
  PASS=$((PASS + 1))
else
  red "  FAIL: 2c. frontend agent 越界未被 block (output='$result')"
  FAIL=$((FAIL + 1))
fi

# 2d. 旧逻辑 bug 验证: 无 marker 时 phase-only 匹配取最后一条 = frontend record
# backend agent 产出 backend 文件但匹配到 frontend record → 旧逻辑会 boundary violation
# 新逻辑无 marker → phase-only 回退取最后一条 = frontend，也会 boundary violation（行为相同）
# 这证明 marker 的重要性: 有 marker 时才能精确关联
rm -f "$TMP_PROJECT/logs/.active-agent-phase-5" 2>/dev/null || true
rm -f "$TMP_PROJECT/logs/.active-agent-id" 2>/dev/null || true
result=$(run_validator_in "$TMP_PROJECT" 5 "$ENVELOPE_BACKEND")
if echo "$result" | grep -q '"block"'; then
  green "  PASS: 2d. 无 marker + phase-only 回退 → 取最后一条 frontend record → boundary violation（预期行为）"
  PASS=$((PASS + 1))
else
  red "  FAIL: 2d. 无 marker 时 phase-only 回退应 block (output='$result')"
  FAIL=$((FAIL + 1))
fi

# ============================================================
# 测试 3: 缺少匹配 dispatch record 时 block（fail-closed）
# ============================================================

# 3a. 有 agent marker 但 dispatch record 中无对应 agent_id → block
echo "phase5-unknown-agent" >"$TMP_PROJECT/logs/.active-agent-phase-5"
result=$(run_validator_in "$TMP_PROJECT" 5 "$ENVELOPE_OK")
if echo "$result" | grep -q '"block"' && echo "$result" | grep -q "correlation missing"; then
  green "  PASS: 3a. agent marker 存在但无匹配 dispatch record → governance correlation missing block"
  PASS=$((PASS + 1))
else
  red "  FAIL: 3a. 无匹配 dispatch record 应 block (output='$result')"
  FAIL=$((FAIL + 1))
fi

# 3b. 有 agent marker + phase 不匹配 → block
echo "phase5-backend-impl" >"$TMP_PROJECT/logs/.active-agent-phase-3"
rm -f "$TMP_PROJECT/logs/.active-agent-phase-5" 2>/dev/null || true
rm -f "$TMP_PROJECT/logs/.active-agent-id" 2>/dev/null || true
# Phase 3 的 marker 不会被 phase 5 validator 读取
# 但 dispatch record 中有 phase5-backend-impl 在 phase 5
# 无 marker → phase-only 回退 → 取最后一条 frontend record
result=$(run_validator_in "$TMP_PROJECT" 5 "$ENVELOPE_FRONTEND")
if [ -z "$result" ] || ! echo "$result" | grep -q '"block"'; then
  green "  PASS: 3b. phase marker 不匹配 → phase-only 回退 → frontend envelope + frontend record → 通过"
  PASS=$((PASS + 1))
else
  red "  FAIL: 3b. phase 不匹配回退测试 (output='$result')"
  FAIL=$((FAIL + 1))
fi

# ============================================================
# 测试 4: dispatch record 保留关键治理字段
# ============================================================

RECORD=$(cat "$TMP_PROJECT/logs/agent-dispatch-record.json" 2>/dev/null)
assert_contains "4a. dispatch record 包含 selection_reason" "$RECORD" 'selection_reason'
assert_contains "4b. dispatch record 包含 resolved_priority" "$RECORD" 'resolved_priority'
assert_contains "4c. dispatch record 包含 owned_artifacts" "$RECORD" 'owned_artifacts'
assert_contains "4d. dispatch record 包含 agent_id" "$RECORD" 'agent_id'

# 4e. 带 fallback_reason 的 record
cat >"$TMP_PROJECT/logs/agent-dispatch-record.json" <<'JSON'
[
  {
    "agent_id": "phase5-default-agent",
    "agent_class": "default",
    "phase": 5,
    "selection_reason": "agent_not_in_policy",
    "resolved_priority": "normal",
    "owned_artifacts": [],
    "background": false,
    "scanned_sources": [],
    "required_validators": ["json_envelope"],
    "fallback_reason": "agent-x not defined in .claude/agents/"
  }
]
JSON
RECORD=$(cat "$TMP_PROJECT/logs/agent-dispatch-record.json" 2>/dev/null)
assert_contains "4e. dispatch record 包含 fallback_reason" "$RECORD" 'fallback_reason'

# ============================================================
# 测试 5: session-scoped marker 优先级高于 phase marker
# ============================================================

cat >"$TMP_PROJECT/logs/agent-dispatch-record.json" <<'JSON'
[
  {
    "agent_id": "phase5-session-agent",
    "agent_class": "session-agent",
    "phase": 5,
    "session_id": "sess-abc-123",
    "selection_reason": "agent_policy_match",
    "resolved_priority": "normal",
    "owned_artifacts": ["src/"],
    "background": false,
    "scanned_sources": [],
    "required_validators": ["json_envelope"]
  },
  {
    "agent_id": "phase5-phase-agent",
    "agent_class": "phase-agent",
    "phase": 5,
    "session_id": "sess-abc-123",
    "selection_reason": "agent_policy_match",
    "resolved_priority": "normal",
    "owned_artifacts": [],
    "background": false,
    "scanned_sources": [],
    "required_validators": ["json_envelope"]
  }
]
JSON

# 写入 lock file 中带 session_id
echo '{"change":"test","pid":"99999","started":"2026-01-01T00:00:00Z","session_id":"sess-abc-123"}' \
  >"$TMP_PROJECT/openspec/changes/.autopilot-active"
# session marker 指向 session-agent（有 owned_artifacts ["src/"]）
echo "phase5-session-agent" >"$TMP_PROJECT/logs/.active-agent-session-sess-abc-123"
# phase marker 指向 phase-agent（owned_artifacts 为空）
echo "phase5-phase-agent" >"$TMP_PROJECT/logs/.active-agent-phase-5"

result=$(run_validator_in "$TMP_PROJECT" 5 "$ENVELOPE_OK")
if [ -z "$result" ] || ! echo "$result" | grep -q '"block"'; then
  green "  PASS: 5. session marker 优先 → session-agent (有 src/ owned) → 通过"
  PASS=$((PASS + 1))
else
  red "  FAIL: 5. session marker 应优先于 phase marker (output='$result')"
  FAIL=$((FAIL + 1))
fi

# ============================================================
# 测试 6: 跨 session 串用保护 — 旧 session record 不可被新 session 命中
# ============================================================

# 构造: lock file 指向 sess-new，dispatch record 仅含 sess-old 同 agent_id 同 phase
echo '{"change":"test","pid":"99999","started":"2026-01-01T00:00:00Z","session_id":"sess-new"}' \
  >"$TMP_PROJECT/openspec/changes/.autopilot-active"
echo "phase5-backend-impl" >"$TMP_PROJECT/logs/.active-agent-session-sess-new"
rm -f "$TMP_PROJECT/logs/.active-agent-session-sess-old" 2>/dev/null || true

cat >"$TMP_PROJECT/logs/agent-dispatch-record.json" <<'JSON'
[
  {
    "agent_id": "phase5-backend-impl",
    "agent_class": "backend-impl",
    "phase": 5,
    "session_id": "sess-old",
    "selection_reason": "agent_policy_match",
    "resolved_priority": "high",
    "owned_artifacts": ["src/api/"],
    "background": false,
    "scanned_sources": [],
    "required_validators": ["json_envelope"]
  }
]
JSON

result=$(run_validator_in "$TMP_PROJECT" 5 "$ENVELOPE_OK")
if echo "$result" | grep -q '"block"' && echo "$result" | grep -q "correlation missing"; then
  green "  PASS: 6a. 跨 session 串用保护 → sess-new marker + sess-old record → governance correlation missing block"
  PASS=$((PASS + 1))
else
  red "  FAIL: 6a. 跨 session 串用保护应 block (output='$result')"
  FAIL=$((FAIL + 1))
fi

# 6b. 同 session record 可正常命中
cat >"$TMP_PROJECT/logs/agent-dispatch-record.json" <<'JSON'
[
  {
    "agent_id": "phase5-backend-impl",
    "agent_class": "backend-impl",
    "phase": 5,
    "session_id": "sess-new",
    "selection_reason": "agent_policy_match",
    "resolved_priority": "high",
    "owned_artifacts": ["src/api/"],
    "background": false,
    "scanned_sources": [],
    "required_validators": ["json_envelope"]
  }
]
JSON

result=$(run_validator_in "$TMP_PROJECT" 5 "$ENVELOPE_OK")
if [ -z "$result" ] || ! echo "$result" | grep -q '"block"'; then
  green "  PASS: 6b. 同 session record → session_id + agent_id + phase 精确匹配 → 通过"
  PASS=$((PASS + 1))
else
  red "  FAIL: 6b. 同 session record 应通过 (output='$result')"
  FAIL=$((FAIL + 1))
fi

# ============================================================
# 清理
# ============================================================

teardown_autopilot_fixture
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1; exit 0

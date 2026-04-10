#!/usr/bin/env bash
# test_agent_priority_enforcement.sh — WS-E: Agent priority & dispatch governance tests
# Verifies:
#   1. rules-scanner.sh scans .claude/agents/ and extracts agent priority
#   2. rules-scanner.sh scans plugin CLAUDE.md
#   3. auto-emit-agent-dispatch.sh writes dispatch record with governance fields
#   4. post-task-validator validates artifact boundary
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../runtime/scripts" && pwd)"
source "$TEST_DIR/_test_helpers.sh"
source "$TEST_DIR/_fixtures.sh"

echo "--- WS-E: Agent priority enforcement ---"

# Self-contained temp directory
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# === 1. rules-scanner: scan .claude/agents/ ===

# 1a. No agents dir → agents_found: false
output=$(bash "$SCRIPT_DIR/rules-scanner.sh" "$TMPDIR" 2>/dev/null)
assert_contains "1a. no agents dir → agents_found false" "$output" '"agents_found":false'

# 1b. Create agents dir with agent definition
mkdir -p "$TMPDIR/.claude/agents"
cat > "$TMPDIR/.claude/agents/backend-developer.md" << 'EOF'
# Backend Developer Agent

priority: high
domain: backend, node
required_for_phase: 5, 6
EOF
output=$(bash "$SCRIPT_DIR/rules-scanner.sh" "$TMPDIR" 2>/dev/null)
assert_contains "1b. agents dir scanned → agents_found true" "$output" '"agents_found": true'
assert_contains "1b. agent name extracted" "$output" '"name": "backend-developer"'
assert_contains "1b. agent priority extracted" "$output" '"priority": "high"'
assert_contains "1b. scanned_sources includes agents" "$output" '.claude/agents/'

# 1c. Agent priority map present
assert_contains "1c. agent_priority_map present" "$output" '"agent_priority_map"'
assert_contains "1c. priority map has backend-developer" "$output" '"backend-developer"'

# === 2. rules-scanner: scan plugin CLAUDE.md ===

# 2a. Plugin CLAUDE.md scanned
mkdir -p "$TMPDIR/plugins/test-plugin"
cat > "$TMPDIR/plugins/test-plugin/CLAUDE.md" << 'EOF'
# Test Plugin Rules
禁止 `console.log`
必须 `strict mode`
EOF
output=$(bash "$SCRIPT_DIR/rules-scanner.sh" "$TMPDIR" --plugin-root "$TMPDIR/plugins/test-plugin" 2>/dev/null)
assert_contains "2a. plugin CLAUDE.md scanned" "$output" 'plugins/test-plugin/CLAUDE.md'
assert_contains "2a. plugin rules extracted (forbidden)" "$output" 'console.log'
assert_contains "2a. plugin rules extracted (required)" "$output" 'strict mode'

# === 3. rules-scanner: phase-local rules ===
cat > "$TMPDIR/phase-rules.md" << 'EOF'
# Phase 5 Local Rules
禁止 `eval()`
EOF
output=$(bash "$SCRIPT_DIR/rules-scanner.sh" "$TMPDIR" --phase-rules "$TMPDIR/phase-rules.md" 2>/dev/null)
assert_contains "3. phase-local rules scanned" "$output" 'eval()'

# === 4. rules-scanner: scanned_sources always reported ===
output=$(bash "$SCRIPT_DIR/rules-scanner.sh" "$TMPDIR" 2>/dev/null)
assert_contains "4. scanned_sources field present" "$output" '"scanned_sources"'

# === 5. Dispatch record: dispatch writes agent-dispatch-record.json ===
setup_autopilot_fixture
mkdir -p "$REPO_ROOT/logs" 2>/dev/null || true

# 写入带 session_id 的 lock file，确保 dispatch 能提取 session_id
echo '{"change":"test","pid":"99999","started":"2026-01-01T00:00:00Z","session_id":"sess-test-001"}' \
  >"$REPO_ROOT/openspec/changes/.autopilot-active"

# Write a rules-scanner cache for the dispatch hook to consume
cat > "$REPO_ROOT/logs/.rules-scanner-cache.json" << 'CACHE'
{
  "agents_found": true,
  "agent_priority_map": {
    "openspec-generator": {
      "priority": "high",
      "domains": ["openspec"],
      "required_phases": [2, 3],
      "forbidden_phases": []
    }
  },
  "scanned_sources": [".claude/rules/", "CLAUDE.md", ".claude/agents/"]
}
CACHE

VALID_JSON='{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:2 --> Generate OpenSpec","description":"OpenSpec generation","subagent_type":"openspec-generator"},"cwd":"'"$REPO_ROOT"'"}'
echo "$VALID_JSON" | bash "$SCRIPT_DIR/auto-emit-agent-dispatch.sh" 2>/dev/null
RESULT=$?
assert_exit "5a. dispatch with governance fields → exit 0" 0 $RESULT

if [ -f "$REPO_ROOT/logs/agent-dispatch-record.json" ]; then
  RECORD=$(cat "$REPO_ROOT/logs/agent-dispatch-record.json" 2>/dev/null)
  assert_contains "5b. dispatch record has selection_reason" "$RECORD" 'selection_reason'
  assert_contains "5c. dispatch record has resolved_priority" "$RECORD" 'resolved_priority'
  assert_contains "5d. dispatch record has owned_artifacts" "$RECORD" 'owned_artifacts'
  assert_contains "5e. dispatch record has agent_class" "$RECORD" 'agent_class'
  assert_contains "5f. dispatch record has scanned_sources" "$RECORD" 'scanned_sources'
  assert_contains "5g. dispatch record has required_validators" "$RECORD" 'required_validators'
  assert_contains "5h. dispatch record has session_id" "$RECORD" 'session_id'
  green "  PASS: 5i. agent-dispatch-record.json file created"
  PASS=$((PASS + 1))
else
  red "  FAIL: 5h. agent-dispatch-record.json not created"
  FAIL=$((FAIL + 1))
fi

# === 6. Dispatch record: missing agents dir → fallback_reason recorded ===
cat > "$REPO_ROOT/logs/.rules-scanner-cache.json" << 'CACHE'
{
  "agents_found": false,
  "agent_priority_map": {},
  "scanned_sources": [".claude/rules/", "CLAUDE.md", ".claude/agents/ (absent)"]
}
CACHE
rm -f "$REPO_ROOT/logs/agent-dispatch-record.json" 2>/dev/null || true
echo "$VALID_JSON" | bash "$SCRIPT_DIR/auto-emit-agent-dispatch.sh" 2>/dev/null
if [ -f "$REPO_ROOT/logs/agent-dispatch-record.json" ]; then
  RECORD=$(cat "$REPO_ROOT/logs/agent-dispatch-record.json" 2>/dev/null)
  assert_contains "6. missing agents dir → fallback_reason present" "$RECORD" 'fallback_reason'
else
  red "  FAIL: 6. dispatch record not created for fallback case"
  FAIL=$((FAIL + 1))
fi

# === 7. Validator 6 精确关联: agent_id + phase 匹配 dispatch record ===
# 使用 _post_task_validator.py 直接测试 Validator 6 的精确关联逻辑

VALIDATOR="$SCRIPT_DIR/_post_task_validator.py"

# Helper: 在指定 cwd 下运行 validator
run_v6_validator() {
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
    capture_output=True, text=True, timeout=30,
    env={**dict(__import__('os').environ), 'SCRIPT_DIR': sys.argv[5]}
)
if proc.stdout.strip():
    print(proc.stdout.strip())
" "$phase" "$agent_output" "$cwd" "$VALIDATOR" "$SCRIPT_DIR" 2>/dev/null || true
}

V6_ENV=$(mktemp -d)
mkdir -p "$V6_ENV/.claude" "$V6_ENV/openspec/changes" "$V6_ENV/logs"
echo '{"change":"test","pid":"99999","started":"2026-01-01T00:00:00Z"}' \
  >"$V6_ENV/openspec/changes/.autopilot-active"

V6_ENVELOPE='{"status":"ok","summary":"impl done","artifacts":["src/api/handler.ts"],"test_results_path":"tests/","tasks_completed":5,"zero_skip_check":{"passed":true}}'

# 7a. agent marker 精确匹配 dispatch record → 通过
cat >"$V6_ENV/logs/agent-dispatch-record.json" <<'JSON'
[{"agent_id":"phase5-api","agent_class":"default","phase":5,"selection_reason":"agent_policy_match","resolved_priority":"normal","owned_artifacts":["src/api/"],"background":false,"scanned_sources":[],"required_validators":["json_envelope"]}]
JSON
echo "phase5-api" >"$V6_ENV/logs/.active-agent-phase-5"
result=$(run_v6_validator "$V6_ENV" 5 "$V6_ENVELOPE")
if [ -z "$result" ] || ! grep -q '"block"' <<< "$result"; then
  green "  PASS: 7a. agent marker 精确匹配 dispatch record → 通过"
  PASS=$((PASS + 1))
else
  red "  FAIL: 7a. 精确匹配应通过 (output='$result')"
  FAIL=$((FAIL + 1))
fi

# 7b. agent marker 无匹配 dispatch record → governance correlation missing
echo "phase5-nonexistent" >"$V6_ENV/logs/.active-agent-phase-5"
result=$(run_v6_validator "$V6_ENV" 5 "$V6_ENVELOPE")
assert_contains "7b. 无匹配 record → correlation missing block" "$result" "correlation missing"

# 7c. 无 agent marker → phase-only 回退
rm -f "$V6_ENV/logs/.active-agent-phase-5" "$V6_ENV/logs/.active-agent-id" 2>/dev/null || true
result=$(run_v6_validator "$V6_ENV" 5 "$V6_ENVELOPE")
if [ -z "$result" ] || ! grep -q '"block"' <<< "$result"; then
  green "  PASS: 7c. 无 agent marker → phase-only 回退 → 通过"
  PASS=$((PASS + 1))
else
  red "  FAIL: 7c. 无 marker 应 phase-only 回退 (output='$result')"
  FAIL=$((FAIL + 1))
fi

rm -rf "$V6_ENV" 2>/dev/null || true

# Cleanup
rm -f "$REPO_ROOT/logs/.active-agent-id" "$REPO_ROOT/logs/.agent-dispatch-ts-"* 2>/dev/null || true
rm -f "$REPO_ROOT/logs/.active-agent-phase-"* "$REPO_ROOT/logs/.active-agent-session-"* 2>/dev/null || true
rm -f "$REPO_ROOT/logs/agent-dispatch-record.json" 2>/dev/null || true
rm -f "$REPO_ROOT/logs/.rules-scanner-cache.json" 2>/dev/null || true
rm -f "$REPO_ROOT/logs/events.jsonl" 2>/dev/null || true
rm -f "$REPO_ROOT/logs/.event_sequence" 2>/dev/null || true
rmdir "$REPO_ROOT/logs/.event_sequence.lk" 2>/dev/null || true
rmdir "$REPO_ROOT/logs" 2>/dev/null || true

teardown_autopilot_fixture
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1; exit 0

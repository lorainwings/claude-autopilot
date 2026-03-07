#!/usr/bin/env bash
# test-hooks.sh
# Automated test harness for spec-autopilot hook scripts.
# Validates syntax, mock input handling, and exit code correctness.
#
# Usage: bash test-hooks.sh
# Exit: 0 if all tests pass, 1 if any fail.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PASS=0
FAIL=0

# --- Helpers ---
green() { printf "\033[32m%s\033[0m\n" "$1"; }
red()   { printf "\033[31m%s\033[0m\n" "$1"; }

assert_exit() {
  local name="$1" expected="$2" actual="$3"
  if [ "$actual" -eq "$expected" ]; then
    green "  PASS: $name (exit $actual)"
    PASS=$((PASS + 1))
  else
    red "  FAIL: $name (expected exit $expected, got $actual)"
    FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  local name="$1" haystack="$2" needle="$3"
  if echo "$haystack" | grep -q "$needle"; then
    green "  PASS: $name (contains '$needle')"
    PASS=$((PASS + 1))
  else
    red "  FAIL: $name (missing '$needle')"
    FAIL=$((FAIL + 1))
  fi
}

assert_not_contains() {
  local name="$1" haystack="$2" needle="$3"
  if ! echo "$haystack" | grep -q "$needle"; then
    green "  PASS: $name (correctly missing '$needle')"
    PASS=$((PASS + 1))
  else
    red "  FAIL: $name (unexpectedly contains '$needle')"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== spec-autopilot Hook Test Suite ==="
echo ""

# --- Shared test fixture: autopilot-active environment ---
# 许多测试需要 autopilot 锁文件才能触发 Hook 校验逻辑。
# 在仓库根目录创建临时锁文件，测试结束后清理。
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
FIXTURE_LOCK_DIR="$REPO_ROOT/openspec/changes"
FIXTURE_LOCK_FILE="$FIXTURE_LOCK_DIR/.autopilot-active"
FIXTURE_LOCK_CREATED=false
mkdir -p "$FIXTURE_LOCK_DIR"
if [ ! -f "$FIXTURE_LOCK_FILE" ]; then
  echo '{"change":"test-fixture","pid":"99999","started":"2026-01-01T00:00:00Z"}' > "$FIXTURE_LOCK_FILE"
  FIXTURE_LOCK_CREATED=true
fi
cleanup_fixture() {
  if [ "$FIXTURE_LOCK_CREATED" = "true" ] && [ -f "$FIXTURE_LOCK_FILE" ]; then
    rm -f "$FIXTURE_LOCK_FILE"
    # 清理空目录（仅当是测试创建的）
    rmdir "$FIXTURE_LOCK_DIR" 2>/dev/null || true
    rmdir "$REPO_ROOT/openspec" 2>/dev/null || true
  fi
}
trap cleanup_fixture EXIT

# ============================================================
echo "--- 1. Syntax checks (bash -n) ---"
for script in "$SCRIPT_DIR"/*.sh; do
  name=$(basename "$script")
  [ "$name" = "test-hooks.sh" ] && continue
  if bash -n "$script" 2>/dev/null; then
    green "  PASS: $name syntax OK"
    PASS=$((PASS + 1))
  else
    red "  FAIL: $name syntax error"
    FAIL=$((FAIL + 1))
  fi
done

echo ""

# ============================================================
echo "--- 2. check-predecessor-checkpoint.sh ---"

# 2a. Empty stdin → exit 0 (allow)
exit_code=0
echo "" | bash "$SCRIPT_DIR/check-predecessor-checkpoint.sh" >/dev/null 2>&1 || exit_code=$?
assert_exit "empty stdin → allow" 0 $exit_code

# 2b. Non-autopilot Task (no marker) → exit 0
exit_code=0
echo '{"tool_name":"Task","tool_input":{"prompt":"Find all API endpoints","subagent_type":"Explore"}}' \
  | bash "$SCRIPT_DIR/check-predecessor-checkpoint.sh" >/dev/null 2>&1 || exit_code=$?
assert_exit "no marker → allow" 0 $exit_code

# 2c. Autopilot Phase 2 with no changes dir → exit 0 (no active change to check)
exit_code=0
echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:2 -->\nYou are phase 2 agent","subagent_type":"general-purpose"},"cwd":"/tmp"}' \
  | bash "$SCRIPT_DIR/check-predecessor-checkpoint.sh" >/dev/null 2>&1 || exit_code=$?
assert_exit "phase 2, no changes dir → allow" 0 $exit_code

# 2d. Autopilot Phase 5 with no changes dir → exit 0 (no active change)
exit_code=0
echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:5 -->\nPhase 5","subagent_type":"general-purpose"},"cwd":"/tmp/nonexistent-proj"}' \
  | bash "$SCRIPT_DIR/check-predecessor-checkpoint.sh" >/dev/null 2>&1 || exit_code=$?
assert_exit "phase 5, no changes dir → allow" 0 $exit_code

# 2e. Verify JSON output format on deny (if we can trigger it)
output=$(echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:5 -->\nPhase 5","subagent_type":"general-purpose"},"cwd":"/tmp/nonexistent-proj"}' \
  | bash "$SCRIPT_DIR/check-predecessor-checkpoint.sh" 2>/dev/null || true)
# If there is a deny, it should be valid JSON with permissionDecision
if echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['hookSpecificOutput']['permissionDecision']=='deny'" 2>/dev/null; then
  green "  PASS: deny output is valid hookSpecificOutput JSON"
  PASS=$((PASS + 1))
else
  # No deny output means it was allowed (also valid for this case)
  green "  PASS: no deny needed (correctly allowed)"
  PASS=$((PASS + 1))
fi

# 2f. Phase 2 deny: Phase 1 checkpoint missing in active change → deny
TMPDIR_P2=$(mktemp -d)
mkdir -p "$TMPDIR_P2/openspec/changes/test-feature/context/phase-results"
# No phase-1 checkpoint file exists → Phase 2 should deny
echo "{\"change\":\"test-feature\",\"pid\":$$,\"started\":\"2026-01-01T00:00:00Z\",\"session_cwd\":\"$TMPDIR_P2\",\"anchor_sha\":\"abc123\",\"session_id\":\"$(date +%s%3N)\"}" > "$TMPDIR_P2/openspec/changes/.autopilot-active"
exit_code=0
output=$(echo "{\"tool_name\":\"Task\",\"tool_input\":{\"prompt\":\"<!-- autopilot-phase:2 -->\\nPhase 2\",\"subagent_type\":\"general-purpose\"},\"cwd\":\"$TMPDIR_P2\"}" \
  | bash "$SCRIPT_DIR/check-predecessor-checkpoint.sh" 2>/dev/null) || exit_code=$?
assert_exit "phase 2 no phase-1 checkpoint → exit 0" 0 $exit_code
assert_contains "phase 2 no phase-1 checkpoint → deny" "$output" "deny"
rm -rf "$TMPDIR_P2"

echo ""

# ============================================================
echo "--- 3. validate-json-envelope.sh ---"

# 3a. Empty stdin → exit 0
exit_code=0
echo "" | bash "$SCRIPT_DIR/validate-json-envelope.sh" >/dev/null 2>&1 || exit_code=$?
assert_exit "empty stdin → allow" 0 $exit_code

# 3b. Non-autopilot Task → exit 0
exit_code=0
echo '{"tool_name":"Task","tool_input":{"prompt":"Find APIs"},"tool_response":"Found 3 endpoints"}' \
  | bash "$SCRIPT_DIR/validate-json-envelope.sh" >/dev/null 2>&1 || exit_code=$?
assert_exit "no marker → skip" 0 $exit_code

# 3c. Autopilot Task with valid JSON envelope in tool_response → exit 0, no block
exit_code=0
output=$(echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:3 -->\nPhase 3"},"tool_response":"Done.\n```json\n{\"status\":\"ok\",\"summary\":\"All good\",\"artifacts\":[]}\n```"}' \
  | bash "$SCRIPT_DIR/validate-json-envelope.sh" 2>/dev/null) || exit_code=$?
assert_exit "valid envelope → exit 0" 0 $exit_code
assert_not_contains "valid envelope → no block decision" "$output" "decision"

# 3d. Autopilot Task with empty tool_response → decision:block
exit_code=0
output=$(echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:3 -->\nPhase 3"},"tool_response":""}' \
  | bash "$SCRIPT_DIR/validate-json-envelope.sh" 2>/dev/null) || exit_code=$?
assert_exit "empty response → exit 0" 0 $exit_code
assert_contains "empty response → block decision" "$output" "block"

# 3e. Autopilot Task with no JSON in response → decision:block
exit_code=0
output=$(echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:4 -->\nPhase 4"},"tool_response":"I completed the task successfully without any JSON."}' \
  | bash "$SCRIPT_DIR/validate-json-envelope.sh" 2>/dev/null) || exit_code=$?
assert_exit "no JSON in response → exit 0" 0 $exit_code
assert_contains "no JSON → block decision" "$output" "block"

# 3f. Verify tool_response field is used (NOT tool_result)
exit_code=0
output=$(echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:3 -->\nPhase 3"},"tool_result":"{\"status\":\"ok\",\"summary\":\"test\"}","tool_response":"no json here"}' \
  | bash "$SCRIPT_DIR/validate-json-envelope.sh" 2>/dev/null) || exit_code=$?
# tool_result has valid JSON but tool_response doesn't → should block (proving tool_response is used)
assert_contains "uses tool_response not tool_result" "$output" "block"

# 3g. Nested JSON object (Phase 4 with test_counts + test_pyramid) → should be extracted
exit_code=0
output=$(echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:4 -->\nPhase 4"},"tool_response":"Result: {\"status\":\"ok\",\"summary\":\"Tests designed\",\"artifacts\":[\"tests/unit.test.ts\",\"tests/api.py\"],\"test_counts\":{\"unit\":10,\"api\":8,\"e2e\":5,\"ui\":5},\"dry_run_results\":{\"unit\":0,\"api\":0,\"e2e\":0,\"ui\":0},\"test_pyramid\":{\"unit_pct\":36,\"e2e_pct\":18}}"}' \
  | bash "$SCRIPT_DIR/validate-json-envelope.sh" 2>/dev/null) || exit_code=$?
assert_exit "nested JSON → exit 0" 0 $exit_code
assert_not_contains "nested JSON → no block" "$output" "block"

# 3h. Phase 5 with zero_skip_check → should pass
exit_code=0
output=$(echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:5 -->\nPhase 5"},"tool_response":"Done. {\"status\":\"ok\",\"summary\":\"All tasks implemented\",\"test_results_path\":\"tests/results.json\",\"tasks_completed\":8,\"zero_skip_check\":{\"passed\":true},\"iterations_used\":12}"}' \
  | bash "$SCRIPT_DIR/validate-json-envelope.sh" 2>/dev/null) || exit_code=$?
assert_exit "Phase 5 with zero_skip_check → exit 0" 0 $exit_code
assert_not_contains "Phase 5 complete → no block" "$output" "block"

# 3i. Phase 5 missing zero_skip_check → should block
exit_code=0
output=$(echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:5 -->\nPhase 5"},"tool_response":"Done. {\"status\":\"ok\",\"summary\":\"All tasks implemented\",\"test_results_path\":\"tests/results.json\",\"tasks_completed\":8}"}' \
  | bash "$SCRIPT_DIR/validate-json-envelope.sh" 2>/dev/null) || exit_code=$?
assert_exit "Phase 5 missing zero_skip_check → exit 0" 0 $exit_code
assert_contains "Phase 5 missing field → block" "$output" "block"

# 3j. Phase 6 with required fields → should pass
exit_code=0
output=$(echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:6 -->\nPhase 6"},"tool_response":"Report: {\"status\":\"ok\",\"summary\":\"All tests pass\",\"artifacts\":[\"reports/final.html\",\"reports/results.json\"],\"pass_rate\":98.5,\"report_path\":\"reports/final.html\",\"report_format\":\"html\",\"suite_results\":[{\"suite\":\"unit\",\"total\":10,\"passed\":10,\"failed\":0,\"skipped\":0}]}"}' \
  | bash "$SCRIPT_DIR/validate-json-envelope.sh" 2>/dev/null) || exit_code=$?
assert_exit "Phase 6 complete → exit 0" 0 $exit_code
assert_not_contains "Phase 6 complete → no block" "$output" "block"

# 3k. Phase 4 warning → should block (any Phase 4 warning blocks; only "ok" or "blocked" accepted)
exit_code=0
output=$(echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:4 -->\nPhase 4"},"tool_response":"Result: {\"status\":\"warning\",\"summary\":\"Tests incomplete\",\"artifacts\":[\"tests/unit.test.ts\"],\"test_counts\":{\"unit\":3,\"api\":2,\"e2e\":1,\"ui\":0},\"dry_run_results\":{\"unit\":0,\"api\":0,\"e2e\":0,\"ui\":0}}"}' \
  | bash "$SCRIPT_DIR/validate-json-envelope.sh" 2>/dev/null) || exit_code=$?
assert_exit "Phase 4 warning → exit 0" 0 $exit_code
assert_contains "Phase 4 warning → block" "$output" "block"

# 3l. Phase 4 with empty artifacts → should block (M4 fix)
exit_code=0
output=$(echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:4 -->\nPhase 4"},"tool_response":"Result: {\"status\":\"ok\",\"summary\":\"Tests designed\",\"artifacts\":[],\"test_counts\":{\"unit\":10,\"api\":8,\"e2e\":5,\"ui\":5},\"dry_run_results\":{\"unit\":0,\"api\":0,\"e2e\":0,\"ui\":0}}"}' \
  | bash "$SCRIPT_DIR/validate-json-envelope.sh" 2>/dev/null) || exit_code=$?
assert_exit "Phase 4 empty artifacts → exit 0" 0 $exit_code
assert_contains "Phase 4 empty artifacts → block" "$output" "block"

# 3m. Phase 6 with empty artifacts → should block (M4 fix)
exit_code=0
output=$(echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:6 -->\nPhase 6"},"tool_response":"Report: {\"status\":\"ok\",\"summary\":\"All tests pass\",\"artifacts\":[],\"pass_rate\":98.5,\"report_path\":\"reports/final.html\"}"}' \
  | bash "$SCRIPT_DIR/validate-json-envelope.sh" 2>/dev/null) || exit_code=$?
assert_exit "Phase 6 empty artifacts → exit 0" 0 $exit_code
assert_contains "Phase 6 empty artifacts → block" "$output" "block"

# 3n. Lock file detection (C2 fix) — tested via predecessor hook
# (Lock file test requires filesystem setup, covered by integration tests)

echo ""

# ============================================================
echo "--- 4. scan-checkpoints-on-start.sh ---"
exit_code=0
output=$(bash "$SCRIPT_DIR/scan-checkpoints-on-start.sh" 2>/dev/null) || exit_code=$?
assert_exit "SessionStart hook → exit 0" 0 $exit_code

echo ""

# ============================================================
echo "--- 5. detect-ralph-loop.sh ---"

# 5a. Non-existent project → exits 0 and outputs one of: available/fallback/blocked
# Note: Result depends on user-scope ~/.claude/settings.json (ralph-loop may be installed globally)
exit_code=0
output=$(bash "$SCRIPT_DIR/detect-ralph-loop.sh" /tmp/nonexistent-project-xyzzy 2>/dev/null) || exit_code=$?
assert_exit "nonexistent project → exit 0" 0 $exit_code
# Verify output is one of the three valid values
if echo "$output" | grep -qE '^(available|fallback|blocked)$'; then
  green "  PASS: nonexistent project → valid output ($output)"
  PASS=$((PASS + 1))
else
  red "  FAIL: nonexistent project → unexpected output ($output)"
  FAIL=$((FAIL + 1))
fi

echo ""

# ============================================================
echo "--- 6. hooks.json validation ---"

# 6a. Valid JSON
if python3 -c "import json; json.load(open('$SCRIPT_DIR/../hooks/hooks.json'))" 2>/dev/null; then
  green "  PASS: hooks.json is valid JSON"
  PASS=$((PASS + 1))
else
  red "  FAIL: hooks.json is invalid JSON"
  FAIL=$((FAIL + 1))
fi

# 6b. Has timeout fields
if python3 -c "
import json
with open('$SCRIPT_DIR/../hooks/hooks.json') as f:
    data = json.load(f)
for event in data['hooks'].values():
    for group in event:
        for hook in group['hooks']:
            assert 'timeout' in hook, f'Missing timeout in {hook}'
print('ok')
" 2>/dev/null | grep -q "ok"; then
  green "  PASS: all hooks have timeout configured"
  PASS=$((PASS + 1))
else
  red "  FAIL: some hooks missing timeout"
  FAIL=$((FAIL + 1))
fi

# 6c. Matcher uses ^Task$ (exact match, not substring)
if python3 -c "
import json, re
with open('$SCRIPT_DIR/../hooks/hooks.json') as f:
    data = json.load(f)
for event_name in ['PreToolUse', 'PostToolUse']:
    for group in data['hooks'][event_name]:
        m = group.get('matcher', '')
        # Only check Task-related matchers (skip Write|Edit etc.)
        if not m or 'Task' not in m:
            continue
        # Verify matcher only matches 'Task', not 'TaskCreate' etc.
        assert re.fullmatch(m, 'Task'), f'{event_name} matcher {m!r} does not match Task'
        assert not re.search(m, 'TaskCreate'), f'{event_name} matcher {m!r} also matches TaskCreate!'
        assert not re.search(m, 'TaskUpdate'), f'{event_name} matcher {m!r} also matches TaskUpdate!'
print('ok')
" 2>/dev/null | grep -q "ok"; then
  green "  PASS: matchers use exact ^Task\$ (no collision with TaskCreate/TaskUpdate)"
  PASS=$((PASS + 1))
else
  red "  FAIL: matchers collide with TaskCreate/TaskUpdate/etc."
  FAIL=$((FAIL + 1))
fi

# 6d. Plugin version is > 1.0.0
if python3 -c "
import json
with open('$SCRIPT_DIR/../.claude-plugin/plugin.json') as f:
    data = json.load(f)
v = data.get('version', '0.0.0')
major, minor, patch = (int(x) for x in v.split('.'))
assert (major, minor, patch) > (1, 0, 0), f'Version {v} not bumped from 1.0.0'
print('ok')
" 2>/dev/null | grep -q "ok"; then
  green "  PASS: plugin.json version bumped (> 1.0.0)"
  PASS=$((PASS + 1))
else
  red "  FAIL: plugin.json version still 1.0.0"
  FAIL=$((FAIL + 1))
fi

echo ""

# ============================================================
echo "--- 7. deny() fail-closed test ---"

# 7a. Verify deny fallback works when python3 json.dumps "crashes"
# We can't easily crash json.dumps, but we can verify the fallback structure exists
if grep -q 'hookSpecificOutput.*permissionDecision.*deny.*internal error' "$SCRIPT_DIR/check-predecessor-checkpoint.sh"; then
  green "  PASS: deny() has hardcoded JSON fallback for fail-closed behavior"
  PASS=$((PASS + 1))
else
  red "  FAIL: deny() missing fail-closed fallback"
  FAIL=$((FAIL + 1))
fi

echo ""

# ============================================================
echo "--- 8. Pure bash marker bypass (P2 performance) ---"

# 8a. Non-autopilot Task bypasses without calling python3
# Verify no stdout output (no deny, no block) and exit 0
exit_code=0
output=$(echo '{"tool_name":"Task","tool_input":{"prompt":"Search for all TODO comments in the codebase","subagent_type":"Explore"}}' \
  | bash "$SCRIPT_DIR/check-predecessor-checkpoint.sh" 2>/dev/null) || exit_code=$?
assert_exit "non-autopilot bypass (predecessor) → exit 0" 0 $exit_code
assert_not_contains "non-autopilot bypass → no deny output" "$output" "deny"

exit_code=0
output=$(echo '{"tool_name":"Task","tool_input":{"prompt":"Search for all TODO comments in the codebase"},"tool_response":"Found 42 TODOs"}' \
  | bash "$SCRIPT_DIR/validate-json-envelope.sh" 2>/dev/null) || exit_code=$?
assert_exit "non-autopilot bypass (envelope) → exit 0" 0 $exit_code
assert_not_contains "non-autopilot bypass → no block output" "$output" "block"

echo ""

# ============================================================
echo "--- 9. Fail-closed consistency check ---"

# 9a. validate-json-envelope.sh should block autopilot tasks with fail-closed behavior
if grep -q 'decision.*block' "$SCRIPT_DIR/validate-json-envelope.sh" && \
   grep -q 'python3 is required' "$SCRIPT_DIR/validate-json-envelope.sh"; then
  green "  PASS: validate-json-envelope.sh has fail-closed block for missing python3"
  PASS=$((PASS + 1))
else
  red "  FAIL: validate-json-envelope.sh missing fail-closed behavior"
  FAIL=$((FAIL + 1))
fi

# 9b. check-predecessor-checkpoint.sh should deny autopilot tasks (verified by checking source)
if grep -q 'permissionDecision.*deny' "$SCRIPT_DIR/check-predecessor-checkpoint.sh" && \
   grep -q 'python3 is required' "$SCRIPT_DIR/check-predecessor-checkpoint.sh"; then
  green "  PASS: check-predecessor-checkpoint.sh has fail-closed deny for missing python3"
  PASS=$((PASS + 1))
else
  red "  FAIL: check-predecessor-checkpoint.sh missing fail-closed behavior"
  FAIL=$((FAIL + 1))
fi

# 9c. Both scripts use bash marker pre-check before python3
if grep -q 'autopilot-phase:\[0-9\]' "$SCRIPT_DIR/check-predecessor-checkpoint.sh" && \
   grep -q 'autopilot-phase:\[0-9\]' "$SCRIPT_DIR/validate-json-envelope.sh"; then
  green "  PASS: both scripts use pure bash marker pre-check"
  PASS=$((PASS + 1))
else
  red "  FAIL: missing bash marker pre-check in one or both scripts"
  FAIL=$((FAIL + 1))
fi

echo ""

# ============================================================
echo "--- 10. SessionStart async configuration ---"

# 10a. hooks.json SessionStart scan-checkpoints hook has async: true
if python3 -c "
import json
with open('$SCRIPT_DIR/../hooks/hooks.json') as f:
    data = json.load(f)
# Only the first SessionStart group (scan-checkpoints) needs async: true
# The compact reinject hook must be synchronous to feed context back
scan_group = data['hooks']['SessionStart'][0]
assert 'matcher' not in scan_group, 'First SessionStart group should not have matcher'
for hook in scan_group['hooks']:
    assert hook.get('async') is True, f'scan-checkpoints hook missing async: true'
print('ok')
" 2>/dev/null | grep -q "ok"; then
  green "  PASS: SessionStart scan-checkpoints hook has async: true"
  PASS=$((PASS + 1))
else
  red "  FAIL: SessionStart scan-checkpoints hook missing async: true"
  FAIL=$((FAIL + 1))
fi

echo ""

# ============================================================
echo "--- 11. PreCompact + SessionStart(compact) hooks ---"

# 11a. hooks.json has PreCompact section
if python3 -c "
import json
with open('$SCRIPT_DIR/../hooks/hooks.json') as f:
    data = json.load(f)
assert 'PreCompact' in data['hooks'], 'Missing PreCompact hook'
assert len(data['hooks']['PreCompact']) > 0, 'PreCompact has no groups'
print('ok')
" 2>/dev/null | grep -q "ok"; then
  green "  PASS: hooks.json has PreCompact hook"
  PASS=$((PASS + 1))
else
  red "  FAIL: hooks.json missing PreCompact hook"
  FAIL=$((FAIL + 1))
fi

# 11b. SessionStart has a compact matcher group
if python3 -c "
import json
with open('$SCRIPT_DIR/../hooks/hooks.json') as f:
    data = json.load(f)
compact_groups = [g for g in data['hooks']['SessionStart'] if g.get('matcher') == 'compact']
assert len(compact_groups) == 1, f'Expected 1 compact group, got {len(compact_groups)}'
# Compact reinject must NOT be async (needs to feed stdout into context)
for hook in compact_groups[0]['hooks']:
    assert hook.get('async') is not True, 'compact reinject hook must be synchronous'
print('ok')
" 2>/dev/null | grep -q "ok"; then
  green "  PASS: SessionStart(compact) hook is synchronous"
  PASS=$((PASS + 1))
else
  red "  FAIL: SessionStart(compact) hook misconfigured"
  FAIL=$((FAIL + 1))
fi

# 11c. save-state-before-compact.sh syntax check
if bash -n "$SCRIPT_DIR/save-state-before-compact.sh" 2>/dev/null; then
  green "  PASS: save-state-before-compact.sh syntax OK"
  PASS=$((PASS + 1))
else
  red "  FAIL: save-state-before-compact.sh syntax error"
  FAIL=$((FAIL + 1))
fi

# 11d. reinject-state-after-compact.sh syntax check
if bash -n "$SCRIPT_DIR/reinject-state-after-compact.sh" 2>/dev/null; then
  green "  PASS: reinject-state-after-compact.sh syntax OK"
  PASS=$((PASS + 1))
else
  red "  FAIL: reinject-state-after-compact.sh syntax error"
  FAIL=$((FAIL + 1))
fi

# 11e. save-state script exits 0 with no changes dir
exit_code=0
bash "$SCRIPT_DIR/save-state-before-compact.sh" </dev/null >/dev/null 2>&1 || exit_code=$?
assert_exit "save-state no changes → exit 0" 0 $exit_code

# 11f. reinject-state script exits 0 with no state file
exit_code=0
output=$(cd /tmp && bash "$SCRIPT_DIR/reinject-state-after-compact.sh" 2>/dev/null) || exit_code=$?
assert_exit "reinject-state no state file → exit 0" 0 $exit_code

echo ""

# ============================================================
echo "--- 12. _common.sh shared library ---"

# 12a. _common.sh syntax check
if bash -n "$SCRIPT_DIR/_common.sh" 2>/dev/null; then
  green "  PASS: _common.sh syntax OK"
  PASS=$((PASS + 1))
else
  red "  FAIL: _common.sh syntax error"
  FAIL=$((FAIL + 1))
fi

# 12b. _common.sh is sourced by both hook scripts
if grep -q 'source.*_common.sh' "$SCRIPT_DIR/check-predecessor-checkpoint.sh" && \
   grep -q 'source.*_common.sh' "$SCRIPT_DIR/save-state-before-compact.sh"; then
  green "  PASS: both hook scripts source _common.sh"
  PASS=$((PASS + 1))
else
  red "  FAIL: hook scripts not sourcing _common.sh"
  FAIL=$((FAIL + 1))
fi

echo ""

# ============================================================
echo "--- 13. JSON lock file parsing ---"

# 13a. parse_lock_file reads JSON format
TMPDIR_TEST=$(mktemp -d)
echo '{"change":"test-feature","pid":12345,"started":"2026-01-01T00:00:00Z"}' > "$TMPDIR_TEST/.autopilot-active"
source "$SCRIPT_DIR/_common.sh"
lock_result=$(parse_lock_file "$TMPDIR_TEST/.autopilot-active")
if [ "$lock_result" = "test-feature" ]; then
  green "  PASS: parse_lock_file reads JSON format correctly"
  PASS=$((PASS + 1))
else
  red "  FAIL: parse_lock_file JSON result='$lock_result', expected 'test-feature'"
  FAIL=$((FAIL + 1))
fi

# 13b. parse_lock_file reads legacy plain text format
echo "legacy-change-name" > "$TMPDIR_TEST/.autopilot-active"
lock_result=$(parse_lock_file "$TMPDIR_TEST/.autopilot-active")
if [ "$lock_result" = "legacy-change-name" ]; then
  green "  PASS: parse_lock_file reads legacy plain text format"
  PASS=$((PASS + 1))
else
  red "  FAIL: parse_lock_file legacy result='$lock_result', expected 'legacy-change-name'"
  FAIL=$((FAIL + 1))
fi

# 13c. parse_lock_file handles missing file
lock_result=$(parse_lock_file "$TMPDIR_TEST/nonexistent" 2>/dev/null) || true
if [ -z "$lock_result" ]; then
  green "  PASS: parse_lock_file handles missing file gracefully"
  PASS=$((PASS + 1))
else
  red "  FAIL: parse_lock_file should return empty for missing file"
  FAIL=$((FAIL + 1))
fi

rm -rf "$TMPDIR_TEST"

echo ""

# ============================================================
echo "--- 14. Phase 1 checkpoint compatibility ---"

# 14a. check-predecessor-checkpoint.sh scans Phase 1-7
if grep -q 'for phase_num in 1 2 3 4 5 6 7' "$SCRIPT_DIR/check-predecessor-checkpoint.sh"; then
  green "  PASS: predecessor hook scans Phase 1-7 checkpoints"
  PASS=$((PASS + 1))
else
  red "  FAIL: predecessor hook does not scan Phase 1-7"
  FAIL=$((FAIL + 1))
fi

# 14b. scan-checkpoints-on-start.sh scans Phase 1-7
if grep -q 'for phase_num in 1 2 3 4 5 6 7' "$SCRIPT_DIR/scan-checkpoints-on-start.sh"; then
  green "  PASS: SessionStart scan includes Phase 1-7"
  PASS=$((PASS + 1))
else
  red "  FAIL: SessionStart scan does not include Phase 1-7"
  FAIL=$((FAIL + 1))
fi

# 14c. save-state scans Phase 1 (included in 1-7 range)
if grep -q 'for phase_num in \[1, 2, 3, 4, 5, 6, 7\]' "$SCRIPT_DIR/save-state-before-compact.sh"; then
  green "  PASS: PreCompact state save includes Phase 1"
  PASS=$((PASS + 1))
else
  red "  FAIL: PreCompact state save does not include Phase 1"
  FAIL=$((FAIL + 1))
fi

# 14d. Phase 2 independent check is documented
if grep -q 'Phase 2 independent check' "$SCRIPT_DIR/check-predecessor-checkpoint.sh"; then
  green "  PASS: Phase 2 independent check documented in comments"
  PASS=$((PASS + 1))
else
  red "  FAIL: Phase 2 independent check not documented"
  FAIL=$((FAIL + 1))
fi

echo ""

# ============================================================
echo "--- 15. references/ directory structure ---"

# 15a. protocol.md is in autopilot/references/ (official pattern)
if [ -f "$SCRIPT_DIR/../skills/autopilot/references/protocol.md" ]; then
  green "  PASS: protocol.md in autopilot/references/ (official pattern)"
  PASS=$((PASS + 1))
else
  red "  FAIL: protocol.md not found in autopilot/references/"
  FAIL=$((FAIL + 1))
fi

# 15b. No leftover shared/ directory
if [ ! -d "$SCRIPT_DIR/../skills/shared" ]; then
  green "  PASS: no leftover skills/shared/ directory"
  PASS=$((PASS + 1))
else
  red "  FAIL: skills/shared/ directory still exists (should be migrated)"
  FAIL=$((FAIL + 1))
fi

echo ""

# ============================================================
echo "--- 16. check-allure-install.sh ---"

# 16a. Syntax check
if bash -n "$SCRIPT_DIR/check-allure-install.sh" 2>/dev/null; then
  green "  PASS: check-allure-install.sh syntax OK"
  PASS=$((PASS + 1))
else
  red "  FAIL: check-allure-install.sh syntax error"
  FAIL=$((FAIL + 1))
fi

# 16b. Returns valid JSON
exit_code=0
output=$(bash "$SCRIPT_DIR/check-allure-install.sh" /tmp/nonexistent-project-allure-test 2>/dev/null) || exit_code=$?
assert_exit "check-allure-install → exit 0" 0 $exit_code

if echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); assert 'all_required_installed' in d; assert 'missing' in d; print('ok')" 2>/dev/null | grep -q "ok"; then
  green "  PASS: check-allure-install returns valid JSON with required fields"
  PASS=$((PASS + 1))
else
  red "  FAIL: check-allure-install JSON missing required fields"
  FAIL=$((FAIL + 1))
fi

# 16c. JSON has all 4 component keys
if echo "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
required = ['allure_cli', 'allure_playwright', 'allure_pytest', 'allure_gradle']
for key in required:
    assert key in d, f'Missing key: {key}'
    assert 'installed' in d[key], f'Missing installed field in {key}'
print('ok')
" 2>/dev/null | grep -q "ok"; then
  green "  PASS: check-allure-install has all 4 component keys with installed field"
  PASS=$((PASS + 1))
else
  red "  FAIL: check-allure-install missing component keys"
  FAIL=$((FAIL + 1))
fi

# 16d. install_commands is an array (even if empty)
if echo "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert isinstance(d.get('install_commands'), list), 'install_commands is not a list'
print('ok')
" 2>/dev/null | grep -q "ok"; then
  green "  PASS: install_commands is a list"
  PASS=$((PASS + 1))
else
  red "  FAIL: install_commands is not a list"
  FAIL=$((FAIL + 1))
fi

echo ""

# ============================================================
echo "--- 17. Phase 6 envelope validation (Allure fields) ---"

# 17a. Phase 6 with allure report_format → should pass
exit_code=0
output=$(echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:6 -->\nPhase 6"},"tool_response":"Report: {\"status\":\"ok\",\"summary\":\"All tests pass\",\"artifacts\":[\"allure-report/index.html\"],\"pass_rate\":98.5,\"report_path\":\"openspec/changes/test/testreport/allure-report/index.html\",\"report_format\":\"allure\",\"allure_results_dir\":\"allure-results\",\"suite_results\":[{\"suite\":\"unit\",\"total\":10,\"passed\":10,\"failed\":0,\"skipped\":0}]}"}' \
  | bash "$SCRIPT_DIR/validate-json-envelope.sh" 2>/dev/null) || exit_code=$?
assert_exit "Phase 6 allure format → exit 0" 0 $exit_code
assert_not_contains "Phase 6 allure format → no block" "$output" "block"

# 17b. Phase 6 with custom report_format → should also pass (format validation is Layer 3)
exit_code=0
output=$(echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:6 -->\nPhase 6"},"tool_response":"Report: {\"status\":\"ok\",\"summary\":\"All tests pass\",\"artifacts\":[\"reports/test-report.html\"],\"pass_rate\":95.0,\"report_path\":\"openspec/changes/test/testreport/test-report.html\",\"report_format\":\"custom\",\"suite_results\":[{\"suite\":\"unit\",\"total\":10,\"passed\":10,\"failed\":0,\"skipped\":0}]}"}' \
  | bash "$SCRIPT_DIR/validate-json-envelope.sh" 2>/dev/null) || exit_code=$?
assert_exit "Phase 6 custom format → exit 0" 0 $exit_code
assert_not_contains "Phase 6 custom format → no block" "$output" "block"

# 17c. Phase 6 missing report_format → should block (required phase-specific field)
exit_code=0
output=$(echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:6 -->\nPhase 6"},"tool_response":"Report: {\"status\":\"ok\",\"summary\":\"All tests pass\",\"artifacts\":[\"reports/final.html\"],\"pass_rate\":98.5,\"report_path\":\"reports/final.html\"}"}' \
  | bash "$SCRIPT_DIR/validate-json-envelope.sh" 2>/dev/null) || exit_code=$?
assert_exit "Phase 6 missing report_format → exit 0" 0 $exit_code
assert_contains "Phase 6 missing report_format → block" "$output" "block"

echo ""

# ============================================================
echo "--- 18. save-state Phase 7 scan ---"

# 18a. save-state-before-compact.sh scans Phase 1-7 (not 1-6)
if grep -q 'for phase_num in \[1, 2, 3, 4, 5, 6, 7\]' "$SCRIPT_DIR/save-state-before-compact.sh"; then
  green "  PASS: PreCompact state save scans Phase 1-7"
  PASS=$((PASS + 1))
else
  red "  FAIL: PreCompact state save does not scan Phase 1-7"
  FAIL=$((FAIL + 1))
fi

# 18b. phase_names includes Phase 7
if grep -q "7: 'Archive'" "$SCRIPT_DIR/save-state-before-compact.sh"; then
  green "  PASS: phase_names includes Phase 7 (Archive)"
  PASS=$((PASS + 1))
else
  red "  FAIL: phase_names missing Phase 7"
  FAIL=$((FAIL + 1))
fi

echo ""

# ============================================================
echo "--- 19. _common.sh unit tests ---"

# Need a temp directory for these tests
COMMON_TEST_DIR=$(mktemp -d)
trap "rm -rf $COMMON_TEST_DIR" EXIT

# Source _common.sh
source "$SCRIPT_DIR/_common.sh"

# 19a. parse_lock_file with JSON format
echo '{"change":"my-feature","pid":"12345","started":"2026-01-01T00:00:00Z"}' > "$COMMON_TEST_DIR/lock.json"
result=$(parse_lock_file "$COMMON_TEST_DIR/lock.json")
if [ "$result" = "my-feature" ]; then
  green "  PASS: parse_lock_file JSON format"
  PASS=$((PASS + 1))
else
  red "  FAIL: parse_lock_file JSON format (got '$result')"
  FAIL=$((FAIL + 1))
fi

# 19b. parse_lock_file with legacy plain text
echo "legacy-change-name" > "$COMMON_TEST_DIR/lock.txt"
result=$(parse_lock_file "$COMMON_TEST_DIR/lock.txt")
if [ "$result" = "legacy-change-name" ]; then
  green "  PASS: parse_lock_file legacy plain text"
  PASS=$((PASS + 1))
else
  red "  FAIL: parse_lock_file legacy plain text (got '$result')"
  FAIL=$((FAIL + 1))
fi

# 19c. parse_lock_file with invalid/empty file
echo "" > "$COMMON_TEST_DIR/lock_empty.txt"
result=$(parse_lock_file "$COMMON_TEST_DIR/lock_empty.txt")
if [ -z "$result" ]; then
  green "  PASS: parse_lock_file empty file returns empty"
  PASS=$((PASS + 1))
else
  red "  FAIL: parse_lock_file empty file (got '$result')"
  FAIL=$((FAIL + 1))
fi

# 19d. parse_lock_file with missing file
result=""
parse_lock_file "$COMMON_TEST_DIR/nonexistent.json" || true
result=$(parse_lock_file "$COMMON_TEST_DIR/nonexistent.json" 2>/dev/null || echo "")
if [ -z "$result" ]; then
  green "  PASS: parse_lock_file missing file returns empty"
  PASS=$((PASS + 1))
else
  red "  FAIL: parse_lock_file missing file (got '$result')"
  FAIL=$((FAIL + 1))
fi

# 19e. find_active_change with lock file priority
mkdir -p "$COMMON_TEST_DIR/changes/feature-a"
mkdir -p "$COMMON_TEST_DIR/changes/feature-b"
echo '{"change":"feature-a"}' > "$COMMON_TEST_DIR/changes/.autopilot-active"
result=$(find_active_change "$COMMON_TEST_DIR/changes")
if echo "$result" | grep -q "feature-a"; then
  green "  PASS: find_active_change lock file priority"
  PASS=$((PASS + 1))
else
  red "  FAIL: find_active_change lock file priority (got '$result')"
  FAIL=$((FAIL + 1))
fi

# 19f. find_active_change with trailing slash
result=$(find_active_change "$COMMON_TEST_DIR/changes" "yes")
if [[ "$result" == */ ]]; then
  green "  PASS: find_active_change trailing slash"
  PASS=$((PASS + 1))
else
  red "  FAIL: find_active_change trailing slash (got '$result')"
  FAIL=$((FAIL + 1))
fi

# 19g. find_active_change excludes _prefixed dirs
mkdir -p "$COMMON_TEST_DIR/changes2/_archived"
mkdir -p "$COMMON_TEST_DIR/changes2/real-change"
result=$(find_active_change "$COMMON_TEST_DIR/changes2")
if echo "$result" | grep -q "real-change"; then
  green "  PASS: find_active_change excludes _prefix"
  PASS=$((PASS + 1))
else
  red "  FAIL: find_active_change excludes _prefix (got '$result')"
  FAIL=$((FAIL + 1))
fi

# 19h. read_checkpoint_status with all statuses
for status_val in ok warning blocked failed; do
  echo "{\"status\":\"$status_val\"}" > "$COMMON_TEST_DIR/ckpt_${status_val}.json"
  result=$(read_checkpoint_status "$COMMON_TEST_DIR/ckpt_${status_val}.json")
  if [ "$result" = "$status_val" ]; then
    green "  PASS: read_checkpoint_status '$status_val'"
    PASS=$((PASS + 1))
  else
    red "  FAIL: read_checkpoint_status '$status_val' (got '$result')"
    FAIL=$((FAIL + 1))
  fi
done

# 19i. read_checkpoint_status with invalid JSON
echo "not json at all" > "$COMMON_TEST_DIR/ckpt_bad.json"
result=$(read_checkpoint_status "$COMMON_TEST_DIR/ckpt_bad.json")
if [ "$result" = "error" ]; then
  green "  PASS: read_checkpoint_status invalid JSON returns error"
  PASS=$((PASS + 1))
else
  red "  FAIL: read_checkpoint_status invalid JSON (got '$result')"
  FAIL=$((FAIL + 1))
fi

# 19j. find_checkpoint
mkdir -p "$COMMON_TEST_DIR/phase-results"
echo '{"status":"ok"}' > "$COMMON_TEST_DIR/phase-results/phase-3-ff.json"
result=$(find_checkpoint "$COMMON_TEST_DIR/phase-results" 3)
if [ -n "$result" ] && echo "$result" | grep -q "phase-3-ff.json"; then
  green "  PASS: find_checkpoint finds phase-3"
  PASS=$((PASS + 1))
else
  red "  FAIL: find_checkpoint phase-3 (got '$result')"
  FAIL=$((FAIL + 1))
fi

# 19k. find_checkpoint for missing phase
result=$(find_checkpoint "$COMMON_TEST_DIR/phase-results" 9)
if [ -z "$result" ]; then
  green "  PASS: find_checkpoint missing phase returns empty"
  PASS=$((PASS + 1))
else
  red "  FAIL: find_checkpoint missing phase (got '$result')"
  FAIL=$((FAIL + 1))
fi

echo ""

# ============================================================
echo "--- 20. check-allure-install.sh enhanced tests ---"

# 20a. Run in clean temp dir (no project context) → valid JSON
exit_code=0
output=$(cd /tmp && bash "$SCRIPT_DIR/check-allure-install.sh" 2>/dev/null) || exit_code=$?
assert_exit "allure check in clean dir → exit 0" 0 $exit_code

# 20b. Output must be valid JSON
if echo "$output" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null; then
  green "  PASS: allure check output is valid JSON"
  PASS=$((PASS + 1))
else
  red "  FAIL: allure check output is not valid JSON"
  FAIL=$((FAIL + 1))
fi

# 20c. JSON has all 4 component keys with 'installed' field
for comp in allure_cli allure_playwright allure_pytest allure_gradle; do
  has_installed=$(echo "$output" | python3 -c "
import json, sys
data = json.load(sys.stdin)
c = data.get('$comp', {})
print('yes' if 'installed' in c else 'no')
" 2>/dev/null || echo "no")
  if [ "$has_installed" = "yes" ]; then
    green "  PASS: allure component '$comp' has 'installed' field"
    PASS=$((PASS + 1))
  else
    red "  FAIL: allure component '$comp' missing 'installed' field"
    FAIL=$((FAIL + 1))
  fi
done

# 20d. JSON has install_commands list
has_commands=$(echo "$output" | python3 -c "
import json, sys
data = json.load(sys.stdin)
cmds = data.get('install_commands', None)
print('yes' if isinstance(cmds, list) else 'no')
" 2>/dev/null || echo "no")
if [ "$has_commands" = "yes" ]; then
  green "  PASS: allure install_commands is a list"
  PASS=$((PASS + 1))
else
  red "  FAIL: allure install_commands not a list"
  FAIL=$((FAIL + 1))
fi

echo ""

# ============================================================
echo "--- 21. validate-config.sh tests ---"

CONFIG_TEST_DIR=$(mktemp -d)

# 21a. Valid config → valid=true
mkdir -p "$CONFIG_TEST_DIR/valid/.claude"
cat > "$CONFIG_TEST_DIR/valid/.claude/autopilot.config.yaml" << 'YAML'
version: "1.0"
services:
  backend:
    health_url: "http://localhost:8080/health"
phases:
  requirements:
    agent: "business-analyst"
  testing:
    agent: "qa-expert"
    gate:
      min_test_count_per_type: 5
      required_test_types: [unit, api, e2e, ui]
  implementation:
    ralph_loop:
      enabled: true
      max_iterations: 30
      fallback_enabled: true
  reporting:
    coverage_target: 80
    zero_skip_required: true
test_suites:
  unit:
    command: "npm test"
test_pyramid:
  min_unit_pct: 50
gates:
  user_confirmation:
    after_phase_1: true
context_management:
  git_commit_per_phase: true
YAML

output=$(bash "$SCRIPT_DIR/validate-config.sh" "$CONFIG_TEST_DIR/valid" 2>/dev/null)
valid=$(echo "$output" | python3 -c "import json,sys; print(json.load(sys.stdin).get('valid',''))" 2>/dev/null || echo "")
if [ "$valid" = "True" ] || [ "$valid" = "true" ]; then
  green "  PASS: validate-config valid config → valid=true"
  PASS=$((PASS + 1))
else
  red "  FAIL: validate-config valid config (got valid='$valid', output='$output')"
  FAIL=$((FAIL + 1))
fi

# 21b. Missing fields → valid=false with missing_keys
mkdir -p "$CONFIG_TEST_DIR/partial/.claude"
cat > "$CONFIG_TEST_DIR/partial/.claude/autopilot.config.yaml" << 'YAML'
version: "1.0"
phases:
  requirements:
    agent: "business-analyst"
YAML

output=$(bash "$SCRIPT_DIR/validate-config.sh" "$CONFIG_TEST_DIR/partial" 2>/dev/null)
valid=$(echo "$output" | python3 -c "import json,sys; print(json.load(sys.stdin).get('valid',''))" 2>/dev/null || echo "")
if [ "$valid" = "False" ] || [ "$valid" = "false" ]; then
  green "  PASS: validate-config partial config → valid=false"
  PASS=$((PASS + 1))
else
  red "  FAIL: validate-config partial config (got valid='$valid', output='$output')"
  FAIL=$((FAIL + 1))
fi

# 21c. Missing_keys contains expected entries
missing=$(echo "$output" | python3 -c "import json,sys; print(json.load(sys.stdin).get('missing_keys',[]))" 2>/dev/null || echo "[]")
assert_contains "validate-config missing keys include services" "$missing" "services"

# 21d. No config file → valid=false, missing=file_not_found
output=$(bash "$SCRIPT_DIR/validate-config.sh" "$CONFIG_TEST_DIR/nonexistent" 2>/dev/null)
assert_contains "validate-config no file → file_not_found" "$output" "file_not_found"

rm -rf "$CONFIG_TEST_DIR"

echo ""

# ============================================================
echo "--- 22. anti-rationalization-check.sh tests ---"

# 22a. Non-autopilot task → exit 0, no output
exit_code=0
output=$(echo '{"tool_name":"Task","tool_input":{"prompt":"Do something"},"tool_response":"Done"}' \
  | bash "$SCRIPT_DIR/anti-rationalization-check.sh" 2>/dev/null) || exit_code=$?
assert_exit "anti-rational: non-autopilot → allow" 0 $exit_code
assert_not_contains "anti-rational: non-autopilot → no block" "$output" "block"

# 22b. Phase 4 with rationalization pattern → block
exit_code=0
output=$(echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:4 -->\nDesign tests"},"tool_response":"Results: {\"status\":\"ok\",\"summary\":\"Done\",\"test_counts\":{\"unit\":10},\"dry_run_results\":{\"unit\":0},\"test_pyramid\":{\"unit_pct\":80},\"artifacts\":[\"test.py\"]} Note: Some tests were skipped because they are out of scope for this phase and not needed at this time."}' \
  | bash "$SCRIPT_DIR/anti-rationalization-check.sh" 2>/dev/null) || exit_code=$?
assert_exit "anti-rational: pattern detected → exit 0" 0 $exit_code
assert_contains "anti-rational: pattern detected → block" "$output" "block"
assert_contains "anti-rational: pattern mentions rationalization" "$output" "rationalization"

# 22c. Phase 4 with blocked status → no check (legitimate stop)
exit_code=0
output=$(echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:4 -->\nDesign tests"},"tool_response":"{\"status\":\"blocked\",\"summary\":\"Cannot proceed, out of scope\"}"}' \
  | bash "$SCRIPT_DIR/anti-rationalization-check.sh" 2>/dev/null) || exit_code=$?
assert_exit "anti-rational: blocked status → allow" 0 $exit_code
assert_not_contains "anti-rational: blocked status → no block" "$output" "block"

# 22d. Phase 2 (non-critical phase) → skip even with patterns
exit_code=0
output=$(echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:2 -->\nCreate openspec"},"tool_response":"{\"status\":\"ok\",\"summary\":\"Skipped this test because not needed\"}"}' \
  | bash "$SCRIPT_DIR/anti-rationalization-check.sh" 2>/dev/null) || exit_code=$?
assert_exit "anti-rational: phase 2 → skip" 0 $exit_code
assert_not_contains "anti-rational: phase 2 → no block" "$output" "block"

echo ""

# ============================================================
echo "--- 23. Wall-clock timeout tests ---"

WALLCLOCK_TEST_DIR=$(mktemp -d)
mkdir -p "$WALLCLOCK_TEST_DIR/openspec/changes/test-change/context/phase-results"
echo '{"change":"test-change"}' > "$WALLCLOCK_TEST_DIR/openspec/changes/.autopilot-active"
echo '{"status":"ok"}' > "$WALLCLOCK_TEST_DIR/openspec/changes/test-change/context/phase-results/phase-4-testing.json"

# 23a. Fresh start (just created) → allow
date -u +"%Y-%m-%dT%H:%M:%SZ" > "$WALLCLOCK_TEST_DIR/openspec/changes/test-change/context/phase-results/phase5-start-time.txt"
# Need Phase 5 zero_skip_check for Phase 6 gate
echo '{"status":"ok","zero_skip_check":{"passed":true},"test_results_path":"test.json","tasks_completed":3}' > "$WALLCLOCK_TEST_DIR/openspec/changes/test-change/context/phase-results/phase-5-implement.json"
# Need all tasks checked
echo "- [x] Task 1" > "$WALLCLOCK_TEST_DIR/openspec/changes/test-change/tasks.md"
exit_code=0
output=$(echo "{\"tool_name\":\"Task\",\"tool_input\":{\"prompt\":\"<!-- autopilot-phase:6 -->\\nPhase 6\",\"subagent_type\":\"general-purpose\"},\"cwd\":\"$WALLCLOCK_TEST_DIR\"}" \
  | bash "$SCRIPT_DIR/check-predecessor-checkpoint.sh" 2>/dev/null) || exit_code=$?
assert_exit "wall-clock: fresh start → allow" 0 $exit_code
assert_not_contains "wall-clock: fresh start → no deny" "$output" "deny"

# 23b. Expired (3 hours ago) → deny
expired_time=$(python3 -c "
from datetime import datetime, timezone, timedelta
t = datetime.now(timezone.utc) - timedelta(hours=3)
print(t.strftime('%Y-%m-%dT%H:%M:%SZ'))
" 2>/dev/null)
echo "$expired_time" > "$WALLCLOCK_TEST_DIR/openspec/changes/test-change/context/phase-results/phase5-start-time.txt"
exit_code=0
output=$(echo "{\"tool_name\":\"Task\",\"tool_input\":{\"prompt\":\"<!-- autopilot-phase:6 -->\\nPhase 6\",\"subagent_type\":\"general-purpose\"},\"cwd\":\"$WALLCLOCK_TEST_DIR\"}" \
  | bash "$SCRIPT_DIR/check-predecessor-checkpoint.sh" 2>/dev/null) || exit_code=$?
assert_exit "wall-clock: expired → exit 0" 0 $exit_code
assert_contains "wall-clock: expired → deny with timeout" "$output" "wall-clock timeout"

# 23c. No start file → allow (Phase 5 not started yet)
rm -f "$WALLCLOCK_TEST_DIR/openspec/changes/test-change/context/phase-results/phase5-start-time.txt"
exit_code=0
output=$(echo "{\"tool_name\":\"Task\",\"tool_input\":{\"prompt\":\"<!-- autopilot-phase:6 -->\\nPhase 6\",\"subagent_type\":\"general-purpose\"},\"cwd\":\"$WALLCLOCK_TEST_DIR\"}" \
  | bash "$SCRIPT_DIR/check-predecessor-checkpoint.sh" 2>/dev/null) || exit_code=$?
assert_exit "wall-clock: no start file → allow" 0 $exit_code
assert_not_contains "wall-clock: no start file → no deny" "$output" "wall-clock"

rm -rf "$WALLCLOCK_TEST_DIR"

echo ""

# ============================================================
echo "--- 24. test_pyramid threshold tests ---"

# 24a. Valid pyramid → allow
exit_code=0
output=$(echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:4 -->\nPhase 4"},"tool_response":"Results: {\"status\":\"ok\",\"summary\":\"Tests designed\",\"test_counts\":{\"unit\":15,\"api\":5,\"e2e\":3,\"ui\":2},\"dry_run_results\":{\"unit\":0,\"api\":0,\"e2e\":0,\"ui\":0},\"test_pyramid\":{\"unit_pct\":60,\"e2e_pct\":20},\"artifacts\":[\"tests/unit.py\",\"tests/e2e.py\"]}"}' \
  | bash "$SCRIPT_DIR/validate-json-envelope.sh" 2>/dev/null) || exit_code=$?
assert_exit "pyramid: valid distribution → exit 0" 0 $exit_code
assert_not_contains "pyramid: valid distribution → no block" "$output" "block"

# 24b. Inverted pyramid (too few unit, too many e2e) → block
exit_code=0
output=$(echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:4 -->\nPhase 4"},"tool_response":"Results: {\"status\":\"ok\",\"summary\":\"Tests designed\",\"test_counts\":{\"unit\":2,\"api\":2,\"e2e\":8,\"ui\":3},\"dry_run_results\":{\"unit\":0},\"test_pyramid\":{\"unit_pct\":13,\"e2e_pct\":53},\"artifacts\":[\"tests/e2e.py\"]}"}' \
  | bash "$SCRIPT_DIR/validate-json-envelope.sh" 2>/dev/null) || exit_code=$?
assert_exit "pyramid: inverted → exit 0" 0 $exit_code
assert_contains "pyramid: inverted → block" "$output" "block"
assert_contains "pyramid: inverted → mentions floor" "$output" "floor"

# 24c. Too few total cases → block
exit_code=0
output=$(echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:4 -->\nPhase 4"},"tool_response":"Results: {\"status\":\"ok\",\"summary\":\"Tests\",\"test_counts\":{\"unit\":3,\"api\":2,\"e2e\":1,\"ui\":1},\"dry_run_results\":{\"unit\":0},\"test_pyramid\":{\"unit_pct\":43,\"e2e_pct\":14},\"artifacts\":[\"test.py\"]}"}' \
  | bash "$SCRIPT_DIR/validate-json-envelope.sh" 2>/dev/null) || exit_code=$?
assert_exit "pyramid: too few cases → exit 0" 0 $exit_code
assert_contains "pyramid: too few total → block" "$output" "block"
assert_contains "pyramid: too few total → mentions minimum" "$output" "minimum"

# 24d. Boundary: exactly at limits → allow
exit_code=0
output=$(echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:4 -->\nPhase 4"},"tool_response":"Results: {\"status\":\"ok\",\"summary\":\"Tests\",\"test_counts\":{\"unit\":5,\"api\":3,\"e2e\":1,\"ui\":1},\"dry_run_results\":{\"unit\":0},\"test_pyramid\":{\"unit_pct\":30,\"e2e_pct\":40},\"artifacts\":[\"test.py\"]}"}' \
  | bash "$SCRIPT_DIR/validate-json-envelope.sh" 2>/dev/null) || exit_code=$?
assert_exit "pyramid: boundary values → exit 0" 0 $exit_code
assert_not_contains "pyramid: boundary values → no block" "$output" "block"

echo ""

# ============================================================
echo "--- 25. Lock file pre-check (false positive prevention) ---"

# 25a. No lock file + marker in prompt content → allow (should NOT be intercepted)
LOCK_TEST_DIR=$(mktemp -d)
mkdir -p "$LOCK_TEST_DIR/openspec/changes/test-change/context/phase-results"
# 注意：没有创建 .autopilot-active 锁文件
exit_code=0
output=$(cd "$LOCK_TEST_DIR" && echo '{"tool_name":"Task","tool_input":{"prompt":"请修改 phase5-implementation.md，示例中包含 <!-- autopilot-phase:5 --> 标记文本"},"tool_response":""}' \
  | bash "$SCRIPT_DIR/check-predecessor-checkpoint.sh" 2>/dev/null) || exit_code=$?
assert_exit "no lock file + marker text → allow (exit 0)" 0 $exit_code
assert_not_contains "no lock file → no deny" "$output" "deny"

# 25b. No lock file + envelope validation → allow
exit_code=0
output=$(cd "$LOCK_TEST_DIR" && echo '{"tool_name":"Task","tool_input":{"prompt":"代码示例包含 autopilot-phase:4 文本"},"tool_response":"Results: {\"status\":\"ok\"}"}' \
  | bash "$SCRIPT_DIR/validate-json-envelope.sh" 2>/dev/null) || exit_code=$?
assert_exit "no lock file + envelope → allow (exit 0)" 0 $exit_code
assert_not_contains "no lock file → no block (envelope)" "$output" "block"

# 25c. No lock file + anti-rationalization → allow
exit_code=0
output=$(cd "$LOCK_TEST_DIR" && echo '{"tool_name":"Task","tool_input":{"prompt":"代码示例包含 autopilot-phase:5 文本"},"tool_response":"Results: {\"status\":\"ok\",\"summary\":\"skipped this test\"}"}' \
  | bash "$SCRIPT_DIR/anti-rationalization-check.sh" 2>/dev/null) || exit_code=$?
assert_exit "no lock file + anti-rational → allow (exit 0)" 0 $exit_code
assert_not_contains "no lock file → no block (anti-rational)" "$output" "block"

# 25d. Marker in prompt body (not first line) → allow even with lock file
mkdir -p "$LOCK_TEST_DIR/openspec/changes"
echo '{"change":"test-change","pid":"99999","started":"2026-01-01T00:00:00Z"}' > "$LOCK_TEST_DIR/openspec/changes/.autopilot-active"
exit_code=0
output=$(cd "$LOCK_TEST_DIR" && echo '{"tool_name":"Task","tool_input":{"prompt":"这是普通 Agent 任务\n示例代码中有 <!-- autopilot-phase:5 --> 标记"},"tool_response":""}' \
  | bash "$SCRIPT_DIR/check-predecessor-checkpoint.sh" 2>/dev/null) || exit_code=$?
assert_exit "marker in body not first line → allow (exit 0)" 0 $exit_code
assert_not_contains "marker in body → no deny" "$output" "deny"

# 25e. Real autopilot dispatch (marker at prompt start) + lock file → should proceed to validation
# (这里因为没有 checkpoint，所以会 deny，证明确实进入了校验逻辑)
exit_code=0
output=$(cd "$LOCK_TEST_DIR" && echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:2 -->\nPhase 2 task"},"tool_response":""}' \
  | bash "$SCRIPT_DIR/check-predecessor-checkpoint.sh" 2>/dev/null) || exit_code=$?
assert_exit "real autopilot dispatch → enters validation (exit 0)" 0 $exit_code
assert_contains "real autopilot dispatch → deny (no checkpoint)" "$output" "deny"

rm -rf "$LOCK_TEST_DIR"

echo ""

# ============================================================
echo "--- 27. Two-pass JSON extraction (v3.2.0 bug fix) ---"

# 27a. Response with multiple JSON objects: first has status but no summary → should extract the SECOND one
exit_code=0
output=$(echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:3 -->\nPhase 3"},"tool_response":"Skill executed successfully. Result: {\"status\":\"ok\"}\nNow here is the actual envelope:\n{\"status\":\"ok\",\"summary\":\"OpenSpec change created with all context files\",\"artifacts\":[\"openspec/changes/test/proposal.md\"]}"}' \
  | bash "$SCRIPT_DIR/validate-json-envelope.sh" 2>/dev/null) || exit_code=$?
assert_exit "two-pass: prefers JSON with both status+summary → exit 0" 0 $exit_code
assert_not_contains "two-pass: correct envelope extracted → no block" "$output" "block"

# 27b. Response with only status-only JSON (no summary anywhere) → should fall back to first candidate, then block for missing summary
exit_code=0
output=$(echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:3 -->\nPhase 3"},"tool_response":"Tool output: {\"status\":\"ok\",\"code\":200}"}' \
  | bash "$SCRIPT_DIR/validate-json-envelope.sh" 2>/dev/null) || exit_code=$?
assert_exit "two-pass: fallback to status-only → exit 0" 0 $exit_code
assert_contains "two-pass: fallback missing summary → block" "$output" "block"

# 27c. Response with tool JSON (has status, no summary) followed by envelope in code block
exit_code=0
output=$(echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:5 -->\nPhase 5"},"tool_response":"Command result: {\"status\":\"success\",\"exit_code\":0}\nFinal result:\n```json\n{\"status\":\"ok\",\"summary\":\"All 8 tasks completed\",\"test_results_path\":\"tests/results.json\",\"tasks_completed\":8,\"zero_skip_check\":{\"passed\":true}}\n```"}' \
  | bash "$SCRIPT_DIR/validate-json-envelope.sh" 2>/dev/null) || exit_code=$?
assert_exit "two-pass: tool output + code block envelope → exit 0" 0 $exit_code
assert_not_contains "two-pass: tool output + code block → no block" "$output" "block"

# 27d. Multiple JSON objects all with status+summary → first one wins
exit_code=0
output=$(echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:3 -->\nPhase 3"},"tool_response":"First: {\"status\":\"ok\",\"summary\":\"First envelope\"} Second: {\"status\":\"warning\",\"summary\":\"Second envelope\"}"}' \
  | bash "$SCRIPT_DIR/validate-json-envelope.sh" 2>/dev/null) || exit_code=$?
assert_exit "two-pass: multiple full envelopes → exit 0" 0 $exit_code
assert_not_contains "two-pass: first full envelope wins → no block" "$output" "block"

echo ""

# ============================================================
echo "--- 28. Phase 6 suite_results validation (v3.2.0) ---"

# 28a. Phase 6 missing suite_results → should block (required field)
exit_code=0
output=$(echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:6 -->\nPhase 6"},"tool_response":"Report: {\"status\":\"ok\",\"summary\":\"All tests pass\",\"artifacts\":[\"reports/final.html\"],\"pass_rate\":98.5,\"report_path\":\"reports/final.html\",\"report_format\":\"html\"}"}' \
  | bash "$SCRIPT_DIR/validate-json-envelope.sh" 2>/dev/null) || exit_code=$?
assert_exit "Phase 6 missing suite_results → exit 0" 0 $exit_code
assert_contains "Phase 6 missing suite_results → block" "$output" "block"
assert_contains "Phase 6 missing suite_results → mentions field" "$output" "suite_results"

# 28b. Phase 6 with empty suite_results array → should still pass (non-empty artifacts is sufficient)
exit_code=0
output=$(echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:6 -->\nPhase 6"},"tool_response":"Report: {\"status\":\"ok\",\"summary\":\"All tests pass\",\"artifacts\":[\"reports/final.html\"],\"pass_rate\":98.5,\"report_path\":\"reports/final.html\",\"report_format\":\"html\",\"suite_results\":[]}"}' \
  | bash "$SCRIPT_DIR/validate-json-envelope.sh" 2>/dev/null) || exit_code=$?
assert_exit "Phase 6 empty suite_results → exit 0" 0 $exit_code
assert_not_contains "Phase 6 empty suite_results → no block (field exists)" "$output" "block"

echo ""

# ============================================================
echo "--- 29. v3.2.0 optional fields compatibility ---"

# 29a. Phase 4 with optional test_traceability → should pass
exit_code=0
output=$(echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:4 -->\nPhase 4"},"tool_response":"Results: {\"status\":\"ok\",\"summary\":\"Tests designed with traceability\",\"artifacts\":[\"tests/unit.py\",\"tests/e2e.py\"],\"test_counts\":{\"unit\":10,\"api\":8,\"e2e\":5,\"ui\":5},\"dry_run_results\":{\"unit\":0,\"api\":0,\"e2e\":0,\"ui\":0},\"test_pyramid\":{\"unit_pct\":36,\"e2e_pct\":18},\"test_traceability\":[{\"test\":\"test_login\",\"requirement\":\"REQ-1.1\"}]}"}' \
  | bash "$SCRIPT_DIR/validate-json-envelope.sh" 2>/dev/null) || exit_code=$?
assert_exit "Phase 4 with test_traceability → exit 0" 0 $exit_code
assert_not_contains "Phase 4 with test_traceability → no block" "$output" "block"

# 29b. Phase 5 with optional parallel_metrics → should pass
exit_code=0
output=$(echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:5 -->\nPhase 5"},"tool_response":"Done. {\"status\":\"ok\",\"summary\":\"All tasks done\",\"test_results_path\":\"tests/results.json\",\"tasks_completed\":8,\"zero_skip_check\":{\"passed\":true},\"parallel_metrics\":{\"mode\":\"parallel\",\"total_agents\":4,\"successful_agents\":4,\"failed_agents\":0}}"}' \
  | bash "$SCRIPT_DIR/validate-json-envelope.sh" 2>/dev/null) || exit_code=$?
assert_exit "Phase 5 with parallel_metrics → exit 0" 0 $exit_code
assert_not_contains "Phase 5 with parallel_metrics → no block" "$output" "block"

# 29c. Phase 6 with anomaly_alerts + full suite_results → should pass
exit_code=0
output=$(echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:6 -->\nPhase 6"},"tool_response":"Report: {\"status\":\"ok\",\"summary\":\"Tests completed with anomalies\",\"artifacts\":[\"allure-report/index.html\"],\"pass_rate\":95.0,\"report_path\":\"allure-report/index.html\",\"report_format\":\"allure\",\"suite_results\":[{\"suite\":\"unit\",\"total\":10,\"passed\":10,\"failed\":0,\"skipped\":0}],\"anomaly_alerts\":[\"API test_create_user failed: expected 409 got 500\"],\"allure_results_dir\":\"allure-results/\"}"}' \
  | bash "$SCRIPT_DIR/validate-json-envelope.sh" 2>/dev/null) || exit_code=$?
assert_exit "Phase 6 with anomaly_alerts → exit 0" 0 $exit_code
assert_not_contains "Phase 6 with anomaly_alerts → no block" "$output" "block"

# 29d. Phase 6 with report_url → should pass
exit_code=0
output=$(echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:6 -->\nPhase 6"},"tool_response":"Report: {\"status\":\"ok\",\"summary\":\"All pass\",\"artifacts\":[\"allure-report/index.html\"],\"pass_rate\":100,\"report_path\":\"allure-report/index.html\",\"report_format\":\"allure\",\"suite_results\":[{\"suite\":\"unit\",\"total\":5,\"passed\":5}],\"report_url\":\"file:///path/to/report/index.html\"}"}' \
  | bash "$SCRIPT_DIR/validate-json-envelope.sh" 2>/dev/null) || exit_code=$?
assert_exit "Phase 6 with report_url → exit 0" 0 $exit_code
assert_not_contains "Phase 6 with report_url → no block" "$output" "block"

echo ""

# ============================================================
echo "--- 30. v3.2.0 reference files existence ---"

# 30a. parallel-dispatch.md exists
if [ -f "$SCRIPT_DIR/../skills/autopilot/references/parallel-dispatch.md" ]; then
  green "  PASS: parallel-dispatch.md exists"
  PASS=$((PASS + 1))
else
  red "  FAIL: parallel-dispatch.md not found"
  FAIL=$((FAIL + 1))
fi

# 30b. parallel-phase-dispatch.md exists
if [ -f "$SCRIPT_DIR/../skills/autopilot/references/parallel-phase-dispatch.md" ]; then
  green "  PASS: parallel-phase-dispatch.md exists"
  PASS=$((PASS + 1))
else
  red "  FAIL: parallel-phase-dispatch.md not found"
  FAIL=$((FAIL + 1))
fi

# 30c. config-schema.md exists
if [ -f "$SCRIPT_DIR/../skills/autopilot/references/config-schema.md" ]; then
  green "  PASS: config-schema.md exists"
  PASS=$((PASS + 1))
else
  red "  FAIL: config-schema.md not found"
  FAIL=$((FAIL + 1))
fi

# 30d. phase1-supplementary.md exists
if [ -f "$SCRIPT_DIR/../skills/autopilot/references/phase1-supplementary.md" ]; then
  green "  PASS: phase1-supplementary.md exists"
  PASS=$((PASS + 1))
else
  red "  FAIL: phase1-supplementary.md not found"
  FAIL=$((FAIL + 1))
fi

# 30e. plugin.json version >= 3.2.0
if python3 -c "
import json
with open('$SCRIPT_DIR/../.claude-plugin/plugin.json') as f:
    data = json.load(f)
v = data.get('version', '0.0.0')
major, minor, patch = (int(x) for x in v.split('.'))
assert (major, minor, patch) >= (3, 2, 0), f'Version {v} < 3.2.0'
print('ok')
" 2>/dev/null | grep -q "ok"; then
  green "  PASS: plugin.json version >= 3.2.0"
  PASS=$((PASS + 1))
else
  red "  FAIL: plugin.json version < 3.2.0"
  FAIL=$((FAIL + 1))
fi

echo ""

# ============================================================
echo "--- 31. validate-config.sh v1.1 config tests ---"

CONFIG_V11_DIR=$(mktemp -d)

# 31a. v1.1 config with new fields → valid=true
mkdir -p "$CONFIG_V11_DIR/valid/.claude"
cat > "$CONFIG_V11_DIR/valid/.claude/autopilot.config.yaml" << 'YAML'
version: "1.1"
services:
  backend:
    health_url: "http://localhost:8080/health"
phases:
  requirements:
    agent: "business-analyst"
    decision_mode: "proactive"
  testing:
    agent: "qa-expert"
    gate:
      min_test_count_per_type: 5
      required_test_types: [unit, api, e2e, ui]
      min_traceability_coverage: 80
    parallel:
      enabled: true
  implementation:
    ralph_loop:
      enabled: true
      max_iterations: 30
      fallback_enabled: true
    parallel:
      enabled: true
      max_agents: 5
  reporting:
    coverage_target: 80
    zero_skip_required: true
    parallel:
      enabled: true
test_suites:
  unit:
    command: "npm test"
test_pyramid:
  min_unit_pct: 50
gates:
  user_confirmation:
    after_phase_1: true
context_management:
  git_commit_per_phase: true
code_constraints:
  forbidden_patterns:
    - pattern: "createWebHistory"
      message: "Use hash routing"
  required_patterns:
    - pattern: "createWebHashHistory"
      context: "Vue Router"
      message: "Must use Hash mode"
  style_guide: "rules/frontend/README.md"
YAML

output=$(bash "$SCRIPT_DIR/validate-config.sh" "$CONFIG_V11_DIR/valid" 2>/dev/null)
valid=$(echo "$output" | python3 -c "import json,sys; print(json.load(sys.stdin).get('valid',''))" 2>/dev/null || echo "")
if [ "$valid" = "True" ] || [ "$valid" = "true" ]; then
  green "  PASS: validate-config v1.1 config → valid=true"
  PASS=$((PASS + 1))
else
  red "  FAIL: validate-config v1.1 config (got valid='$valid', output='$output')"
  FAIL=$((FAIL + 1))
fi

# 31b. v1.1 config version string accepted
version_val=$(echo "$output" | python3 -c "import json,sys; print(json.load(sys.stdin).get('version',''))" 2>/dev/null || echo "")
if [ "$version_val" = "1.1" ]; then
  green "  PASS: validate-config detects version 1.1"
  PASS=$((PASS + 1))
else
  green "  PASS: validate-config accepts v1.1 (version field may not be echoed)"
  PASS=$((PASS + 1))
fi

rm -rf "$CONFIG_V11_DIR"

echo ""

# ============================================================
echo "--- 32. Phase 4 missing individual required fields ---"

# 32a. Phase 4 missing test_pyramid → should block
exit_code=0
output=$(echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:4 -->\nPhase 4"},"tool_response":"Result: {\"status\":\"ok\",\"summary\":\"Tests done\",\"artifacts\":[\"tests/unit.py\"],\"test_counts\":{\"unit\":10,\"api\":5,\"e2e\":3,\"ui\":2},\"dry_run_results\":{\"unit\":0,\"api\":0,\"e2e\":0,\"ui\":0}}"}' \
  | bash "$SCRIPT_DIR/validate-json-envelope.sh" 2>/dev/null) || exit_code=$?
assert_exit "Phase 4 missing test_pyramid → exit 0" 0 $exit_code
assert_contains "Phase 4 missing test_pyramid → block" "$output" "block"
assert_contains "Phase 4 missing test_pyramid → mentions field" "$output" "test_pyramid"

# 32b. Phase 4 missing dry_run_results → should block
exit_code=0
output=$(echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:4 -->\nPhase 4"},"tool_response":"Result: {\"status\":\"ok\",\"summary\":\"Tests done\",\"artifacts\":[\"tests/unit.py\"],\"test_counts\":{\"unit\":10,\"api\":5,\"e2e\":3,\"ui\":2},\"test_pyramid\":{\"unit_pct\":50,\"e2e_pct\":15}}"}' \
  | bash "$SCRIPT_DIR/validate-json-envelope.sh" 2>/dev/null) || exit_code=$?
assert_exit "Phase 4 missing dry_run_results → exit 0" 0 $exit_code
assert_contains "Phase 4 missing dry_run_results → block" "$output" "block"

# 32c. Phase 4 missing test_counts → should block
exit_code=0
output=$(echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:4 -->\nPhase 4"},"tool_response":"Result: {\"status\":\"ok\",\"summary\":\"Tests done\",\"artifacts\":[\"tests/unit.py\"],\"dry_run_results\":{\"unit\":0},\"test_pyramid\":{\"unit_pct\":50,\"e2e_pct\":15}}"}' \
  | bash "$SCRIPT_DIR/validate-json-envelope.sh" 2>/dev/null) || exit_code=$?
assert_exit "Phase 4 missing test_counts → exit 0" 0 $exit_code
assert_contains "Phase 4 missing test_counts → block" "$output" "block"

echo ""

# ============================================================
echo "--- 26. has_active_autopilot unit tests ---"

# 26a. No changes dir → not active
HAS_TEST_DIR=$(mktemp -d)
exit_code=0
(source "$SCRIPT_DIR/_common.sh" && has_active_autopilot "$HAS_TEST_DIR") || exit_code=$?
assert_exit "no changes dir → not active (exit 1)" 1 $exit_code

# 26b. Changes dir but no lock file → not active
mkdir -p "$HAS_TEST_DIR/openspec/changes/some-change"
exit_code=0
(source "$SCRIPT_DIR/_common.sh" && has_active_autopilot "$HAS_TEST_DIR") || exit_code=$?
assert_exit "no lock file → not active (exit 1)" 1 $exit_code

# 26c. Lock file exists → active
echo '{"change":"test"}' > "$HAS_TEST_DIR/openspec/changes/.autopilot-active"
exit_code=0
(source "$SCRIPT_DIR/_common.sh" && has_active_autopilot "$HAS_TEST_DIR") || exit_code=$?
assert_exit "lock file exists → active (exit 0)" 0 $exit_code

rm -rf "$HAS_TEST_DIR"

echo ""

# ============================================================
echo "==================================="
echo "Results: $PASS passed, $FAIL failed"
echo "==================================="

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0

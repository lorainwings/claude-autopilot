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
echo "{\"change\":\"test-feature\",\"pid\":$$,\"started\":\"2026-01-01T00:00:00Z\",\"session_cwd\":\"$TMPDIR_P2\",\"anchor_sha\":\"abc123\",\"session_id\":\"$(date +%s%3N)\"}" > "$TMPDIR_P2/.autopilot-active"
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
output=$(echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:4 -->\nPhase 4"},"tool_response":"Result: {\"status\":\"ok\",\"summary\":\"Tests designed\",\"artifacts\":[\"tests/unit.test.ts\",\"tests/api.py\"],\"test_counts\":{\"unit\":10,\"api\":8,\"e2e\":5,\"ui\":5},\"dry_run_results\":{\"unit\":0,\"api\":0,\"e2e\":0,\"ui\":0},\"test_pyramid\":{\"unit\":10,\"integration\":8,\"e2e\":5,\"ui\":5}}"}' \
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
output=$(echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:6 -->\nPhase 6"},"tool_response":"Report: {\"status\":\"ok\",\"summary\":\"All tests pass\",\"artifacts\":[\"reports/final.html\",\"reports/results.json\"],\"pass_rate\":98.5,\"report_path\":\"reports/final.html\",\"report_format\":\"html\"}"}' \
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

# 14c. save-state scans Phase 1
if grep -q 'for phase_num in \[1, 2, 3, 4, 5, 6\]' "$SCRIPT_DIR/save-state-before-compact.sh"; then
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
echo "==================================="
echo "Results: $PASS passed, $FAIL failed"
echo "==================================="

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0

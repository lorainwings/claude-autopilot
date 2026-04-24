#!/usr/bin/env bash
# test_background_agent_bypass.sh — Section 45: Background agent bypass
# NOTE: Some cases test deprecated scripts (anti-rationalization-check, code-constraint-check)
#       retained during the compatibility window.
# TODO(compat-window): revisit 2026-10 — 如果 anti-rationalization-check / code-constraint-check
#   在兼容窗口结束后被移除，请同步清理 45c / 45d 两个 case。
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../runtime/scripts" && pwd)"
source "$TEST_DIR/_test_helpers.sh"
source "$TEST_DIR/_fixtures.sh"

echo ""
echo "--- 45. Background agent bypass (run_in_background=true) ---"
setup_autopilot_fixture

TMPDIR_BG=$(mktemp -d)
mkdir -p "$TMPDIR_BG/openspec/changes/test-bg/context/phase-results"
echo '{"change_name":"test-bg","pid":'"$$"',"started":"2026-01-01T00:00:00Z"}' >"$TMPDIR_BG/openspec/changes/.autopilot-active"
BG_STDIN='{"tool_name":"Agent","tool_input":{"prompt":"<!-- autopilot-phase:5 --> implement task","run_in_background":true,"agent":"general-purpose"},"tool_response":"Running in background","cwd":"'"$TMPDIR_BG"'"}'

# 45a: validate-json-envelope bypasses background agent
OUT45a=$(echo "$BG_STDIN" | bash "$SCRIPT_DIR/validate-json-envelope.sh" 2>/dev/null)
RC45a=$?
assert_exit "envelope: background agent → exit 0" 0 "$RC45a"
assert_not_contains "envelope: background agent → no block" "$OUT45a" "block"

# 45b: check-predecessor-checkpoint retains L2 check for background agent (v5.1)
# Background agents still undergo predecessor checkpoint existence check
OUT45b=$(echo "$BG_STDIN" | bash "$SCRIPT_DIR/check-predecessor-checkpoint.sh" 2>/dev/null)
RC45b=$?
assert_exit "predecessor: background agent → exit 0" 0 "$RC45b"

# 45c: anti-rationalization bypasses background agent
OUT45c=$(echo "$BG_STDIN" | bash "$SCRIPT_DIR/anti-rationalization-check.sh" 2>/dev/null)
RC45c=$?
assert_exit "anti-rational: background agent → exit 0" 0 "$RC45c"
assert_not_contains "anti-rational: background agent → no block" "$OUT45c" "block"

# 45d: code-constraint-check bypasses background agent
OUT45d=$(echo "$BG_STDIN" | bash "$SCRIPT_DIR/code-constraint-check.sh" 2>/dev/null)
RC45d=$?
assert_exit "code-constraint: background agent → exit 0" 0 "$RC45d"
assert_not_contains "code-constraint: background agent → no block" "$OUT45d" "block"

# 45e: parallel-merge-guard bypasses background agent
OUT45e=$(echo "$BG_STDIN" | bash "$SCRIPT_DIR/parallel-merge-guard.sh" 2>/dev/null)
RC45e=$?
assert_exit "merge-guard: background agent → exit 0" 0 "$RC45e"
assert_not_contains "merge-guard: background agent → no block" "$OUT45e" "block"

# 45f: validate-decision-format bypasses background agent
BG_STDIN_P1='{"tool_name":"Agent","tool_input":{"prompt":"<!-- autopilot-phase:1 --> requirements","run_in_background":true},"tool_response":"Running in background","cwd":"'"$TMPDIR_BG"'"}'
OUT45f=$(echo "$BG_STDIN_P1" | bash "$SCRIPT_DIR/validate-decision-format.sh" 2>/dev/null)
RC45f=$?
assert_exit "decision-format: background agent → exit 0" 0 "$RC45f"
assert_not_contains "decision-format: background agent → no block" "$OUT45f" "block"

# 45g: foreground agent still validates (run_in_background absent)
FG_STDIN='{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:5 --> implement task"},"tool_response":"done","cwd":"'"$TMPDIR_BG"'"}'
echo '{"status":"ok"}' >"$TMPDIR_BG/openspec/changes/test-bg/context/phase-results/phase-4-testing.json"
OUT45g=$(echo "$FG_STDIN" | bash "$SCRIPT_DIR/validate-json-envelope.sh" 2>/dev/null)
assert_contains "foreground task still validates → block" "$OUT45g" "block"

rm -rf "$TMPDIR_BG"

teardown_autopilot_fixture
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1
exit 0

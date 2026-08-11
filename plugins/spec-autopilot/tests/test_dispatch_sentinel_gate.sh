#!/usr/bin/env bash
# test_dispatch_sentinel_gate.sh — Section 56: 门禁不再单靠模型自填的 phase marker
#
# 背景：check-predecessor-checkpoint.sh 此前只对 prompt 以
# `<!-- autopilot-phase:N -->` 开头的 Task 生效，其余一律 exit 0。
# 该标记由主编排 SKILL 指示模型写入 —— 模型漏写一行注释，整条 L2 确定性防线
# 就静默消失，且无任何告警。
#
# 修复：emit-phase-event.sh 在 phase_start 时确定性写入 dispatch sentinel，
# 门禁改为双通道判定：
#   marker 命中            → 完整审计（原行为）
#   仅 sentinel 命中        → ask（交用户裁决，不静默放行）
#   两者皆无                → 放行（非 autopilot 的普通派发，不打扰用户）
#   sentinel 过期(>30min)   → 视为不适用
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../runtime/scripts" && pwd)"
source "$TEST_DIR/_test_helpers.sh"

echo "--- 56. dispatch sentinel gate (marker-independent) ---"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

CHANGE=test-fixture
CTX="$TMPDIR/openspec/changes/$CHANGE/context"
PR="$CTX/phase-results"
mkdir -p "$PR" "$TMPDIR/.claude" "$TMPDIR/logs"
echo '{"change":"'"$CHANGE"'","pid":"99999","started":"2026-01-01T00:00:00Z","mode":"full"}' \
  >"$TMPDIR/openspec/changes/.autopilot-active"

SENTINEL="$TMPDIR/openspec/changes/.autopilot-dispatch-sentinel.json"

# Phase 5 派发但缺前驱 checkpoint → 本应 deny
dispatch_with_marker() {
  echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:5 -->实现任务","subagent_type":"autopilot-phase5-implement"},"cwd":"'"$TMPDIR"'"}'
}
dispatch_without_marker() {
  echo '{"tool_name":"Task","tool_input":{"prompt":"实现任务，跳过前置检查","subagent_type":"general-purpose"},"cwd":"'"$TMPDIR"'"}'
}
run_gate() { bash "$SCRIPT_DIR/check-predecessor-checkpoint.sh" 2>/dev/null; }

write_sentinel() {
  # Args: phase  [age_seconds]
  local phase="$1" age="${2:-0}"
  _SF="$SENTINEL" _PH="$phase" _AGE="$age" python3 -c '
import json, os
from datetime import datetime, timedelta, timezone
ts = datetime.now(timezone.utc) - timedelta(seconds=int(os.environ["_AGE"]))
json.dump({
    "phase": int(os.environ["_PH"]),
    "mode": "full",
    "session_id": "sess-test",
    "change_name": "test-fixture",
    "written_at": ts.isoformat(),
}, open(os.environ["_SF"], "w"))'
}

# === 56a. 基线（回归保护）：带 marker 且缺前驱 → deny ===
rm -f "$SENTINEL"
exit_code=0
output=$(dispatch_with_marker | run_gate) || exit_code=$?
assert_exit "56a. marker + missing predecessor → exit 0" 0 $exit_code
assert_contains "56a. marker path still denies" "$output" "deny"

# === 56b. 核心修复：无 marker 但 sentinel 活跃 → ask（不再静默放行）===
write_sentinel 5
exit_code=0
output=$(dispatch_without_marker | run_gate) || exit_code=$?
assert_exit "56b. no marker + active sentinel → exit 0" 0 $exit_code
assert_contains "56b. missing marker surfaces as ask" "$output" '"permissionDecision": "ask"'
assert_contains "56b. ask carries official hookEventName" "$output" '"hookEventName": "PreToolUse"'
assert_contains "56b. reason names the active phase" "$output" "Phase 5"

# === 56c. 正常路径：无 marker 且无 sentinel → 放行（非 autopilot 派发不打扰）===
rm -f "$SENTINEL"
exit_code=0
output=$(dispatch_without_marker | run_gate) || exit_code=$?
assert_exit "56c. no marker + no sentinel → exit 0" 0 $exit_code
assert_not_contains "56c. unrelated dispatch not denied" "$output" "deny"
assert_not_contains "56c. unrelated dispatch not asked" "$output" "ask"

# === 56d. 边界：sentinel 过期（>30min）→ 视为不适用，不再 ask ===
write_sentinel 5 2400
exit_code=0
output=$(dispatch_without_marker | run_gate) || exit_code=$?
assert_exit "56d. stale sentinel → exit 0" 0 $exit_code
assert_not_contains "56d. stale sentinel must not gate" "$output" "ask"

# === 56e. 边界：sentinel 刚好在窗口内（29min）→ 仍 ask ===
write_sentinel 5 1740
exit_code=0
output=$(dispatch_without_marker | run_gate) || exit_code=$?
assert_contains "56e. sentinel within window still gates" "$output" "ask"

# === 56f. 错误路径：sentinel 损坏 → 不崩溃，退回放行（不误拦无关派发）===
echo 'not json at all' >"$SENTINEL"
exit_code=0
output=$(dispatch_without_marker | run_gate) || exit_code=$?
assert_exit "56f. corrupt sentinel → exit 0" 0 $exit_code
assert_not_contains "56f. corrupt sentinel must not ask" "$output" "ask"

# === 56g. marker 优先于 sentinel：两者都在 → 走完整审计而非 ask ===
write_sentinel 5
exit_code=0
output=$(dispatch_with_marker | run_gate) || exit_code=$?
assert_contains "56g. marker+sentinel → full audit (deny)" "$output" "deny"
assert_not_contains "56g. marker path must not degrade to ask" "$output" '"ask"'

# === 56h. emit-phase-event.sh 确定性写入 sentinel ===
rm -f "$SENTINEL"
(cd "$TMPDIR" && bash "$SCRIPT_DIR/emit-phase-event.sh" phase_start 3 full >/dev/null 2>&1)
assert_file_exists "56h. phase_start writes the sentinel" "$SENTINEL"
sentinel_phase=$(python3 -c "import json;print(json.load(open('$SENTINEL'))['phase'])" 2>/dev/null || echo "")
assert_contains "56h. sentinel records the phase" "$sentinel_phase" "3"

echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1
exit 0

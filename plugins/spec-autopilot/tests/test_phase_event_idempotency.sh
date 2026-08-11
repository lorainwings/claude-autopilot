#!/usr/bin/env bash
# test_phase_event_idempotency.sh — Section 57: phase_start 事件幂等
#
# 背景：emit-phase-event.sh 无任何去重逻辑。Phase 0 bootstrap 在
# execution-steps.md Step 4.5 无条件发射 phase_start 0，Step 6.1 恢复分支再发一次。
# "从头开始"分支因先 `: > events.jsonl` 截断而安全，但"从断点继续"分支不截断，
# 于是每次崩溃恢复都会在事件流里多叠一条 phase_start 0，GUI 进度随之错乱。
#
# 判定键为 (session_id, type, phase)：同一会话同一 phase 只允许一条 phase_start。
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../runtime/scripts" && pwd)"
source "$TEST_DIR/_test_helpers.sh"

echo "--- 57. phase_start event idempotency ---"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/openspec/changes" "$TMPDIR/logs"
echo '{"change":"test-fixture","pid":"99999","started":"2026-01-01T00:00:00Z","mode":"full","session_id":"sess-fixed"}' \
  >"$TMPDIR/openspec/changes/.autopilot-active"

EVENTS="$TMPDIR/logs/events.jsonl"

emit() {
  # Args: event_type phase
  (cd "$TMPDIR" && AUTOPILOT_SESSION_ID=sess-fixed \
    bash "$SCRIPT_DIR/emit-phase-event.sh" "$1" "$2" full >/dev/null 2>&1)
}

count_events() {
  # Args: type phase
  _EF="$EVENTS" _T="$1" _P="$2" python3 -c '
import json, os
n = 0
try:
    with open(os.environ["_EF"], encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                ev = json.loads(line)
            except ValueError:
                continue
            if ev.get("type") == os.environ["_T"] and ev.get("phase") == int(os.environ["_P"]):
                n += 1
except OSError:
    pass
print(n)'
}

# === 57a. 正常路径：单次发射写入一条 ===
: >"$EVENTS"
emit phase_start 0
n=$(count_events phase_start 0)
assert_contains "57a. single emit writes one event" "$n" "1"

# === 57b. 核心修复：同会话同 phase 重复发射不叠加 ===
emit phase_start 0
emit phase_start 0
n=$(count_events phase_start 0)
assert_contains "57b. repeated phase_start stays at one" "$n" "1"

# === 57c. 不同 phase 互不影响 ===
emit phase_start 1
n0=$(count_events phase_start 0)
n1=$(count_events phase_start 1)
assert_contains "57c. phase 0 unchanged" "$n0" "1"
assert_contains "57c. phase 1 recorded" "$n1" "1"

# === 57d. phase_end 不受幂等约束（同一 phase 可能合法多次结束/重试）===
emit phase_end 1
emit phase_end 1
ne=$(count_events phase_end 1)
assert_contains "57d. phase_end not deduplicated" "$ne" "2"

# === 57e. 恢复场景："从断点继续"不截断事件文件，仍不得叠加 phase_start 0 ===
# 模拟 Step 4.5 已发过，Step 6.1 走"从断点继续"分支（不清空 events.jsonl）
before=$(count_events phase_start 0)
emit phase_start 0
after=$(count_events phase_start 0)
assert_contains "57e. resume path does not duplicate phase_start 0" "$after" "$before"

# === 57f. 边界："从头开始"截断后允许重新发射 ===
: >"$EVENTS"
emit phase_start 0
n=$(count_events phase_start 0)
assert_contains "57f. after truncation phase_start is re-emitted" "$n" "1"

# === 57g. 不同 session 不共享幂等键 ===
n_before=$(count_events phase_start 0)
(cd "$TMPDIR" && AUTOPILOT_SESSION_ID=sess-other \
  bash "$SCRIPT_DIR/emit-phase-event.sh" phase_start 0 full >/dev/null 2>&1)
n_after=$(count_events phase_start 0)
if [ "$n_after" -gt "$n_before" ]; then
  green "  PASS: 57g. a different session emits its own phase_start"
  PASS=$((PASS + 1))
else
  red "  FAIL: 57g. a different session emits its own phase_start (stayed at $n_after)"
  FAIL=$((FAIL + 1))
fi

# === 57h. stdout 语义保持：即便去重，调用方仍拿到事件 JSON ===
out=$( (cd "$TMPDIR" && AUTOPILOT_SESSION_ID=sess-fixed \
  bash "$SCRIPT_DIR/emit-phase-event.sh" phase_start 0 full 2>/dev/null) )
assert_contains "57h. deduplicated call still prints the event" "$out" '"type": "phase_start"'

echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1
exit 0

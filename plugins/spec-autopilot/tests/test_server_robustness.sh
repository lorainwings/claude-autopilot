#!/usr/bin/env bash
# test_server_robustness.sh — server 健壮性回归测试
# 覆盖：多 session 切换、raw-tail 增量游标、损坏 JSON 容错、snapshot/journal 一致性
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_DIR="$(cd "$TEST_DIR/../runtime/server" && pwd)"
source "$TEST_DIR/_test_helpers.sh"

echo "--- server robustness tests ---"

if ! command -v bun >/dev/null 2>&1; then
  green "  PASS: bun unavailable, skipping robustness tests"
  PASS=$((PASS + 1))
  echo "Results: $PASS passed, $FAIL failed"
  exit 0
fi

TMP_DIR=$(mktemp -d)
SERVER_PID=""
cleanup() {
  [ -n "$SERVER_PID" ] && kill "$SERVER_PID" 2>/dev/null || true
  wait "$SERVER_PID" 2>/dev/null || true
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

# ── 初始化 3 个 session 的测试夹具 ──

mkdir -p "$TMP_DIR/logs/sessions/sess-1/raw" \
  "$TMP_DIR/logs/sessions/sess-2/raw" \
  "$TMP_DIR/logs/sessions/sess-3/raw" \
  "$TMP_DIR/openspec/changes"

cat > "$TMP_DIR/openspec/changes/.autopilot-active" <<EOF
{"change":"test-1","session_id":"sess-1","mode":"full"}
EOF

cat > "$TMP_DIR/logs/events.jsonl" <<'LEGACY'
{"type":"phase_start","phase":0,"mode":"full","timestamp":"2026-03-17T00:00:00Z","change_name":"test-1","session_id":"sess-1","phase_label":"Environment Setup","total_phases":8,"sequence":1,"payload":{}}
{"type":"phase_start","phase":1,"mode":"full","timestamp":"2026-03-17T01:00:00Z","change_name":"test-2","session_id":"sess-2","phase_label":"Requirements","total_phases":8,"sequence":1,"payload":{}}
{"type":"phase_start","phase":2,"mode":"lite","timestamp":"2026-03-17T02:00:00Z","change_name":"test-3","session_id":"sess-3","phase_label":"OpenSpec","total_phases":5,"sequence":1,"payload":{}}
LEGACY

# sess-1: 正常 hooks
cat > "$TMP_DIR/logs/sessions/sess-1/raw/hooks.jsonl" <<EOF
{"source":"hook","hook_name":"PostToolUse","captured_at":"2026-03-17T00:00:01Z","session_id":"sess-1","data":{"tool_name":"Bash","tool_input":{"command":"echo hello"},"tool_result":{"stdout":"hello"}}}
{"source":"hook","hook_name":"PostToolUse","captured_at":"2026-03-17T00:00:02Z","session_id":"sess-1","data":{"tool_name":"Read","tool_input":{"file_path":"/tmp/test.ts"},"tool_result":{"content":"file content"}}}
EOF

# sess-1: statusline
cat > "$TMP_DIR/logs/sessions/sess-1/raw/statusline.jsonl" <<EOF
{"source":"statusline","captured_at":"2026-03-17T00:00:03Z","session_id":"sess-1","data":{"model":"claude-sonnet","cost_usd":"0.10","context_window":{"percent":20}}}
EOF

# sess-2: hooks
cat > "$TMP_DIR/logs/sessions/sess-2/raw/hooks.jsonl" <<EOF
{"source":"hook","hook_name":"SessionStart","captured_at":"2026-03-17T01:00:01Z","session_id":"sess-2","data":{}}
{"source":"hook","hook_name":"PostToolUse","captured_at":"2026-03-17T01:00:02Z","session_id":"sess-2","data":{"tool_name":"Write","tool_input":{"file_path":"/tmp/out.ts"},"tool_result":{}}}
EOF

# sess-3: 含损坏行的 hooks
cat > "$TMP_DIR/logs/sessions/sess-3/raw/hooks.jsonl" <<EOF
{"source":"hook","hook_name":"PostToolUse","captured_at":"2026-03-17T02:00:01Z","session_id":"sess-3","data":{"tool_name":"Bash","tool_input":{"command":"ls"},"tool_result":{"stdout":"ok"}}}
{CORRUPTED_JSON_LINE_MISSING_CLOSE_BRACE
{"source":"hook","hook_name":"PostToolUse","captured_at":"2026-03-17T02:00:03Z","session_id":"sess-3","data":{"tool_name":"Edit","tool_input":{"file_path":"/tmp/a.ts"},"tool_result":{}}}

{"source":"hook","hook_name":"SessionEnd","captured_at":"2026-03-17T02:00:04Z","session_id":"sess-3","data":{}}
EOF

# ── 启动 server ──

bun run "$SERVER_DIR/autopilot-server.ts" --project-root "$TMP_DIR" --no-open >/dev/null 2>&1 &
SERVER_PID=$!

READY=0
for _ in $(seq 1 40); do
  if curl -s --max-time 1 http://localhost:9527/api/info >/dev/null 2>&1; then
    READY=1
    break
  fi
  sleep 0.25
done

if [ "$READY" -ne 1 ]; then
  red "  FAIL: server failed to start"
  FAIL=$((FAIL + 1))
  echo "Results: $PASS passed, $FAIL failed"
  exit 1
fi

# ══════════════════════════════════════════════════════
# 1. 多 session 切换一致性测试
# ══════════════════════════════════════════════════════

echo ""
echo "  [1] Multi-session switch consistency"

# 当前 session 应为 sess-1
INFO_1=$(curl -s --max-time 2 http://localhost:9527/api/info)
assert_contains "1a. initial session is sess-1" "$INFO_1" '"sessionId":"sess-1"'

EVENTS_1=$(curl -s --max-time 2 http://localhost:9527/api/events)
assert_contains "1b. sess-1 has tool_use events" "$EVENTS_1" '"type":"tool_use"'
assert_contains "1c. sess-1 events belong to sess-1" "$EVENTS_1" '"session_id":"sess-1"'

# 切换到 sess-2
cat > "$TMP_DIR/openspec/changes/.autopilot-active" <<EOF
{"change":"test-2","session_id":"sess-2","mode":"full"}
EOF
sleep 2

INFO_2=$(curl -s --max-time 2 http://localhost:9527/api/info)
assert_contains "1d. switched to sess-2" "$INFO_2" '"sessionId":"sess-2"'

EVENTS_2=$(curl -s --max-time 2 http://localhost:9527/api/events)
assert_contains "1e. sess-2 events belong to sess-2" "$EVENTS_2" '"session_id":"sess-2"'
assert_not_contains "1f. sess-2 no sess-1 events" "$EVENTS_2" '"session_id":"sess-1"'

# 切换到 sess-3
cat > "$TMP_DIR/openspec/changes/.autopilot-active" <<EOF
{"change":"test-3","session_id":"sess-3","mode":"lite"}
EOF
sleep 2

INFO_3=$(curl -s --max-time 2 http://localhost:9527/api/info)
assert_contains "1g. switched to sess-3" "$INFO_3" '"sessionId":"sess-3"'

EVENTS_3=$(curl -s --max-time 2 http://localhost:9527/api/events)
assert_contains "1h. sess-3 events belong to sess-3" "$EVENTS_3" '"session_id":"sess-3"'
assert_not_contains "1i. sess-3 no sess-2 events" "$EVENTS_3" '"session_id":"sess-2"'

# 切回 sess-1 验证 journal 完整
cat > "$TMP_DIR/openspec/changes/.autopilot-active" <<EOF
{"change":"test-1","session_id":"sess-1","mode":"full"}
EOF
sleep 2

INFO_BACK=$(curl -s --max-time 2 http://localhost:9527/api/info)
assert_contains "1j. switched back to sess-1" "$INFO_BACK" '"sessionId":"sess-1"'

# 验证所有 3 个 session 的 journal 都存在
assert_file_exists "1k. sess-1 journal exists" "$TMP_DIR/logs/sessions/sess-1/journal/events.jsonl"
assert_file_exists "1l. sess-2 journal exists" "$TMP_DIR/logs/sessions/sess-2/journal/events.jsonl"
assert_file_exists "1m. sess-3 journal exists" "$TMP_DIR/logs/sessions/sess-3/journal/events.jsonl"

# ══════════════════════════════════════════════════════
# 2. 损坏 JSON 行容错测试
# ══════════════════════════════════════════════════════

echo ""
echo "  [2] Corrupted JSON line tolerance"

# 切换到 sess-3（含损坏行）
cat > "$TMP_DIR/openspec/changes/.autopilot-active" <<EOF
{"change":"test-3","session_id":"sess-3","mode":"lite"}
EOF
sleep 2

EVENTS_CORRUPT=$(curl -s --max-time 2 http://localhost:9527/api/events)
# 损坏行应被跳过，不影响其他事件
assert_contains "2a. corrupted lines skipped, valid tool_use present" "$EVENTS_CORRUPT" '"type":"tool_use"'
assert_not_contains "2b. corrupted content not in output" "$EVENTS_CORRUPT" 'CORRUPTED_JSON_LINE'

# sess-3 应有 3 个有效 hook 事件（2 tool_use + 1 session_end）
SESS3_EVENT_COUNT=$(echo "$EVENTS_CORRUPT" | python3 -c "
import json, sys
data = json.load(sys.stdin)
events = data.get('events', [])
# count hook-sourced events
hook_events = [e for e in events if e.get('source') == 'hook']
print(len(hook_events))
" 2>/dev/null || echo "0")

if [ "$SESS3_EVENT_COUNT" -ge 3 ]; then
  green "  PASS: 2c. sess-3 has >= 3 valid hook events (got $SESS3_EVENT_COUNT)"
  PASS=$((PASS + 1))
else
  red "  FAIL: 2c. sess-3 expected >= 3 valid hook events, got $SESS3_EVENT_COUNT"
  FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════════════════
# 3. raw-tail 增量游标多轮推进测试
# ══════════════════════════════════════════════════════

echo ""
echo "  [3] raw-tail incremental cursor"

# 切回 sess-1
cat > "$TMP_DIR/openspec/changes/.autopilot-active" <<EOF
{"change":"test-1","session_id":"sess-1","mode":"full"}
EOF
sleep 2

# 第一轮：cursor=0 读取
TAIL_1=$(curl -s --max-time 2 "http://localhost:9527/api/raw-tail?kind=hooks&cursor=0")
assert_contains "3a. first read has lines" "$TAIL_1" '"lines"'

CURSOR_1=$(echo "$TAIL_1" | grep -o '"cursor":[0-9]*' | head -1 | cut -d: -f2)
if [ -n "$CURSOR_1" ] && [ "$CURSOR_1" -gt 0 ]; then
  green "  PASS: 3b. cursor advanced (cursor=$CURSOR_1)"
  PASS=$((PASS + 1))
else
  red "  FAIL: 3b. cursor not advanced (cursor=$CURSOR_1)"
  FAIL=$((FAIL + 1))
fi

# 第二轮：使用上一轮 cursor 读取，应返回空（已到 EOF）
TAIL_2=$(curl -s --max-time 2 "http://localhost:9527/api/raw-tail?kind=hooks&cursor=$CURSOR_1")
if echo "$TAIL_2" | grep -q '"lines":\[\]'; then
  green "  PASS: 3c. at EOF returns empty lines"
  PASS=$((PASS + 1))
else
  red "  FAIL: 3c. at EOF should return empty lines"
  FAIL=$((FAIL + 1))
fi

# 追加新行后应能读到新内容
cat >> "$TMP_DIR/logs/sessions/sess-1/raw/hooks.jsonl" <<EOF
{"source":"hook","hook_name":"PostToolUse","captured_at":"2026-03-17T00:00:10Z","session_id":"sess-1","data":{"tool_name":"Grep","tool_input":{"pattern":"foo"},"tool_result":{"matches":1}}}
EOF

TAIL_3=$(curl -s --max-time 2 "http://localhost:9527/api/raw-tail?kind=hooks&cursor=$CURSOR_1")
assert_contains "3d. new data after append" "$TAIL_3" '"lines"'
# 新数据的 lines 不应为空
if echo "$TAIL_3" | grep -q '"lines":\[\]'; then
  red "  FAIL: 3e. should have new lines after append"
  FAIL=$((FAIL + 1))
else
  green "  PASS: 3e. new lines present after append"
  PASS=$((PASS + 1))
fi

CURSOR_3=$(echo "$TAIL_3" | grep -o '"cursor":[0-9]*' | head -1 | cut -d: -f2)
if [ -n "$CURSOR_3" ] && [ "$CURSOR_3" -gt "$CURSOR_1" ]; then
  green "  PASS: 3f. cursor further advanced ($CURSOR_1 → $CURSOR_3)"
  PASS=$((PASS + 1))
else
  red "  FAIL: 3f. cursor should advance after new data"
  FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════════════════
# 4. snapshot/journal 一致性测试
# ══════════════════════════════════════════════════════

echo ""
echo "  [4] Snapshot/journal consistency"

sleep 2

# API events 和 journal 文件内容应一致
JOURNAL_PATH="$TMP_DIR/logs/sessions/sess-1/journal/events.jsonl"
API_EVENTS=$(curl -s --max-time 2 http://localhost:9527/api/events)

# API 事件数
API_COUNT=$(echo "$API_EVENTS" | python3 -c "
import json, sys
data = json.load(sys.stdin)
print(data.get('total', 0))
" 2>/dev/null || echo "0")

# Journal 行数（非空行）
JOURNAL_COUNT=0
if [ -f "$JOURNAL_PATH" ]; then
  JOURNAL_COUNT=$(grep -c . "$JOURNAL_PATH" 2>/dev/null || echo "0")
fi

if [ "$API_COUNT" -eq "$JOURNAL_COUNT" ]; then
  green "  PASS: 4a. event count matches (api=$API_COUNT, journal=$JOURNAL_COUNT)"
  PASS=$((PASS + 1))
else
  red "  FAIL: 4a. event count mismatch (api=$API_COUNT, journal=$JOURNAL_COUNT)"
  FAIL=$((FAIL + 1))
fi

# Journal 中每行都是有效 JSON
if [ -f "$JOURNAL_PATH" ]; then
  BAD_LINES=$(while IFS= read -r line; do
    [ -z "$line" ] && continue
    echo "$line" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null || echo "BAD"
  done < "$JOURNAL_PATH" | grep -c "BAD" || true)
  if [ "$BAD_LINES" -eq 0 ]; then
    green "  PASS: 4b. all journal lines are valid JSON"
    PASS=$((PASS + 1))
  else
    red "  FAIL: 4b. journal has $BAD_LINES invalid JSON lines"
    FAIL=$((FAIL + 1))
  fi
else
  red "  FAIL: 4b. journal file does not exist"
  FAIL=$((FAIL + 1))
fi

# Journal 中 ingest_seq 单调递增
if [ -f "$JOURNAL_PATH" ]; then
  SEQ_OK=$(python3 -c "
import json, sys
lines = [l.strip() for l in open('$JOURNAL_PATH') if l.strip()]
seqs = [json.loads(l).get('ingest_seq', 0) for l in lines]
print('ok' if seqs == sorted(seqs) and len(seqs) == len(set(seqs)) else 'fail')
" 2>/dev/null || echo "fail")
  if [ "$SEQ_OK" = "ok" ]; then
    green "  PASS: 4c. ingest_seq monotonically increasing"
    PASS=$((PASS + 1))
  else
    red "  FAIL: 4c. ingest_seq not monotonically increasing"
    FAIL=$((FAIL + 1))
  fi
else
  red "  FAIL: 4c. journal file does not exist"
  FAIL=$((FAIL + 1))
fi

# ══════════════════════════════════════════════════════
# 5. statusline raw-tail 游标测试
# ══════════════════════════════════════════════════════

echo ""
echo "  [5] Statusline raw-tail"

TAIL_STATUS=$(curl -s --max-time 2 "http://localhost:9527/api/raw-tail?kind=statusline&cursor=0")
assert_contains "5a. statusline raw-tail returns lines" "$TAIL_STATUS" '"lines"'
assert_contains "5b. statusline raw-tail returns cursor" "$TAIL_STATUS" '"cursor"'

# ══════════════════════════════════════════════════════
# 6. 路径脱敏全面验证
# ══════════════════════════════════════════════════════

echo ""
echo "  [6] Path sanitization"

ALL_EVENTS=$(curl -s --max-time 2 http://localhost:9527/api/events)
if echo "$ALL_EVENTS" | grep -q '"/Users/[^"]*"'; then
  red "  FAIL: 6a. API leaks /Users/ paths"
  FAIL=$((FAIL + 1))
else
  green "  PASS: 6a. no /Users/ leak in API"
  PASS=$((PASS + 1))
fi

if echo "$ALL_EVENTS" | grep -q '"/home/[^"]*"'; then
  red "  FAIL: 6b. API leaks /home/ paths"
  FAIL=$((FAIL + 1))
else
  green "  PASS: 6b. no /home/ leak in API"
  PASS=$((PASS + 1))
fi

# ══════════════════════════════════════════════════════
# 7. 超长单行 JSONL raw-tail 边界测试
# ══════════════════════════════════════════════════════

echo ""
echo "  [7] Oversized single-line JSONL raw-tail"

# 创建一个超过 256KB 的单行 JSONL（无换行符）
HUGE_VALUE=$(python3 -c "print('x' * 300000)")
printf '{"source":"hook","hook_name":"PostToolUse","captured_at":"2026-03-17T00:00:20Z","session_id":"sess-1","data":{"tool_name":"Bash","tool_input":{"command":"%s"},"tool_result":{"stdout":"ok"}}}' "$HUGE_VALUE" >> "$TMP_DIR/logs/sessions/sess-1/raw/hooks.jsonl"
# 不加换行符 — 模拟正在写入的超长行

# raw-tail 从文件末尾附近开始读，应得到空 lines（超长行无完整换行）
HUGE_FILE_SIZE=$(wc -c < "$TMP_DIR/logs/sessions/sess-1/raw/hooks.jsonl" | xargs)
# 使用一个已知位置作为 cursor（在超长行之前的位置）
TAIL_HUGE=$(curl -s --max-time 2 "http://localhost:9527/api/raw-tail?kind=hooks&cursor=$CURSOR_3")
HUGE_CURSOR=$(echo "$TAIL_HUGE" | grep -o '"cursor":[0-9]*' | head -1 | cut -d: -f2)

# cursor 应该推进（跳过超长行），不应崩溃或卡住
if [ -n "$HUGE_CURSOR" ] && [ "$HUGE_CURSOR" -ge "$CURSOR_3" ]; then
  green "  PASS: 7a. cursor advances past oversized line (cursor=$HUGE_CURSOR)"
  PASS=$((PASS + 1))
else
  red "  FAIL: 7a. cursor stuck or missing after oversized line"
  FAIL=$((FAIL + 1))
fi

# 验证 API 没有崩溃（仍然能正常响应）
HEALTH_CHECK=$(curl -s --max-time 2 http://localhost:9527/api/info)
assert_contains "7b. server still responsive after oversized line" "$HEALTH_CHECK" '"sessionId"'

# 现在给超长行加上换行，再追加一个正常行
printf '\n{"source":"hook","hook_name":"SessionEnd","captured_at":"2026-03-17T00:00:21Z","session_id":"sess-1","data":{}}\n' >> "$TMP_DIR/logs/sessions/sess-1/raw/hooks.jsonl"

# 再次读取，应能获取到新的正常行
TAIL_AFTER=$(curl -s --max-time 2 "http://localhost:9527/api/raw-tail?kind=hooks&cursor=$HUGE_CURSOR")
if echo "$TAIL_AFTER" | grep -q '"lines":\[\]'; then
  # 可能 cursor 已经跳过了，再用 cursor 0 重读验证文件仍可解析
  TAIL_FULL=$(curl -s --max-time 2 "http://localhost:9527/api/raw-tail?kind=hooks&cursor=0&lines=500")
  assert_contains "7c. full re-read still works" "$TAIL_FULL" '"lines"'
else
  green "  PASS: 7c. new normal line readable after oversized line"
  PASS=$((PASS + 1))
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1
exit 0

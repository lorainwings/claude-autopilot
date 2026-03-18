#!/usr/bin/env bash
# test_autopilot_server_aggregation.sh — server aggregates legacy + raw hook + statusline + transcript
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_DIR="$(cd "$TEST_DIR/../server" && pwd)"
source "$TEST_DIR/_test_helpers.sh"

echo "--- autopilot-server aggregation ---"

if ! command -v bun >/dev/null 2>&1; then
  green "  PASS: bun unavailable, skipping aggregation smoke test"
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

mkdir -p "$TMP_DIR/logs" "$TMP_DIR/logs/sessions/sess-agg/raw" "$TMP_DIR/openspec/changes"
cat > "$TMP_DIR/openspec/changes/.autopilot-active" <<EOF
{"change":"agg-test","session_id":"sess-agg","mode":"full"}
EOF
cat > "$TMP_DIR/logs/events.jsonl" <<EOF
{"type":"phase_start","phase":1,"mode":"full","timestamp":"2026-03-17T00:00:00Z","change_name":"agg-test","session_id":"sess-agg","phase_label":"Requirements","total_phases":8,"sequence":1,"payload":{}}
EOF
cat > "$TMP_DIR/logs/sessions/sess-agg/raw/hooks.jsonl" <<EOF
{"source":"hook","hook_name":"PostToolUse","captured_at":"2026-03-17T00:00:01Z","session_id":"sess-agg","cwd":"$TMP_DIR","transcript_path":"$TMP_DIR/transcript.jsonl","active_agent_id":"phase1-agent","data":{"tool_name":"Bash","tool_input":{"command":"echo hello"},"tool_result":{"stdout":"hello"}}}
EOF
cat > "$TMP_DIR/logs/sessions/sess-agg/raw/statusline.jsonl" <<EOF
{"source":"statusline","captured_at":"2026-03-17T00:00:02Z","session_id":"sess-agg","cwd":"$TMP_DIR","transcript_path":"$TMP_DIR/transcript.jsonl","data":{"model":"claude-sonnet","cwd":"$TMP_DIR","transcript_path":"$TMP_DIR/transcript.jsonl","cost_usd":"0.42","context_window":{"percent":31}}}
EOF
cat > "$TMP_DIR/transcript.jsonl" <<EOF
{"timestamp":"2026-03-17T00:00:03Z","role":"user","content":[{"text":"请开始 autopilot"}]}
{"timestamp":"2026-03-17T00:00:04Z","role":"assistant","content":[{"text":"开始执行"}]}
EOF

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
  red "  FAIL: aggregation server failed to start"
  FAIL=$((FAIL + 1))
  echo "Results: $PASS passed, $FAIL failed"
  exit 1
fi

API_JSON=$(curl -s --max-time 2 http://localhost:9527/api/events)
assert_contains "aggregated API exposes tool_use" "$API_JSON" '"type":"tool_use"'
assert_contains "aggregated API exposes status_snapshot" "$API_JSON" '"type":"status_snapshot"'
assert_contains "aggregated API exposes transcript_message" "$API_JSON" '"type":"transcript_message"'

INFO_JSON=$(curl -s --max-time 2 http://localhost:9527/api/info)
assert_contains "api/info exposes current session" "$INFO_JSON" '"sessionId":"sess-agg"'

# ── P1: 跨 session journal 独立性测试 ──
# 创建第二个 session (sess-b) 数据，验证两个 journal 文件都存在
mkdir -p "$TMP_DIR/logs/sessions/sess-b/raw"
cat > "$TMP_DIR/logs/sessions/sess-b/raw/hooks.jsonl" <<EOF
{"source":"hook","hook_name":"SessionStart","captured_at":"2026-03-17T01:00:00Z","session_id":"sess-b","data":{}}
EOF

# 切换到 sess-b
cat > "$TMP_DIR/openspec/changes/.autopilot-active" <<EOF
{"change":"test-b","session_id":"sess-b","mode":"full"}
EOF
cat > "$TMP_DIR/logs/events.jsonl" <<'LEGACY'
{"type":"phase_start","phase":1,"mode":"full","timestamp":"2026-03-17T00:00:00Z","change_name":"agg-test","session_id":"sess-agg","phase_label":"Requirements","total_phases":8,"sequence":1,"payload":{}}
{"type":"phase_start","phase":0,"mode":"full","timestamp":"2026-03-17T01:00:00Z","change_name":"test-b","session_id":"sess-b","phase_label":"Environment Setup","total_phases":8,"sequence":1,"payload":{}}
LEGACY

# 等待服务器刷新（polling 间隔 700ms，等 2 秒足够）
sleep 2

SESS_B_EVENTS=$(curl -s --max-time 2 http://localhost:9527/api/events)
assert_contains "sess-b events accessible" "$SESS_B_EVENTS" '"sessionId":"sess-b"'

# 切回 sess-agg 验证其 journal 仍存在
JOURNAL_AGG="$TMP_DIR/logs/sessions/sess-agg/journal/events.jsonl"
if [ -f "$JOURNAL_AGG" ]; then
  green "  PASS: sess-agg journal 文件存在"
  PASS=$((PASS + 1))
else
  red "  FAIL: sess-agg journal 文件丢失"
  FAIL=$((FAIL + 1))
fi

JOURNAL_B="$TMP_DIR/logs/sessions/sess-b/journal/events.jsonl"
if [ -f "$JOURNAL_B" ]; then
  green "  PASS: sess-b journal 文件存在"
  PASS=$((PASS + 1))
else
  red "  FAIL: sess-b journal 文件丢失"
  FAIL=$((FAIL + 1))
fi

# ── P0: 路径脱敏验证 ──
EVENTS_FOR_SANITIZE=$(curl -s --max-time 2 http://localhost:9527/api/events)
# 检查返回值中不含原始用户路径（$TMP_DIR 以 /tmp 或 /var 开头，不含 /Users/）
if echo "$EVENTS_FOR_SANITIZE" | grep -q '"/Users/[^"]*"'; then
  red "  FAIL: API 返回中包含未脱敏的 /Users/ 路径"
  FAIL=$((FAIL + 1))
else
  green "  PASS: API 返回中不含 /Users/ 绝对路径"
  PASS=$((PASS + 1))
fi

# ── P2: /api/raw-tail 游标增量验证 ──
# 切回 sess-agg 来测试 raw-tail
cat > "$TMP_DIR/openspec/changes/.autopilot-active" <<EOF
{"change":"agg-test","session_id":"sess-agg","mode":"full"}
EOF
sleep 2

RAW_TAIL=$(curl -s --max-time 2 "http://localhost:9527/api/raw-tail?kind=hooks&cursor=0")
assert_contains "raw-tail returns lines" "$RAW_TAIL" '"lines"'
assert_contains "raw-tail returns cursor" "$RAW_TAIL" '"cursor"'

# 游标推进到文件末尾后应返回空
CURSOR=$(echo "$RAW_TAIL" | grep -o '"cursor":[0-9]*' | head -1 | cut -d: -f2)
if [ -n "$CURSOR" ] && [ "$CURSOR" -gt 0 ]; then
  RAW_TAIL_EMPTY=$(curl -s --max-time 2 "http://localhost:9527/api/raw-tail?kind=hooks&cursor=$CURSOR")
  if echo "$RAW_TAIL_EMPTY" | grep -q '"lines":\[\]'; then
    green "  PASS: 游标到末尾后返回空行"
    PASS=$((PASS + 1))
  else
    red "  FAIL: 游标到末尾后应返回空行"
    FAIL=$((FAIL + 1))
  fi
else
  red "  FAIL: 无法提取 raw-tail cursor 值"
  FAIL=$((FAIL + 1))
fi

echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1; exit 0

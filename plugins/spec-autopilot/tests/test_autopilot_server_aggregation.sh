#!/usr/bin/env bash
# test_autopilot_server_aggregation.sh — server aggregates legacy + raw hook + statusline + transcript
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../scripts" && pwd)"
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

bun run "$SCRIPT_DIR/autopilot-server.ts" --project-root "$TMP_DIR" --no-open >/dev/null 2>&1 &
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

echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1; exit 0

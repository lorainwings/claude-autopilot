#!/usr/bin/env bash
# test_raw_hook_capture.sh — raw hook bridge writes session-scoped records
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../scripts" && pwd)"
source "$TEST_DIR/_test_helpers.sh"

echo "--- raw hook capture ---"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$TMP_DIR/logs"
echo "phase5-impl" > "$TMP_DIR/logs/.active-agent-session-sess_1"

HOOK_JSON='{"session_id":"sess:1","cwd":"'"$TMP_DIR"'","transcript_path":"'"$TMP_DIR"'/transcript.jsonl","tool_name":"Bash","tool_input":{"command":"echo hello"},"tool_result":{"stdout":"hello"}}'
echo "$HOOK_JSON" | bash "$SCRIPT_DIR/capture-hook-event.sh" PostToolUse
EXIT_CODE=$?
assert_exit "raw hook capture exits 0" 0 "$EXIT_CODE"

RAW_FILE="$TMP_DIR/logs/sessions/sess_1/raw/hooks.jsonl"
META_FILE="$TMP_DIR/logs/sessions/sess_1/meta.json"
assert_file_exists "raw hooks.jsonl created" "$RAW_FILE"
assert_file_exists "session meta.json created" "$META_FILE"

RAW_CONTENT=$(cat "$RAW_FILE" 2>/dev/null || true)
assert_contains "raw hook stores hook_name" "$RAW_CONTENT" '"hook_name": "PostToolUse"'
assert_contains "raw hook stores transcript_path" "$RAW_CONTENT" '"transcript_path": "'"$TMP_DIR"'/transcript.jsonl"'
assert_contains "raw hook stores session-scoped active agent" "$RAW_CONTENT" '"active_agent_id": "phase5-impl"'

echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1; exit 0

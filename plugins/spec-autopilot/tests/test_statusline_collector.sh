#!/usr/bin/env bash
# test_statusline_collector.sh — statusline collector writes telemetry and prints concise status
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../scripts" && pwd)"
source "$TEST_DIR/_test_helpers.sh"

echo "--- statusline collector ---"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

STATUS_JSON='{"session_id":"sess-telemetry","cwd":"'"$TMP_DIR"'","model":"claude-sonnet","transcript_path":"'"$TMP_DIR"'/transcript.jsonl","cost_usd":"0.42","context_window":{"percent":31}}'
OUTPUT=$(echo "$STATUS_JSON" | AUTOPILOT_PROJECT_ROOT="$TMP_DIR" bash "$SCRIPT_DIR/statusline-collector.sh" 2>/dev/null)
EXIT_CODE=$?
assert_exit "statusline collector exits 0" 0 "$EXIT_CODE"
assert_contains "statusline stdout includes model" "$OUTPUT" 'claude-sonnet'
assert_contains "statusline stdout includes context" "$OUTPUT" 'ctx 31%'

RAW_FILE="$TMP_DIR/logs/sessions/sess-telemetry/raw/statusline.jsonl"
assert_file_exists "statusline raw file created" "$RAW_FILE"
RAW_CONTENT=$(cat "$RAW_FILE" 2>/dev/null || true)
assert_contains "statusline raw stores transcript path" "$RAW_CONTENT" '"transcript_path": "'"$TMP_DIR"'/transcript.jsonl"'

echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1; exit 0

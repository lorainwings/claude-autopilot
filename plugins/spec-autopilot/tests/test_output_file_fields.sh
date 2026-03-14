#!/usr/bin/env bash
# test_output_file_fields.sh — Section 48: output_file / new fields in envelope
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../scripts" && pwd)"
source "$TEST_DIR/_test_helpers.sh"
source "$TEST_DIR/_fixtures.sh"

echo "--- 48. output_file / new fields in envelope compatibility ---"
setup_autopilot_fixture

TMPDIR_48=$(mktemp -d)
mkdir -p "$TMPDIR_48/openspec/changes/test-v330/context/phase-results"
echo '{"change":"test-v330","mode":"full"}' > "$TMPDIR_48/openspec/changes/.autopilot-active"

# 48a. Envelope with output_file field → no block (output_file is ignored by validation)
OUT48a=$(echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:3 -->\nPhase 3"},"tool_response":"Done. {\"status\":\"ok\",\"summary\":\"Design complete\",\"output_file\":\"openspec/changes/test/context/design.md\",\"artifacts\":[]}","cwd":"'"$TMPDIR_48"'"}' \
  | bash "$SCRIPT_DIR/validate-json-envelope.sh" 2>/dev/null)
RC48a=$?
assert_exit "48a: envelope with output_file → exit 0" 0 "$RC48a"
assert_not_contains "48a: envelope with output_file → no block" "$OUT48a" "block"

# 48b. Envelope with decision_points field → no block (unknown fields are ignored)
OUT48b=$(echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:3 -->\nPhase 3"},"tool_response":"Done. {\"status\":\"ok\",\"summary\":\"Spec written\",\"decision_points\":[{\"id\":\"dp-1\",\"decision\":\"use REST\"}],\"artifacts\":[]}","cwd":"'"$TMPDIR_48"'"}' \
  | bash "$SCRIPT_DIR/validate-json-envelope.sh" 2>/dev/null)
RC48b=$?
assert_exit "48b: envelope with decision_points → exit 0" 0 "$RC48b"
assert_not_contains "48b: envelope with decision_points → no block" "$OUT48b" "block"

rm -rf "$TMPDIR_48"

teardown_autopilot_fixture
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1; exit 0

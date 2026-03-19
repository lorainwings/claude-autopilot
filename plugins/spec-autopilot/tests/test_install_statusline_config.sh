#!/usr/bin/env bash
# test_install_statusline_config.sh — installer should materialize statusLine config and bridge script
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/../runtime/scripts" && pwd)"
source "$TEST_DIR/_test_helpers.sh"

echo "--- install statusline config ---"

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT
git -C "$TMP_DIR" init >/dev/null 2>&1

OUTPUT=$(bash "$SCRIPT_DIR/install-statusline-config.sh" --scope local --project-root "$TMP_DIR" 2>/dev/null)
EXIT_CODE=$?
assert_exit "installer exits 0" 0 "$EXIT_CODE"
assert_contains "installer prints success" "$OUTPUT" "statusLine installed"

SETTINGS_FILE="$TMP_DIR/.claude/settings.local.json"
BRIDGE_FILE="$TMP_DIR/.claude/statusline-autopilot.sh"
EXCLUDE_FILE="$TMP_DIR/.git/info/exclude"

assert_file_exists "settings.local.json created" "$SETTINGS_FILE"
assert_file_exists "bridge script created" "$BRIDGE_FILE"
assert_file_exists "git exclude exists" "$EXCLUDE_FILE"

SETTINGS_CONTENT=$(cat "$SETTINGS_FILE" 2>/dev/null || true)
assert_contains "settings contain statusLine key" "$SETTINGS_CONTENT" '"statusLine"'
assert_contains "settings contain bridge command" "$SETTINGS_CONTENT" "$BRIDGE_FILE"

EXCLUDE_CONTENT=$(cat "$EXCLUDE_FILE" 2>/dev/null || true)
assert_contains "exclude ignores settings.local" "$EXCLUDE_CONTENT" '.claude/settings.local.json'
assert_contains "exclude ignores bridge script" "$EXCLUDE_CONTENT" '.claude/statusline-autopilot.sh'

echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1; exit 0

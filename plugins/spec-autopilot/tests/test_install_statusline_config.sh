#!/usr/bin/env bash
# test_install_statusline_config.sh — installer should materialize statusLine config (no bridge script)
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
EXCLUDE_FILE="$TMP_DIR/.git/info/exclude"

assert_file_exists "settings.local.json created" "$SETTINGS_FILE"

# Bridge script must NOT be created — command points directly to collector
BRIDGE_FILE="$TMP_DIR/.claude/statusline-autopilot.sh"
if [ -f "$BRIDGE_FILE" ]; then
  red "  FAIL: bridge script should not exist"
  FAIL=$((FAIL + 1))
else
  green "  PASS: no bridge script created"
  PASS=$((PASS + 1))
fi

SETTINGS_CONTENT=$(cat "$SETTINGS_FILE" 2>/dev/null || true)
assert_contains "settings contain statusLine key" "$SETTINGS_CONTENT" '"statusLine"'
assert_contains "settings contain collector command" "$SETTINGS_CONTENT" "statusline-collector.sh"
assert_contains "settings use CLAUDE_PLUGIN_ROOT env var" "$SETTINGS_CONTENT" 'CLAUDE_PLUGIN_ROOT'

assert_file_exists "git exclude exists" "$EXCLUDE_FILE"
EXCLUDE_CONTENT=$(cat "$EXCLUDE_FILE" 2>/dev/null || true)
assert_contains "exclude ignores settings.local" "$EXCLUDE_CONTENT" '.claude/settings.local.json'
# Bridge script entry should NOT be in exclude (no bridge file)
if echo "$EXCLUDE_CONTENT" | grep -qF 'statusline-autopilot.sh'; then
  red "  FAIL: exclude still references bridge script"
  FAIL=$((FAIL + 1))
else
  green "  PASS: exclude does not reference bridge script"
  PASS=$((PASS + 1))
fi

echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1; exit 0
